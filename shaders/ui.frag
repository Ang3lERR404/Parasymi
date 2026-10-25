#version 450
// organic UI: every shape is an animated signed-distance field. No boxes.
layout(push_constant) uniform Push { vec2 screen; float time; float pad; } pc;
layout(location = 0) in vec2 v_uv;
layout(location = 1) in vec4 v_col;
layout(location = 2) flat in uvec2 v_bits;
layout(location = 3) flat in vec2 v_size;
layout(location = 4) flat in vec2 v_param;
layout(location = 0) out vec4 o;

const float PAD = 28.0;
const float PI = 3.14159;
const float TAU = 6.2832;
// sap's glow, what every shape brightens toward where sap shows
const vec3 UI_SAP = vec3(1.0, 0.78, 0.35);
// vine green: a membrane's rim, a pod's rim
const vec3 MEMBRANE_RIM = vec3(0.18, 0.42, 0.20);
const vec3 POD_RIM = vec3(0.25, 0.5, 0.25);
// warm white: a tendril's bud, a gem's edges
const vec3 BUD_GLOW = vec3(1.0, 0.85, 0.5);
const vec3 GEM_EDGE = vec3(1.0, 0.97, 0.9);
// a glyph cell's rounding (cells are 1 across)
const float GLYPH_ROUND = 0.3;
// coverage below which a fragment is dropped: shapes, glyphs
const float SHAPE_CLEAR = 0.003;
const float GLYPH_CLEAR = 0.01;
// a quad is a shape when its bits' x is SHAPE_MARK (else a glyph's bitmap),
// its bits' y which (ui/draw.zig `Shape`, its u32 value; must match)
const uint SHAPE_MARK = 0xffffffffu;
const uint SHAPE_MEMBRANE = 0u;
const uint SHAPE_POD = 1u;
const uint SHAPE_TENDRIL = 2u;
const uint SHAPE_GLOW = 3u;
const uint SHAPE_LIMB = 4u;
const uint SHAPE_LEAF = 5u;
const uint SHAPE_GRAIN = 6u;
const uint SHAPE_GEM = 7u;
const uint SHAPE_NIGHT = 8u;

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

vec4 membrane(vec2 px, float seed) {
  float t = pc.time;
  vec2 inner = v_size - 2.0 * PAD;
  vec2 c = px - v_size * 0.5;
  // perimeter coordinate drives the travelling wobble and sap pulses
  float ang = atan(c.y, c.x);
  float wob = (ringNoise(ang, 1.6, seed, t * 0.6) - 0.5) * 7.0
            + sin(ang * 5.0 + t * 1.3 + seed * 6.0) * 1.5;
  float r = min(inner.x, inner.y) * 0.32;
  float d = sdRound(c, inner * 0.5, r) - wob;

  float fill = smoothstep(1.5, -1.5, d);
  // veins inside the membrane
  float veins = smoothstep(0.92, 1.0, 1.0 - abs(vnoise(px * 0.035 + vec2(seed * 7.0, t * 0.05)) * 2.0 - 1.0));
  vec3 body = v_col.rgb * (0.75 + 0.25 * vnoise(px * 0.02 + t * 0.1)) + vec3(0.06, 0.12, 0.05) * veins;
  // vine rim with sap pulses running around it
  float rim = smoothstep(4.0, 0.5, abs(d + 1.5));
  float pulse = pow(0.5 + 0.5 * sin(ang * 4.0 - t * 2.2 + seed * 9.0), 6.0);
  vec3 rimc = sapColor(MEMBRANE_RIM, pulse * 0.9);
  // soft outer aura
  float aura = exp(-max(d, 0.0) * 0.25) * (1.0 - fill) * 0.35 * smoothstep(PAD - 6.0, PAD - 16.0, d);

  vec3 col = mix(body, rimc, rim);
  float a = max(fill * v_col.a, rim) + aura * pulse;
  return vec4(col + rimc * aura, clamp(a, 0.0, 1.0));
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

vec4 tendril(vec2 px, float value, float seed) {
  float t = pc.time;
  vec2 inner = v_size - 2.0 * PAD;
  vec2 p = px - vec2(PAD, v_size.y * 0.5);
  float k = p.x / inner.x;                   // 0..1 along the tendril
  // distance to the wavy centreline, clamped so both ends round off
  float kc = clamp(k, 0.0, 1.0);
  float wave = sin(kc * 18.0 + t * 2.0 + seed * 7.0) * inner.y * 0.18;
  float thick = inner.y * 0.5 * (1.0 - 0.35 * kc);
  float d = length(vec2((k - kc) * inner.x, p.y - wave)) - thick;
  float grown = smoothstep(value + 0.015, value - 0.015, k);
  // grown part glows with sap; the rest is a faint dry husk
  float body = smoothstep(1.0, -1.0, d);
  float pulse = 0.6 + 0.4 * sin(k * 30.0 - t * 4.0);
  vec3 col = mix(v_col.rgb * 0.25, sapColor(v_col.rgb, 0.25 * pulse), grown);
  // a bud at the growing tip
  float tip = smoothstep(inner.y * 0.7, 0.0, length(vec2(p.x - value * inner.x, p.y - sin(value * 18.0 + t * 2.0 + seed * 7.0) * inner.y * 0.18)));
  float a = body * mix(0.35, 1.0, grown) + tip * step(0.001, value);
  return vec4(col + BUD_GLOW * tip, clamp(a * v_col.a, 0.0, 1.0));
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

// is glyph cell q set? (5x7 bitmap, row-major, bit 0 top-left)
bool lit(ivec2 q) {
  if (q.x < 0 || q.y < 0 || q.x >= 5 || q.y >= 7) return false;
  int b = q.y * 5 + q.x;
  uint word = b < 32 ? v_bits.x : v_bits.y;
  return ((word >> uint(b & 31)) & 1u) != 0u;
}

void main() {
  if (v_bits.x == SHAPE_MARK) {
    vec4 c;
    switch (v_bits.y) {
      case SHAPE_MEMBRANE: c = membrane(v_uv, v_param.y); break;
      case SHAPE_POD: c = pod(v_uv, v_param.x, v_param.y); break;
      case SHAPE_TENDRIL: c = tendril(v_uv, v_param.x, v_param.y); break;
      case SHAPE_GLOW: c = glow(v_uv); break;
      case SHAPE_LIMB: c = limb(v_uv, v_param.x, v_param.y); break;
      case SHAPE_LEAF: c = leaf(v_uv, v_param.x, v_param.y); break;
      case SHAPE_GRAIN: c = seedCoat(v_uv, v_param.x, v_param.y); break;
      case SHAPE_GEM: c = gem(v_uv, v_param.x, v_param.y); break;
      default: c = night(v_uv, v_param.y); break; // SHAPE_NIGHT
    }
    if (c.a < SHAPE_CLEAR) discard;
    o = c;
    return;
  }
  // glyphs: each lit cell is a rounded square that merges with its lit
  // neighbours; coverage is antialiased per pixel so text stays clean at any
  // scale, softly shimmering like sap catching light
  ivec2 p = ivec2(floor(v_uv));
  float aa = max(fwidth(v_uv.x), 1e-3) * 0.75;
  float d = 1e3;
  for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) {
    ivec2 q = p + ivec2(dx, dy);
    if (!lit(q)) continue;
    vec2 rel = abs(v_uv - (vec2(q) + 0.5)) - vec2(0.5 - GLYPH_ROUND);
    d = min(d, length(max(rel, 0.0)) + min(max(rel.x, rel.y), 0.0) - GLYPH_ROUND);
  }
  float cover = smoothstep(aa, -aa, d);
  if (cover < GLYPH_CLEAR) discard;
  float shimmer = 0.88 + 0.12 * sin(pc.time * 2.0 + v_param.y * 8.0 + v_uv.y * 0.6);
  o = vec4(v_col.rgb * shimmer, v_col.a * cover);
}
