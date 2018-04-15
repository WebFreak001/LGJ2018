module systems.display;

import avocado.core;
import avocado.gl3;
import avocado.sdl2;
import avocado.input;

import audioengine;
import config;
import components;
import systems.movement;
import text;

import std.algorithm;
import std.stdio;

final class DisplaySystem : ISystem
{
private:
	Renderer renderer;
	View view;
	float time = 0;

	GLTexture white, judgementCircle;
	GLTexture redCircle, blueCircle;
	GLTexture redClick, blueClick;

	Font font;
	Text scoreText;
	GL3ShaderProgram textShader;

public:
	this(View view, Renderer renderer, GLTexture judgementCircle, GLTexture redCircle,
			GLTexture blueCircle, GLTexture redClick, GLTexture blueClick, Font font,
			GL3ShaderProgram textShader)
	{
		this.renderer = renderer;
		this.view = view;
		renderer.projection.top = perspective(view.width, view.height, 90.0f, 0.01f, 100.0f);
		white = new GLTexture();
		white.create(1, 1, cast(ubyte[])[255, 255, 255, 255]);
		this.judgementCircle = judgementCircle;
		this.redCircle = redCircle;
		this.blueCircle = blueCircle;
		this.redClick = redClick;
		this.blueClick = blueClick;
		this.font = font;
		this.textShader = textShader;
		scoreText = new Text(font, textShader, 16);
	}

	/// Draws the entities
	final void update(World world)
	{
		int rendered;
		time += world.delta;
		renderer.begin(view);
		renderer.clearColor = vec4(0x49 / 255.0f, 0x8c / 255.0f, 0xb3 / 255.0f, 1);
		renderer.clear();

		auto projectionView = renderer.projection.top * renderer.view.top;

		foreach (entity; world.entities)
		{
			if (entity.alive)
			{
				PositionComponent* position;
				MeshComponent mesh;
				AnimatedMeshComponent* animatedMesh;
				LockCamera lock;
				Cyclic cyclic;
				JumpPhysics* phys;
				if (entity.fetch(position))
				{
					if (entity.fetch(lock))
					{
						lock.value.position = position.position;
						lock.value.position.y = 0;
					}
					if (entity.fetch(cyclic))
					{
						if (position.position.x < cyclic.min)
							position.position.x += cyclic.max - cyclic.min;
						else if (position.position.x > cyclic.max)
							position.position.x += cyclic.min - cyclic.max;
					}
					if (entity.fetch(phys))
					{
						float nrm = (phys.jumpAnimation - 0.5f) * 2;
						auto jumpHeight = phys.height * 0.5;
						position.position.y = -(nrm * nrm) * jumpHeight + jumpHeight;
					}

					renderer.model.push();
					renderer.model.top *= mat4.translation(
							position.position + position.offset) * position.rotation.to_matrix!(4, 4);
					AABBCull cull;
					bool draw = true;
					bool hasCull;
					if ((hasCull = entity.fetch(cull)) != false)
					{
						if (!isInsideFrustum(projectionView * renderer.model.top, cull.min, cull.max))
							draw = false;
					}
					if (draw)
					{
						if (entity.fetch(mesh))
						{
							mesh.tex.bind(renderer, 0);
							renderer.bind(mesh.shader);
							mesh.shader.set("model", renderer.model.top);
							renderer.drawMesh(mesh.mesh);
							rendered++;
						}
						if (entity.fetch(animatedMesh))
						{
							renderer.model.push();
							renderer.model.top *= animatedMesh.offset;
							animatedMesh.tick(world.delta);
							animatedMesh.tex.bind(renderer, 0);
							renderer.bind(animatedMesh.shader);
							animatedMesh.shader.set("model", renderer.model.top);
							animatedMesh.shader.set("bones", animatedMesh.mesh.bones);
							renderer.drawMesh(animatedMesh.mesh.base);
							rendered++;
							renderer.model.pop();
						}
						ContainerStack containers;
						if (entity.fetch(containers))
						{
							containers.tex.bind(renderer, 0);
							for (int i = 0; i < containers.height; i++)
							{
								renderer.model.top[1][3] -= 2.44;
								if (!hasCull || isInsideFrustum(projectionView * renderer.model.top,
										containers.cullMin, containers.cullMax))
								{
									renderer.bind(containers.shader);
									containers.shader.set("model", renderer.model.top);
									renderer.drawMesh(containers.mesh);
									rendered++;
								}
							}
						}
					}
					renderer.model.pop();
				}
			}
		}

		renderer.bind2D();
		renderer.drawRectangle(white, vec4(0, view.height - 123, view.width, 123));
		foreach_reverse (entity; world.entities)
		{
			if (entity.alive)
			{
				{
					HitCircleComponent* hitCircle;
					if (entity.fetch(hitCircle))
					{
						auto offset = hitCircle.info.time - audio.currentTime.total!"msecs";
						auto x = 115 + offset * 0.5;
						if (x >= -200 && x <= view.width + 200)
						{
							vec4 rect;
							if (hitCircle.info.taikoIsBig)
								rect = vec4(x - 60, view.height - 120, 120, 120);
							else
								rect = vec4(x - 40, view.height - 120 + 20, 80, 80);
							float yDisplayOffset = 0;
							vec4 color = vec4(1);
							if (hitCircle.judgement == Judgement.hit)
							{
								if (offset < 0)
								{
									offset += 100;
									yDisplayOffset = (offset * offset) * 0.01 - 100;
								}
							}
							else if (hitCircle.judgement == Judgement.miss)
							{
								if (offset < 0)
								{
									color = vec4(1, 1, 1, (10 + offset) * 0.1);
								}
							}
							rect.y += yDisplayOffset;
							if (color.a > 0)
								renderer.drawRectangle(hitCircle.info.taikoIsBlue ? blueCircle
										: redCircle, rect, color);
						}
					}
				}
			}
		}
		renderer.drawRectangle(judgementCircle, vec4(0, -0.1, 1, 1.2), vec4(0,
				view.height - 120, 200, 120), vec4(1));
		renderer.drawFadedAnimation(redClick, vec4(15, view.height - 160, 200, 200),
				redClickAnimation, world.delta);
		renderer.drawFadedAnimation(blueClick, vec4(15, view.height - 160, 200,
				200), blueClickAnimation, world.delta);
		scoreAnimation += world.delta;
		if (scoreAnimation < 0.2)
		{
			auto newText = scoreAmount.textForAmount;
			scoreText.text = newText;
			renderer.model.push(mat4.identity);
			renderer.model.top *= mat4.translation(40,
					view.height - 60 - scoreAnimation * 50, 0) * mat4.scaling(768, 512, 1);
			float a = 1 - (scoreAnimation * 5) ^^ 3;
			scoreText.draw(renderer, scoreAmount == 0 ? vec4(1, 0, 0, a) : vec4(0.2, 0.8, 0.3, a));
			renderer.model.pop();
		}

		{
			scoreChars[$ - 1] = '0' + (totalScore % 10);
			scoreChars[$ - 2] = '0' + ((totalScore / 10) % 10);
			scoreChars[$ - 3] = '0' + ((totalScore / 100) % 10);
			scoreChars[$ - 4] = ',';
			scoreChars[$ - 5] = '0' + ((totalScore / 1000) % 10);
			scoreChars[$ - 6] = '0' + ((totalScore / 10000) % 10);
			scoreChars[$ - 7] = '0' + ((totalScore / 100000) % 10);
			scoreChars[$ - 8] = ',';
			scoreChars[$ - 9] = '0' + ((totalScore / 1000000) % 10);
			scoreChars[$ - 10] = '0' + ((totalScore / 10000000) % 10);
			scoreChars[$ - 11] = '0' + ((totalScore / 100000000) % 10);
			scoreText.text = cast(dstring) scoreChars[];
			renderer.model.push(mat4.identity);
			renderer.model.top *= mat4.translation(view.width - scoreText.textWidth * 768 - 10,
					40, 0) * mat4.scaling(768, 512, 1);
			scoreText.draw(renderer, vec4(1));
			renderer.model.pop();
		}

		renderer.bind3D();
		renderer.end(view);
	}
}

dchar[11] scoreChars;

dstring textForAmount(int amount)
{
	switch (amount)
	{
	case 600:
		return "600";
	case 300:
		return "300";
	case 200:
		return "200";
	case 100:
		return "100";
	case 50:
		return "50";
	case 0:
		return "MISS";
	default:
		return "???";
	}
}

void drawFadedAnimation(ref Renderer renderer, GLTexture texture, vec4 rect,
		ref double time, double delta)
{
	time += delta;
	if (time < 0.3)
		renderer.drawRectangle(texture, rect, vec4(1, 1, 1, 1 - (time / 0.3)));
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
