#version 450
//! bloom: one step up the glow's blur chain (3x3 tent, added onto the larger level).
#extension GL_GOOGLE_include_directive : require
#include "post.glsl"

// one step up the glow's blur chain: a 3x3 tent filter of the smaller level
// below, added onto this level (the pipeline blends additively), so the
// glow spreads wide while keeping its bright heart.
layout(set = 0, binding = 0) uniform sampler2D src;

vec3 tap(vec2 d) { return texture(src, v_uv + d * pc.texel).rgb; }

void main() {
  vec3 s = tap(vec2(0, 0)) * 4.0;
  s += (tap(vec2(-1, 0)) + tap(vec2(1, 0)) + tap(vec2(0, -1)) + tap(vec2(0, 1))) * 2.0;
  s += tap(vec2(-1, -1)) + tap(vec2(1, -1)) + tap(vec2(-1, 1)) + tap(vec2(1, 1));
  o = vec4(s / 16.0, 1.0);
}
