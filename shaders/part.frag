#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

layout(location = 0) in vec3 v_pos;
layout(location = 1) in vec3 v_nrm;
layout(location = 2) in vec3 v_col;
layout(location = 3) in float v_glow;
layout(location = 4) flat in float v_part;
layout(location = 5) in float v_t;
layout(location = 6) flat in float v_fade;
layout(location = 7) in float v_u;
layout(location = 8) in vec3 v_obj;
layout(location = 9) flat in float v_phase; // per-instance phase (seeds a beam's motes)
layout(location = 0) out vec4 o;

const vec3 SAP = vec3(1.0, 0.43, 0.08);       // linear amber, the only accent
const vec3 SAP_DEEP = vec3(0.12, 0.035, 0.004); // the sac's dark heart
const vec3 SAP_SRGB_LIN = vec3(1.0, 0.428, 0.036); // palette sap (1, .68, .22), linearised

// direction of increasing `v_t` across the surface: along a tube that is its
// spine. Zero where `v_t` is constant (knots, spheres).
vec3 surfaceTangent() {
  vec3 dpx = dFdx(v_pos);
  vec3 dpy = dFdy(v_pos);
  vec3 sn = cross(dpx, dpy);
  vec3 r1 = cross(dpy, sn);
  vec3 r2 = cross(sn, dpx);
  float det = dot(dpx, r1);
  return abs(det) < 1e-12 ? vec3(0.0) : (r1 * dFdx(v_t) + r2 * dFdy(v_t)) / det;
}

// sap is alive: bubbles drifting up inside it, beads sliding down its
// surface. Added to every sap material.
vec3 sapLife(vec3 c, vec3 sapc, vec3 n, vec3 V, float inside, inout float alpha) {
  float t = pc.eye_time.w;
  vec3 lit = mix(vec3(0.35, 0.45, 0.8) * 0.3, vec3(1.0), pc.sun.w);
  float bub = sapBubbles(v_obj, V, t) * inside;
  c += mix(sapc, vec3(1.0, 0.95, 0.85), 0.35) * bub * 0.45 * lit;
  vec2 drop = sapDroplets(v_obj, n, SUN, V, t);
  c = mix(c, c * 0.8 + sapc * 0.35 * lit, drop.x * 0.7) + lit * drop.y * 0.9;
  alpha = max(alpha, drop.x * 0.85);
  return c;
}

void main() {
  vec3 tgrad = surfaceTangent(); // derivatives first, in uniform control flow
  vec3 raw = normalize(v_nrm);
  vec3 n = gl_FrontFacing ? raw : -raw;
  vec3 V = normalize(pc.eye_time.xyz - v_pos);
  int part = int(v_part + 0.5);
  float alpha = 1.0;
  vec3 c;

  // sap's hue follows its vertex colour relative to plain sap, so an
  // instance tint (paw beans, nose) can make it denser and browner
  vec3 hue = clamp(v_col / SAP_SRGB_LIN, 0.0, 1.5);
  bool inner_ear = part == 5 && dot(raw, V) < 0.0;
  if (part == 8) {
    // soft rays sent from one bloom to the other: no core, a faint haze
    // across the width (v_u -1..1) with a few soft streaks in it, each
    // broken into long swells of light travelling from the sender (v_t 0)
    // to the receiver. The hue runs the rainbow from one end to the other,
    // rolling along with them; tiny motes of light drift along inside,
    // shifting hue as they go. It carries light of its own (bloom catches
    // the swells and motes); a dark network's beam is a faint trace.
    float t = pc.eye_time.w;
    float u = v_u;
    float len = max(v_fade, 0.1);
    float x = v_t * len; // world distance from the sender
    float lit = min(v_glow, 1.0);
    float roll = v_t - t * 0.12;
    float haze = exp(-u * u * 3.0);
    vec3 rays = vec3(0.0);
    float ray_a = 0.0;
    for (int k = 0; k < 5; k++) {
      float fk = float(k);
      float lane = (fk - 2.0) * 0.32 + 0.1 * sin(t * 0.6 + fk * 2.1 + x * 0.7);
      float across = exp(-(u - lane) * (u - lane) * 38.0);
      float swell = 0.5 + 0.5 * sin(x * (1.1 + 0.23 * fk) - t * (1.6 + 0.3 * fk) + fk * 1.7);
      float a = across * swell * swell * (1.0 - 0.15 * abs(fk - 2.0));
      rays += filmHue(roll + fk * 0.04) * a;
      ray_a += a;
    }
    // motes: one per cell along the beam, drifting toward the receiver,
    // each at its own place across (seeded by the instance's phase, which
    // holds still, unlike its length) and twinkling; neighbouring cells
    // too, so none is cut at a cell's edge
    const float CELL = 0.3;
    const float DRIFT = 0.55;
    const float WIDTH = 0.42; // part.vert's half width at the middle
    float m = 0.0;
    vec3 mc = vec3(0.0);
    float drift = (x - t * DRIFT) / CELL;
    for (int k = -1; k <= 1; k++) {
      float id = floor(drift) + float(k);
      vec3 h = hash33(vec3(id, v_phase * 7.31, 7.0));
      float dx = (drift - id - h.x) * CELL;
      float du = (u - (h.y * 1.5 - 0.75) - 0.08 * sin(t * 1.3 + h.z * TAU)) * WIDTH;
      float tw = 0.55 + 0.45 * sin(t * (3.0 + 3.0 * h.z) + h.x * TAU);
      float d2 = dx * dx + du * du;
      float g = (exp(-d2 / 0.0006) + 0.35 * exp(-d2 / 0.006)) * tw;
      m += g;
      mc += filmHue(roll + h.z * 0.3 + t * 0.05) * g;
    }
    // fade into each bloom's core at the ends
    float ends = smoothstep(0.0, 0.08, v_t) * smoothstep(1.0, 0.92, v_t);
    vec3 film = filmHue(roll);
    c = (film * haze * 0.25 + rays * 0.9 + mix(mc, vec3(m), 0.35) * 2.5) * (0.12 + 0.88 * lit);
    float a = clamp(haze * 0.18 + ray_a * 0.45 + m, 0.0, 1.0);
    o = vec4(applyFog(c, v_pos), a * ends * (0.3 + 0.7 * lit));
    return;
  }
  if (part == 9) {
    // a halo band: still light lying on the ground along an edge of the
    // halo's square, from a corner (v_t 0) to the edge's middle. A soft
    // haze across its width (v_u -1..1) around a fine core, a little
    // brighter at the corner; its hue a film that turns with the angle it
    // is seen from and runs along it. Nothing in it moves with time; its
    // brightness (v_glow) dims where a corner has lost its bloom.
    float reach = max(v_fade, 1e-3);
    float u = v_u;
    float along = v_t * reach; // share of the half edge from its corner
    float ndv = abs(dot(raw, V));
    float haze = exp(-u * u * 2.5) * (1.0 - u * u);
    float core = exp(-u * u * 18.0);
    float corner = 1.0 + 0.35 * exp(-along * 18.0);
    vec3 film = mix(filmHue(0.55 + 0.6 * (1.0 - ndv) + along * 0.4 + u * 0.06), vec3(1.0), 0.35);
    float b = v_glow;
    c = film * (haze * 0.45 + core * 0.75) * b * corner;
    float a = clamp(haze * 0.45 + core * 0.5, 0.0, 1.0) * mix(0.5, 1.0, b);
    // its growing end softens; grown, it meets its neighbour at the middle
    a *= mix(1.0, smoothstep(1.0, 0.75, v_t), clamp((1.0 - reach) * 8.0, 0.0, 1.0));
    // it starts just behind its corner, fading into the band crossing it
    a *= smoothstep(0.0, 0.03, along);
    o = vec4(applyFog(c, v_pos), a);
    return;
  }
  if (part == 10) {
    // a cut crystal with no light of its own: each flat facet shades as
    // stone does and reflects a warm iridescent film that shifts with the
    // angle it is seen at and from facet to facet; the sun glints off it
    float ndv = clamp(dot(n, V), 0.0, 1.0);
    float fres = pow(1.0 - ndv, 3.0);
    vec3 facet = hash33(floor(n * 7.0) + 3.0);
    vec3 film = mix(filmHue(0.08 + 0.9 * ndv + facet.x * 0.35), vec3(1.0, 0.82, 0.6), 0.35);
    float day = pc.sun.w;
    vec3 lit = mix(vec3(0.35, 0.45, 0.8) * 0.3, vec3(1.0, 0.96, 0.9), day);
    c = shade(v_col * 0.55, n, v_pos);
    c += film * lit * (0.18 + 0.55 * fres + 0.25 * facet.y * max(dot(n, SUN), 0.0));
    vec3 H = normalize(SUN + V);
    c += lit * pow(max(dot(n, H), 0.0), 120.0) * 1.6 * step(0.0, dot(n, SUN));
    c += film * fres * mix(0.25, 0.08, day);
    o = vec4(applyFog(c, v_pos), 1.0);
    return;
  }
  if (part == 7) {
    // a soft shadow on the ground: darkest at its centre, gone at its rim
    float r = clamp(v_t, 0.0, 1.0);
    float a = v_fade * pow(1.0 - r, 1.6);
    o = vec4(applyFog(vec3(0.015, 0.015, 0.025), v_pos), a);
    return;
  }
  if (part == 6) {
    // solidified sap, thick as resin: dense and dark where it meets the body
    // (v_u 0), thinning toward its surface (v_u 1). No light of its own:
    // what glows is light passing through it, so it dims with the day.
    if (dot(raw, V) < 0.0) discard;
    float h = clamp(v_u, 0.0, 1.0);
    float ndv = clamp(dot(raw, V), 0.0, 1.0);
    float fres = pow(1.0 - ndv, 2.0);
    float day = pc.sun.w;
    vec3 sap = SAP * hue;
    vec3 deep = SAP_DEEP * hue * mix(0.55, 1.6, h);
    // light carried through the mass: wrapped, so the shadow side still
    // shows a warm core, thicker resin swallowing more of it
    float wrap = clamp(dot(raw, SUN) * 0.5 + 0.5, 0.0, 1.0);
    float through = max(dot(-raw, SUN), 0.0);
    vec3 lit = mix(vec3(0.35, 0.45, 0.8) * 0.25, vec3(1.0), day);
    c = shade(deep, raw, v_pos);
    c += sap * lit * wrap * mix(0.06, 0.32, h);
    c += sap * lit * through * 0.25 * h;
    // the polished face: amber at grazing angles and a tight highlight
    c += mix(deep, sap * 1.4, fres) * 0.3 * lit;
    vec3 H = normalize(SUN + V);
    c += lit * pow(max(dot(raw, H), 0.0), 90.0) * 0.55 * smoothstep(0.0, 0.2, dot(raw, SUN));
    // denser at the base: nearly opaque there, see-through only toward the face
    alpha = mix(v_fade, 1.0, max(fres, (1.0 - h) * 0.85));
    c = sapLife(c, sap, raw, V, h * (1.0 - fres), alpha);
    o = vec4(applyFog(c, v_pos), alpha);
    return;
  }
  if (part == 2 && v_fade < 0.999) {
    // translucent sap sac: dark and see-through at the centre, amber at
    // grazing angles. Only the near side is drawn (it is a closed sac).
    if (dot(raw, V) < 0.0) discard;
    float fres = pow(1.0 - clamp(dot(raw, V), 0.0, 1.0), 2.0);
    vec3 deep = SAP_DEEP * hue * (0.6 + 0.8 * v_glow);
    c = shade(deep, raw, v_pos) + mix(deep, SAP * hue * 2.2, fres) * (0.35 + v_glow);
    alpha = mix(v_fade, 1.0, fres);
    c = sapLife(c, SAP * hue, raw, V, 1.0 - fres, alpha);
  } else if (inner_ear && v_fade < 0.999) {
    // the inner ear is a sheet of sap: glowing at grazing angles, faintly
    // see-through face-on (the outer face stays solid vine)
    float fres = pow(1.0 - clamp(-dot(raw, V), 0.0, 1.0), 2.0);
    vec3 deep = SAP_DEEP * 1.6;
    c = shade(deep, -raw, v_pos) + mix(deep, SAP * 1.8, fres) * 0.5;
    c += SAP * max(dot(raw, SUN), 0.0) * 0.25; // light through the ear
    alpha = mix(v_fade, 1.0, fres);
    c = sapLife(c, SAP, -raw, V, 0.6 * (1.0 - fres), alpha);
  } else {
    vec3 albedo = v_col;
    float inner = 0.0;
    // the inner face of an ear (the side opposite its normal) is sap-lined
    if (part == 5) {
      inner = dot(raw, V) < 0.0 ? 1.0 : 0.0;
      albedo = mix(albedo, SAP * 0.6, inner * 0.8);
    }
    c = shade(albedo, n, v_pos);
    // leaves and sap are thin/translucent: back light shines through
    if (part == 1 || part == 2 || part == 5) c += albedo * max(dot(-n, SUN), 0.0) * 0.3;
    c += SAP * inner * 0.25;
    // woven strands: a Kajiya-Kay sheen across the tube's tangent so vines
    // read as directional fibres rather than flat facets
    float tl = length(tgrad);
    if (part == 0 && tl > 0.0) {
      float sheen = fibreSheen(tgrad, tl, n, normalize(SUN + V));
      float lit = smoothstep(0.0, 0.3, dot(n, SUN));
      vec3 light = mix(vec3(0.35, 0.45, 0.8) * 0.3, vec3(1.0, 0.95, 0.85), pc.sun.w);
      c += mix(albedo, light, 0.5) * sheen * lit * 0.28 * smoothstep(0.3, 1.5, tl);
    }
    c += v_col * v_glow * 2.2;
  }
  // rim light keeps the silhouette readable at night
  float rim = pow(1.0 - max(dot(n, V), 0.0), 3.0);
  c += v_col * rim * mix(0.35, 0.12, pc.sun.w);
  o = vec4(applyFog(c, v_pos), alpha);
}
