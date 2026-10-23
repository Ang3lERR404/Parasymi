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
layout(location = 7) in vec4 ib;    // flow, health, sway amplitude, form (species.Form)
layout(location = 8) in vec4 ic;    // blend toward the next growth key, ghost (0/1), ghost fits (0/1)
// the same vertex in the next growth key (equals pos/nrm for keyless plants)
layout(location = 9) in vec3 pos_next;
layout(location = 10) in vec3 nrm_next;

layout(location = 0) out vec3 v_pos;
layout(location = 1) out vec3 v_nrm;
layout(location = 2) out vec3 v_col;
layout(location = 3) out vec2 v_sap;          // mana fill 0..1, sap moving through (pulse) 0..1
layout(location = 6) out float v_t;           // height along the plant (fibre direction)
layout(location = 7) out float v_young;       // 0 old, dense growth .. 1 newest, thinnest
layout(location = 4) flat out vec4 v_inst; // affinity, seed, health, part
layout(location = 5) flat out float v_form;
layout(location = 8) flat out vec2 v_ghost; // a placement preview, and whether it fits

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
  // species.Form: 0 herb, 1 coil, 2 confluence, 3 drift
  bool confluence = abs(ib.w - 2.0) < 0.5;
  bool coil = abs(ib.w - 1.0) < 0.5;
  // a confluence blends between the growth keys around its growth, so it
  // grows smoothly instead of stepping from one shape to the next
  vec3 p = mix(pos, pos_next, ic.x);
  vec3 n = normalize(mix(nrm, nrm_next, ic.x));

  // growth: whole-plant scale, then leaves/petals unfurl as it matures
  float g = smoothstep(0.0, 1.0, growth);
  float open = part == 2u ? smoothstep(0.75, 1.0, growth) : smoothstep(tu.x * 0.8, tu.x * 0.8 + 0.3, growth);
  // (a confluence's canopy opens in its growth keys instead, on its leader).
  // Weighted along the leaf (tu.y 0 at its base), so a leaf's base stays
  // where it grows from, on the stem or along a vine.
  if ((part == 1u || part == 2u) && !confluence && !coil) p.xz *= mix(1.0, mix(0.25, 1.0, open), tu.y);
  // a parasite's crown comes up closed, its fronds a tight upright bundle,
  // and opens out as it matures; its bladders swell in as the stalk passes them
  if (coil) {
    float unfurl = smoothstep(0.3, 1.0, growth);
    if (part == 4u) p.xz *= mix(0.3, 1.0, unfurl);
    if (part == 2u && tu.x < 0.9) p.xz *= mix(0.55, 1.0, smoothstep(tu.x * 0.7, tu.x * 0.7 + 0.35, growth));
  }

  // ---- motion: rooted and heavy. Nothing jitters: plants bend from the
  // root and answer the wind late, tips last; leaves only lift a little.
  // Every offset is a smooth field of position and tu, so shared vertices
  // move alike and the meshes stay watertight. ----
  float h = tu.x;
  // one wind over the whole garden: its heading drifts slowly, and broad
  // gusts roll across it as a wave, so neighbours lean together
  vec4 wind = gardenWind(t, ipos.xz);
  vec2 wdir = wind.xy;
  float gust = wind.z, along = wind.w;

  // symbiotic breathing: slow, the leaf tips moving
  if (aff > 0.0 && part == 1u) p.xz *= 1.0 + 0.04 * aff * tu.y * sin(t * 0.9 + seed * 6.28);
  // leaves and petals lift a touch in the gusts, tips most (bases stay)
  if (part == 1u || part == 2u) p.y += 0.012 * tu.y * tu.y * gust * sin(t * 1.7 + seed * 11.0 + h * 3.0);
  // parasites: fronds curl and uncurl slowly while feeding, alien but
  // unhurried; thorns barely stir
  if (aff < -0.5) {
    float hunger = -aff * (0.3 + flow);
    if (part == 4u) p.xz = rot(sin(t * 0.6 + tu.x * 3.0 + seed * 9.0) * 0.12 * hunger) * p.xz;
    if (part == 3u) p.y += 0.006 * hunger * tu.y * sin(t * 4.0 + seed * 40.0 + tu.x * 7.0);
  }
  // convergent: blooms turn, very slowly (a confluence's canopy stays on its leader)
  if (abs(aff) < 0.5 && part == 2u && !confluence) p.xz = rot(t * 0.12 + seed * 6.28) * p.xz;

  // wilt when unhealthy
  p.y *= mix(0.55, 1.0, health);

  // per-instance variation
  float yaw = seed * 6.2831;
  p.xz = rot(yaw) * p.xz;
  n.xz = rot(yaw) * n.xz;

  // the bend: each point turns about the root in the wind's plane, more
  // toward the tip, so a plant curves instead of shearing. Its own lean is
  // slow and reaches the tip after the base. What hangs below the root (a
  // floater's filaments) swings the other way, so it trails downwind.
  float own = sin(t * 0.85 - along * 0.3 + seed * 6.28 - h * 0.9);
  float lean = sway * (0.05 * gust + 0.025 * (0.4 + gust) * own);
  float ang = lean * h * h;
  ang *= smoothstep(-0.1, 0.1, p.y) * 2.0 - 1.0;
  p = bendIn(p, wdir, ang);
  n = bendIn(n, wdir, ang);
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
  v_ghost = ic.yz;
  // sap moving through the plant travels up it as a slow pulse
  v_sap = vec2(fill, clamp(flow, 0.0, 1.0) * (0.5 + 0.5 * sin(t * 2.0 - h * 6.0 + seed * 12.0)));
  v_t = h;
  // growth read: what grew last (near the growing front, and toward the
  // tips once grown) is thinner and more translucent than the old base
  v_young = clamp((h - growth + 0.55) / 0.55, 0.0, 1.0);
  if (part == 1u || part == 2u) v_young = max(v_young, 0.5);
  v_inst = vec4(aff, seed, health, float(part));
  gl_Position = pc.vp * vec4(wp, 1.0);
}
