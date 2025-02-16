#version 450

layout(set = 1, binding = 0) uniform SizeBlock {
	vec4 size;
	vec4 rect;
	vec4 region;
};

layout(location = 0) out vec2 v_uv;

void main() {

	uint vert_idx = gl_VertexIndex;

	vec2 rect_uv = vec2(vert_idx % 2 == 0 ? 0 : 1, vert_idx / 2);

	vec4 position;
	position.xy = rect.xy + rect_uv * rect.zw;
	position.x = position.x / size.x * 2 - 1;
	position.y = position.y / size.y * -2 + 1;
	position.z = 0.0;
	position.w = 1.0;

	v_uv = region.xy + region.zw * rect_uv;

	// Output the final position
	gl_Position = position;
}