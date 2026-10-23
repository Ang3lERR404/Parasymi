#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

// per-vertex (species mesh)
layout(location = 0) in vec3 pos;
layout(location = 1) in vec3 nrm;
layout(location = 2) in vec4 col;
layout(location = 3) in vec2 tu;    // height along plant, position along blade
layout(location = 4) in uint part;  // 0 stem 1 leaf 2 bloom 3 thorn 4 tendril
// per-instance
layout(location = 5) in vec3 ipos;
layout(location = 6) in vec4 ia;    // growth, mana fill, seed, affinity
layout(location = 7) in vec4 ib;    // flow, health, sway amplitude, form (0 herb, 1 confluence)
layout(location = 8) in vec4 ic;    // blend toward the next growth key
// the same vertex in the next growth key (equals pos/nrm for keyless plants)
layout(location = 9) in vec3 pos_next;
layout(location = 10) in vec3 nrm_next;

layout(location = 0) out vec3 v_pos;
layout(location = 1) out vec3 v_nrm;
layout(location = 2) out vec3 v_col;
layout(location = 3) out float v_glow;
layout(location = 4) flat out vec4 v_inst; // affinity, seed, health, part
layout(location = 5) flat out float v_form;

mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }

// rotate a colour's hue by `a` radians about the grey axis
vec3 hueShift(vec3 c, float a) {
  const vec3 k = vec3(0.57735);
  float ca = cos(a);
  return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

void main() {
  float t = pc.eye_time.w;
  float growth = ia.x, fill = ia.y, seed = ia.z, aff = ia.w;
  float flow = ib.x, health = ib.y, sway = ib.z;
  bool confluence = ib.w > 0.5;
  // a confluence blends between the growth keys around its growth, so it
  // grows smoothly instead of stepping from one shape to the next
  vec3 p = mix(pos, pos_next, ic.x);
  vec3 n = normalize(mix(nrm, nrm_next, ic.x));

  // growth: whole-plant scale, then leaves/petals unfurl as it matures
  float g = smoothstep(0.0, 1.0, growth);
  float open = part == 2u ? smoothstep(0.75, 1.0, growth) : smoothstep(tu.x * 0.8, tu.x * 0.8 + 0.3, growth);
  // (a confluence's canopy opens in its growth keys instead, on its leader)
  if ((part == 1u || part == 2u) && !confluence) p.xz *= mix(0.25, 1.0, open);

  // symbiotic breathing: slow, shared rhythm
  if (aff > 0.0 && part == 1u) p.xz *= 1.0 + 0.07 * aff * sin(t * 1.6 + seed * 6.28);
  // parasitic hunger: tendrils writhe and thorns twitch harder while feeding
  if (aff < 0.0 || part == 4u) {
    float hunger = max(-aff, 0.35) * (0.3 + flow);
    // a confluence's vines are held by its braid until they peel away (tu.y along the vine)
    float held = confluence ? smoothstep(0.1, 0.45, tu.y) : 1.0;
    if (part == 4u) p.xz = rot(sin(t * 3.0 + tu.x * 7.0 + seed * 9.0) * 0.35 * hunger * held) * p.xz;
    // thorns quiver at the tip only (tu.y = 0 at the base), along a shared axis
    if (part == 3u) p.y += 0.02 * hunger * tu.y * sin(t * 23.0 + seed * 40.0 + tu.x * 7.0);
  }
  // convergent: blooms slowly orbit (a confluence's canopy stays on its leader)
  if (abs(aff) < 0.5 && part == 2u && !confluence) p.xz = rot(t * 0.4 + seed * 6.28) * p.xz;

  // wilt when unhealthy
  p.y *= mix(0.55, 1.0, health);

  // wind sway, stronger toward the tip
  float h = tu.x;
  float wind = sin(t * 1.3 + ipos.x * 0.35 + ipos.z * 0.25 + seed * 6.28) + 0.4 * sin(t * 2.7 + seed * 20.0);
  p.x += wind * 0.05 * sway * h * h;
  p.z += cos(t * 1.1 + ipos.z * 0.3 + seed * 3.0) * 0.03 * sway * h * h;

  // per-instance variation
  float yaw = seed * 6.2831;
  p.xz = rot(yaw) * p.xz;
  n.xz = rot(yaw) * n.xz;
  // a confluence's growth keys already carry its size
  float s = (confluence ? 1.0 : mix(0.12, 1.0, g)) * (0.85 + 0.3 * fract(seed * 7.13));
  vec3 wp = ipos + p * s;

  v_pos = wp;
  v_nrm = n;
  v_col = srgb2lin(col.rgb);
  // the transition zone of a confluence's vines shimmers: its hue drifts +-10 degrees
  if (confluence && part == 4u) {
    float zone = smoothstep(0.08, 0.3, tu.y) * (1.0 - smoothstep(0.55, 0.8, tu.y));
    v_col = max(hueShift(v_col, radians(10.0) * zone * sin(t * 0.5 + seed * 6.28 + tu.y * 3.0)), 0.0);
  }
  v_form = ib.w;
  float bloomy = part == 2u ? 1.0 : (part == 1u ? 0.25 : 0.1);
  v_glow = (fill * bloomy + flow * 0.4) * (0.6 + 0.4 * sin(t * 3.0 + seed * 12.0 + h * 4.0)) * mix(0.3, 1.0, g);
  v_inst = vec4(aff, seed, health, float(part));
  gl_Position = pc.vp * vec4(wp, 1.0);
}
