#version 450

layout(set = 2, binding = 0) uniform sampler2D u_texture;

layout(location = 0) in vec2 v_uv;

layout(location = 0) out vec4 fragColor;


float linear_to_srgb (float theLinearValue) {
  return theLinearValue <= 0.0031308f
       ? theLinearValue * 12.92f
       : pow (theLinearValue, 1.0f/2.4f) * 1.055f - 0.055f;
}
float srgb_to_linear (float thesRGBValue) {
  return thesRGBValue <= 0.04045f
       ? thesRGBValue / 12.92f
       : pow ((thesRGBValue + 0.055f) / 1.055f, 2.4f);
}

void main() {
    vec4 color = texture(u_texture, v_uv);
    color.r = linear_to_srgb(color.r);
    color.g = linear_to_srgb(color.g);
    color.b = linear_to_srgb(color.b);
    fragColor = color;
}


