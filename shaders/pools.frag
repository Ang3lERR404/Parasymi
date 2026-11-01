#version 450
//! pooled rain (pools.vert): still deep-blue water over the ground, clear in the shallows and murky where deep, mirroring the sky and the key light, stirred by the wind and ringed by the rain falling on it, its shore soft; seen through the fog.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
#include "volume.glsl"

layout(location = 0) in float v_depth;
layout(location = 1) in vec3 v_pos;
layout(location = 0) out vec4 o;

// the water's own colour where deep (linear), and how deep it must be to
// hide the ground under it; how see-through it is in the shallows and at
// its deepest, looking straight down
const vec3 MURK = vec3(0.02, 0.07, 0.17);
const float MURK_DEPTH = 0.25;
const float CLEAR_SHALLOW = 0.4;
const float CLEAR_DEEP = 0.85;
// the shore: how deep the water is where it has wholly come in, both by the
// depth carried from its texels (soft along the grid) and over the ground
// right under it (crisp where the ground rises through)
const float SHORE = 0.12;
const float SHORE_EDGE = 0.02;
// how much of the sky it mirrors looking straight down, and at a graze,
// and the blue it tints what it mirrors
const float MIRROR_DOWN = 0.12;
const float MIRROR_GRAZE = 0.9;
const vec3 MIRROR_TINT = vec3(0.4, 0.72, 1.2);
// how bright the key light glints off it
const float GLINT = 1.2;
// the wind stirring it: ripples per unit, how fast they run, how far they
// tip its face
const float STIR_CELLS = 2.2;
const float STIR_RATE = 0.6;
const float STIR_TIP = 0.05;
// rain on it: ring cells per unit, how long one ring spreads (s), how wide
// it grows (of its cell), how sharp its crest, how far it tips the face
const float RING_CELLS = 3.0;
const float RING_LIFE = 0.9;
const float RING_WIDE = 0.45;
const float RING_CREST = 0.06;
const float RING_TIP = 0.12;
// rain this heavy or more rings every cell
const float RING_FULL = 0.6;

// a ring spreading from a drop in each rained-on cell round `p`: the slope
// it leaves on the face (x, z), how many cells ring as `rain` (0..1)
vec2 rings(vec2 p, float t, float rain) {
  vec2 g = p * RING_CELLS;
  vec2 cell = floor(g);
  vec2 slope = vec2(0.0);
  for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
    vec2 k = cell + vec2(i, j);
    vec3 h = hash33(vec3(k, 41.0));
    if (h.z * RING_FULL >= rain) continue;
    // the drop's place in its cell, and how far its ring has spread
    vec2 at = k + 0.2 + 0.6 * h.xy;
    float s = fract(t / RING_LIFE + h.x * 7.0);
    vec2 d = g - at;
    float r = length(d);
    float x = (r - s * RING_WIDE * 2.0) / RING_CREST;
    // a crest and a trough round it, flattening as it spreads
    float wave = -x * exp(-x * x) * (1.0 - s);
    slope += wave * d / max(r, 1e-4);
  }
  return slope;
}

void main() {
  float t = pc.eye_time.w;
  vec2 uv = overheadUv(v_pos);
  float rain = texture(field_map, uv).b;
  // its face: still, but for the wind's ripples and the rain's rings
  vec2 q = v_pos.xz * STIR_CELLS;
  vec2 wind = gardenWind(t, v_pos.xz).xy;
  vec2 stir = vec2(sin(q.x + q.y * 0.6 + t * STIR_RATE * 2.3), cos(q.y - q.x * 0.4 + t * STIR_RATE * 1.7)) * STIR_TIP * (0.4 + length(wind));
  vec2 slope = stir + rings(v_pos.xz, t, rain) * RING_TIP;
  vec3 n = normalize(vec3(-slope.x, 1.0, -slope.y));
  vec3 V = normalize(pc.eye_time.xyz - v_pos);
  float sh = keyShadow(v_pos, n);
  // the sky mirrored, more at a graze; the key light's glint
  float fres = mix(MIRROR_DOWN, MIRROR_GRAZE, pow(1.0 - max(dot(n, V), 0.0), 5.0));
  vec3 R = reflect(-V, n);
  vec3 sky = mix(byDay(MOONLIGHT * 0.25, mix(SKY_DAY, SKY_VEILED, VEIL) + 0.3), byDay(SKY_LEY_NIGHT * 2.0, SKY_LEY_DAY + 0.3), SHIFT);
  vec3 glint = keyLight() * hardSpot(R, SUN, SUN_SPOT) * GLINT * sh;
  // the water itself: the ground showing through the shallows, its murk
  // where deep, lit by the sky and the key light
  float deep = smoothstep(0.0, MURK_DEPTH, v_depth);
  vec3 body = shadeLit(MURK, vec3(0.0, 1.0, 0.0), v_pos, sh);
  vec3 c = mix(body, sky * MIRROR_TINT, fres) + glint;
  float a = mix(CLEAR_SHALLOW, CLEAR_DEEP, deep);
  float over = v_pos.y - texture(overhead_map, uv).a;
  a = mix(a, 1.0, fres) * smoothstep(0.0, SHORE, v_depth) * smoothstep(0.0, SHORE_EDGE, over);
  if (a < 0.003) discard;
  o = vec4(applyFog(c, v_pos), a);
}
