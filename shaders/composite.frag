#version 450

// the world and its glow onto the screen. The glow is laid over the scene,
// then a gentle tone curve: below 0.8 the scene passes untouched (the
// garden keeps its look), above it highlights roll off softly toward white
// instead of clipping, so bright light reads as light. A faint vignette
// draws the eye in. Output is linear (the swapchain encodes sRGB).
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 o;
layout(set = 0, binding = 0) uniform sampler2D scene;
layout(set = 0, binding = 1) uniform sampler2D glow;
layout(push_constant) uniform Push {
  vec2 texel;
  float threshold;
  float intensity;
} pc;

vec3 shoulder(vec3 c) {
  const float knee = 0.8;
  vec3 over = max(c - knee, 0.0);
  return min(c, vec3(knee)) + (1.0 - knee) * (1.0 - exp(-over / (1.0 - knee)));
}

void main() {
  vec3 c = texture(scene, v_uv).rgb;
  vec3 g = texture(glow, v_uv).rgb;
  c += g * pc.intensity;
  c = shoulder(c);
  vec2 d = v_uv - 0.5;
  c *= 1.0 - 0.18 * smoothstep(0.35, 0.85, length(d * vec2(1.2, 1.0)));
  o = vec4(c, 1.0);
}
