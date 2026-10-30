#version 450
//! one full-screen triangle for the fog, handing on the inverse view-projection (worked out once a vertex, not once a texel).
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

// one full-screen triangle over the volume; fog.frag turns each texel back
// into the eye's ray through it with the inverse view-projection, worked
// out here three times instead of once a texel
layout(location = 0) flat out mat4 v_inv;

void main() {
  vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
  v_inv = inverse(pc.vp);
  gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
}
