#version 450
//! terrain shading: tile colour, ley sight and its plexus, shadows, fog.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

layout(location = 0) in vec3 v_pos;
layout(location = 1) in vec3 v_nrm;
layout(location = 2) in vec3 v_col;
layout(location = 3) in vec4 v_info;
layout(location = 0) out vec4 o;

// ley sight: the currents' colour (plain, veiled), and the plexus's pale tint
const vec3 LEY = vec3(0.45, 0.3, 1.0);
const vec3 LEY_VEILED = vec3(1.0, 0.7, 1.0);
const vec3 PLEXUS_PALE = vec3(0.9, 0.85, 1.0);
// the hovered tile's highlight, pulsing at this rate (rad/s)
const vec3 HOVER = vec3(0.25, 0.25, 0.2);
const float HOVER_PULSE = 6.0;
// a paw's contact shadow: its radii (side, forward) on the ground, and its
// darkness there
const vec2 PAW_SHADOW = vec2(0.12, 0.18);
const float PAW_SHADOW_DARK = 0.7;

float hash12(vec2 p) {
  vec3 q = fract(vec3(p.xyx) * 0.1031);
  q += dot(q, q.yzx + 33.33);
  return fract((q.x + q.y) * q.z);
}

float segDist(vec2 p, vec2 a, vec2 b) {
  vec2 ab = b - a;
  float h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
  return length(p - a - ab * h);
}

// faint points drifting over a ley tile, joined by threads of light where
// they come near one another (a plexus). Two cells per tile.
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

void main() {
  vec3 n = normalize(v_nrm);
  float t = pc.eye_time.w;
  // how much of the key light reaches here: what stands between it and the
  // sun or moon (a plant, a structure, the wolf, a hill) shades it
  float sh = keyShadow(v_pos, n);
  vec3 c = shadeLit(v_col, n, v_pos, sh);

  bool ground = v_info.z > 0.5;
  if (ground || v_info.w > 0.0) {
    // ley currents: everywhere with ley sight, on the ground and its grass,
    // fading smoothly across tile borders (ley is shared at tile edges)
    float ley = v_info.y;
    float pulse = 0.5 + 0.5 * sin(t * 2.0 + v_pos.x * 0.45 + v_pos.z * 0.3);
    vec3 leyc = mix(LEY, LEY_VEILED, VEIL);
    c += leyc * pc.misc.y * ley * ley * 0.45 * pulse;
    // a faint plexus drifting over the ley lines themselves
    // (only evaluated where it shows: it is the costliest thing on the ground)
    float on = smoothstep(0.5, 0.85, ley);
    if (ground && on > 0.0) c += mix(leyc, PLEXUS_PALE, 0.4) * plexus(v_pos.xz, t) * on * mix(0.32, 0.16, DAYLIGHT);
  }
  // hovered tile
  if (ground && all(equal(floor(v_pos.xz), pc.misc.zw))) c += HOVER * (0.7 + 0.3 * sin(t * HOVER_PULSE));
  // contact shadows: a soft ellipse under each paw, long along the facing,
  // spreading and fading as the paw lifts. Only upward faces at or below the
  // paw receive one.
  if (n.y > 0.5) for (int i = 0; i < 2; i++) {
    vec4 f = pc.feet[i];
    float lift = f.y - v_pos.y;
    if (lift < -0.05) continue;
    lift = max(lift, 0.0);
    vec2 d = v_pos.xz - f.xz;
    float s = sin(f.w), co = cos(f.w);
    vec2 local = vec2(d.x * co - d.y * s, d.x * s + d.y * co); // (side, forward)
    vec2 radii = PAW_SHADOW * (1.0 + lift * 3.0);
    float e = length(local / radii);
    float strength = PAW_SHADOW_DARK / ((1.0 + lift * 5.0) * (1.0 + lift * 5.0));
    c *= 1.0 - strength * (1.0 - smoothstep(0.1, 1.0, e));
  }
  o = vec4(applyFog(c, v_pos), 1.0);
}
