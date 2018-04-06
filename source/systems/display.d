module systems.display;

import avocado.core;
import avocado.sdl2;
import avocado.input;

import config;
import components;

import std.algorithm;

final class DisplaySystem : ISystem
{
private:
	Renderer renderer;
	View view;
	float time = 0;

public:
	this(View view, Renderer renderer)
	{
		this.renderer = renderer;
		this.view = view;
		renderer.projection.top = perspective(view.width, view.height, 90.0f, 0.01f, 100.0f);
	}

	/// Draws the entities
	final void update(World world)
	{
		int rendered;
		time += world.delta;
		renderer.begin(view);
		renderer.clear();
		foreach (entity; world.entities)
		{
			if (entity.alive)
			{
				PositionComponent* position;
				MeshComponent mesh;
				LockCamera lock;
				Cyclic cyclic;
				JumpPhysics* phys;
				if (entity.fetch(position))
				{
					if (entity.fetch(mesh))
					{
						renderer.model.push();
						renderer.model.top *= mat4.translation(
								position.position + position.offset) * position.rotation.to_matrix!(4, 4);
						AABBCull cull;
						bool draw = true;
						if (entity.fetch(cull))
						{
							if (!isInsideFrustum(renderer.projection.top * renderer.view.top * renderer.model.top,
									cull.min, cull.max))
								draw = false;
						}
						if (draw)
						{
							mesh.tex.bind(renderer, 0);
							renderer.bind(mesh.shader);
							mesh.shader.set("model", renderer.model.top);
							renderer.drawMesh(mesh.mesh);
							rendered++;
						}
						renderer.model.pop();
					}
					if (entity.fetch(lock))
					{
						lock.value.position = position.position;
					}
					if (entity.fetch(cyclic))
					{
						position.position.x += 5 * world.delta;
						if (position.position.x < cyclic.min)
							position.position.x += cyclic.max - cyclic.min;
						else if (position.position.x > cyclic.max)
							position.position.x += cyclic.min - cyclic.max;
					}
					if (entity.fetch(phys))
					{
					}
				}
			}
		}

		import std.stdio;

		writeln("Drawn ", rendered);

		renderer.bind2D();
		foreach (entity; world.entities)
		{
			if (entity.alive)
			{
				{
					RectangleComponent rect;
					if (entity.fetch(rect))
					{
						renderer.drawRectangle(rect.tex, rect.rect);
					}
				}
				{
					SolidComponent rect;
					if (entity.fetch(rect))
					{
						renderer.fillRectangle(rect.rect, rect.color);
					}
				}
				{
					ControlComponent control;
					if (entity.fetch(control))
					{
						control.control.draw(renderer);
					}
				}
			}
		}
		renderer.bind3D();
		renderer.end(view);
	}
}

bool isInsideFrustum(mat4 mvp, vec3 min, vec3 max)
{
	//dfmt off
	vec4[8] points = [
		mvp * vec4(min.x, min.y, min.z, 1),
		mvp * vec4(min.x, min.y, max.z, 1),
		mvp * vec4(min.x, max.y, min.z, 1),
		mvp * vec4(min.x, max.y, max.z, 1),
		mvp * vec4(max.x, min.y, min.z, 1),
		mvp * vec4(max.x, min.y, max.z, 1),
		mvp * vec4(max.x, max.y, min.z, 1),
		mvp * vec4(max.x, max.y, max.z, 1),
	];
	//dfmt on

	int[6] c;
	foreach (point; points)
	{
		if (point.x < -point.w)
			c[0]++;
		if (point.x > point.w)
			c[1]++;
		if (point.y < -point.w)
			c[2]++;
		if (point.y > point.w)
			c[3]++;
		if (point.z < -point.w)
			c[4]++;
		if (point.z > point.w)
			c[5]++;
	}
	if (c[].any!"a == 8")
		return false;
	return true;
}
