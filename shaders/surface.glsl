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

// ---- leaves and petals (meshgen laminae: along 0..1 base to tip, across
// 1..3 edge to edge, its midrib at 2; 0 off any sheet) ----
// lateral vein pairs along a leaf; streaks across a petal
const float LEAF_LATERALS = 7.0;
const float PETAL_STREAKS = 9.0;
// what a sheet's surface holds at a point: its veins (midrib, laterals, or
// a petal's streaks) 0..1, the fine net between them 0..1, how near its edge
// 0..1, and where on it the point lies
struct Sheet { float vein; float net; float edge; float along; float across; };
// how near `p` lies to a border between worley cells: 1 on the border
float sheetNet(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 d = vec2(8.0);
  for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
    vec2 o = vec2(x, y);
    vec2 c = o + vec2(hash12(i + o), hash12(i + o + 23.1)) - f;
    float e = dot(c, c);
    if (e < d.x) d = vec2(e, d.x); else if (e < d.y) d.y = e;
  }
  d = sqrt(d);
  return 1.0 - smoothstep(0.02, 0.09, d.y - d.x);
}
// a leaf's surface: the midrib, lateral veins arching out from it toward
// the tip and fading before the edge, and the fine net of veinlets between
// them (each fading out where a pixel spans too much to show it)
Sheet leafSheet(vec2 sh) {
  float along = sh.x, across = sh.y - 2.0, a = abs(across);
  float fa = fwidth(a);
  float mid = 1.0 - smoothstep(0.035, 0.06 + 2.0 * fa, a);
  float phase = along * LEAF_LATERALS - a * 1.25 + a * a * 0.45;
  float fp = fwidth(phase);
  float d = abs(fract(phase + 0.5) - 0.5);
  float w = mix(0.07, 0.025, a);
  float lat = (1.0 - smoothstep(w, w + fp * 1.5, d)) * smoothstep(0.04, 0.12, a) * (1.0 - smoothstep(0.8, 0.96, a));
  lat *= smoothstep(0.03, 0.12, along) * (1.0 - smoothstep(0.86, 0.98, along)) * (1.0 - smoothstep(0.25, 0.6, fp));
  vec2 q = vec2(across * 9.0, along * 24.0);
  float net = sheetNet(q) * (1.0 - smoothstep(0.3, 0.8, length(fwidth(q))));
  return Sheet(max(mid, lat), net, smoothstep(0.72, 1.0, a), along, across);
}
// a petal's surface: fine streaks running out from its claw, wavering,
// fading toward its tip, and its edge
Sheet petalSheet(vec2 sh) {
  float along = sh.x, across = sh.y - 2.0, a = abs(across);
  float phase = across * PETAL_STREAKS + 0.18 * sin(along * 7.0 + across * 3.0);
  float fp = fwidth(phase);
  float d = abs(fract(phase + 0.5) - 0.5);
  float streak = (1.0 - smoothstep(0.08, 0.08 + fp * 1.5, d)) * (1.0 - smoothstep(0.55, 0.95, along)) * (1.0 - smoothstep(0.3, 0.7, fp));
  return Sheet(streak, 0.0, smoothstep(0.78, 1.0, a), along, across);
}
// a sheet's colour from its plain `body` (and a stem's, from its grain): a leaf's veins paler and
// yellower, the net between them a shade darker, its edge a little
// yellower, its base paler; a petal's streaks deeper, its throat deeper,
// its edge paler. `trans` (out): how much of the light through it gets
// past its veins (they shade what shines through)
// ridges round a stem, and how far its fibres run before they change
const float STEM_RIDGES = 9.0;
const float STEM_FIBRE = 40.0;
// a stem's surface (a tube: `round` 0..1 round its ring, `t` along it):
// fine ridges running its length, darker in their grooves, and fibres
// streaking along them, lighter and darker by turns (fading where a
// pixel spans too much); a factor on its colour
float stemGrain(float round, float t) {
  float ph = round * STEM_RIDGES;
  float fr = fwidth(ph);
  float ridge = 0.5 + 0.5 * cos(ph * TAU);
  float streak = hash12(vec2(floor(round * STEM_RIDGES * 3.0), floor(t * STEM_FIBRE)));
  float k = 1.0 - smoothstep(0.3, 0.7, fr);
  return 1.0 + k * ((ridge - 0.5) * 0.34 + (streak - 0.5) * 0.2);
}
// how a lit stem or tendril is grained (`stemGrain` on a tube's sides, 1
// anywhere else): taken on all its light, its skin's and its sap's alike
float grainOf(int part, vec2 sh, float t) {
  return (sh.y > 3.5 && (part == PART_STEM || part == PART_TENDRIL)) ? stemGrain(fract(sh.y), t) : 1.0;
}
vec3 sheetColour(vec3 body, int part, vec2 sh, float t, out float trans) {
  trans = 1.0;
  if (sh.y < 0.5) return body;
  if (sh.y > 3.5) return body;
  if (part == PART_LEAF || part == PART_EAR) {
    Sheet s = leafSheet(sh);
    body = mix(body, body * vec3(1.3, 1.32, 0.92) + 0.015, s.vein * 0.6);
    body *= 1.0 - 0.09 * s.net;
    body = mix(body, body * vec3(1.1, 1.12, 0.78), s.edge * 0.45);
    body *= mix(1.12, 1.0, smoothstep(0.0, 0.25, s.along));
    trans = (1.0 - 0.55 * s.vein) * (1.0 - 0.3 * s.net);
  } else if (part == PART_BLOOM) {
    Sheet s = petalSheet(sh);
    body = mix(body, body * 0.7, s.vein * 0.4);
    body *= mix(0.75, 1.0, smoothstep(0.0, 0.4, s.along));
    body = mix(body, mix(body, vec3(1.0), 0.18), s.edge * 0.5);
    trans = 1.0 - 0.35 * s.vein;
  }
  return body;
}
