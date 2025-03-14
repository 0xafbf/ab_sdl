#version 450

layout(set = 2, binding = 0) uniform sampler2D u_environment;


layout(location = 0) in vec3 v_camera;

layout(location = 0) out vec4 frag_color;

void main() {
    vec3 camera = normalize(v_camera);
    vec2 texcoord;
    texcoord.y = 1.0 - (asin(camera.z) / 3.1416 + 0.5);
    texcoord.x = 0.5 - atan(camera.y, camera.x) / 6.283;
//    texcoord = v_camera.xy;
    
    vec4 color = texture(u_environment, texcoord);

    frag_color.xyz = color.xyz;
//    frag_color.xyz = camera;

    gl_FragDepth = 1.0;
}
