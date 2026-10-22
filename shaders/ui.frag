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

vec3 sapColor(vec3 base, float k) { return mix(base, vec3(1.0, 0.78, 0.35), k); }

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
  vec3 rimc = sapColor(vec3(0.18, 0.42, 0.20), pulse * 0.9);
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
  vec3 rimc = sapColor(vec3(0.25, 0.5, 0.25), lit);
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
  return vec4(col + vec3(1.0, 0.85, 0.5) * tip, clamp(a * v_col.a, 0.0, 1.0));
}

vec4 glow(vec2 px) {
  vec2 c = px - v_size * 0.5;
  float R = (v_size.x - 2.0 * PAD) * 0.5;
  float a = exp(-dot(c, c) / (R * R) * 2.5) * (0.8 + 0.2 * sin(pc.time * 2.5));
  // reach exactly zero before the quad edge so no straight border shows
  a *= smoothstep(R + PAD - 4.0, R, length(c));
  return vec4(v_col.rgb, a * v_col.a);
}

// is glyph cell q set? (5x7 bitmap, row-major, bit 0 top-left)
bool lit(ivec2 q) {
  if (q.x < 0 || q.y < 0 || q.x >= 5 || q.y >= 7) return false;
  int b = q.y * 5 + q.x;
  uint word = b < 32 ? v_bits.x : v_bits.y;
  return ((word >> uint(b & 31)) & 1u) != 0u;
}

void main() {
  if (v_bits.x == 0xffffffffu) {
    vec4 c;
    switch (v_bits.y) {
      case 0u: c = membrane(v_uv, v_param.y); break;
      case 1u: c = pod(v_uv, v_param.x, v_param.y); break;
      case 2u: c = tendril(v_uv, v_param.x, v_param.y); break;
      default: c = glow(v_uv); break;
    }
    if (c.a < 0.003) discard;
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
    vec2 rel = abs(v_uv - (vec2(q) + 0.5)) - vec2(0.5 - 0.3);
    d = min(d, length(max(rel, 0.0)) + min(max(rel.x, rel.y), 0.0) - 0.3);
  }
  float cover = smoothstep(aa, -aa, d);
  if (cover < 0.01) discard;
  float shimmer = 0.88 + 0.12 * sin(pc.time * 2.0 + v_param.y * 8.0 + v_uv.y * 0.6);
  o = vec4(v_col.rgb * shimmer, v_col.a * cover);
}
