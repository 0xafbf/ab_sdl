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
layout(location = 3) in vec3 in_tangent;

layout(location = 0) out vec2 v_texcoord;
layout(location = 1) out mat3 v_tangentspace;

layout(location = 4) out vec3 v_camera;
layout(location = 5) out vec4 v_position;


void main() {
	v_position = model * vec4(in_position, 1.0);
	v_position = projection * view * v_position;
	gl_Position = v_position;
	v_camera = -view[3].xyz;
	v_texcoord = in_texcoord;
	vec3 cotangent = cross(in_normal, in_tangent);
	v_tangentspace = mat3(model) * mat3(in_tangent, cotangent, in_normal);
}
