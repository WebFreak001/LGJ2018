module systems.menu;

import avocado.assimp;
import avocado.core;
import avocado.dfs;
import avocado.gl3;
import avocado.sdl2;
import avocado.input;

import audioengine;
import config;
import components;
import systems.display;
import systems.movement;
import text;
import archive.zip;

import std.algorithm;
import fs = std.file;
import std.stdio;
import std.path;
import std.random;

import osu;

final class MainMenuScene : ISystem
{
private:
	Renderer renderer;
	View view;
	World world;
	ISystem[] systems;
	Entity[] clearEntities;
	ResourceManager resources;

	Text text;
	Font font;
	GL3ShaderProgram textShader;
	GL3ShaderProgram shader;

public:
	this(View view, Renderer renderer, World world, ISystem[] systems, Font font,
			GL3ShaderProgram textShader, GL3ShaderProgram shader, ResourceManager resources)
	{
		this.view = view;
		this.renderer = renderer;
		this.world = world;
		this.systems = systems;
		this.font = font;
		this.textShader = textShader;
		this.shader = shader;
		this.text = new Text(font, textShader, 32);
		this.resources = resources;

		view.onDrop ~= &onDrop;
	}

	void onDrop(DropEvent event)
	{
		if (event.file.extension != ".osz")
			return;

		if (!clearEntities.length)
			clearEntities = world.entities.dup;
		else
			world.entities = clearEntities.dup;

		foreach (system; systems)
			if (cast(MovementSystem) system)
				(cast(MovementSystem) system).reset();

		auto archive = new ZipArchive(fs.read(event.file));

		selectedSong = Osu.init;
		immutable(ubyte)[] songMP3;

		ZipArchive.File[] files;
		foreach (file; archive.files)
			files ~= file;

		foreach (file; files.randomCover)
		{
			if (file.path.extension != ".osu")
				continue;
			auto osu = parseOsu(cast(string) file.data);
			if (osu.general.mode != Osu.Mode.taiko)
				continue;
			selectedSong = osu;
			songMP3 = archive.getFile(osu.general.audioFilename).data;
			break;
		}

		if (selectedSong == Osu.init || !songMP3.length)
		{
			writeln("No suitable map found, try one with a taiko difficulty.");
			return;
		}

		writeln("Playing ", selectedSong.metadata.artistUnicode, " - ", selectedSong.metadata.titleUnicode, " [",
				selectedSong.metadata.version_, "] mapped by ", selectedSong.metadata.creator);

		audio.stop(false);

		world.systems = systems;

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

		try
		{
			audio.play(songMP3);
			audio.audioReadIndex = -audio.audioSampleRate * 3;
		}
		catch (Exception e)
		{
			stderr.writeln("Failed to play audio: ", e);
		}
	}

	/// Draws the entities
	final void update(World world)
	{
		renderer.begin(view);
		renderer.clearColor = vec4(0, 0, 0, 1);
		renderer.clear();
		renderer.bind2D();

		text.text = "Drop .osz file here";
		renderer.model.push(mat4.identity);
		renderer.model.top *= mat4.translation((view.width - text.textWidth * 768) / 2,
				view.height / 2, 0) * mat4.scaling(768, 512, 1);
		text.draw(renderer, vec4(1));
		renderer.model.pop();

		text.text = "Play with D/F and J/K";
		renderer.model.push(mat4.identity);
		renderer.model.top *= mat4.translation((view.width - text.textWidth * 768) / 2,
				view.height / 2 + 50, 0) * mat4.scaling(768, 512, 1);
		text.draw(renderer, vec4(0.5));
		renderer.model.pop();

		renderer.bind3D();
		renderer.end(view);
	}
}
