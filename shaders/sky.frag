#version 450
//! the sky dome: gradient by night and day, sun, moon and stars; once the
//! unforming has shifted it, the ley's glow: veils of violet light flowing
//! over it, a plexus drifting across it, pulsing as the ley lines did, no
//! sun, moon or stars, its glow turning rose by day and deep by night.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

layout(location = 0) in vec3 v_dir;
layout(location = 0) out vec4 o;

// the zenith's tint over the horizon's colour, by night and by day
const vec3 ZENITH_NIGHT = vec3(0.45, 0.55, 0.85);
const vec3 ZENITH_DAY = vec3(0.55, 0.65, 1.0);
// the key light seen in the sky: a cool moon, a warm sun; how tight its glow
// is, and where its disc's edge lies (cosine of its angular radius)
const vec3 MOON_SKY = vec3(0.55, 0.65, 0.95);
const vec3 SUN_SKY = vec3(1.0, 0.85, 0.6);
const float SKY_GLOW_POW = 24.0;
const float DISC_OUTER = 0.9993;
const float DISC_INNER = 0.9996;
// stars: cells across the dome, the share of them holding one, their colour
const float STAR_CELLS = 180.0;
const float STAR_SHARE = 0.9975;
const vec3 STAR = vec3(0.9, 0.92, 1.0);
// the shifted sky: its glow by night (deep blue violet) and by day (rose
// violet), the plexus's pale tint, and where the dome is laid flat for it
// (cells per unit of the plane over the eye; the plane's lift at the horizon)
const vec3 GLOW_NIGHT = vec3(0.3, 0.2, 1.0);
const vec3 GLOW_DAY = vec3(1.0, 0.45, 0.95);
const vec3 GLOW_PALE = vec3(0.9, 0.85, 1.0);
const float PLEXUS_CELLS = 3.0;
const float PLANE_LIFT = 0.25;

float hash(vec3 p) {
  uvec3 q = uvec3(ivec3(floor(p))) * uvec3(1597334673u, 3812015801u, 2798796415u);
  return float((q.x ^ q.y ^ q.z) * 1597334673u) / 4294967295.0;
}

// smooth value noise over the plane, and three octaves of it
float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}
float fbm3(vec2 p) { return 0.5 * vnoise(p) + 0.3 * vnoise(p * 2.1 + 5.2) + 0.2 * vnoise(p * 4.3 + 1.7); }

// the ley's glow over the dome toward `d` (above the horizon by `up`) at
// time `t`: veils of light flowing slowly, warped through one another, a
// plexus drifting across it, a band of light along the horizon, all
// breathing as the ley lines pulse
vec3 leyGlow(vec3 d, float up, float t) {
  vec3 glow = mix(GLOW_NIGHT, GLOW_DAY, DAYLIGHT);
  // the dome laid flat over the eye
  vec2 q = d.xz / (up + PLANE_LIFT);
  vec2 w = vec2(fbm3(q * 0.6 + t * 0.02), fbm3(q * 0.6 - t * 0.017 + 9.1));
  float veil = fbm3(q * 0.9 + w * 1.8 + vec2(t * 0.03, -t * 0.021));
  veil = smoothstep(0.35, 0.85, veil);
  float pulse = 0.5 + 0.5 * sin(t * 0.7 + q.x * 0.45 + q.y * 0.3);
  vec3 c = glow * veil * mix(0.14, 0.3, DAYLIGHT) * (0.7 + 0.3 * pulse);
  // its hue wandering a little through the veils: otherworldly, never still
  c *= 0.85 + 0.3 * filmHue(veil * 0.35 + t * 0.01 + 0.62);
  c += mix(glow, GLOW_PALE, 0.4) * plexus(q * PLEXUS_CELLS, t) * smoothstep(0.02, 0.3, up) * mix(0.32, 0.14, DAYLIGHT) * (0.6 + 0.4 * pulse);
  c += glow * pow(1.0 - up, 5.0) * mix(0.05, 0.12, DAYLIGHT) * (0.8 + 0.2 * pulse);
  return c;
}

// the sky dome: the fog colour at the horizon (so the ground melts into it),
// deepening toward the zenith, with the sun or moon, a dusk glow around it,
// and stars once it is dark.
void main() {
  vec3 d = normalize(v_dir);
  float day = DAYLIGHT;
  float up = clamp(d.y, 0.0, 1.0);
  vec3 horizon = pc.fog.rgb;
  vec3 zenith = mix(horizon * ZENITH_NIGHT, horizon * ZENITH_DAY, day);
  vec3 c = mix(horizon, zenith, pow(up, 0.6));
  // what of the old sky is left (the shift takes its sun, moon and stars)
  float old = 1.0 - smoothstep(0.0, 0.8, SHIFT);
  // glow and disc around the key light (the sun by day, a cool moon by night)
  float toward = max(dot(d, SUN), 0.0);
  vec3 light = mix(MOON_SKY, SUN_SKY, day);
  c += light * pow(toward, SKY_GLOW_POW) * mix(0.08, 0.35, day) * old;
  c += light * smoothstep(DISC_OUTER, DISC_INNER, toward) * mix(0.8, 3.0, day) * old;
  // stars: sparse cells on the dome, twinkling, gone by day
  vec3 cell = d * STAR_CELLS;
  float star = step(STAR_SHARE, hash(cell)) * smoothstep(0.0, 0.15, up);
  float twinkle = 0.6 + 0.4 * sin(pc.eye_time.w * 3.0 + hash(cell + 7.0) * 40.0);
  c += STAR * star * twinkle * (1.0 - day) * 0.8 * old;
  // the ley's glow, coming in as the sky shifts
  if (SHIFT > 0.0) c += leyGlow(d, up, pc.eye_time.w) * smoothstep(0.1, 1.0, SHIFT);
  o = vec4(c, 1.0);
}
