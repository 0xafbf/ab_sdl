#version 450


layout(set = 1, binding = 0) uniform View {
	mat4 view;
	mat4 projection;
};

layout(set = 1, binding = 1) uniform Model {
	mat4 model;
};


layout(location = 0) in vec3 in_position;
layout(location = 1) in vec2 in_texcoord;
layout(location = 2) in vec3 in_normal;
layout(location = 3) in vec4 in_tangent;

layout(location = 0) out vec2 v_texcoord;

layout(location = 1) out vec4 v_tangent;
layout(location = 2) out vec3 v_normal;
layout(location = 3) out vec3 v_unused;

layout(location = 4) out vec3 v_camera;
layout(location = 5) out vec4 v_position;


void main() {
	v_position = model * vec4(in_position, 1.0);
	gl_Position = projection * view * v_position;
	
	v_camera = -view[3].xyz * mat3(view);
	v_texcoord = in_texcoord;

	v_tangent.xyz = mat3(model) * in_tangent.xyz;
	v_tangent.w = in_tangent.w;

	v_normal = mat3(model) * in_normal;
}
