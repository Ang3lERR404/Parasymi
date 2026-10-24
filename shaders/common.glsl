// shared push constants + lighting for world passes.
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
  vec4 feet[2];   // the wolf's paws: xyz world position, w facing yaw
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
// a light or a colour that turns with the day: `night` by night, `day` at noon
vec3 byDay(vec3 night, vec3 day) { return mix(night, day, DAYLIGHT); }

// this frame's light (render/light.zig `Lighting`): the key light's shadow
// cascades and the points of light the garden makes
const int CASCADES = 3;
const int MAX_LIGHTS = 32;
struct PointLight {
  vec4 pos; // xyz where, w how far it reaches
  vec4 col; // linear rgb times its strength
};
layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer Lighting {
  mat4 cascade[CASCADES]; // world to each cascade's clip space
  float texel[4];         // the world size of each cascade's texels
  vec4 info;              // x points of light, y how far from the eye shadows reach
  PointLight lights[MAX_LIGHTS];
};
// the shadow map: a depth layer per cascade, read with depth compares
layout(set = 0, binding = 0) uniform sampler2DArrayShadow shadow_map;

// where a world point lands on screen (or, drawing shadow casters, in the
// cascade this view draws)
vec4 project(vec3 w) {
#ifdef SHADOW
  return Lighting(pc.light).cascade[gl_ViewIndex] * vec4(w, 1.0);
#else
  return pc.vp * vec4(w, 1.0);
#endif
}
// a vertex placed here is clipped away (what casts no shadow)
const vec4 UNSEEN = vec4(0.0, 0.0, 2.0, 1.0);

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
// sets of roles, one bit each: a shader keys what roles do alike off a set
// (PART_IN), so a new role joins a behaviour by joining its set
#define PART_BIT(p) (1u << uint(p))
#define PART_IN(set, p) ((((set) >> uint(p)) & 1u) != 0u)
// the roles that are light itself: they cast no shadow (part.vert SHADOW)
// and are not lit by the key light (part.frag)
const uint PARTS_LIGHT = PART_BIT(PART_THREAD) | PART_BIT(PART_FLASH) | PART_BIT(PART_HALO) | PART_BIT(PART_PROJECTION);
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
bool isForm(float f, float form) { return abs(f - form) < 0.5; }
// sets of forms, one bit each (as the roles' sets): what forms do alike is
// keyed off a set (formIn), so a new form joins a behaviour by joining it
#define FORM_BIT(f) (1u << uint(f))
bool formIn(uint set, float f) { return ((set >> uint(f + 0.5)) & 1u) != 0u; }
// the forms whose petals are a lantern of clear sap (meshgen `lantern`,
// below LANTERN_TOP along the plant): it is drawn see-through and, being
// clear, casts no shadow (plant.vert SHADOW and plant.frag agree on it)
const uint FORMS_LANTERN = FORM_BIT(FORM_DRIFT);
const float LANTERN_TOP = 0.75;
bool isLantern(float form, int part, float h) { return part == PART_BLOOM && h < LANTERN_TOP && formIn(FORMS_LANTERN, form); }

// tile kinds (world tile `Kind`, info.x * 255; must match)
const int TILE_WATER = 0;
const int TILE_SOIL = 1;

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

// bubbles floating up through sap: a rim-lit ring mask, sampled at two
// depths behind the surface along the view so they hang inside it. `obj`
// is the mesh-space point (they ride with the body), `view` toward the eye.
const float BUBBLE_DEPTH = 0.012;  // how far behind the surface the near layer hangs
const float BUBBLE_CELLS = 36.0;   // bubble cells per unit (near layer)
const float BUBBLE_RISE = 0.3;     // how fast they rise (cells/s, near layer)
const float BUBBLE_SHARE = 0.3;    // the share of cells holding one
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
    // a thin bright skin, a clear middle
    b += (smoothstep(r, r * 0.78, d) - 0.7 * smoothstep(r * 0.72, r * 0.35, d)) * (1.0 - 0.45 * fl);
  }
  return b;
}

// beads of sap clinging to a surface, sliding slowly down it: x the bead,
// y its glint (a dome lit off-centre by `light`)
const float DROP_CELLS = 52.0;    // bead cells per unit
const float DROP_SLIDE = 0.1;     // how fast they slide down (cells/s)
const float DROP_SHARE = 0.4;     // the share of cells holding one
const float DROP_GLINT_POW = 48.0; // how tight a bead's glint is
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
  float glint = pow(max(dot(reflect(-light, bn), view), 0.0), DROP_GLINT_POW);
  return vec2(bead, bead * glint);
}

// the palette's sRGB colours to linear (a plain power curve)
const float GAMMA = 2.2;
vec3 srgb2lin(vec3 c) { return pow(c, vec3(GAMMA)); }

// texels apart the shadow filter's taps are
const float SHADOW_TAP = 1.2;
// how far a point is pushed off its surface toward the light (texels), and
// how much more where the light grazes it
const float SHADOW_BIAS = 0.8;
const float SHADOW_SLOPE_BIAS = 2.0;
// how far out across a cascade (0 centre .. 1 rim) it starts blending into
// the next, and is wholly the next
const float CASCADE_BLEND_FROM = 0.82;
const float CASCADE_BLEND_TO = 0.97;
// the share of the shadows' reach past which they fade out
const float SHADOW_FADE = 0.8;

// how much of the key light reaches `wpos` through cascade `i` (1 lit, 0
// in shadow), filtered over 2x2 taps of 2x2 compares each; `edge` how far
// out across the cascade it lies (0 centre .. 1 rim; 2 outside it). The
// point is pushed off its surface toward the light by a texel or so (more
// on slopes the light grazes) so a surface never shadows itself.
float cascadeLit(Lighting L, int i, vec3 wpos, vec3 nl, float slope, out float edge) {
  float tx = L.texel[i];
  vec4 q = L.cascade[i] * vec4(wpos + nl * tx * (SHADOW_BIAS + SHADOW_SLOPE_BIAS * slope), 1.0);
  edge = max(abs(q.x), abs(q.y));
  if (edge >= 1.0 || q.z >= 1.0) {
    edge = 2.0;
    return 1.0;
  }
  vec2 uv = q.xy * 0.5 + 0.5;
  vec2 tap = SHADOW_TAP / vec2(textureSize(shadow_map, 0).xy);
  float s = 0.0;
  for (int y = 0; y < 2; y++) for (int x = 0; x < 2; x++) {
    s += texture(shadow_map, vec4(uv + (vec2(x, y) - 0.5) * tap, float(i), q.z));
  }
  return s * 0.25;
}

// how much of the key light (sun or moon) reaches a surface at `wpos`
// facing `n`: from the nearest cascade holding it, blended into the next
// over its rim so no seam shows, fading out toward the shadows' reach
float keyShadow(vec3 wpos, vec3 n) {
  Lighting L = Lighting(pc.light);
  float far = L.info.y;
  float dist = length(wpos - pc.eye_time.xyz);
  if (dist >= far) return 1.0;
  float ndl = dot(n, SUN);
  vec3 nl = ndl >= 0.0 ? n : -n;
  float slope = sqrt(clamp(1.0 - ndl * ndl, 0.0, 1.0));
  float lit = 1.0;
  for (int i = 0; i < CASCADES; i++) {
    float edge;
    float s = cascadeLit(L, i, wpos, nl, slope, edge);
    if (edge > 1.0) continue;
    float b = smoothstep(CASCADE_BLEND_FROM, CASCADE_BLEND_TO, edge);
    if (b > 0.0) {
      float e2;
      float s2 = i + 1 < CASCADES ? cascadeLit(L, i + 1, wpos, nl, slope, e2) : 1.0;
      s = mix(s, s2, b);
    }
    lit = s;
    break;
  }
  return mix(lit, 1.0, smoothstep(far * SHADOW_FADE, far, dist));
}

// the light the garden's points of light (blooms, motes, a halo) shed on a
// surface at `wpos` facing `n`: each brightest beside it, gone at its
// reach. `wrap` > 0 lets light reach round thin tissue (0 a plain surface).
const float LIGHT_FALLOFF = 8.0; // how fast a point of light dims with (distance / reach)^2
vec3 pointLight(vec3 wpos, vec3 n, float wrap) {
  Lighting L = Lighting(pc.light);
  int count = int(L.info.x + 0.5);
  vec3 sum = vec3(0.0);
  for (int i = 0; i < count; i++) {
    vec4 lp = L.lights[i].pos;
    vec3 d = lp.xyz - wpos;
    float d2 = dot(d, d);
    float k = d2 / (lp.w * lp.w);
    if (k >= 1.0) continue;
    float win = (1.0 - k) * (1.0 - k);
    float facing = (dot(n, d) * inversesqrt(max(d2, 1e-6)) + wrap) / (1.0 + wrap);
    sum += L.lights[i].col.rgb * max(facing, 0.0) * win / (1.0 + LIGHT_FALLOFF * k);
  }
  return sum;
}

// the key light's strength: the moon's by night, the sun's by day
const float MOON_STRENGTH = 0.35;
const float SUN_STRENGTH = 1.1;
// the key light's colour and strength (the sun by day, the moon by night)
vec3 keyLight() { return byDay(MOONLIGHT * MOON_STRENGTH, SUNLIGHT * SUN_STRENGTH); }

// the ambient light: the sky's by day (veiled, toward violet), by night, the
// ground's bounce (dimmed to this share by night), and how strong it all is
const vec3 SKY_DAY = vec3(0.35, 0.40, 0.50);
const vec3 SKY_VEILED = vec3(0.45, 0.30, 0.65);
const vec3 SKY_NIGHT = vec3(0.07, 0.09, 0.18);
const vec3 GROUND_BOUNCE = vec3(0.12, 0.10, 0.08);
const float GROUND_NIGHT = 0.3;
const float AMBIENT = 0.55;
// a surface lit by the sky, the key light (`sh` of it reaching it, see
// keyShadow) and the points of light
vec3 shadeLit(vec3 albedo, vec3 n, vec3 wpos, float sh) {
  float ndl = max(dot(n, SUN), 0.0);
  float day = DAYLIGHT;
  vec3 sky = mix(SKY_DAY, SKY_VEILED, VEIL);
  sky = byDay(SKY_NIGHT, sky);
  vec3 ground = GROUND_BOUNCE * mix(GROUND_NIGHT, 1.0, day);
  vec3 amb = mix(ground, sky, n.y * 0.5 + 0.5) * AMBIENT;
  vec3 sun = keyLight() * ndl * sh;
  return albedo * (amb + sun + pointLight(wpos, n, 0.0));
}

vec3 shade(vec3 albedo, vec3 n, vec3 wpos) { return shadeLit(albedo, n, wpos, keyShadow(wpos, n)); }


vec3 applyFog(vec3 c, vec3 wpos) {
  float d = length(wpos - pc.eye_time.xyz);
  float f = 1.0 - exp(-pow(d * pc.fog.w, 2.0));
  // the drawn world ends a little before the streamed one: close it into the
  // horizon so a low camera never sees an edge
  f = max(f, smoothstep(pc.view.z, pc.view.w, length(wpos.xz - pc.view.xy)));
  return mix(c, pc.fog.rgb, clamp(f, 0.0, 1.0));
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
