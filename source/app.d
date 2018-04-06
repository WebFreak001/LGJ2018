import std.stdio;

import avocado.core;
import avocado.dfs;
import avocado.sdl2;
import avocado.gl3;
import avocado.assimp;

import fs = std.file;
import std.path;
import std.format;
import std.random;

import config;
import components;
import systems.camera;
import systems.display;

/// The entrypoint of the program
int main(string[] args)
{
	Engine engine = new Engine();
	with (engine)
	{
		auto window = new View("Example");
		window.grabMouse();
		scope (exit)
			window.ungrabMouse();
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
		world.addSystem!CameraSystem(window, renderer, &playerCam);
		world.addSystem!DisplaySystem(window, renderer);

		window.onResized ~= (w, h) {
			renderer.resize(w, h);
			renderer.projection.top = perspective(w, h, 90.0f, 0.01f, 100.0f);
		};

		auto resources = new ResourceManager();
		resources.prepend("res");
		resources.prependAll("packs", "*.{pack,zip}");

		writeln(resources.listResources("texture", true));

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
			auto texSpecial = resources.load!GLTexture("models/container/container_satania.png");
			auto tex = resources.load!GLTexture("models/container/container.png");

			for (int x = startContainers; x <= endContainers; x++)
				for (int y = 0; y <= yContainers; y++)
					mixin(createEntity!("Container", q{
						PositionComponent: vec3(x * 2.44 * 3, -(y + 1) * 2.44, 0)
						Cyclic: startContainers * 2.44 * 3, (endContainers + 1) * 2.44 * 3
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

		start();
		while (update)
			limiter.wait();
		stop();
	}
	return 0;
}
