#version 450
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

float hash(vec3 p) {
  uvec3 q = uvec3(ivec3(floor(p))) * uvec3(1597334673u, 3812015801u, 2798796415u);
  return float((q.x ^ q.y ^ q.z) * 1597334673u) / 4294967295.0;
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
  // glow and disc around the key light (the sun by day, a cool moon by night)
  float toward = max(dot(d, SUN), 0.0);
  vec3 light = mix(MOON_SKY, SUN_SKY, day);
  c += light * pow(toward, SKY_GLOW_POW) * mix(0.08, 0.35, day);
  c += light * smoothstep(DISC_OUTER, DISC_INNER, toward) * mix(0.8, 3.0, day);
  // stars: sparse cells on the dome, twinkling, gone by day
  vec3 cell = d * STAR_CELLS;
  float star = step(STAR_SHARE, hash(cell)) * smoothstep(0.0, 0.15, up);
  float twinkle = 0.6 + 0.4 * sin(pc.eye_time.w * 3.0 + hash(cell + 7.0) * 40.0);
  c += STAR * star * twinkle * (1.0 - day) * 0.8;
  o = vec4(c, 1.0);
}
