module components;

import avocado.core;
import avocado.gl3;
import avocado.sdl2;

import config;
import osu;

mixin BasicComponent!("VelocityComponent", vec3);
mixin BasicComponent!("LockCamera", Camera*);

final struct PositionComponent
{
	vec3 position;
	quat rotation = quat.identity;
	vec3 offset = vec3(0);
	mixin ComponentBase;
}

final struct MeshComponent
{
	GLTexture tex;
	GL3ShaderProgram shader;
	GL3MeshCommon mesh;
	mixin ComponentBase;

	string toString() const
	{
		return format("Mesh %x", cast(size_t)&mesh);
	}
}

final struct AnimatedMeshComponent
{
	GLTexture tex;
	GL3ShaderProgram shader;
	AnimatedMesh mesh;
	float playFrom = 0, playTo = 5;
	mat4 offset = mat4.identity;
	float time = 0;
	mixin ComponentBase;

	string toString() const
	{
		return format("AnimatedMesh %x", cast(size_t)&mesh);
	}

	void tick(double delta)
	{
		float tps = mesh.animation.ticksPerSecond != 0 ? mesh.animation.ticksPerSecond : 25;
		time += cast(float) delta * tps;
		if (time > playTo)
			time = playFrom;
		mesh.loadFrame(time);
	}
}

final struct ContainerStack
{
	GLTexture tex;
	GL3ShaderProgram shader;
	GL3MeshCommon mesh;
	int height;
	vec3 cullMin, cullMax;
	mixin ComponentBase;

	string toString() const
	{
		return format("Mesh %x", cast(size_t)&mesh);
	}
}

final struct RectangleComponent
{
	GLTexture tex;
	vec4 rect;
	mixin ComponentBase;

	string toString() const
	{
		return format("Texture Rectangle %s,%s %sx%s (null=%s)", rect.x, rect.y,
				rect.z, rect.w, tex is null);
	}
}

final struct SolidComponent
{
	vec4 color;
	vec4 rect;
	mixin ComponentBase;

	string toString() const
	{
		return format("Solid Rectangle %d,%d %dx%d", rect.x, rect.y, rect.z, rect.w);
	}
}

final struct ControlComponent
{
	Control control;
	mixin ComponentBase;

	string toString() const
	{
		return format("Control %x", &control);
	}
}

final struct Cyclic
{
	float min = 0, max = 0;
	float step = 0;
	mixin ComponentBase;
}

enum HitJudgement : ubyte
{
	idle,
	tooFast,
	good,
	tooSlow,
	missed
}

bool isBad(HitJudgement hit)
{
	return hit == HitJudgement.tooFast || hit == HitJudgement.tooSlow || hit == HitJudgement.missed;
}

final struct JumpPhysics
{
	HitJudgement lastHit;
	float maxAnimationTime, animationTime;
	float jumpAnimation;
	float height = 1;
	bool stumbling;
	mixin ComponentBase;

	void hit(HitJudgement hit, float timeToNext)
	{
		if (lastHit == HitJudgement.missed)
			return;
		if (animationTime > 0.04 && hit == HitJudgement.missed)
			return;
		if (lastHit.isBad && hit.isBad)
		{
			if (stumbling)
			{
				lastHit = HitJudgement.missed;
				return;
			}
			stumbling = true;
		}
		else
			stumbling = false;
		lastHit = hit;
		animationTime = maxAnimationTime = timeToNext;
	}
}

final struct AABBCull
{
	vec3 min, max;
	mixin ComponentBase;
}

struct Camera
{
	bool lockPosition;
	bool lockRotation;
	float fov = 90;
	vec3 position = vec3(0);
	vec3 offset = vec3(0);
	vec3 absoluteOffset = vec3(0);
	float yaw = 0, pitch = 0;

	/// forward, backward, left, right
	Key[4] movement;
}

enum Judgement
{
	tbd,
	hit,
	miss
}

struct HitCircleComponent
{
	int index;
	HitObject info;
	Judgement judgement;

	mixin ComponentBase;
}
