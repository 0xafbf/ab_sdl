#version 450


layout(set = 1, binding = 0) uniform View {
	mat4 view;
	mat4 projection;
};

layout(set = 1, binding = 1) uniform Model {
	mat4 model;
};

layout(set = 1, binding = 2) uniform Line {
	// if positive, is applied at world space
	// if negative, is applied at clip space
	float width;
};


layout(location = 0) in vec3 in_position;
layout(location = 1) in vec2 in_texcoord;
layout(location = 2) in vec4 in_color;
layout(location = 3) in vec3 in_normal;
layout(location = 4) in vec3 in_tangent;


layout(location = 0) out vec2 v_texcoord;
layout(location = 1) out mat3 v_tangentspace;
layout(location = 4) out vec3 v_camera;
layout(location = 5) out vec3 v_position;
layout(location = 6) out vec4 v_color;


void main() {
	vec4 position = model * vec4(in_position, 1.0);
	v_camera = -view[3].xyz * mat3(view);
	v_texcoord = in_texcoord;

	vec3 delta_to_cam = v_camera - position.xyz;
	vec3 dir_to_cam = normalize(delta_to_cam);
	vec3 side = normalize(cross(dir_to_cam, in_tangent));

	v_tangentspace = mat3(in_tangent, side, dir_to_cam);

	//position.xyz += 0.2 * in_texcoord.y * vec3(1,1,1);
	position.xyz += width * (in_texcoord.y - 0.5) * side;
	v_position = position.xyz;
	gl_Position = projection * view * position;
/*
	gl_Position.x = gl_VertexIndex/2 * 0.1 + position.x * 0.2;
	gl_Position.y = in_texcoord.y * 0.1 + position.y * 0.2;
	gl_Position.z = 0;
	gl_Position.w = 1;
*/
	v_color = in_color;

}
