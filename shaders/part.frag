#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

layout(location = 0) in vec3 v_pos;
layout(location = 1) in vec3 v_nrm;
layout(location = 2) in vec3 v_col;
layout(location = 3) in float v_glow;
layout(location = 4) flat in float v_part;
layout(location = 5) in float v_t;
layout(location = 6) flat in float v_fade;
layout(location = 0) out vec4 o;

const vec3 SAP = vec3(1.0, 0.43, 0.08);       // linear amber, the only accent
const vec3 SAP_DEEP = vec3(0.12, 0.035, 0.004); // the sac's dark heart
const vec3 SAP_SRGB_LIN = vec3(1.0, 0.428, 0.036); // palette sap (1, .68, .22), linearised

// direction of increasing `v_t` across the surface: along a tube that is its
// spine. Zero where `v_t` is constant (knots, spheres).
vec3 surfaceTangent() {
  vec3 dpx = dFdx(v_pos);
  vec3 dpy = dFdy(v_pos);
  vec3 sn = cross(dpx, dpy);
  vec3 r1 = cross(dpy, sn);
  vec3 r2 = cross(sn, dpx);
  float det = dot(dpx, r1);
  return abs(det) < 1e-12 ? vec3(0.0) : (r1 * dFdx(v_t) + r2 * dFdy(v_t)) / det;
}

void main() {
  vec3 tgrad = surfaceTangent(); // derivatives first, in uniform control flow
  vec3 raw = normalize(v_nrm);
  vec3 n = gl_FrontFacing ? raw : -raw;
  vec3 V = normalize(pc.eye_time.xyz - v_pos);
  int part = int(v_part + 0.5);
  float alpha = 1.0;
  vec3 c;

  // sap's hue follows its vertex colour relative to plain sap, so an
  // instance tint (paw beans, nose) can make it denser and browner
  vec3 hue = clamp(v_col / SAP_SRGB_LIN, 0.0, 1.5);
  bool inner_ear = part == 5 && dot(raw, V) < 0.0;
  if (part == 2 && v_fade < 0.999) {
    // translucent sap sac: dark and see-through at the centre, amber at
    // grazing angles. Only the near side is drawn (it is a closed sac).
    if (dot(raw, V) < 0.0) discard;
    float fres = pow(1.0 - clamp(dot(raw, V), 0.0, 1.0), 2.0);
    vec3 deep = SAP_DEEP * hue * (0.6 + 0.8 * v_glow);
    c = shade(deep, raw, v_pos) + mix(deep, SAP * hue * 2.2, fres) * (0.35 + v_glow);
    alpha = mix(v_fade, 1.0, fres);
  } else if (inner_ear && v_fade < 0.999) {
    // the inner ear is a sheet of sap: glowing at grazing angles, faintly
    // see-through face-on (the outer face stays solid vine)
    float fres = pow(1.0 - clamp(-dot(raw, V), 0.0, 1.0), 2.0);
    vec3 deep = SAP_DEEP * 1.6;
    c = shade(deep, -raw, v_pos) + mix(deep, SAP * 1.8, fres) * 0.5;
    c += SAP * max(dot(raw, SUN), 0.0) * 0.25; // light through the ear
    alpha = mix(v_fade, 1.0, fres);
  } else {
    vec3 albedo = v_col;
    float inner = 0.0;
    // the inner face of an ear (the side opposite its normal) is sap-lined
    if (part == 5) {
      inner = dot(raw, V) < 0.0 ? 1.0 : 0.0;
      albedo = mix(albedo, SAP * 0.6, inner * 0.8);
    }
    c = shade(albedo, n, v_pos);
    // leaves and sap are thin/translucent: back light shines through
    if (part == 1 || part == 2 || part == 5) c += albedo * max(dot(-n, SUN), 0.0) * 0.3;
    c += SAP * inner * 0.25;
    // woven strands: a Kajiya-Kay sheen across the tube's tangent so vines
    // read as directional fibres rather than flat facets
    float tl = length(tgrad);
    if (part == 0 && tl > 0.0) {
      vec3 T = tgrad / tl;
      T = normalize(T - n * dot(T, n) + 1e-6);
      vec3 H = normalize(SUN + V);
      float th = dot(T, H);
      float sheen = pow(sqrt(max(1.0 - th * th, 0.0)), 40.0);
      float lit = smoothstep(0.0, 0.3, dot(n, SUN));
      vec3 light = mix(vec3(0.35, 0.45, 0.8) * 0.3, vec3(1.0, 0.95, 0.85), pc.sun.w);
      c += mix(albedo, light, 0.5) * sheen * lit * 0.28 * smoothstep(0.3, 1.5, tl);
    }
    c += v_col * v_glow * 2.2;
  }
  // rim light keeps the silhouette readable at night
  float rim = pow(1.0 - max(dot(n, V), 0.0), 3.0);
  c += v_col * rim * mix(0.35, 0.12, pc.sun.w);
  o = vec4(applyFog(c, v_pos), alpha);
}
