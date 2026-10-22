#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

layout(location = 0) in vec3 v_pos;
layout(location = 1) in vec3 v_nrm;
layout(location = 2) in vec3 v_col;
layout(location = 3) in float v_glow;
layout(location = 4) flat in float v_part;
layout(location = 0) out vec4 o;

void main() {
  vec3 n = normalize(v_nrm);
  if (!gl_FrontFacing) n = -n;
  vec3 c = shade(v_col, n, v_pos);
  // leaves and sap are thin/translucent: back light shines through
  if (v_part > 0.5 && v_part < 2.5) c += v_col * max(dot(-n, SUN), 0.0) * 0.3;
  // rim light keeps the silhouette readable at night
  float rim = pow(1.0 - max(dot(n, normalize(pc.eye_time.xyz - v_pos)), 0.0), 3.0);
  c += v_col * rim * mix(0.35, 0.12, pc.sun.w);
  c += v_col * v_glow * 2.2;
  o = vec4(applyFog(c, v_pos), 1.0);
}
