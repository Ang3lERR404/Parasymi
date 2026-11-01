#version 450
//! the moisture field's next step at each texel (render/passes/moisture.zig): the last step drifted along the garden's wind, spread into its neighbours and drying away; thick cloud gathering, holding together and raining itself out, the rain soaking the ground. Red the low mist, green the cloud, blue the rain falling, alpha the ground's wetness.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
#include "volume.glsl"
#include "moisture.glsl"

// how long the step is (s)
layout(location = 0) flat in float v_dt;
layout(location = 0) out vec4 o;

// how fast each kind drifts along the wind (a share of the wind's own
// pace, units/s): the mist slowly over the ground, the cloud faster aloft
const float LOW_DRIFT = 0.25;
const float HIGH_DRIFT = 0.6;
// how fast each spreads into its neighbours (the share of the difference
// closed a second)
const float LOW_SPREAD = 1.2;
const float HIGH_SPREAD = 0.6;
// how long each takes to dry away to a third (s)
const float LOW_DRY = 45.0;
const float HIGH_DRY = 120.0;
// cloud gathering: from how thick it starts to hold together, and how thick
// it wholly holds; held, it spreads this share less and lasts this many
// times longer, so it pools into heavy cloud instead of thinning away
const float GATHER_FROM = 0.5;
const float GATHER_TO = 1.4;
const float GATHER_HOLD = 0.85;
const float GATHER_KEEP = 1.5;
// rain: how thick cloud must grow before it rains (MOISTURE_RAIN_AT,
// moisture.glsl), how thin it is rained out to before it stops, how much
// rain its thinnest keeps falling (a share of a downpour), how quickly a
// shower builds and eases (a second), and how much cloud a downpour rains
// out a second
const float RAIN_STOP = 0.8;
const float RAIN_FLOOR = 0.25;
const float RAIN_EASE = 0.35;
const float RAIN_DRAW = 0.05;
// the ground under the rain: how long a downpour takes to soak it through,
// and how long it takes to dry to a third once the rain stops (s)
const float WET_SOAK = 40.0;
const float WET_DRY = 300.0;

// the mist at `uv`, the cloud and the rain at `uv2`, as the last step left them
vec3 at(vec2 uv, vec2 uv2) {
  vec4 h = texture(field_map, uv2);
  return vec3(texture(field_map, uv).r, h.g, h.b);
}

void main() {
  float t = pc.eye_time.w;
  // one texel across the field, and this texel's place on it
  vec2 texel = 1.0 / vec2(textureSize(field_map, 0));
  vec2 uv = gl_FragCoord.xy * texel;
  float dt = v_dt;
  // the wind here, turned onto the field (its rows run toward -z), and how
  // far it carries each kind this step
  vec2 w = gardenWind(t, vec2(uv.x, -uv.y) * OVERHEAD_SIZE).xy;
  vec2 along = vec2(w.x, -w.y) * texel * dt;
  vec2 lowAt = uv - along * LOW_DRIFT;
  vec2 highAt = uv - along * HIGH_DRIFT;
  // each kind fetched from upwind (the rain rides with its cloud), then the
  // mist and the cloud's neighbours' mean round them
  vec3 c = at(lowAt, highAt);
  vec2 dx = vec2(texel.x, 0.0), dy = vec2(0.0, texel.y);
  vec3 n = 0.25 * (at(lowAt + dx, highAt + dx) + at(lowAt - dx, highAt - dx) + at(lowAt + dy, highAt + dy) + at(lowAt - dy, highAt - dy));
  // how much the cloud here holds together: thick, it spreads less and lasts
  float held = smoothstep(GATHER_FROM, GATHER_TO, c.g);
  vec2 spread = vec2(LOW_SPREAD, HIGH_SPREAD * (1.0 - GATHER_HOLD * held));
  c.rg += (n.rg - c.rg) * clamp(spread * dt, 0.0, 1.0);
  c.rg *= exp(-dt / vec2(LOW_DRY, HIGH_DRY * (1.0 + GATHER_KEEP * held)));
  // rain: a cloud thick enough begins to rain and keeps raining until it is
  // rained out thin, more the thicker it is; a shower builds and eases
  bool raining = c.b > 0.01 ? c.g > RAIN_STOP : c.g > MOISTURE_RAIN_AT;
  float want = raining ? mix(RAIN_FLOOR, 1.0, clamp((c.g - RAIN_STOP) / (MOISTURE_RAIN_AT - RAIN_STOP), 0.0, 1.0)) : 0.0;
  c.b += (want - c.b) * (1.0 - exp(-dt * RAIN_EASE));
  c.g -= c.b * RAIN_DRAW * dt;
  // the ground under it (which stays where it is): soaked by the rain on
  // it, drying slowly once the rain stops
  float wet = texture(field_map, uv).a;
  wet = min(wet + c.b * dt / WET_SOAK, 1.0) * exp(-dt / WET_DRY);
  o = vec4(max(c, 0.0), wet);
}
