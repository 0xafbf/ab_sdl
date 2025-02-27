#version 450

layout(set = 2, binding = 0) uniform sampler2D u_texture;

layout(location = 0) in vec2 v_texcoord;

layout(location = 0) out vec4 fragColor;


void main() {
    vec4 color = texture(u_texture, v_texcoord);
    color.xy = v_texcoord;
    fragColor = color;
}
