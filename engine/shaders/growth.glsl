//! growth along growth splines on the GPU (gfx/growth.zig): a vertex shrunk into the point it grows out of until its spline's front comes by, then grown out, thin at first and thickening as its spline finishes; a piece that falls (a young leaf) drops away and shrinks to nothing later on.
// A vertex's growth record (vertex.Grow): `from` where it grows out of,
// `at` when it begins, how long it takes, and when its spline began and
// was done (at.y 0: not on a spline); a piece hung on a spline that falls
// later has at.z the negated moment it starts falling and at.w how long it
// takes. `g` is how far its thing has grown (0..1), `lag` how far into its
// own growth it starts (a leaf's tip lagging its base). Shrunk about a
// point, so its normal holds.

// how thin a piece is while its spline is still growing
const float SPROUT_THIN = 0.5;
// how far a falling piece drops (mesh units) by the time it is gone, and
// how far through its fall it starts to shrink away
const float FALL_DROP = 0.5;
const float FALL_SHRINK = 0.45;

vec3 growOut(vec3 p, vec3 from, vec4 at, float g, float lag) {
  if (at.y <= 0.0) return p;
  float out_ = smoothstep(at.x + lag, at.x + at.y, g);
  if (at.z < 0.0) {
    // falling: it lets go, drops and shrinks away
    float f = smoothstep(-at.z, -at.z + at.w, g);
    out_ *= 1.0 - smoothstep(FALL_SHRINK, 1.0, f);
    return from + (p - from) * out_ - vec3(0.0, FALL_DROP * f * f, 0.0);
  }
  if (at.w > at.z) out_ *= mix(SPROUT_THIN, 1.0, smoothstep(at.z, at.w, g));
  return from + (p - from) * out_;
}
