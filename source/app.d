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

/// The entrypoint of the program
int main(string[] args)
{
	Engine engine = new Engine();
	with (engine)
	{
		auto window = new View("Example");
		auto renderer = new Renderer;
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
		world.addSystem!MovementSystem(&playerCam);
		world.addSystem!CameraSystem(window, renderer, &playerCam);
		world.addSystem!DisplaySystem(window, renderer);

		window.onResized ~= (w, h) {
			renderer.resize(w, h);
			renderer.projection.top = perspective(w, h, 90.0f, 0.01f, 100.0f);
		};

		auto resources = new ResourceManager();
		resources.prepend("res");
		resources.prependAll("packs", "*.{pack,zip}");

		auto songs = resources.listResources("Songs");
		immutable(ubyte)[] songMP3;
		SongSelect: foreach (song; songs)
		{
			if (song.extension == ".osz")
			{
				auto archive = new ZipArchive(resources.readFile(song).dup);
				foreach (file; archive.files)
				{
					if (file.path.extension != ".osu")
						continue;
					auto song = parseOsu(cast(string) file.data);
					if (song.general.mode != Osu.Mode.taiko)
						continue;
					selectedSong = song;
					songMP3 = archive.getFile(song.general.audioFilename).data;
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

		int startContainers = -8, endContainers = 60;
		int yContainers = 10;

		{
			auto container = resources.load!Scene("models/container/container.obj")
				.value.meshes[0].toGLMesh;
			auto texSpecial = resources.load!GLTexture("models/container/container2.png");
			auto tex = resources.load!GLTexture("models/container/container.png");

			for (int x = startContainers; x <= endContainers; x++)
				for (int y = 0; y <= yContainers; y++)
					mixin(createEntity!("Container", q{
						PositionComponent: vec3(x * 2.44 * 3, -(y + 1) * 2.44, 0)
						Cyclic: startContainers * 2.44 * 3, (endContainers + 1) * 2.44 * 3, 2.44 * 3
						MeshComponent: uniform(0, 10) == 0 ? texSpecial : tex, shader, container
						AABBCull: vec3(-1.22, 0, -3.03), vec3(1.22, 2.44, 3.03)
					}));
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

		start();
		while (update)
			limiter.wait();
		stop();
	}
	return 0;
}
