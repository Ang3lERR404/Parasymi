#version 450
layout(push_constant) uniform Push { vec2 screen; } pc;
layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 uv;
layout(location = 2) in vec4 col;
layout(location = 3) in uvec2 bits;
layout(location = 0) out vec2 v_uv;
layout(location = 1) out vec4 v_col;
layout(location = 2) flat out uvec2 v_bits;
void main() {
  v_uv = uv;
  v_col = vec4(pow(col.rgb, vec3(2.2)), col.a);
  v_bits = bits;
  gl_Position = vec4(pos / pc.screen * 2.0 - 1.0, 0.0, 1.0);
}
