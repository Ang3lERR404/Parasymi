//! how dense the garden's air is anywhere: the haze over everything, the low air among the plants, the mist lying low and pooled in the hollows; read by the fog's march and by what glows in it.
// The including shader includes common.glsl and volume.glsl first (the
// overhead map holds the ground's height under every point).

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
// what is breathed into the air (the moisture field, render/passes/
// moisture.zig): how much fog a unit of its low mist makes, how thick that
// mist lies on the ground; how much fog a unit of its cloud makes, the
// height over the ground the cloud gathers at and how far it reaches up and
// down from there, and how big its billows are (noise cells per unit)
const float BREATH_MIST = 0.3;
const float BREATH_HUG = 0.8;
const float BREATH_CLOUD = 0.9;
const float CLOUD_AT = 3.7;
const float CLOUD_HALF = 0.75;
const float CLOUD_CELL = 0.9;
// the breathed mist and cloud's density at `p`, the ground `ground` under
// it: the mist lying low and torn into the same wisps as the garden's own,
// the cloud a billowing band over the ground, thickest at its middle
float breathed(vec3 p, float ground, float t) {
  vec2 f = texture(field_map, overheadUv(p)).rg;
  if (f.r + f.g < 1e-4) return 0.0;
  float h = p.y - ground;
  float mistD = f.r * BREATH_MIST * exp(-max(h, 0.0) / BREATH_HUG) * (0.45 + 0.55 * wisps(p, t));
  // how far into the band, 0 at its middle, 1 at its edge, and its billows
  float into = abs(h - CLOUD_AT) / CLOUD_HALF;
  vec2 w = vec2(cos(WIND_HEADING), sin(WIND_HEADING)) * MIST_DRIFT * 2.0 * t;
  vec3 q = (p - vec3(w.x, 0.0, w.y)) * CLOUD_CELL;
  float billow = 0.6 * noise3(q) + 0.4 * noise3(q * 2.1 + vec3(3.7, 8.1, 1.9));
  float shape = 1.0 - smoothstep(0.35 + 0.5 * billow, 1.0, into);
  float cloudD = f.g * BREATH_CLOUD * shape * smoothstep(0.35, 0.7, billow);
  return mistD + cloudD;
}
// how dense the air is at `p` at time `t`: its haze, low air and mist, and
// what is breathed into it
float airDensity(vec3 p, float t) {
  float ground = texture(overhead_map, overheadUv(p)).a;
  return haze(p.y) + low(p, ground) + mist(p, ground, t) + breathed(p, ground, t);
}
