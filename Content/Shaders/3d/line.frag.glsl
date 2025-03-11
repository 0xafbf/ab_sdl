#version 450

layout(set = 2, binding = 0) uniform sampler2D u_texture;

layout(location = 0) in vec2 v_texcoord;
layout(location = 1) in mat3 v_tangentspace;
layout(location = 4) in vec3 v_camera;
layout(location = 5) in vec3 v_position;
layout(location = 6) in vec4 v_color;

layout(location = 0) out vec4 frag_color;

void main() {

    vec4 color = v_color;
    ivec2 texSize = textureSize(u_texture, 0);
    if (texSize.x == 0) {
        // color *= texture(u_texture, v_texcoord);
    }
    frag_color = color;

    gl_FragDepth = gl_FragCoord.z;       // Write fragment depth
}
