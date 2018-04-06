#version 330
uniform sampler2D tex;
in vec2 texCoord;
in vec3 normal;

layout(location = 0) out vec4 out_frag_color;

void main()
{
	out_frag_color = max(0.3, dot(normal, normalize(vec3(0, 0.5, 1)))) * texture(tex, texCoord);
}