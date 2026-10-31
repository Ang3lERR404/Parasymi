//! shared by every world pass: push constants, the sky's shift, garden wind, growth, gathering, halo spiral, the plexus and shading (shadows and points of light from the engine's light.glsl).
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_buffer_reference_uvec2 : require
#ifdef SHADOW
// a shadow caster draws into every cascade at once, one view each
#extension GL_EXT_multiview : require
#endif
layout(push_constant) uniform Push {
  mat4 vp;
  vec4 eye_time;  // xyz camera eye, w time (s)
  vec4 fog;       // rgb fog/sky colour (linear), w fog density
  vec4 misc;      // x veil 0..1, y ley sight 0/1, zw hovered tile (x,z)
  vec4 sun;       // xyz direction toward the key light (sun or moon), w daylight 0..1
  vec4 feet[2];   // the wolf's paws: xyz world position; [0].w facing yaw, [1].w the sky's shift
  vec4 view;      // xy camera target (x,z), z fog-out start, w fog-out end (horizontal)
  uvec2 bones;    // the parts pass: the address of this frame's bones (part.vert)
  uvec2 light;    // the address of this frame's Lighting
} pc;

#define SUN pc.sun.xyz
// what drives the garden's light, by name (a sky shift or other world event
// is these moving): how much of the day it is (0 night .. 1 noon), and how
// far the veil has drawn over it (0 none .. 1 full)
#define DAYLIGHT pc.sun.w
#define VEIL pc.misc.x
// how far the unforming has shifted the sky, 0 the old one .. 1 the ley's
// glow for good (sky.zig `Sky.shift`); the ley lines seal over part of it
#define SHIFT pc.feet[1].w
const float SEAL_FROM = 0.15;  // (unforming.zig sealFrom; must match)
const float SEAL_SPAN = 0.6;   // (unforming.zig sealSpan; must match)
// how far the ley lines have sealed, 0 open .. 1 closed
float sealed() { return clamp((SHIFT - SEAL_FROM) / SEAL_SPAN, 0.0, 1.0); }
// a light or a colour that turns with the day: `night` by night, `day` at noon
vec3 byDay(vec3 night, vec3 day) { return mix(night, day, DAYLIGHT); }

#include "light.glsl"

const float TAU = 6.2831853;
// how tight the sheen along fibres is (anisotropic highlight exponent)
const float SHEEN_POWER = 40.0;

// what a vertex's role is (gfx/vertex.zig `Part`, its u32 value; must match).
// Untyped so they compare with the vertex stage's uint and the fragment
// stage's int alike. (PART_SHADOW: not SHADOW, the shadow-variant define.)
#define PART_STEM 0       // a stem, a vine
#define PART_LEAF 1
#define PART_BLOOM 2      // a petal, sap, a glow
#define PART_THORN 3      // a thorn, a claw
#define PART_TENDRIL 4    // a tendril, a frond, a root
#define PART_EAR 5        // a sap-lined leaf (the ear)
#define PART_RESIN 6
#define PART_SHADOW 7     // a soft patch on the ground under a floater
#define PART_THREAD 8     // a beam between blooms
#define PART_FLASH 9      // the flash where a halo's blooms meet
#define PART_PRISM 10     // the diamond's cut crystal
#define PART_HALO 11      // the ring of split light
#define PART_PROJECTION 12 // the rays that make the ring
#define PART_CORE 13      // a conduit's core
#define PART_ESSENCE 14   // liquid essence a germinator pours, spins and winds
#define PART_ENERGY 15    // research energy an arsthraxia condenses
#define PART_NERVE 16     // an arsthraxia's nerve: thought rises through it
#define PART_POD 17       // a plant's yield ripening on it, a bead of sap
#define PART_PLEXUS 18    // the constellate web: points, lines, panes of light
#define PART_STONE 19     // weathered stone: grained, flecked, lichened
// sets of roles, one bit each: a shader keys what roles do alike off a set
// (PART_IN), so a new role joins a behaviour by joining its set
#define PART_BIT(p) (1u << uint(p))
#define PART_IN(set, p) ((((set) >> uint(p)) & 1u) != 0u)
// the roles that are light itself: they cast no shadow (part.vert SHADOW)
// and are not lit by the key light (part.frag)
const uint PARTS_LIGHT = PART_BIT(PART_THREAD) | PART_BIT(PART_FLASH) | PART_BIT(PART_HALO) | PART_BIT(PART_PROJECTION) | PART_BIT(PART_ENERGY) | PART_BIT(PART_PLEXUS);
// the roles that are a plant's leaves and petals (plant.vert, plant.frag):
// they unfurl as it grows, lift in the gusts, always read as thin and show
// no fibres
const uint SHEETS = PART_BIT(PART_LEAF) | PART_BIT(PART_BLOOM);

// a plant's form (sim/species.zig `Form`, instance ib.w; must match)
const float FORM_HERB = 0.0;
const float FORM_COIL = 1.0;
const float FORM_DRIFT = 2.0;
const float FORM_CONFLUENCE = 3.0;
const float FORM_RADIANT = 4.0;
const float FORM_STAR = 5.0;
bool isForm(float f, float form) { return abs(f - form) < 0.5; }
// sets of forms, one bit each (as the roles' sets): what forms do alike is
// keyed off a set (formIn), so a new form joins a behaviour by joining it
#define FORM_BIT(f) (1u << uint(f))
bool formIn(uint set, float f) { return ((set >> uint(f + 0.5)) & 1u) != 0u; }
// the radiant lineage's plants (radiant_kit): petals and leaves floating
// free of a core, gathered and turned by it, never bending from a root and
// glowing with the light they carry (the celestial bloom, the vesper)
const uint FORMS_FREE = FORM_BIT(FORM_RADIANT) | FORM_BIT(FORM_STAR);
// the forms whose petals are a lantern of clear sap (meshgen `lantern`,
// below LANTERN_TOP along the plant): it is drawn see-through and, being
// clear, casts no shadow (plant.vert SHADOW and plant.frag agree on it)
const uint FORMS_LANTERN = FORM_BIT(FORM_DRIFT);
const float LANTERN_TOP = 0.75;
bool isLantern(float form, int part, float h) { return part == PART_BLOOM && h < LANTERN_TOP && formIn(FORMS_LANTERN, form); }

// tile kinds (world tile `Kind`, info.x * 255; must match)
const int TILE_SOIL = 0;

float hash12(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

// how the ley lines pulse at `p` (0..1): a slow wave rolling across them
float leyPulse(vec3 p, float t) { return 0.5 + 0.5 * sin(t * 2.0 + p.x * 0.45 + p.z * 0.3); }

float segDist(vec2 p, vec2 a, vec2 b) {
  vec2 ab = b - a;
  float h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
  return length(p - a - ab * h);
}

// faint points drifting over a plane (`wp`, two cells per unit), joined by
// threads of light where they come near one another (a plexus): over the
// ley lines (terrain.frag), and across the shifted sky (sky.frag)
float plexus(vec2 wp, float t) {
  vec2 g = wp * 2.0;
  vec2 id = floor(g);
  vec2 pts[9];
  for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
    vec2 c = id + vec2(i, j);
    float r1 = hash12(c), r2 = hash12(c + 17.1), r3 = hash12(c + 41.7);
    vec2 drift = vec2(sin(t * (0.15 + 0.2 * r1) + r2 * TAU), cos(t * (0.13 + 0.2 * r3) + r1 * TAU));
    pts[(j + 1) * 3 + (i + 1)] = c + 0.5 + 0.36 * drift;
  }
  float v = 0.0;
  for (int k = 0; k < 9; k++) {
    float d = length(g - pts[k]);
    v += (1.0 - smoothstep(0.02, 0.07, d)) * 0.9;
    for (int l = k + 1; l < 9; l++) {
      float len = length(pts[k] - pts[l]);
      float near = 1.0 - smoothstep(0.45, 0.95, len);
      if (near <= 0.0) continue;
      v += near * (1.0 - smoothstep(0.006, 0.02, segDist(g, pts[k], pts[l]))) * 0.45;
    }
  }
  return v;
}

// light colours: the moon's cool blue (scaled down by night), the sun's warm
// white, and the amber of sap (linear), the garden's one accent
const vec3 MOONLIGHT = vec3(0.35, 0.45, 0.8);
const vec3 SUNLIGHT = vec3(1.0, 0.95, 0.85);
const vec3 AMBER = vec3(1.0, 0.43, 0.08);

// fresnel falloff (1 - n.v)^this, and the night rim light's
const float FRESNEL_POW = 2.0;
const float RIM_POW = 3.0;

// two passes draw every surface: the solid one keeps the fragments that are
// opaque (alpha >= SOLID) and writes depth; the glass one (built with GLASS,
// after every solid pass) blends the see-through ones over it (down to
// CLEAR), testing depth but writing none
const float SOLID = 0.996;
const float CLEAR = 0.002;

// a beam's half width at its middle (part.vert spindle, part.frag motes)
const float BEAM_HALF_WIDTH = 0.42;

// a thin film's hue: one turn of the rainbow per unit of `x`, its three
// channels this far apart
const vec3 FILM_PHASE = vec3(0.0, 0.33, 0.67);
vec3 filmHue(float x) { return 0.5 + 0.5 * cos(TAU * (FILM_PHASE + x)); }

// the highlight of light (half vector `H`) along fibres running `tgrad`
// (unnormalised, its length `tl` > 0) over a surface with normal `n`.
float fibreSheen(vec3 tgrad, float tl, vec3 n, vec3 H) {
  vec3 T = normalize(tgrad / tl - n * dot(tgrad / tl, n) + 1e-6);
  float th = dot(T, H);
  return pow(sqrt(max(1.0 - th * th, 0.0)), SHEEN_POWER);
}
// that sheen as light on a woven body (`base`, its sheen tinted toward
// `light`), `k` of it, on faces toward the key light (`sh` of it reaching
// them), fading where the fibres are too fine to see (tl small)
vec3 fibreLight(vec3 base, vec3 light, vec3 tgrad, float tl, vec3 n, vec3 V, float k, float sh) {
  float sheen = fibreSheen(tgrad, tl, n, normalize(SUN + V));
  return mix(base, light, 0.5) * sheen * smoothstep(0.0, 0.3, dot(n, SUN)) * k * smoothstep(0.3, 1.5, tl) * sh;
}

// a turn by `a` radians in a plane (x,y) or (x,z)
mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }
// `v` turned by `a` radians about the unit `axis` (Rodrigues)
vec3 turnAbout(vec3 v, vec3 axis, float a) {
  float ca = cos(a);
  return v * ca + cross(axis, v) * sin(a) + axis * dot(axis, v) * (1.0 - ca);
}

// how far growth `g` has passed a point `at` along what grows (0..1): it
// arrives there at `at * pace`, and is wholly past `span` later
float grownPast(float at, float pace, float span, float g) { return smoothstep(at * pace, at * pace + span, g); }
// the scale across a leaf or petal growing in, `along` it (0 its base,
// which holds, .. 1 its tip): `closed` while folded, 1 once `open`
float unfold(float closed, float open, float along) { return mix(1.0, mix(closed, 1.0, open), along); }

// the one wind over the whole garden at a point (x,z): its heading (xy,
// unit) drifts slowly, and broad gusts (z, 0..1, mostly calm) roll across
// it as a wave, so neighbours lean together; w is the point's distance
// along the wind, which later motion is phased by.
const float WIND_HEADING = 0.6;        // its mean heading (radians)
const float WIND_HEADING_SWING = 0.35; // how far the heading drifts either way
const float WIND_HEADING_RATE = 0.031; // how fast it drifts (rad/s)
const float GUST_RATE = 0.32;          // how fast the gust wave rolls (rad/s)
const float GUST_WAVE = 0.16;          // its phase per unit along the wind
vec4 gardenWind(float t, vec2 at) {
  float head = WIND_HEADING + WIND_HEADING_SWING * sin(t * WIND_HEADING_RATE);
  vec2 wdir = vec2(cos(head), sin(head));
  float along = dot(at, wdir);
  float gust = 0.5 + 0.5 * sin(t * GUST_RATE - along * GUST_WAVE);
  return vec4(wdir, gust * gust, along);
}

// how a kind of growth answers the garden's wind (windPush): its own sway's
// rate (rad/s) and phase per unit along the wind, its push per unit of gust,
// and its own sway's reach, keeping `calm` of that reach in a calm (more in
// gusts). Everything grown that bends in the wind is one of these.
struct WindResponse { float rate; float wave; float gust; float own; float calm; };
// how far a thing answering `r` is pushed by the wind (`wind`, gardenWind)
// at its own `phase`: the gust's push plus a sway of its own, phased by
// where it stands along the wind
float windPush(float t, vec4 wind, float phase, WindResponse r) {
  float own = sin(t * r.rate - wind.w * r.wave + phase);
  return r.gust * wind.z + r.own * (r.calm + wind.z) * own;
}

// how far something grown leans in the wind (radians at its tip, before the
// h^2 of its height): the push (as LEAN), at its own `phase`, reaching a
// point at height `h` (0 root .. 1 tip) late. Plants and standing
// structures share it.
const WindResponse LEAN = WindResponse(
  0.85,  // its own sway (rad/s)
  0.3,   // phase per unit along the wind
  0.05,  // lean per unit of gust
  0.025, // its own sway's reach ...
  0.4    // ... (this much even in a calm, more in gusts)
);
const float LEAN_LAG = 0.9;     // phase the tip lags the base by
float windLean(float t, vec4 wind, float phase, float h, float sway) {
  return sway * windPush(t, wind, phase - h * LEAN_LAG, LEAN);
}

// leaves and petals lift a touch in the gusts and breathe, tips most
const float LEAF_LIFT = 0.012;     // lift in a full gust
const float LEAF_LIFT_RATE = 1.7;  // its flutter (rad/s)

// turn `v` about the origin by `ang` in the vertical plane holding `wdir`
// (positive: its top toward the wind's heading).
vec3 bendIn(vec3 v, vec2 wdir, float ang) {
  float ca = cos(ang), sa = sin(ang);
  float a0 = dot(v.xz, wdir);
  float a1 = a0 * ca + v.y * sa;
  v.y = v.y * ca - a0 * sa;
  v.xz += wdir * (a1 - a0);
  return v;
}

vec3 hash33(vec3 p) {
  p = fract(p * vec3(0.1031, 0.1030, 0.0973));
  p += dot(p, p.yxz + 33.33);
  return fract((p.xxy + p.yxx) * p.zyx);
}

// a hard-edged highlight: 1 where the direction `r` falls within a disc of
// radius `size` (1 - cos of it) about the light's direction `l`, its edge a
// sharp step (SPOT_EDGE of the radius), never a soft falloff
const float SPOT_EDGE = 0.3;
float hardSpot(vec3 r, vec3 l, float size) {
  return 1.0 - smoothstep(size * (1.0 - SPOT_EDGE), size, 1.0 - dot(r, l));
}

// bubbles floating up through sap: a crisp ring mask with a pinpoint where
// the light from above catches each, sampled at two depths behind the
// surface along the view so they hang inside it. `obj` is the mesh-space
// point (they ride with the body), `view` toward the eye.
const float BUBBLE_DEPTH = 0.012;  // how far behind the surface the near layer hangs
const float BUBBLE_CELLS = 36.0;   // bubble cells per unit (near layer)
const float BUBBLE_RISE = 0.3;     // how fast they rise (cells/s, near layer)
const float BUBBLE_SHARE = 0.3;    // the share of cells holding one
const vec3 BUBBLE_CATCH = vec3(-0.3, 0.5, 0.0); // where on a bubble its pinpoint sits (of its radius)
const float BUBBLE_CATCH_GAIN = 2.5;
float sapBubbles(vec3 obj, vec3 view, float t) {
  float b = 0.0;
  for (int l = 0; l < 2; l++) {
    float fl = float(l);
    vec3 q = (obj - view * (BUBBLE_DEPTH + 0.02 * fl)) * (BUBBLE_CELLS - 10.0 * fl) - vec3(0.0, t * (BUBBLE_RISE + 0.12 * fl), 0.0);
    vec3 id = floor(q);
    vec3 h = hash33(id + fl * 19.0);
    if (h.x > BUBBLE_SHARE) continue;
    vec3 c = id + 0.3 + 0.4 * h.yzx;
    c.x += 0.1 * sin(t * 0.8 + h.z * TAU);
    float r = 0.08 + 0.14 * h.y;
    float d = length(q - c);
    // a thin sharp skin, a clear middle, a hard pinpoint of light
    float skin = smoothstep(r, r * 0.9, d) - 0.85 * smoothstep(r * 0.86, r * 0.66, d);
    float pin = 1.0 - smoothstep(r * 0.12, r * 0.17, length(q - c - BUBBLE_CATCH * r));
    b += (skin + pin * BUBBLE_CATCH_GAIN) * (1.0 - 0.45 * fl);
  }
  return b;
}

// beads of sap clinging to a surface, sliding slowly down it: x the bead,
// y its glint (a dome mirroring `light` in a hard spot)
const float DROP_CELLS = 52.0;    // bead cells per unit
const float DROP_SLIDE = 0.1;     // how fast they slide down (cells/s)
const float DROP_SHARE = 0.4;     // the share of cells holding one
const float DROP_SPOT = 0.03;     // how big a bead's glint is (1 - cos)
const float DROP_GLINT_GAIN = 3.0;
vec2 sapDroplets(vec3 obj, vec3 n, vec3 light, vec3 view, float t) {
  vec3 q = obj * DROP_CELLS + vec3(0.0, t * DROP_SLIDE, 0.0);
  vec3 id = floor(q);
  vec3 h = hash33(id + 7.0);
  if (h.x > DROP_SHARE) return vec2(0.0);
  vec3 c = id + 0.28 + 0.44 * h.yzx;
  float r = 0.14 + 0.16 * h.z;
  // drawn out down the surface, heavier at the bottom
  vec3 d = q - c;
  d.y *= d.y > 0.0 ? 1.4 : 0.8;
  float l = length(d);
  float bead = smoothstep(r, r * 0.7, l);
  vec3 bn = normalize(n + (d / r) * 0.9);
  float glint = hardSpot(reflect(-light, bn), view, DROP_SPOT) * DROP_GLINT_GAIN;
  return vec2(bead, bead * glint);
}

// the palette's sRGB colours to linear (a plain power curve)
const float GAMMA = 2.2;
vec3 srgb2lin(vec3 c) { return pow(c, vec3(GAMMA)); }

// the key light's strength: the moon's by night, the sun's by day
const float MOON_STRENGTH = 0.35;
const float SUN_STRENGTH = 1.1;
// the shifted sky's light (the ley's glow overhead): a deep violet by night,
// a rose violet by day, softer than the sun (the whole sky glows)
const vec3 LEYLIGHT_NIGHT = vec3(0.16, 0.11, 0.36);
const vec3 LEYLIGHT_DAY = vec3(0.78, 0.55, 1.0);
// the key light's colour and strength (the sun by day, the moon by night;
// once shifted, the ley's glow)
vec3 keyLight() { return mix(byDay(MOONLIGHT * MOON_STRENGTH, SUNLIGHT * SUN_STRENGTH), byDay(LEYLIGHT_NIGHT, LEYLIGHT_DAY * 0.8), SHIFT); }

// the ambient light: the sky's by day (veiled, toward violet), by night, the
// ground's bounce (dimmed to this share by night), and how strong it all is
const vec3 SKY_DAY = vec3(0.35, 0.40, 0.50);
const vec3 SKY_VEILED = vec3(0.45, 0.30, 0.65);
const vec3 SKY_NIGHT = vec3(0.07, 0.09, 0.18);
// the shifted sky's: the ley's glow all round, by night and by day
const vec3 SKY_LEY_NIGHT = vec3(0.1, 0.06, 0.22);
const vec3 SKY_LEY_DAY = vec3(0.45, 0.3, 0.7);
const vec3 GROUND_BOUNCE = vec3(0.12, 0.10, 0.08);
const float GROUND_NIGHT = 0.3;
const float AMBIENT = 0.55;
// a surface lit by the sky, the key light (`sh` of it reaching it, see
// keyShadow) and the points of light (`points`, as pointLight gives them)
vec3 shadeLitWith(vec3 albedo, vec3 n, float sh, vec3 points) {
  float ndl = max(dot(n, SUN), 0.0);
  float day = DAYLIGHT;
  vec3 sky = mix(SKY_DAY, SKY_VEILED, VEIL);
  sky = mix(byDay(SKY_NIGHT, sky), byDay(SKY_LEY_NIGHT, SKY_LEY_DAY), SHIFT);
  vec3 ground = GROUND_BOUNCE * mix(GROUND_NIGHT, 1.0, day);
  vec3 amb = mix(ground, sky, n.y * 0.5 + 0.5) * AMBIENT;
  vec3 sun = keyLight() * ndl * sh;
  return albedo * (amb + sun + points);
}
vec3 shadeLit(vec3 albedo, vec3 n, vec3 wpos, float sh) { return shadeLitWith(albedo, n, sh, pointLight(wpos, n, 0.0)); }

vec3 shade(vec3 albedo, vec3 n, vec3 wpos) { return shadeLit(albedo, n, wpos, keyShadow(wpos, n)); }

// sap glistens: it is wet, and light on a wet surface is hard. Each light is
// mirrored in it as a crisp disc with a white-hot core, brighter than white
// so the bloom gathers the glow round it (the sap itself never glows softly);
// its skin ripples in tiny facets that catch the light one by one and wink
// out; light falling through a clear body is focused into a sharp caustic on
// its far wall; and its edge holds a thin hard line of reflected sky.
const float SUN_SPOT = 0.0035;      // the key light's image (1 - cos of its radius)
const float SUN_CORE = 0.0008;      // its white-hot core
const float SUN_SPOT_GAIN = 2.2;
const float SUN_CORE_GAIN = 6.0;
const float POINT_SPOT = 0.012;     // a point of light's image
const float POINT_SPOT_GAIN = 3.5;
const float GLINT_CELLS = 26.0;     // glinting facets per unit of skin
const float GLINT_SHARE = 0.45;     // the share of cells holding one
const float GLINT_SIZE = 0.32;      // a facet's radius (of its cell)
const float GLINT_TILT = 0.5;       // how far a facet leans off the skin
const float GLINT_RATE = 0.8;       // how fast facets turn (rad/s)
const float GLINT_SPOT = 0.02;      // how near the light's mirror a facet catches
const float GLINT_GAIN = 5.0;
const float SAP_IOR = 1.45;         // sap bends light as water does, a little more
const float CAUSTIC_SPOT = 0.05;    // the focused light's spot on the far wall
const float CAUSTIC_GAIN = 2.4;
const float EDGE_LINE = 0.14;       // n.v below which the edge line shows
const float EDGE_GAIN = 0.6;
const float SKY_SPOT = 0.05;        // the bright sky overhead mirrored: a hard window
const float SKY_SPOT_GAIN = 0.45;

// the points of light as a surface at `wpos` facing `n` sees them, all in
// one pass over them (a material wanting several views of them reads the
// lights once; the views it leaves unused are compiled away): as
// pointLight gives them facing `n` (plain), wrapping round thin tissue
// (wrap 1) and facing away (-n), and, with `mirror`, mirrored in wet
// skin along `R`
struct PointLit { vec3 plain; vec3 wrapped; vec3 behind; vec3 mirrored; };
PointLit pointLights(vec3 wpos, vec3 n, vec3 R, bool mirror) {
  Lighting L = Lighting(pc.light);
  int count = int(L.info.x + 0.5);
  PointLit p = PointLit(vec3(0.0), vec3(0.0), vec3(0.0), vec3(0.0));
  for (int i = 0; i < count; i++) {
    vec4 lp = L.lights[i].pos;
    vec3 d = lp.xyz - wpos;
    float d2 = dot(d, d);
    float k = d2 / (lp.w * lp.w);
    if (k >= 1.0) continue;
    vec3 col = L.lights[i].col.rgb;
    float win = (1.0 - k) * (1.0 - k);
    float inv = inversesqrt(max(d2, 1e-6));
    float f = dot(n, d) * inv;
    vec3 lit = col * win / (1.0 + LIGHT_FALLOFF * k);
    p.plain += lit * max(f, 0.0);
    p.wrapped += lit * max((f + 1.0) * 0.5, 0.0);
    p.behind += lit * max(-f, 0.0);
    if (mirror) p.mirrored += col * hardSpot(R, d * inv, POINT_SPOT) * POINT_SPOT_GAIN * win;
  }
  return p;
}

// the hard light on sap at `wpos` (mesh-space `obj`, its glints ride with
// it) facing `n`, seen from `V`: `sapc` its colour, `clear` how see-through
// (0 opaque: no caustic), `sh` the key light reaching it (keyShadow),
// `mirrored` the points of light mirrored in it (pointLights)
vec3 sapGlistenWith(vec3 n, vec3 V, vec3 wpos, vec3 obj, vec3 sapc, float clear, float sh, vec3 mirrored) {
  vec3 R = reflect(-V, n);
  vec3 key = keyLight();
  vec3 c = key * (hardSpot(R, SUN, SUN_SPOT) * SUN_SPOT_GAIN + hardSpot(R, SUN, SUN_CORE) * SUN_CORE_GAIN) * sh;
  // the sky overhead, mirrored as a hard-edged window of light
  vec3 sky = mix(byDay(MOONLIGHT * 0.25, mix(SKY_DAY, SKY_VEILED, VEIL) + 0.5), byDay(SKY_LEY_NIGHT * 2.0, SKY_LEY_DAY + 0.4), SHIFT);
  c += sky * hardSpot(R, vec3(0.0, 1.0, 0.0), SKY_SPOT) * SKY_SPOT_GAIN;
  // every point of light nearby (blooms, motes) is mirrored too
  c += mirrored;
  // facets of the rippling skin, each leaning its own way and turning
  // slowly, flashing as one swings through the light's mirror
  float t = pc.eye_time.w;
  vec3 q = obj * GLINT_CELLS;
  vec3 id = floor(q);
  vec3 h = hash33(id + 31.0);
  if (h.x < GLINT_SHARE) {
    float facet = 1.0 - smoothstep(GLINT_SIZE * 0.8, GLINT_SIZE, length(q - id - 0.5 - (h.yzx - 0.5) * 0.3));
    float a = t * GLINT_RATE * (0.5 + h.z) + h.y * TAU;
    vec3 lean = (hash33(id + 57.0) - 0.5) * 2.0 + vec3(cos(a), sin(a * 0.7), sin(a)) * 0.6;
    vec3 fn = normalize(n + lean * GLINT_TILT);
    c += key * hardSpot(reflect(-V, fn), SUN, GLINT_SPOT) * facet * GLINT_GAIN * sh;
  }
  // the light focused through a clear body: seen through it on the far
  // wall (a sphere's chord from where the view enters, bent), where that
  // wall faces away from the light
  vec3 r = refract(-V, n, 1.0 / SAP_IOR);
  vec3 far = n - 2.0 * dot(n, r) * r;
  c += sapc * key * hardSpot(far, -SUN, CAUSTIC_SPOT) * CAUSTIC_GAIN * clear * mix(0.4, 1.0, sh);
  // the edge: a thin hard line of sky
  float ndv = dot(n, V);
  float edge = (1.0 - smoothstep(EDGE_LINE * 0.75, EDGE_LINE, ndv)) * step(0.0, ndv);
  c += mix(sapc, vec3(1.0), 0.6) * byDay(MOONLIGHT * 0.3, vec3(1.0)) * edge * EDGE_GAIN;
  return c;
}
vec3 sapGlisten(vec3 n, vec3 V, vec3 wpos, vec3 obj, vec3 sapc, float clear, float sh) {
  return sapGlistenWith(n, V, wpos, obj, sapc, clear, sh, pointLights(wpos, n, reflect(-V, n), true).mirrored);
}


// the drawn world ends a little before the streamed one: close it into the
// horizon so a low camera never sees an edge. (The air itself, haze and
// mist, is the fog pass's: fog.frag.)
vec3 applyFog(vec3 c, vec3 wpos) {
  float f = smoothstep(pc.view.z, pc.view.w, length(wpos.xz - pc.view.xy));
  return mix(c, pc.fog.rgb, f);
}

// a halo forming (game/structures/polyp.zig): over k 0..1 its blooms spiral
// in from their corners to its centre, the share of the way covered growing
// as e^(HALO_RUSH k) (a crawl, then a rush) while they turn HALO_TURNS times
// around it, folding back toward buds over the last HALO_FOLD of it
const float HALO_RUSH = 4.0;
const float HALO_TURNS = 1.25;
const float HALO_FOLD = 0.3;
float haloPull(float k) { return (exp(HALO_RUSH * clamp(k, 0.0, 1.0)) - 1.0) / (exp(HALO_RUSH) - 1.0); }
float haloFold(float k) { return smoothstep(1.0 - HALO_FOLD, 1.0, k); }
// how far around the centre a bloom has turned by k (radians)
float haloTurn(float k) { return HALO_TURNS * TAU * haloPull(k); }
// where a point riding with a bloom is at k: its way out from the centre
// turned and shortened
vec3 haloSpiral(vec3 p, vec3 centre, float k) {
  float pull = haloPull(k);
  float a = haloTurn(k);
  vec3 d = p - centre;
  float c = cos(a), s = sin(a);
  return centre + vec3(d.x * c - d.z * s, d.y, d.x * s + d.z * c) * (1.0 - pull);
}

// the radiant lineage's one way of forming (gfx/meshes/radiant_kit.zig):
// never grown, gathered. Each fragment (petal, thread, mote, facet), joined
// to nothing, comes in from afar on its own way, turning round the heart as
// it comes, and settles in its place in its turn.
// a fragment as the kit marks it: tu.x its assembly order, tu.y its ring
// (radiant_kit.Ring) plus, on a thread, how far it is from what it holds
// (held 1 there .. 0 at the heart), colour alpha its bearing
const float RADIANT_THREAD = 0.9;
struct Fragment { float order; float ring; float held; float bearing; };
Fragment fragmentOf(vec2 tu, float a) {
  return Fragment(tu.x, floor(tu.y + 0.01), 1.0 - fract(tu.y + 0.01) / RADIANT_THREAD, a * TAU);
}
// how far a fragment still is from its place (1 setting out .. 0 settled)
// when its thing is `k` gathered: each `pace` of its order later than the
// first, taking `span` to come in
float gatherAway(float order, float pace, float span, float k) { return 1.0 - grownPast(order, pace, span, k); }
// where a fragment `away` from its place is: drawn in from `from` (its
// offset when furthest out, mesh space), shrunk toward the heart by
// `shrink` (a shard), turned `turn` radians round the heart's up axis
vec3 gatherIn(vec3 p, vec3 from, float away, float shrink, float turn) {
  vec3 q = p * (1.0 - shrink * away) + from * away;
  q.xz = rot(away * turn) * q.xz;
  return q;
}
// its normal, turned with it
vec3 gatherTurn(vec3 n, float away, float turn) { return gatherIn(n, vec3(0.0), away, 0.0, turn); }

// light split into its spectrum, x 0 red .. 1 violet, as a prism or an ice
// halo fans it out
vec3 spectral(float x) {
  x = clamp(x, 0.0, 1.0);
  return vec3(
    smoothstep(0.42, 0.0, x) + 0.55 * smoothstep(0.78, 1.0, x),
    smoothstep(0.02, 0.32, x) * smoothstep(0.82, 0.45, x),
    smoothstep(0.38, 0.75, x)
  );
}
