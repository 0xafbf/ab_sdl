#version 450

// Uniform block to hold the constants, equivalent to the cbuffer in HLSL

layout(set = 1, binding = 0) uniform SizeBlock {
	vec4 size;
	vec4 rect;
};

// The main vertex shader function
void main() {
	// Get the vertex index automatically, equivalent to 'SV_VertexID' in HLSL
	uint vert_idx = gl_VertexIndex;

	// Declare a vec4 to hold the final position
	vec4 position;

	float pos_x = rect.x / size.x * 2.0 - 0.5;
	float size_x = rect.z / size.x * 2.0;

	position.x = (rect.x + ((vert_idx % 2) * rect.z)) / size.x * 2 - 1;
	position.y = (rect.y + ((vert_idx / 2) * rect.w)) / size.y * -2 + 1;
	position.z = 0.0;
	position.w = 1.0;

	// Output the final position
	gl_Position = position;
}