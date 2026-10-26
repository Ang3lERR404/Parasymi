//! growth along growth splines on the GPU (gfx/growth.zig): a vertex shrunk into the point it grows out of until its spline's front comes by, then grown out, thin at first and thickening as its spline finishes.
// A vertex's growth record (vertex.Grow): `from` where it grows out of,
// `at` when it begins, how long it takes, and when its spline began and
// was done (at.y 0: not on a spline). `g` is how far its thing has grown
// (0..1), `lag` how far into its own growth it starts (a leaf's tip lagging
// its base). Shrunk about a point, so its normal holds.

// how thin a piece is while its spline is still growing
const float SPROUT_THIN = 0.5;

vec3 growOut(vec3 p, vec3 from, vec4 at, float g, float lag) {
  if (at.y <= 0.0) return p;
  float out_ = smoothstep(at.x + lag, at.x + at.y, g);
  if (at.w > at.z) out_ *= mix(SPROUT_THIN, 1.0, smoothstep(at.z, at.w, g));
  return from + (p - from) * out_;
}
