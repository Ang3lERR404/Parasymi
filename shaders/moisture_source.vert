#version 450
//! one thing breathing moisture laid onto the moisture field (render/passes/moisture.zig): a soft disc round where it stands, carrying what it breathed (or poured onto the ground, a spring) since the last step, spread so the disc holds all of it.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
#include "volume.glsl"
#include "moisture.glsl"

// x, z where it breathes from, its reach, the step (s); how much a second into the mist, the cloud and onto the ground
layout(location = 0) in vec4 i_at;
layout(location = 1) in vec4 i_rate;
// where across the disc this corner lies (-1..1), and what the disc adds at its middle
layout(location = 0) out vec2 v_local;
layout(location = 1) flat out vec3 v_add;

// the disc's square, two triangles
const vec2 CORNERS[6] = vec2[](vec2(-1.0, -1.0), vec2(1.0, -1.0), vec2(1.0, 1.0), vec2(-1.0, -1.0), vec2(1.0, 1.0), vec2(-1.0, 1.0));
// the disc's falloff (1 - r^2)^2 summed over it is this times its reach squared (pi / 3)
const float DISC = 1.0471976;

void main() {
  vec2 k = CORNERS[gl_VertexIndex];
  // its middle on the field (wrapped onto it), and this corner out from it
  // (rows run toward -z)
  vec2 mid = fract(overheadUv(vec3(i_at.x, 0.0, i_at.y)));
  vec2 uv = mid + vec2(k.x, -k.y) * i_at.z / OVERHEAD_SIZE;
  // the step the field was just carried on by
  float dt = moistureStep(i_at.w);
  v_local = k;
  v_add = i_rate.xyz * dt / (DISC * i_at.z * i_at.z);
  gl_Position = vec4(uv * 2.0 - 1.0, 0.0, 1.0);
}
