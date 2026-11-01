#version 450
//! the moisture field's next step at each texel (render/passes/moisture.zig): the last step drifted along the garden's wind, spread into its neighbours and drying away; red the low mist, green the cloud.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
#include "volume.glsl"

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

// the mist at `uv` and the cloud at `uv2`, as the last step left them
vec2 at(vec2 uv, vec2 uv2) { return vec2(texture(field_map, uv).r, texture(field_map, uv2).g); }

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
  // each kind fetched from upwind, then its neighbours' mean round it
  vec2 c = at(lowAt, highAt);
  vec2 dx = vec2(texel.x, 0.0), dy = vec2(0.0, texel.y);
  vec2 n = 0.25 * (at(lowAt + dx, highAt + dx) + at(lowAt - dx, highAt - dx) + at(lowAt + dy, highAt + dy) + at(lowAt - dy, highAt - dy));
  c += (n - c) * clamp(vec2(LOW_SPREAD, HIGH_SPREAD) * dt, 0.0, 1.0);
  c *= exp(-dt / vec2(LOW_DRY, HIGH_DRY));
  o = vec4(max(c, 0.0), 0.0, 0.0);
}
