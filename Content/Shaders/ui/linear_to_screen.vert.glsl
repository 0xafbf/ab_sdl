#version 450


layout(location = 0) out vec2 v_uv;



void main() {

	uint vert_idx = gl_VertexIndex;

	vec2 rect_uv = vec2(vert_idx % 2 == 0 ? 0 : 1, vert_idx / 2);

	vec4 position;
	position.xy = rect_uv * 2.0 - 1.0;
	position.z = 0.0;
	position.w = 1.0;

	v_uv = rect_uv;
	v_uv.y = 1.0 - v_uv.y;

	// Output the final position
	gl_Position = position;
}
