#version 450
//! the air the garden stands in, marched once a half-size texel along the eye's ray: a haze over everything, mist lying low and pooled in the hollows, the key light falling through it in shafts, the points of light and the ley lines glowing in it.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
#include "volume.glsl"

// The air (render/passes/fog.zig), as the engine's volume takes it: rgb the
// light it sends toward the eye, a how much of what lies behind shows
// through. Each texel follows the eye's ray to the world's depth there (or
// on into the sky). Over the low slab where the garden stands (the mist,
// the plants, the structures) the ray is marched in steps, each starting a
// little further in by a fixed dither, so no banding shows; there the key
// light is looked up in its shadow map at every step, so what shades the
// ground shades the air too and light falls through the gaps in shafts.
// Above the slab only the haze is left, thinning with height, and the ray
// through it is summed in closed form. The points of light glow in the air
// round them, each summed in closed form along the ray; the ley lines'
// glow, read from the overhead map, rises off the ground into it.

layout(location = 0) flat in mat4 v_inv;
layout(location = 0) out vec4 o;

// the haze over everything: how dense per unit of the old distance fog's
// density (pc.fog.w, thinner as the camera draws back, so a far view never
// drowns), thinning over HAZE_FALL with height above HAZE_BASE
const float HAZE = 0.4;
const float HAZE_BASE = 0.0;
const float HAZE_FALL = 14.0;
// the low air the garden stands in, among its plants (what the key light
// falls through in shafts): how dense on the ground, thinning over LOW_FALL
// above it, denser by night and at dawn and dusk (LOW_NIGHT times)
const float LOW_AIR = 0.014;
const float LOW_FALL = 2.5;
const float LOW_NIGHT = 1.4;
// the mist: how dense at its thickest, how thick it lies on the ground, and
// the hollows it pools in (everything below POOL_TOP, fading in over
// POOL_FADE), denser by night (MIST_NIGHT times)
const float MIST = 0.045;
const float MIST_HUG = 0.45;
const float POOL_TOP = 1.1;
const float POOL_FADE = 0.7;
const float MIST_NIGHT = 1.6;
// its wisps: noise cells per unit across (flattened MIST_FLAT times
// upright, so they lie in sheets), drifting along the wind's mean heading
// (units/s), where the noise starts and is wholly mist
const float MIST_CELL = 0.12;
const float MIST_FLAT = 2.5;
const float MIST_DRIFT = 0.3;
const float WISP_FROM = 0.4;
const float WISP_TO = 0.78;
// the slab marched through (from under the lowest ground to over the tallest
// growth), and in how many steps
const float SLAB_BOTTOM = -1.0;
const float SLAB_TOP = 9.0;
const int STEPS = 28;
// how much of what the air stops it scatters (the rest it swallows)
const float ALBEDO = 0.9;
// the key light in it: how much it leans toward the light ahead (Henyey-
// Greenstein; none once the sky has shifted: its glow comes from all round),
// the even share, and how strongly
const float FORWARD = 0.45;
const float EVEN = 0.3;
const float SHAFT = 1.0;
// how strongly the points of light glow in it
const float POINT_AIR = 2.0;
// the ley lines' glow in it: how strongly, how high it rises, how far round
// a line it spreads (units)
const float LEY_AIR = 3.0;
const float LEY_RISE = 1.4;
const float LEY_SPREAD = 2.0;
// the sky's light all round, as a share of the sky's colour (less than all
// of it, so what the key light reaches stands out from what it does not)
const float SKY_AIR = 0.75;
// how far a ray into the sky is followed (a share of the drawn reach)
const float SKY_REACH = 1.0;

float hash13(vec3 p) { return hash33(p).x; }
// smooth value noise in space
float noise3(vec3 p) {
  vec3 i = floor(p), f = fract(p);
  vec3 u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), u.x), mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), u.x), u.y),
    mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), u.x), mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), u.x), u.y),
    u.z);
}
// the mist's wisps at `p` (0 clear .. 1 thick): two octaves drifting with
// the wind, flattened into sheets
float wisps(vec3 p, float t) {
  vec2 w = vec2(cos(WIND_HEADING), sin(WIND_HEADING)) * MIST_DRIFT * t;
  vec3 q = (p - vec3(w.x, 0.0, w.y)) * MIST_CELL * vec3(1.0, MIST_FLAT, 1.0);
  float n = 0.62 * noise3(q) + 0.38 * noise3(q * 2.3 + vec3(5.2, 1.3, 7.1) + t * 0.02);
  return smoothstep(WISP_FROM, WISP_TO, n);
}
// the haze's density at height `y`
float haze(float y) { return HAZE * pc.fog.w * exp(-max(y - HAZE_BASE, 0.0) / HAZE_FALL); }
// how much the haze stops between heights `ya` and `yb` along a ray rising
// `dy` a unit, `len` long (its density summed in closed form)
float hazeDepth(float ya, float yb, float dy, float len) {
  if (abs(dy) < 1e-3) return haze(0.5 * (ya + yb)) * len;
  return (haze(ya) - haze(yb)) * HAZE_FALL / dy;
}
// the mist's density at `p`, the ground `ground` under it
float mist(vec3 p, float ground, float t) {
  float hug = exp(-max(p.y - ground, 0.0) / MIST_HUG);
  float pool = smoothstep(POOL_TOP, POOL_TOP - POOL_FADE, p.y);
  return MIST * max(hug, pool) * wisps(p, t) * mix(MIST_NIGHT, 1.0, DAYLIGHT);
}
// the low air's density at `p`, the ground `ground` under it
float low(vec3 p, float ground) { return LOW_AIR * exp(-max(p.y - ground, 0.0) / LOW_FALL) * mix(LOW_NIGHT, 1.0, DAYLIGHT); }
// the share of the key light sent along the ray (1 even), cosine `c`
// between the ray and the way toward the light
float phase(float c) {
  float g = FORWARD * (1.0 - SHIFT);
  float hg = (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * c, 1.5);
  return EVEN + (1.0 - EVEN) * hg;
}
// the ground's glow and height at overhead-map point `uv`, the glow taken
// round a ring `ring` wide (uv) so it spreads into the air beside a line
vec4 groundAt(vec2 uv, float ring) {
  vec4 c = texture(overhead_map, uv);
  vec3 g = c.rgb;
  g += texture(overhead_map, uv + vec2(ring, 0.0)).rgb;
  g += texture(overhead_map, uv - vec2(ring, 0.0)).rgb;
  g += texture(overhead_map, uv + vec2(0.0, ring)).rgb;
  g += texture(overhead_map, uv - vec2(0.0, ring)).rgb;
  return vec4(g * 0.2, c.a);
}
// a stretch of air `tau` deep, lit `light` all along it, onto what is
// gathered so far: its light added in where it shows, what shows through cut
void gather(float tau, vec3 light, inout vec3 scat, inout float trans) {
  float through = exp(-tau);
  scat += trans * light * (1.0 - through);
  trans *= through;
}

void main() {
  ivec2 tx = ivec2(gl_FragCoord.xy);
  float t = pc.eye_time.w;
  Lighting L = Lighting(pc.light);
  // the ray: from the eye to the world's depth here, or on into the sky
  float d = volumeDepth(tx);
  bool sky = d >= 1.0;
  vec3 eye = pc.eye_time.xyz;
  vec3 hit = volumePoint(v_inv, tx, sky ? 0.5 : d);
  vec3 dir = normalize(hit - eye);
  float len = sky ? pc.view.w * SKY_REACH : length(hit - eye);
  // the key light along it, and the sky's light all round
  vec3 key = keyLight() * phase(dot(dir, SUN)) * SHAFT * ALBEDO;
  vec3 amb = pc.fog.rgb * SKY_AIR;
  // where the ray is within the slab
  float dy = dir.y;
  float s0 = 0.0, s1 = len;
  if (abs(dy) > 1e-4) {
    float a = (SLAB_TOP - eye.y) / dy, b = (SLAB_BOTTOM - eye.y) / dy;
    s0 = clamp(min(a, b), 0.0, len);
    s1 = clamp(max(a, b), 0.0, len);
  } else if (eye.y > SLAB_TOP || eye.y < SLAB_BOTTOM) {
    s0 = len;
  }
  vec3 scat = vec3(0.0);
  float trans = 1.0;
  // the haze before the slab
  gather(hazeDepth(eye.y, eye.y + dy * s0, dy, s0), amb + key, scat, trans);
  float t0 = trans;
  // the slab, marched: each step its haze and mist, lit by the key light
  // (as its shadow map has it there), the sky, and the ley lines' glow
  float span = s1 - s0;
  float ds = span / float(STEPS);
  float dither = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
  vec2 uvA = overheadUv(eye + dir * s0), uvB = overheadUv(eye + dir * s1);
  float ring = LEY_SPREAD * length(overheadUv(eye + vec3(1.0, 0.0, 0.0)) - overheadUv(eye));
  float stepTrans[STEPS];
  if (span > 1e-3) for (int i = 0; i < STEPS; i++) {
    float k = (float(i) + dither) / float(STEPS);
    float s = s0 + span * k;
    vec3 p = eye + dir * s;
    vec4 under = groundAt(mix(uvA, uvB, k), ring);
    float rho = haze(p.y) + low(p, under.a) + mist(p, under.a, t);
    vec3 glow = under.rgb * (0.5 + leyPulse(p, t)) * LEY_AIR * exp(-max(p.y - under.a, 0.0) / LEY_RISE) * ALBEDO;
    vec3 light = amb + key * airLit(L, p, s) + glow;
    gather(rho * ds, light, scat, trans);
    stepTrans[i] = trans;
  } else for (int i = 0; i < STEPS; i++) stepTrans[i] = trans;
  // the haze after it (a ray rising out of the slab into the sky)
  gather(hazeDepth(eye.y + dy * s1, eye.y + dy * len, dy, len - s1), amb + key, scat, trans);
  // the points of light: each one's glow along the ray in closed form (its
  // falloff, light.glsl `pointLight`, summed across the chord through its
  // reach), in the air as it is where the ray passes nearest it, seen
  // through what lies before that
  int count = int(L.info.x + 0.5);
  for (int i = 0; i < count; i++) {
    vec4 lp = L.lights[i].pos;
    vec3 to = lp.xyz - eye;
    float near = dot(to, dir);
    float h2 = max(dot(to, to) - near * near, 0.0);
    float r2 = lp.w * lp.w;
    if (h2 >= r2) continue;
    float chord = sqrt(r2 - h2);
    float ua = max(-chord, -near), ub = min(chord, len - near);
    if (ua >= ub) continue;
    float c = sqrt((r2 + LIGHT_FALLOFF * h2) / LIGHT_FALLOFF);
    float sum = r2 / (LIGHT_FALLOFF * c) * (atan(ub / c) - atan(ua / c));
    float win = (1.0 - h2 / r2) * (1.0 - h2 / r2);
    float at = clamp(near, 0.0, len);
    vec3 p = eye + dir * at;
    float ground = texture(overhead_map, overheadUv(p)).a;
    float rho = haze(p.y) + low(p, ground) + mist(p, ground, t);
    float seen = at < s0 ? t0 : at >= s1 ? trans : stepTrans[clamp(int((at - s0) / max(ds, 1e-4)), 0, STEPS - 1)];
    scat += L.lights[i].col.rgb * sum * win * rho * seen * ALBEDO * POINT_AIR;
  }
  o = vec4(scat, trans);
}
