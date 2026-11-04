#version 450
//! the sky dome: gradient by night and day, sun, moon and stars; at the
//! unforming the old sky shatters like glass from the zenith down, a ring
//! of cracks sweeping over the dome to the horizon, each pane of it flaring
//! and falling away to the ley's glow behind: veils of violet light flowing
//! round the dome, a plexus drifting across it, pulsing as the ley lines
//! did, no sun, moon or stars, its glow turning rose by day and deep by night.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

layout(location = 0) in vec3 v_dir;
layout(location = 0) out vec4 o;

// the zenith's tint over the horizon's colour, by night and by day (the
// ley's sky after the unforming)
const vec3 ZENITH_NIGHT = vec3(0.45, 0.55, 0.85);
const vec3 ZENITH_DAY = vec3(0.55, 0.65, 1.0);
// the old sky's zenith (linear), the horizon (the fog's colour, game/sky.zig)
// deepening up to it: by day from a dash of cyan into a semi-deep blue, by
// night from violet into a broody royal purple (the gardener's word)
const vec3 OLD_ZENITH_DAY = vec3(0.022, 0.06, 0.25);
const vec3 OLD_ZENITH_NIGHT = vec3(0.014, 0.002, 0.03);
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
// violet), the plexus's pale tint, and its horizon by night and by day
// (sky.zig leyNight, leyDay; must match, so the ground melts into it)
const vec3 GLOW_NIGHT = vec3(0.3, 0.2, 1.0);
const vec3 GLOW_DAY = vec3(1.0, 0.45, 0.95);
const vec3 GLOW_PALE = vec3(0.9, 0.85, 1.0);
const vec3 LEY_HORIZON_NIGHT = vec3(0.03, 0.02, 0.09);
const vec3 LEY_HORIZON_DAY = vec3(0.24, 0.1, 0.4);
// the dome's veils: how many turns of them over a radian of sky, and how
// slowly the whole dome of them wheels round (radians a second)
const float VEIL_SCALE = 1.8;
const float VEIL_WHEEL = 0.006;
// the plexus: the radius of the shell its points lie on, in cells (about
// that many cells to a radian of sky, alike all over the dome)
const float PLEXUS_SHELL = 6.0;
// the shattering: where along the shift its front sets off from the zenith
// and how much of the shift it takes to pass the horizon (sky.zig fogFrom,
// fogSpan follow it down); panes of glass to a radian; how far behind the
// front the panes fall (radians) and how ragged its edge is
const float FRONT_FROM = 0.02;
const float FRONT_SPAN = 0.5;
const float PANE_CELLS = 7.0;
const float PANE_FALL = 0.35;
const float FRONT_RAGGED = 0.22;

float hash(vec3 p) {
  uvec3 q = uvec3(ivec3(floor(p))) * uvec3(1597334673u, 3812015801u, 2798796415u);
  return float((q.x ^ q.y ^ q.z) * 1597334673u) / 4294967295.0;
}
// three randoms for a cell, 0..1 each
vec3 hash3(vec3 c) { return vec3(hash(c), hash(c + 31.7), hash(c + 63.1)); }

// smooth value noise through space, and three octaves of it: the veils are
// drawn on the dome itself, so they keep their size all the way round
float vnoise(vec3 p) {
  vec3 i = floor(p), f = fract(p);
  vec3 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), u.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), u.x), u.y),
             mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), u.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}
float fbm3(vec3 p) { return 0.5 * vnoise(p) + 0.3 * vnoise(p * 2.1 + 5.2) + 0.2 * vnoise(p * 4.3 + 1.7); }

// `d` turned round the vertical by `a` radians
vec3 wheel(vec3 d, float a) {
  float c = cos(a), s = sin(a);
  return vec3(c * d.x - s * d.z, d.y, s * d.x + c * d.z);
}

// a plexus over the dome toward `d` at time `t`: faint points drifting on a
// shell round the eye, joined by threads of light where they come near one
// another, each thread bowed along the dome (never cutting under it), so
// they keep their size and spacing from the zenith to the horizon. A cell
// holds a point if its middle lies on the shell, so every pixel agrees
// which points there are.
float plexusDome(vec3 d, float t) {
  vec3 g = d * PLEXUS_SHELL;
  vec3 id = floor(g);
  vec3 pts[24];
  int n = 0;
  for (int z = -2; z <= 2; z++) for (int y = -2; y <= 2; y++) for (int x = -2; x <= 2; x++) {
    vec3 c = id + vec3(x, y, z);
    if (abs(length(c + 0.5) - PLEXUS_SHELL) > 0.5) continue;
    vec3 r = hash3(c);
    vec3 drift = vec3(sin(t * (0.15 + 0.2 * r.x) + r.y * TAU), cos(t * (0.13 + 0.2 * r.z) + r.x * TAU), sin(t * (0.11 + 0.2 * r.y) + r.z * TAU));
    vec3 p = normalize(c + 0.5 + 0.3 * drift) * PLEXUS_SHELL;
    if (length(p - g) > 1.1 || n >= 24) continue;
    pts[n++] = p;
  }
  float v = 0.0;
  for (int k = 0; k < n; k++) {
    // a sharp bright point in a faint halo
    float e = length(g - pts[k]);
    v += (1.0 - smoothstep(0.012, 0.03, e)) * 1.2 + (1.0 - smoothstep(0.03, 0.09, e)) * 0.15;
    for (int l = k + 1; l < n; l++) {
      vec3 ab = pts[l] - pts[k];
      float len = length(ab);
      float near = 1.0 - smoothstep(0.5, 1.1, len);
      if (near <= 0.0) continue;
      // the nearest point on the thread, lifted back onto the dome
      float h = clamp(dot(g - pts[k], ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
      vec3 q = normalize(pts[k] + ab * h) * PLEXUS_SHELL;
      v += near * (1.0 - smoothstep(0.006, 0.02, length(g - q))) * 0.45;
    }
  }
  return v;
}

// the ley's glow over the dome toward `d` (above the horizon by `up`) at
// time `t`: veils of light flowing slowly round the dome, warped through
// one another, a plexus drifting across it, a band of light along the
// horizon, all breathing as the ley lines pulse
vec3 leyGlow(vec3 d, float up, float t) {
  vec3 glow = mix(GLOW_NIGHT, GLOW_DAY, DAYLIGHT);
  vec3 p = wheel(d, t * VEIL_WHEEL) * VEIL_SCALE;
  vec3 w = vec3(fbm3(p * 0.8 + t * 0.02), fbm3(p * 0.8 - t * 0.017 + 9.1), fbm3(p * 0.8 + vec3(4.3, -2.7, 7.7) + t * 0.013));
  float veil = fbm3(p * 1.2 + w * 1.8 + vec3(t * 0.03, -t * 0.021, t * 0.017));
  veil = smoothstep(0.35, 0.85, veil);
  float pulse = 0.5 + 0.5 * sin(t * 0.7 + (d.x * 0.45 + d.z * 0.3) * 6.0);
  vec3 c = glow * veil * mix(0.14, 0.3, DAYLIGHT) * (0.7 + 0.3 * pulse);
  // its hue wandering a little through the veils: otherworldly, never still
  c *= 0.85 + 0.3 * filmHue(veil * 0.35 + t * 0.01 + 0.62);
  c += mix(glow, GLOW_PALE, 0.4) * plexusDome(d, t) * smoothstep(0.0, 0.12, up) * mix(0.32, 0.14, DAYLIGHT) * (0.6 + 0.4 * pulse);
  c += glow * pow(1.0 - up, 5.0) * mix(0.05, 0.12, DAYLIGHT) * (0.8 + 0.2 * pulse);
  return c;
}

// the sky as it was toward `d`: the fog colour at the horizon (so the ground
// melts into it), deepening toward the zenith, with the sun or moon, a dusk
// glow around it, and stars once it is dark
vec3 oldSky(vec3 d, float up, float day) {
  vec3 horizon = pc.fog.rgb;
  vec3 zenith = mix(OLD_ZENITH_NIGHT, OLD_ZENITH_DAY, day);
  vec3 c = mix(horizon, zenith, pow(up, 0.6));
  float toward = max(dot(d, SUN), 0.0);
  vec3 light = mix(MOON_SKY, SUN_SKY, day);
  c += light * pow(toward, SKY_GLOW_POW) * mix(0.08, 0.35, day);
  c += light * smoothstep(DISC_OUTER, DISC_INNER, toward) * mix(0.8, 3.0, day);
  vec3 cell = d * STAR_CELLS;
  float star = step(STAR_SHARE, hash(cell)) * smoothstep(0.0, 0.15, up);
  float twinkle = 0.6 + 0.4 * sin(pc.eye_time.w * 3.0 + hash(cell + 7.0) * 40.0);
  c += STAR * star * twinkle * (1.0 - day) * 0.8;
  return c;
}

// the sky as the unforming leaves it toward `d`: the ley's horizon deepening
// up the dome, and its glow
vec3 newSky(vec3 d, float up, float day) {
  vec3 horizon = mix(LEY_HORIZON_NIGHT, LEY_HORIZON_DAY, day);
  vec3 c = mix(horizon, horizon * mix(ZENITH_NIGHT, ZENITH_DAY, day), pow(up, 0.6));
  return c + leyGlow(d, up, pc.eye_time.w);
}

// the panes of glass the old sky breaks into toward `d`, `cells` of them to
// a radian: how far the nearest pane's middle is from the zenith (radians),
// its own random, and how near `d` is to the crack between it and the next
// (0 on the crack)
vec3 pane(vec3 d, float cells) {
  vec3 g = d * cells;
  vec3 id = floor(g);
  float f1 = 1e9, f2 = 1e9;
  vec3 best = vec3(0.0, 1.0, 0.0);
  float r = 0.0;
  for (int z = -1; z <= 1; z++) for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
    vec3 c = id + vec3(x, y, z);
    vec3 p = c + hash3(c);
    float e = length(g - p);
    if (e < f1) { f2 = f1; f1 = e; best = p; r = hash(c + 97.3); }
    else if (e < f2) f2 = e;
  }
  return vec3(acos(clamp(normalize(best).y, -1.0, 1.0)), r, f2 - f1);
}

void main() {
  vec3 d = normalize(v_dir);
  float day = DAYLIGHT;
  float up = clamp(d.y, 0.0, 1.0);
  float s = SHIFT;
  if (s <= 0.0) { o = vec4(oldSky(d, up, day), 1.0); return; }
  if (s >= 1.0) { o = vec4(newSky(d, up, day), 1.0); return; }
  // the front of the shattering, as far from the zenith as it has come
  // (radians; it sets off slowly, then races down the dome to the horizon)
  float k = clamp((s - FRONT_FROM) / FRONT_SPAN, 0.0, 1.0);
  float front = -0.3 + 2.6 * pow(k, 1.35);
  vec3 pn = pane(d, PANE_CELLS);
  // the finer cracks splintering each pane, nearer the front
  float splinter = pane(wheel(d, 0.7), PANE_CELLS * 2.6).z;
  // each pane falls at its own moment as the front passes it, the front's
  // edge ragged where the sky tears unevenly
  float tear = (fbm3(d * 3.0 + 11.0) - 0.5) * FRONT_RAGGED;
  float fall = clamp((front - pn.x - tear - (pn.y - 0.5) * 0.12) / PANE_FALL, 0.0, 1.0);
  // the cracks run ahead of the falling panes, brightest at the front
  float zen = acos(clamp(d.y, -1.0, 1.0));
  float ahead = front + 0.12 - zen - tear;
  float cracking = smoothstep(0.0, 0.1, ahead) * (1.0 - smoothstep(0.1, 0.55, ahead));
  float crack = (1.0 - smoothstep(0.0, 0.016 + 0.014 * cracking, pn.z)) * cracking;
  crack += (1.0 - smoothstep(0.0, 0.03, splinter)) * smoothstep(0.05, 0.2, ahead) * (1.0 - smoothstep(0.2, 0.45, ahead)) * 0.45;
  // a pane flares as it falls away, its glass catching the glow behind
  float flare = fall * (1.0 - fall) * 4.0;
  vec3 glow = mix(GLOW_NIGHT, GLOW_DAY, day);
  vec3 c = mix(oldSky(d, up, day), newSky(d, up, day), smoothstep(0.0, 1.0, fall));
  c += mix(glow, GLOW_PALE, 0.6) * (crack * mix(1.2, 0.7, day) + flare * 0.35 * (1.0 - smoothstep(0.0, 0.08, pn.z) * 0.6));
  // the seam of light where the glow floods in, all along the front
  c += mix(GLOW_PALE, glow, 0.3) * exp(-abs(ahead - 0.12) * 18.0) * 0.25 * (1.0 - k * k);
  o = vec4(c, 1.0);
}
