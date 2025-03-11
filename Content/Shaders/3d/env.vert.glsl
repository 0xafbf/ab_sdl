#version 450


layout(set = 1, binding = 0) uniform View {
	mat4 view;
	mat4 projection;
	vec4 camera_data;
};

layout(location = 0) out vec3 v_camera;

const vec4 positions[4] = vec4[](
	vec4( 1,  1,  1, 1),
	vec4( 1, -1,  1, 1),
	vec4( 1,  1, -1, 1),
	vec4( 1, -1, -1, 1)
);

void main() {
	int vertex_id = gl_VertexIndex;
	vec4 position = positions[vertex_id];
	position.y /= projection[1][0];
	position.z /= projection[2][1];
	gl_Position = projection * position;
	gl_Position.z = 1;


	vec3 camera = inverse(mat3(view)) * position.xyz;
	v_camera = camera.xyz;
	//v_camera = position.xyz;
	//v_camera = camera.xyz;
}
