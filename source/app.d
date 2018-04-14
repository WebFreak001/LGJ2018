import std.stdio;

import archive.zip;

import avocado.assimp;
import avocado.core;
import avocado.dfs;
import avocado.gl3;
import avocado.sdl2;

import core.thread;

import fs = std.file;
import std.algorithm;
import std.format;
import std.math;
import std.path;
import std.random;
import std.string;

import audioengine;
import components;
import config;
import osu;
import systems.camera;
import systems.display;
import systems.movement;
import waved;

/// The entrypoint of the program
int main(string[] args)
{
	Engine engine = new Engine();
	with (engine)
	{
		auto window = new View("D-Man Taiko Name Placeholder");
		auto renderer = new Renderer; //(GLGUIArguments(true, 800, 480, true));
		auto world = add(window, renderer);

		//dfmt off
		Camera playerCam = {
			lockPosition: true,
			lockRotation: true,
			absoluteOffset: vec3(0, 1, 2),
			offset: vec3(0, 0, 4),
			yaw: -0.38,
			pitch: -0.135,
			movement: [
				Key.W, Key.S, Key.A, Key.D
			]
		};
		//dfmt on

		FPSLimiter limiter = new FPSLimiter(240);

		window.onResized ~= (w, h) {
			renderer.resize(w, h);
			renderer.projection.top = perspective(w, h, 90.0f, 0.01f, 100.0f);
		};

		auto resources = new ResourceManager();
		resources.prepend("res");
		resources.prependAll("packs", "*.{pack,zip}");

		auto songs = resources.listResources("Songs", false, false);
		immutable(ubyte)[] songMP3;
		SongSelect: foreach (song; songs.randomCover)
		{
			import std.file : isDir, dirEntries, readText, read, SpanMode, exists;

			if (song.extension == ".osz")
			{
				auto archive = new ZipArchive(resources.readFile(song).dup);
				foreach (file; archive.files)
				{
					if (file.path.extension != ".osu")
						continue;
					auto osu = parseOsu(cast(string) file.data);
					if (osu.general.mode != Osu.Mode.taiko)
						continue;
					selectedSong = osu;
					songMP3 = archive.getFile(osu.general.audioFilename).data;
					break SongSelect;
				}
			}
			else if (exists(chainPath("res", song)) && isDir(chainPath("res", song)))
			{
				foreach (file; dirEntries(buildPath("res", song), SpanMode.shallow))
				{
					if (file.extension != ".osu")
						continue;
					auto osu = parseOsu(readText(file));
					if (osu.general.mode != Osu.Mode.taiko)
						continue;
					selectedSong = osu;
					songMP3 = cast(immutable(ubyte)[]) read(buildPath(file.dirName,
							osu.general.audioFilename));
					break SongSelect;
				}
			}
		}

		if (selectedSong == Osu.init || !songMP3.length)
			throw new Exception(
					"No songs found (Place some osz files or folders with osu files in res/Songs)");
		else
			writeln("Playing ", selectedSong.metadata.artistUnicode, " - ", selectedSong.metadata.titleUnicode, " [",
					selectedSong.metadata.version_, "] mapped by ", selectedSong.metadata.creator);

		auto shader = new GL3ShaderProgram();
		shader.attach(new GLShaderUnit(ShaderType.Fragment, import("texture.frag")))
			.attach(new GLShaderUnit(ShaderType.Vertex, import("default.vert")));
		shader.create(renderer);
		shader.register(["modelview", "projection", "model", "tex"]);
		shader.set("tex", 0);

		int yContainers = 10;

		{
			auto container = resources.load!Scene("models/container/container.obj")
				.value.meshes[0].toGLMesh;
			auto texSpecial = resources.load!GLTexture("models/container/container2.png");
			auto tex = resources.load!GLTexture("models/container/container.png");
			auto texRed = resources.load!GLTexture("models/container/container_red.png");

			float x = 0;
			for (int i = 0; i < selectedSong.hitObjects.objects.length; i++)
			{
				double spacing = 3;
				if (i - 1 >= 0)
				{
					auto delta = selectedSong.hitObjects.objects[i].time
						- selectedSong.hitObjects.objects[i - 1].time;
					if (delta < 100)
						spacing = 1.5;
					else if (delta < 250)
						spacing = 2;
				}
				selectedSong.hitObjects.objects[i].spacing = spacing;
				x += 2.44 * spacing;
				mixin(createEntity!("ContainerStack", q{
					PositionComponent: vec3(x, 0, 0)
					ContainerStack: selectedSong.hitObjects.objects[i].taikoIsBlue ? (uniform(0, 10) == 0 ? texSpecial : tex) : texRed, shader, container, yContainers, vec3(-1.22, 0, -3.03), vec3(1.22, 2.44, 3.03)
					AABBCull: vec3(-1.22, -2.44 * yContainers, -3.03), vec3(1.22, 0, 3.03)
					HitCircleComponent: i, selectedSong.hitObjects.objects[i]
				}));
			}
		}

		{
			auto scene = resources.load!Scene("models/dman/dman.fbx").value;
			foreach (i, ref mesh; scene.meshes)
				writeln(i, ": ", mesh.name);
			auto dman = scene.meshes[0].toGLMesh;
			auto tex = resources.load!GLTexture("models/dman/dman.png");
			writeln(dman);
			mixin(createEntity!("Player", q{
				PositionComponent: vec3(0, 0, 0), quat.xrotation(-cradians!90)
				MeshComponent: tex, shader, dman
				LockCamera: &playerCam
				JumpPhysics:
			}));
		}

		renderer.setupDepthTest(DepthFunc.Less);

		bool running = true;
		scope (exit)
			running = false;
		auto audioThread = new Thread({
			try
			{
				audio.load();

				audio.musicVolume = 0.5;
				audio.masterVolume = 0;

				try
				{
					audio.play(songMP3);
				}
				catch (Exception e)
				{
					stderr.writeln("Failed to play audio: ", e);
				}

				while (running)
				{
					audio.tick();
					Thread.sleep(1.msecs);
				}
			}
			catch (Error e)
			{
				writeln("Audio thread has crashed: ", e);
			}
		});
		audioThread.start();

		auto clap = resources.readFile("sounds/drum-hitclap.wav").soundFromWav;
		auto normal = resources.readFile("sounds/drum-hitnormal.wav").soundFromWav;

		auto movement = world.addSystem!MovementSystem(&playerCam, normal, clap,
				Key.D, Key.F, Key.J, Key.K);
		world.addSystem!CameraSystem(window, renderer, &playerCam);

		// everything shit code
		auto judgementCircle = resources.load!GLTexture("ui/judgement_circle.png");
		judgementCircle.wrapY = TextureClampMode.ClampToEdge;
		judgementCircle.applyParameters();
		auto redCircle = resources.load!GLTexture("ui/circle_red.png").circleTexture;
		auto blueCircle = resources.load!GLTexture("ui/circle_blue.png").circleTexture;
		world.addSystem!DisplaySystem(window, renderer, judgementCircle, redCircle, blueCircle);

		window.onKeyboard ~= &movement.onKeyboard;

		start();
		while (update)
			limiter.wait();
		stop();
	}
	return 0;
}

GLTexture circleTexture(GLTexture tex)
{
	tex.wrapX = TextureClampMode.ClampToEdge;
	tex.wrapY = TextureClampMode.ClampToEdge;
	tex.applyParameters();
	return tex;
}

SoundEffect soundFromWav(in ubyte[] data, float volume = 1)
{
	SoundEffect ret;
	ret.volume = volume;
	Sound sound = decodeWAV(data).makeMono;
	ret.data.length = sound.samples.length;
	foreach (i, ref sample; ret.data)
		sample = cast(short)(sound.samples[i] * short.max);
	return ret;
}
