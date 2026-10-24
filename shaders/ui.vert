#version 450
layout(push_constant) uniform Push { vec2 screen; float time; float pad; } pc;
layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 uv;
layout(location = 2) in vec2 size;
layout(location = 3) in vec4 col;
layout(location = 4) in uvec2 bits;
layout(location = 5) in vec2 param;
layout(location = 0) out vec2 v_uv;
layout(location = 1) out vec4 v_col;
layout(location = 2) flat out uvec2 v_bits;
layout(location = 3) flat out vec2 v_size;
layout(location = 4) flat out vec2 v_param;
// the palette's sRGB colours to linear (as common.glsl srgb2lin)
const float GAMMA = 2.2;
void main() {
  v_uv = uv;
  v_col = vec4(pow(col.rgb, vec3(GAMMA)), col.a);
  v_bits = bits;
  v_size = size;
  v_param = param;
  gl_Position = vec4(pos / pc.screen * 2.0 - 1.0, 0.0, 1.0);
}
