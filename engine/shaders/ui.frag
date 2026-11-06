#version 450
//! organic UI, all of it grown: every shape is an animated signed-distance
//! field. No boxes: panels are vine trellises, slots hanging husks, bars
//! leafy stems.
layout(push_constant) uniform Push { vec2 screen; float time; float pad; } pc;
layout(location = 0) in vec2 v_uv;
layout(location = 1) in vec4 v_col;
layout(location = 2) flat in uvec2 v_bits;
layout(location = 3) flat in vec2 v_size;
layout(location = 4) flat in vec2 v_param;
// the rectangle it is cut to, and where this fragment sits (screen pixels)
layout(location = 5) flat in vec4 v_clip;
layout(location = 6) in vec2 v_px;
layout(location = 0) out vec4 o;

const float PAD = 28.0;
const float PI = 3.14159;
const float TAU = 6.2832;
// sap's glow, what every shape brightens toward where sap shows
const vec3 UI_SAP = vec3(1.0, 0.78, 0.35);
// vine green: the night's veins, a pod's rim
const vec3 MEMBRANE_RIM = vec3(0.18, 0.42, 0.20);
const vec3 POD_RIM = vec3(0.25, 0.5, 0.25);
// a trellis panel: its vines (bark lit, bark shaded), their leaves, buds of
// sap on them, and the woven withies of the lattice behind
const vec3 VINE_LIT = vec3(0.30, 0.50, 0.20);
const vec3 VINE_SHADE = vec3(0.10, 0.19, 0.08);
const vec3 TRELLIS_LEAF = vec3(0.27, 0.58, 0.22);
const vec3 TRELLIS_BUD = vec3(0.95, 0.66, 0.26);
const vec3 WITHY = vec3(0.24, 0.19, 0.12);
// strands' radius and how far they swing about the rim as they braid (px),
// braid crossings per px of rim, how far a tip tapers off (px)
const float VINE_R = 3.4;
const float VINE_BRAID = 3.2;
const float VINE_TWIST = 0.011;
const float VINE_TIP = 46.0;
// px of rim between leaf nodes; a leaf's length and half width (px); how
// far past a node the growing tip is when its leaf has opened (px)
const float LEAF_EVERY = 30.0;
const float TRELLIS_LEAF_LEN = 16.0;
const float TRELLIS_LEAF_WID = 5.5;
const float LEAF_UNFURL = 70.0;
// share of nodes that put out a bud of sap, a curling tendril
const float NODE_BUD = 0.22;
const float NODE_CURL = 0.16;
// the lattice: spacing of its diagonal withies (px), their half width
const float LATTICE = 46.0;
const float WITHY_R = 1.1;
// how strongly the lattice shows through the bed (kept low: text sits on it)
const float LATTICE_SHOW = 0.16;
// a husk slot: the stalk's reach above its centre, and its sepals
const float HUSK_STALK = 1.6;
const float HUSK_SEPAL_LEN = 0.55;
const float HUSK_SEPAL_WID = 0.2;
// a stem bar: px between its leaves, a leaf's length and width as shares of
// the bar's height, px past a leaf the tip is when it has opened
const float STEM_LEAF_EVERY = 22.0;
const float STEM_LEAF_LEN = 1.05;
const float STEM_LEAF_WID = 0.36;
const float STEM_UNFURL = 18.0;
// warm white: a tendril's bud, a gem's edges
const vec3 BUD_GLOW = vec3(1.0, 0.85, 0.5);
const vec3 GEM_EDGE = vec3(1.0, 0.97, 0.9);
// glyph stems (cells are 1 across): radius where text is small (stout to
// stay legible) and big (slender vines); a tip's, a lone seed's and a fork's
// radius as shares of it
const float GLYPH_THICK = 0.42;
const float GLYPH_SLENDER = 0.27;
const float GLYPH_TIP = 0.6;
const float GLYPH_SEED = 1.25;
const float GLYPH_NODE = 1.15;
// leaves on stem tips fade in between these sizes (screen pixels per cell)
const float GLYPH_LEAF_FROM = 1.8;
const float GLYPH_LEAF_FULL = 3.0;
const float GLYPH_LEAF_LEN = 1.1;
const float GLYPH_LEAF_WID = 0.3;
// share of a big glyph's plain stem nodes that put out a leaf too
const float GLYPH_LEAF_MID = 0.3;
// how far (cells) a big glyph's stems bow, like grown ones
const float GLYPH_BOW = 0.3;
// glyph quads reach this far (cells) past the bitmap, room for leaves
const float GLYPH_PAD = 1.0;
const vec3 GLYPH_LEAF_GREEN = vec3(0.35, 0.75, 0.3);
// how far (cells) a glyph's top sways
const float GLYPH_SWAY = 0.08;
// coverage below which a fragment is dropped: shapes, glyphs
const float SHAPE_CLEAR = 0.003;
const float GLYPH_CLEAR = 0.01;
// a quad is a shape when its bits' x is SHAPE_MARK (else a glyph's bitmap),
// its bits' y which (ui/draw.zig `Shape`, its u32 value; must match)
const uint SHAPE_MARK = 0xffffffffu;
const uint SHAPE_TRELLIS = 0u;
const uint SHAPE_POD = 1u;
const uint SHAPE_TENDRIL = 2u;
const uint SHAPE_GLOW = 3u;
const uint SHAPE_LIMB = 4u;
const uint SHAPE_LEAF = 5u;
const uint SHAPE_GRAIN = 6u;
const uint SHAPE_GEM = 7u;
const uint SHAPE_NIGHT = 8u;
const uint SHAPE_HUSK = 9u;
const uint SHAPE_DUSK = 10u;
const uint SHAPE_BLOSSOM = 11u;
const uint SHAPE_GALL = 12u;
const uint SHAPE_SHARD = 13u;
const uint SHAPE_KNOT = 14u;
const uint SHAPE_SWATCH = 15u;
// the research tree's painting: the dark it hangs in, the soil under it, the
// moon low behind (a share of the screen across and down), its pale light
const vec3 DUSK_HIGH = vec3(0.003, 0.0028, 0.006);
const vec3 DUSK_LOW = vec3(0.010, 0.008, 0.013);
const vec3 DUSK_EARTH = vec3(0.016, 0.010, 0.006);
const vec3 DUSK_DEEP = vec3(0.003, 0.002, 0.0015);
const vec3 DUSK_MOSS = vec3(0.035, 0.07, 0.025);
// the warm light pooled over the soil where the tree stands (linear)
const vec3 DUSK_WARM = vec3(0.020, 0.011, 0.005);
// the grain laid over the painting, against banding (linear)
const float DUSK_GRAIN = 0.0016;
const vec2 DUSK_MOON = vec2(0.2, 0.2);
const vec3 DUSK_MOON_LIGHT = vec3(0.80, 0.84, 0.95);
// what drifts down through it: petals, small flowers, seeds on fluff,
// leaves and pollen, in a far layer and a near one (cell sizes, px; how
// fast each falls, px a second; the share of cells holding one)
const float DRIFT_FAR = 64.0;
const float DRIFT_NEAR = 118.0;
const float DRIFT_FAR_FALL = 9.0;
const float DRIFT_NEAR_FALL = 17.0;
const float DRIFT_SHARE = 0.34;
const vec3 DRIFT_PETAL = vec3(0.93, 0.70, 0.78);
const vec3 DRIFT_LILAC = vec3(0.72, 0.62, 0.92);
const vec3 DRIFT_LEAF = vec3(0.36, 0.58, 0.26);
const vec3 DRIFT_SEED = vec3(0.45, 0.32, 0.20);
const vec3 DRIFT_FLUFF = vec3(0.92, 0.92, 0.88);
// the stamens every opened flower shows (filaments, anthers)
const vec3 STAMEN = vec3(0.92, 0.78, 0.36);
const vec3 ANTHER = vec3(1.0, 0.88, 0.45);
// a symbiotic node: its sepals' and leaves' green
const vec3 BLOSSOM_LEAF = vec3(0.30, 0.56, 0.24);
// a parasitic node: its thorns' bone, its mouth's glow
const vec3 GALL_THORN = vec3(0.86, 0.80, 0.70);
const vec3 GALL_MAW = vec3(0.95, 0.35, 0.65);
// a convergent node: its two strands, one of each lineage
const vec3 KNOT_SYM = vec3(0.40, 0.72, 0.32);
const vec3 KNOT_PAR = vec3(0.62, 0.30, 0.66);

// integer hash of a lattice point: exact at any magnitude (a sin()-based hash
// loses precision as time grows and shows up as crawling speckle)
float hash(vec2 p) {
  uvec2 q = uvec2(ivec2(p)) * uvec2(1597334673u, 3812015801u);
  uint n = (q.x ^ q.y) * 1597334673u;
  n ^= n >> 16;
  return float(n) * (1.0 / 4294967295.0);
}
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// noise around a closed outline: sampled on a circle so it wraps seamlessly
// (keying noise on the raw angle would jump where atan wraps from +pi to -pi)
float ringNoise(float ang, float freq, float seed, float drift) {
  return vnoise(vec2(cos(ang), sin(ang)) * freq + vec2(seed * 10.0 + drift, seed * 7.0 - drift * 0.7));
}

// rounded-rect distance, used as the skeleton for membranes
float sdRound(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec3 sapColor(vec3 base, float k) { return mix(base, UI_SAP, k); }

vec2 rot(vec2 p, float a) { float c = cos(a), s = sin(a); return vec2(c * p.x - s * p.y, s * p.x + c * p.y); }

// distance to a stem tapering from radius ra at a to rb at b
float sdStem(vec2 p, vec2 a, vec2 b, float ra, float rb) {
  vec2 ab = b - a;
  float h = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
  return length(p - a - ab * h) - mix(ra, rb, h);
}

// distance to a leaf from `base` along unit `u`, `len` long, `wid` across
float sdGlyphLeaf(vec2 p, vec2 base, vec2 u, float len, float wid) {
  vec2 r = p - base;
  float x = dot(r, u);
  float y = dot(r, vec2(-u.y, u.x));
  float k = clamp(x / len, 0.0, 1.0);
  float w = wid * pow(sin(PI * pow(k, 0.7)), 0.8);
  return max(abs(y - wid * 0.4 * k * k) - w, max(-x, x - len));
}

// a small leaf's colour at `p`, `u` its direction from `base`: lit and
// shaded halves about the midrib, sap in the thin margin
vec3 leafShade(vec2 p, vec2 base, vec2 u, float wid, vec3 green) {
  float y = dot(p - base, vec2(-u.y, u.x));
  float across = clamp(y / max(wid, 0.5), -1.0, 1.0);
  vec3 col = green * (across > 0.0 ? 1.0 : 0.72);
  col *= 1.0 + 0.3 * smoothstep(0.9, 0.0, abs(y));
  return sapColor(col, smoothstep(0.6, 1.0, abs(across)) * 0.25);
}

// arc length round a rounded rect's outline (half extents b, corner radius
// r), clockwise on screen from the top edge's left end; P the whole way round
float rimS(vec2 c, vec2 b, float r, out float P) {
  vec2 h = b - r;
  float q = 0.5 * PI * r;
  P = 4.0 * (h.x + h.y + q);
  if (abs(c.x) <= h.x) return c.y < 0.0 ? c.x + h.x : 2.0 * h.x + 2.0 * q + 2.0 * h.y + (h.x - c.x);
  if (abs(c.y) <= h.y) return c.x > 0.0 ? 2.0 * h.x + q + (c.y + h.y) : 4.0 * h.x + 3.0 * q + 2.0 * h.y + (h.y - c.y);
  vec2 k = c - sign(c) * h;
  float a = atan(k.x, -k.y);                 // 0 up, pi/2 right, ±pi down
  if (c.x > 0.0 && c.y < 0.0) return 2.0 * h.x + r * a;
  if (c.x > 0.0) return 2.0 * h.x + q + 2.0 * h.y + r * (a - 0.5 * PI);
  if (c.y > 0.0) return 4.0 * h.x + 2.0 * q + 2.0 * h.y + r * (a + PI);
  return 4.0 * h.x + 3.0 * q + 4.0 * h.y + r * (a + 0.5 * PI);
}

// a panel: a dark bed of leaf litter behind a lattice of woven withies,
// framed by two vines braided round its rim, rooted at its lower left
// corner. They grow both ways round as `grow` runs 0..1 (meeting at the
// upper right), tips tapering; leaves unfurl off their nodes once the tips
// have passed, some nodes bear a bud of sap or a curling tendril; leaves
// sway, sap pulses climb out from the root.
vec4 trellis(vec2 px, float grow, float seed) {
  float t = pc.time;
  vec2 inner = v_size - 2.0 * PAD;
  vec2 c = px - v_size * 0.5;
  float r = min(min(inner.x, inner.y) * 0.3, 40.0);
  float d = sdRound(c, inner * 0.5, r) + (vnoise(px * 0.05 + seed * 9.0) - 0.5) * 1.5;
  float P;
  float s = rimS(c, inner * 0.5, r, P);
  // the root: the middle of the lower left corner's arc
  float root = 4.0 * (inner.x * 0.5 - r) + 2.5 * 0.5 * PI * r + 2.0 * (inner.y * 0.5 - r);
  float reach = grow * P * 0.5;
  float from = abs(s - root);
  from = min(from, P - from);

  // the bed and its lattice
  float fill = smoothstep(1.5, -1.5, d);
  float bed = smoothstep(0.0, 0.6, grow);
  vec3 col = v_col.rgb * (0.78 + 0.22 * vnoise(px * 0.018 + seed * 3.0) + 0.08 * vnoise(px * 0.11 + seed));
  vec2 dg = vec2(c.x + c.y, c.x - c.y) * 0.7071 + seed * 17.0;
  vec2 cell = floor(dg / LATTICE + 0.5);
  vec2 off = abs(dg - cell * LATTICE);
  float wu = smoothstep(WITHY_R + 0.8, WITHY_R - 0.4, off.x);
  float wv = smoothstep(WITHY_R + 0.8, WITHY_R - 0.4, off.y);
  // over and under in turn at each crossing
  bool uTop = mod(cell.x + cell.y, 2.0) < 0.5;
  float under = smoothstep(0.0, 6.0, uTop ? off.x : off.y);
  vec3 withy = WITHY * (0.75 + 0.25 * vnoise(dg * vec2(0.3, 0.05)));
  float lat = smoothstep(0.3, 1.0, grow) * LATTICE_SHOW;
  col = mix(col, withy * (uTop ? 1.0 : mix(0.55, 1.0, under)), wv * lat);
  col = mix(col, withy * (uTop ? mix(0.55, 1.0, under) : 1.0), wu * lat * (uTop ? 1.0 : 1.0 - wv * (1.0 - under)));
  // the vines' shade falls in a little from the rim
  col *= 1.0 - 0.35 * smoothstep(-16.0, 0.0, d) * bed;
  float a = fill * v_col.a * bed;
  // a soft shadow round the panel, so it lifts off the world
  float shadow = exp(-max(d, 0.0) * 0.2) * (1.0 - fill) * 0.45 * bed * smoothstep(PAD - 4.0, PAD - 14.0, d);
  col = mix(col, vec3(0.0), shadow / max(a + shadow, 1e-3));
  a = max(a, shadow);

  // the braid: two strands crossing about the rim
  float nb = max(2.0, floor(P * VINE_TWIST + 0.5));
  float ph = TAU * nb * s / P;
  float drift = sin(s * 0.03 + t * 0.7 + seed * 5.0) * 0.6;
  float o1 = VINE_BRAID * sin(ph) + drift;
  float o2 = -VINE_BRAID * sin(ph) + drift;
  float tipR = VINE_R * sqrt(clamp((reach - from) / VINE_TIP, 0.0, 1.0));
  float r1 = tipR * (0.92 + 0.12 * vnoise(vec2(s * 0.04, 1.0)));
  float r2 = tipR * (0.82 + 0.12 * vnoise(vec2(s * 0.04, 7.0)));
  float pulse = pow(0.5 + 0.5 * sin(from * 0.045 - t * 2.2 + seed * 9.0), 6.0);
  bool oneTop = cos(ph) > 0.0;
  for (int k = 0; k < 2; k++) {
    bool first = (k == 0) != oneTop;           // the strand under goes first
    float o = first ? o1 : o2;
    float rr = first ? r1 : r2;
    float dv = abs(d - o) - rr;
    float cov = smoothstep(0.8, -0.8, dv) * step(0.05, rr);
    float across = clamp((d - o) / max(rr, 0.5), -1.0, 1.0);
    float shade = 0.55 + 0.45 * sqrt(max(0.0, 1.0 - across * across)) - 0.15 * across;
    float groove = vnoise(vec2(s * 0.12, across * 2.5 + (first ? 3.0 : 9.0)));
    vec3 bark = mix(VINE_SHADE, VINE_LIT, shade) * (0.85 + 0.3 * groove);
    bark = sapColor(bark, pulse * 0.45 * (1.0 - abs(across)));
    col = mix(col, bark, cov);
    a = max(a, cov);
  }

  // nodes along the rim: a leaf each, now and then a bud or a curl
  float n = max(4.0, floor(P / LEAF_EVERY + 0.5));
  float sp = P / n;
  float i0 = floor(s / sp);
  for (int j = -1; j <= 1; j++) {
    float i = mod(i0 + float(j), n);
    float h = hash(vec2(i, seed * 53.0));
    float h2 = hash(vec2(i + 31.0, seed * 19.0));
    float si = (i + 0.5 + (h - 0.5) * 0.5) * sp;
    float x = s - si;
    x -= P * floor(x / P + 0.5);
    float fi = abs(si - root);
    fi = min(fi, P - fi);
    float open = smoothstep(0.0, LEAF_UNFURL, reach - fi);
    if (open <= 0.0) continue;
    float yo = mod(i, 2.0) < 0.5 ? o1 : o2;
    vec2 q = vec2(x, d);
    vec2 base = vec2(0.0, yo);
    // leaves lean along the rim, most out over the world, some in over the bed
    float side = h2 > 0.5 ? 1.0 : -1.0;
    float outward = h > 0.3 ? 1.0 : -1.0;
    float ang = side * (0.55 + 0.45 * h2) + sin(t * 1.6 + h * TAU) * 0.12;
    vec2 u = vec2(sin(ang), cos(ang) * outward);
    float len = TRELLIS_LEAF_LEN * (0.7 + 0.5 * h) * (outward > 0.0 ? 1.0 : 0.7) * mix(0.35, 1.0, open);
    float wid = TRELLIS_LEAF_WID * mix(0.4, 1.0, open) * (0.8 + 0.3 * h2);
    float dl = sdGlyphLeaf(q, base + u * VINE_R * 0.5, u, len, wid);
    float cov = smoothstep(0.8, -0.8, dl);
    if (cov > 0.0) {
      vec3 green = mix(TRELLIS_LEAF, TRELLIS_LEAF * vec3(1.2, 1.1, 0.7), h2 * 0.5);
      col = mix(col, leafShade(q, base, u, wid, green), cov);
      a = max(a, cov);
    }
    float pick = fract(h * 7.31 + h2 * 3.7);
    if (pick < NODE_BUD) {
      // a bud of sap on the strand, swelling as it opens
      vec2 bc = base + vec2(-side * 5.0, outward * 3.0);
      float db = length(q - bc) - 3.4 * open;
      float bcov = smoothstep(0.8, -0.8, db);
      vec2 bq = (q - bc) / max(3.4 * open, 0.5);
      vec3 bud = TRELLIS_BUD * (0.7 + 0.3 * smoothstep(1.0, -0.6, bq.x + bq.y)) + BUD_GLOW * smoothstep(0.5, 0.0, length(bq - vec2(-0.35, -0.35))) * 0.6;
      col = mix(col, bud, bcov);
      a = max(a, bcov);
    } else if (pick > 1.0 - NODE_CURL) {
      // a tendril curling off the node, out over the world
      vec2 cc = base + vec2(-side * 8.0, 11.0);
      vec2 cq = q - cc;
      float rr = length(cq);
      float an = atan(cq.y, cq.x * -side);
      const float PITCH = 3.0;
      float kk = rr / PITCH - an / TAU;
      float dc = max(abs(kk - floor(kk + 0.5)) * PITCH - 0.8, rr - 7.5 * open);
      dc = min(dc, sdStem(q, base, cc + vec2(side * 7.0, 0.0) * open, 1.2, 0.8));
      float ccov = smoothstep(0.7, -0.7, dc) * step(1.0, rr + 1.0);
      col = mix(col, VINE_LIT * 1.1, ccov);
      a = max(a, ccov);
    }
  }
  return vec4(col, clamp(a, 0.0, 1.0));
}

vec4 pod(vec2 px, float lit, float seed) {
  float t = pc.time;
  vec2 c = px - v_size * 0.5;
  float R = (v_size.x - 2.0 * PAD) * 0.5;
  float ang = atan(c.y, c.x);
  float breathe = 1.0 + 0.04 * sin(t * 1.8 + seed * 6.0);
  float wob = (ringNoise(ang, 1.3, seed + 1.3, t * 0.8) - 0.5) * 2.5;
  float d = length(c * vec2(1.0, 1.08)) - R * breathe - wob;
  float fill = smoothstep(1.2, -1.2, d);
  // translucent shell, darker core, a sap glint
  float shade = 0.55 + 0.45 * smoothstep(R, -R, c.y + c.x * 0.4);
  vec3 body = v_col.rgb * shade * (0.6 + 0.4 * lit);
  float glint = smoothstep(R * 0.35, 0.0, length(c - vec2(-R * 0.35, -R * 0.4)));
  float rim = smoothstep(3.0, 0.0, abs(d + 1.0));
  vec3 rimc = sapColor(POD_RIM, lit);
  float halo = exp(-max(d, 0.0) * 0.18) * (1.0 - fill) * lit * (0.6 + 0.4 * sin(t * 3.0)) * smoothstep(PAD - 6.0, PAD - 16.0, d);
  vec3 col = mix(body + glint * 0.25, rimc, rim) + rimc * halo;
  return vec4(col, clamp(max(fill * v_col.a, rim) + halo, 0.0, 1.0));
}

// a slot: a seed husk hanging from its stalk, fuller below like a gourd,
// ribbed, a calyx of sepals cupping its shoulders. It swings a little on
// its stalk; `lit` fills it with sap light.
vec4 husk(vec2 px, float lit, float seed) {
  float t = pc.time;
  float R = (v_size.x - 2.0 * PAD) * 0.5;
  vec2 top = vec2(0.0, -R * HUSK_STALK);
  vec2 c = rot(px - v_size * 0.5 - top, sin(t * 1.2 + seed * 6.0) * 0.045) + top;
  float breathe = 1.0 + 0.03 * sin(t * 1.8 + seed * 6.0);
  vec2 q = c / (R * breathe);
  float w = mix(0.84, 1.04, smoothstep(-1.0, 0.6, q.y));
  vec2 e = vec2(q.x / w, q.y);
  float l = length(e);
  float d = (l - 1.0) * R * mix(w, 1.0, 0.5);
  float fill = smoothstep(1.2, -1.2, d);
  vec3 n = normalize(vec3(e, sqrt(max(0.0, 1.0 - min(l * l, 1.0)))));
  float shade = 0.5 + 0.5 * max(dot(n, normalize(vec3(-0.5, -0.6, 0.65))), 0.0);
  // ribs running from stalk to tip, darker in their seams
  float phi = asin(clamp(e.x / sqrt(max(1.0 - e.y * e.y, 1e-3)), -1.0, 1.0));
  float rib = 0.82 + 0.18 * cos(phi * 5.0);
  vec3 body = v_col.rgb * shade * rib * (0.65 + 0.35 * lit);
  body += UI_SAP * lit * 0.22 * (1.0 - min(l, 1.0)) * (0.85 + 0.15 * sin(t * 2.4 + seed * 4.0));
  float glint = smoothstep(0.35, 0.0, length(q - vec2(-0.35, -0.1)));
  float rim = smoothstep(2.5, 0.0, abs(d + 1.0));
  vec3 rimc = sapColor(POD_RIM, lit * 0.8);
  vec3 col = mix(body + glint * 0.2, rimc, rim * 0.8);
  float a = max(fill * v_col.a, rim * 0.9);
  // the calyx: sepals fanned over its shoulders from the stalk's foot
  vec2 foot = vec2(0.0, -R * 0.84);
  float ds = 1e3;
  vec2 su = vec2(0.0, 1.0);
  for (int k = 0; k < 5; k++) {
    float ang = (float(k) - 2.0) * 0.62;
    vec2 u = vec2(sin(ang), cos(ang));
    float len = R * HUSK_SEPAL_LEN * (k == 2 ? 0.6 : 1.0);
    float dk = sdGlyphLeaf(c, foot, u, len, R * HUSK_SEPAL_WID);
    if (dk < ds) { ds = dk; su = u; }
  }
  float scov = smoothstep(0.8, -0.8, ds);
  col = mix(col, leafShade(c, foot, su, R * HUSK_SEPAL_WID, TRELLIS_LEAF * 0.85), scov);
  a = max(a, scov);
  // the stalk it hangs by
  float dst = sdStem(c, foot, top, max(R * 0.11, 0.8), max(R * 0.07, 0.6));
  float tcov = smoothstep(0.8, -0.8, dst);
  float across = clamp(c.x / max(R * 0.1, 0.6), -1.0, 1.0);
  col = mix(col, mix(VINE_SHADE, VINE_LIT, 0.6 - 0.4 * across), tcov);
  a = max(a, tcov);
  float halo = exp(-max(d, 0.0) * 0.18) * (1.0 - fill) * lit * (0.6 + 0.4 * sin(t * 3.0)) * smoothstep(PAD - 6.0, PAD - 16.0, d);
  return vec4(col + rimc * halo, clamp(a + halo, 0.0, 1.0));
}

// a bar: a stem growing along local x to `value` of its length. The grown
// stem is bark tinted its colour, sap pulsing toward its tip, putting out
// leaves in turn on either side that unfurl once the tip has passed; a bud
// at the tip. Ahead of it only a faint twine marks the way.
vec4 tendril(vec2 px, float value, float seed) {
  float t = pc.time;
  vec2 inner = v_size - 2.0 * PAD;
  vec2 p = px - vec2(PAD, v_size.y * 0.5);
  float L = inner.x;
  float H = inner.y;
  float at = value * L;
  float wave = sin(p.x * 0.06 + t * 1.5 + seed * 7.0) * H * 0.1;
  float y = p.y - wave;
  float xc = clamp(p.x, 0.0, L);
  // the twine ahead
  float twine = smoothstep(1.0, 0.0, abs(y)) * step(at, p.x) * step(p.x, L) * 0.35;
  vec3 col = v_col.rgb * 0.3;
  float a = twine;
  // the stem
  float k = clamp(p.x / max(at, 1.0), 0.0, 1.0);
  float r = H * 0.32 * mix(1.0, 0.55, k);
  float dsx = length(vec2(p.x - clamp(p.x, 0.0, at), y)) - r;
  float scov = smoothstep(0.8, -0.8, dsx) * step(0.001, value);
  float across = clamp(y / max(r, 0.5), -1.0, 1.0);
  float shade = 0.6 + 0.4 * sqrt(max(0.0, 1.0 - across * across)) - 0.12 * across;
  float pulse = pow(0.5 + 0.5 * sin(p.x * 0.08 - t * 4.0), 4.0);
  vec3 bark = mix(VINE_SHADE, mix(VINE_LIT, v_col.rgb, 0.55), shade);
  bark = sapColor(bark, pulse * 0.4 * (1.0 - abs(across)));
  col = mix(col, bark, scov);
  a = max(a, scov);
  // leaves, alternating, leaning toward the tip
  float i0 = floor(p.x / STEM_LEAF_EVERY);
  for (int j = -1; j <= 1; j++) {
    float i = i0 + float(j);
    float xi = (i + 0.5) * STEM_LEAF_EVERY;
    if (xi < 4.0 || xi > at - 6.0) continue;
    float open = smoothstep(0.0, STEM_UNFURL, at - xi - 6.0);
    float side = mod(i, 2.0) < 0.5 ? -1.0 : 1.0;
    float h = hash(vec2(i, seed * 41.0));
    float ang = side * (1.0 + 0.25 * h + sin(t * 1.9 + h * TAU) * 0.1);
    vec2 u = vec2(cos(ang), sin(ang));
    vec2 base = vec2(xi, sin(xi * 0.06 + t * 1.5 + seed * 7.0) * H * 0.1);
    float len = H * STEM_LEAF_LEN * mix(0.3, 1.0, open) * (0.85 + 0.3 * h);
    float wid = H * STEM_LEAF_WID * mix(0.45, 1.0, open);
    float dl = sdGlyphLeaf(p, base, u, len, wid);
    float lcov = smoothstep(0.8, -0.8, dl);
    col = mix(col, leafShade(p, base, u, wid, mix(TRELLIS_LEAF, v_col.rgb, 0.3)), lcov);
    a = max(a, lcov);
  }
  // the bud at the growing tip
  vec2 tip = vec2(at, sin(at * 0.06 + t * 1.5 + seed * 7.0) * H * 0.1);
  float db = sdGlyphLeaf(p, tip - vec2(H * 0.15, 0.0), vec2(1.0, 0.0), H * 0.6, H * 0.26);
  float bcov = smoothstep(0.8, -0.8, db) * step(0.001, value) * step(value, 0.999);
  col = mix(col, sapColor(v_col.rgb, 0.5) + BUD_GLOW * 0.25, bcov);
  a = max(a, bcov);
  return vec4(col, clamp(a * v_col.a, 0.0, 1.0));
}

vec4 glow(vec2 px) {
  vec2 c = px - v_size * 0.5;
  float R = (v_size.x - 2.0 * PAD) * 0.5;
  float a = exp(-dot(c, c) / (R * R) * 2.5) * (0.8 + 0.2 * sin(pc.time * 2.5));
  // reach exactly zero before the quad edge so no straight border shows
  a *= smoothstep(R + PAD - 4.0, R, length(c));
  return vec4(v_col.rgb, a * v_col.a);
}

// a tapered stem segment along local x: round bark lit from one side, fibre
// grooves running along it and sap pulses rising toward the tip. `s0` is the
// arc length at its start, so consecutive segments read as one stem.
vec4 limb(vec2 px, float taper, float s0) {
  float t = pc.time;
  float L = v_size.x - 2.0 * PAD;
  float r0 = (v_size.y - 2.0 * PAD) * 0.5;
  vec2 p = px - vec2(PAD, v_size.y * 0.5);
  float k = clamp(p.x / max(L, 1e-3), 0.0, 1.0);
  float r = r0 * mix(1.0, taper, k);
  float d = length(vec2(p.x - k * L, p.y)) - r;
  float cover = smoothstep(0.8, -0.8, d);
  float across = clamp(p.y / max(r, 0.5), -1.0, 1.0);
  float s = s0 + p.x;
  float shade = 0.6 + 0.4 * sqrt(max(0.0, 1.0 - across * across)) - 0.1 * across;
  float groove = vnoise(vec2(s * 0.07, across * 2.5 + 3.0));
  vec3 col = v_col.rgb * shade * (0.8 + 0.35 * groove);
  float pulse = pow(0.5 + 0.5 * sin(s * 0.05 - t * 2.4), 6.0) * (1.0 - abs(across));
  col = sapColor(col, pulse * 0.35);
  col *= mix(1.0, 0.55, smoothstep(0.7, 1.0, abs(across)));
  return vec4(col, cover * v_col.a);
}

// a leaf blade from its base (x = 0) to its tip (x = L), or closed (open 0)
// a fat teardrop bud: lit and shaded halves about the midrib, veins, sap
// showing through the thin margin.
vec4 leaf(vec2 px, float open, float seed) {
  float L = v_size.x - 2.0 * PAD;
  float W = (v_size.y - 2.0 * PAD) * 0.5;
  vec2 p = px - vec2(PAD, v_size.y * 0.5);
  float kc = clamp(p.x / max(L, 1e-3), 0.0, 1.0);
  float prof = pow(sin(PI * pow(kc, mix(0.8, 0.62, open))), mix(1.1, 0.8, open));
  float w = W * prof;
  float y = p.y - W * 0.3 * kc * kc * sin(seed * 6.0) * open;
  float d = max(abs(y) - w, max(-p.x, p.x - L));
  float cover = smoothstep(0.8, -0.8, d);
  float across = clamp(y / max(w, 0.5), -1.0, 1.0);
  float lit = across > 0.0 ? 1.0 : mix(0.7, 0.86, open);
  float midrib = smoothstep(1.2, 0.0, abs(y)) * open;
  float veins = smoothstep(0.8, 1.0, sin((kc * 6.0 - abs(across) * 1.4) * TAU)) * open * (1.0 - abs(across));
  float margin = smoothstep(0.55, 1.0, abs(across));
  vec3 col = v_col.rgb * lit * (0.85 + 0.15 * vnoise(p * 0.15 + seed * 9.0));
  col = mix(col, col * 1.3 + vec3(0.04, 0.06, 0.02), veins * 0.5 + midrib * 0.6);
  col = sapColor(col, margin * 0.25);
  return vec4(col, cover * v_col.a * mix(0.96, 0.85, margin));
}

// a seed standing on its round end, its pointed top (where it breaks open)
// up: a lit, ridged coat with a darker seam down from the tip that splits
// open by `crack` to show green inside, and a pale hilum scar at its foot.
vec4 seedCoat(vec2 px, float crack, float seed) {
  float t = pc.time;
  vec2 inner = v_size - 2.0 * PAD;
  vec2 c = px - v_size * 0.5;
  vec2 h = inner * 0.5;
  vec2 q = c / h;                            // -1..1, y down
  float breathe = 1.0 + 0.02 * sin(t * 1.6 + seed * 6.0);
  // narrower toward the top: an egg drawn to a soft point
  float w = mix(0.55, 1.0, smoothstep(-1.0, 0.4, q.y));
  vec2 e = vec2(q.x / w, q.y) / breathe;
  float l = length(e);
  float d = (l - 1.0) * min(h.x * w, h.y);
  float cover = smoothstep(0.8, -0.8, d);
  vec3 n = normalize(vec3(e.x, e.y, sqrt(max(0.0, 1.0 - min(l * l, 1.0)))));
  float shade = 0.45 + 0.55 * max(dot(n, normalize(vec3(-0.55, -0.6, 0.6))), 0.0);
  float ridge = 0.9 + 0.1 * sin(atan(e.x, 1.0 - e.y) * 9.0 + seed * 5.0);
  float speck = vnoise(c * 0.4 + seed * 13.0);
  vec3 col = v_col.rgb * shade * ridge * (0.88 + 0.2 * speck);
  // the seam, splitting from the tip
  float reach = mix(0.15, 0.85, crack);
  float along = smoothstep(-1.0 + reach, -1.0, q.y);
  float gap = (0.02 + 0.16 * crack * along) * h.x;
  float seam = smoothstep(gap + 1.0, gap, abs(c.x + sin(q.y * 4.0 + seed) * 0.6)) * step(q.y, -1.0 + reach + 0.1);
  vec3 inside = mix(vec3(0.15, 0.3, 0.12), vec3(0.45, 0.85, 0.35), along);
  col = mix(col, crack > 0.01 ? inside : col * 0.5, seam * along);
  // the hilum and a thin darker rim
  float hilum = smoothstep(0.22, 0.12, length((q - vec2(0.0, 0.82)) * vec2(1.0, 2.2)));
  col = mix(col, v_col.rgb * 1.25 + 0.1, hilum * 0.6);
  col *= mix(1.0, 0.55, smoothstep(-2.0, 0.0, d));
  float glint = smoothstep(0.3, 0.0, length(q - vec2(-0.35, -0.2))) * 0.35;
  return vec4(col + glint, cover * v_col.a);
}

// a cut gem: a flat table, a crown of facets over the girdle, a pavilion
// drawn to a point. Each facet catches light in turn (spectral fire), the
// edges are bright lines.
vec4 gem(vec2 px, float lit, float seed) {
  float t = pc.time;
  vec2 c = px - v_size * 0.5;
  float R = (v_size.x - 2.0 * PAD) * 0.5;
  vec2 q = c / R;
  vec2 a = vec2(abs(q.x), q.y);
  vec2 n1 = normalize(vec2(0.5, -0.55));
  vec2 n2 = normalize(vec2(1.2, 1.0));
  float dTop = -q.y - 0.62;
  float dCrown = dot(a - vec2(1.0, -0.15), n1);
  float dPav = dot(a - vec2(1.0, -0.15), n2);
  float d = max(max(dTop, dCrown), dPav) * R;
  float cover = smoothstep(0.8, -0.8, d);
  bool crown = q.y < -0.15;
  // facets: sectors about the culet below the girdle, table and bevels above
  float sector = crown ? floor((q.x + 1.0) * 2.5) : floor(atan(q.x, 1.0 - q.y) * 5.0 + 5.0);
  float f = hash(vec2(sector, crown ? 7.0 : 3.0) + seed * 17.0);
  float fire = pow(0.5 + 0.5 * sin(t * 1.7 + f * TAU), 4.0);
  vec3 spec = 0.6 + 0.4 * cos(TAU * (f + t * 0.05 + vec3(0.0, 0.33, 0.67)));
  float shade = crown ? 0.85 + 0.15 * f : 0.55 + 0.35 * f;
  vec3 col = v_col.rgb * shade + spec * fire * 0.45 * (0.5 + lit);
  // edges: girdle, table and facet seams
  float edge = smoothstep(1.4, 0.0, abs(q.y + 0.15) * R) + smoothstep(1.2, 0.0, abs(dTop) * R) + smoothstep(1.0, 0.0, -d);
  col += GEM_EDGE * min(edge, 1.0) * 0.4;
  float star = smoothstep(0.25, 0.0, length(q - vec2(-0.3, -0.35))) * (0.5 + 0.5 * sin(t * 2.3 + seed * 4.0));
  return vec4(col + star * 0.6, cover * v_col.a);
}

// a living night over the whole quad: soil-dark, slow clouds of sap veins
// drifting through it, spores rising in sparse cells and glinting, a faint
// warm breath about the middle, darker toward the edges.
vec4 night(vec2 px, float seed) {
  float t = pc.time;
  vec2 inner = v_size - 2.0 * PAD;
  vec2 c = (px - v_size * 0.5) / max(inner.x, inner.y);
  float cloud = vnoise(px * 0.0035 + vec2(t * 0.02 + seed * 5.0, -t * 0.013));
  vec3 col = v_col.rgb * (0.65 + 0.7 * cloud);
  float veins = smoothstep(0.975, 1.0, 1.0 - abs(vnoise(px * 0.006 + vec2(seed * 3.0 - t * 0.025, t * 0.01)) * 2.0 - 1.0));
  col += MEMBRANE_RIM * 0.08 * veins * cloud;
  col += UI_SAP * 0.035 * exp(-dot(c, c) * 9.0) * (0.85 + 0.15 * sin(t * 0.9));
  // spores: at most one a cell, rising, swaying, twinkling
  const float CELL = 46.0;
  vec2 q = px + vec2(0.0, t * 14.0);
  vec2 cell = floor(q / CELL);
  float h = hash(cell + seed * 31.0);
  if (h > 0.82) {
    vec2 at = (cell + vec2(hash(cell + 3.0), hash(cell + 9.0))) * CELL;
    at.x += sin(t * 0.7 + h * TAU) * 6.0;
    float r = length(q - at);
    float tw = 0.5 + 0.5 * sin(t * (1.5 + h * 2.0) + h * 40.0);
    col += BUD_GLOW * (smoothstep(2.2, 0.0, r) * 0.55 + exp(-r * 0.35) * 0.08) * tw;
  }
  col *= 1.0 - 0.75 * smoothstep(0.15, 0.75, length(c * vec2(1.0, 1.3)));
  return vec4(col, v_col.a);
}

// the stamens of an opened flower round `c`: `n` filaments out to radius
// `r`, each tipped with an anther; returns colour (rgb) and cover (a)
vec4 stamens(vec2 c, float r, float n, float seed) {
  float cover = 0.0;
  vec3 col = STAMEN;
  for (int k = 0; k < 8; k++) {
    if (float(k) >= n) break;
    float ang = float(k) * TAU / n + seed * 5.0;
    vec2 end = vec2(cos(ang), sin(ang)) * r;
    float df = sdStem(c, vec2(0.0), end, max(r * 0.07, 0.5), max(r * 0.05, 0.4));
    float da = length(c - end) - max(r * 0.2, 0.9);
    cover = max(cover, smoothstep(0.7, -0.7, df));
    float ac = smoothstep(0.7, -0.7, da);
    col = mix(col, ANTHER, ac);
    cover = max(cover, ac);
  }
  return vec4(col, cover);
}

// one thing drifting down through the painting, if cell `cell` (of a layer
// `C` px across, in its falling space `q`) holds one: a petal, a small
// flower with its stamens, a seed on its fluff, a leaf, or a mote of pollen;
// each sways and tumbles as it falls
vec4 drifter(vec2 q, vec2 cell, float C, float seed) {
  if (hash(cell + seed * 31.0) > DRIFT_SHARE) return vec4(0.0);
  float t = pc.time;
  float h1 = hash(cell + 3.7), h2 = hash(cell + 9.1), h3 = hash(cell + 17.3);
  float kind = floor(hash(cell + 23.9) * 4.999);
  vec2 at = (cell + 0.5 + (vec2(h1, h2) - 0.5) * 0.3) * C;
  at.x += sin(t * (0.5 + h2 * 0.5) + h1 * TAU) * C * 0.12;
  float R = C * mix(0.11, 0.19, h3);
  vec2 p = rot(q - at, t * (h1 - 0.5) * 1.6 + h2 * TAU);
  vec3 col = vec3(0.0);
  float a = 0.0;
  if (kind < 1.0) {
    // a petal
    float d = sdGlyphLeaf(p, vec2(-R, 0.0), vec2(1.0, 0.0), 2.0 * R, R * 0.55);
    a = smoothstep(0.8, -0.8, d);
    col = mix(DRIFT_PETAL, DRIFT_LILAC, h1) * (0.75 + 0.3 * smoothstep(-R, R, p.y));
  } else if (kind < 2.0) {
    // a small whole flower, stamens and all
    float ang = atan(p.y, p.x);
    float d = length(p) - R * (0.5 + 0.5 * pow(abs(cos(2.5 * ang)), 0.6));
    a = smoothstep(0.8, -0.8, d);
    col = mix(vec3(0.96, 0.92, 0.94), DRIFT_PETAL, h2) * (0.8 + 0.2 * length(p) / R);
    vec4 st = stamens(p, R * 0.32, 6.0, h1);
    col = mix(col, st.rgb, st.a);
  } else if (kind < 3.0) {
    // a seed on its fluff, as a dandelion's: the seed hanging below on a
    // fine beak, a soft round puff of many fine rays above it
    vec2 hub = vec2(0.0, -R * 0.15);
    float ds = length((p - vec2(0.0, R * 0.95)) * vec2(2.2, 1.0)) - R * 0.2;
    float beak = sdStem(p, hub, vec2(0.0, R * 0.8), max(R * 0.03, 0.4), max(R * 0.03, 0.4));
    float rho = length(p - hub);
    float ang = atan(p.x, -(p.y - hub.y));
    float off = abs(fract(ang * 22.0 / TAU + 0.5) - 0.5) * TAU / 22.0 * rho;
    float within = step(abs(ang), 2.2) * smoothstep(R * 0.85, R * 0.6, rho);
    float ray = smoothstep(0.7, 0.1, off) * within;
    float haze = within * 0.18 * smoothstep(0.0, R * 0.4, rho);
    float sc = smoothstep(0.8, -0.8, ds);
    float bc = smoothstep(0.6, -0.6, beak);
    col = mix(DRIFT_FLUFF, DRIFT_SEED, max(sc, bc * 0.6));
    a = max(max(sc, bc * 0.7), max(ray * 0.6, haze));
  } else if (kind < 4.0) {
    // a leaf, its midrib down the middle
    float d = sdGlyphLeaf(p, vec2(-R * 1.1, 0.0), vec2(1.0, 0.0), 2.2 * R, R * 0.5);
    a = smoothstep(0.8, -0.8, d);
    col = leafShade(p, vec2(-R * 1.1, 0.0), vec2(1.0, 0.0), R * 0.5, mix(DRIFT_LEAF, DRIFT_LEAF * vec3(1.3, 1.0, 0.6), h1));
    col *= 1.0 - 0.3 * smoothstep(1.0, 0.0, abs(p.y));
  } else {
    // a mote of pollen, glowing and twinkling
    float r = length(p);
    float tw = 0.6 + 0.4 * sin(t * (1.5 + h2 * 2.0) + h1 * 40.0);
    a = (smoothstep(R * 0.22, R * 0.1, r) + exp(-r / (R * 0.35)) * 0.35) * tw;
    col = ANTHER;
  }
  return vec4(col, clamp(a, 0.0, 1.0));
}

// the research tree's backdrop over the whole screen, a flat painting of the
// main menu's stage: the dark laid in broad strokes, lighter toward the soil,
// the moon low behind; below the soil line (`soil`, px down the screen) the
// earth in strata and pebbles, a tufted moss lip along it, a warm light pooled
// over it;
// petals, small flowers, seeds on fluff, leaves and pollen drifting down,
// far and near, fading in from the top and away at the ground.
vec4 dusk(vec2 px, float soil, float seed) {
  float t = pc.time;
  vec2 S = v_size - 2.0 * PAD;
  vec2 p = px - PAD;
  float depth = p.y - soil;
  float stroke = vnoise(p * vec2(0.0035, 0.011) + seed * 5.0);
  vec3 col = mix(DUSK_HIGH, DUSK_LOW, smoothstep(0.0, max(soil, 1.0), p.y)) * (0.85 + 0.3 * stroke);
  // the warm light pooled over the soil where the tree stands, as over the
  // sleeping wolf, broken by the strokes
  vec2 pool = (p - vec2(S.x * 0.5, soil - S.y * 0.28)) / (S.y * vec2(0.75, 0.5));
  col += DUSK_WARM * exp(-dot(pool, pool)) * (0.8 + 0.4 * stroke);
  // the moon, mottled, and its halo
  vec2 mp = p - DUSK_MOON * S;
  float md = length(mp);
  float mr = S.y * 0.03;
  float mottle = 0.8 + 0.2 * vnoise(mp / mr * 2.5 + 7.0);
  col += DUSK_MOON_LIGHT * (smoothstep(mr + 1.5, mr - 1.5, md) * 0.3 * mottle + exp(-md / (S.y * 0.1)) * 0.025);
  if (depth > 0.0) {
    float strata = vnoise(vec2(p.x * 0.004, depth * 0.03) + seed * 3.0);
    vec3 earth = mix(DUSK_EARTH, DUSK_DEEP, smoothstep(0.0, S.y * 0.7, depth)) * (0.75 + 0.45 * strata);
    vec2 pcell = floor(p / 26.0);
    if (hash(pcell + 51.0) > 0.8) {
      vec2 pat = (pcell + 0.5 + (vec2(hash(pcell + 2.0), hash(pcell + 5.0)) - 0.5) * 0.5) * 26.0;
      float dp = length((p - pat) * vec2(1.0, 1.4)) - (3.0 + 4.0 * hash(pcell + 8.0));
      earth = mix(earth, earth * 1.6 + 0.004, smoothstep(0.8, -0.8, dp));
    }
    col = earth;
  }
  // the moss lip, tufted along the soil line
  float tuft = 3.0 + 7.0 * vnoise(vec2(p.x * 0.07, seed)) + 3.0 * pow(abs(sin(p.x * 0.31 + seed)), 6.0);
  float moss = smoothstep(-tuft - 1.0, -tuft + 1.0, depth) * smoothstep(6.0, 2.0, depth);
  col = mix(col, DUSK_MOSS * (0.7 + 0.4 * vnoise(p * 0.2)), moss);
  // what drifts down: the far layer dimmer, then the near
  float fade = smoothstep(0.0, S.y * 0.12, p.y) * smoothstep(8.0, -30.0, depth);
  for (int l = 0; l < 2; l++) {
    float C = l == 0 ? DRIFT_FAR : DRIFT_NEAR;
    vec2 q = p - vec2(0.0, t * (l == 0 ? DRIFT_FAR_FALL : DRIFT_NEAR_FALL));
    vec4 d = drifter(q, floor(q / C), C, seed + float(l) * 7.0);
    col = mix(col, d.rgb * (l == 0 ? 0.5 : 0.95), d.a * fade);
  }
  // a whisper of grain, so the dark's slow gradients never band
  col += (hash(p + floor(t * 30.0) * 17.0) - 0.5) * DUSK_GRAIN;
  return vec4(max(col, 0.0), v_col.a);
}

// a symbiotic study, a flower of the sharers: two leaves down either side
// and five petals tinted its colour that, closed (open 0), cup upward into
// a bud held in green sepals, and as `open` runs to 1 part and spread round
// a heart of stamens. It sways a little on the breeze.
vec4 blossom(vec2 px, float open, float seed) {
  float t = pc.time;
  float R = (v_size.x - 2.0 * PAD) * 0.5;
  vec2 c = rot(px - v_size * 0.5, sin(t * 1.1 + seed * 6.0) * 0.06);
  float o = smoothstep(0.0, 1.0, open);
  vec3 col = vec3(0.0);
  float a = 0.0;
  for (int k = 0; k < 2; k++) {
    vec2 u = normalize(vec2(k == 0 ? -0.9 : 0.9, 0.5));
    vec2 base = vec2(0.0, R * 0.2);
    float wid = R * 0.26;
    float lc = smoothstep(0.8, -0.8, sdGlyphLeaf(c, base, u, R * 1.0, wid));
    col = mix(col, leafShade(c, base, u, wid, BLOSSOM_LEAF), lc);
    a = max(a, lc);
  }
  // the petals, back ones first, each rimmed darker where it overlaps
  float spread = mix(0.22, 1.2566, o);
  vec2 heart = vec2(0.0, mix(R * 0.1, 0.0, o));
  for (int k = 0; k < 5; k++) {
    float j = float(k) - 2.0;
    float ang = -PI * 0.5 + j * spread + (hash(vec2(float(k), seed * 9.0)) - 0.5) * 0.15 * o;
    vec2 u = vec2(cos(ang), sin(ang));
    float len = R * mix(0.62, 0.92, o);
    float wid = R * mix(0.2, 0.34, o);
    float d = sdGlyphLeaf(c, heart, u, len, wid);
    float pc0 = smoothstep(0.8, -0.8, d);
    float along = clamp(dot(c - heart, u) / len, 0.0, 1.0);
    vec3 pcol = mix(BLOSSOM_LEAF, v_col.rgb, 0.3 + 0.7 * o) * (0.72 + 0.4 * along);
    pcol *= 1.0 - 0.3 * smoothstep(-2.0, 0.0, d);
    col = mix(col, pcol, pc0);
    a = max(a, pc0);
  }
  // sepals holding the bud, falling back as it opens
  for (int k = 0; k < 2; k++) {
    vec2 u = normalize(vec2(k == 0 ? -0.45 : 0.45, -1.0));
    float wid = R * 0.14;
    float sc = smoothstep(0.8, -0.8, sdGlyphLeaf(c, vec2(0.0, R * 0.25), u, R * 0.5 * (1.0 - 0.7 * o), wid));
    col = mix(col, leafShade(c, vec2(0.0, R * 0.25), u, wid, BLOSSOM_LEAF * 0.9), sc);
    a = max(a, sc);
  }
  // its heart of stamens, hidden while it is a bud
  float show = smoothstep(0.35, 0.6, o);
  float hd = length(c) - R * 0.15;
  col = mix(col, STAMEN * 0.7, smoothstep(0.8, -0.8, hd) * show);
  vec4 st = stamens(c, R * 0.34, 7.0, seed);
  col = mix(col, st.rgb, st.a * show);
  return vec4(col, a * v_col.a);
}

// a parasitic study, a gall of the takers: a swollen bladder tinted its
// colour, veined and breathing, ringed with hooked thorns (sharp, laid
// flatter while it sleeps); across it a lipped mouth that parts as `open`
// runs to 1, a hungry glow and a row of teeth inside.
vec4 gall(vec2 px, float open, float seed) {
  float t = pc.time;
  float R = (v_size.x - 2.0 * PAD) * 0.5;
  vec2 c = px - v_size * 0.5;
  float ang = atan(c.y, c.x);
  float Rb = R * 0.62 * (1.0 + 0.05 * sin(t * 1.6 + seed * 6.0));
  float d = length(c * vec2(1.0, 1.1)) - Rb - (ringNoise(ang, 1.6, seed, t * 0.5) - 0.5) * R * 0.12;
  vec3 col = vec3(0.0);
  float a = 0.0;
  for (int k = 0; k < 7; k++) {
    float ta = float(k) * TAU / 7.0 + seed * 3.0;
    vec2 u = vec2(cos(ta), sin(ta));
    vec2 base = u * Rb * 0.85;
    float len = R * mix(0.22, 0.42, open) * (0.8 + 0.4 * hash(vec2(float(k), seed * 9.0)));
    vec2 mid = base + u * len * 0.55;
    vec2 tip = mid + rot(u, mix(0.9, 0.5, open)) * len * 0.5;
    float dt = min(sdStem(c, base, mid, R * 0.08, R * 0.045), sdStem(c, mid, tip, R * 0.045, 0.0));
    float tc = smoothstep(0.8, -0.8, dt);
    col = mix(col, GALL_THORN * (0.7 + 0.3 * clamp(dot(c - base, u) / len, 0.0, 1.0)), tc);
    a = max(a, tc);
  }
  vec2 q = c / Rb;
  vec3 n = normalize(vec3(q, sqrt(max(0.0, 1.0 - min(dot(q, q), 1.0)))));
  float shade = 0.45 + 0.55 * max(dot(n, normalize(vec3(-0.5, -0.6, 0.65))), 0.0);
  float veins = smoothstep(0.92, 1.0, 1.0 - abs(vnoise(q * 3.0 + seed * 7.0) * 2.0 - 1.0));
  vec3 body = v_col.rgb * shade * (0.85 + 0.35 * veins);
  float fill = smoothstep(1.0, -1.0, d);
  // the mouth: a slit across, parting
  float w = Rb * 0.72;
  float across = clamp(c.x / w, -1.0, 1.0);
  float gap = R * 0.2 * open * sqrt(max(0.0, 1.0 - across * across)) * step(abs(c.x), w);
  float y = c.y - R * 0.08;
  float maw = smoothstep(0.8, -0.8, abs(y) - gap) * step(0.01, gap);
  float teeth = step(abs(y), gap) * step(gap - abs(y), R * 0.07 * (1.0 - abs(fract(c.x / (R * 0.13)) * 2.0 - 1.0)));
  vec3 inside = GALL_MAW * (0.55 + 0.45 * sin(t * 3.0 + seed * 4.0)) * (1.0 - abs(y) / max(gap, 1e-3) * 0.5);
  body = mix(body, inside, maw);
  body = mix(body, GALL_THORN, teeth * maw);
  float seam = smoothstep(1.2, 0.0, abs(abs(y) - gap)) * step(abs(c.x), w) * (1.0 - 0.6 * abs(across));
  body *= 1.0 - 0.6 * seam;
  body = mix(body, body * 0.55, smoothstep(-2.5, 0.0, d));
  col = mix(col, body, fill);
  a = max(a, fill);
  return vec4(col, a * v_col.a);
}

// a radiant study, light gathered and never grown: crystal fragments drift
// round a core of light and, as `open` runs to 1, settle one by one into a
// cluster about it, points outward; gathered, the core burns and each
// facet catches fire in turn.
vec4 shard(vec2 px, float open, float seed) {
  float t = pc.time;
  float R = (v_size.x - 2.0 * PAD) * 0.5;
  vec2 c = px - v_size * 0.5;
  vec3 col = vec3(0.0);
  float a = 0.0;
  for (int k = 0; k < 7; k++) {
    float h = hash(vec2(float(k), seed * 13.0));
    float from = float(k) / 7.0 * 0.75;
    float settle = smoothstep(from, from + 0.25, open);
    float home = float(k) * TAU / 7.0 - PI * 0.5;
    float orbit = t * (0.25 + 0.35 * h) + h * TAU;
    vec2 at = mix(vec2(cos(orbit), sin(orbit)) * R * (0.7 + 0.15 * h), vec2(cos(home), sin(home)) * R * 0.28, settle);
    float dir = mix(orbit + h * 3.0 + t * 0.7, home, settle);
    vec2 u = vec2(cos(dir), sin(dir));
    float len = R * mix(0.2, 0.5 + 0.15 * h, settle);
    float wid = R * mix(0.08, 0.13, settle);
    vec2 r = c - at;
    float x = dot(r, u);
    float y = dot(r, vec2(-u.y, u.x));
    float dk = (abs(y) / wid + (x > 0.0 ? x / len : -x / (len * 0.3)) - 1.0) * wid;
    float cover = smoothstep(0.8, -0.8, dk);
    vec3 spec = 0.6 + 0.4 * cos(TAU * (h + t * 0.05 + vec3(0.0, 0.33, 0.67)));
    float fire = pow(0.5 + 0.5 * sin(t * 1.7 + h * TAU), 4.0) * settle;
    vec3 scol = v_col.rgb * (y > 0.0 ? 1.0 : 0.62) + spec * fire * 0.45;
    scol += GEM_EDGE * smoothstep(1.0, 0.0, abs(y)) * 0.3 + GEM_EDGE * smoothstep(1.0, 0.0, -dk) * 0.25;
    col = mix(col, scol, cover);
    a = max(a, cover * mix(0.55, 1.0, settle));
  }
  float core = exp(-length(c) / (R * mix(0.1, 0.22, open))) * mix(0.35, 1.0, open);
  col += (v_col.rgb * 1.1 + 0.35) * core;
  a = max(a, min(core, 1.0));
  return vec4(col, clamp(a, 0.0, 1.0) * v_col.a);
}

// a convergent study, where the lineages meet: a green strand and a violet
// one braid round each other in a ring, over and under, grown round from
// the top as `open` runs to 1; once the ring closes a bloom of its colour
// opens in its heart, stamens and all. The ring turns slowly.
vec4 knot(vec2 px, float open, float seed) {
  float t = pc.time;
  float R = (v_size.x - 2.0 * PAD) * 0.5;
  vec2 c = rot(px - v_size * 0.5, t * 0.15 + seed * 6.0);
  float rho = length(c);
  float th = atan(c.y, c.x);
  float along = fract((th + PI * 0.5) / TAU);
  float reach = mix(0.12, 1.0, open);
  float grown = smoothstep(reach + 0.001, reach - 0.03, along);
  float ring = R * 0.6;
  float amp = R * 0.13;
  // the strands thin toward their growing tips, whole once the ring closes
  float tipK = open >= 0.999 ? 1.0 : mix(0.4, 1.0, smoothstep(reach, reach - 0.12, along));
  float w = R * 0.085 * tipK;
  float sA = ring + amp * sin(th * 3.0);
  float sB = ring - amp * sin(th * 3.0);
  float cA = smoothstep(0.8, -0.8, abs(rho - sA) - w) * grown;
  float cB = smoothstep(0.8, -0.8, abs(rho - sB) - w) * grown;
  float xa = clamp((rho - sA) / max(w, 0.5), -1.0, 1.0);
  float xb = clamp((rho - sB) / max(w, 0.5), -1.0, 1.0);
  vec3 colA = KNOT_SYM * (0.6 + 0.4 * sqrt(max(0.0, 1.0 - xa * xa)));
  vec3 colB = KNOT_PAR * (0.6 + 0.4 * sqrt(max(0.0, 1.0 - xb * xb)));
  vec3 col = vec3(0.0);
  if (cos(th * 3.0) > 0.0) {
    col = mix(mix(col, colB, cB), colA, cA);
  } else {
    col = mix(mix(col, colA, cA), colB, cB);
  }
  float a = max(cA, cB);
  float bloom = smoothstep(0.7, 1.0, open);
  float pd = rho - R * 0.32 * bloom * (0.55 + 0.45 * abs(cos(2.0 * th)));
  float pcov = smoothstep(0.8, -0.8, pd) * step(0.01, bloom);
  col = mix(col, v_col.rgb * (0.75 + 0.35 * rho / max(R * 0.32, 1.0)), pcov);
  a = max(a, pcov);
  vec4 st = stamens(c, R * 0.15 * bloom, 5.0, seed);
  col = mix(col, st.rgb, st.a * step(0.01, bloom));
  a = max(a, st.a * step(0.01, bloom));
  return vec4(col, a * v_col.a);
}

// is glyph cell q set? (5x7 bitmap and a row below the line for tails,
// row-major, bit 0 top-left)
bool lit(ivec2 q) {
  if (q.x < 0 || q.y < 0 || q.x >= 5 || q.y >= 8) return false;
  int b = q.y * 5 + q.x;
  uint word = b < 32 ? v_bits.x : v_bits.y;
  return ((word >> uint(b & 31)) & 1u) != 0u;
}

// do lit cells q and q + o share a stem? Orthogonal neighbours always; a
// diagonal only where no orthogonal pair already turns that corner (so a
// staircase becomes one smooth slanting stem, a filled block no web)
bool joined(ivec2 q, ivec2 o) {
  if (!lit(q) || !lit(q + o)) return false;
  if (o.x == 0 || o.y == 0) return true;
  return !lit(q + ivec2(o.x, 0)) && !lit(q + ivec2(0, o.y));
}

// a lit cell's stems: how many, and the sum of their directions
int stems(ivec2 q, out vec2 dir) {
  dir = vec2(0.0);
  int n = 0;
  for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
    ivec2 o = ivec2(dx, dy);
    if (o == ivec2(0) || !joined(q, o)) continue;
    dir += normalize(vec2(o));
    n++;
  }
  return n;
}

// a cell's node radius (cells): a lone cell is a round seed, a tip tapers,
// a fork swells like a plant's node
float nodeRadius(int n, float thick) {
  return thick * (n == 0 ? GLYPH_SEED : n == 1 ? GLYPH_TIP : n == 2 ? 1.0 : GLYPH_NODE);
}

// glyphs grow as vines: each lit cell is a node, joined to its lit
// neighbours by tapering stems; a stem's free tips point and, once text is
// big enough to show them, put out a leaf. The whole glyph sways from its
// foot and sap shimmers up it. Small text keeps its stems stout to stay legible.
vec4 glyph() {
  float t = pc.time;
  float px = 1.0 / max(fwidth(v_uv.x), 1e-3);  // screen pixels per cell
  float big = smoothstep(GLYPH_LEAF_FROM, GLYPH_LEAF_FULL, px);
  float thick = mix(GLYPH_THICK, GLYPH_SLENDER, big);
  // sway grows toward the glyph's top, a wave running along the line
  vec2 uv = v_uv - GLYPH_PAD;
  float seed = v_param.y * 13.0;
  uv += (vec2(vnoise(uv * 0.4 + seed), vnoise(uv * 0.4 - seed + 5.0)) - 0.5) * GLYPH_BOW * big;
  uv.x += sin(t * 1.3 + v_param.y * 9.0) * GLYPH_SWAY * max(1.0 - uv.y / 7.0, 0.0);
  ivec2 p = ivec2(floor(uv));
  int reach = big > 0.0 ? 2 : 1;
  float aa = 0.75 / px;
  float ds = 1e3, dl = 1e3;
  for (int dy = -reach; dy <= reach; dy++) for (int dx = -reach; dx <= reach; dx++) {
    ivec2 q = p + ivec2(dx, dy);
    if (!lit(q)) continue;
    vec2 c = vec2(q) + 0.5;
    bool near = abs(dx) <= 1 && abs(dy) <= 1;
    vec2 dir;
    int n = stems(q, dir);
    float ra = nodeRadius(n, thick);
    // a leaf: off a tip that does not point down, angled off its stem, or
    // now and then off a straight stem node, slanting up
    if (big > 0.0 && (n == 1 || n == 2)) {
      float h = hash(vec2(q) + seed * 37.0);
      vec2 tip = n == 1 ? -normalize(dir) : vec2(0.0);
      bool grows = n == 1 ? tip.y < 0.5 : h < GLYPH_LEAF_MID && length(dir) < 0.1;
      if (grows) {
        float side = fract(h * 7.0) > 0.5 ? 1.0 : -1.0;
        float a = side * ((n == 1 ? 0.75 : 1.2) + 0.25 * sin(t * 2.1 + h * TAU));
        vec2 from = n == 1 ? tip : vec2(0.0, -1.0);
        vec2 u = vec2(from.x * cos(a) - from.y * sin(a), from.x * sin(a) + from.y * cos(a));
        float len = GLYPH_LEAF_LEN * big * (n == 1 ? 1.0 : 0.8);
        dl = min(dl, sdGlyphLeaf(uv, c + tip * ra * 0.5, u, len, GLYPH_LEAF_WID * big));
      }
    }
    if (!near) continue;
    ds = min(ds, length(uv - c) - ra);
    // each stem once: toward the right and downward neighbours
    for (int k = 0; k < 4; k++) {
      ivec2 o = k == 0 ? ivec2(1, 0) : k == 1 ? ivec2(0, 1) : k == 2 ? ivec2(1, 1) : ivec2(-1, 1);
      if (!joined(q, o)) continue;
      vec2 od;
      float rb = nodeRadius(stems(q + o, od), thick);
      ds = min(ds, sdStem(uv, c, c + vec2(o), ra, rb));
    }
  }
  float d = min(ds, dl);
  float cover = smoothstep(aa, -aa, d);
  if (cover < GLYPH_CLEAR) return vec4(0.0);
  // a stem's core catches the light; sap pulses climb it
  float core = smoothstep(0.0, -thick * 0.8, ds);
  float sap = 0.88 + 0.12 * sin(t * 2.0 + v_param.y * 8.0 + uv.y * 0.9);
  vec3 col = v_col.rgb * sap * mix(1.0, 0.82 + 0.3 * core, big);
  // leaves take on green, keeping the text's own hue
  col = mix(col, mix(col, GLYPH_LEAF_GREEN, 0.5), smoothstep(-aa, aa, ds - dl));
  return vec4(col, v_col.a * cover);
}

void main() {
  // nothing shows outside the rectangle it is cut to
  if (any(lessThan(v_px, v_clip.xy)) || any(greaterThanEqual(v_px, v_clip.zw))) discard;
  if (v_bits.x == SHAPE_MARK) {
    vec4 c;
    switch (v_bits.y) {
      case SHAPE_TRELLIS: c = trellis(v_uv, v_param.x, v_param.y); break;
      case SHAPE_HUSK: c = husk(v_uv, v_param.x, v_param.y); break;
      case SHAPE_POD: c = pod(v_uv, v_param.x, v_param.y); break;
      case SHAPE_TENDRIL: c = tendril(v_uv, v_param.x, v_param.y); break;
      case SHAPE_GLOW: c = glow(v_uv); break;
      case SHAPE_LIMB: c = limb(v_uv, v_param.x, v_param.y); break;
      case SHAPE_LEAF: c = leaf(v_uv, v_param.x, v_param.y); break;
      case SHAPE_GRAIN: c = seedCoat(v_uv, v_param.x, v_param.y); break;
      case SHAPE_GEM: c = gem(v_uv, v_param.x, v_param.y); break;
      case SHAPE_DUSK: c = dusk(v_uv, v_param.x, v_param.y); break;
      case SHAPE_BLOSSOM: c = blossom(v_uv, v_param.x, v_param.y); break;
      case SHAPE_GALL: c = gall(v_uv, v_param.x, v_param.y); break;
      case SHAPE_SHARD: c = shard(v_uv, v_param.x, v_param.y); break;
      case SHAPE_KNOT: c = knot(v_uv, v_param.x, v_param.y); break;
      // one pixel of a picture: its colour, the whole quad
      case SHAPE_SWATCH: c = v_col; break;
      default: c = night(v_uv, v_param.y); break; // SHAPE_NIGHT
    }
    if (c.a < SHAPE_CLEAR) discard;
    o = c;
    return;
  }
  vec4 c = glyph();
  if (c.a < GLYPH_CLEAR) discard;
  o = c;
}
