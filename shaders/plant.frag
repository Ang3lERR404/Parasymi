#version 450
//! plant material: woven body, sap through young tissue, see-through petals, the radiant film, lanterns.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
#include "surface.glsl"

// Plants share the wolf's material vocabulary (part.frag): a woven body with
// a sheen along its fibres, and sap inside it that is dense and dark where
// the growth is old and thick, thin and see-through where it is new. Sap has
// no light of its own: it shows only by light carried through it (behind,
// at grazing angles, through thin new growth), so plants dim with the day
// and keep only a rim at night, as the wolf does. Only their yield holds a
// light of its own: ripening, a plant's sap takes on what it yields, and
// its ripe pods glow softly from within.

layout(location = 0) centroid in vec3 v_pos;
layout(location = 1) centroid in vec3 v_nrm;
layout(location = 2) in vec3 v_col;
layout(location = 3) in vec2 v_sap;   // mana fill, sap moving through
layout(location = 4) flat in vec4 v_inst;
layout(location = 5) flat in float v_form;
layout(location = 6) in float v_t;
layout(location = 7) in float v_young;
layout(location = 8) flat in vec2 v_ghost; // a placement preview, and whether it fits
layout(location = 9) in vec3 v_obj;
layout(location = 10) in float v_glow; // the light a radiant fragment carries
layout(location = 11) in vec2 v_pod;   // a pod: how far swelled (< 0 not one), how freshly its yield was taken
layout(location = 13) flat in float v_glitch; // how far the unforming has shattered it 0..1 (< 0 none)
layout(location = 12) flat in vec4 v_yield; // the colour of what it yields (linear), how ripe 0..1
layout(location = 14) in vec2 v_sheet;      // a leaf or petal: along it 0..1, across it 1..3 (0: not a sheet)
layout(location = 15) in vec3 v_rest;       // the point in its mesh as built (what the unforming cuts it along)
layout(location = 16) flat in vec4 v_cell;  // the shard or flake this triangle is (xyz), how far it has withered (w)
layout(location = 17) in vec3 v_cellS;      // the same, interpolated: it differs from v_cell where the triangle crosses two shards
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
// how much of a symbiote leaf's own green light through it carries (its
// structures' leaves: part.frag's back light)
const float GREEN_THROUGH = 0.45;
// the forms whose `.bloom` is bare sap of both lineages, not a petal
const uint FORMS_SAP_BLOOM = FORM_BIT(FORM_CONFLUENCE);
// radiant forms that keep more of their own colour under the iridescent
// film (OWN_HUE_FILM of it): the vesper's dusk violet and evening gold
const uint FORMS_OWN_HUE = FORM_BIT(FORM_STAR);
const float OWN_HUE_FILM = 0.45;
// a radiant plant's cut crystal (part `.prism`): its fire's hue turns
// across its facets (CRYSTAL_FIRE, per unit of normal); the key light
// mirrored in a facet is a hard spot (CRYSTAL_SPOT, 1 - cos of its
// radius) CRYSTAL_SPOT_GAIN bright; facets wink (in cells of
// CRYSTAL_WINK_CELLS a metre, at CRYSTAL_WINK_RATE rad/s, sharpened by
// CRYSTAL_WINK_SHARP) CRYSTAL_WINK_GAIN bright
const vec3 CRYSTAL_FIRE = vec3(1.7, 2.3, 1.1);
const float CRYSTAL_SPOT = 0.02;
const float CRYSTAL_SPOT_GAIN = 3.0;
const float CRYSTAL_WINK_CELLS = 14.0;
const float CRYSTAL_WINK_RATE = 2.6;
const float CRYSTAL_WINK_SHARP = 24.0;
const float CRYSTAL_WINK_GAIN = 1.4;
// a halcyra's veil (radiant_kit.Ring `veil`; must match): how clear it is
// face-on, a bell of glass
const float RING_VEIL = 11.0;
const float VEIL_CLEAR = 0.12;
// a placement preview: green where it fits, red where it cannot be sown,
// breathing at this rate (rad/s)
const vec3 GHOST_FITS = vec3(0.55, 1.0, 0.7);
const vec3 GHOST_BLOCKED = vec3(1.0, 0.35, 0.3);
const float GHOST_PULSE = 4.0;
// ripening: how far a plant's sap takes on its yield's colour, and how
// much more of it shows, when it is ripe
const float RIPE_TINT = 0.4;
const float RIPE_SHOW = 0.6;
// a ripe pod's own light, how slowly it breathes (rad/s), and how bright
// the sap a just-plucked nub weeps
const float POD_GLOW = 0.12;
const float POD_BREATH_RATE = 1.6;
const float POD_WOUND = 0.35;

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

  float ripe = v_yield.a;
  vec3 yieldCol = v_yield.rgb;
#ifndef HEAD
  // (built with HEAD, for each mesh's always-solid triangles alone, the
  // materials below are left out: those triangles never take them, and the
  // shader is lighter without them)
  if (part == PART_POD && !formIn(FORMS_FREE, v_form)) {
    // a pod (meshgen `pods`): its yield ripening as a bead of sap in its
    // colour. Empty it is a pale nub of the lineage's own sap, dense and
    // dull; swelling it clears and takes on the yield's colour; ripe it
    // holds a soft light of its own, slowly breathing, brightest face-on.
    // Just plucked, the nub left weeps bright sap that dries as it heals.
    float sw = clamp(v_pod.x, 0.0, 1.0), wound = v_pod.y;
    vec3 col = mix(sapOf(aff, ndv, seed) * 0.45, yieldCol, smoothstep(0.0, 0.6, sw));
    vec3 deep = col * mix(0.3, 0.12, sw) * health;
    PointLit pl = pointLights(v_pos, n, reflect(-V, n), true);
    vec3 c = shadeLitWith(deep, n, sh, pl.plain);
    c += mix(col * 0.04, col * 0.55, pow(1.0 - ndv, 2.5)) * (0.3 + 0.5 * sw) * lit;
    c += col * max(dot(-n, SUN), 0.0) * 0.15 * sw * klit;
    c += col * pl.wrapped * 0.3;
    c += mix(col, vec3(1.0), 0.4) * sapBubbles(v_obj, V, pc.eye_time.w) * sw * lit * 0.3;
    float glow = sw * sw * (0.8 + 0.2 * sin(pc.eye_time.w * POD_BREATH_RATE + seed * 9.0));
    c += yieldCol * glow * POD_GLOW * ndv * ndv * health;
    c += mix(col, vec3(1.0), 0.3) * wound * POD_WOUND * lit;
    vec3 g = sapGlistenWith(n, V, v_pos, v_obj, col, 0.2 * sw * (1.0 - fres), sh, pl.mirrored) * health * mix(0.3, 1.0, max(sw, wound));
    float a = max(mix(mix(0.97, 0.6, sw), 1.0, fres), clamp(dot(g, vec3(0.33)), 0.0, 1.0));
    if (v_ghost.x > 0.5) a *= 0.5;
    o = vec4(applyFog(c + g, v_pos), a);
    return;
  }
  if (formIn(FORMS_FREE, v_form)) {
    // a radiant plant (the celestial bloom, the vesper): the only things in
    // the garden that truly glow, and
    // the glow is light carried inside thin living tissue, not a flat
    // emission: brightest where the tissue is thinnest (its edges, at
    // grazing angles) and in its core, pulsing out from the heart, with sap
    // bubbles rising through it. Fragments fade in as they lock into place.
    // Its tissue is iridescent: a pearl whose thin film turns its hue with
    // the view angle, drifting slowly along each petal; the core and its
    // threads stay near white, with only a breath of the film. What carries
    // less light (v_glow: a vesper's living leaves) keeps more of its own
    // colour and body; withering out of radiance, the light goes out of it.
    float core = part == PART_BLOOM ? 1.3 : 1.1;
    float glow = v_glow * mix(0.25, 1.0, health) * (1.0 + 0.3 * ripe);
    vec3 film = filmHue(ndv * 1.4 + v_t * 0.8 + seed * 3.0 + pc.eye_time.w * 0.03);
    float filmy = (formIn(FORMS_OWN_HUE, v_form) ? OWN_HUE_FILM : 1.0) * mix(0.3, 1.0, v_glow);
    // a bead of its yield: a dim seed of light empty, the yield's colour
    // and fully lit ripe; just plucked, a flash where it was
    vec3 own = v_col;
    if (part == PART_POD) {
      own = mix(v_col * 0.35, yieldCol, v_pod.x);
      glow *= mix(0.2, 1.3, v_pod.x) + v_pod.y;
    }
    vec3 col = mix(own, film, (part == PART_BLOOM ? 0.25 : 0.4 + 0.35 * fres) * filmy * (part == PART_POD ? 0.4 : 1.0));
    vec3 c = shadeLit(col * mix(0.6, 0.2, v_glow), n, v_pos, sh);
    c += col * (0.35 + 0.9 * fres) * (0.7 + 0.5 * v_sap.y) * core * 1.4 * glow;
    c += col * max(dot(-n, SUN), 0.0) * 0.4;
    c += mix(col, vec3(1.0), 0.4) * sapBubbles(v_obj, V, pc.eye_time.w) * 0.5 * glow;
    // its cut crystal (a solcyriphon's lens, a heliocyra's heart, a
    // halcyra's crystal petals): clear, each flat facet flashing the key
    // light and every point of light near it as a hard spot split into
    // fire, and winking as it turns, scattering the light off as sparkles
    if (part == PART_PRISM) {
      vec3 R = reflect(-V, n);
      PointLit pl = pointLights(v_pos, n, R, true);
      vec3 fire = spectral(fract(dot(n, CRYSTAL_FIRE) + pc.eye_time.w * 0.05 + seed));
      vec3 flash = keyLight() * hardSpot(R, SUN, CRYSTAL_SPOT) * CRYSTAL_SPOT_GAIN * sh + pl.mirrored;
      c += flash * mix(vec3(1.0), fire, 0.6);
      float wink = pow(0.5 + 0.5 * sin(pc.eye_time.w * CRYSTAL_WINK_RATE + dot(floor(v_obj * CRYSTAL_WINK_CELLS), vec3(12.9, 78.2, 37.7))), CRYSTAL_WINK_SHARP);
      c += mix(vec3(1.0), fire, 0.7) * wink * CRYSTAL_WINK_GAIN * glow;
    }
    // petals are thin: see-through face-on, their edges bright (living
    // leaves denser; a veil sheerer still, a bell of glass; a crystal clear
    // but for its flashes)
    float ring = floor(v_sheet.x + 0.01);
    float a = (part == PART_LEAF ? mix(mix(0.85, 0.3, v_glow), 0.9, fres) : mix(0.5, 0.95, fres)) * v_young;
    if (abs(ring - RING_VEIL) < 0.5) a = mix(VEIL_CLEAR, 0.8, fres) * v_young;
    if (part == PART_PRISM) a = clamp(mix(0.45, 0.9, fres) + dot(c, vec3(0.1)), 0.0, 1.0) * v_young;
    if (v_ghost.x > 0.5) a *= 0.5;
    o = vec4(applyFog(c, v_pos), a);
    return;
  }
  if (formIn(FORMS_SAP_BLOOM, v_form) && part == PART_BLOOM) {
    // the lineages' sap mixed (convergence_kit `sac`): see-through face-on,
    // warming to amber at grazing angles. Hue follows the vertex colour, so
    // its two saps swirl in it.
    vec3 deep = v_col * 0.18 * health;
    PointLit pl = pointLights(v_pos, n, reflect(-V, n), true);
    vec3 c = shadeLitWith(deep, n, sh, pl.plain) + mix(v_col * 0.8, mix(v_col, AMBER, 0.2) * 2.0, pow(1.0 - ndv, SAP_EDGE_POW)) * (0.3 + fill * 0.3) * lit;
    c += mix(v_col, AMBER, 0.3) * max(dot(-n, SUN), 0.0) * 0.25 * klit;
    c += mix(v_col, AMBER, 0.3) * pl.wrapped * 0.5;
    vec3 g = sapGlistenWith(n, V, v_pos, v_obj, mix(v_col, AMBER, 0.3), 1.0 - fres, sh, pl.mirrored) * health;
    float a = max(mix(0.5, 1.0, fres), clamp(dot(g, vec3(0.33)), 0.0, 1.0));
    o = vec4(applyFog(c + g, v_pos), a);
    return;
  }

  if (part == PART_RESIN) {
    // a symbiote's bead of resin sap (structure_kit `plant`): the
    // structures' resin (surface.glsl), v_young its dense base .. thin crown,
    // the plant's health dimming it; only its outer face is drawn
    if (dot(normalize(v_nrm), V) < 0.0) discard;
    vec3 hue = clamp(v_col / SAP_SRGB_LIN, 0.0, 1.5) * mix(0.4, 1.0, health);
    o = resinSurface(normalize(v_nrm), V, v_pos, v_obj, hue, clamp(v_young, 0.0, 1.0), 0.35, sh);
    if (v_ghost.x > 0.5) o.a *= 0.5;
    return;
  }

  if (isLantern(v_form, part, v_t)) {
    // a floater's lantern (meshgen `lantern`, tu.x 0.5): clear sap, the
    // spore inside showing through face-on and its rim bright; its comb
    // rows carry light split into colours (their vertex colour), the hue
    // turning with the view angle, and bubbles rise inside it
    vec3 film = filmHue(ndv * 1.3 + seed * 3.0 + pc.eye_time.w * 0.05);
    vec3 col = mix(v_col, v_col * film * 1.8, 0.3 + 0.4 * fres);
    PointLit pl = pointLights(v_pos, n, reflect(-V, n), true);
    vec3 c = shadeLitWith(col * 0.25, n, sh, pl.plain) * health;
    c += col * (0.2 + 0.85 * fres) * lit;
    c += col * max(dot(-n, SUN), 0.0) * 0.3 * klit;
    c += col * pl.wrapped * 0.6;
    c += mix(col, vec3(1.0), 0.4) * sapBubbles(v_obj, V, pc.eye_time.w) * lit * 0.5;
    vec3 g = sapGlistenWith(n, V, v_pos, v_obj, col, 1.0 - fres, sh, pl.mirrored) * health;
    c += g;
    float a = max(mix(0.18, 0.85, fres), clamp(dot(g, vec3(0.33)), 0.0, 1.0));
    if (v_ghost.x > 0.5) a *= 0.5;
    o = vec4(applyFog(c, v_pos), a);
    return;
  }

#endif
  // thickness: old growth is dense, new growth thin; leaves and petals are
  // always thin. A wilting plant's skin dulls toward dead brown.
  float thin = clamp(v_young, 0.0, 1.0);
  // the body is the wolf's family: a muted skin, its colour carried mostly
  // by the sap showing through; old growth near the ground densifies
  // toward the wolf's root brown
  float lum = dot(v_col, LUMA);
  vec3 body = mix(vec3(lum), v_col, 0.5) * 0.78;
  body = mix(body, ROOT_BROWN, (1.0 - thin) * (1.0 - smoothstep(0.0, 0.55, v_t)) * 0.75);
  // but a symbiote's leaves (and sepals) are the lineage's own green, as
  // on its structures (part.frag), and so are a low plant's (pads afloat
  // on the water, a creeper's moss): unmuted, the light through them theirs
  bool green = (aff > 0.5 || formIn(FORMS_LOW, v_form)) && part == PART_LEAF;
  if (green) body = v_col;
  // a leaf's or petal's own surface: veins, the net between, edge and base
  float trans;
  body = sheetColour(body, part, v_sheet, v_t, trans);
  body = mix(DEAD_BROWN, body, health);
  // symbiotes and parasites are matte living tissue, stems, vines, leaves
  // and petals alike: sap shows through them, but nothing wet or glossy sits
  // on them (no glisten, no beads, no glinting bubbles, no fibre sheen);
  // only a convergent plant's young growth stays wet
  bool matte = abs(aff) > 0.5 || PART_IN(SHEETS, part);
  // how strongly it glistens (below): only thin, living growth does, so the
  // points of light are mirrored only there
  float glisten = matte ? 0.0 : thin * (0.35 + 0.65 * fill) * health * SKIN_GLISTEN;
  PointLit pl = pointLights(v_pos, n, reflect(-V, n), glisten > 0.0);
  vec3 c = shadeLitWith(body, n, sh, pl.plain);

  // fibres: a Kajiya-Kay sheen across the stem's length, as on the wolf's vines
  float tl = length(tgrad);
  if (tl > 0.0 && !matte) c += fibreLight(body, lit, tgrad, tl, n, V, 0.22, sh);

  // sap, seen through the skin: light from behind and at grazing angles,
  // more where the growth is thin and the plant is full
  vec3 sap = mix(sapOf(aff, ndv, seed), v_col, 0.25);
  sap = mix(sap, vec3(1.0, 0.85, 1.0), VEIL * 0.5);
  if (green) sap = v_col * GREEN_THROUGH;
  // ripening, its sap takes on what it yields, and more of it shows (a
  // symbiote's leaves keep their own green)
  if (!green) sap = mix(sap, yieldCol, ripe * RIPE_TINT);
  float through = max(dot(-n, SUN), 0.0) * sh;
  float wrap = clamp(dot(n, SUN) * 0.5 + 0.5, 0.0, 1.0) * mix(0.4, 1.0, sh);
  float show = mix(0.1, 1.0, thin) * (0.35 + 0.65 * fill) * (1.0 + (green ? 0.0 : ripe * RIPE_SHOW));
  // light scattered inside thin tissue tints it with its sap; light from
  // behind and at grazing angles shows the sap most (a bloom's or a mote's
  // light too, wrapping round the tissue it falls on)
  c += sap * lit * (through * 0.8 * trans + fres * 0.45 + wrap * 0.22) * show * health;
  c += sap * pl.wrapped * 0.6 * show * health * trans;
  // sap moving through the plant (sharing, draining) brightens it as it passes
  c += sap * lit * moving * 0.3 * show;
  // sap is alive: bubbles drifting up inside thin growth, beads of it
  // sliding down the skin of a full plant
  if (!matte) {
    c += mix(sap, vec3(1.0), 0.3) * sapBubbles(v_obj, V, pc.eye_time.w) * show * lit * 0.4;
    vec2 drop = sapDroplets(v_obj * 0.8, n, SUN, V, pc.eye_time.w) * (0.25 + 0.75 * fill) * health;
    c = mix(c, c * 0.85 + sap * 0.3 * lit, drop.x * 0.6) + keyLight() * drop.y * sh * 0.8;
  }
  // thin sap-filled growth is wet: it glistens, as bare sap does, a little
  // less under its skin
  if (glisten > 0.0) c += sapGlistenWith(n, V, v_pos, v_obj, sap, thin * show, sh, pl.mirrored) * glisten;


  // a stem's ridges and fibres grain all its light
  c *= grainOf(part, v_sheet, v_t);
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

// whether this triangle's corners lie in more than one shard or flake (its
// own, interpolated, strays from its first corner's): pulled apart, it
// would smear across the gap, so it is cut away
bool split() { return dot(v_cellS - v_cell.xyz, v_cellS - v_cell.xyz) > 1e-6; }
// the unforming (plant.vert `unformAt`, the same constants): a radiant
// plant's light goes out of it as it glitches; the whole blinks out for a
// step now and then, and a slipping band splits faintly into its film's
// colours. Cracks of its own light run over it, cell after cell of the
// shatter, thin and bright; once it breaks each shard keeps only the
// triangles wholly its own (one across two is cut away), its edges lit and
// its body its own colour, dimming, never white.
const float GLITCH_RATE = 14.0;
const float SHARD_CELLS = 2.6;
const float BREAK = 0.55;
// the cracks' light, of the plant's own colour (times it)
const float CRACK_GLOW = 2.4;
void unform() {
  float g = v_glitch;
  if (g < 0.0) return;
  float seed = v_inst.y;
  float t = pc.eye_time.w;
  float step = floor(t * GLITCH_RATE + seed * 37.0);
  if (g < BREAK && hash33(vec3(step, seed * 53.0, 3.0)).x < 0.03 + 0.2 * g) discard;
  vec4 sc = shardCell(v_rest * SHARD_CELLS + seed * 17.0);
  float broke = smoothstep(BREAK, 1.0, g);
  if (broke > 0.0 && split()) discard;
  // its own colour: what it is, through its film
  vec3 own = mix(v_col, filmHue(seed * 3.0 + dot(sc.xyz, vec3(0.13, 0.07, 0.11))), 0.45);
  // the light going out of it
  o.rgb *= mix(1.0, 0.3, smoothstep(0.15, 0.9, g));
  // a slipping band splits into its film's colours for a step
  vec3 hs = hash33(vec3(floor(v_rest.y * 9.0), step, seed * 91.0));
  if (g < BREAK && hs.x < 0.1 + 0.55 * g) o.rgb = mix(o.rgb, filmHue(hs.y + seed) * 0.9, 0.35);
  // cracks reach each cell at its own moment, spreading over it
  vec3 hc = hash33(sc.xyz + seed * 7.0);
  float cracked = smoothstep(0.1 + 0.35 * hc.x, 0.2 + 0.35 * hc.x, g);
  float width = mix(0.035, 0.09, broke);
  float crack = (1.0 - smoothstep(0.0, width, sc.w)) * cracked;
  float fade = 1.0 - smoothstep(0.8, 1.0, g);
  o.rgb += own * crack * CRACK_GLOW * (1.0 - 0.5 * broke) * fade;
  o.a = max(o.a, crack * 0.85 * fade);
}
// withering (plant.vert `crumbleAt`, the same constants): its colour dries
// out to grey-brown and then to ash; where a flake comes loose it is cut
// along its own cell, its edge lit a dull ember for a moment as it breaks
const float ASH_CELLS = 9.0;
const float CRUMBLE_FROM = 0.45;
const vec3 ASH = vec3(0.16, 0.15, 0.14);
const vec3 EMBER = vec3(0.9, 0.35, 0.1);
float crumbleOf(float h, float w, float jitter) {
  float front = 1.25 - 1.55 * smoothstep(CRUMBLE_FROM, 1.0, w);
  return clamp((h + 0.25 * jitter - front) / 0.35, 0.0, 1.0);
}
void wither() {
  float w = v_cell.w;
  if (w <= 0.0) return;
  float seed = v_inst.y;
  vec4 sc = shardCell(v_rest * ASH_CELLS + seed * 23.0);
  float a = crumbleOf(v_t, w, hash33(sc.xyz + seed * 5.0).x);
  if (a > 0.0 && split()) discard;
  // dried out, then ash
  float lum = dot(o.rgb, LUMA);
  o.rgb = mix(o.rgb, vec3(lum) * vec3(1.05, 0.95, 0.82), smoothstep(0.05, 0.5, w));
  o.rgb = mix(o.rgb, ASH * (0.35 + 0.65 * DAYLIGHT) * (0.7 + 0.6 * lum), max(smoothstep(0.4, 0.9, w), smoothstep(0.0, 0.2, a)));
  // the ember along a flake's edge as it comes loose
  float edge = 1.0 - smoothstep(0.0, 0.07, sc.w);
  o.rgb += EMBER * edge * smoothstep(0.0, 0.1, a) * (1.0 - smoothstep(0.15, 0.5, a)) * 0.8;
}

void main() {
  surface();
  unform();
  wither();
  keepPass(o.a);
}
