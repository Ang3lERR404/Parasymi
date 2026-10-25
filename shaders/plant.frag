#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
#include "surface.glsl"

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

// what the sap carries at night (moonlight; by day plain white)
const vec3 NIGHT_LIT = MOONLIGHT * 0.25;
// each lineage's sap: symbiote, parasite (pale, under its film), convergent
const vec3 SAP_SYMBIOTE = vec3(0.25, 0.95, 0.8);
const vec3 SAP_PARASITE = vec3(0.75, 0.8, 0.95);
const vec3 SAP_CONVERGENT = vec3(0.75, 0.55, 1.0);
// perceived brightness weights (the body's grey)
const vec3 LUMA = vec3(0.3, 0.59, 0.11);
// old growth densifies toward the wolf's root brown; wilting toward dead brown
const vec3 ROOT_BROWN = vec3(0.06, 0.055, 0.035);
const vec3 DEAD_BROWN = vec3(0.18, 0.12, 0.06);
// how tightly sap's colour gathers to its edge (1 - n.v)^this (part.frag
// alike): a narrow band; its light is the glisten's (sapGlisten)
const float SAP_EDGE_POW = 5.0;
// how much thin sap-filled growth glistens (under its skin, less than bare sap)
const float SKIN_GLISTEN = 0.6;
// the forms whose `.bloom` is bare sap of both lineages, not a petal
const uint FORMS_SAP_BLOOM = FORM_BIT(FORM_CONFLUENCE);
// a placement preview: green where it fits, red where it cannot be sown,
// breathing at this rate (rad/s)
const vec3 GHOST_FITS = vec3(0.55, 1.0, 0.7);
const vec3 GHOST_BLOCKED = vec3(1.0, 0.35, 0.3);
const float GHOST_PULSE = 4.0;

// the sap each lineage carries. Parasites are alien rather than hostile: a
// pale sap with a thin-film sheen whose hue turns with the view angle.
vec3 sapOf(float aff, float ndv, float seed) {
  if (aff > 0.5) return SAP_SYMBIOTE;
  if (aff < -0.5) return mix(SAP_PARASITE, filmHue(ndv * 1.3 + seed), 0.55);
  return SAP_CONVERGENT;
}

void surface() {
  vec3 tgrad = surfaceTangent(v_pos, v_t); // up the stem, along a tendril; derivatives first, in uniform control flow
  vec3 n = normalize(v_nrm);
  if (!gl_FrontFacing) n = -n;
  vec3 V = normalize(pc.eye_time.xyz - v_pos);
  float aff = v_inst.x, seed = v_inst.y, health = v_inst.z;
  int part = int(v_inst.w + 0.5);
  float day = DAYLIGHT;
  float ndv = clamp(dot(n, V), 0.0, 1.0);
  float fres = pow(1.0 - ndv, FRESNEL_POW);
  vec3 lit = byDay(NIGHT_LIT, vec3(1.0));
  float fill = v_sap.x, moving = v_sap.y;
  // how much of the key light reaches here (what stands between it and the
  // sun or moon shades it), and that light: what it carries through thin
  // tissue, its sheen and its glints all fall in shadow with it
  float sh = keyShadow(v_pos, n);
  vec3 klit = lit * sh;

  if (isForm(v_form, FORM_RADIANT)) {
    // a celestial bloom: the only thing in the garden that truly glows, and
    // the glow is light carried inside thin living tissue, not a flat
    // emission: brightest where the tissue is thinnest (its edges, at
    // grazing angles) and in its core, pulsing out from the heart, with sap
    // bubbles rising through it. Fragments fade in as they lock into place.
    // Its tissue is iridescent: a pearl whose thin film turns its hue with
    // the view angle, drifting slowly along each petal; the core and its
    // threads stay near white, with only a breath of the film.
    float core = part == PART_BLOOM ? 1.3 : 1.1;
    vec3 film = filmHue(ndv * 1.4 + v_t * 0.8 + seed * 3.0 + pc.eye_time.w * 0.03);
    vec3 col = mix(v_col, film, part == PART_BLOOM ? 0.25 : 0.4 + 0.35 * fres);
    vec3 c = shadeLit(col * 0.2, n, v_pos, sh);
    c += col * (0.35 + 0.9 * fres) * (0.7 + 0.5 * v_sap.y) * core * 1.4;
    c += col * max(dot(-n, SUN), 0.0) * 0.4;
    c += mix(col, vec3(1.0), 0.4) * sapBubbles(v_obj, V, pc.eye_time.w) * 0.5;
    // petals are thin: see-through face-on, their edges bright
    float a = (part == PART_LEAF ? mix(0.3, 0.9, fres) : mix(0.5, 0.95, fres)) * v_young;
    if (v_ghost.x > 0.5) a *= 0.5;
    o = vec4(applyFog(c, v_pos), a);
    return;
  }
  if (formIn(FORMS_SAP_BLOOM, v_form) && part == PART_BLOOM) {
    // the lineages' sap mixed (convergence_kit `sac`): see-through face-on,
    // warming to amber at grazing angles. Hue follows the vertex colour, so
    // its two saps swirl in it.
    vec3 deep = v_col * 0.18 * health;
    vec3 c = shadeLit(deep, n, v_pos, sh) + mix(v_col * 0.8, mix(v_col, AMBER, 0.2) * 2.0, pow(1.0 - ndv, SAP_EDGE_POW)) * (0.3 + fill * 0.3) * lit;
    c += mix(v_col, AMBER, 0.3) * max(dot(-n, SUN), 0.0) * 0.25 * klit;
    c += mix(v_col, AMBER, 0.3) * pointLight(v_pos, n, 1.0) * 0.5;
    vec3 g = sapGlisten(n, V, v_pos, v_obj, mix(v_col, AMBER, 0.3), 1.0 - fres, sh) * health;
    float a = max(mix(0.5, 1.0, fres), clamp(dot(g, vec3(0.33)), 0.0, 1.0));
    o = vec4(applyFog(c + g, v_pos), a);
    return;
  }

  if (isLantern(v_form, part, v_t)) {
    // a floater's lantern (meshgen `lantern`, tu.x 0.5): clear sap, the
    // spore inside showing through face-on and its rim bright; its comb
    // rows carry light split into colours (their vertex colour), the hue
    // turning with the view angle, and bubbles rise inside it
    vec3 film = filmHue(ndv * 1.3 + seed * 3.0 + pc.eye_time.w * 0.05);
    vec3 col = mix(v_col, v_col * film * 1.8, 0.3 + 0.4 * fres);
    vec3 c = shadeLit(col * 0.25, n, v_pos, sh) * health;
    c += col * (0.2 + 0.85 * fres) * lit;
    c += col * max(dot(-n, SUN), 0.0) * 0.3 * klit;
    c += col * pointLight(v_pos, n, 1.0) * 0.6;
    c += mix(col, vec3(1.0), 0.4) * sapBubbles(v_obj, V, pc.eye_time.w) * lit * 0.5;
    vec3 g = sapGlisten(n, V, v_pos, v_obj, col, 1.0 - fres, sh) * health;
    c += g;
    float a = max(mix(0.18, 0.85, fres), clamp(dot(g, vec3(0.33)), 0.0, 1.0));
    if (v_ghost.x > 0.5) a *= 0.5;
    o = vec4(applyFog(c, v_pos), a);
    return;
  }

  // thickness: old growth is dense, new growth thin; leaves and petals are
  // always thin. A wilting plant's skin dulls toward dead brown.
  float thin = clamp(v_young, 0.0, 1.0);
  // the body is the wolf's family: a muted skin, its colour carried mostly
  // by the sap showing through; old growth near the ground densifies
  // toward the wolf's root brown
  float lum = dot(v_col, LUMA);
  vec3 body = mix(vec3(lum), v_col, 0.5) * 0.78;
  body = mix(body, ROOT_BROWN, (1.0 - thin) * (1.0 - smoothstep(0.0, 0.55, v_t)) * 0.75);
  body = mix(DEAD_BROWN, body, health);
  vec3 c = shadeLit(body, n, v_pos, sh);

  // fibres: a Kajiya-Kay sheen across the stem's length, as on the wolf's vines
  float tl = length(tgrad);
  if (tl > 0.0 && !PART_IN(SHEETS, part)) c += fibreLight(body, lit, tgrad, tl, n, V, 0.22, sh);

  // sap, seen through the skin: light from behind and at grazing angles,
  // more where the growth is thin and the plant is full
  vec3 sap = mix(sapOf(aff, ndv, seed), v_col, 0.25);
  sap = mix(sap, vec3(1.0, 0.85, 1.0), VEIL * 0.5);
  float through = max(dot(-n, SUN), 0.0) * sh;
  float wrap = clamp(dot(n, SUN) * 0.5 + 0.5, 0.0, 1.0) * mix(0.4, 1.0, sh);
  float show = mix(0.1, 1.0, thin) * (0.35 + 0.65 * fill);
  // light scattered inside thin tissue tints it with its sap; light from
  // behind and at grazing angles shows the sap most (a bloom's or a mote's
  // light too, wrapping round the tissue it falls on)
  c += sap * lit * (through * 0.8 + fres * 0.45 + wrap * 0.22) * show * health;
  c += sap * pointLight(v_pos, n, 1.0) * 0.6 * show * health;
  // sap moving through the plant (sharing, draining) brightens it as it passes
  c += sap * lit * moving * 0.3 * show;
  // sap is alive: bubbles drifting up inside thin growth, beads of it
  // sliding down the skin of a full plant
  c += mix(sap, vec3(1.0), 0.3) * sapBubbles(v_obj, V, pc.eye_time.w) * show * lit * 0.4;
  vec2 drop = sapDroplets(v_obj * 0.8, n, SUN, V, pc.eye_time.w) * (0.25 + 0.75 * fill) * health;
  c = mix(c, c * 0.85 + sap * 0.3 * lit, drop.x * 0.6) + keyLight() * drop.y * sh * 0.8;
  // thin sap-filled growth is wet: it glistens, as bare sap does, a little
  // less under its skin
  c += sapGlisten(n, V, v_pos, v_obj, sap, thin * show, sh) * thin * (0.35 + 0.65 * fill) * health * SKIN_GLISTEN;


  // rim light keeps the silhouette readable at night (as on the wolf)
  float rim = pow(1.0 - ndv, RIM_POW);
  c += v_col * rim * mix(0.3, 0.1, day);

  // petals are thin enough to see through face-on
  float alpha = part == PART_BLOOM ? mix(0.72, 1.0, fres) : 1.0;
  // a placement preview: the grown plant as a pale, breathing outline,
  // green where it fits, red where it cannot be sown
  if (v_ghost.x > 0.5) {
    vec3 tint = v_ghost.y > 0.5 ? GHOST_FITS : GHOST_BLOCKED;
    float pulse = 0.5 + 0.5 * sin(pc.eye_time.w * GHOST_PULSE);
    c = mix(c, tint * (0.5 + 0.4 * day), 0.6) + tint * fres * 0.5;
    alpha = mix(0.3, 0.6, fres) * (0.8 + 0.2 * pulse);
  }
  o = vec4(applyFog(c, v_pos), alpha);
}

void main() {
  surface();
  keepPass(o.a);
}
