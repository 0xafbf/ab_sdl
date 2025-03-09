#version 450

layout(set = 2, binding = 0) uniform sampler2D u_texture;
layout(set = 2, binding = 1) uniform sampler2D u_tex_metal_rough;
layout(set = 2, binding = 2) uniform sampler2D u_tex_normalmap;

layout(set = 3, binding = 0) uniform Light {
	vec4 light_direction;
};


layout(location = 0) in vec2 v_texcoord;
layout(location = 1) in mat3 v_tangentspace;

layout(location = 0) out vec4 frag_color;

void main() {
    vec4 color = texture(u_texture, v_texcoord);
    vec4 metal_rough = texture(u_tex_metal_rough, v_texcoord);
    vec4 normal_map = texture(u_tex_normalmap, v_texcoord) * 2.0 - 1.0;
    vec3 normal = v_tangentspace * normal_map.xyz;
    float intensity = dot(normalize(normal), light_direction.xyz);
    // color.rgb = color.aaa;
    // color.xy = v_texcoord;
    frag_color.xyz = color.xyz * intensity;

    gl_FragDepth = gl_FragCoord.z;       // Write fragment depth
}
