#version 450


layout(set = 1, binding = 0) uniform View {
	mat4 view;
	mat4 projection;
	vec4 camera_data;
};

layout(location = 0) out vec3 v_camera;

const vec4 positions[4] = vec4[](
	vec4(-1, -1, 0, 1),
	vec4(-1,  1, 0, 1),
	vec4( 1, -1, 0, 1),
	vec4( 1,  1, 0, 1)
);

void main() {
	int vertex_id = gl_VertexIndex;
	vec4 position = positions[vertex_id];
	gl_Position = position;
	vec4 camera = position;
	camera.x = camera.x / projection[0][0];
	camera.y = camera.y / projection[1][1];
	camera.z = 1;
	v_camera = mat3(view) * camera.xyz;
	//v_camera = camera.xyz;
}
