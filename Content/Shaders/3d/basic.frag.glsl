#version 450

layout(set = 2, binding = 0) uniform sampler2D u_texture;
layout(set = 2, binding = 1) uniform sampler2D u_tex_metal_rough;
layout(set = 2, binding = 2) uniform sampler2D u_tex_normalmap;

layout(set = 2, binding = 3) uniform sampler2D u_environment;

layout(set = 3, binding = 0) uniform Light {
	vec3 light_pos;
};


layout(location = 0) in vec2 v_texcoord;
layout(location = 1) in mat3 v_tangentspace;
layout(location = 4) in vec3 v_camera;
layout(location = 5) in vec4 v_position;

layout(location = 0) out vec4 frag_color;

void main() {
    vec4 color = texture(u_texture, v_texcoord);
    vec4 metal_rough = texture(u_tex_metal_rough, v_texcoord);
    vec4 normal_map = texture(u_tex_normalmap, v_texcoord) * 2.0 - 1.0;
    vec3 normal = normalize(v_tangentspace * normal_map.xyz);

    vec3 to_light = normalize(light_pos);
    // color.rgb = color.aaa;
    // color.xy = v_texcoord;
    float intensity = dot(normal, to_light);

    float roughness = metal_rough.y;
    float metallic = metal_rough.z;

    frag_color.xyz = color.xyz * intensity;


    vec3 to_cam = normalize(v_camera.xyz - v_position.xyz);
    vec3 reflection = -to_cam + (2 * dot(to_cam, normal) * normal);

    // phong
    float specular = dot(reflection, to_light);
    float shine = 1.0 - roughness;
    float specular_add = pow(specular, 1.01/(0.01+roughness)) * shine * intensity;

    frag_color.xyz += max(0.0, specular_add);

    vec2 env_uv;
    env_uv.y = 1.0 - (asin(reflection.z) / 3.1416 + 0.5);
    env_uv.x = 0.5 - atan(reflection.y, reflection.x) / 6.283;

    vec4 env_color = texture(u_environment, env_uv);
    frag_color.xyz += env_color.xyz * shine * 0.02;



//    frag_color.xyz = normal;
    //frag_color.xyz = reflection;//vec3(specular);
    //frag_color.xyz = to_light;//vec3(specular);
    //frag_color.xyz = v_camera;
    // blinn phong


    gl_FragDepth = gl_FragCoord.z;       // Write fragment depth
}
