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

enum Red = false;
enum Blue = true;

double redClickAnimation = 1;
double blueClickAnimation = 1;
double scoreAnimation = 1;
int scoreAmount = 0;
int totalScore = 0;

final class MovementSystem : ISystem
{
private:
	int index;
	int msToNextObject;
	int transitionMs, transitionStartMs;
	float transitionOffset = 0;
	Camera* camera;
	SoundEffect clickEffect, clickEffect2;
	KeyboardState prevState;
	bool modAuto; // = true;

	Key l1, l2, r1, r2;

	long clickTime;
	bool doubleClickBlue;
	float doubleTimer = 0;

	float correction = 0;

public:
	this(Camera* cam, SoundEffect normal, SoundEffect clap, Key l1, Key l2, Key r1, Key r2)
	{
		this.camera = cam;

		clickEffect = clap;
		clickEffect2 = normal;

		this.l1 = l1;
		this.l2 = l2;
		this.r1 = r1;
		this.r2 = r2;
	}

	void score(int howMuch)
	{
		totalScore += howMuch;
		scoreAmount = howMuch;
		scoreAnimation = 0;
	}

	void hit(bool blue, bool big, long at)
	{
		if (blue)
			blueClickAnimation = 0;
		else
			redClickAnimation = 0;
		auto circle = getCurrentCircle();
		if (blue)
		{
			clickEffect2.volume = big ? 1.0 : 0.65;
			audio.playEffect(clickEffect2);
		}
		else
		{
			clickEffect.volume = big ? 1.0 : 0.65;
			audio.playEffect(clickEffect);
		}
		auto ms50 = selectedSong.hitMsFor50(Osu.Mod.none);
		if (circle == HitObject.init || at < circle.time - ms50)
			return;
		if (circle.taikoIsBlue == blue)
		{
			int mul = 1;
			if (circle.taikoIsBig && big)
				mul = 2;
			auto miss = abs(at - circle.time);
			if (miss < selectedSong.hitMsFor300(Osu.Mod.none))
				score(300 * mul);
			else if (miss < selectedSong.hitMsFor100(Osu.Mod.none))
				score(100 * mul);
			else
				score(50 * mul);
			foreach (ref com; HitCircleComponent.components.byValue)
			{
				if (com.index == index)
				{
					com.judgement = Judgement.hit;
					break;
				}
			}
			nextCircle();
		}
		else
		{
			foreach (ref com; HitCircleComponent.components.byValue)
			{
				if (com.index == index)
				{
					com.judgement = Judgement.miss;
					break;
				}
			}
			miss();
		}
	}

	void miss()
	{
		score(0);
		nextCircle();
	}

	HitObject getCurrentCircle()
	{
		if (index >= selectedSong.hitObjects.objects.length
				|| audio.currentTime.total!"msecs" < selectedSong.hitObjects.objects[index].time - selectedSong.hitMsFor50(
				Osu.Mod.none))
			return HitObject.init;
		else
			return selectedSong.hitObjects.objects[index];
	}

	void onKeyboard(KeyboardEvent event)
	{
		if (event.type == SDL_KEYDOWN && !event.repeat)
		{
			if (!modAuto)
			{
				if (event.keysym.sym == l1 || event.keysym.sym == l2)
					userClick(Red);
				else if (event.keysym.sym == r1 || event.keysym.sym == r2)
					userClick(Blue);
				else if (event.keysym.sym == Key.F1)
				{
					audio.clearBuffer();
				}
				else if (event.keysym.sym == Key.F2)
				{
					audio.speed /= 1.03;
				}
				else if (event.keysym.sym == Key.F3)
				{
					audio.speed *= 1.03;
				}
			}
		}
	}

	void userClick(bool blue)
	{
		if (doubleTimer > 0)
		{
			if (doubleClickBlue == blue)
				hit(blue ? Blue : Red, true, clickTime);
			else
			{
				hit(blue ? Red : Blue, false, clickTime);
				hit(blue ? Blue : Red, false, audio.currentTime.total!"msecs");
			}
			doubleTimer = 0;
		}
		else
		{
			doubleClickBlue = blue;
			doubleTimer = 0.02;
			clickTime = audio.currentTime.total!"msecs";
		}
	}

	void triggerNonDouble()
	{
		hit(doubleClickBlue ? Blue : Red, false, clickTime);
		doubleTimer = 0;
	}

	void nextCircle()
	{
		auto object = selectedSong.hitObjects.objects[index];
		auto nextStart = selectedSong.hitObjects.objects[(index + 1) % $].time;

		if (nextStart < object.time)
			msToNextObject = 100;
		else
			msToNextObject = nextStart - object.time;

		msToNextObject -= cast(int) selectedSong.hitMsFor300(Osu.Mod.none);
		if (msToNextObject <= 10)
			msToNextObject = 10;
		index++;

		auto time = audio.currentTime.total!"msecs";
		transitionMs = 0;
	}

	final void update(World world)
	{
		auto prevOffset = transitionOffset;

		if (doubleTimer > 0)
		{
			doubleTimer -= world.delta;
			if (doubleTimer <= 0)
				triggerNonDouble();
		}

		auto time = audio.currentTime.total!"msecs";

		double width = 0;

		if (index < selectedSong.hitObjects.objects.length)
		{
			auto object = selectedSong.hitObjects.objects[index];
			if (time > selectedSong.hitObjects.objects[index].time + (modAuto ? 0
					: selectedSong.hitMsFor50(Osu.Mod.none)))
			{
				if (modAuto)
					hit(object.taikoIsBlue, object.taikoIsBig, time);
				else if (doubleTimer > 0)
					triggerNonDouble();
				else
					miss();
			}
			width = object.spacing;
		}
		if (index >= selectedSong.hitObjects.objects.length
				&& audio.audioReadIndex >= audio.audioData.length - audio.audioSampleRate)
		{
			index = 0;
			audio.reset();
		}

		if (transitionStartMs > 0)
		{
			transitionStartMs -= cast(int)(world.delta * 1000 * audio.effectiveSpeed);
			if (transitionStartMs <= 0)
			{
				transitionMs = 0;
				transitionStartMs = 0;
			}
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
		bool finishedMoving;
		if (movement > 0)
		{
			movement--;
			finishedMoving = true;
		}

		float nextCorrection = 0;
		foreach (entity; world.entities)
		{
			if (entity.alive)
			{
				PositionComponent* position;
				HitCircleComponent* hitObject;
				Cyclic cyclic;
				if (entity.fetch(position))
				{
					if (entity.fetch(position, cyclic))
					{
						position.position.x += movement * cyclic.step;
					}
					if (entity.fetch(hitObject))
					{
						position.position.x += correction;
						position.position.x += movement * 2.44 * width;
						if (finishedMoving && hitObject.index == index - 1 && position.position.x != 0)
							nextCorrection = -position.position.x;
					}
				}

				JumpPhysics* jump;
				if (entity.fetch(jump))
				{
					jump.height = width;
					jump.jumpAnimation = transitionOffset;
				}
			}
		}
		correction = nextCorrection;
	}
}
