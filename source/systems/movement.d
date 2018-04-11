module systems.movement;

import avocado.core;
import avocado.sdl2;
import avocado.input;

import config;
import components;

import std.algorithm;
import std.stdio;

import audioengine;
import osu;

Osu selectedSong;

final class MovementSystem : ISystem
{
private:
	int index;
	int msToNextObject;
	int transitionMs;
	float transitionOffset = 0;
	Camera* camera;

public:
	this(Camera* cam)
	{
		this.camera = cam;
	}

	/// Draws the entities
	final void update(World world)
	{
		auto prevOffset = transitionOffset;
		bool reset;

		if (index < selectedSong.hitObjects.objects.length
				&& audio.currentTime.total!"msecs" > selectedSong.hitObjects.objects[index].time)
		{
			auto object = selectedSong.hitObjects.objects[index];
			auto nextStart = selectedSong.hitObjects.objects[(index + 1) % $].time;

			if (nextStart < object.time)
				msToNextObject = 100;
			else
				msToNextObject = nextStart - object.time;

			transitionMs = 0;
			reset = true;
			if (object.taikoIsBig)
				writeln(object.taikoIsBlue ? "A" : "B");
			else
				writeln(object.taikoIsBlue ? "a" : "b");
			index++;
		}
		if (index == selectedSong.hitObjects.objects.length)
		{
			index = 0;
			audio.reset();
		}

		transitionMs += cast(int)(world.delta * 1000 * audio.effectiveSpeed);

		if (transitionMs < msToNextObject)
		{
			if (msToNextObject > 300)
				transitionOffset = transitionMs / 300.0f;
			else
				transitionOffset = transitionMs / cast(float)(msToNextObject - 10);

			if (transitionOffset > 1)
				transitionOffset = 1;
		}
		else
			transitionOffset = 1;

		float movement = prevOffset - transitionOffset;
		if (movement > 0)
			movement--;

		foreach (entity; world.entities)
		{
			if (entity.alive)
			{
				PositionComponent* position;
				Cyclic cyclic;
				if (entity.fetch(position, cyclic))
				{
					position.position.x += movement * cyclic.step;
				}

				JumpPhysics* jump;
				if (entity.fetch(jump))
				{
					jump.jumpAnimation = transitionOffset;
				}
			}
		}
	}
}
