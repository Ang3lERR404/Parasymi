// shared push constants + lighting for world passes.
layout(push_constant) uniform Push {
  mat4 vp;
  vec4 eye_time;  // xyz camera eye, w time (s)
  vec4 fog;       // rgb fog/sky colour (linear), w fog density
  vec4 misc;      // x veil 0..1, y ley sight 0/1, zw hovered tile (x,z)
} pc;

const vec3 SUN = normalize(vec3(0.45, 0.85, 0.30));

vec3 srgb2lin(vec3 c) { return pow(c, vec3(2.2)); }

vec3 shade(vec3 albedo, vec3 n, vec3 wpos) {
  float ndl = max(dot(n, SUN), 0.0);
  vec3 sky = mix(vec3(0.35, 0.40, 0.50), vec3(0.45, 0.30, 0.65), pc.misc.x);
  vec3 ground = vec3(0.12, 0.10, 0.08);
  vec3 amb = mix(ground, sky, n.y * 0.5 + 0.5) * 0.55;
  vec3 sun = vec3(1.0, 0.95, 0.85) * ndl * 1.1;
  return albedo * (amb + sun);
}

vec3 applyFog(vec3 c, vec3 wpos) {
  float d = length(wpos - pc.eye_time.xyz);
  float f = 1.0 - exp(-pow(d * pc.fog.w, 2.0));
  return mix(c, pc.fog.rgb, clamp(f, 0.0, 1.0));
}
