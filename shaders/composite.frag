#version 450
#extension GL_GOOGLE_include_directive : require
#include "post.glsl"

// the world and its glow onto the screen. The glow is laid over the scene,
// then a gentle tone curve: below 0.8 the scene passes untouched (the
// garden keeps its look), above it highlights roll off softly toward white
// instead of clipping, so bright light reads as light. A faint vignette
// draws the eye in. Output is linear (the swapchain, or the image FXAA
// reads, encodes sRGB).
layout(set = 0, binding = 0) uniform sampler2D scene;
layout(set = 0, binding = 1) uniform sampler2D glow;

// where the tone curve starts rolling highlights off
const float KNEE = 0.8;
// the vignette: how dark at the corners, where it starts and is full (from
// the centre, the width stretched by its aspect)
const float VIGNETTE = 0.18;
const float VIGNETTE_FROM = 0.35;
const float VIGNETTE_TO = 0.85;
const vec2 VIGNETTE_ASPECT = vec2(1.2, 1.0);
// perceptual luma weights (Rec. 601), for FXAA
const vec3 LUMA = vec3(0.299, 0.587, 0.114);

vec3 shoulder(vec3 c) {
  vec3 over = max(c - KNEE, 0.0);
  return min(c, vec3(KNEE)) + (1.0 - KNEE) * (1.0 - exp(-over / (1.0 - KNEE)));
}

void main() {
  vec3 c = texture(scene, v_uv).rgb;
  vec3 g = texture(glow, v_uv).rgb;
  c += g * pc.intensity;
  c = shoulder(c);
  vec2 d = v_uv - 0.5;
  c *= 1.0 - VIGNETTE * smoothstep(VIGNETTE_FROM, VIGNETTE_TO, length(d * VIGNETTE_ASPECT));
  // alpha: perceptual luma, for FXAA when it runs after this (the
  // swapchain is opaque, so it is ignored otherwise)
  o = vec4(c, sqrt(clamp(dot(c, LUMA), 0.0, 1.0)));
}
