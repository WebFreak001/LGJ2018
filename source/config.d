module config;

import avocado.assimp;
import avocado.bmfont;
import avocado.core;
import avocado.gl3;
import avocado.sdl2;

import std.algorithm;

alias Renderer = GL3Renderer;
alias View = SDLWindow;

auto toGLMesh(AssimpMeshData from)
{
	auto mesh = new GL3MeshCommon();
	mesh.primitiveType = PrimitiveType.Triangles;
	foreach (indices; from.indices)
		mesh.addIndexArray(indices);
	mesh.addPositionArray(from.vertices);
	foreach (texCoord; from.texCoords[0])
		mesh.addTexCoord(texCoord.xy);
	mesh.addNormalArray(from.normals);
	mesh.generate();
	return mesh;
}

alias BoneIndexElement = BufferElement!("BoneIndex", 4, int);
alias BoneWeightElement = BufferElement!("BoneWeight", 4);

alias GL3MeshIndexPositionTextureNormalBoneWeights = GL3Mesh!(IndexElement,
		PositionElement, TexCoordElement, NormalElement, BoneIndexElement, BoneWeightElement);

struct AnimatedMesh
{
	enum MAX_BONES = 100;

	GL3MeshIndexPositionTextureNormalBoneWeights base;
	string[] boneNames;
	mat4[MAX_BONES] baseBones;
	mat4[MAX_BONES] bones;

	AssimpAnimation animation;

	void loadFrame(float time)
	{
		int i = 0;
		for (; i < boneNames.length; i++)
		{
			auto translation = interpolate(animation.boneChannels[i].positionKeyframes, time);
			auto rotation = interpolate(animation.boneChannels[i].rotationKeyframes, time);
			bones[i] = mat4.translation(translation) * baseBones[i] * rotation.to_matrix!(4, 4);
		}
		bones[i .. $] = mat4.identity;
	}
}

AnimatedMesh toAnimatedGLMesh(AssimpMeshData from, AssimpAnimation animation)
{
	AnimatedMesh ret;
	ret.animation = animation;
	ret.baseBones[] = mat4.identity;
	ret.bones[] = mat4.identity;

	foreach (usedBone; animation.boneChannels)
		ret.boneNames ~= usedBone.nodeName;

	auto mesh = new GL3MeshIndexPositionTextureNormalBoneWeights();
	mesh.primitiveType = PrimitiveType.Triangles;
	foreach (indices; from.indices)
		mesh.addIndexArray(indices);
	mesh.addPositionArray(from.vertices);
	foreach (texCoord; from.texCoords[0])
		mesh.addTexCoord(texCoord.xy);
	mesh.addNormalArray(from.normals);
	vec4[] weights = new vec4[from.vertices.length];
	weights[] = vec4(0);
	vec4i[] indices = new vec4i[from.vertices.length];
	foreach (bone; from.bones)
	{
		auto index = ret.boneNames.countUntil(bone.name);
		if (index != -1)
		{
			foreach (weight; bone.weights)
			{
				if (weight.vertexID >= 0 && weight.vertexID < weights.length)
				{
					size_t min = 0;
					float minValue = 1;
					foreach (i, v; weights[weight.vertexID].vector)
					{
						if (v < minValue)
						{
							minValue = v;
							min = i;
						}
					}
					indices[weight.vertexID].vector[min] = cast(int) index;
					weights[weight.vertexID].vector[min] = weight.weight;
				}
			}
			ret.baseBones[index] *= bone.offset;
		}
	}
	mesh.addBoneIndexArray(indices);
	mesh.addBoneWeightArray(weights);
	mesh.generate();
	ret.base = mesh;
	return ret;
}
