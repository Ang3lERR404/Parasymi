#version 450
//! the world and its glow onto the screen: highlights rolled off above 0.8 keeping their hue, faint vignette, luma in alpha for FXAA.
#extension GL_GOOGLE_include_directive : require
#include "post.glsl"

// the world and its glow onto the screen. The glow is laid over the scene,
// then a gentle tone curve: below 0.8 the scene passes untouched (the
// garden keeps its look), above it highlights roll off softly by their
// brightest channel, keeping their hue, instead of clipping or draining to
// white, so bright light reads as light in its own colour. A faint vignette
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

// one value rolled off above the knee, toward 1 and never past it
float roll(float v) {
  return v <= KNEE ? v : KNEE + (1.0 - KNEE) * (1.0 - exp(-(v - KNEE) / (1.0 - KNEE)));
}
// a colour's highlights rolled off by its brightest channel, the others
// scaled with it, so a bright glow dims keeping its own hue instead of
// each channel flattening toward white on its own
vec3 shoulder(vec3 c) {
  float peak = max(max(c.r, c.g), c.b);
  return peak <= KNEE ? c : c * (roll(peak) / peak);
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
