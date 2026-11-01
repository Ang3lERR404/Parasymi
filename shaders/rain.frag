#version 450
//! one raindrop (rain.vert): a pale streak soft at its edges and fading toward its tail, or the thin ring of its splash fading as it spreads; lit by the sky and the key light, seen through the fog.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

layout(location = 0) in vec2 v_local;
layout(location = 1) flat in float v_kind;
layout(location = 2) in float v_fade;
layout(location = 3) in vec3 v_pos;
layout(location = 0) out vec4 o;

// how much of the sky's light and of the key light a drop gives back, its
// tint, and how see-through a streak and a splash are at their thickest
const float SKY_LIT = 0.9;
const float KEY_LIT = 0.25;
const vec3 TINT = vec3(0.85, 0.92, 1.0);
const float STREAK_ALPHA = 0.5;
const float SPLASH_ALPHA = 0.55;
// a drop fading out toward the edge of where rain is drawn round the view
// (units from its middle)
const float NEAR = 15.0;
const float FAR = 21.0;

void main() {
  float a;
  if (v_kind < 0.5) {
    // the streak: soft across, bright at its head, fading to its tail
    a = STREAK_ALPHA * (1.0 - v_local.y * v_local.y) * v_local.x;
  } else {
    // the splash: a thin ring, fading as it spreads
    float r = length(v_local);
    a = SPLASH_ALPHA * smoothstep(0.55, 0.85, r) * (1.0 - smoothstep(0.85, 1.0, r)) * (1.0 - v_fade);
  }
  vec2 off = abs(v_pos.xz - pc.view.xy);
  a *= 1.0 - smoothstep(NEAR, FAR, max(off.x, off.y));
  if (a < 0.003) discard;
  vec3 c = (pc.fog.rgb * SKY_LIT + keyLight() * KEY_LIT) * TINT;
  o = vec4(applyFog(c, v_pos), a);
}
