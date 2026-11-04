#version 450
//! one full-screen triangle at the far plane, turned back into view directions.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

// one full-screen triangle at the far plane; the fragment shader turns each
// pixel back into a world-space view direction.
layout(location = 0) out vec3 v_dir;

void main() {
  vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
  vec2 ndc = uv * 2.0 - 1.0;
  vec4 clip = vec4(ndc, 1.0, 1.0);
  // the direction through this corner (light.glsl `viewRay`: steady as the
  // camera moves, and exact blended between the corners)
  v_dir = viewRay(ndc);
  gl_Position = clip;
}
