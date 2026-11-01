#version 450
//! plants by form: growth, wind, parasite cages and crowns, lantern filaments, confluence keys, radiant gathering and falling.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
// the solid and glass passes rasterize it at the very same depth (the
// glass pass tests `less` against what the solid one wrote)
invariant gl_Position;

// per-vertex (species mesh)
layout(location = 0) in vec3 pos;
layout(location = 1) in vec3 nrm;
layout(location = 2) in vec4 col;
layout(location = 3) in vec3 tu;    // height along plant, position along blade, across a sheet (1..3; 0 none)
layout(location = 4) in uint part;  // 0 stem 1 leaf 2 bloom 3 thorn 4 tendril ... 17 pod
// per-instance
layout(location = 5) in vec3 ipos;
layout(location = 6) in vec4 ia;    // growth, mana fill, seed, affinity
layout(location = 7) in vec4 ib;    // flow, health, sway amplitude, form (species.Form)
layout(location = 8) in vec4 ic;    // blend toward the next growth key, ghost (0/1), ghost fits (0/1), the way it faces (yaw)
// the same vertex in the next growth key (equals pos/nrm for keyless plants)
layout(location = 9) in vec4 ih;    // a forming halo drawing it in: its centre, how far along (< 0 none)
layout(location = 10) in vec4 it;   // its bend after the gardener's paws plucking it: the way on the ground (xy), how far (z, radians at its tip)
layout(location = 11) in vec4 ir;   // its yield ripening: how ripe 0..1, its pods, a radiant pod's radius, seconds since its yield last came loose
layout(location = 12) in vec4 iy;   // the colour of what it yields (sRGB)
layout(location = 13) in vec4 ig;   // its unforming: how far it has shattered 0..1 (< 0 none)
layout(location = 14) in vec3 pos_next;
layout(location = 15) in vec3 nrm_next;

layout(location = 0) out vec3 v_pos;
layout(location = 1) out vec3 v_nrm;
layout(location = 2) out vec3 v_col;
layout(location = 3) out vec2 v_sap;          // mana fill 0..1, sap moving through (pulse) 0..1
layout(location = 6) out float v_t;           // height along the plant (fibre direction)
layout(location = 7) out float v_young;       // 0 old, dense growth .. 1 newest, thinnest
layout(location = 4) flat out vec4 v_inst; // affinity, seed, health, part
layout(location = 5) flat out float v_form;
layout(location = 8) flat out vec2 v_ghost; // a placement preview, and whether it fits
layout(location = 9) out vec3 v_obj;          // the plant-space point (sap bubbles ride with it)
layout(location = 10) out float v_glow;       // how much light a radiant fragment carries (1 elsewhere)
layout(location = 11) out vec2 v_pod;         // a pod: how far it has swelled 0..1 (< 0 not a pod), how freshly its yield was taken 1..0
layout(location = 12) flat out vec4 v_yield;  // the colour of what it yields (linear), how ripe the plant is 0..1
layout(location = 13) flat out float v_glitch; // how far the unforming has shattered it 0..1 (< 0 none)
layout(location = 14) out vec2 v_sheet;       // a leaf or petal: along it 0..1, across it 1..3 (0: not a sheet)

// how far a bloom a forming halo draws in has folded back toward a bud
const float HALO_BUD = 0.12;
// a radiant plant's turning: each ring's pace (rad/s, alternating ways),
// by its radiant_kit.Ring: core, inner, middle, outer whorl, motes, halo,
// leaves, the beads of its yield (with the core), a grounded one's root
// (dug in: it never turns; a ring past the table turns as the last)
const float SPIN[9] = float[9](0.03, 0.05, -0.035, 0.025, 0.1, 0.04, -0.02, 0.03, 0.0);
// the light each ring carries (v_glow): the core and its threads fullest,
// a vesper's floating leaves living tissue that carries little, its root
// a little dimmer than its heart
const float GLOW[9] = float[9](1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.3, 1.0, 0.8);
// a grounded radiant plant's root strikes down out of its heart as it
// gathers: its soil end starts ROOT_STRIKE up, under the heart (the
// vesper's heart height less its core's underside), its heart end held
// decision: a constant, as the vesper is the one grounded radiant plant
const float ROOT_STRIKE = 0.55;
const float MOTE_RATE = 0.07; // how often a mote spirals in (cycles/s)
// how it gathers (common.glsl gatherAway, gatherIn): fragments settle
// ARRIVE_PACE of growth apart by order, each over ARRIVE_SPAN, coming in
// from ARRIVE_REACH out (horizontally), turning ARRIVE_TURN radians
const float ARRIVE_PACE = 0.7;
const float ARRIVE_SPAN = 0.3;
const float ARRIVE_REACH = 1.4;
const float ARRIVE_TURN = 1.4;
// what falls in from the sky instead (the vesper, an evening star come
// down): each piece starts FALL_FROM above its place (and ARRIVE_REACH
// out), turning FALL_TURN round its heart as it comes down
const float FALL_FROM = 1.8;
const float FALL_TURN = 2.4;
// withering out of radiance, a radiant plant comes loose: its pieces sink
// LOOSE_SINK, drift back out (LOOSE_AWAY of the way they came in) and its
// petals and leaves hang open
const float LOOSE_SINK = 0.14;
const float LOOSE_AWAY = 0.22;
const float LOOSE_HANG = 0.7;
// plucked, a plant that never bends from a root (its pieces held by light)
// is drawn after the paws instead: this far (m) per radian of the bend
const float TUG_SLIDE = 0.3;
// a wilting plant sinks to this share of its height
const float WILT = 0.55;
// a sown plant's size: seedling share, and the spread between instances
const float SEEDLING = 0.12;
const float SIZE_MIN = 0.85;
const float SIZE_SPREAD = 0.3;
// how far behind the growing front growth still reads as new (v_young)
const float YOUNG_SPAN = 0.55;
// a pod empty of its yield is a nub this share of its ripe size; ripe, it
// breathes by POD_BREATH of its size at POD_BREATH_RATE (rad/s)
const float POD_NUB = 0.3;
const float POD_BREATH = 0.04;
const float POD_BREATH_RATE = 1.6;
// once its yield comes loose the plant shivers: its leaves, petals and
// pods quiver SHIVER metres at their tips at SHIVER_RATE (rad/s), the
// quiver dying away at SHIVER_FADE a second; the nub a pod leaves weeps
// for WOUND_FADE seconds as it heals
const float SHIVER = 0.018;
const float SHIVER_RATE = 31.0;
const float SHIVER_FADE = 2.6;
const float WOUND_FADE = 4.0;

// what each form does its own way (sets of FORM_ bits, common.glsl): a new
// form, or a new species of one, takes up a behaviour by joining its set.
// (Petals floating free of a core: FORMS_FREE, common.glsl.) Gathered
// falling from the sky rather than drifting in from around it
const uint FORMS_FALLING = FORM_BIT(FORM_STAR);
// its growth keys carry its size, its canopy and its offshoots (blended
// between keys; nothing scaled or unfolded here)
const uint FORMS_KEYED = FORM_BIT(FORM_CONFLUENCE);
// a crown that comes up closed, its fronds a tight bundle, opening out as
// it matures (its leaves and petals not unfolding on their own)
const uint FORMS_CROWNED = FORM_BIT(FORM_COIL);
// a stalk woven tight round its core that parts into a cage from the foot
// up (tu.y how far each strand has parted, parasite_kit `lattice`)
const uint FORMS_PARTING = FORM_BIT(FORM_COIL);
// filaments hanging from a float, rippling like a jelly's
const uint FORMS_FILAMENTS = FORM_BIT(FORM_DRIFT);
// afloat (common.glsl FORMS_AFLOAT): how far what lies on the water drifts
// on the wind (m), how far it bobs on slow ripples (m), how deep under the
// surface the stems still follow it (m)
const float AFLOAT_DRIFT = 0.025;
const float AFLOAT_BOB = 0.006;
const float AFLOAT_DEEP = 0.15;

// how far pod `place` (col.a: its place among `pods`) has swelled when its
// plant is `ripe` (0..1): each fills in turn, the first first
float podSwell(float place, float ripe, float pods) {
  float k = floor(place * pods);
  return smoothstep(0.0, 1.0, clamp(ripe * pods - k, 0.0, 1.0));
}
// how much the plant still shivers, `since` seconds after its yield came loose
float shiverLeft(float since) { return since >= 0.0 ? exp(-since * SHIVER_FADE) : 0.0; }
// a quiver at time `t`, `ph` its phase: a smooth wobble in all three ways
vec3 quiver(float t, float ph) { return vec3(sin(t * SHIVER_RATE + ph), 0.6 * sin(t * SHIVER_RATE * 1.31 + ph * 1.7), cos(t * SHIVER_RATE * 0.87 + ph * 2.3)); }

// the unforming (game/unforming.zig): a radiant plant glitches, shatters
// like glass and blinks out of reality as `g` runs 0..1. Slices of it tear
// sideways and blocks jump out of place, a step at a time; then its shards
// break away outward and up, opening at its facets as glass does. Every
// move is a field of the world point (its seed and the step), so shared
// vertices move alike until the facets themselves part.
const float GLITCH_RATE = 14.0;
vec3 unformAt(vec3 wp, vec3 n, vec3 base, float g, float seed, float t) {
  if (g < 0.0) return wp;
  float step = floor(t * GLITCH_RATE + seed * 37.0);
  // horizontal slices torn sideways, more of them as it goes
  float slice = floor(wp.y * 16.0);
  vec3 hs = hash33(vec3(slice, step, seed * 91.0));
  if (hs.x < 0.15 + 0.5 * g) wp.xz += (hs.yz - 0.5) * 0.3 * g;
  // blocks jumping out of place for a step
  vec3 hb = hash33(floor(wp * 9.0) + step * 1.37);
  if (hb.x > 0.92 - 0.4 * g) wp += (hb - 0.5) * 0.12 * (0.3 + g);
  // shattering: shards break away outward and up
  float sh = smoothstep(0.55, 1.0, g);
  vec3 hp = hash33(floor((wp - base) * 6.0) + seed * 13.0);
  wp += (normalize(n + vec3(0.0, 0.6, 0.0)) * (0.3 + hp.x) + (hp - 0.5) * 0.6) * sh * sh * 1.2;
  return wp;
}

void main() {
  v_sheet = vec2(tu.y, tu.z);
  float t = pc.eye_time.w;
  v_glitch = ig.x;
  float growth = ia.x, fill = ia.y, seed = ia.z, aff = ia.w;
  // a bloom a forming halo draws in spirals to its centre (see haloSpiral),
  // folding back toward a bud as it arrives
  bool drawn = ih.w >= 0.0;
  vec3 base = drawn ? haloSpiral(ipos, ih.xyz, ih.w) : ipos;
  if (drawn) growth = mix(growth, HALO_BUD, haloFold(ih.w));
  float flow = ib.x, health = ib.y, sway = ib.z;
  // species.Form (ib.w): what it does its own way (the FORMS_ sets above)
  bool keyed = formIn(FORMS_KEYED, ib.w);
  bool crowned = formIn(FORMS_CROWNED, ib.w);
  bool sheet = PART_IN(SHEETS, part);
  // a confluence blends between the growth keys around its growth, so it
  // grows smoothly instead of stepping from one shape to the next
  vec3 p = mix(pos, pos_next, ic.x);
  vec3 n = normalize(mix(nrm, nrm_next, ic.x));
  // its yield: how ripe, and how freshly it was taken
  float ripe = clamp(ir.x, 0.0, 1.0);
  float shiver = shiverLeft(ir.w);
  bool pod = part == PART_POD;
  v_yield = vec4(srgb2lin(clamp(iy.rgb, 0.0, 1.0)), ripe);
  v_pod = vec2(-1.0, 0.0);

  if (formIn(FORMS_FREE, ib.w)) {
    // a flower whose petals float free of it, gathered by its core (the
    // radiant way, common.glsl gatherIn): each fragment drifts in from its
    // bearing, spiralling, folded up like a bud, and opens as it settles.
    // Grown, the whorls never quite close: each petal drifts a little away
    // and back, slowly, held by its thread (a thread's core end stays with
    // the core). Motes of light spiral in and are taken up. It never bends
    // from a root. A vesper's pieces fall to it out of the sky instead, and
    // its floating leaves (ring 6) fold and breathe as the petals do.
    Fragment f = fragmentOf(tu.xy, col.a);
    float order = f.order, bearing = f.bearing, ring = f.ring, held = f.held;
    bool leaves = abs(ring - 6.0) < 0.5;
    bool rooted = abs(ring - 8.0) < 0.5;
    // a bead of its yield (ring 7) swells from a nub about its own centre
    // (ir.z its radius) as it ripens, breathing once ripe; just taken, it
    // quivers
    if (pod) {
      float sw = podSwell(col.a, ripe, ir.y);
      float size = mix(POD_NUB, 1.0, sw) * (1.0 + POD_BREATH * sw * sin(t * POD_BREATH_RATE + bearing * 3.0));
      p -= n * ir.z * (1.0 - size);
      p += quiver(t, bearing * 5.0) * SHIVER * 0.5 * shiver;
      v_pod = vec2(sw, exp(-max(ir.w, 0.0) / WOUND_FADE) * (1.0 - sw));
    }
    bool petals = (ring > 0.5 && ring < 3.5) || leaves;
    bool motes = abs(ring - 4.0) < 0.5;
    bool falling = formIn(FORMS_FALLING, ib.w);
    // out of radiance it comes loose (health falls as it withers)
    float loose = 1.0 - clamp(health, 0.0, 1.0);
    float away = gatherAway(order, ARRIVE_PACE, ARRIVE_SPAN, growth);
    float settle = 1.0 - away;
    if (ring > 0.5 && !rooted) away = max(away, loose * LOOSE_AWAY);
    vec2 dir = vec2(cos(bearing), sin(bearing));
    float ph = bearing * 3.0 + ring * 1.7 + seed * 9.0;
    if (petals) {
      // fold up toward a bud while it comes in, then open; breathing
      // slowly once it has settled, the outer whorls most; coming loose,
      // hanging open
      float wide = leaves ? 1.0 : ring;
      float fold = away * 0.9 + 0.07 * (wide / 3.0) * sin(t * 0.35 + ph) - loose * LOOSE_HANG;
      vec3 ax = vec3(-dir.y, 0.0, dir.x);
      float ang = fold * held;
      p = turnAbout(p, ax, ang);
      n = turnAbout(n, ax, ang);
      // drifting apart and together, and bobbing out of step
      float drift = 0.035 * wide * (0.5 + 0.5 * sin(t * 0.3 + ph));
      p.xz += dir * drift * held;
      p.y += 0.025 * sin(t * 0.55 + ph * 1.3) * held;
    }
    if (ring > 0.5 && !rooted) p.y -= loose * LOOSE_SINK * held;
    // each mote spirals in from beyond the outer whorl to the core and
    // fades as it is taken up, then begins again (c 0..1 of the way)
    float c = fract(t * MOTE_RATE + order + seed);
    if (motes) {
      float r = mix(0.75, -0.12, c);
      p.xz += dir * r;
      p.y += mix(-0.2, 0.05, c) + 0.04 * sin(t * 1.1 + ph);
      p.xz = rot(c * 2.2) * p.xz;
    }
    // arriving from afar along its bearing, rising in from below (or, an
    // evening star's, falling from high above), turning round the core as
    // it comes; the heart itself comes down first, alone
    float rise = falling ? FALL_FROM * (0.8 + 0.4 * fract(bearing * 1.3 + seed * 5.0)) : -0.35 + 0.45 * sin(bearing * 3.0 + seed * 9.0);
    vec3 from = vec3(dir.x * ARRIVE_REACH, rise, dir.y * ARRIVE_REACH) * held;
    if (falling && ring < 0.5) from = vec3(0.0, FALL_FROM, 0.0);
    float turns = falling ? FALL_TURN : ARRIVE_TURN;
    // its root strikes straight down out of the heart into the soil
    if (rooted) {
      from = vec3(-p.x, ROOT_STRIKE, -p.z) * held;
      turns = 0.0;
    }
    p = gatherIn(p, from, away, 0.0, turns);
    n = gatherTurn(n, away, turns);
    // each ring turns at its own slow pace, alternating ways
    int ri = clamp(int(ring), 0, 8);
    float spin = SPIN[ri];
    mat2 turn = rot(t * spin + seed * TAU);
    p.xz = turn * p.xz;
    n.xz = turn * n.xz;
    p *= 1.0 + 0.02 * sin(t * 0.6 + seed * TAU);
    // and as it is turned (R)
    mat2 faced = rot(ic.w);
    p.xz = faced * p.xz;
    n.xz = faced * n.xz;
    // drawn into a forming halo, it turns with its orbit
    if (drawn) {
      mat2 orbit = rot(-haloTurn(ih.w));
      p.xz = orbit * p.xz;
      n.xz = orbit * n.xz;
    }
    // plucked, it is drawn after the paws, springing back once let go
    // (its root's soil end stays dug in)
    p.xz += it.xy * it.z * TUG_SLIDE * (rooted ? 1.0 - held : 1.0);
    vec3 wp = unformAt(base + p, n, base, ig.x, seed, t);
    v_pos = wp;
    v_nrm = n;
    v_col = srgb2lin(col.rgb);
    v_form = ib.w;
    v_ghost = ic.yz;
    v_obj = p;
    // light moving through it, a slow pulse out from the core
    v_sap = vec2(fill, 0.5 + 0.5 * sin(t * 1.1 - order * 5.0 + seed * 6.0));
    v_t = order;
    // how far each fragment has settled (it fades in as it arrives)
    v_young = motes ? settle * smoothstep(0.0, 0.15, c) * (1.0 - smoothstep(0.75, 1.0, c)) : settle;
    v_glow = GLOW[ri];
    v_inst = vec4(aff, seed, health, float(part));
    gl_Position = project(wp);
#ifdef SHADOW
    // a radiant plant is light itself: it casts no shadow, but for the
    // living leaves a vesper carries (once they have come down)
    if (!leaves || settle < 0.5) gl_Position = UNSEEN;
#endif
    return;
  }

  // growth: whole-plant scale, then leaves/petals unfurl as it matures
  float g = smoothstep(0.0, 1.0, growth);
  float passed = grownPast(tu.x, 0.8, 0.3, growth);
  float open = part == PART_BLOOM ? smoothstep(0.75, 1.0, growth) : passed;
  // how far out along an offshoot a vertex is (colour alpha 1 - it; 0 on
  // the main plant, meshgen `shootFold`): an offshoot comes up pressed to
  // its stem, its bud or bloom a narrow closed one, and leans out and opens
  // as growth passes where it leaves (a confluence grows them in its keys)
  float shoot = keyed || pod ? 0.0 : 1.0 - col.a;
  // a pod (meshgen `pods`) swells from a nub about its own centre (tu.y
  // its radius) as the plant ripens, each in turn, breathing once ripe
  if (pod) {
    float sw = podSwell(col.a, ripe, ir.y);
    float size = mix(POD_NUB, 1.0, sw) * (1.0 + POD_BREATH * sw * sin(t * POD_BREATH_RATE + col.a * 20.0 + seed * TAU));
    p -= n * tu.y * (1.0 - size);
    v_pod = vec2(sw, exp(-max(ir.w, 0.0) / WOUND_FADE) * (1.0 - sw));
  }
  bool trunk = shoot < 0.002;
  // (a confluence's canopy opens in its growth keys instead, on its leader).
  // Weighted along the leaf (tu.y 0 at its base), so a leaf's base stays
  // where it grows from, on the stem or along a vine.
  if (sheet && !keyed && !crowned && trunk) p.xz *= unfold(0.25, open, tu.y);
  if (!trunk) p.xz *= unfold(0.2, passed, shoot);
  // a parasite's crown comes up closed, its fronds (and the pods and sacs
  // at their ends) a tight upright bundle, and opens out as it matures; the
  // sacs in its cage swell in as the stalk passes them
  if (crowned && trunk) {
    float unfurl = smoothstep(0.3, 1.0, growth);
    if (part == PART_TENDRIL || (part == PART_BLOOM && tu.x >= 0.9)) p.xz *= mix(0.3, 1.0, unfurl);
    else if (part == PART_BLOOM || pod) p.xz *= mix(0.55, 1.0, grownPast(tu.x, 0.7, 0.35, growth));
  }
  // a cage comes up woven tight round its core and parts from the foot up
  if (formIn(FORMS_PARTING, ib.w) && trunk && part == PART_STEM && tu.y > 0.0) p.xz *= mix(1.0 - tu.y, 1.0, grownPast(tu.x, 0.8, 0.35, growth));

  // ---- motion: rooted and heavy. Nothing jitters: plants bend from the
  // root and answer the wind late, tips last; leaves only lift a little.
  // Every offset is a smooth field of position and tu, so shared vertices
  // move alike and the meshes stay watertight. ----
  float h = tu.x;
  // one wind over the whole garden: its heading drifts slowly, and broad
  // gusts roll across it as a wave, so neighbours lean together
  vec4 wind = gardenWind(t, ipos.xz);
  vec2 wdir = wind.xy;
  float gust = wind.z;

  // symbiotic breathing: slow, the leaf tips moving
  if (aff > 0.0 && part == PART_LEAF) p.xz *= 1.0 + 0.04 * aff * tu.y * sin(t * 0.9 + seed * TAU);
  // leaves and petals lift a touch in the gusts, tips most (bases stay)
  if (sheet) p.y += LEAF_LIFT * tu.y * tu.y * gust * sin(t * LEAF_LIFT_RATE + seed * 11.0 + h * 3.0);
  // its yield just taken, it shivers: leaves and petals quiver at their
  // tips, the pods on their stalks, dying away
  if (shiver > 0.0) {
    if (sheet) p += quiver(t, seed * 17.0 + h * 9.0) * SHIVER * tu.y * tu.y * shiver;
    if (pod) p += quiver(t, seed * 17.0 + col.a * 13.0) * SHIVER * 0.6 * shiver;
  }
  // parasites: fronds curl and uncurl slowly while feeding, alien but
  // unhurried; thorns barely stir
  if (aff < -0.5) {
    float hunger = -aff * (0.3 + flow);
    if (part == PART_TENDRIL && trunk) p.xz = rot(sin(t * 0.6 + tu.x * 3.0 + seed * 9.0) * 0.12 * hunger) * p.xz;
    if (part == PART_THORN) p.y += 0.006 * hunger * tu.y * sin(t * 4.0 + seed * 40.0 + tu.x * 7.0);
  }
  // a floater's filaments ripple like a jelly's: slow waves run down them
  // from the float, swinging wider toward the free tips (the bend below
  // still trails them downwind)
  if (part == PART_TENDRIL && formIn(FORMS_FILAMENTS, ib.w)) {
    float down = max(-p.y, 0.0);
    float ph = t * 1.4 - down * 8.0 + seed * TAU;
    p.xz += vec2(sin(ph + p.x * 9.0), cos(ph * 0.83 + p.z * 9.0)) * 0.03 * down;
  }
  // afloat: what lies on the water drifts with the wind, swinging slowly
  // back and forth on its stem, and bobs on ripples running under it; the
  // stems below follow it, less the deeper they lie
  bool afloat = formIn(FORMS_AFLOAT, ib.w);
  if (afloat) {
    float on = smoothstep(-AFLOAT_DEEP, 0.0, p.y);
    p.xz += wdir * AFLOAT_DRIFT * (0.6 + 0.4 * sin(t * 0.4 + seed * TAU)) * (0.5 + gust) * on;
    p.y += AFLOAT_BOB * sin(t * 1.3 + dot(ipos.xz + p.xz, vec2(5.1, 3.7)) + seed * TAU) * on;
  }
  // convergent: blooms turn, very slowly (a confluence's canopy stays on its stems)
  if (abs(aff) < 0.5 && part == PART_BLOOM && !keyed && trunk) p.xz = rot(t * 0.12 + seed * TAU) * p.xz;

  // wilt when unhealthy
  p.y *= mix(WILT, 1.0, health);

  // per-instance variation, turned the way it faces (R)
  float yaw = seed * TAU + ic.w;
  p.xz = rot(yaw) * p.xz;
  n.xz = rot(yaw) * n.xz;

  // the bend: each point turns about the root in the wind's plane, more
  // toward the tip, so a plant curves instead of shearing. Its own lean is
  // slow and reaches the tip after the base. What hangs below the root (a
  // floater's filaments) swings the other way, so it trails downwind.
  float ang = windLean(t, wind, seed * TAU, h, sway) * h * h;
  ang *= formIn(FORMS_LOW, ib.w) ? 0.0 : smoothstep(-0.1, 0.1, p.y) * 2.0 - 1.0;
  p = bendIn(p, wdir, ang);
  n = bendIn(n, wdir, ang);
  // plucked, it bends after the paws drawing its yield back, the same way
  // (tip most), and springs back past upright once the yield comes loose
  float tug = it.z * h * h;
  p = bendIn(p, it.xy, tug);
  n = bendIn(n, it.xy, tug);
  // a confluence's growth keys already carry its size
  float s = (keyed ? 1.0 : mix(SEEDLING, 1.0, g)) * (SIZE_MIN + SIZE_SPREAD * fract(seed * 7.13));
  vec3 wp = unformAt(base + p * s, n, base, ig.x, seed, t);

  v_pos = wp;
  v_nrm = n;
  v_col = srgb2lin(col.rgb);
  v_form = ib.w;
  v_ghost = ic.yz;
  v_obj = p;
  // sap moving through the plant travels up it as a slow pulse
  v_sap = vec2(fill, clamp(flow, 0.0, 1.0) * (0.5 + 0.5 * sin(t * 2.0 - h * 6.0 + seed * 12.0)));
  v_t = h;
  // growth read: what grew last (near the growing front, and toward the
  // tips once grown) is thinner and more translucent than the old base
  v_young = clamp((h - growth + YOUNG_SPAN) / YOUNG_SPAN, 0.0, 1.0);
  if (sheet) v_young = max(v_young, 0.5);
  // a bead of resin carries its dense base .. thin crown (tu.y) instead
  if (part == PART_RESIN) v_young = tu.y;
  v_glow = 1.0;
  v_inst = vec4(aff, seed, health, float(part));
  gl_Position = project(wp);
#ifdef SHADOW
  // a placement preview casts no shadow, nor does a floater's clear lantern
  if (ic.y > 0.5 || isLantern(ib.w, int(part), h)) gl_Position = UNSEEN;
#endif
}

