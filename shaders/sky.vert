#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

// one full-screen triangle at the far plane; the fragment shader turns each
// pixel back into a world-space view direction.
layout(location = 0) out vec3 v_dir;

void main() {
  vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
  vec4 clip = vec4(uv * 2.0 - 1.0, 1.0, 1.0);
  vec4 w = inverse(pc.vp) * clip;
  v_dir = w.xyz / w.w - pc.eye_time.xyz;
  gl_Position = clip;
}
