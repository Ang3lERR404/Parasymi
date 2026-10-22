#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

layout(location = 0) in vec3 v_pos;
layout(location = 1) in vec3 v_nrm;
layout(location = 2) in vec3 v_col;
layout(location = 3) in float v_glow;
layout(location = 4) flat in vec4 v_inst;
layout(location = 0) out vec4 o;

void main() {
  vec3 n = normalize(v_nrm);
  if (!gl_FrontFacing) n = -n;
  float aff = v_inst.x, health = v_inst.z;
  vec3 albedo = mix(vec3(0.18, 0.12, 0.06), v_col, health);
  vec3 c = shade(albedo, n, v_pos);
  // translucency: leaves and petals glow a little with back light
  c += albedo * max(dot(-n, SUN), 0.0) * 0.35;
  vec3 sym = vec3(0.3, 1.0, 0.9), par = vec3(1.0, 0.2, 0.35), con = vec3(0.75, 0.55, 1.0);
  vec3 glowc = aff > 0.5 ? sym : (aff < -0.5 ? par : con);
  glowc = mix(glowc, vec3(1.0, 0.85, 1.0), pc.misc.x * 0.5);
  c += glowc * v_glow * 1.4;
  o = vec4(applyFog(c, v_pos), 1.0);
}
