//! fragment-stage helpers for plant and part materials: what needs screen-space derivatives or discards.
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

// resin: the lineages' solidified sap (a structure's pods, a symbiote's
// bead), the same in the part and plant materials
const vec3 RESIN_DEEP = vec3(0.12, 0.035, 0.004); // its dark heart
const vec3 SAP_SRGB_LIN = vec3(1.0, 0.428, 0.036); // palette sap (1, .68, .22), linearised
const vec3 RESIN_NIGHT = MOONLIGHT * 0.25;          // its light at night (it is denser)
const vec3 SAP_NIGHT = MOONLIGHT * 0.3;             // what light reaches sap at night
const float RESIN_EDGE_POW = 5.0;                   // its amber gathered to its edge

// sap is alive and wet: bubbles drifting up inside it, beads sliding down
// its surface, and hard light glistening on it (sapGlisten). Added to every
// sap material. `pos`/`obj` the fragment in the world and in its mesh;
// `inside` how see-through it is there; `sh`: how much of the key light
// reaches it (its glints fall in shadow with it); `mirrored`: the points
// of light mirrored in it (pointLights)
vec3 sapLifeAt(vec3 c, vec3 sapc, vec3 n, vec3 V, vec3 pos, vec3 obj, float inside, float sh, vec3 mirrored, inout float alpha) {
  float t = pc.eye_time.w;
  vec3 lit = byDay(SAP_NIGHT, vec3(1.0));
  float bub = sapBubbles(obj, V, t) * inside;
  c += mix(sapc, vec3(1.0, 0.95, 0.85), 0.35) * bub * 0.45 * lit;
  vec2 drop = sapDroplets(obj, n, SUN, V, t);
  c = mix(c, c * 0.8 + sapc * 0.35 * lit, drop.x * 0.7) + keyLight() * drop.y * sh;
  alpha = max(alpha, drop.x * 0.85);
  vec3 g = sapGlistenWith(n, V, pos, obj, sapc, inside, sh, mirrored);
  // a glint is opaque light: it shows whole even on clear sap
  alpha = max(alpha, clamp(dot(g, vec3(0.33)), 0.0, 1.0));
  return c + g;
}

// solidified sap, thick as resin (`raw` its outward normal, `hue` its
// colour over plain amber): dense and dark where it meets the body (`h`
// 0), thinning toward its surface (`h` 1), `fade` its least opacity. No
// light of its own: what glows is light passing through it, so it dims
// with the day. Colour and opacity, fogged.
vec4 resinSurface(vec3 raw, vec3 V, vec3 pos, vec3 obj, vec3 hue, float h, float fade, float sh) {
  float ndv = clamp(dot(raw, V), 0.0, 1.0);
  float fres = pow(1.0 - ndv, FRESNEL_POW);
  vec3 sap = AMBER * hue;
  vec3 deep = RESIN_DEEP * hue * mix(0.55, 1.6, h);
  // light carried through the mass: wrapped, so the shadow side still
  // shows a warm core, thicker resin swallowing more of it
  float wrap = clamp(dot(raw, SUN) * 0.5 + 0.5, 0.0, 1.0) * mix(0.4, 1.0, sh);
  float through = max(dot(-raw, SUN), 0.0) * sh;
  vec3 lit = byDay(RESIN_NIGHT, vec3(1.0));
  PointLit pl = pointLights(pos, raw, reflect(-V, raw), true);
  vec3 c = shadeLitWith(deep, raw, sh, pl.plain);
  c += sap * lit * wrap * mix(0.05, 0.22, h);
  c += sap * lit * through * 0.25 * h;
  // light from a bloom or a mote nearby carried through the mass too
  c += sap * pl.wrapped * mix(0.1, 0.4, h);
  // the polished face: amber gathered to a narrow band at its edge (its
  // highlights are the glisten's, in sapLifeAt)
  c += mix(deep, sap * 1.4, pow(1.0 - ndv, RESIN_EDGE_POW)) * 0.3 * lit;
  // denser at the base: nearly opaque there, see-through only toward the face
  float alpha = mix(fade, 1.0, max(fres, (1.0 - h) * 0.85));
  c = sapLifeAt(c, sap, raw, V, pos, obj, h * (1.0 - fres), sh, pl.mirrored, alpha);
  return vec4(applyFog(c, pos), alpha);
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
