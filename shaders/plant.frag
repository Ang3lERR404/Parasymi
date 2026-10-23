#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

// Plants share the wolf's material vocabulary (part.frag): a woven body with
// a sheen along its fibres, and sap inside it that is dense and dark where
// the growth is old and thick, thin and see-through where it is new. Sap has
// no light of its own: it shows only by light carried through it (behind,
// at grazing angles, through thin new growth), so plants dim with the day
// and keep only a rim at night, as the wolf does.

layout(location = 0) in vec3 v_pos;
layout(location = 1) in vec3 v_nrm;
layout(location = 2) in vec3 v_col;
layout(location = 3) in vec2 v_sap;   // mana fill, sap moving through
layout(location = 4) flat in vec4 v_inst;
layout(location = 5) flat in float v_form;
layout(location = 6) in float v_t;
layout(location = 7) in float v_young;
layout(location = 8) flat in vec2 v_ghost; // a placement preview, and whether it fits
layout(location = 9) in vec3 v_obj;
layout(location = 0) out vec4 o;

const vec3 AMBER = vec3(1.0, 0.43, 0.08);

// direction of increasing `v_t` across the surface: up the stem, along a
// tendril. Zero where `v_t` is constant (a petal fan).
vec3 surfaceTangent() {
  vec3 dpx = dFdx(v_pos);
  vec3 dpy = dFdy(v_pos);
  vec3 sn = cross(dpx, dpy);
  vec3 r1 = cross(dpy, sn);
  vec3 r2 = cross(sn, dpx);
  float det = dot(dpx, r1);
  return abs(det) < 1e-12 ? vec3(0.0) : (r1 * dFdx(v_t) + r2 * dFdy(v_t)) / det;
}

// the sap each lineage carries. Parasites are alien rather than hostile: a
// pale sap with a thin-film sheen whose hue turns with the view angle.
vec3 sapOf(float aff, float ndv, float seed) {
  if (aff > 0.5) return vec3(0.25, 0.95, 0.8);
  if (aff < -0.5) return mix(vec3(0.75, 0.8, 0.95), 0.5 + 0.5 * cos(6.2832 * (vec3(0.0, 0.33, 0.67) + ndv * 1.3 + seed)), 0.55);
  return vec3(0.75, 0.55, 1.0);
}

void main() {
  vec3 tgrad = surfaceTangent(); // derivatives first, in uniform control flow
  vec3 n = normalize(v_nrm);
  if (!gl_FrontFacing) n = -n;
  vec3 V = normalize(pc.eye_time.xyz - v_pos);
  float aff = v_inst.x, seed = v_inst.y, health = v_inst.z;
  int part = int(v_inst.w + 0.5);
  float day = pc.sun.w;
  float ndv = clamp(dot(n, V), 0.0, 1.0);
  float fres = pow(1.0 - ndv, 2.0);
  vec3 lit = mix(vec3(0.35, 0.45, 0.8) * 0.25, vec3(1.0), day);
  float fill = v_sap.x, moving = v_sap.y;

  if (abs(v_form - 4.0) < 0.5) {
    // a celestial bloom: the only thing in the garden that truly glows, and
    // the glow is light carried inside thin living tissue, not a flat
    // emission: brightest where the tissue is thinnest (its edges, at
    // grazing angles) and in its core, pulsing out from the heart, with sap
    // bubbles rising through it. Fragments fade in as they lock into place.
    float core = part == 2 ? 1.0 : 0.65;
    vec3 c = shade(v_col * 0.2, n, v_pos);
    c += v_col * (0.35 + 0.9 * fres) * (0.7 + 0.5 * v_sap.y) * core * 1.4;
    c += v_col * max(dot(-n, SUN), 0.0) * 0.4;
    c += mix(v_col, vec3(1.0), 0.4) * sapBubbles(v_obj, V, pc.eye_time.w) * 0.5;
    float a = mix(0.5, 0.95, fres) * v_young;
    if (v_ghost.x > 0.5) a *= 0.5;
    o = vec4(applyFog(c, v_pos), a);
    return;
  }
  if (abs(v_form - 3.0) < 0.5 && part == 2) {
    // a confluence's sap petal: see-through violet face-on, amber at grazing
    // angles. Hue follows the vertex colour.
    vec3 deep = v_col * 0.18 * health;
    vec3 c = shade(deep, n, v_pos) + mix(v_col * 0.8, mix(v_col, AMBER, 0.45) * 2.0, fres) * (0.3 + fill * 0.3) * lit;
    c += mix(v_col, AMBER, 0.3) * max(dot(-n, SUN), 0.0) * 0.25 * lit;
    o = vec4(applyFog(c, v_pos), mix(0.5, 1.0, fres));
    return;
  }

  // thickness: old growth is dense, new growth thin; leaves and petals are
  // always thin. A wilting plant's skin dulls toward dead brown.
  float thin = clamp(v_young, 0.0, 1.0);
  // the body is the wolf's family: a muted skin, its colour carried mostly
  // by the sap showing through; old growth near the ground densifies
  // toward the wolf's root brown
  float lum = dot(v_col, vec3(0.3, 0.59, 0.11));
  vec3 body = mix(vec3(lum), v_col, 0.5) * 0.78;
  body = mix(body, vec3(0.06, 0.055, 0.035), (1.0 - thin) * (1.0 - smoothstep(0.0, 0.55, v_t)) * 0.75);
  body = mix(vec3(0.18, 0.12, 0.06), body, health);
  vec3 c = shade(body, n, v_pos);

  // fibres: a Kajiya-Kay sheen across the stem's length, as on the wolf's vines
  float tl = length(tgrad);
  if (tl > 0.0 && part != 1 && part != 2) {
    vec3 T = tgrad / tl;
    T = normalize(T - n * dot(T, n) + 1e-6);
    vec3 H = normalize(SUN + V);
    float th = dot(T, H);
    float sheen = pow(sqrt(max(1.0 - th * th, 0.0)), 40.0);
    c += mix(body, lit, 0.5) * sheen * smoothstep(0.0, 0.3, dot(n, SUN)) * 0.22 * smoothstep(0.3, 1.5, tl);
  }

  // sap, seen through the skin: light from behind and at grazing angles,
  // more where the growth is thin and the plant is full
  vec3 sap = mix(sapOf(aff, ndv, seed), v_col, 0.25);
  sap = mix(sap, vec3(1.0, 0.85, 1.0), pc.misc.x * 0.5);
  float through = max(dot(-n, SUN), 0.0);
  float wrap = clamp(dot(n, SUN) * 0.5 + 0.5, 0.0, 1.0);
  float show = mix(0.1, 1.0, thin) * (0.35 + 0.65 * fill);
  // light scattered inside thin tissue tints it with its sap; light from
  // behind and at grazing angles shows the sap most
  c += sap * lit * (through * 0.8 + fres * 0.45 + wrap * 0.22) * show * health;
  // sap moving through the plant (sharing, draining) brightens it as it passes
  c += sap * lit * moving * 0.3 * show;
  // sap is alive: bubbles drifting up inside thin growth, beads of it
  // sliding down the skin of a full plant
  c += mix(sap, vec3(1.0), 0.3) * sapBubbles(v_obj, V, pc.eye_time.w) * show * lit * 0.4;
  vec2 drop = sapDroplets(v_obj * 0.8, n, SUN, V, pc.eye_time.w) * (0.25 + 0.75 * fill) * health;
  c = mix(c, c * 0.85 + sap * 0.3 * lit, drop.x * 0.6) + lit * drop.y * 0.7;
  // thin sap-filled growth has a polished face
  vec3 Hs = normalize(SUN + V);
  c += lit * pow(max(dot(n, Hs), 0.0), 60.0) * 0.25 * thin * smoothstep(0.0, 0.2, dot(n, SUN));

  // rim light keeps the silhouette readable at night (as on the wolf)
  float rim = pow(1.0 - ndv, 3.0);
  c += v_col * rim * mix(0.3, 0.1, day);

  // petals are thin enough to see through face-on
  float alpha = part == 2 ? mix(0.72, 1.0, fres) : 1.0;
  // a placement preview: the grown plant as a pale, breathing outline,
  // green where it fits, red where it cannot be sown
  if (v_ghost.x > 0.5) {
    vec3 tint = v_ghost.y > 0.5 ? vec3(0.55, 1.0, 0.7) : vec3(1.0, 0.35, 0.3);
    float pulse = 0.5 + 0.5 * sin(pc.eye_time.w * 4.0);
    c = mix(c, tint * (0.5 + 0.4 * day), 0.6) + tint * fres * 0.5;
    alpha = mix(0.3, 0.6, fres) * (0.8 + 0.2 * pulse);
  }
  o = vec4(applyFog(c, v_pos), alpha);
}
