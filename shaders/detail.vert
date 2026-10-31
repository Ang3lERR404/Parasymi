#version 450
//! ground detail grown per tile from one DetailTile: curved grass blades as thick as the ground is grassy, and clods and stones on soil.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
#include "ground.glsl"

// The ground's detail, grown here from one record per tile (DetailTile). On
// soil, a clod heaped up and a small pebble half sunk in it, each a
// rounded lump, smoothly shaded (the first 192 vertices). Then up to 96 grass blades in tufts of six,
// each a curved, tapering blade of three bands fanning out from its tuft's
// heart: they grow as thick as the ground beneath
// them is grassy (its kinds melted together exactly as terrain.frag melts
// them, so grass thins and frays across borders with the ground's own
// look), shorter where it thins, coloured dark at the root and pale at the
// tip by the ground they rise from, and sway in the garden wind. Far off,
// fewer and wider. What a tile does not use folds to nothing outside the
// view. All placement is hashed from the tile's position, so a tile always
// grows the same.

layout(location = 0) in vec3 at;      // tile corner x, centre height, corner z
layout(location = 1) in vec4 corners; // corner heights (x0,z0) (x0,z1) (x1,z1) (x1,z0)
layout(location = 2) in vec4 col;
layout(location = 3) in vec4 info;    // kind/255, ley, -, -
layout(location = 4) in vec4 k00;     // the ground's kinds (soil, moss, stone, ley) at corner (x0,z0)
layout(location = 5) in vec4 k01;     // (at (x0,z1))
layout(location = 6) in vec4 k11;     // (at (x1,z1))
layout(location = 7) in vec4 k10;     // (at (x1,z0))
layout(location = 8) in vec4 kc;      // (at the centre)

layout(location = 0) out vec3 v_pos;
layout(location = 1) out vec3 v_nrm;
layout(location = 2) out vec3 v_col;
layout(location = 3) out vec4 v_info;
layout(location = 4) out vec4 v_mat; // the ground's kinds: unused off the ground

// vertices the lumps take, then the grass: how many blades at most, and the
// vertices each runs (two bands of two triangles, a tip of one)
const int LUMP_VERTS = 192;
// corners round each ring of a lump, and the vertices a lump runs (a band
// of two triangles a side, a crown and a bottom of one)
const int LUMP_SIDES = 8;
const int LUMP_ONE = LUMP_SIDES * 4 * 3;
const int BLADES = 96;
// blades to a tuft, and how far from its heart they rise
const int TUFT = 6;
const float TUFT_REACH = 0.07;
const int BLADE_VERTS = 15;
// a grass blade: how long it grows (min, max), its half width at the root,
// how far it arches over along its lean
const float BLADE_MIN = 0.1;
const float BLADE_MAX = 0.3;
const float BLADE_HALF_WIDTH = 0.022;
const float BLADE_ARCH = 0.45;
// how thick grass grows on each kind of ground (soil, moss, stone, ley)
const vec4 GRASS_DENSITY = vec4(0.0, 1.0, 0.25, 0.8);
// far off: from how far (world units from the eye) grass thins, to how far
// it is thinnest, the share of blades kept there, and how much wider they grow
const float GRASS_NEAR = 9.0;
const float GRASS_FAR = 26.0;
const float GRASS_FAR_SHARE = 0.3;
const float GRASS_FAR_WIDEN = 1.8;
// how much a blade's normal leans to the sky (so both its faces catch light,
// as thin grass does)
const float BLADE_SKYWARD = 0.55;
// grass on each kind of ground, root and tip (sRGB): moss's green, ley's
// violet-tinged, stone's grey-green; the share of blades with dry, straw tips
const vec3 MOSS_GRASS_ROOT = vec3(0.07, 0.15, 0.07);
const vec3 MOSS_GRASS_TIP = vec3(0.40, 0.55, 0.22);
const vec3 LEY_GRASS_ROOT = vec3(0.11, 0.09, 0.19);
const vec3 LEY_GRASS_TIP = vec3(0.47, 0.42, 0.64);
const vec3 STONE_GRASS_ROOT = vec3(0.12, 0.14, 0.11);
const vec3 STONE_GRASS_TIP = vec3(0.45, 0.49, 0.36);
const vec3 STRAW = vec3(0.62, 0.56, 0.33);
const float STRAW_SHARE = 0.12;
// grass in the wind: its own sway (rad/s, phase per unit along the wind),
// the gust's push and its own sway's reach (this much even in a calm)
const WindResponse GRASS = WindResponse(1.4, 0.4, 0.09, 0.035, 0.4);
// how far a bent blade sinks (per bend squared)
const float GRASS_DROOP = 0.3;
// the share of soil tiles bare of clods and stones
const float SOIL_BARE = 0.35;
// a stone's grey (sRGB)
const vec3 STONE_GREY = vec3(0.42, 0.4, 0.38);

float hash13(vec3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.zyx + 31.32);
  return fract((p.x + p.y) * p.z);
}

// a value at (fx, fz) within the tile, from its corners and centre across
// the fan of four triangles the ground is built of (terrain_mesh.zig)
vec4 fanAt(vec4 c00, vec4 c01, vec4 c11, vec4 c10, vec4 c, float fx, float fz) {
  vec2 d = vec2(fx, fz) - 0.5;
  // which triangle of the fan, and how far toward its two corners
  vec2 a = abs(d);
  if (a.x >= a.y) {
    vec4 e0 = d.x < 0.0 ? c00 : c10;
    vec4 e1 = d.x < 0.0 ? c01 : c11;
    float s = a.x * 2.0;               // 0 at centre .. 1 at the edge
    float v = s > 0.0 ? (d.y / a.x) * 0.5 + 0.5 : 0.5;
    return mix(c, mix(e0, e1, v), s);
  }
  vec4 e0 = d.y < 0.0 ? c00 : c01;
  vec4 e1 = d.y < 0.0 ? c10 : c11;
  float s = a.y * 2.0;
  float v = s > 0.0 ? (d.x / a.y) * 0.5 + 0.5 : 0.5;
  return mix(c, mix(e0, e1, v), s);
}

// the ground's height at (fx, fz) within the tile
float groundAt(float fx, float fz) {
  return fanAt(vec4(corners.x), vec4(corners.y), vec4(corners.z), vec4(corners.w), vec4(at.y), fx, fz).x;
}

void hide() {
  gl_Position = vec4(0.0, 0.0, -2.0, 1.0);
  v_pos = vec3(0.0);
  v_nrm = vec3(0.0, 1.0, 0.0);
  v_col = vec3(0.0);
  v_info = vec4(0.0);
  v_mat = vec4(0.0);
}

// one grass blade's vertex `j` (of BLADE_VERTS), blade `blade` of the tile
void blade(int blade, int j) {
  float t = pc.eye_time.w;
  vec2 cell = at.xz;
  // far off, fewer blades, each wider
  float dist = length(vec3(cell.x + 0.5, at.y, cell.y + 0.5) - pc.eye_time.xyz);
  float far = smoothstep(GRASS_NEAR, GRASS_FAR, dist);
  if (float(blade) >= float(BLADES) * mix(1.0, GRASS_FAR_SHARE, far)) { hide(); return; }
  // no grassy ground anywhere on the tile (bare soil): nothing to work out
  vec4 any = max(max(max(k00, k01), max(k11, k10)), kc);
  if (dot(any, GRASS_DENSITY) <= 0.0) { hide(); return; }
  vec3 k = vec3(cell, float(blade));
  // its tuft's heart, and how grassy the ground is there (its kinds melted
  // as terrain.frag melts them): a whole tuft grows or none of it
  int tuft = blade / TUFT;
  vec3 kt = vec3(cell, float(tuft) + 101.0);
  vec2 heart = vec2(mix(0.05, 0.95, hash13(kt + 0.1)), mix(0.05, 0.95, hash13(kt + 1.7)));
  vec4 b = groundBlend(cell + heart, fanAt(k00, k01, k11, k10, kc, heart.x, heart.y));
  float dense = dot(b, GRASS_DENSITY);
  if (hash13(kt + 9.1) >= dense) { hide(); return; }
  // the blade rises a little off its heart, fanning out from it
  float round_ = TAU * (float(blade - tuft * TUFT) + hash13(k + 2.9)) / float(TUFT);
  vec2 off = vec2(cos(round_), sin(round_)) * TUFT_REACH * mix(0.2, 1.0, hash13(k + 0.6));
  float fx = clamp(heart.x + off.x, 0.0, 1.0);
  float fz = clamp(heart.y + off.y, 0.0, 1.0);
  vec2 spot = cell + vec2(fx, fz);
  // the blade: how long (shorter where the grass thins), which way it faces
  // and leans, how far it arches
  float len = mix(BLADE_MIN, BLADE_MAX, hash13(k + 3.3)) * mix(0.55, 1.0, smoothstep(0.0, 0.6, dense));
  float leanAng = round_ + (hash13(k + 4.2) - 0.5) * 0.9;
  float face = leanAng + (hash13(k + 5.9) - 0.5) * 0.8;
  vec3 lean = vec3(cos(leanAng), 0.0, sin(leanAng));
  float arch = BLADE_ARCH * mix(0.3, 1.0, hash13(k + 7.1));
  vec3 side = vec3(-sin(face), 0.0, cos(face));
  float halfW = BLADE_HALF_WIDTH * mix(0.75, 1.25, hash13(k + 8.3)) * mix(1.0, GRASS_FAR_WIDEN, far);
  // which band corner this vertex is: its height up the blade (0 root .. 3
  // tip, in thirds) and which edge (-1, 1; 0 the tip)
  int ring, edge;
  if (j < 12) {
    int q = j / 6, c = j - q * 6;
    ring = q + ((c == 2 || c == 4 || c == 5) ? 1 : 0);
    edge = (c == 0 || c == 3 || c == 5) ? -1 : 1;
  } else {
    int c = j - 12;
    ring = c == 2 ? 3 : 2;
    edge = c == 0 ? -1 : (c == 1 ? 1 : 0);
  }
  float s = float(ring) / 3.0;
  // up the blade it arches over along its lean, tapering to its tip
  vec3 base = vec3(spot.x, groundAt(fx, fz) - 0.01, spot.y);
  vec3 p = base + vec3(0.0, len * s * (1.0 - 0.35 * arch * s * s), 0.0) + lean * (arch * len * s * s);
  p += side * (halfW * float(edge) * pow(1.0 - s, 0.7));
  vec3 tangent = normalize(vec3(0.0, len * (1.0 - 1.05 * arch * s * s), 0.0) + lean * (2.0 * arch * len * s));
  vec3 n = normalize(cross(side, tangent));
  if (dot(n, lean) > 0.0) n = -n;
  n = normalize(mix(n, vec3(0.0, 1.0, 0.0), BLADE_SKYWARD));
  // it bends in the garden's wind, the tip most, with a sway of its own
  vec4 wind = gardenWind(t, p.xz);
  float bend = windPush(t, wind, dot(floor(base.xz * 8.0), vec2(1.7, 2.3)), GRASS) * s * s;
  p.xz += wind.xy * bend;
  p.y -= GRASS_DROOP * bend * bend;
  // coloured by the ground it rises from: dark at the root, pale at the tip,
  // each blade a little its own, a few gone to straw at the tip
  vec4 g = vec4(b.x + b.y, 0.0, b.z, b.w);
  vec3 root = MOSS_GRASS_ROOT * g.x + STONE_GRASS_ROOT * g.z + LEY_GRASS_ROOT * g.w;
  vec3 tip = MOSS_GRASS_TIP * g.x + STONE_GRASS_TIP * g.z + LEY_GRASS_TIP * g.w;
  tip = mix(tip, STRAW, step(1.0 - STRAW_SHARE, hash13(k + 12.7)) * smoothstep(0.4, 1.0, s));
  vec3 c = mix(root, tip, pow(s, 0.8)) * mix(0.85, 1.15, hash13(k + 13.9));
  v_pos = p;
  v_nrm = n;
  v_col = srgb2lin(min(c, vec3(1.0)));
  // w > 0 marks grass for terrain.frag (ley glow), z 0: not the ground
  v_info = vec4(info.x, info.y, 0.0, max(s, 0.004));
  gl_Position = project(p);
}

void main() {
  int kind = int(info.x * 255.0 + 0.5);
  int vi = gl_VertexIndex;
  v_mat = vec4(0.0);
  if (vi >= LUMP_VERTS) {
    int g = vi - LUMP_VERTS;
    int bl = g / BLADE_VERTS;
    blade(bl, g - bl * BLADE_VERTS);
    return;
  }
  if (kind != TILE_SOIL) { hide(); return; }
  vec3 tile = srgb2lin(col.rgb);
  vec2 cell = at.xz;

  // soil: rounded lumps of 32 triangles, two per tile: a ring round its
  // middle, a shoulder ring above it turned half a step, a crown and a
  // buried bottom, shaded smooth as the rounded lump they stand for
  int lump = vi / LUMP_ONE;
  int j = vi - lump * LUMP_ONE;
  int tri = j / 3;
  int corner = j - tri * 3;
  vec3 k = vec3(cell, float(lump) + 11.0);
  if (hash13(vec3(cell, 0.5)) < SOIL_BARE) { hide(); return; }
  bool stone = lump == 1;
  float fx = mix(0.12, 0.88, hash13(k + 0.3));
  float fz = mix(0.12, 0.88, hash13(k + 2.1));
  float r = stone ? mix(0.025, 0.055, hash13(k + 4.4)) : mix(0.05, 0.1, hash13(k + 4.4));
  float flat_ = stone ? 0.75 : 0.6;
  vec3 c = vec3(cell.x + fx, groundAt(fx, fz), cell.y + fz);
  float turn = TAU * hash13(k + 6.6);
  // the ring point `i` round it (`up`: the shoulder ring), and the crown and bottom
  vec3 q[3];
  for (int n = 0; n < 3; n++) {
    // which point this corner of the triangle is: a middle point, a
    // shoulder point, the crown (-1) or the bottom (-2)
    int i = 0, ring = 0;
    if (tri < 2 * LUMP_SIDES) {
      int seg = tri / 2;
      bool second = tri - seg * 2 == 1;
      int corners0[3] = int[3](0, 1, 2), corners1[3] = int[3](1, 3, 2);
      int cc = second ? corners1[n] : corners0[n];
      // 0: middle seg, 1: middle seg+1, 2: shoulder seg, 3: shoulder seg+1
      i = seg + (cc == 1 || cc == 3 ? 1 : 0);
      ring = cc >= 2 ? 1 : 0;
    } else if (tri < 3 * LUMP_SIDES) {
      int seg = tri - 2 * LUMP_SIDES;
      i = seg + (n == 1 ? 1 : 0);
      ring = n == 2 ? -1 : 1;
    } else {
      int seg = tri - 3 * LUMP_SIDES;
      i = seg + (n == 2 ? 1 : 0);
      ring = n == 1 ? -2 : 0;
    }
    i = i - (i >= LUMP_SIDES ? LUMP_SIDES : 0);
    vec3 kr = k + float(i) * 13.1 + float(ring) * 5.3;
    if (ring == -1) q[n] = c + vec3(r * (hash13(k + 8.1) - 0.5) * 0.2, r * flat_, r * (hash13(k + 9.3) - 0.5) * 0.2);
    else if (ring == -2) q[n] = c - vec3(0.0, r * flat_ * 0.6, 0.0);
    else {
      float a = turn + TAU * (float(i) + 0.5 * float(ring)) / float(LUMP_SIDES);
      float d = r * mix(0.72, 1.2, hash13(kr + 0.7)) * (ring == 1 ? mix(0.55, 0.8, hash13(kr + 2.6)) : 1.0);
      float h = ring == 1 ? r * flat_ * mix(0.5, 0.9, hash13(kr + 1.9)) : r * flat_ * 0.15 * hash13(kr + 1.9);
      q[n] = c + vec3(cos(a) * d, h, sin(a) * d);
    }
  }
  vec3 p = q[corner];
  // its normal: the rounded lump's (an ellipsoid round its heart)
  vec3 heart = c + vec3(0.0, r * flat_ * 0.25, 0.0);
  vec3 n = normalize((p - heart) / vec3(r * r, r * flat_ * r * flat_, r * r));
  vec3 grey = STONE_GREY * mix(0.75, 1.15, hash13(k + 10.7));
  v_pos = p;
  v_nrm = n;
  // a clod's crust dries paler on top, darker and damper underneath
  v_col = stone ? srgb2lin(grey) * mix(0.8, 1.05, n.y * 0.5 + 0.5) : tile * vec3(0.8, 0.75, 0.7) * mix(0.75, 1.1, n.y * 0.5 + 0.5);
  v_info = vec4(info.x, info.y, 0.0, 0.0);
  gl_Position = project(p);
}
