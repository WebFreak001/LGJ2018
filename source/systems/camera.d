module systems.camera;

import avocado.core;
import avocado.input;

import config;
import components;

final class CameraSystem : ISystem
{
private:
	Renderer renderer;
	View view;

	Camera* currentCamera;

public:
	this(View view, Renderer renderer, Camera* currentCamera)
	{
		this.renderer = renderer;
		this.view = view;
		this.currentCamera = currentCamera;
	}

	/// Outputs the delta and every
	final void update(World world)
	{
		if (currentCamera)
		{
			if (!currentCamera.lockPosition)
			{
				float sinx = sin(currentCamera.yaw);
				float cosx = cos(currentCamera.yaw);
				if (Keyboard.state.isKeyPressed(currentCamera.movement[0]))
					currentCamera.position += vec3(-sinx, 0, -cosx) * world.delta * 10;
				if (Keyboard.state.isKeyPressed(currentCamera.movement[1]))
					currentCamera.position += vec3(sinx, 0, cosx) * world.delta * 10;
				if (Keyboard.state.isKeyPressed(currentCamera.movement[2]))
					currentCamera.position += vec3(-cosx, 0, sinx) * world.delta * 10;
				if (Keyboard.state.isKeyPressed(currentCamera.movement[3]))
					currentCamera.position += vec3(cosx, 0, -sinx) * world.delta * 10;
			}
			if (!currentCamera.lockRotation)
			{
				currentCamera.yaw -= Mouse.state.offX * 0.005;
				currentCamera.pitch = clamp(currentCamera.pitch - Mouse.state.offY * 0.005,
						-1.5707f, 1.5707f);
				Mouse.state.resetOffset();
				import std.stdio; writeln(*currentCamera);
			}
			renderer.view.top = mat4.translation(-currentCamera.offset) * mat4.yrotation(
					-currentCamera.yaw).rotatex(-currentCamera.pitch) * mat4.translation(
					-currentCamera.position - currentCamera.absoluteOffset);
			renderer.projection.top = perspective(view.width, view.height,
					currentCamera.fov, 0.01f, 100.0f);
		}
	}
}
