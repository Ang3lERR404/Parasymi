#version 450
//! one breathing disc's share at a texel of the moisture field: most at its middle, none at its edge, added onto what is there.

layout(location = 0) in vec2 v_local;
layout(location = 1) flat in vec2 v_add;
layout(location = 0) out vec4 o;

void main() {
  float r2 = dot(v_local, v_local);
  if (r2 >= 1.0) discard;
  float f = (1.0 - r2) * (1.0 - r2);
  o = vec4(v_add * f, 0.0, 0.0);
}
