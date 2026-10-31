//! the ground's own stuff, worked out per pixel: soil, moss, stone and ley
//! ground melted into each other along wandering, frayed borders (never the
//! tile grid), each with a surface of its own (grain and pebbles in the
//! soil, clumps of moss, cracked slabs of stone) and the bumps that light
//! them. Included after common.glsl (terrain.frag; detail.vert for where
//! its grass grows).

// value noise 0..1 at `p`, smooth between the lattice's hashed corners
float groundNoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
// three octaves of it, each turned off the last so no grid shows (0..~0.9)
float groundFbm(vec2 p) {
  float s = 0.0, a = 0.5;
  for (int i = 0; i < 3; i++) {
    s += a * groundNoise(p);
    p = rot(0.62) * p * 2.07 + 17.3;
    a *= 0.5;
  }
  return s;
}
// how strongly each kind's own shape (moss clumps, stone slabs) pushes its
// border out: a share of how much of it there is (from 1 - this to 1 + this)
const float GROUND_FRAY = 0.75;
// how much more firmly a ley line holds its ground than the kinds round it
const float LEY_HOLD = 1.7;
// how soft the border between two kinds is, once frayed
const float GROUND_SOFT = 0.12;
// how far the ground's kinds reach for each other, scaled up, at `p` (world
// x, z): the tiles' shares `w` (soil, moss, stone, ley) pushed out where
// each kind's own shape rises, then sharpened, so borders wander in blobs
// and fray at their edges instead of following the tiles
vec4 groundBlend(vec2 p, vec4 w) {
  vec4 shape = vec4(
    groundFbm(p * 1.3 + 3.1),                                   // soil: broad
    0.7 * groundFbm(p * 1.7 + 11.0) + 0.3 * groundNoise(p * 9.0), // moss: clumped, frayed
    groundFbm(p * 0.9 + 23.0),                                  // stone: slabs
    groundFbm(p * 1.1 + 41.0));                                 // ley: drifting
  // a ley line is often one tile wide: it holds its ground more firmly, so
  // it never breaks apart between the kinds round it
  vec4 s = w * vec4(1.0, 1.0, 1.0, LEY_HOLD) * (1.0 - GROUND_FRAY + 2.0 * GROUND_FRAY * shape);
  float top = max(max(s.x, s.y), max(s.z, s.w));
  vec4 b = max(s - top + GROUND_SOFT, 0.0);
  return b / max(dot(b, vec4(1.0)), 1e-4);
}
// worley cells at `p`: the distance to the nearest point and to the next (x, y)
vec2 groundCells(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 d = vec2(8.0);
  for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
    vec2 o = vec2(x, y);
    vec2 c = o + vec2(hash12(i + o), hash12(i + o + 19.7)) - f;
    float e = dot(c, c);
    if (e < d.x) d = vec2(e, d.x); else if (e < d.y) d.y = e;
  }
  return sqrt(d);
}
// one kind of ground at a point: its colour (linear) and how high its
// surface stands there (for bumps, 0..1)
struct GroundSurface { vec3 albedo; float height; };
// soil (sRGB): damp dark, its own brown, dry and pale; a pale pebble
const vec3 SOIL_DAMP = vec3(0.25, 0.18, 0.12);
const vec3 SOIL = vec3(0.36, 0.27, 0.19);
const vec3 SOIL_DRY = vec3(0.47, 0.38, 0.29);
const vec3 PEBBLE = vec3(0.55, 0.52, 0.47);
// moss (sRGB): deep in its clumps, its own green, sunlit tips going gold
const vec3 MOSS_DEEP = vec3(0.10, 0.22, 0.13);
const vec3 MOSS = vec3(0.20, 0.36, 0.20);
const vec3 MOSS_TIP = vec3(0.36, 0.46, 0.20);
// stone (sRGB): cool and warm greys, the dark of its cracks, pale lichen
const vec3 STONE_COOL = vec3(0.38, 0.39, 0.44);
const vec3 STONE_WARM = vec3(0.47, 0.45, 0.43);
const vec3 STONE_CRACK = vec3(0.17, 0.17, 0.19);
const vec3 LICHEN = vec3(0.58, 0.60, 0.46);
// ley ground (sRGB): its violet, and darker in its grain
const vec3 LEY_GROUND = vec3(0.30, 0.24, 0.45);
const vec3 LEY_DEEP = vec3(0.19, 0.15, 0.30);
// soil: broad damp and dry patches, a crumbly grain, scattered pale pebbles;
// `fine` 1 near, 0 where a pixel spans too much for grain (it fades to its mean)
GroundSurface soilAt(vec2 p, float fine) {
  float damp = groundFbm(p * 0.35);
  vec3 c = mix(mix(SOIL_DAMP, SOIL, smoothstep(0.15, 0.45, damp)), SOIL_DRY, smoothstep(0.5, 0.8, damp));
  float crumb = groundNoise(p * 7.0) * 0.6 + groundNoise(p * 23.0) * 0.4;
  c *= mix(1.0, 0.78 + 0.44 * crumb, fine);
  vec2 cell = groundCells(p * 5.0);
  float pebble = (1.0 - smoothstep(0.07, 0.13, cell.x)) * step(0.82, hash12(floor(p * 5.0 + 0.5) + 3.3)) * fine;
  c = mix(c, PEBBLE * (0.8 + 0.4 * hash12(floor(p * 5.0) + 7.7)), pebble);
  return GroundSurface(srgb2lin(c), crumb * 0.5 + pebble * 0.8);
}
// moss: cushions of every size heaped into each other (broad mounds, small
// tufts on them), deep in the folds between, their tops catching gold, a
// fine fuzz; no two alike, no pattern to read
GroundSurface mossAt(vec2 p, float fine) {
  vec2 q = p + 0.6 * vec2(groundNoise(p * 0.7 + 2.0), groundNoise(p * 0.7 + 8.0));
  float mound = groundFbm(q * 1.1 + 5.0);
  float tuft = groundFbm(q * 4.3 + 29.0);
  float clump = smoothstep(0.2, 0.75, mound * 0.6 + tuft * 0.55);
  float fuzz = mix(0.5, groundNoise(p * 31.0), fine);
  vec3 c = mix(MOSS_DEEP, MOSS, smoothstep(0.1, 0.6, clump * 0.8 + fuzz * 0.25));
  c = mix(c, MOSS_TIP, smoothstep(0.6, 1.0, clump * 0.7 + groundFbm(p * 0.35 + 3.0) * 0.5) * 0.6);
  return GroundSurface(srgb2lin(c), clump * 0.7 + fuzz * 0.3);
}
// stone: broad warm and cool slabs split by dark cracks, flecked with lichen
GroundSurface stoneAt(vec2 p, float fine) {
  vec2 cell = groundCells(p * 1.4);
  float crack = (1.0 - smoothstep(0.0, mix(0.2, 0.06, fine), cell.y - cell.x)) * mix(0.4, 1.0, fine);
  float tone = groundFbm(p * 0.6 + 9.0);
  vec3 c = mix(STONE_COOL, STONE_WARM, smoothstep(0.25, 0.65, tone));
  c *= mix(1.0, 0.85 + 0.3 * groundNoise(p * 13.0), fine);
  float lichen = smoothstep(0.62, 0.7, groundFbm(p * 2.3 + 31.0)) * 0.6;
  c = mix(c, LICHEN, lichen);
  c = mix(c, STONE_CRACK, crack);
  return GroundSurface(srgb2lin(c), (1.0 - crack) * (0.6 + 0.4 * tone));
}
// ley ground: soil's crumbly grain in the line's violet
GroundSurface leyAt(vec2 p, float fine) {
  float crumb = mix(0.5, groundNoise(p * 7.0) * 0.6 + groundNoise(p * 23.0) * 0.4, fine);
  vec3 c = mix(LEY_DEEP, LEY_GROUND, smoothstep(0.2, 0.75, groundFbm(p * 0.5 + 13.0) * 0.6 + crumb * 0.5));
  return GroundSurface(srgb2lin(c), crumb * 0.5);
}
// the ground at `p` with the blend `b` (groundBlend): its colour and its
// surface's height, each kind worked out only where it shows
GroundSurface groundOf(vec2 p, vec4 b, float fine) {
  GroundSurface g = GroundSurface(vec3(0.0), 0.0);
  if (b.x > 0.0) { GroundSurface s = soilAt(p, fine); g.albedo += s.albedo * b.x; g.height += s.height * b.x; }
  if (b.y > 0.0) { GroundSurface s = mossAt(p, fine); g.albedo += s.albedo * b.y; g.height += s.height * b.y; }
  if (b.z > 0.0) { GroundSurface s = stoneAt(p, fine); g.albedo += s.albedo * b.z; g.height += s.height * b.z; }
  if (b.w > 0.0) { GroundSurface s = leyAt(p, fine); g.albedo += s.albedo * b.w; g.height += s.height * b.w; }
  return g;
}
