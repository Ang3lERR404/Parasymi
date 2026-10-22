#version 450
layout(location = 0) in vec2 v_uv;
layout(location = 1) in vec4 v_col;
layout(location = 2) flat in uvec2 v_bits;
layout(location = 0) out vec4 o;
void main() {
  if (v_bits != uvec2(0xffffffffu)) {
    ivec2 p = ivec2(floor(v_uv));
    if (p.x >= 5 || p.y >= 7) discard;
    int b = p.y * 5 + p.x;
    uint word = b < 32 ? v_bits.x : v_bits.y;
    if (((word >> uint(b & 31)) & 1u) == 0u) discard;
  }
  o = v_col;
}
