#version 450
//! places library parts (matrix, curve, star mote, skinned) and moves them: growth splines, wind, breath, carried essence, gathering.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
#include "growth.glsl"
// the solid and glass passes rasterize it at the very same depth (the
// glass pass tests `less` against what the solid one wrote)
invariant gl_Position;
#ifndef SHADOW
out float gl_ClipDistance[1];
#endif

// per-vertex (mesh library)
layout(location = 0) in vec3 pos;
layout(location = 1) in vec3 nrm;
layout(location = 2) in vec4 col;
layout(location = 3) in vec2 tu;
layout(location = 4) in uint part;  // 0 vine 1 leaf 2 sap/glow 3 claw/thorn 4 root 5 sap-lined leaf (ear) 6 resin ... 13 a conduit's core
// per-instance
layout(location = 5) in vec4 c0;
layout(location = 6) in vec4 c1;
layout(location = 7) in vec4 c2;
layout(location = 8) in vec4 c3;
layout(location = 9) in vec4 ip;    // glow, flutter, phase, fade
layout(location = 10) in vec4 tint; // rgb multiply, w amount
layout(location = 11) in vec4 iq;   // essence carried along a conduit's core (< 0 none), give (resin surface push)
layout(location = 12) in vec4 iw;   // sway, height of the sway, how far below the origin it is rooted, grown
layout(location = 13) in vec4 ie;   // placement: 0 matrix, 1 curve (tail), 2 star mote; then its parameters
layout(location = 14) in vec4 ih;   // a forming halo it belongs to: its centre, how far along (< 0 none)
layout(location = 15) in uint iflags; // PART_GHOST, ... (vertex.zig)
layout(location = 16) in vec4 ik;   // how far it is blended into its mesh's next key
// per-vertex skin (skinned meshes only): four bone indices, one per byte, and their weights
layout(location = 17) in uint sbones;
layout(location = 18) in vec4 sweights;
// how each of those weights changes across the mesh: its x, y and z
layout(location = 19) in vec4 sgx;
layout(location = 20) in vec4 sgy;
layout(location = 21) in vec4 sgz;
// per-vertex growth (structures grown along growth splines, gfx/growth.zig):
// where it grows out of, and when it begins, how long it takes, when its
// spline began and was done (gat.y 0: not on a spline)
layout(location = 22) in vec3 gfrom;
layout(location = 23) in vec4 gat;
// the same vertex in its mesh's next key (itself where the mesh has none):
// a bud opening blends into it
layout(location = 24) in vec3 kpos;
layout(location = 25) in vec3 knrm;

// iflags: a placement preview (vertex.PART_GHOST)
const uint PART_GHOST = 1u;

// this frame's bones (renderer Scene.bones): each carries a vertex from
// where it was built to where it is now
layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer Bones { mat4 m[]; };
// this vertex's `k`th bone (of four, one index per byte of sbones), its
// mesh's bones starting at `base`
mat4 bone(Bones B, int base, int k) { return B.m[base + int((sbones >> (8u * uint(k))) & 255u)]; }

layout(location = 0) out vec3 v_pos;
layout(location = 1) out vec3 v_nrm;
layout(location = 2) out vec3 v_col;
layout(location = 3) out float v_glow;
layout(location = 4) flat out float v_part;
layout(location = 5) out float v_t;         // position along the part (tube tangent source)
layout(location = 6) flat out float v_fade; // opacity of translucent sap at its centre
layout(location = 7) out float v_u;
layout(location = 8) out vec3 v_obj;       // mesh-space point (sap bubbles ride with the body)
layout(location = 9) flat out float v_phase; // per-instance phase (seeds a beam's motes)
layout(location = 10) flat out float v_aux;  // a beam: 1 for a halo's edge; a flash: its age 0..1

// how an instance is placed (vertex.zig `PartInstance.e.x`; must match)
const int PLACE_MATRIX = 0;
const int PLACE_CURVE = 1;   // along a Catmull-Rom curve (the tail, beams)
const int PLACE_MOTE = 2;    // a star mote
const int PLACE_SKINNED = 3; // by its bones
const int PLACE_BURST = 4;   // a burst flung out where a yield came loose

// how a diamond gathers (common.glsl gatherAway, gatherIn): its facets
// settle PRISM_PACE of the way apart by order, each over PRISM_SPAN,
// drawn in PRISM_REACH along its face, turning PRISM_TURN radians
const float PRISM_PACE = 0.4;
const float PRISM_SPAN = 0.6;
const float PRISM_REACH = 0.45;
const float PRISM_TURN = 3.0;
// a flash spreads out from this share of its size to this many times it
const float FLASH_FROM = 0.1;
const float FLASH_TO = 3.2;
// a star mote: how fast it turns (rad/s), how far its echoes trail above it
const float MOTE_TURN = 0.35;
const float ECHO_RISE = 0.16;
// a burst where a yield came loose (meshes/pluck_burst.zig): its beads'
// radius (mesh space), how far its motes drift up and its drops fall
// over its life (mesh space: the matrix sizes it)
const float BURST_BEAD = 0.11;
const float BURST_RISE = 0.5;
const float BURST_FALL = 1.6;
// sap pulses running along a part (rad/s), and a part's own glow beside a
// glowing sap part's
const float PULSE_RATE = 3.0;
const float DIM_GLOW = 0.06;
// the constellate web (meshes/constellate.zig; PLEXUS_POINTS must match its
// `count`): how many points float in a cluster, which one is its heart (in
// the middle of the spindle), how far each drifts from where it rests and
// how fast (rad/s, slowest and quickest), how big a point is, how wide a
// line, how far a pane's faces sit apart, where a line begins to fade as
// its points part (a share of its reach)
const int PLEXUS_POINTS = 30;
const int PLEXUS_HEART = 15;
const float PLEXUS_DRIFT = 0.13;
// what shape a web holds (meshes/constellate.zig `Shape`): a loose
// cluster, or one of the plant parts a gardener builds with; a part's
// points drift only a little, so it keeps its form
const int PLEXUS_CLUSTER = 0;
const int PLEXUS_PETAL = 1;
const int PLEXUS_LEAF = 2;
const int PLEXUS_BUD = 3;
const int PLEXUS_FLOWER = 4;
const float PLEXUS_PART_DRIFT = 0.025;
// a petal's rows, base to tip: how many points each holds (30 in all)
// and how far along the petal it lies
const int PLEXUS_PETAL_ROWS[8] = int[8](2, 3, 4, 5, 5, 5, 4, 2);
const float PLEXUS_PETAL_ALONG[8] = float[8](0.02, 0.14, 0.28, 0.42, 0.56, 0.7, 0.84, 0.96);
const float PLEXUS_SLOW = 0.12;
const float PLEXUS_QUICK = 0.32;
const float PLEXUS_POINT_R = 0.015;
// each point is a pair of lights circling each other: how far apart they
// are, how much of that the first (the larger) keeps to the middle's far
// side (the smaller swings wider), how big the companion is beside it, how
// fast they circle (rad/s, slowest and quickest)
const float PLEXUS_PAIR = 0.04;
const float PLEXUS_PAIR_LEAN = 0.4;
const float PLEXUS_COMPANION = 0.7;
const float PLEXUS_PAIR_SLOW = 0.6;
const float PLEXUS_PAIR_QUICK = 1.4;
const float PLEXUS_LINE_W = 0.007;
const float PLEXUS_PANE = 0.005;
const float PLEXUS_SOFT = 0.8;

// where constellate point `id` rests in a web of `shape`, each point
// nudged a little off its place so no part is ruled straight
vec3 plexusRest(float id, int shape) {
  vec3 h = hash33(vec3(id, 3.1, 7.7));
  vec3 jit = (h - 0.5) * 0.04;
  if (shape == PLEXUS_PETAL) {
    // a petal: eight rows from its narrow base (two, id 0 the heart) out
    // through its broadest (five) to its round tip (two), cupped and
    // curling back toward its tip; no midrib
    int n = 2;
    float row = 0.0;
    float first = 0.0;
    for (int r = 0; r < 8; r++) {
      n = PLEXUS_PETAL_ROWS[r];
      if (id < first + float(n)) { row = float(r); break; }
      first += float(n);
    }
    float u = PLEXUS_PETAL_ALONG[int(row)];
    float v = n > 1 ? (id - first) / float(n - 1) * 2.0 - 1.0 : 0.0;
    float w = 0.27 * pow(max(sin(0.5 * TAU * min(u, 0.97)), 0.0), 0.6) * (0.4 + 0.6 * u) + 0.025;
    float cup = 0.12 * (1.0 - v * v) * sin(0.5 * TAU * u);
    return vec3(v * w * 0.95, 0.7 + 0.65 * u, 0.3 * u * u - cup) + jit * 0.6;
  }
  if (shape == PLEXUS_LEAF) {
    // a leaf: a midrib of ten from the foot of its stalk (id 0, its
    // heart) to its point, ten down either edge of the blade, which begins
    // a fifth of the way up; it reaches out and up from the stalk, its
    // edges folded a little up from the midrib, widest a third of the way
    // along its blade and drawn to a point
    float side = id < 10.0 ? 0.0 : (id < 20.0 ? -1.0 : 1.0);
    float k = id < 10.0 ? id : mod(id - 10.0, 10.0);
    float ub = id < 10.0 ? max(k / 9.0 - 0.2, 0.0) / 0.8 : (k + 0.5) / 10.0;
    float u = id < 10.0 ? k / 9.0 : 0.2 + 0.8 * ub;
    float w = 0.24 * pow(sin(0.5 * TAU * ub), 0.75) * (1.0 - 0.35 * ub);
    vec3 c = vec3(0.0, 0.55 + 0.75 * u - 0.25 * u * u, 0.6 * u);
    vec3 up = normalize(vec3(0.0, 0.6, -(0.75 - 0.5 * u)));
    return c + vec3(side * w, 0.0, 0.0) + up * abs(side) * w * 0.3 + jit * 0.4;
  }
  if (shape == PLEXUS_BUD) {
    // a bud: closed, a teardrop of points wound in a golden spiral from
    // its base (id 0) to its tip (the last)
    float u = id / float(PLEXUS_POINTS - 1);
    float a = id * 2.39996;
    float r = 0.17 * pow(sin(0.5 * TAU * pow(u, 0.75)), 0.9);
    return vec3(cos(a) * r, 0.75 + 0.55 * u, sin(a) * r) + jit * 0.5;
  }
  if (shape == PLEXUS_FLOWER) {
    // a flower head, open: its heart (id 0) in the middle of a domed disc
    // of nine, five petals of four round it (base, two flanks, tip),
    // cupped up toward their tips
    if (id < 0.5) return vec3(0.0, 1.13, 0.0);
    if (id < 9.5) {
      float a = (id - 1.0) / 9.0 * TAU;
      return vec3(cos(a) * 0.075, 1.1 + 0.015 * mod(id, 2.0), sin(a) * 0.075) + jit * 0.3;
    }
    float p = floor((id - 10.0) / 4.0);
    float k = mod(id - 10.0, 4.0);
    float r = k < 0.5 ? 0.18 : (k < 2.5 ? 0.3 : 0.42);
    float off = k < 0.5 || k > 2.5 ? 0.0 : (k < 1.5 ? -0.22 : 0.22);
    float a = p / 5.0 * TAU + off;
    float lift = 0.15 * (r / 0.42) * (r / 0.42);
    return vec3(cos(a) * r, 1.0 + lift, sin(a) * r) + jit * 0.5;
  }
  // a loose cluster: an upright spindle of them, widest in the middle,
  // from knee height to over the wolf's head
  float up = id / float(PLEXUS_POINTS - 1);
  float wide = 0.2 + 0.4 * sin(0.5 * TAU * up);
  float a = h.x * TAU;
  float r = wide * mix(0.35, 1.0, h.y);
  return vec3(cos(a) * r, 0.5 + 1.2 * up + (h.z - 0.5) * 0.12, sin(a) * r);
}
// which point is the heart of a web of `shape`, where its beat starts: the
// spindle's middle, a petal's base, a leaf's stalk, a bud's base, a flower
// head's middle
float plexusHeart(int shape) { return shape == PLEXUS_CLUSTER ? float(PLEXUS_HEART) : 0.0; }
// where it is at time `t`: drifting round its rest, each axis on two slow
// waves of its own (a part only a little, keeping its form)
vec3 plexusAt(float id, int shape, float t) {
  vec3 f = mix(vec3(PLEXUS_SLOW), vec3(PLEXUS_QUICK), hash33(vec3(id, 11.3, 2.9)));
  vec3 g = mix(vec3(PLEXUS_SLOW), vec3(PLEXUS_QUICK), hash33(vec3(id, 5.7, 19.1)));
  vec3 ph = hash33(vec3(id, 23.9, 1.3)) * TAU;
  vec3 d = 0.6 * sin(t * f + ph) + 0.4 * sin(t * g * 1.7 + ph.yzx * 2.0);
  float drift = shape == PLEXUS_CLUSTER ? PLEXUS_DRIFT : PLEXUS_PART_DRIFT;
  return plexusRest(id, shape) + drift * d * vec3(1.0, 0.6, 1.0);
}
// how much a line between `a` and `b` shows: whole within its reach's
// soft edge, gone beyond its reach
float plexusLink(vec3 a, vec3 b, float reach) { return 1.0 - smoothstep(reach * PLEXUS_SOFT, reach, length(b - a)); }
// where one light of point `id`'s pair is at time `t` (`twin` 1 the first,
// -1 its companion): circling the other round where the point has drifted
// to, each pair about an axis and at a pace of its own
vec3 plexusLight(float id, int shape, float t, float twin) {
  vec3 h = hash33(vec3(id, 41.7, 13.3));
  vec3 axis = normalize(h - 0.5 + vec3(0.0, 0.6, 0.0));
  vec3 side = normalize(cross(axis, abs(axis.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
  float spin = t * mix(PLEXUS_PAIR_SLOW, PLEXUS_PAIR_QUICK, h.z) + h.x * TAU;
  vec3 orbit = side * cos(spin) + cross(axis, side) * sin(spin);
  return plexusAt(id, shape, t) + orbit * PLEXUS_PAIR * twin * mix(1.0 - PLEXUS_PAIR_LEAN, PLEXUS_PAIR_LEAN, step(0.0, twin));
}
// a conduit's amber pulses: how fast they run (rad/s)
const float CORE_RUN_RATE = 2.6;
// thought climbing an arsthraxia's nerves: its colour (linear violet), how
// many pulses along a nerve at once, how fast they climb (rad/s), how long
// the surge of a unit done is (a share of the nerve)
const vec3 THOUGHT = vec3(0.42, 0.2, 1.0);
const float NERVE_PULSES = 3.0;
const float NERVE_RISE = 7.0;
const float NERVE_SURGE_W = 0.08;
// a stream of essence poured into a germinator's core: how far it ripples
// off its fall at the bottom
const float POUR_RIPPLE = 0.012;
// research energy's core quivers by this share of its size, more as it flares
const float ENERGY_QUIVER = 0.04;
const float ENERGY_QUIVER_FLARE = 0.12;
// the roles that are a structure's foliage (leaves, an ear): they unfold as
// it grows and breathe and lift in the wind
const uint FOLIAGE = PART_BIT(PART_LEAF) | PART_BIT(PART_EAR);
// grown along a growth spline (growth.glsl): how far into its own growth a
// leaf's tip lags its base
const float LEAF_LAG = 0.6;

// Catmull-Rom through b..c (a, d the neighbours) at f, and its tangent
vec3 catmull(vec3 a, vec3 b, vec3 c, vec3 d, float f) {
  return 0.5 * (2.0 * b + (c - a) * f + (2.0 * a - 5.0 * b + 4.0 * c - d) * f * f + (3.0 * b - a - 3.0 * c + d) * f * f * f);
}
vec3 catmullTan(vec3 a, vec3 b, vec3 c, vec3 d, float f) {
  return 0.5 * ((c - a) + 2.0 * (2.0 * a - 5.0 * b + 4.0 * c - d) * f + 3.0 * (3.0 * b - a - 3.0 * c + d) * f * f);
}

void main() {
  float t = pc.eye_time.w;
  int mode = int(ie.x + 0.5);
  mat4 M = mat4(c0, c1, c2, c3);
  // a skinned mesh: its vertex goes where its bones, blended by weight, take it
  if (mode == PLACE_SKINNED) {
    Bones B = Bones(pc.bones);
    int base = int(ie.y + 0.5);
    M = mat4(0.0);
    for (int k = 0; k < 4; k++) M += sweights[k] * bone(B, base, k);
  }
  // blended into its next key's shape (a bud opening, petal by petal)
  vec3 p = mix(pos, kpos, ik.x);
  vec3 nm = ik.x > 0.0 ? normalize(mix(nrm, knrm, ik.x)) : nrm;
  // grown along a growth spline (growth.glsl): a leaf unfolds from its
  // base, tips last
  float lag = PART_IN(FOLIAGE, part) ? LEAF_LAG * gat.y * tu.y : 0.0;
  p = growOut(p, gfrom, gat, iw.w, lag);
  // the belly (tu.y 3, its button 4; fill in iq.y): as it fills, creases
  // fold into it down its middle and across it, deepening the fuller it
  // is (in the bind pose, before the gut swells it, so they swell with
  // it; iq.zw the y and z where they cross, at its button). A smooth
  // field pushed in along the sac's normal, the normal turned by its
  // slope so the folds catch the light. The button surfaces from inside
  // the sap and pops out past it.
  if (tu.y > 2.5 && tu.y < 4.5) {
    const float CREASE = 0.024;  // depth when full
    const float DOWN_W = 0.019;  // the crease down the middle: its width
    const float ACROSS_W = 0.017; // the crease across it
    const float POP = 0.03;
    float fill = clamp(iq.y, 0.0, 1.0);
    vec3 d = p - vec3(0.0, iq.z, iq.w);
    // down the front, fading toward the ribs; across the front and sides
    float gv = exp(-d.x * d.x / (DOWN_W * DOWN_W)) * smoothstep(-0.02, 0.05, d.z) * (1.0 - smoothstep(0.06, 0.13, d.y));
    float gh = exp(-d.y * d.y / (ACROSS_W * ACROSS_W)) * smoothstep(-0.08, 0.02, d.z);
    float g = gv + gh - gv * gh;
    vec3 slope = vec3(-2.0 * d.x / (DOWN_W * DOWN_W) * gv * (1.0 - gh), -2.0 * d.y / (ACROSS_W * ACROSS_W) * gh * (1.0 - gv), 0.0);
    float depth = CREASE * fill;
    if (tu.y > 3.5) {
      p.z += POP * pow(fill, 1.5) - depth;
    } else {
      p -= nrm * depth * g;
      nm = normalize(nrm + depth * (slope - nrm * dot(slope, nrm)));
    }
  }
  // a conduit's living core (part 13, tu.x 0 where it comes up out of the
  // soil .. 1 where it goes back down): essence carried through it (iq.x
  // how far along, < 0 none; ie.yzw its colour) swells it as it passes,
  // pushing out between the strands woven round it, and leaves a fading
  // wake behind. A smooth field along it, so shared vertices move alike.
  float carried = 0.0;
  float wake = 0.0;
  if (part == PART_CORE && mode == PLACE_MATRIX && iq.x >= 0.0) {
    const float CARRY_W = 0.075; // how long a stretch the essence fills
    const float SWELL = 0.022;
    const float WAKE = 0.2;
    float d = tu.x - iq.x;
    carried = exp(-d * d / (CARRY_W * CARRY_W));
    wake = d < 0.0 ? exp(d / WAKE) * (1.0 - carried) : 0.0;
    p += nrm * SWELL * carried;
  }
  // secondary motion. Offsets must be identical for every copy of a shared
  // vertex (faceted parts carry different normals per face), so they use a
  // fixed axis scaled by position along the leaf: tips move, bases stay put.
  float sway = iw.x;
  vec4 wind = gardenWind(t, c3.xz);
  // grown structures move as the plants do: leaves and petals breathe
  // slowly and lift a little in the gusts, tips most, bases held
  bool foliage = PART_IN(FOLIAGE, part);
  if (sway > 0.0 && foliage) {
    p.y += tu.y * tu.y * (LEAF_LIFT * wind.z * sin(t * LEAF_LIFT_RATE + ip.z * 11.0 + tu.x * 3.0) + 0.01 * sin(t * 0.9 + ip.z * TAU));
  } else if (foliage) p.y += 0.03 * ip.y * tu.y * tu.y * sin(t * 7.0 + ip.z * 40.0 + tu.y * 2.0);
  if (part == PART_TENDRIL) p.y += 0.006 * sin(t * 2.0 + ip.z * 20.0 + tu.x * 9.0);
  // resin gives like dense gel: its surface follows the spring, its base on
  // the body holds (a smooth field of height, so shared vertices move alike)
  if (part == PART_RESIN) p += iq.yzw * smoothstep(0.0, 1.0, tu.y);
  bool drawn = ih.w >= 0.0;
  // the halo's diamond is gathered as its blooms close in (how far they
  // have come, haloPull), the radiant way (common.glsl gatherIn): its
  // facets come in as shards turning round it, each drawn in along its
  // face and growing as it comes, one after another from its foot up,
  // fitting together as the blooms meet; then it is still
  if (part == PART_PRISM && drawn) {
    float away = gatherAway(fragmentOf(tu, col.a).order, PRISM_PACE, PRISM_SPAN, sqrt(haloPull(ih.w)));
    p = gatherIn(p, nrm * PRISM_REACH, away, 1.0, PRISM_TURN);
    nm = gatherTurn(nm, away, PRISM_TURN);
  }
  // the flash where the blooms met: a disc of light (tu.x its radius
  // 0..1) thrown outward from the diamond, fast then slowing (age 0..1)
  if (part == PART_FLASH) p.xz *= mix(FLASH_FROM, FLASH_TO, 1.0 - pow(1.0 - clamp(ip.y, 0.0, 1.0), 3.0));
  // a stream of essence poured along a curve (a germinator's): its fade is
  // how full it runs, and it ripples as it falls, more the further from
  // the lip (a smooth field along it, so shared vertices move alike)
  if (part == PART_ESSENCE && mode == PLACE_CURVE) {
    float k = clamp(p.y, 0.0, 1.0);
    p.xz *= ip.w;
    p.x += POUR_RIPPLE * k * sin(k * 13.0 - t * 9.0 + ip.z * TAU);
    p.z += POUR_RIPPLE * 0.7 * k * sin(k * 10.0 - t * 7.0 + ip.z * 17.0);
  }

  // research energy condensing in an arsthraxia's core (matrix-placed;
  // its wisps are curves): it quivers, a smooth field of its rest position
  // so shared vertices move alike, harder as it flares (flutter)
  if (part == PART_ENERGY && mode == PLACE_MATRIX) {
    float q = sin(t * 6.3 + dot(pos, vec3(5.0, 7.0, 3.0)) + ip.z * TAU) * sin(t * 4.1 - dot(pos, vec3(3.0, -4.0, 6.0)));
    p *= 1.0 + (ENERGY_QUIVER + ENERGY_QUIVER_FLARE * ip.y) * q;
  }
  vec4 w;
  vec3 wn;
  float twinkle = 1.0;
  // the constellate web: how far its beat runs to reach here (from its
  // heart, straight across), how much of it shows, what it is
  float plexBeat = 0.0;
  float plexFade = 1.0;
  float plexKind = 0.0;
  float plexLayer = 0.0;
  if (part == PART_PLEXUS) {
    // its points (colour r, g, b their ids), what it is (alpha), the
    // cluster's reach (pos.x); for a line or pane, which layer of the web
    // (pos.z: 0 the firsts', 1 the companions', each joining only its own
    // lights); every point drifting, the heart among them
    vec3 ids = floor(col.rgb * 255.0 + 0.5);
    float code = floor(col.a * 255.0 + 0.5);
    plexKind = mod(code, 4.0);
    // what shape the web holds (alpha's high part)
    int shape = int(code / 4.0);
    float reach = pos.x;
    float twin = plexKind < 0.5 ? pos.y : 1.0 - 2.0 * pos.z;
    plexLayer = step(twin, 0.0);
    vec3 A = plexusLight(ids.x, shape, t, twin);
    vec3 B = plexusLight(ids.y, shape, t, twin);
    vec3 C = plexusLight(ids.z, shape, t, twin);
    vec3 H = plexusAt(plexusHeart(shape), shape, t);
    // how thin this layer's lines are: the companions' as their lights
    float thin = mix(PLEXUS_COMPANION, 1.0, step(0.0, twin));
    vec3 lp;
    if (plexKind < 0.5) {
      // a point: one light of its pair (pos.y 1 the first, -1 its
      // companion, the smaller)
      lp = A + nrm * PLEXUS_POINT_R * thin;
      w = M * vec4(lp, 1.0);
      wn = mat3(M) * nrm;
    } else if (plexKind < 1.5) {
      // a line (tu.x along it, tu.y which side): a ribbon turned to the
      // eye, pointed at both ends, thinning to nothing as its points part
      plexFade = plexusLink(A, B, reach);
      lp = mix(A, B, tu.x);
      vec3 wc = (M * vec4(lp, 1.0)).xyz;
      vec3 T = mat3(M) * (B - A);
      vec3 toEye = normalize(pc.eye_time.xyz - wc);
      vec3 across = cross(T, toEye);
      vec3 right = across / max(length(across), 1e-6);
      float pinch = sqrt(max(sin(0.5 * TAU * tu.x), 0.0));
      w = vec4(wc + right * tu.y * PLEXUS_LINE_W * thin * pinch * plexFade, 1.0);
      wn = toEye;
    } else {
      // a pane (tu its corner's weights, pos.y its face): it shows while
      // all three of its lines do, drawn in toward its middle as any of
      // them breaks
      plexFade = min(min(plexusLink(A, B, reach), plexusLink(A, C, reach)), plexusLink(B, C, reach));
      vec3 mid = (A + B + C) / 3.0;
      vec3 corner = A * tu.x + B * tu.y + C * (1.0 - tu.x - tu.y);
      vec3 cr = cross(B - A, C - A);
      vec3 n = cr / max(length(cr), 1e-6) * pos.y;
      lp = mid + (corner - mid) * 0.85 * plexFade + n * PLEXUS_PANE;
      w = M * vec4(lp, 1.0);
      wn = mat3(M) * n;
    }
    plexBeat = length(lp - H);
  } else if (mode == PLACE_CURVE) {
    // a curve (the tail): the mesh runs straight up +Y over 0..1; each point
    // goes to that fraction along the Catmull-Rom curve through c0..c3 (the
    // ends extended in line), its x laid toward the side (tint.xyz) and its
    // z across, so the vine bends here instead of being rebuilt each frame
    vec3 P[4] = vec3[4](c0.xyz, c1.xyz, c2.xyz, c3.xyz);
    // a beam from a bloom a forming halo draws in follows it: its ends
    // (ie.z 1 first, 2 last) spiral with the bloom, the points between by
    // how near they lie to it
    if (drawn) {
      int ends = int(ie.z + 0.5);
      float w0 = (ends & 1) != 0 ? 1.0 : 0.0;
      float w3 = (ends & 2) != 0 ? 1.0 : 0.0;
      for (int k = 0; k < 4; k++) P[k] = mix(P[k], haloSpiral(P[k], ih.xyz, ih.w), mix(w0, w3, float(k) / 3.0));
    }
    // how far along it reaches (a bloom thread extends as its bloom finishes)
    float u = clamp(p.y, 0.0, ie.y) * 3.0;
    int i = min(int(u), 2);
    float f = u - float(i);
    vec3 b = P[i], c = P[i + 1];
    vec3 a = i == 0 ? 2.0 * b - c : P[i - 1];
    vec3 d = i == 2 ? 2.0 * c - b : P[i + 2];
    vec3 T = normalize(catmullTan(a, b, c, d, f));
    vec3 C = catmull(a, b, c, d, f);
    if (part == PART_THREAD) {
      // soft rays: a spindle of light, narrow where it leaves one bloom and
      // reaches the other, widest between, its width (x, -1..1) turned to
      // face the eye from every side
      vec3 toEye = normalize(pc.eye_time.xyz - C);
      vec3 right = normalize(cross(T, toEye) + vec3(1e-5, 0.0, 0.0));
      // a halo's edge (flutter 1) runs even from corner to corner, so the
      // edges join into one ring
      float spindle = ip.y > 0.5 ? 0.7 : mix(0.3, 1.0, pow(sin(0.5 * TAU * clamp(tu.x, 0.0, 1.0)), 0.6));
      w = vec4(C + right * p.x * BEAM_HALF_WIDTH * spindle, 1.0);
      wn = toEye;
    } else {
      vec3 B = normalize(tint.xyz - T * dot(tint.xyz, T));
      vec3 N = cross(B, T);
      w = vec4(C + B * p.x + N * p.z, 1.0);
      // the mesh was squeezed to 0..1 along its length: undo that on its normals
      wn = B * nrm.x + T * (nrm.y / ie.w) + N * nrm.z;
    }
  } else if (mode == PLACE_BURST) {
    // a burst (ie.y how far through its life, 0..1): each bead flies out
    // the way it lies (its centre a radius in from its skin), fast then
    // slowing; motes of light (tu.y below 0.5) drift up, drops of sap arc
    // down; each its own pace (tu.y), all swelling in at once and shrinking
    // away over the burst's life
    float age = clamp(ie.y, 0.0, 1.0);
    bool drop = tu.y >= 0.5;
    float pace = mix(0.65, 1.3, fract(tu.y * 2.0));
    vec3 c = pos - nrm * BURST_BEAD;
    vec3 at = c * (1.0 - pow(1.0 - age, 3.0)) * pace;
    at.y += drop ? -BURST_FALL * age * age : BURST_RISE * age * pace;
    float size = (1.0 - age) * (drop ? 1.0 : 0.65) * smoothstep(0.0, 0.06, age);
    w = M * vec4(at + nrm * BURST_BEAD * size, 1.0);
    wn = mat3(M) * nrm;
  } else if (mode == PLACE_MOTE) {
    // a star mote: it turns slowly, tilts, twinkles and, resting, hovers
    // with a slow breath; falling, its echoes (ie.w 1..3) trail above it,
    // fading and shrinking
    float ph = ie.y;
    float echo = ie.w;
    twinkle = 0.75 + 0.25 * sin(t * 3.1 + ph * 40.0) * sin(t * 1.7 + ph * 13.0);
    float turn = t * MOTE_TURN + ph * TAU - max(echo, 0.0) * 0.3;
    float tilt = echo > 0.5 ? 0.0 : 0.25 * sin(t * 0.5 + ph * 9.0);
    float size = (0.55 + 0.55 * ie.z) * (0.9 + 0.1 * twinkle) * (1.0 - 0.22 * max(echo, 0.0));
    float hover = echo < 0.0 ? 0.05 * sin(t * 1.1 + ph * 30.0) : 0.0;
    mat3 R = mat3(cos(turn), 0.0, -sin(turn), 0.0, 1.0, 0.0, sin(turn), 0.0, cos(turn))
           * mat3(cos(tilt), sin(tilt), 0.0, -sin(tilt), cos(tilt), 0.0, 0.0, 0.0, 1.0);
    w = vec4(c3.xyz + vec3(0.0, hover + ECHO_RISE * max(echo, 0.0), 0.0) + R * p * size, 1.0);
    wn = R * nrm;
    if (echo > 0.5) twinkle = 1.0;
  } else {
    w = M * vec4(p, 1.0);
#ifdef SHADOW
    // a shadow caster needs no normals
    wn = nm;
    if (false) {
#else
    if (mode == PLACE_SKINNED) {
#endif
      // a skinned mesh's bones may swell it unevenly (the belly): its
      // normals take the inverse-transpose of how the skin truly moves
      // there, the blended bones plus where each bone would take this
      // point times how fast its weight changes across the skin (without
      // that, where a swollen sac hangs from the body the normals turn
      // away from a surface still facing the eye)
      Bones B = Bones(pc.bones);
      int base = int(ie.y + 0.5);
      mat3 J = mat3(M);
      // (where each bone would take it, from where the blend does: the
      // slopes need not sum to nothing once the slightest bones are
      // dropped, and the wolf's place in the world must not leak in)
      vec4 hp = vec4(p, 1.0);
      for (int k = 0; k < 4; k++) {
        vec3 at = (bone(B, base, k) * hp).xyz - w.xyz;
        J += mat3(at * sgx[k], at * sgy[k], at * sgz[k]);
      }
      wn = transpose(inverse(J)) * nm;
    } else wn = mat3(M) * nm;
    // a shadow under a bloom a forming halo draws in follows it over the
    // ground (fading as the bloom folds, below)
    if (drawn && part == PART_SHADOW) w.xz += haloSpiral(c3.xyz, ih.xyz, ih.w).xz - c3.xz;
  }
  // ... and bend from their root in the garden's wind, as the plants do:
  // more toward the top, the lean slow and late at the tip (a smooth field
  // of world height, so shared vertices move alike)
  if (sway > 0.0) {
    vec3 root = c3.xyz - vec3(0.0, iw.z, 0.0);
    float h = clamp((w.y - root.y) / iw.y, 0.0, 1.5);
    float ang = windLean(t, wind, ip.z * TAU, h, sway) * h * h;
    w.xyz = root + bendIn(w.xyz - root, wind.xy, ang);
    wn = bendIn(wn, wind.xy, ang);
  }
  v_pos = w.xyz;
  v_nrm = normalize(wn);
  vec3 c = srgb2lin(col.rgb);
  // (the ring's tint is its points' light, not a colour)
  v_col = (mode == PLACE_CURVE || part == PART_HALO) ? c : mix(c, c * tint.rgb, tint.w);
  // essence is the colour of what it is (sRGB; along a curve in iq.yzw)
  if (part == PART_ESSENCE) v_col = c * srgb2lin(clamp(mode == PLACE_CURVE ? iq.yzw : tint.rgb, 0.0, 1.0));
  // sap pulses travel along the part
  float pulse = 0.65 + 0.35 * sin(t * PULSE_RATE - tu.x * 8.0 + ip.z * TAU);
  v_glow = ip.x * ((part == PART_BLOOM || part == PART_THREAD) ? 1.0 : DIM_GLOW) * pulse * twinkle;
  // a flash, a halo's projection and research energy shine as bright as
  // their glow, never pulsing; a prism has no light of its own
  if (part == PART_FLASH || part == PART_PROJECTION || part == PART_ENERGY) v_glow = ip.x;
  // the ring: an arc is as bright as the points at its ends (tint holds
  // the four points' light, east, south, west, north; tu.x its angle)
  if (part == PART_HALO) {
    float a = fract(tu.x) * 4.0;
    int i = int(a) % 4;
    v_glow = mix(tint[i], tint[(i + 1) % 4], fract(a));
  }
  if (part == PART_PRISM) v_glow = 0.0;
  // essence carries as much light of its own as its glow, never pulsing
  if (part == PART_ESSENCE) v_glow = ip.x;
  // a conduit's core: its sap forever runs the way it carries, in faint
  // amber pulses (brighter while it is busy, ip.x); essence carried
  // through it takes it over in its own colour, its wake fading behind
  if (part == PART_CORE) {
    float run = pow(0.5 + 0.5 * sin(tu.x * TAU * 2.0 - t * CORE_RUN_RATE + ip.z * TAU), 6.0);
    v_col = mix(v_col, AMBER * 0.8, run * 0.6);
    v_col = mix(v_col, srgb2lin(clamp(ie.yzw, 0.0, 1.0)), max(carried, wake * 0.6));
    v_glow = run * (0.1 + 0.2 * ip.x) + carried * 0.55 + wake * 0.2;
  }
  // an arsthraxia's nerve (tu.x 0 at its roots .. 1 at its crown, or out
  // along an offshoot): while it studies (ip.x) thought climbs it in violet
  // pulses, and a unit done (ip.y, 1 fading to 0) sends one surge up it from
  // the roots, its front climbing as the flare fades. At rest, dark wood.
  if (part == PART_NERVE) {
    float study = clamp(ip.x, 0.0, 1.0);
    float rise = pow(0.5 + 0.5 * sin(tu.x * TAU * NERVE_PULSES - t * NERVE_RISE + ip.z * TAU), 6.0) * study;
    float front = tu.x - (1.0 - ip.y);
    float surge = ip.y > 0.0 ? exp(-front * front / (NERVE_SURGE_W * NERVE_SURGE_W)) * sqrt(ip.y) : 0.0;
    float lit = max(rise, surge);
    v_col = mix(v_col, THOUGHT, lit * 0.85);
    v_glow = rise * 0.45 + surge * 1.1 + study * 0.03;
  }
  v_part = float(part);
  v_t = tu.x;
  // a beam carries its length instead, so its rays and motes keep their size
  v_fade = part == PART_THREAD ? length(c3.xyz - c0.xyz) : ip.w;
  // the halo's ring and its projection carry their radius (their scale)
  if (part == PART_HALO || part == PART_PROJECTION) v_fade = length(c0.xyz);
  if (drawn && part == PART_SHADOW) v_fade *= 1.0 - haloFold(ih.w);
  v_u = tu.y;
  // the constellate web carries how far its beat runs to reach here, what
  // it is, and how much of it shows (as its glow)
  if (part == PART_PLEXUS) {
    v_t = plexBeat;
    // what it is, and 4 more on the companions' layer
    v_u = plexKind + 4.0 * plexLayer;
    v_glow = plexFade;
  }
  v_obj = p;
  v_phase = ip.z;
  v_aux = ip.y;
  // the halo's ring and the rays making it appear as its diamond forms
  // (from its shards, as its blooms close in)
  if (part == PART_HALO || part == PART_PROJECTION) v_aux = drawn ? sqrt(haloPull(ih.w)) : 1.0;
  gl_Position = project(w.xyz);
#ifndef SHADOW
  // a skinned mesh may hide what some of its bones carry (the wolf's head,
  // seen from its own eyes): ie.zw a mask of bones, 24 to a float. Clipped
  // where those bones carry it more than half, so the cut follows the skin
  // weights, clean across the mesh; its shadow is still cast.
  float hidden = 0.0;
  if (mode == PLACE_SKINNED && ie.z + ie.w > 0.0) {
    for (int k = 0; k < 4; k++) {
      uint b = (sbones >> (8u * uint(k))) & 255u;
      uint word = b < 24u ? uint(ie.z) : uint(ie.w);
      hidden += sweights[k] * float((word >> (b % 24u)) & 1u);
    }
  }
  gl_ClipDistance[0] = 0.5 - hidden;
#endif
#ifdef SHADOW
  // what is light itself casts no shadow (a star mote, PARTS_LIGHT: a beam,
  // a halo's flash, ring and rays), nor does the soft shadow under a floater
  // or a placement preview
  if (mode == PLACE_MOTE || mode == PLACE_BURST || part == PART_SHADOW || PART_IN(PARTS_LIGHT, part) || (iflags & PART_GHOST) != 0u) gl_Position = UNSEEN;
#endif
}

