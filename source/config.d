module config;

import avocado.sdl2;
import avocado.gl3;
import avocado.assimp;

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
