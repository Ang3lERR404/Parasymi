// shared push constants + lighting for world passes.
layout(push_constant) uniform Push {
  mat4 vp;
  vec4 eye_time;  // xyz camera eye, w time (s)
  vec4 fog;       // rgb fog/sky colour (linear), w fog density
  vec4 misc;      // x veil 0..1, y ley sight 0/1, zw hovered tile (x,z)
  vec4 sun;       // xyz direction toward the key light (sun or moon), w daylight 0..1
  vec4 feet[2];   // the wolf's paws: xyz world position, w facing yaw
  vec4 view;      // xy camera target (x,z), z fog-out start, w fog-out end (horizontal)
} pc;

#define SUN pc.sun.xyz

vec3 srgb2lin(vec3 c) { return pow(c, vec3(2.2)); }

vec3 shade(vec3 albedo, vec3 n, vec3 wpos) {
  float ndl = max(dot(n, SUN), 0.0);
  float day = pc.sun.w;
  vec3 sky = mix(vec3(0.35, 0.40, 0.50), vec3(0.45, 0.30, 0.65), pc.misc.x);
  sky = mix(vec3(0.07, 0.09, 0.18), sky, day);
  vec3 ground = vec3(0.12, 0.10, 0.08) * mix(0.3, 1.0, day);
  vec3 amb = mix(ground, sky, n.y * 0.5 + 0.5) * 0.55;
  vec3 light = mix(vec3(0.35, 0.45, 0.8) * 0.35, vec3(1.0, 0.95, 0.85) * 1.1, day);
  vec3 sun = light * ndl;
  return albedo * (amb + sun);
}

vec3 applyFog(vec3 c, vec3 wpos) {
  float d = length(wpos - pc.eye_time.xyz);
  float f = 1.0 - exp(-pow(d * pc.fog.w, 2.0));
  // the drawn world ends a little before the streamed one: close it into the
  // horizon so a low camera never sees an edge
  f = max(f, smoothstep(pc.view.z, pc.view.w, length(wpos.xz - pc.view.xy)));
  return mix(c, pc.fog.rgb, clamp(f, 0.0, 1.0));
}
