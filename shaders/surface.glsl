// fragment-stage helpers for the plant and part materials (after common.glsl):
// what needs screen-space derivatives or discards.

// direction of increasing `t` across the surface at `pos` (up a stem, along
// a tube that is its spine). Zero where `t` is constant (a petal fan, a
// knot, a sphere). Call it first, in uniform control flow.
vec3 surfaceTangent(vec3 pos, float t) {
  vec3 dpx = dFdx(pos);
  vec3 dpy = dFdy(pos);
  vec3 sn = cross(dpx, dpy);
  vec3 r1 = cross(dpy, sn);
  vec3 r2 = cross(sn, dpx);
  float det = dot(dpx, r1);
  return abs(det) < 1e-12 ? vec3(0.0) : (r1 * dFdx(t) + r2 * dFdy(t)) / det;
}

#ifdef GLASS
// the glass pass writes no depth, so the depth test may always run before
// the shader: a fragment its solid pass kept (at the same depth, failing
// the strict `less` test) or anything solid in front is never shaded
layout(early_fragment_tests) in;
#endif

// two passes draw every surface (SOLID, common.glsl), so nothing
// see-through hides what lies behind it: this pass keeps only its share
// of fragments of opacity `a`
void keepPass(float a) {
#ifdef GLASS
  if (a >= SOLID || a < CLEAR) discard;
#else
  if (a < SOLID) discard;
#endif
}
