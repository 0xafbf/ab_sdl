#version 450

layout(set = 2, binding = 0) uniform sampler2D u_texture;

layout(set = 3, binding = 0) uniform ColorBlock {
    vec4 u_color;
};

layout(location = 0) in vec2 v_uv;

layout(location = 0) out vec4 fragColor;


void main() {
    vec4 alpha = texture(u_texture, v_uv);
    vec4 color = u_color;
    color.a *= alpha.a;
    fragColor = color;
}
