#version 450
//! material of library parts (structures, the wolf, nodes, beams, motes): fibre, sap, resin, essence, light.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
#include "surface.glsl"
#include "ground.glsl"
#ifdef AIR
#include "volume.glsl"
#include "air.glsl"
// what glows lights the air itself: its light taken before the distance
// fog, which the air pass's own march stands in for
#define applyFog(c, p) (c)
#endif

layout(location = 0) centroid in vec3 v_pos;
layout(location = 1) centroid in vec3 v_nrm;
layout(location = 2) in vec3 v_col;
layout(location = 3) in float v_glow;
layout(location = 4) flat in float v_part;
layout(location = 5) in float v_t;
layout(location = 6) flat in float v_fade;
layout(location = 7) in float v_u;
layout(location = 8) in vec3 v_obj;
layout(location = 9) flat in float v_phase; // per-instance phase (seeds a beam's motes)
layout(location = 10) flat in float v_aux;  // a beam: 1 for a halo's edge; a flash: its age 0..1
layout(location = 11) in vec2 v_sheet;      // a leaf or petal: along it 0..1, across it 1..3 (0: not a sheet)
layout(location = 0) out vec4 o;

const vec3 SAP = AMBER;                        // linear amber, the only accent
const vec3 SAP_DEEP = RESIN_DEEP;             // the sac's dark heart
// what light reaches sap and fibres at night (moonlight; by day near white)
const vec3 NIGHT_LIT = SAP_NIGHT;
// the diamond's crystal: its daylight, the warm film it reflects, its glint
const vec3 PRISM_DAY = vec3(1.0, 0.96, 0.9);
const vec3 PRISM_FILM = vec3(1.0, 0.82, 0.6);
const float PRISM_SPEC_POW = 120.0;
const float PRISM_FRESNEL_POW = 3.0;
// the strange seed's crystal husk: how much of its own colour it keeps, how
// clear it is face-on, its cracks' glow (the web's pale blue), how large
// its crack pattern is (per unit of mesh space) and how thin a seam
const float HUSK_TINT = 0.08;
const float HUSK_CLEAR = 0.1;
const vec3 HUSK_CRACK = vec3(0.55, 0.85, 1.6);
const float HUSK_CRACK_SCALE = 22.0;
const float HUSK_CRACK_W = 0.035;
// a ganglion's cortex: how clear it is face-on, how fast it thickens
// toward its edges, what its furrows take of its colour (darker, more
// violet) and how much denser they are, how much of the light of what it
// holds shines through it from inside
const float CORTEX_CLEAR = 0.45;
const float CORTEX_EDGE_POW = 2.2;
const vec3 CORTEX_FURROW = vec3(0.3, 0.22, 0.45);
const float CORTEX_FURROW_DENSE = 0.55;
const float CORTEX_THROUGH = 1.4;
// smooth value noise over a husk, its cracks laid along where it crosses
// the middle
float huskNoise(vec3 p) {
  vec3 i = floor(p), f = fract(p);
  vec3 u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(mix(hash33(i).x, hash33(i + vec3(1, 0, 0)).x, u.x), mix(hash33(i + vec3(0, 1, 0)).x, hash33(i + vec3(1, 1, 0)).x, u.x), u.y),
    mix(mix(hash33(i + vec3(0, 0, 1)).x, hash33(i + vec3(1, 0, 1)).x, u.x), mix(hash33(i + vec3(0, 1, 1)).x, hash33(i + vec3(1, 1, 1)).x, u.x), u.y), u.z);
}
// how tightly sap's colour gathers to its edge (1 - n.v)^this: a narrow
// band, so face-on it reads deep and clear and its light is the glisten's
const float SAP_EDGE_POW = 5.0;
// liquid essence: the streaks running along it (how many over its length,
// how fast)
const float ESSENCE_STREAKS = 3.0;
const float ESSENCE_RUN = 5.0;
// the soft shadow under a floater: its colour, and how it falls off to its rim
const vec3 GROUND_SHADOW = vec3(0.015, 0.015, 0.025);
const float GROUND_SHADOW_FALLOFF = 1.6;
// a flash's burst: a warm white
const vec3 FLASH_WHITE = vec3(1.0, 0.97, 0.9);
// research energy: deep violet, white-gold at its heart; its core's
// filaments (how many arms, how far they wind in from the rim, how fast),
// its rings closing in (how many, how fast), a wisp's pulses (how many
// along it, how fast they run into the core)
const vec3 ENERGY_DEEP = vec3(0.32, 0.14, 0.95);
const vec3 ENERGY_HEART = vec3(1.0, 0.86, 0.62);
const float ENERGY_ARMS = 3.0;
const float ENERGY_WIND = 7.0;
const float ENERGY_SPIN = 2.6;
const float ENERGY_RINGS = 14.0;
const float ENERGY_CLOSE = 5.0;
const float ENERGY_PULSES = 3.0;
const float ENERGY_RUN = 8.0;
// a spark of lightning: its violet edge, its white-hot core, how tight
// that core is, and how fast it flickers
const vec3 SPARK_EDGE = vec3(0.55, 0.32, 1.0);
const vec3 SPARK_CORE = vec3(1.0, 0.96, 1.0);
const float SPARK_TIGHT = 6.0;
const float SPARK_FLICKER = 47.0;
// the constellate web: its blue, the pale it lightens to as a beat passes,
// how often its heart beats (s), how fast a beat runs through it (m/s),
// where in the beat the two thumps fall and how sharp they are, how much a
// beat fades for every metre it runs
const vec3 PLEXUS_BLUE = vec3(0.04, 0.16, 0.85);
const vec3 PLEXUS_PALE = vec3(0.62, 0.86, 1.0);
// the companions' layer of the web: cyan, going pale sea-glass as a beat passes
const vec3 PLEXUS_CYAN = vec3(0.02, 0.5, 0.6);
const vec3 PLEXUS_CYAN_PALE = vec3(0.6, 1.0, 0.95);
const float PLEXUS_PERIOD = 1.6;
const float PLEXUS_SPEED = 0.9;
const float PLEXUS_LUB = 0.06;
const float PLEXUS_DUB = 0.2;
const float PLEXUS_THUMP = 0.035;
const float PLEXUS_FADE = 0.35;
// a halo crown's fragment: how much of the sky's light its upper faces
// take by day (it is light itself, the key light left out)
const float CROWN_SKY = 0.25;
// the halo's projection: how many rays it has round it
const float RAYS = 40.0;
// the roles thin enough for light from behind to shine through (leaves,
// sap, an ear), and the woven ones with a sheen along their fibres
const uint THIN = PART_BIT(PART_LEAF) | PART_BIT(PART_BLOOM) | PART_BIT(PART_EAR);
const uint FIBRES = PART_BIT(PART_STEM) | PART_BIT(PART_CORE) | PART_BIT(PART_NERVE);

// sapLifeAt (surface.glsl) for this fragment
vec3 sapLife(vec3 c, vec3 sapc, vec3 n, vec3 V, float inside, float sh, vec3 mirrored, inout float alpha) {
  return sapLifeAt(c, sapc, n, V, v_pos, v_obj, inside, sh, mirrored, alpha);
}

// weathered stone (sRGB): the dark of its hollows and flecks, its pale
// flecks, the lichen that takes the faces turned to the sky; how deep its
// grain lights it, and how many grains a unit of its mesh holds
const vec3 STONE_HOLLOW = vec3(0.16, 0.15, 0.15);
const vec3 STONE_FLECK = vec3(0.86, 0.84, 0.78);
const vec3 STONE_LICHEN = vec3(0.56, 0.6, 0.38);
const float STONE_BUMP = 0.04;
const float STONE_GRAIN = 9.0;
// value noise 0..1 in three dimensions, smooth between hashed lattice corners
float rockNoise(vec3 p) {
  vec3 i = floor(p), f = fract(p);
  vec3 u = f * f * (3.0 - 2.0 * f);
  float a = hash12(i.xy + i.z * 17.13), b = hash12(i.xy + vec2(1.0, 0.0) + i.z * 17.13);
  float c = hash12(i.xy + vec2(0.0, 1.0) + i.z * 17.13), d = hash12(i.xy + vec2(1.0, 1.0) + i.z * 17.13);
  float e = hash12(i.xy + (i.z + 1.0) * 17.13), g = hash12(i.xy + vec2(1.0, 0.0) + (i.z + 1.0) * 17.13);
  float h = hash12(i.xy + vec2(0.0, 1.0) + (i.z + 1.0) * 17.13), k = hash12(i.xy + vec2(1.0, 1.0) + (i.z + 1.0) * 17.13);
  return mix(mix(mix(a, b, u.x), mix(c, d, u.x), u.y), mix(mix(e, g, u.x), mix(h, k, u.x), u.y), u.z);
}
// three octaves of it, each turned off the last
float rockFbm(vec3 p) {
  float s = 0.0, a = 0.5;
  for (int i = 0; i < 3; i++) {
    s += a * rockNoise(p);
    p = p.yzx * 2.03 + 11.7;
    a *= 0.5;
  }
  return s;
}
// a stone's surface at mesh point `q` (world normal `n`): its colour from
// the vertex's grey, mottled, flecked dark and pale, darker down in its
// hollows, lichened up its sky-turned faces; and how high its grain stands
struct StoneSurface { vec3 albedo; float height; };
StoneSurface stoneSurface(vec3 base, vec3 q, vec3 n) {
  vec3 p = q * STONE_GRAIN;
  float mottle = rockFbm(p * 0.35);
  float grain = rockNoise(p * 2.0) * 0.6 + rockNoise(p * 5.0) * 0.4;
  float hollow = smoothstep(0.55, 0.25, rockFbm(p * 0.8 + 5.0));
  vec3 c = base * (0.78 + 0.44 * mottle) * (0.88 + 0.24 * grain);
  c = mix(c, srgb2lin(STONE_HOLLOW), hollow * 0.45);
  float fleck = rockNoise(p * 7.0 + 3.0);
  c = mix(c, srgb2lin(STONE_HOLLOW), smoothstep(0.9, 0.95, fleck) * 0.6);
  c = mix(c, srgb2lin(STONE_FLECK), smoothstep(0.1, 0.03, fleck) * 0.6);
  float lichen = smoothstep(0.55, 0.62, rockFbm(p * 0.6 + 21.0)) * smoothstep(0.35, 0.8, n.y);
  c = mix(c, srgb2lin(STONE_LICHEN) * (0.8 + 0.4 * grain), lichen * 0.75);
  return StoneSurface(c, grain * 0.6 + (1.0 - hollow) * 0.4 + lichen * 0.2);
}

void surface() {
  vec3 tgrad = surfaceTangent(v_pos, v_t); // along a tube; derivatives first, in uniform control flow
  vec3 raw = normalize(v_nrm);
  vec3 n = gl_FrontFacing ? raw : -raw;
  vec3 V = normalize(pc.eye_time.xyz - v_pos);
  int part = int(v_part + 0.5);
  float alpha = 1.0;
  vec3 c;

  // sap's hue follows its vertex colour relative to plain sap, so an
  // instance tint (paw beans, nose) can make it denser and browner
  vec3 hue = clamp(v_col / SAP_SRGB_LIN, 0.0, 1.5);
  bool inner_ear = part == PART_EAR && dot(raw, V) < 0.0;
  // what is light itself (PARTS_LIGHT: beams, a halo's flash, ring and
  // rays) shines on its own, the key light left out: each its own material
#ifndef HEAD
  // (built with HEAD, for each mesh's always-solid triangles alone, what
  // is light itself, a ground shadow, resin and sap are left out: those
  // triangles never take them, and the shader is lighter without them)
  if (part == PART_THREAD) {
    // soft rays sent from one bloom to the other: no core, a faint haze
    // across the width (v_u -1..1) with a few soft streaks in it, each
    // broken into long swells of light travelling from the sender (v_t 0)
    // to the receiver. The hue runs the rainbow from one end to the other,
    // rolling along with them; tiny motes of light drift along inside,
    // shifting hue as they go. It carries light of its own (bloom catches
    // the swells and motes); a dark network's beam is a faint trace.
    float t = pc.eye_time.w;
    float u = v_u;
    float len = max(v_fade, 0.1);
    float x = v_t * len; // world distance from the sender
    float lit = min(v_glow, 1.0);
    float roll = v_t - t * 0.12;
    float haze = exp(-u * u * 3.0);
    vec3 rays = vec3(0.0);
    float ray_a = 0.0;
    for (int k = 0; k < 5; k++) {
      float fk = float(k);
      float lane = (fk - 2.0) * 0.32 + 0.1 * sin(t * 0.6 + fk * 2.1 + x * 0.7);
      float across = exp(-(u - lane) * (u - lane) * 38.0);
      float swell = 0.5 + 0.5 * sin(x * (1.1 + 0.23 * fk) - t * (1.6 + 0.3 * fk) + fk * 1.7);
      float a = across * swell * swell * (1.0 - 0.15 * abs(fk - 2.0));
      rays += filmHue(roll + fk * 0.04) * a;
      ray_a += a;
    }
    // motes: one per cell along the beam, drifting toward the receiver,
    // each at its own place across (seeded by the instance's phase, which
    // holds still, unlike its length) and twinkling; neighbouring cells
    // too, so none is cut at a cell's edge
    const float CELL = 0.3;
    const float DRIFT = 0.55;
    const float WIDTH = BEAM_HALF_WIDTH;
    float m = 0.0;
    vec3 mc = vec3(0.0);
    float drift = (x - t * DRIFT) / CELL;
    for (int k = -1; k <= 1; k++) {
      float id = floor(drift) + float(k);
      vec3 h = hash33(vec3(id, v_phase * 7.31, 7.0));
      float dx = (drift - id - h.x) * CELL;
      float du = (u - (h.y * 1.5 - 0.75) - 0.08 * sin(t * 1.3 + h.z * TAU)) * WIDTH;
      float tw = 0.55 + 0.45 * sin(t * (3.0 + 3.0 * h.z) + h.x * TAU);
      float d2 = dx * dx + du * du;
      float g = (exp(-d2 / 0.0006) + 0.35 * exp(-d2 / 0.006)) * tw;
      m += g;
      mc += filmHue(roll + h.z * 0.3 + t * 0.05) * g;
    }
    // fade into each bloom's core at the ends
    // (a halo's edges run on into each other at its corners instead)
    float ends = v_aux > 0.5 ? 1.0 : smoothstep(0.0, 0.08, v_t) * smoothstep(1.0, 0.92, v_t);
    vec3 film = filmHue(roll);
    c = (film * haze * 0.25 + rays * 0.9 + mix(mc, vec3(m), 0.35) * 2.5) * (0.12 + 0.88 * lit);
    float a = clamp(haze * 0.18 + ray_a * 0.45 + m, 0.0, 1.0);
    o = vec4(applyFog(c, v_pos), a * ends * (0.3 + 0.7 * lit));
    return;
  }
  if (part == PART_PLEXUS) {
    // the constellate web (v_u: 0 a point, 1 a line, 2 a pane; v_t how far
    // a beat runs through it to reach here; v_glow how much of a line or
    // pane shows as its points part). Its heart beats lub-dub, and
    // each beat runs out through the web, reaching here v_t / SPEED late,
    // fading as it goes: it lightens the blue toward pale as it passes. A
    // point is a solid light; a line glows thin; a pane is a sheet of blue
    // glass, brighter at its grazing edges.
    float t = pc.eye_time.w;
    float ph = fract((t - v_t / PLEXUS_SPEED) / PLEXUS_PERIOD + v_phase);
    float lub = (ph - PLEXUS_LUB) / PLEXUS_THUMP;
    float dub = (ph - PLEXUS_DUB) / PLEXUS_THUMP;
    float beat = (exp(-lub * lub) + 0.6 * exp(-dub * dub)) / (1.0 + PLEXUS_FADE * v_t);
    float ndv = abs(dot(raw, V));
    // what it is (3 a bond, drawn as a line), whether it is on the
    // companions' layer (v_u 4 more), whether a mote of light a yielder
    // yields (8 more: pale light itself, brighter than any point)
    int code = int(v_u + 0.5);
    int kind = code % 4;
    bool second = (code / 4) % 2 == 1;
    bool mote = code >= 8;
    vec3 blue = second ? PLEXUS_CYAN : PLEXUS_BLUE;
    vec3 pale = second ? PLEXUS_CYAN_PALE : PLEXUS_PALE;
    vec3 col = mix(blue, pale, clamp(beat, 0.0, 1.0));
    float a;
    if (kind == 0) {
      // (v_glow: dimmer where the heart's webs crowd close)
      c = mote ? pale * 4.0 : mix(col, pale, 0.35 * pow(ndv, 2.0)) * (1.6 + 4.0 * beat) * v_glow;
      a = 1.0;
    } else if (kind == 1 || kind == 3) {
      // a line is a glow: a thin bright core (v_obj.x how far across it)
      // fading softly out either side
      float x = v_obj.x;
      float core = exp(-x * x * 40.0);
      float halo = exp(-x * x * 4.0);
      c = (col * (0.8 + 3.0 * beat) * halo + pale * core * (0.6 + 1.5 * beat)) * v_glow;
      a = clamp(0.55 * halo + 0.5 * core + 0.3 * beat * halo, 0.0, 1.0) * v_glow;
    } else {
      float rim = pow(1.0 - ndv, 3.0);
      c = col * (0.32 + 0.6 * rim + 1.8 * beat) * v_glow;
      a = clamp(0.4 + 0.35 * rim + 0.4 * beat, 0.0, 1.0) * v_glow;
    }
    o = vec4(applyFog(c, v_pos), a);
    return;
  }
  if (part == PART_ENERGY) {
    // research energy an arsthraxia condenses: light itself, deep violet
    // going white-gold at its heart (v_glow how bright; v_fade how far
    // the unit has condensed 0..1; v_aux a flare as it is done, fading).
    // Its core (v_t < 0): a dense heart face-on, filaments of light
    // winding in from the rim toward it and rings of it closing in on it.
    // A wisp (v_t 0 at the satellite .. 1 at the core): a soft thread
    // whose pulses run into the core, brightening as they near it.
    if (dot(raw, V) < 0.0) discard;
    float t = pc.eye_time.w;
    float ndv = clamp(dot(raw, V), 0.0, 1.0);
    float rim = 1.0 - ndv;
    float a;
    if (v_t < 0.0) {
      float dense = clamp(v_fade, 0.0, 1.0);
      vec3 d = normalize(v_obj);
      float around = atan(d.z, d.x);
      float wind = around * ENERGY_ARMS + rim * ENERGY_WIND + t * ENERGY_SPIN + v_phase * TAU + 1.5 * sin(d.y * 4.0 + t * 0.7);
      float fil = pow(0.5 + 0.5 * sin(wind), 8.0) * rim;
      float rings = pow(0.5 + 0.5 * sin(rim * ENERGY_RINGS + t * ENERGY_CLOSE), 6.0) * rim;
      float heart = pow(ndv, 3.0);
      vec3 col = mix(ENERGY_DEEP, ENERGY_HEART, heart * (0.35 + 0.65 * dense) + v_aux * 0.5);
      c = col * (heart * (0.6 + 1.4 * dense) + fil * 0.9 + rings * 0.55 + v_aux * 1.6) * v_glow;
      a = clamp(heart * (0.3 + 0.65 * dense) + fil * 0.55 + rings * 0.35 + v_aux * 0.5, 0.0, 1.0);
    } else {
      float run = pow(0.5 + 0.5 * sin(v_t * TAU * ENERGY_PULSES - t * ENERGY_RUN + v_phase * TAU), 4.0);
      float body = pow(ndv, 1.5);
      float ends = smoothstep(0.0, 0.15, v_t) * smoothstep(1.0, 0.8, v_t);
      vec3 col = mix(ENERGY_DEEP, ENERGY_HEART, 0.2 + 0.5 * v_t * run);
      c = col * body * (0.25 + 1.3 * run) * (0.5 + 0.5 * v_t) * v_glow;
      a = clamp(body * (0.15 + 0.75 * run), 0.0, 1.0) * ends * clamp(v_fade, 0.0, 1.0);
    }
    o = vec4(applyFog(c, v_pos), a);
    return;
  }
  if (part == PART_SPARK) {
    // a spark of lightning (v_t 0..1 along it): light itself, a white-hot
    // core seen face-on, violet toward its edge, flickering fast; brighter
    // than white, so the glow takes it up (v_glow how bright, v_fade how
    // much is left of it)
    if (dot(raw, V) < 0.0) discard;
    float t = pc.eye_time.w;
    float ndv = clamp(dot(raw, V), 0.0, 1.0);
    float core = pow(ndv, SPARK_TIGHT);
    float flick = 0.6 + 0.4 * sin(t * SPARK_FLICKER + v_t * 9.0 + v_phase * TAU);
    vec3 col = mix(SPARK_EDGE, SPARK_CORE, core);
    float ends = smoothstep(0.0, 0.08, v_t) * smoothstep(1.0, 0.92, v_t);
    c = col * (0.6 + 2.4 * core) * flick * v_glow;
    float a = clamp((0.25 + 0.75 * core) * flick, 0.0, 1.0) * ends * clamp(v_fade, 0.0, 1.0);
    o = vec4(applyFog(c, v_pos), a);
    return;
  }
  if (part == PART_CROWN) {
    // a halo crown's fragment (game/light_crown.zig): pearl, as the
    // radiant plants are, its thin film turning its hue with the view and
    // drifting slowly over it like a soap bubble; light held inside it
    // (v_glow), brightest where it is thinnest (its edges), see-through
    // face-on; a breath of the sky's light on its upper faces by day so its
    // form reads; fading in as it settles (v_fade)
    float t = pc.eye_time.w;
    float ndv = abs(dot(raw, V));
    float fres = pow(1.0 - ndv, 2.0);
    vec3 film = filmHue(ndv * 1.4 + v_t * 0.8 + v_phase * 3.0 + t * 0.03);
    vec3 pearl = mix(v_col, film, 0.3 + 0.4 * fres);
    c = pearl * (0.3 + 1.1 * fres) * (0.35 + 1.5 * v_glow);
    c += pearl * (0.5 + 0.5 * n.y) * CROWN_SKY * DAYLIGHT;
    c += mix(pearl, vec3(1.0), 0.5) * pow(max(dot(reflect(-V, n), SUN), 0.0), 40.0) * 0.6 * DAYLIGHT;
    float a = mix(0.45, 0.95, fres) * clamp(v_fade, 0.0, 1.0);
    o = vec4(applyFog(c, v_pos), a);
    return;
  }
  if (part == PART_TRAIL) {
    // a trail of light (v_t 0 its tail .. 1 its head; v_obj.x across it,
    // -1..1): a thin bright core in a soft glow, its colour going pale at
    // the head, fading out toward the tail; light itself, brighter than
    // white, so the glow takes it up (v_glow how bright, v_fade how much
    // is left of it)
    float x = v_obj.x;
    float head = clamp(v_t, 0.0, 1.0);
    float core = exp(-x * x * 30.0);
    float halo = exp(-x * x * 3.0);
    float along = pow(head, 1.6) * smoothstep(1.0, 0.94, head);
    vec3 col = mix(v_col, vec3(1.0), 0.5 * core * head);
    c = col * (halo * 0.9 + core * 2.2) * along * v_glow;
    float a = clamp(halo * 0.5 + core * 0.6, 0.0, 1.0) * along * clamp(v_fade, 0.0, 1.0);
    o = vec4(applyFog(c, v_pos), a);
    return;
  }
  if (part == PART_FLASH) {
    // the flash where the blooms became one: a disc of light thrown out
    // from the diamond (v_t its radius 0..1), its rim a bright ring that
    // runs the film's colours around, its inside a burst that is gone
    // almost at once; all of it fading as it spreads (age v_aux 0..1). It
    // is light: brighter than white, so the glow takes it up.
    float age = clamp(v_aux, 0.0, 1.0);
    float r = clamp(v_t, 0.0, 1.0);
    float rim = exp(-(r - 0.92) * (r - 0.92) * 220.0);
    float burst = (1.0 - r * r) * pow(1.0 - age, 6.0);
    float fade = pow(1.0 - age, 2.0);
    vec3 film = mix(filmHue(atan(v_obj.z, v_obj.x) / TAU + age * 0.3), vec3(1.0), 0.45);
    c = (film * rim * 3.0 + FLASH_WHITE * burst * 2.5) * fade * v_glow;
    o = vec4(applyFog(c, v_pos), clamp((rim * 0.9 + burst * 0.6) * fade, 0.0, 1.0));
    return;
  }
  if (part == PART_HALO) {
    // the halo: light the diamond has split and thrown into a ring. Across
    // its width (v_u, inner edge -1 .. outer 1) the spectrum fans out as in
    // an ice halo: a sharp red inner edge, then orange, gold, green, blue,
    // washing out pale toward violet beyond. Swells of light and fine
    // motes run round it as along the blooms' beams. An arc dims with the
    // points beside it (v_glow); the whole appears as the diamond forms
    // (v_aux). All of it is periodic round the ring, so it has no seam.
    float t = pc.eye_time.w;
    float form = v_aux;
    float x = (v_u + 1.0) * 0.5;
    float body = smoothstep(0.0, 0.1, x) * exp(-x * 2.4);
    vec3 col = mix(spectral(x * 1.2), vec3(1.0), smoothstep(0.45, 1.0, x) * 0.55);
    float ang = v_t * TAU;
    float lit = min(v_glow, 1.0);
    float sw = 0.0;
    for (int k = 0; k < 3; k++) {
      float fk = float(k);
      sw += pow(0.5 + 0.5 * sin(ang * (5.0 + 2.0 * fk) - t * (0.9 + 0.35 * fk) + fk * 2.1), 3.0);
    }
    sw /= 3.0;
    // motes: one per cell round the ring, drifting round it, each at its
    // own place across; neighbouring cells too, so none is cut at an edge
    float cells = max(floor(TAU * v_fade / 0.35), 1.0);
    float drift = fract(v_t - t * 0.012) * cells;
    float mo = 0.0;
    vec3 mc = vec3(0.0);
    for (int k = -1; k <= 1; k++) {
      float id = mod(floor(drift) + float(k), cells);
      vec3 h = hash33(vec3(id, v_phase * 5.17, 11.0));
      float dx = (drift - (floor(drift) + float(k)) - h.x) * TAU * v_fade / cells;
      float du = (x - h.y) * 0.13 * v_fade;
      float tw = 0.55 + 0.45 * sin(t * (2.5 + 3.0 * h.z) + h.x * TAU);
      float d2 = dx * dx + du * du;
      float gl = (exp(-d2 / 0.0006) + 0.3 * exp(-d2 / 0.006)) * tw;
      mo += gl;
      mc += spectral(h.y * 1.1) * gl;
    }
    c = (col * body * (0.5 + 1.1 * sw) + mix(mc, vec3(mo), 0.4) * 1.8) * (0.25 + 0.75 * lit) * form;
    float a = clamp(body * (0.4 + 0.5 * sw) + mo * 0.8, 0.0, 1.0) * (0.35 + 0.65 * lit) * form * form;
    o = vec4(applyFog(c, v_pos), a);
    return;
  }
  if (part == PART_PROJECTION) {
    // the projection: fine needles of split light the diamond throws out
    // (v_t 0 at the crystal .. 1 at the ring, v_u round it), each ray its
    // own hue, pulses running out along them to the ring; between them
    // only a breath of haze. They reach out as the diamond forms (v_aux).
    float t = pc.eye_time.w;
    float reach = v_aux;
    if (v_t > reach) discard;
    float a = v_u * RAYS;
    float id = mod(floor(a + 0.5), RAYS);
    vec3 h = hash33(vec3(id, v_phase * 7.3, 3.0));
    float on = step(0.3, h.x);
    float d = abs(a - floor(a + 0.5)) / RAYS * TAU * max(v_t * v_fade, 0.06);
    float ray = exp(-d * d / 0.0012) * on;
    float pulse = pow(0.5 + 0.5 * sin(v_t * 10.0 - t * (1.8 + h.y) + h.z * TAU), 4.0);
    float ends = smoothstep(0.0, 0.12, v_t) * smoothstep(1.0, 0.88, v_t) * smoothstep(reach, reach - 0.06, v_t);
    vec3 col = mix(spectral(h.y), vec3(1.0), 0.2);
    c = col * ray * (0.25 + 1.3 * pulse) * v_glow;
    float al = clamp(ray * (0.12 + 0.5 * pulse) + 0.015, 0.0, 1.0) * ends;
    o = vec4(applyFog(c, v_pos), al);
    return;
  }
#endif
  // how much of the key light reaches what is left (what stands between it
  // and the sun or moon shades it): it shades the light's glints, the
  // light carried through sap and leaves and the fibres' sheen with it
  float sh = part == PART_SHADOW ? 1.0 : keyShadow(v_pos, n);
  if (part == PART_ESSENCE) {
    // liquid essence, thick and glossy, in its own colour: lit as anything
    // is, but carrying a light of its own (what the plants condensed);
    // where it flows (v_t 0..1 the way it runs, < 0 still) brighter streaks
    // run along it, and a pale film shines at grazing angles
    float t = pc.eye_time.w;
    float flow = v_t < 0.0 ? 0.0 : pow(0.5 + 0.5 * sin(v_t * TAU * ESSENCE_STREAKS - t * ESSENCE_RUN + v_phase * TAU), 3.0);
    float fres = pow(1.0 - clamp(dot(n, V), 0.0, 1.0), FRESNEL_POW);
    vec3 lit = byDay(NIGHT_LIT, vec3(1.0));
    PointLit pl = pointLights(v_pos, n, reflect(-V, n), true);
    c = shadeLitWith(v_col * 0.5, n, sh, pl.plain);
    c += v_col * v_glow * (0.7 + 1.1 * flow);
    c += mix(v_col, vec3(1.0), 0.5) * fres * 0.5 * lit;
    c += v_col * pl.plain * 0.3;
    c += sapGlistenWith(n, V, v_pos, v_obj, v_col, 0.0, sh, pl.mirrored);
    o = vec4(applyFog(c, v_pos), 1.0);
    return;
  }
  if (part == PART_PRISM) {
    // a cut crystal with no light of its own: each flat facet shades as
    // stone does and reflects a warm iridescent film that shifts with the
    // angle it is seen at and from facet to facet; the sun glints off it
    float ndv = clamp(dot(n, V), 0.0, 1.0);
    float fres = pow(1.0 - ndv, PRISM_FRESNEL_POW);
    vec3 facet = hash33(floor(n * 7.0) + 3.0);
    vec3 film = mix(filmHue(0.08 + 0.9 * ndv + facet.x * 0.35), PRISM_FILM, 0.35);
    float day = DAYLIGHT;
    vec3 lit = byDay(NIGHT_LIT, PRISM_DAY);
    PointLit pl = pointLights(v_pos, n, n, false);
    c = shadeLitWith(v_col * 0.55, n, sh, pl.plain);
    c += film * lit * (0.18 + 0.55 * fres + 0.25 * facet.y * max(dot(n, SUN), 0.0) * sh);
    c += film * pl.plain * 0.5;
    vec3 H = normalize(SUN + V);
    c += lit * pow(max(dot(n, H), 0.0), PRISM_SPEC_POW) * 1.6 * step(0.0, dot(n, SUN)) * sh;
    c += film * fres * mix(0.25, 0.08, day);
    o = vec4(applyFog(c, v_pos), 1.0);
    return;
  }
#ifndef HEAD
  if (part == PART_SHADOW) {
    // a soft shadow on the ground: darkest at its centre, gone at its rim
    float r = clamp(v_t, 0.0, 1.0);
    float a = v_fade * pow(1.0 - r, GROUND_SHADOW_FALLOFF);
    o = vec4(applyFog(GROUND_SHADOW, v_pos), a);
    return;
  }
  if (part == PART_CORTEX) {
    // a ganglion's folded cortex: pale matte tissue, milky and see-through
    // face-on so what it holds shows within, denser at its edges and down
    // its furrows (v_u 0 a fold's crown .. 1 a furrow's floor), which run
    // darker and more violet, so its folds read; the light of what it
    // holds shines through it from inside, and the key light a little
    // from behind. No sheen: it is tissue. Only its near side is drawn.
    if (dot(raw, V) < 0.0) discard;
    float ndv = clamp(dot(n, V), 0.0, 1.0);
    float fres = pow(1.0 - ndv, CORTEX_EDGE_POW);
    float furrow = smoothstep(0.0, 1.0, clamp(v_u, 0.0, 1.0));
    vec3 tissue = mix(v_col, v_col * CORTEX_FURROW, furrow);
    PointLit pl = pointLights(v_pos, n, n, false);
    c = shadeLitWith(tissue, n, sh, pl.plain);
    c += tissue * (pl.behind * CORTEX_THROUGH + max(dot(-n, SUN), 0.0) * 0.2 * sh);
    c += v_col * v_glow * 2.2;
    c += v_col * pow(1.0 - ndv, RIM_POW) * mix(0.35, 0.12, DAYLIGHT);
    alpha = clamp(mix(CORTEX_CLEAR, 1.0, fres) + furrow * CORTEX_FURROW_DENSE, 0.0, 1.0);
    o = vec4(applyFog(c, v_pos), alpha);
    return;
  }
  if (part == PART_HUSK) {
    // a crystal husk (the strange seed's): clear glass, faintly its own
    // colour, each facet catching an iridescent film as it turns edge-on
    // and the sun glinting off it; cracks run over it, glowing with the
    // light of the web inside (thin seams where a noise in its own space
    // crosses nothing). Only its near side is drawn.
    if (dot(raw, V) < 0.0) discard;
    float ndv = clamp(dot(n, V), 0.0, 1.0);
    float fres = pow(1.0 - ndv, PRISM_FRESNEL_POW);
    vec3 facet = hash33(floor(n * 7.0) + 3.0);
    vec3 film = mix(filmHue(0.08 + 0.9 * ndv + facet.x * 0.35), PRISM_FILM, 0.35);
    vec3 lit = byDay(NIGHT_LIT, PRISM_DAY);
    PointLit pl = pointLights(v_pos, n, n, false);
    c = v_col * HUSK_TINT + film * lit * (0.08 + 0.7 * fres) + film * pl.plain * 0.4;
    vec3 H = normalize(SUN + V);
    c += lit * pow(max(dot(n, H), 0.0), PRISM_SPEC_POW) * 1.6 * step(0.0, dot(n, SUN)) * sh;
    float seam = abs(huskNoise(v_obj * HUSK_CRACK_SCALE) - 0.5) + 0.5 * abs(huskNoise(v_obj * HUSK_CRACK_SCALE * 2.3 + 7.0) - 0.5);
    float crack = 1.0 - smoothstep(0.0, HUSK_CRACK_W, seam);
    c += HUSK_CRACK * crack * (0.8 + 0.6 * sin(pc.eye_time.w * 1.3));
    alpha = clamp(HUSK_CLEAR + 0.6 * fres + crack, 0.0, 1.0);
    o = vec4(applyFog(c, v_pos), alpha);
    return;
  }
  if (part == PART_RESIN) {
    // solidified sap (surface.glsl resinSurface): v_u 0 where it meets
    // the body, 1 at its surface; only its outer face is drawn
    if (dot(raw, V) < 0.0) discard;
    o = resinSurface(raw, V, v_pos, v_obj, hue, clamp(v_u, 0.0, 1.0), v_fade, sh);
    return;
  }
  if (part == PART_BLOOM && v_fade < 0.999) {
    // translucent sap sac: dark and see-through at the centre, amber at
    // grazing angles. Only the near side is drawn (it is a closed sac).
    if (dot(raw, V) < 0.0) discard;
    float ndv = clamp(dot(raw, V), 0.0, 1.0);
    float fres = pow(1.0 - ndv, FRESNEL_POW);
    vec3 deep = SAP_DEEP * hue * (0.6 + 0.8 * v_glow);
    PointLit pl = pointLights(v_pos, raw, reflect(-V, raw), true);
    c = shadeLitWith(deep, raw, sh, pl.plain) + mix(deep, SAP * hue * 2.2, pow(1.0 - ndv, SAP_EDGE_POW)) * (0.35 + v_glow);
    c += SAP * hue * pl.wrapped * 0.3;
    alpha = mix(v_fade, 1.0, fres);
    c = sapLife(c, SAP * hue, raw, V, 1.0 - fres, sh, pl.mirrored, alpha);
  } else if (inner_ear && v_fade < 0.999) {
    // the inner ear is a sheet of sap: glowing at grazing angles, faintly
    // see-through face-on (the outer face stays solid vine)
    float ndv = clamp(-dot(raw, V), 0.0, 1.0);
    float fres = pow(1.0 - ndv, FRESNEL_POW);
    vec3 deep = SAP_DEEP * 1.6;
    PointLit pl = pointLights(v_pos, -raw, reflect(-V, -raw), true);
    c = shadeLitWith(deep, -raw, sh, pl.plain) + mix(deep, SAP * 1.8, pow(1.0 - ndv, SAP_EDGE_POW)) * 0.5;
    c += SAP * max(dot(raw, SUN), 0.0) * 0.25 * sh; // light through the ear
    c += SAP * pl.behind * 0.25;
    alpha = mix(v_fade, 1.0, fres);
    c = sapLife(c, SAP, -raw, V, 0.6 * (1.0 - fres), sh, pl.mirrored, alpha);
  } else
#endif
  {
    // a leaf's or petal's own surface: veins, the net between, edge and base
    float trans;
    vec3 albedo = sheetColour(v_col, part, v_sheet, v_t, trans);
    float inner = 0.0;
    if (part == PART_STONE) {
      // weathered stone: its grain lights it, tipping the normal (the
      // surface gradient, from screen derivatives)
      StoneSurface s = stoneSurface(v_col, v_obj, n);
      albedo = s.albedo;
      vec3 dpx = dFdx(v_pos), dpy = dFdy(v_pos);
      vec3 r1 = cross(dpy, n), r2 = cross(n, dpx);
      float det = dot(dpx, r1);
      vec3 grad = sign(det) * (dFdx(s.height) * r1 + dFdy(s.height) * r2);
      n = normalize(abs(det) * n - grad * STONE_BUMP);
    }
    // the inner face of an ear (the side opposite its normal) is sap-lined
    if (part == PART_EAR) {
      inner = dot(raw, V) < 0.0 ? 1.0 : 0.0;
      albedo = mix(albedo, SAP * 0.6, inner * 0.8);
    }
    PointLit pl = pointLights(v_pos, n, n, false);
    c = shadeLitWith(albedo, n, sh, pl.plain);
    // leaves and sap are thin/translucent: back light shines through (a
    // bloom's or a mote's too)
    if (PART_IN(THIN, part)) c += albedo * (max(dot(-n, SUN), 0.0) * 0.3 * sh + pl.behind * 0.3) * trans;
    c += SAP * inner * 0.25;
    // woven strands: a Kajiya-Kay sheen across the tube's tangent so vines
    // read as directional fibres rather than flat facets
    float tl = length(tgrad);
    if (PART_IN(FIBRES, part) && tl > 0.0) c += fibreLight(albedo, byDay(NIGHT_LIT, SUNLIGHT), tgrad, tl, n, V, 0.28, sh);
    c += v_col * v_glow * 2.2;
    // a stem's ridges and fibres grain all its light
    c *= grainOf(part, v_sheet, v_t);
  }
  // rim light keeps the silhouette readable at night
  float rim = pow(1.0 - max(dot(n, V), 0.0), RIM_POW);
  c += v_col * rim * mix(0.35, 0.12, DAYLIGHT);
  o = vec4(applyFog(c, v_pos), alpha);
}

#ifdef AIR
// how strongly what glows lights the air round it, per unit of the air's
// density
const float AIR_GLOW = 3.0;
// the air round what glows (render/passes/parts.zig `air`): drawn into the
// fog's volume, the same light it shines with, spread wider (part.vert
// under AIR), fading out to its edge, and lighting only as much as the air
// there is dense: brighter in the mist, faint in clear air, hidden behind
// what stands in front of it
void main() {
  int part = int(v_part + 0.5);
  if (!PART_IN(PARTS_LIGHT, part)) discard;
  if (gl_FragCoord.z > volumeDepth(ivec2(gl_FragCoord.xy)) + 1e-6) discard;
  surface();
  vec3 V = normalize(pc.eye_time.xyz - v_pos);
  float soft = pow(abs(dot(normalize(v_nrm), V)), 2.0);
  o = vec4(max(o.rgb, 0.0) * clamp(o.a, 0.0, 1.0) * soft * airDensity(v_pos, pc.eye_time.w) * AIR_GLOW, 0.0);
}
#else
void main() {
  surface();
  keepPass(o.a);
}
#endif
