#version 450
#extension GL_GOOGLE_include_directive : require
#include "post.glsl"

// one step down the glow's blur chain: a 13-tap filter of the image above,
// at half its size. The first step (threshold > 0) also keeps only what is
// brighter than white (with a soft knee below it) and weighs each group of
// taps by its brightness, so a single blazing pixel cannot flicker.
layout(set = 0, binding = 0) uniform sampler2D src;

vec3 bright(vec3 c) {
  if (pc.threshold <= 0.0) return c;
  float l = max(c.r, max(c.g, c.b));
  float knee = pc.threshold * 0.5;
  float soft = clamp(l - pc.threshold + knee, 0.0, 2.0 * knee);
  soft = soft * soft / (4.0 * knee + 1e-4);
  float keep = max(soft, l - pc.threshold) / max(l, 1e-4);
  return c * keep;
}

float weight(vec3 c) {
  return pc.threshold > 0.0 ? 1.0 / (1.0 + max(c.r, max(c.g, c.b))) : 1.0;
}

vec3 tap(vec2 d) { return texture(src, v_uv + d * pc.texel).rgb; }

void main() {
  vec3 a = tap(vec2(-2, -2)), b = tap(vec2(0, -2)), c = tap(vec2(2, -2));
  vec3 d = tap(vec2(-1, -1)), e = tap(vec2(1, -1));
  vec3 f = tap(vec2(-2, 0)), g = tap(vec2(0, 0)), h = tap(vec2(2, 0));
  vec3 i = tap(vec2(-1, 1)), j = tap(vec2(1, 1));
  vec3 k = tap(vec2(-2, 2)), l = tap(vec2(0, 2)), mm = tap(vec2(2, 2));
  // five overlapping boxes, the centre one weighted most
  vec3 g0 = (d + e + i + j) * 0.25;
  vec3 g1 = (a + b + f + g) * 0.25;
  vec3 g2 = (b + c + g + h) * 0.25;
  vec3 g3 = (f + g + k + l) * 0.25;
  vec3 g4 = (g + h + l + mm) * 0.25;
  g0 = bright(g0); g1 = bright(g1); g2 = bright(g2); g3 = bright(g3); g4 = bright(g4);
  float w0 = weight(g0) * 0.5, w1 = weight(g1) * 0.125, w2 = weight(g2) * 0.125, w3 = weight(g3) * 0.125, w4 = weight(g4) * 0.125;
  vec3 sum = g0 * w0 + g1 * w1 + g2 * w2 + g3 * w3 + g4 * w4;
  o = vec4(sum / (w0 + w1 + w2 + w3 + w4), 1.0);
}
