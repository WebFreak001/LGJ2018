import std.stdio;

import archive.zip;

import avocado.assimp;
import avocado.bmfont;
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
import systems.menu;
import waved;
import text;

/// The entrypoint of the program
int main(string[] args)
{
	Engine engine = new Engine();
	with (engine)
	{
		auto window = new View("D-Man Taiko Name Placeholder");
		auto renderer = new Renderer; //(GLGUIArguments(true, 800, 480, true));
		auto world = add(window, renderer);

		SDL_EventState(SDL_DROPFILE, SDL_ENABLE);

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

		auto textureFrag = new GLShaderUnit(ShaderType.Fragment, import("texture.frag"));

		auto shader = new GL3ShaderProgram();
		shader.attach(textureFrag).attach(new GLShaderUnit(ShaderType.Vertex, import("default.vert")));
		shader.create(renderer);
		shader.register(["modelview", "projection", "model", "tex"]);
		shader.set("tex", 0);

		auto animatedShader = new GL3ShaderProgram();
		animatedShader.attach(textureFrag)
			.attach(new GLShaderUnit(ShaderType.Vertex, import("bone.vert")));
		animatedShader.create(renderer);
		animatedShader.register(["modelview", "projection", "model", "tex", "bones"]);
		animatedShader.set("tex", 0);

		auto textShader = new GL3ShaderProgram();
		textShader.attach(new GLShaderUnit(ShaderType.Fragment, import("text.frag")))
			.attach(new GLShaderUnit(ShaderType.Vertex, import("text.vert")));
		textShader.create(renderer);
		textShader.register(["modelview", "projection", "color", "tex"]);
		textShader.set("tex", 0);

		{
			auto scene = resources.load!Scene("models/dman/dman.fbx").value;
			auto dman = scene.meshes[0].toAnimatedGLMesh(scene.animations[0]);
			auto tex = resources.load!GLTexture("models/dman/dman.png");
			mixin(createEntity!("Player", q{
				PositionComponent: vec3(0, 0, 0), quat.yrotation(cradians!90)
				AnimatedMeshComponent: tex, animatedShader, dman
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

				audio.musicVolume = 0.7;
				audio.masterVolume = 1;

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
		auto redCircle = resources.load!GLTexture("ui/circle_red.png").clampingTexture;
		auto blueCircle = resources.load!GLTexture("ui/circle_blue.png").clampingTexture;
		auto redClick = resources.load!GLTexture("ui/click_red.png").clampingTexture;
		auto blueClick = resources.load!GLTexture("ui/click_blue.png").clampingTexture;
		Font font = resources.load!Font("fonts/roboto.fnt", resources, "fonts/");
		world.addSystem!DisplaySystem(window, renderer, judgementCircle,
				redCircle, blueCircle, redClick, blueClick, font, textShader);

		window.onKeyboard ~= &movement.onKeyboard;

		spawnMenu(world, window, renderer, font, textShader, shader, resources);

		start();
		while (update)
			limiter.wait();
		stop();
	}
	return 0;
}

void spawnMenu(World world, View view, Renderer renderer, Font font,
		GL3ShaderProgram textShader, GL3ShaderProgram shader, ResourceManager resources)
{
	auto systems = world.systems;
	world.systems = [];
	world.addSystem!MainMenuScene(view, renderer, world, systems, font,
			textShader, shader, resources);
}

GLTexture clampingTexture(GLTexture tex)
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
