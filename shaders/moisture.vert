#version 450
//! one full-screen triangle over the whole moisture field, so moisture.frag steps every texel of it on, handing on how long the step is.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
#include "moisture.glsl"

// x the seconds the world moved since the last step
layout(location = 0) in vec4 i_dt;
// the step as the field takes it
layout(location = 0) flat out float v_dt;

void main() {
  vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
  v_dt = moistureStep(i_dt.x);
  gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
}
