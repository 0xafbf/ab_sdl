#version 450

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec2 in_texcoord;

layout(location = 0) out vec2 v_texcoord;

layout(set = 1, binding = 0) uniform View {
	mat4 view;
	mat4 projection;
};

layout(set = 1, binding = 2) uniform Model {
	mat4 model;
};

void main() {
	gl_Position = projection * view * model * vec4(in_position, 1.0);
	v_texcoord = in_texcoord;
}