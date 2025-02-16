#version 450

layout(set = 3, binding = 0) uniform ColorBlock {
    vec4 u_color;
};

layout(location = 0) out vec4 fragColor;

void main() {
    fragColor = u_color;
}
