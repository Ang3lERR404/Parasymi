#version 450
//! places library parts (matrix, curve, star mote, skinned) and moves them: growth splines, wind, breath, carried essence, gathering.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
#include "growth.glsl"
// the solid and glass passes rasterize it at the very same depth (the
// glass pass tests `less` against what the solid one wrote)
invariant gl_Position;
#ifndef SHADOW
out float gl_ClipDistance[1];
#endif

// per-vertex (mesh library)
layout(location = 0) in vec3 pos;
layout(location = 1) in vec3 nrm;
layout(location = 2) in vec4 col;
layout(location = 3) in vec3 tu;    // along the part, along a sheet, across a sheet (1..3; 0 none)
layout(location = 4) in uint part;  // 0 vine 1 leaf 2 sap/glow 3 claw/thorn 4 root 5 sap-lined leaf (ear) 6 resin ... 13 a conduit's core
// per-instance
layout(location = 5) in vec4 c0;
layout(location = 6) in vec4 c1;
layout(location = 7) in vec4 c2;
layout(location = 8) in vec4 c3;
layout(location = 9) in vec4 ip;    // glow, flutter, phase, fade
layout(location = 10) in vec4 tint; // rgb multiply, w amount
layout(location = 11) in vec4 iq;   // essence carried along a conduit's core (< 0 none), give (resin surface push)
layout(location = 12) in vec4 iw;   // sway, height of the sway, how far below the origin it is rooted, grown
layout(location = 13) in vec4 ie;   // placement: 0 matrix, 1 curve (tail), 2 star mote; then its parameters
layout(location = 14) in vec4 ih;   // a forming halo it belongs to: its centre, how far along (< 0 none)
layout(location = 15) in uint iflags; // PART_GHOST, ... (vertex.zig)
layout(location = 16) in vec4 ik;   // how far it is blended into its mesh's next key
// per-vertex skin (skinned meshes only): four bone indices, one per byte, and their weights
layout(location = 17) in uint sbones;
layout(location = 18) in vec4 sweights;
// how each of those weights changes across the mesh: its x, y and z
layout(location = 19) in vec4 sgx;
layout(location = 20) in vec4 sgy;
layout(location = 21) in vec4 sgz;
// per-vertex growth (structures grown along growth splines, gfx/growth.zig):
// where it grows out of, and when it begins, how long it takes, when its
// spline began and was done (gat.y 0: not on a spline)
layout(location = 22) in vec3 gfrom;
layout(location = 23) in vec4 gat;
// the same vertex in its mesh's next key (itself where the mesh has none):
// a bud opening blends into it
layout(location = 24) in vec3 kpos;
layout(location = 25) in vec3 knrm;

// iflags: a placement preview (vertex.PART_GHOST)
const uint PART_GHOST = 1u;

// this frame's bones (renderer Scene.bones): each carries a vertex from
// where it was built to where it is now
layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer Bones { mat4 m[]; };
// this vertex's `k`th bone (of four, one index per byte of sbones), its
// mesh's bones starting at `base`
mat4 bone(Bones B, int base, int k) { return B.m[base + int((sbones >> (8u * uint(k))) & 255u)]; }

layout(location = 0) out vec3 v_pos;
layout(location = 1) out vec3 v_nrm;
layout(location = 2) out vec3 v_col;
layout(location = 3) out float v_glow;
layout(location = 4) flat out float v_part;
layout(location = 5) out float v_t;         // position along the part (tube tangent source)
layout(location = 6) flat out float v_fade; // opacity of translucent sap at its centre
layout(location = 7) out float v_u;
layout(location = 8) out vec3 v_obj;       // mesh-space point (sap bubbles ride with the body)
layout(location = 9) flat out float v_phase; // per-instance phase (seeds a beam's motes)
layout(location = 10) flat out float v_aux;  // a beam: 1 for a halo's edge; a flash: its age 0..1
layout(location = 11) out vec2 v_sheet;      // a leaf or petal: along it 0..1, across it 1..3 (0: not a sheet)

// how an instance is placed (vertex.zig `PartInstance.e.x`; must match)
const int PLACE_MATRIX = 0;
const int PLACE_CURVE = 1;   // along a Catmull-Rom curve (the tail, beams)
const int PLACE_MOTE = 2;    // a star mote
const int PLACE_SKINNED = 3; // by its bones
const int PLACE_BURST = 4;   // a burst flung out where a yield came loose

// how a diamond gathers (common.glsl gatherAway, gatherIn): its facets
// settle PRISM_PACE of the way apart by order, each over PRISM_SPAN,
// drawn in PRISM_REACH along its face, turning PRISM_TURN radians
const float PRISM_PACE = 0.4;
const float PRISM_SPAN = 0.6;
const float PRISM_REACH = 0.45;
const float PRISM_TURN = 3.0;
// a flash spreads out from this share of its size to this many times it
const float FLASH_FROM = 0.1;
const float FLASH_TO = 3.2;
// a star mote: how fast it turns (rad/s), how far its echoes trail above it
const float MOTE_TURN = 0.35;
const float ECHO_RISE = 0.16;
// a burst where a yield came loose (meshes/pluck_burst.zig): its beads'
// radius (mesh space), how far its motes drift up and its drops fall
// over its life (mesh space: the matrix sizes it)
const float BURST_BEAD = 0.11;
const float BURST_RISE = 0.5;
const float BURST_FALL = 1.6;
// sap pulses running along a part (rad/s), and a part's own glow beside a
// glowing sap part's
const float PULSE_RATE = 3.0;
const float DIM_GLOW = 0.06;
// the constellate web (meshes/constellate.zig; PLEXUS_POINTS must match its
// `count`): how many points float in a cluster, which one is its heart (in
// the middle of the spindle), how far each drifts from where it rests and
// how fast (rad/s, slowest and quickest), how big a point is, how wide a
// line, how far a pane's faces sit apart, where a line begins to fade as
// its points part (a share of its reach)
const int PLEXUS_POINTS = 30;
const int PLEXUS_HEART = 15;
const float PLEXUS_DRIFT = 0.13;
// what shape a web holds (meshes/constellate.zig `Shape`): a loose
// cluster, or one of the plant parts a gardener builds with; a part's
// points drift only a little, so it keeps its form
const int PLEXUS_CLUSTER = 0;
const int PLEXUS_PETAL = 1;
const int PLEXUS_LEAF = 2;
const int PLEXUS_BUD = 3;
const int PLEXUS_FLOWER = 4;
const float PLEXUS_PART_DRIFT = 0.025;
// a yielder: five or more petals snapped to a flower head, which becomes
// its core, joined to every petal's base; its webs (each its own shape so
// a web joins only its own points): the core, its five petals (one after
// another), the fragments it yields (three of three points each), the
// motes of light it yields, the point it gathers them in. Where its middle
// is, how far out the petals stand, how they lean up open and shut (rad),
// how fast they turn round the head (rad/s), where their tips gather; how
// long a gathering takes (s), when in it (a share) the gathered point is
// let go; the spring the petals move on (how fast it swings, rad/s, and
// dies away, 1/s), and how far behind the one before each petal follows (s)
const int PLEXUS_YIELD_CORE = 5;
const int PLEXUS_YIELD_PETAL = 6;
const int PLEXUS_YIELD_FRAGMENT = 11;
const int PLEXUS_YIELD_LIGHT = 12;
const int PLEXUS_YIELD_GATHERING = 13;
// a stem: the plain part everything else holds to, its joints (every third
// ring) where other stems and leaves fasten; a sprig built on one: its
// stem, a branch stem fastened at its middle joint, a leaf at its lowest
// joint and another at its highest (each its own shape so a web joins only
// its own points; bonds fasten them)
const int PLEXUS_STEM = 14;
const int PLEXUS_SPRIG_STEM = 15;
const int PLEXUS_SPRIG_BRANCH = 16;
const int PLEXUS_SPRIG_LEAF = 17;
const int PLEXUS_SPRIG_LEAF_HIGH = 18;
// the heart, as it comes to be: four buds fastened to a stem's joints, then
// the whole rising a little, shrunk, filaments dripping from its foot one
// by one and unfurling, then the buds blooming one after another as the
// stem becomes a grand flower. Its webs: the stem, its four buds (one
// after another), its filaments (three of eight points each). Which stage
// a web is at rides in its reach's whole part (0 bound, 1 rising, 2
// blooming), set for every function below as `plexStage`; how long the
// rising and the blooming each take before they begin again (s)
const int PLEXUS_HEART_STEM = 19;
const int PLEXUS_HEART_BUD = 20;
const int PLEXUS_HEART_FILAMENT = 24;
const float PLEXUS_HEART_RISING = 10.0;
const float PLEXUS_HEART_BLOOMING = 16.0;
// where on the stem each bud fastens (the first point of its joint's ring)
// and which way it reaches out
const float PLEXUS_HEART_JOINT[4] = float[4](9.0, 18.0, 27.0, 27.0);
const vec3 PLEXUS_HEART_SIDE[4] = vec3[4](vec3(1.0, 0.0, 0.0), vec3(-1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, -1.0));
// the heart's chain reaction (stage 3, from its blooms all open): four
// petlets snapped to its first bloom make it a yielder of fragments only;
// each fragment spins slowly over to the next bloom and becomes three
// points of one of its petlets, so a petlet is built a fragment at a time
// (four to a petlet, sixteen to a bloom), base to tip, every one swelling
// the heart. A bloom done yields too, all of them feeding the same next
// bloom, so each is finished quicker than the last; when all four are done
// the heart grows past its first size and grand petals open between its
// own. Its webs: the petlets (four on each bloom, `PLEXUS_HEART_PETLET`
// + 4 * bloom + petlet), its grand petals (five, one after another), the
// fragments on their way (forty-eight of three points each). How long it
// all takes before it begins again (s), how often a bloom lets a fragment
// go, and how long one takes on its way
const int PLEXUS_HEART_PETLET = 25;
const int PLEXUS_HEART_GRAND = 41;
const int PLEXUS_HEART_SEED = 46;
const float PLEXUS_HEART_CHAIN = 104.0;
const float PLEXUS_HEART_EVERY = 2.0;
const float PLEXUS_HEART_WAY = 4.5;
// the heart settling into a builder (stage 4, from the chain done): its
// blooms burst free in a puff of fragments and drift slowly down to lie on
// the ground as parts; the heart, keeping its size, floats down to hover
// over the ground, its tendrils hanging free, and faint currents of energy flow in
// from the air below and round it, like water, rising into its base. Its
// webs beside the heart's own: the fragments that burst from the blooms
// (six of three points from each), the currents (seven of ten points). How
// long it all takes before it begins again (s), and how far the heart
// comes down
const int PLEXUS_HEART_BURST = 47;
const int PLEXUS_HEART_CURRENT = 48;
// the heart's grand flower is a layered rose: its stem becomes the rose's
// tight middle, a golden spiral, and three rings of five petals (ten points
// each) open round it one ring after another, the inner hugging it, the
// outer open with their lips curled back. The rose petals' web, and where
// the rose's middle and its petals' feet sit (before the heart is sized)
const int PLEXUS_HEART_ROSE = 49;
// the settled heart builds: the energy its currents bring gathers in a
// glowing spot on top of its rose, and a whole part slowly forms there
// point by point (a petal, a leaf, a bud, a flower head, a stem, a new one
// each time round), resting there until it is taken. Its webs: the part it
// makes, the glowing spot. When in the settling (s) the spot gathers, the
// part forms and how long that takes; how far over the rose's middle the
// spot is, how big a part is made
const int PLEXUS_HEART_MADE = 50;
const int PLEXUS_HEART_MADE_GLOW = 51;
const float PLEXUS_MADE_GATHER = 24.0;
const float PLEXUS_MADE_FORM = 26.0;
const float PLEXUS_MADE_FORMING = 16.0;
const vec3 PLEXUS_MADE_SPOT = vec3(0.0, 1.0, 0.0);
const float PLEXUS_MADE_SIZE = 0.8;
// a tendril the gardener draws: loose fragments braided into a segment
// along a path between two ends, always flowing along it like a stream,
// carrying parts from one end to the other. Its webs: the tendril itself
// at each height it can be set to (`PLEXUS_TENDRIL` + 0 floating, sagging a
// little between its ends; 1 along the ground; 2 arcing up and over), and
// a part riding along each (`PLEXUS_TENDRIL_RIDE` + the same). How many
// strands it is braided of and how many fragments each holds, how long it
// runs, how far the strands stand from its middle, how many turns they make
// round each other along it, how fast the fragments flow along it (lengths
// a second), how long a part takes to ride it (s), and how big a part is
const int PLEXUS_TENDRIL = 52;
const int PLEXUS_TENDRIL_RIDE = 55;
const int PLEXUS_TENDRIL_STRANDS = 3;
const int PLEXUS_TENDRIL_EACH = 24;
const float PLEXUS_TENDRIL_LEN = 2.4;
const float PLEXUS_TENDRIL_R = 0.05;
const float PLEXUS_TENDRIL_TURNS = 2.2;
const float PLEXUS_TENDRIL_FLOW = 0.06;
const float PLEXUS_TENDRIL_RIDING = 8.0;
const float PLEXUS_TENDRIL_PART = 0.3;
const float PLEXUS_ROSE_FOOT = 1.45;
const float PLEXUS_HEART_SETTLE = 56.0;
const float PLEXUS_HEART_DROP = 1.1;
// the heart's whole story in one (stage 5 in the mesh): bound, rising,
// blooming, its chain reaction, settling into a builder, each stage in
// turn on one clock, then fading away to begin again. How long each stage
// is held (s) and how long the fade out and in at the ends
const float PLEXUS_STORY[5] = float[5](6.0, 8.0, 14.0, 96.0, 50.0);
const float PLEXUS_STORY_FADE = 3.0;
// a petlet's rows, base to tip: how many points each holds (12 in all) and
// how far along it lies
const int PLEXUS_PETLET_ROWS[6] = int[6](1, 2, 3, 3, 2, 1);
const float PLEXUS_PETLET_ALONG[6] = float[6](0.02, 0.2, 0.4, 0.6, 0.8, 0.97);
// which stage of the heart the web being placed is at
float plexStage = 0.0;
// whether the heart's settling carries what is being placed down with it
// (0 while placing a bloom that has burst free, or its fragments)
float plexDropOn = 1.0;
// whether the web being placed tells the heart's whole story (1), how far
// into its stage it is (s), and how much of it shows at the ends
float plexStory = 0.0;
float plexLocal = 0.0;
float plexStoryShow = 1.0;
// how many times the story has begun again (which part the heart makes)
float plexStoryRound = 0.0;
// how far into its stage the heart is at time `t` (s): on the story's clock,
// or looping the stage alone every `loop` s
float plexusStageClock(float t, float loop) { return plexStory > 0.5 ? plexLocal : mod(t, loop); }
const vec3 PLEXUS_YIELD_MIDDLE = vec3(0.0, 1.13, 0.0);
const float PLEXUS_YIELD_OUT = 0.5;
const float PLEXUS_YIELD_LEAN = 0.5;
const float PLEXUS_YIELD_SHUT = 1.35;
const float PLEXUS_YIELD_SPIN = 0.15;
const vec3 PLEXUS_YIELD_GATHER = vec3(0.0, 1.75, 0.0);
const float PLEXUS_YIELD_CYCLE = 6.0;
const float PLEXUS_YIELD_RELEASE = 0.7;
const float PLEXUS_YIELD_SWING = 3.6;
const float PLEXUS_YIELD_DAMP = 1.8;
const float PLEXUS_YIELD_LAG = 0.07;
// a petal's rows, base to tip: how many points each holds (30 in all)
// and how far along the petal it lies
const int PLEXUS_PETAL_ROWS[8] = int[8](2, 3, 4, 5, 5, 5, 4, 2);
const float PLEXUS_PETAL_ALONG[8] = float[8](0.02, 0.14, 0.28, 0.42, 0.56, 0.7, 0.84, 0.96);
const float PLEXUS_SLOW = 0.12;
const float PLEXUS_QUICK = 0.32;
const float PLEXUS_POINT_R = 0.009;
// how big a mote of light a yielder gathers or yields is, beside a point
const float PLEXUS_MOTE_R = 0.015;
// each point is a pair of lights circling each other: how far apart they
// are, how much of that the first (the larger) keeps to the middle's far
// side (the smaller swings wider), how big the companion is beside it, how
// fast they circle (rad/s, slowest and quickest)
const float PLEXUS_PAIR = 0.04;
const float PLEXUS_PAIR_LEAN = 0.4;
const float PLEXUS_COMPANION = 0.7;
const float PLEXUS_PAIR_SLOW = 0.6;
const float PLEXUS_PAIR_QUICK = 1.4;
// how far a line's glow reaches either side of it (its bright core a
// share of that, part.frag)
const float PLEXUS_LINE_W = 0.022;
// in the air round what glows (AIR): how much wider a constellate line's
// glow and point's light reach, and how far out any other glow's shell
const float AIR_SPREAD = 5.0;
const float AIR_REACH = 0.08;
const float PLEXUS_PANE = 0.005;
const float PLEXUS_SOFT = 0.8;

// whether point `id` of a stem is on one of its joints, where other stems
// and leaves fasten (every third ring above its foot)
bool plexusJoint(float id) {
  float ring = floor(id / 3.0);
  return ring > 0.5 && mod(ring, 3.0) < 0.5;
}
// where constellate point `id` rests in a part of `shape` on its own (a
// petal, leaf, bud, flower head, stem, loose cluster), each point nudged a
// little off its place so no part is ruled straight
vec3 plexusForm(float id, int shape) {
  vec3 h = hash33(vec3(id, 3.1, 7.7));
  vec3 jit = (h - 0.5) * 0.04;
  if (shape == PLEXUS_PETAL) {
    // a petal: eight rows from its narrow base (two, id 0 the heart) out
    // through its broadest (five) to its round tip (two), cupped and
    // curling back toward its tip; no midrib
    int n = 2;
    float row = 0.0;
    float first = 0.0;
    for (int r = 0; r < 8; r++) {
      n = PLEXUS_PETAL_ROWS[r];
      if (id < first + float(n)) { row = float(r); break; }
      first += float(n);
    }
    float u = PLEXUS_PETAL_ALONG[int(row)];
    float v = n > 1 ? (id - first) / float(n - 1) * 2.0 - 1.0 : 0.0;
    float w = 0.27 * pow(max(sin(0.5 * TAU * min(u, 0.97)), 0.0), 0.6) * (0.4 + 0.6 * u) + 0.025;
    float cup = 0.12 * (1.0 - v * v) * sin(0.5 * TAU * u);
    return vec3(v * w * 0.95, 0.7 + 0.65 * u, 0.3 * u * u - cup) + jit * 0.6;
  }
  if (shape == PLEXUS_LEAF) {
    // a leaf: a midrib of ten from the foot of its stalk (id 0, its
    // heart) to its point, ten down either edge of the blade, which begins
    // a fifth of the way up; it reaches out and up from the stalk, its
    // edges folded a little up from the midrib, widest a third of the way
    // along its blade and drawn to a point
    float side = id < 10.0 ? 0.0 : (id < 20.0 ? -1.0 : 1.0);
    float k = id < 10.0 ? id : mod(id - 10.0, 10.0);
    float ub = id < 10.0 ? max(k / 9.0 - 0.2, 0.0) / 0.8 : (k + 0.5) / 10.0;
    float u = id < 10.0 ? k / 9.0 : 0.2 + 0.8 * ub;
    float w = 0.24 * pow(sin(0.5 * TAU * ub), 0.75) * (1.0 - 0.35 * ub);
    vec3 c = vec3(0.0, 0.55 + 0.75 * u - 0.25 * u * u, 0.6 * u);
    vec3 up = normalize(vec3(0.0, 0.6, -(0.75 - 0.5 * u)));
    return c + vec3(side * w, 0.0, 0.0) + up * abs(side) * w * 0.3 + jit * 0.4;
  }
  if (shape == PLEXUS_BUD) {
    // a bud: closed, a teardrop of points wound in a golden spiral from
    // its base (id 0) to its tip (the last)
    float u = id / float(PLEXUS_POINTS - 1);
    float a = id * 2.39996;
    float r = 0.17 * pow(sin(0.5 * TAU * pow(u, 0.75)), 0.9);
    return vec3(cos(a) * r, 0.75 + 0.55 * u, sin(a) * r) + jit * 0.5;
  }
  if (shape == PLEXUS_STEM) {
    // a stem: ten rings of three wound round its length from its foot
    // (id 0, its heart) up, thinning as it rises and leaning a little; a
    // ring every third (its joints) swelling where things fasten
    float ring = floor(id / 3.0);
    float u = ring / 9.0;
    float a = (id - ring * 3.0) / 3.0 * TAU + ring * 0.7;
    float r = 0.035 * (1.0 - 0.3 * u) + (plexusJoint(id) ? 0.025 : 0.0);
    return vec3(cos(a) * r + 0.06 * sin(0.5 * TAU * u), 0.5 + 1.2 * u, sin(a) * r) + jit * 0.2;
  }
  if (shape == PLEXUS_FLOWER) {
    // a flower head, open: its heart (id 0) in the middle of a domed disc
    // of nine, five petals of four round it (base, two flanks, tip),
    // cupped up toward their tips
    if (id < 0.5) return vec3(0.0, 1.13, 0.0);
    if (id < 9.5) {
      float a = (id - 1.0) / 9.0 * TAU;
      return vec3(cos(a) * 0.075, 1.1 + 0.015 * mod(id, 2.0), sin(a) * 0.075) + jit * 0.3;
    }
    float p = floor((id - 10.0) / 4.0);
    float k = mod(id - 10.0, 4.0);
    float r = k < 0.5 ? 0.18 : (k < 2.5 ? 0.3 : 0.42);
    float off = k < 0.5 || k > 2.5 ? 0.0 : (k < 1.5 ? -0.22 : 0.22);
    float a = p / 5.0 * TAU + off;
    float lift = 0.15 * (r / 0.42) * (r / 0.42);
    return vec3(cos(a) * r, 1.0 + lift, sin(a) * r) + jit * 0.5;
  }
  // a loose cluster: an upright spindle of them, widest in the middle,
  // from knee height to over the wolf's head
  float up = id / float(PLEXUS_POINTS - 1);
  float wide = 0.2 + 0.4 * sin(0.5 * TAU * up);
  float a = h.x * TAU;
  float r = wide * mix(0.35, 1.0, h.y);
  return vec3(cos(a) * r, 0.5 + 1.2 * up + (h.z - 0.5) * 0.12, sin(a) * r);
}
// where constellate point `id` rests in a web of `shape`: a part on its
// own where it is, a yielder's core where a flower head is (its petals
// move, `plexusPetal`)
vec3 plexusRest(float id, int shape) { return plexusForm(id, shape == PLEXUS_YIELD_CORE ? PLEXUS_FLOWER : (shape == PLEXUS_SPRIG_STEM ? PLEXUS_STEM : shape)); }
// a lone part's point `q`, its own `origin` set on `base` and turned so
// its up runs `along` and its front `face`, at `size`
vec3 plexusFasten(vec3 q, vec3 origin, vec3 base, vec3 along, vec3 face, float size) {
  vec3 d = (q - origin) * size;
  return base + d.x * cross(along, face) + d.y * along + d.z * face;
}
// where point `id` (drifted by `moved`) of a part fastened in a sprig is:
// the branch stem from the sprig stem's middle joint, leaning out to one
// side; a leaf from its lowest joint reaching out the other way, another
// from its highest reaching out a third
vec3 plexusSprig(float id, int shape, vec3 moved) {
  if (shape == PLEXUS_SPRIG_BRANCH) return plexusFasten(plexusForm(id, PLEXUS_STEM) + moved, vec3(0.0, 0.5, 0.0), plexusForm(19.0, PLEXUS_STEM) + vec3(-0.04, 0.0, 0.0), normalize(vec3(-0.65, 0.75, 0.1)), vec3(0.0, 0.0, 1.0), 0.65);
  vec3 q = plexusForm(id, PLEXUS_LEAF) + moved;
  if (shape == PLEXUS_SPRIG_LEAF) return plexusFasten(q, vec3(0.0, 0.55, 0.0), plexusForm(10.0, PLEXUS_STEM) + vec3(0.03, 0.0, 0.0), normalize(vec3(0.2, 1.0, 0.0)), vec3(1.0, 0.0, 0.0), 0.75);
  return plexusFasten(q, vec3(0.0, 0.55, 0.0), plexusForm(28.0, PLEXUS_STEM) + vec3(0.0, 0.0, 0.03), normalize(vec3(0.0, 1.0, 0.25)), normalize(vec3(0.3, 0.0, 1.0)), 0.65);
}
// how far a yielder's petals have turned in at time `t` (0 open, 1 shut):
// over each gathering they close, hold while the gathered point fills, and
// open again once it is let go; each move on a spring, overshooting a
// little and settling (a damped swing: how fast it swings, rad/s, and how
// fast it dies away, 1/s), the opening the livelier
float plexusShut(float t) {
  float x = fract(t / PLEXUS_YIELD_CYCLE) * PLEXUS_YIELD_CYCLE;
  float let = PLEXUS_YIELD_RELEASE * PLEXUS_YIELD_CYCLE;
  // closing, from the start of the gathering
  float shut = 1.0 - exp(-PLEXUS_YIELD_DAMP * x) * cos(PLEXUS_YIELD_SWING * x);
  // opening, from the moment the gathered point is let go
  float y = max(x - let, 0.0);
  float stay = x < let ? 1.0 : exp(-PLEXUS_YIELD_DAMP * 1.2 * y) * cos(PLEXUS_YIELD_SWING * 1.2 * y);
  return shut * stay;
}
// where a point `q` of a lone petal (plexusForm) is on a yielder's petal
// `k` at time `t`: the petals turn slowly round the head all the while,
// each standing out from the core's rim and leaning up; as they shut they
// rise and turn in, and their tips are drawn to one point over the core;
// each petal a moment behind the one before, so they move as a ripple
vec3 plexusPetal(vec3 q, int k, float t) {
  float shut = plexusShut(t - float(k) * PLEXUS_YIELD_LAG);
  float a = float(k) / 5.0 * TAU + t * PLEXUS_YIELD_SPIN;
  vec3 outward = vec3(cos(a), 0.0, sin(a));
  vec3 across = vec3(-sin(a), 0.0, cos(a));
  float lean = mix(PLEXUS_YIELD_LEAN, PLEXUS_YIELD_SHUT, shut);
  vec3 along = outward * cos(lean) + vec3(0.0, sin(lean), 0.0);
  vec3 face = cross(across, along);
  vec3 base = PLEXUS_YIELD_MIDDLE + outward * PLEXUS_YIELD_OUT + vec3(0.0, 0.03, 0.0);
  vec3 p = base + q.x * across + (q.y - 0.7) * along + q.z * face;
  float u = clamp((q.y - 0.7) / 0.65, 0.0, 1.0);
  return mix(p, PLEXUS_YIELD_GATHER, clamp(shut, 0.0, 1.0) * pow(u, 2.5));
}
// what a yielder gathers and yields, point `id` of `shape` at time `t`:
// where it is (xyz) and how much of it there is (w, 0 to 1). While the
// petals are shut, the air and energy their tips draw in gathers into one
// point of light over the core, filling; when it is full it is let go as
// one mote of light, rising straight and quick, and one new fragment (three
// points, a small pane), which grows, rises turning out and tumbling, and
// is let go. Two motes and three fragments are on their way at once, each
// from a gathering before the last
vec4 plexusYield(float id, int shape, float t) {
  float s = t / PLEXUS_YIELD_CYCLE;
  if (shape == PLEXUS_YIELD_GATHERING) {
    float c = fract(s);
    return vec4(PLEXUS_YIELD_GATHER, smoothstep(0.15, PLEXUS_YIELD_RELEASE, c) * (1.0 - step(PLEXUS_YIELD_RELEASE, c)));
  }
  if (shape == PLEXUS_YIELD_LIGHT) {
    float age = mod(s - PLEXUS_YIELD_RELEASE - id, 2.0);
    vec3 h = hash33(vec3(id, 7.1, 3.3)) - 0.5;
    float env = smoothstep(0.0, 0.03, age) * (1.0 - smoothstep(0.35, 0.8, age));
    return vec4(PLEXUS_YIELD_GATHER + vec3(h.x, 0.0, h.z) * 0.15 * age + vec3(0.0, 2.2 * age, 0.0), env);
  }
  float f = floor(id / 3.0);
  float c = id - f * 3.0;
  float age = mod(s - PLEXUS_YIELD_RELEASE - f, 3.0);
  float env = smoothstep(0.0, 0.12, age) * (1.0 - smoothstep(2.0, 2.6, age));
  float sa = age * 1.6 + f * 2.1;
  vec3 mid = PLEXUS_YIELD_GATHER + vec3(cos(sa), 0.0, sin(sa)) * 0.12 * age + vec3(0.0, 0.6 * age, 0.0);
  vec3 e1 = normalize(vec3(cos(t + f), 0.4, sin(t + f)));
  vec3 e2 = normalize(cross(e1, vec3(0.3, 1.0, 0.2)));
  float ang = c / 3.0 * TAU + t * 1.3;
  return vec4(mid + 0.07 * env * (cos(ang) * e1 + sin(ang) * e2), env);
}
// how far into the chain reaction it is at time `t` (s), and how much of
// it is still standing (it all comes undone quickly at the end, to begin
// again)
float plexusChainAt(float t) {
  if (plexStage > 3.5) return PLEXUS_HEART_CHAIN - 5.0;
  if (plexStory > 0.5) return plexStage < 2.5 ? -100.0 : plexLocal;
  return mod(t, PLEXUS_HEART_CHAIN);
}
float plexusChainKeep(float t) { return 1.0 - smoothstep(PLEXUS_HEART_CHAIN - 4.0, PLEXUS_HEART_CHAIN - 1.0, plexusChainAt(t)); }
// when the blooms begin building bloom `k` (1 to 3, s into the chain): the
// first at once, each next once the last fragment of the one before has
// arrived, its `k` done blooms letting fragments go in turn
float plexusChainStart(int k) {
  float s = 0.0;
  for (int b = 1; b < k; b++) s += 15.0 * PLEXUS_HEART_EVERY / float(b) + PLEXUS_HEART_WAY;
  return s;
}
// when fragment `n` (0 to 15) for bloom `k` is let go: its done blooms take
// turns, so it comes `k` times as often
float plexusChainLetGo(int k, float n) { return plexusChainStart(k) + n * PLEXUS_HEART_EVERY / float(k); }
// when the last fragment arrives and every bloom is done
float plexusChainDone() { return plexusChainLetGo(3, 15.0) + PLEXUS_HEART_WAY; }
// how far point `id` of petlet `j` on the heart's bloom `k` is there at
// time `t`: the first bloom's snapped on from the start, the others' three
// at a time, as the fragment that becomes them arrives
float plexusChainPetlet(int k, int j, float id, float t) {
  // (snapped on as the story's chain begins)
  if (k == 0) return plexStory > 0.5 ? smoothstep(0.0, 1.5, plexusChainAt(t)) : plexusChainKeep(t);
  float a = plexusChainLetGo(k, float(j * 4) + floor(id / 3.0)) + PLEXUS_HEART_WAY;
  return smoothstep(a - 0.15, a + 0.35, plexusChainAt(t)) * plexusChainKeep(t);
}
// how many fragments have arrived at bloom `k` by `x` s into the chain
float plexusChainLanded(int k, float x) { return clamp((x - plexusChainStart(k) - PLEXUS_HEART_WAY) * float(k) / PLEXUS_HEART_EVERY + 1.0, 0.0, 16.0); }
// how far the heart has risen off the ground at time `t` (0 bound, 1 up):
// in the story, slowly as its rising begins; on its own, at once
float plexusRise(float t) {
  if (plexStage < 0.5) return 0.0;
  if (plexStory > 0.5 && plexStage < 1.5) return smoothstep(0.0, 4.0, plexLocal);
  return 1.0;
}
// how big the heart is at time `t` (its first size 1): shrunk once it
// rises; in the chain reaction swelling with every fragment that arrives,
// then growing slowly past its first size once all four blooms are done,
// until it stands twice the wolf's height, tendril tips to rose
float plexusHeartSize(float t) {
  if (plexStage < 0.5) return 1.0;
  // (in the story, shrinking as it rises)
  if (plexStory > 0.5 && plexStage < 1.5) return mix(1.0, 0.7, plexusRise(t));
  if (plexStage < 2.5) return 0.7;
  float x = plexusChainAt(t);
  float done = 0.0;
  for (int k = 1; k < 4; k++) done += plexusChainLanded(k, x);
  float last = plexusChainDone();
  return 0.7 + (0.2 * done / 48.0 + 1.4 * smoothstep(last, last + 12.0, x)) * plexusChainKeep(t);
}
// how far into its settling the heart is at time `t` (s), and how much of
// it still holds (it all goes back quickly at the end, to begin again)
float plexusSettleAt(float t) { return plexStory > 0.5 && plexStage < 3.5 ? -100.0 : plexusStageClock(t, PLEXUS_HEART_SETTLE); }
float plexusSettleKeep(float t) { return 1.0 - smoothstep(PLEXUS_HEART_SETTLE - 4.0, PLEXUS_HEART_SETTLE - 1.0, plexusSettleAt(t)); }
// when the heart's bloom `k` bursts free (s into the settling)
float plexusSettleLet(int k) { return 3.0 + 0.6 * float(k); }
// how far the heart's bloom `k` has drifted down to the ground at time `t`
float plexusSettleFall(int k, float t) {
  float r = plexusSettleLet(k);
  return smoothstep(r, r + 13.0, plexusSettleAt(t)) * plexusSettleKeep(t);
}
// how far the heart has come down at time `t` (0 floating, 1 near the
// ground): only while it settles, once its blooms are well on their way
float plexusSettleDrop(float t) {
  if (plexStage < 3.5) return 0.0;
  return smoothstep(8.0, 24.0, plexusSettleAt(t)) * plexusSettleKeep(t);
}
// how far the heart's grand petals have opened at time `t`, one after
// another once it has grown
float plexusChainGrand(int p, float t) {
  float a = plexusChainDone() + 12.0 + 1.2 * float(p);
  return smoothstep(a, a + 5.0, plexusChainAt(t)) * plexusChainKeep(t);
}
// how far the heart's stem has become its grand flower at time `t` (0 a
// stem, 1 the flower): only while blooming, slowly, and undone quickly
// before the blooming begins again; all of it in the chain reaction
float plexusHeartMorph(float t) {
  if (plexStage < 1.5) return 0.0;
  if (plexStage > 2.5) return 1.0;
  float x = plexusStageClock(t, PLEXUS_HEART_BLOOMING);
  return smoothstep(2.0, 12.0, x) * (1.0 - smoothstep(14.0, 16.0, x));
}
// how far the heart's bud `k` has bloomed at time `t`: one after another
float plexusHeartBloom(int k, float t) {
  if (plexStage < 1.5) return 0.0;
  if (plexStage > 2.5) return 1.0;
  float x = plexusStageClock(t, PLEXUS_HEART_BLOOMING);
  return smoothstep(1.0 + 2.0 * float(k), 4.0 + 2.0 * float(k), x) * (1.0 - smoothstep(14.0, 16.0, x));
}
// how far the heart's filament `k` has dripped down at time `t`: none
// while bound, one after another while rising, all while blooming
float plexusHeartGrow(float k, float t) {
  if (plexStage < 0.5) return 0.0;
  if (plexStage > 1.5) return 1.0;
  float x = plexusStageClock(t, PLEXUS_HEART_RISING);
  return smoothstep(1.5 * k, 1.5 * k + 3.0, x) * (1.0 - smoothstep(9.0, 10.0, x));
}
// a point `p` of the heart once it rises: sized about its foot, lifted
// off the ground and gently bobbing; brought down near the ground as it
// settles
vec3 plexusHeartLift(vec3 p, float t) {
  if (plexStage < 0.5) return p;
  vec3 foot = vec3(0.0, 0.5, 0.0);
  float down = PLEXUS_HEART_DROP * plexusSettleDrop(t) * plexDropOn;
  return foot + (p - foot) * plexusHeartSize(t) + vec3(0.0, (0.45 + 0.04 * sin(t * 0.8)) * plexusRise(t) - down, 0.0);
}
// where point `id` (drifted by `moved`) of the heart's stem is at time
// `t`: a stem, drawing in to become its rose's tight middle, a golden
// spiral wound up from where its petals stand
vec3 plexusHeartStem(float id, float t, vec3 moved) {
  vec3 stem = plexusForm(id, PLEXUS_STEM);
  vec3 middle = (plexusForm(id, PLEXUS_BUD) - vec3(0.0, 0.75, 0.0)) * 0.7 + vec3(0.0, PLEXUS_ROSE_FOOT + 0.06, 0.0);
  return plexusHeartLift(mix(stem, middle, plexusHeartMorph(t)) + moved, t);
}
// how far ring `ring` (0 inner, 2 outer) of the heart's rose has opened at
// time `t`: one ring after another as the stem becomes it
float plexusRoseOpen(float ring, float t) { return smoothstep(ring * 0.2, ring * 0.2 + 0.6, plexusHeartMorph(t)); }
// where point `id` (drifted by `moved`) of the heart's rose petals is at
// time `t`: petal id/10 (ring by fives, each ring turned on from the last),
// its ten points its foot, then three rows of three across it (an edge,
// its middle, the other edge), the last its lip. Each lies on a ball round the rose's middle,
// running from under it up its side, so together they make a round rose:
// the inner ring's lips folded in over the middle, the outer ring wider and
// open, its lips curling back out. Closed, each is tucked small under it
vec3 plexusHeartRose(float id, float t, vec3 moved) {
  float p = floor(id / 10.0);
  float j = id - p * 10.0;
  float ring = floor(p / 5.0);
  float i = p - ring * 5.0;
  float open = plexusRoseOpen(ring, t);
  float row = j < 0.5 ? 0.0 : 1.0 + floor((j - 1.0) / 3.0);
  float u = row / 3.0;
  float v = j < 0.5 ? 0.0 : mod(j - 1.0, 3.0) - 1.0;
  float a = i / 5.0 * TAU + ring * 0.63;
  float rad = mix(0.08, 0.17 + 0.08 * ring, open) * (1.0 + 0.25 * ring * open * u * u * u);
  float polar = mix(2.6, mix(2.4, 0.45 + 0.4 * ring, open), u);
  float az = a + v * (0.5 + 0.1 * ring) * (row < 1.5 ? 0.7 : (row < 2.5 ? 1.0 : 0.85));
  vec3 middle = vec3(0.0, PLEXUS_ROSE_FOOT + 0.25, 0.0);
  return plexusHeartLift(middle + rad * vec3(sin(polar) * cos(az), cos(polar), sin(polar) * sin(az)) + moved, t);
}
// where point `id` of the heart's bud `k` is: fastened at its joint,
// reaching out and up, blooming from a bud into a flower head
vec3 plexusHeartBud(float id, int k, float t, vec3 moved) {
  vec3 q = mix(plexusForm(id, PLEXUS_BUD), (plexusForm(id, PLEXUS_FLOWER) - vec3(0.0, 1.0, 0.0)) * 0.8 + vec3(0.0, 0.8, 0.0), plexusHeartBloom(k, t)) + moved;
  // (fastened at its joint, then round the rose's rim as the stem becomes it)
  vec3 rim = PLEXUS_HEART_SIDE[k] * 0.34 + vec3(0.0, PLEXUS_ROSE_FOOT + 0.14, 0.0);
  vec3 base = plexusHeartLift(mix(plexusForm(PLEXUS_HEART_JOINT[k] + 1.0, PLEXUS_STEM), rim, plexusHeartMorph(t)), t);
  vec3 along = normalize(PLEXUS_HEART_SIDE[k] * 0.8 + vec3(0.0, 0.6, 0.0));
  vec3 face = normalize(cross(along, vec3(0.0, 1.0, 0.0)));
  return plexusFasten(q, vec3(0.0, 0.75, 0.0), base, along, face, 0.6 * plexusHeartSize(t));
}
// where point `id` of a petlet rests on its own: a small petal, rows
// from a narrow base to a round tip, cupped, as a petal is
vec3 plexusPetlet(float id) {
  int n = 1;
  int row = 0;
  float first = 0.0;
  for (int r = 0; r < 6; r++) {
    n = PLEXUS_PETLET_ROWS[r];
    if (id < first + float(n)) { row = r; break; }
    first += float(n);
  }
  float u = PLEXUS_PETLET_ALONG[row];
  float v = n > 1 ? (id - first) / float(n - 1) * 2.0 - 1.0 : 0.0;
  float w = 0.27 * pow(max(sin(0.5 * TAU * min(u, 0.97)), 0.0), 0.6) * (0.4 + 0.6 * u) + 0.025;
  float cup = 0.12 * (1.0 - v * v) * sin(0.5 * TAU * u);
  return vec3(v * w * 0.95, 0.7 + 0.65 * u, 0.3 * u * u - cup);
}
// a lone part's point `q`, its own `origin` set on `base`, reaching out
// along `outward` and leaning up by `lean` (rad), at `size`
vec3 plexusSpread(vec3 q, vec3 origin, vec3 base, vec3 outward, float lean, float size) {
  vec3 across = normalize(cross(vec3(0.0, 1.0, 0.0), outward));
  vec3 along = outward * cos(lean) + vec3(0.0, sin(lean), 0.0);
  return plexusFasten(q, origin, base, along, cross(across, along), size);
}
// where the middle of the heart's bloom `k` is at time `t`
vec3 plexusHeartBloomMiddle(int k, float t) { return plexusHeartBud(0.0, k, t, vec3(0.0)); }
// where point `id` (drifted by `moved`) of petlet `j` on the heart's bloom
// `k` is: standing out from the bloom's middle between its own petals,
// leaning up, each point where its fragment set it
vec3 plexusHeartPetlet(float id, int k, int j, float t, vec3 moved) {
  float a = (float(j) + 0.5) / 4.0 * TAU + float(k) * 0.9;
  vec3 outward = vec3(cos(a), 0.0, sin(a));
  return plexusSpread(plexusPetlet(id) + moved, vec3(0.0, 0.7, 0.0), plexusHeartBloomMiddle(k, t) + outward * 0.03, outward, 0.55, 0.4 * plexusHeartSize(t));
}
// where point `id` (drifted by `moved`) of the heart's grand petal `p` is:
// from the grand flower's middle, between two of its own petals, reaching
// about half again as far, leaning up a little, opening as it forms
vec3 plexusHeartGrand(float id, int p, float t, vec3 moved) {
  float a = (float(p) + 0.5) / 5.0 * TAU;
  vec3 outward = vec3(cos(a), 0.0, sin(a));
  vec3 middle = vec3(0.0, PLEXUS_ROSE_FOOT + 0.05, 0.0);
  float open = plexusChainGrand(p, t);
  vec3 q = plexusSpread(plexusForm(id, PLEXUS_PETAL) + moved, vec3(0.0, 0.7, 0.0), middle + outward * 0.3, outward, mix(1.2, 0.3, open), 1.6 * (0.05 + 0.95 * open));
  return plexusHeartLift(q, t);
}
// what of a fragment the heart's done blooms let go, point `id` at time
// `t`: where it is (xyz) and how much of it there is (w). Fragment i is
// the n-th of sixteen for bloom k, let go by its done blooms in turn; it
// spins slowly on its way, arcing up, and as it comes in its three points
// part to the three of the petlet they become, where it is gone and they
// are lit
vec4 plexusHeartSeed(float id, float t) {
  float i = floor(id / 3.0);
  float c = id - i * 3.0;
  int k = 1 + int(i / 16.0);
  float n = i - float(k - 1) * 16.0;
  float s = (plexusChainAt(t) - plexusChainLetGo(k, n)) / PLEXUS_HEART_WAY;
  float sc = clamp(s, 0.0, 1.0);
  int from = int(mod(n, float(k)));
  vec3 a = plexusHeartBloomMiddle(from, t) + vec3(0.0, 0.08, 0.0);
  vec3 b = plexusHeartBloomMiddle(k, t);
  vec3 mid = mix(a, b, smoothstep(0.0, 1.0, sc)) + vec3(0.0, 0.25 * sin(0.5 * TAU * sc), 0.0);
  float env = smoothstep(0.0, 0.12, s) * (1.0 - step(1.0, s)) * plexusChainKeep(t);
  float spin = t * 1.1 + i;
  vec3 e1 = normalize(vec3(cos(spin), 0.5, sin(spin)));
  vec3 e2 = normalize(cross(e1, vec3(0.2, 1.0, 0.3)));
  float ang = c / 3.0 * TAU + t * 0.9;
  vec3 p = mid + 0.06 * env * (cos(ang) * e1 + sin(ang) * e2);
  // the petlet point it becomes: the fragment's c-th of its petlet's three
  int j = int(n / 4.0);
  vec3 to = plexusHeartPetlet(3.0 * mod(n, 4.0) + c, k, j, t, vec3(0.0));
  return vec4(mix(p, to, smoothstep(0.6, 1.0, sc)), env);
}
// where point `id` of the heart's filaments is: filament k hangs from
// point k of the stem's foot, dripping down as it grows, its young tip
// curled tight and unfurling as it lengthens, swaying a little
vec3 plexusHeartFilament(float id, float t) {
  float k = floor(id / 8.0);
  float j = id - k * 8.0;
  float grow = plexusHeartGrow(k, t);
  vec3 anchor = plexusHeartStem(k, t, vec3(0.0));
  vec3 side = normalize(vec3(anchor.x, 0.0, anchor.z) + vec3(1e-4, 0.0, 0.0));
  float s = j / 7.0 * 0.6 * grow * plexusHeartSize(t) / 0.7;
  float bend = mix(14.0, 0.5, grow);
  vec3 p = anchor + side * (1.0 - cos(bend * s)) / bend - vec3(0.0, sin(bend * s) / bend, 0.0);
  return p + vec3(sin(t * 0.9 + k * 2.0), 0.0, cos(t * 0.7 + k)) * 0.03 * j / 7.0 * plexusHeartSize(t) / 0.7;
}
// a point `p` of the heart's bloom `k` (placed where it was fastened) once
// it bursts free: pushed out a little, then drifting slowly down to the
// ground like a falling leaf, swaying side to side and turning, coming to
// stand upright on its base where it lands, a part to be picked up
vec3 plexusBloomFall(vec3 p, int k, float t) {
  if (plexStage < 3.5) return p;
  float x = plexusSettleAt(t);
  float r = plexusSettleLet(k);
  float pop = smoothstep(r, r + 1.5, x) * plexusSettleKeep(t);
  float f = plexusSettleFall(k, t);
  vec3 m0 = plexusHeartBloomMiddle(k, t);
  vec3 away = normalize(vec3(m0.x, 0.0, m0.z) + vec3(1e-4, 0.0, 0.0));
  vec3 land = vec3(m0.x, 0.02, m0.z) + away * 0.5;
  vec3 sway = vec3(away.z, 0.0, -away.x) * 0.18 * sin(x * 1.1 + float(k) * 1.7) * sin(0.5 * TAU * f);
  vec3 piv = mix(m0 + away * 0.2 * pop, land, f) + sway;
  vec3 along = normalize(PLEXUS_HEART_SIDE[k] * 0.8 + vec3(0.0, 0.6, 0.0));
  vec3 axis = normalize(cross(along, vec3(0.0, 1.0, 0.0)));
  vec3 v = turnAbout(p - m0, axis, acos(along.y) * smoothstep(0.0, 0.8, f));
  return piv + turnAbout(v, vec3(0.0, 1.0, 0.0), 1.2 * f);
}
// what of a fragment burst from the heart's blooms, point `id` at time
// `t`: where it is (xyz) and how much of it there is (w). Six burst from
// each bloom as it breaks free, flung out quick and slowing, tumbling,
// sinking and fading as they go
vec4 plexusHeartBurst(float id, float t) {
  float i = floor(id / 3.0);
  float c = id - i * 3.0;
  int k = int(i / 6.0);
  float s = (plexusSettleAt(t) - plexusSettleLet(k)) / 7.0;
  float sc = clamp(s, 0.0, 1.0);
  vec3 dir = normalize(hash33(vec3(i, 7.1, 3.3)) - 0.5 + vec3(0.0, 0.25, 0.0));
  vec3 mid = plexusHeartBloomMiddle(k, t) + dir * 0.45 * (1.0 - exp(-4.0 * sc)) - vec3(0.0, 0.5 * sc * sc, 0.0);
  float env = step(0.0, s) * smoothstep(0.0, 0.04, s) * (1.0 - smoothstep(0.55, 1.0, s)) * plexusSettleKeep(t);
  float spin = t * 1.7 + i;
  vec3 e1 = normalize(vec3(cos(spin), 0.5, sin(spin)));
  vec3 e2 = normalize(cross(e1, vec3(0.2, 1.0, 0.3)));
  float ang = c / 3.0 * TAU + t * 1.3;
  return vec4(mid + 0.05 * env * (cos(ang) * e1 + sin(ang) * e2), env);
}
// how far along its current point `id` of the heart's currents is (0
// where it comes in, 1 its base) at time `t`: flowing slowly on, the
// points of each current spaced along it
float plexusCurrentAlong(float id, float t) {
  float c = floor(id / 10.0);
  return fract((id - c * 10.0) / 10.0 + plexusSettleAt(t) * 0.05 + hash33(vec3(c, 9.1, 4.7)).x);
}
// how much there is of point `id` of the heart's currents at time `t`:
// faint, only once the heart has settled, thinning to nothing at either end
float plexusCurrentShow(float id, float t) {
  float on = 0.6 * smoothstep(16.0, 24.0, plexusSettleAt(t)) * plexusSettleKeep(t);
  return on * sin(0.5 * TAU * plexusCurrentAlong(id, t));
}
// where point `id` of the heart's currents is at time `t`: seven currents
// coming in low from all round, from the air below it, spiralling in and
// rising into its base like water drawn up, rippling as they flow
vec3 plexusHeartCurrent(float id, float t) {
  float c = floor(id / 10.0);
  float x = plexusSettleAt(t);
  vec3 h = hash33(vec3(c, 2.3, 8.9));
  float u = plexusCurrentAlong(id, t);
  vec3 base = plexusHeartStem(0.0, t, vec3(0.0));
  float a = c / 7.0 * TAU + h.y * 0.8 + 1.6 * u + 0.15 * sin(x * 0.3 + c);
  float wave = 0.035 * (1.0 - u) * sin(u * 14.0 - x * 2.2 + c * 1.3);
  float r = mix(0.9 + 0.3 * h.z, 0.0, pow(u, 0.8)) + wave;
  float y = mix(0.05, base.y - 0.03, smoothstep(0.15, 1.0, u)) + 0.5 * wave;
  return vec3(base.x + cos(a) * r, y, base.z + sin(a) * r);
}
// which part the settled heart makes this time round (its shape in
// `plexusForm`), a new one each time its settling begins again
int plexusMadeKind(float t) {
  const int kinds[5] = int[5](PLEXUS_PETAL, PLEXUS_LEAF, PLEXUS_BUD, PLEXUS_FLOWER, PLEXUS_STEM);
  float turn = plexStory > 0.5 ? plexStoryRound : floor(t / PLEXUS_HEART_SETTLE);
  return kinds[int(mod(turn, 5.0))];
}
// where the glowing spot the heart gathers energy in is at time `t`: on
// top of its rose
vec3 plexusMadeSpot(float t) { return plexusHeartLift(vec3(0.0, PLEXUS_ROSE_FOOT + 0.25, 0.0), t) + PLEXUS_MADE_SPOT; }
// how much of the glowing spot shows at time `t`: gathering once the heart
// has settled, spent as the part it makes is done
float plexusMadeGlow(float t) {
  if (plexStage < 3.5) return 0.0;
  float x = plexusSettleAt(t);
  return smoothstep(PLEXUS_MADE_GATHER, PLEXUS_MADE_FORM + 1.0, x) * (1.0 - smoothstep(PLEXUS_MADE_FORM + PLEXUS_MADE_FORMING - 1.0, PLEXUS_MADE_FORM + PLEXUS_MADE_FORMING + 1.0, x)) * plexusSettleKeep(t);
}
// what of the part the settled heart makes, point `id` (drifted by `moved`)
// at time `t`: where it is (xyz) and how much of it there is (w). Slowly,
// point by point, base first, each drifts up out of the glowing spot to its
// place in the part; whole, it rests there on top of the rose until taken
vec4 plexusHeartMade(float id, float t, vec3 moved) {
  if (plexStage < 3.5) return vec4(0.0);
  float x = plexusSettleAt(t);
  vec3 rel = (plexusForm(id, plexusMadeKind(t)) - vec3(0.0, 1.0, 0.0)) * PLEXUS_MADE_SIZE + moved;
  float a = PLEXUS_MADE_FORM + PLEXUS_MADE_FORMING * id / float(PLEXUS_POINTS);
  float env = smoothstep(a, a + 0.5, x) * plexusSettleKeep(t);
  return vec4(plexusMadeSpot(t) + rel * smoothstep(a, a + 1.5, x), env);
}
// where the middle of a tendril set to `height` (0 floating, 1 on the
// ground, 2 arcing) is, `u` of the way from one end to the other at time
// `t`: running from one end to the other, swaying a little side to side
vec3 plexusTendrilPath(float u, int height, float t) {
  float y = height == 0 ? 1.0 - 0.2 * sin(0.5 * TAU * u) : (height == 1 ? 0.06 : 0.3 + 1.4 * sin(0.5 * TAU * u));
  float sway = (height == 1 ? 0.02 : 0.08) * sin(u * 3.0 + t * 0.4) * sin(0.5 * TAU * u);
  return vec3(sway, y, (u - 0.5) * PLEXUS_TENDRIL_LEN);
}
// what of fragment `id` of a tendril set to `height` is at time `t`: where
// it is (xyz) and how much of it there is (w). Strand id/EACH of three
// braided round the tendril's middle, its fragments flowing on along it,
// each strand's turn breathing in and out as the flow passes, thinning
// away at either end where it meets what it joins
vec4 plexusTendril(float id, int height, float t) {
  float k = floor(id / float(PLEXUS_TENDRIL_EACH));
  float j = id - k * float(PLEXUS_TENDRIL_EACH);
  float u = fract(j / float(PLEXUS_TENDRIL_EACH) + t * PLEXUS_TENDRIL_FLOW + k * 0.013);
  vec3 c = plexusTendrilPath(u, height, t);
  vec3 dir = normalize(plexusTendrilPath(min(u + 0.01, 1.0), height, t) - plexusTendrilPath(max(u - 0.01, 0.0), height, t));
  vec3 e1 = normalize(cross(dir, vec3(0.0, 1.0, 0.0)));
  vec3 e2 = cross(e1, dir);
  float ang = k / float(PLEXUS_TENDRIL_STRANDS) * TAU + u * PLEXUS_TENDRIL_TURNS * TAU - t * 0.8;
  float r = PLEXUS_TENDRIL_R * (0.75 + 0.25 * sin(u * 20.0 - t * 2.0));
  float env = smoothstep(0.0, 0.06, u) * (1.0 - smoothstep(0.94, 1.0, u));
  return vec4(c + (cos(ang) * e1 + sin(ang) * e2) * r, env);
}
// what of the part riding a tendril set to `height`, point `id` (drifted
// by `moved`) at time `t`: where it is (xyz) and how much of it there is
// (w). A small petal carried along it over and over, from one end to the
// other, riding just over it, turning slowly as it goes
vec4 plexusTendrilRide(float id, int height, float t, vec3 moved) {
  float s = fract(t / PLEXUS_TENDRIL_RIDING);
  vec3 rel = turnAbout((plexusForm(id, PLEXUS_PETAL) - vec3(0.0, 1.0, 0.0)) * PLEXUS_TENDRIL_PART + moved * PLEXUS_TENDRIL_PART, vec3(0.0, 1.0, 0.0), t * 0.5);
  float env = smoothstep(0.0, 0.08, s) * (1.0 - smoothstep(0.92, 1.0, s));
  return vec4(plexusTendrilPath(s, height, t) + vec3(0.0, 0.12, 0.0) + rel, env);
}
// which point is the heart of a web of `shape`, where its beat starts: the
// spindle's middle, a petal's base, a leaf's stalk, a bud's base, a flower
// head's middle
float plexusHeart(int shape) { return shape == PLEXUS_CLUSTER ? float(PLEXUS_HEART) : 0.0; }
// where it is at time `t`: drifting round its rest, each axis on two slow
// waves of its own (a part only a little, keeping its form); a yielder's
// petal then carried round with it, what it yields on its own way
vec3 plexusAt(float id, int shape, float t) {
  if (shape >= PLEXUS_YIELD_FRAGMENT && shape <= PLEXUS_YIELD_GATHERING) return plexusYield(id, shape, t).xyz;
  vec3 f = mix(vec3(PLEXUS_SLOW), vec3(PLEXUS_QUICK), hash33(vec3(id, 11.3, 2.9)));
  vec3 g = mix(vec3(PLEXUS_SLOW), vec3(PLEXUS_QUICK), hash33(vec3(id, 5.7, 19.1)));
  vec3 ph = hash33(vec3(id, 23.9, 1.3)) * TAU;
  vec3 d = 0.6 * sin(t * f + ph) + 0.4 * sin(t * g * 1.7 + ph.yzx * 2.0);
  float drift = shape == PLEXUS_CLUSTER ? PLEXUS_DRIFT : PLEXUS_PART_DRIFT;
  vec3 moved = drift * d * vec3(1.0, 0.6, 1.0);
  if (shape >= PLEXUS_YIELD_PETAL && shape < PLEXUS_YIELD_PETAL + 5) return plexusPetal(plexusForm(id, PLEXUS_PETAL) + moved, shape - PLEXUS_YIELD_PETAL, t);
  if (shape >= PLEXUS_SPRIG_BRANCH && shape <= PLEXUS_SPRIG_LEAF_HIGH) return plexusSprig(id, shape, moved);
  if (shape == PLEXUS_HEART_STEM) return plexusHeartStem(id, t, moved);
  if (shape == PLEXUS_HEART_ROSE) return plexusHeartRose(id, t, moved);
  if (shape == PLEXUS_HEART_FILAMENT) return plexusHeartFilament(id, t);
  if (shape >= PLEXUS_HEART_GRAND && shape < PLEXUS_HEART_SEED) return plexusHeartGrand(id, shape - PLEXUS_HEART_GRAND, t, moved);
  if (shape == PLEXUS_HEART_SEED) return plexusHeartSeed(id, t).xyz;
  if (shape == PLEXUS_HEART_CURRENT) return plexusHeartCurrent(id, t);
  if (shape == PLEXUS_HEART_MADE) return plexusHeartMade(id, t, moved).xyz;
  if (shape == PLEXUS_HEART_MADE_GLOW) return plexusMadeSpot(t);
  if (shape >= PLEXUS_TENDRIL && shape < PLEXUS_TENDRIL_RIDE) return plexusTendril(id, shape - PLEXUS_TENDRIL, t).xyz;
  if (shape >= PLEXUS_TENDRIL_RIDE && shape < PLEXUS_TENDRIL_RIDE + 3) return plexusTendrilRide(id, shape - PLEXUS_TENDRIL_RIDE, t, moved).xyz;
  // a bloom, its petlets and what bursts from it: placed where they were
  // fastened, the heart's settling not carrying them down, then falling
  // free on their own
  plexDropOn = 0.0;
  vec3 r = plexusRest(id, shape) + moved;
  if (shape >= PLEXUS_HEART_BUD && shape < PLEXUS_HEART_FILAMENT) r = plexusBloomFall(plexusHeartBud(id, shape - PLEXUS_HEART_BUD, t, moved), shape - PLEXUS_HEART_BUD, t);
  if (shape >= PLEXUS_HEART_PETLET && shape < PLEXUS_HEART_GRAND) r = plexusBloomFall(plexusHeartPetlet(id, (shape - PLEXUS_HEART_PETLET) / 4, (shape - PLEXUS_HEART_PETLET) % 4, t, moved), (shape - PLEXUS_HEART_PETLET) / 4, t);
  if (shape == PLEXUS_HEART_BURST) r = plexusHeartBurst(id, t).xyz;
  plexDropOn = 1.0;
  return r;
}
// how much a line between `a` and `b` shows: whole within its reach's
// soft edge, gone beyond its reach
float plexusLink(vec3 a, vec3 b, float reach) { return 1.0 - smoothstep(reach * PLEXUS_SOFT, reach, length(b - a)); }
// where one light of point `id`'s pair is at time `t` (`twin` 1 the first,
// -1 its companion): circling the other round where the point has drifted
// to, each pair about an axis and at a pace of its own
vec3 plexusLight(float id, int shape, float t, float twin) {
  vec3 h = hash33(vec3(id, 41.7, 13.3));
  vec3 axis = normalize(h - 0.5 + vec3(0.0, 0.6, 0.0));
  vec3 side = normalize(cross(axis, abs(axis.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
  float spin = t * mix(PLEXUS_PAIR_SLOW, PLEXUS_PAIR_QUICK, h.z) + h.x * TAU;
  vec3 orbit = side * cos(spin) + cross(axis, side) * sin(spin);
  return plexusAt(id, shape, t) + orbit * PLEXUS_PAIR * twin * mix(1.0 - PLEXUS_PAIR_LEAN, PLEXUS_PAIR_LEAN, step(0.0, twin));
}
// a conduit's amber pulses: how fast they run (rad/s)
const float CORE_RUN_RATE = 2.6;
// thought climbing an arsthraxia's nerves: its colour (linear violet), how
// many pulses along a nerve at once, how fast they climb (rad/s), how long
// the surge of a unit done is (a share of the nerve)
const vec3 THOUGHT = vec3(0.42, 0.2, 1.0);
const float NERVE_PULSES = 3.0;
const float NERVE_RISE = 7.0;
const float NERVE_SURGE_W = 0.08;
// a stream of essence poured into a germinator's core: how far it ripples
// off its fall at the bottom
const float POUR_RIPPLE = 0.012;
// research energy's core quivers by this share of its size, more as it flares
const float ENERGY_QUIVER = 0.04;
const float ENERGY_QUIVER_FLARE = 0.12;
// the roles that are a structure's foliage (leaves, an ear): they unfold as
// it grows and breathe and lift in the wind
const uint FOLIAGE = PART_BIT(PART_LEAF) | PART_BIT(PART_EAR);
// grown along a growth spline (growth.glsl): how far into its own growth a
// leaf's tip lags its base
const float LEAF_LAG = 0.6;

// Catmull-Rom through b..c (a, d the neighbours) at f, and its tangent
vec3 catmull(vec3 a, vec3 b, vec3 c, vec3 d, float f) {
  return 0.5 * (2.0 * b + (c - a) * f + (2.0 * a - 5.0 * b + 4.0 * c - d) * f * f + (3.0 * b - a - 3.0 * c + d) * f * f * f);
}
vec3 catmullTan(vec3 a, vec3 b, vec3 c, vec3 d, float f) {
  return 0.5 * ((c - a) + 2.0 * (2.0 * a - 5.0 * b + 4.0 * c - d) * f + 3.0 * (3.0 * b - a - 3.0 * c + d) * f * f);
}

void main() {
  float t = pc.eye_time.w;
  int mode = int(ie.x + 0.5);
  mat4 M = mat4(c0, c1, c2, c3);
  // a skinned mesh: its vertex goes where its bones, blended by weight, take it
  if (mode == PLACE_SKINNED) {
    Bones B = Bones(pc.bones);
    int base = int(ie.y + 0.5);
    M = mat4(0.0);
    for (int k = 0; k < 4; k++) M += sweights[k] * bone(B, base, k);
  }
  // blended into its next key's shape (a bud opening, petal by petal)
  vec3 p = mix(pos, kpos, ik.x);
  vec3 nm = ik.x > 0.0 ? normalize(mix(nrm, knrm, ik.x)) : nrm;
  // grown along a growth spline (growth.glsl): a leaf unfolds from its
  // base, tips last
  float lag = PART_IN(FOLIAGE, part) ? LEAF_LAG * gat.y * tu.y : 0.0;
  p = growOut(p, gfrom, gat, iw.w, lag);
  // the belly (tu.y 3, its button 4; fill in iq.y): as it fills, creases
  // fold into it down its middle and across it, deepening the fuller it
  // is (in the bind pose, before the gut swells it, so they swell with
  // it; iq.zw the y and z where they cross, at its button). A smooth
  // field pushed in along the sac's normal, the normal turned by its
  // slope so the folds catch the light. The button surfaces from inside
  // the sap and pops out past it.
  if (tu.y > 2.5 && tu.y < 4.5) {
    const float CREASE = 0.024;  // depth when full
    const float DOWN_W = 0.019;  // the crease down the middle: its width
    const float ACROSS_W = 0.017; // the crease across it
    const float POP = 0.03;
    float fill = clamp(iq.y, 0.0, 1.0);
    vec3 d = p - vec3(0.0, iq.z, iq.w);
    // down the front, fading toward the ribs; across the front and sides
    float gv = exp(-d.x * d.x / (DOWN_W * DOWN_W)) * smoothstep(-0.02, 0.05, d.z) * (1.0 - smoothstep(0.06, 0.13, d.y));
    float gh = exp(-d.y * d.y / (ACROSS_W * ACROSS_W)) * smoothstep(-0.08, 0.02, d.z);
    float g = gv + gh - gv * gh;
    vec3 slope = vec3(-2.0 * d.x / (DOWN_W * DOWN_W) * gv * (1.0 - gh), -2.0 * d.y / (ACROSS_W * ACROSS_W) * gh * (1.0 - gv), 0.0);
    float depth = CREASE * fill;
    if (tu.y > 3.5) {
      p.z += POP * pow(fill, 1.5) - depth;
    } else {
      p -= nrm * depth * g;
      nm = normalize(nrm + depth * (slope - nrm * dot(slope, nrm)));
    }
  }
  // a conduit's living core (part 13, tu.x 0 where it comes up out of the
  // soil .. 1 where it goes back down): essence carried through it (iq.x
  // how far along, < 0 none; ie.yzw its colour) swells it as it passes,
  // pushing out between the strands woven round it, and leaves a fading
  // wake behind. A smooth field along it, so shared vertices move alike.
  float carried = 0.0;
  float wake = 0.0;
  if (part == PART_CORE && mode == PLACE_MATRIX && iq.x >= 0.0) {
    const float CARRY_W = 0.075; // how long a stretch the essence fills
    const float SWELL = 0.022;
    const float WAKE = 0.2;
    float d = tu.x - iq.x;
    carried = exp(-d * d / (CARRY_W * CARRY_W));
    wake = d < 0.0 ? exp(d / WAKE) * (1.0 - carried) : 0.0;
    p += nrm * SWELL * carried;
  }
  // secondary motion. Offsets must be identical for every copy of a shared
  // vertex (faceted parts carry different normals per face), so they use a
  // fixed axis scaled by position along the leaf: tips move, bases stay put.
  float sway = iw.x;
  vec4 wind = gardenWind(t, c3.xz);
  // grown structures move as the plants do: leaves and petals breathe
  // slowly and lift a little in the gusts, tips most, bases held
  bool foliage = PART_IN(FOLIAGE, part);
  if (sway > 0.0 && foliage) {
    p.y += tu.y * tu.y * (LEAF_LIFT * wind.z * sin(t * LEAF_LIFT_RATE + ip.z * 11.0 + tu.x * 3.0) + 0.01 * sin(t * 0.9 + ip.z * TAU));
  } else if (foliage) p.y += 0.03 * ip.y * tu.y * tu.y * sin(t * 7.0 + ip.z * 40.0 + tu.y * 2.0);
  if (part == PART_TENDRIL) p.y += 0.006 * sin(t * 2.0 + ip.z * 20.0 + tu.x * 9.0);
  // resin gives like dense gel: its surface follows the spring, its base on
  // the body holds (a smooth field of height, so shared vertices move alike)
  if (part == PART_RESIN) p += iq.yzw * smoothstep(0.0, 1.0, tu.y);
  bool drawn = ih.w >= 0.0;
  // the halo's diamond is gathered as its blooms close in (how far they
  // have come, haloPull), the radiant way (common.glsl gatherIn): its
  // facets come in as shards turning round it, each drawn in along its
  // face and growing as it comes, one after another from its foot up,
  // fitting together as the blooms meet; then it is still
  if (part == PART_PRISM && drawn) {
    float away = gatherAway(fragmentOf(tu.xy, col.a).order, PRISM_PACE, PRISM_SPAN, sqrt(haloPull(ih.w)));
    p = gatherIn(p, nrm * PRISM_REACH, away, 1.0, PRISM_TURN);
    nm = gatherTurn(nm, away, PRISM_TURN);
  }
  // the flash where the blooms met: a disc of light (tu.x its radius
  // 0..1) thrown outward from the diamond, fast then slowing (age 0..1)
  if (part == PART_FLASH) p.xz *= mix(FLASH_FROM, FLASH_TO, 1.0 - pow(1.0 - clamp(ip.y, 0.0, 1.0), 3.0));
  // a stream of essence poured along a curve (a germinator's): its fade is
  // how full it runs, and it ripples as it falls, more the further from
  // the lip (a smooth field along it, so shared vertices move alike)
  if (part == PART_ESSENCE && mode == PLACE_CURVE) {
    float k = clamp(p.y, 0.0, 1.0);
    p.xz *= ip.w;
    p.x += POUR_RIPPLE * k * sin(k * 13.0 - t * 9.0 + ip.z * TAU);
    p.z += POUR_RIPPLE * 0.7 * k * sin(k * 10.0 - t * 7.0 + ip.z * 17.0);
  }

  // research energy condensing in an arsthraxia's core (matrix-placed;
  // its wisps are curves): it quivers, a smooth field of its rest position
  // so shared vertices move alike, harder as it flares (flutter)
  if (part == PART_ENERGY && mode == PLACE_MATRIX) {
    float q = sin(t * 6.3 + dot(pos, vec3(5.0, 7.0, 3.0)) + ip.z * TAU) * sin(t * 4.1 - dot(pos, vec3(3.0, -4.0, 6.0)));
    p *= 1.0 + (ENERGY_QUIVER + ENERGY_QUIVER_FLARE * ip.y) * q;
  }
  vec4 w;
  vec3 wn;
  float twinkle = 1.0;
  // the constellate web: how far its beat runs to reach here (from its
  // heart, straight across), how much of it shows, what it is
  float plexBeat = 0.0;
  float plexFade = 1.0;
  // how bright it shines where the heart's webs crowd close (its rose and
  // the tight middle its stem becomes, its buds, its petlets), so their
  // lights do not run together into one white glare and the shape still
  // reads; 1 elsewhere
  float plexCrowd = 1.0;
  float plexKind = 0.0;
  float plexLayer = 0.0;
  // whether it is light a yielder gathers or yields: 1 a mote, 2 the
  // gathered point (bigger)
  float plexMote = 0.0;
  if (part == PART_PLEXUS) {
    // its points (colour r, g, b their ids), what it is (alpha), the
    // cluster's reach (pos.x); for a line or pane, which layer of the web
    // (pos.z: 0 the firsts', 1 the companions', each joining only its own
    // lights); every point drifting, the heart among them
    vec3 ids = floor(col.rgb * 255.0 + 0.5);
    float code = floor(col.a * 255.0 + 0.5);
    plexKind = mod(code, 4.0);
    // what shape the web holds (alpha's high part)
    int shape = int(code / 4.0);
    // the reach (pos.x), its whole part the heart's stage
    plexStage = floor(pos.x);
    // (the whole story: which stage it is at now, how far into it, and how
    // much shows as it fades out at the end and in at the start)
    if (plexStage > 4.5) {
      float total = 0.0;
      for (int k = 0; k < 5; k++) total += PLEXUS_STORY[k];
      float x = mod(t, total);
      plexStory = 1.0;
      plexStoryShow = smoothstep(0.0, PLEXUS_STORY_FADE, x) * (1.0 - smoothstep(total - PLEXUS_STORY_FADE, total, x));
      plexStage = 4.0;
      float start = 0.0;
      for (int k = 0; k < 5; k++) {
        if (x < start + PLEXUS_STORY[k]) { plexStage = float(k); break; }
        start += PLEXUS_STORY[k];
      }
      plexLocal = x - start;
      plexStoryRound = floor(t / total);
    }
    float reach = fract(pos.x);
    float twin = plexKind < 0.5 ? pos.y : 1.0 - 2.0 * pos.z;
    plexLayer = step(twin, 0.0);
    vec3 A = plexusLight(ids.x, shape, t, twin);
    vec3 B = plexusLight(ids.y, shape, t, twin);
    vec3 C = plexusLight(ids.z, shape, t, twin);
    // a bond (kind 3) joins point ids.x of its own web to point ids.y of
    // another (of shape ids.z): a yielder's core to each petal's base, the
    // point it gathers to each tip; a sprig's stem joint to what fastens
    // there
    if (plexKind > 2.5) B = plexusLight(ids.y, int(ids.z), t, twin);
    // a build's webs all beat from one heart: a yielder's from its core's,
    // a sprig's from its stem's foot
    int hs = shape >= PLEXUS_YIELD_CORE && shape <= PLEXUS_YIELD_GATHERING ? PLEXUS_YIELD_CORE : (shape >= PLEXUS_HEART_STEM ? PLEXUS_HEART_STEM : (shape >= PLEXUS_SPRIG_STEM ? PLEXUS_SPRIG_STEM : shape));
    // (a bloom burst free from a settling heart beats on its own, from its
    // base, and so does each of its petlets)
    bool bloomPart = (shape >= PLEXUS_HEART_BUD && shape < PLEXUS_HEART_FILAMENT) || (shape >= PLEXUS_HEART_PETLET && shape < PLEXUS_HEART_GRAND);
    if (plexStage > 3.5 && bloomPart) hs = shape;
    // (and so does a part the heart makes, from its own heart)
    if (shape == PLEXUS_HEART_MADE) hs = shape;
    // the heart's stem reaches further as it becomes its grand flower
    if (shape == PLEXUS_HEART_STEM) reach *= mix(1.0, 0.82, plexusHeartMorph(t));
    // (the part the heart makes joins as far as that part does on its own)
    if (shape == PLEXUS_HEART_MADE) {
      int mk = plexusMadeKind(t);
      reach = PLEXUS_MADE_SIZE * (mk == PLEXUS_LEAF ? 0.22 : (mk == PLEXUS_BUD ? 0.2 : (mk == PLEXUS_FLOWER ? 0.21 : 0.17)));
    }
    // in the chain reaction the heart's webs reach as far as it has grown
    // (all through the story, built at its risen size)
    if ((plexStage > 2.5 || plexStory > 0.5) && ((shape >= PLEXUS_HEART_STEM && shape < PLEXUS_HEART_SEED) || shape == PLEXUS_HEART_ROSE)) reach *= plexusHeartSize(t) / 0.7;
    vec3 H = plexusAt(plexusHeart(hs), hs, t);
    // how much there is of what a yielder yields, as it grows and is let go
    // (or of a heart's filament as it drips down)
    float yield = shape >= PLEXUS_YIELD_FRAGMENT && shape <= PLEXUS_YIELD_GATHERING ? plexusYield(ids.x, shape, t).w : 1.0;
    if (shape == PLEXUS_HEART_FILAMENT) yield = smoothstep(0.0, 0.1, plexusHeartGrow(floor(ids.x / 8.0), t));
    // (or of a petlet's points as their fragments arrive, a line or pane
    // there once all its points are, a grand petal as it opens, a
    // fragment on its way)
    if (shape >= PLEXUS_HEART_PETLET && shape < PLEXUS_HEART_GRAND) {
      int pk = (shape - PLEXUS_HEART_PETLET) / 4;
      int pj = (shape - PLEXUS_HEART_PETLET) % 4;
      yield = min(min(plexusChainPetlet(pk, pj, ids.x, t), plexusChainPetlet(pk, pj, ids.y, t)), plexusChainPetlet(pk, pj, ids.z, t));
    }
    if (shape >= PLEXUS_HEART_GRAND && shape < PLEXUS_HEART_SEED) yield = smoothstep(0.0, 0.3, plexusChainGrand(shape - PLEXUS_HEART_GRAND, t));
    if (shape == PLEXUS_HEART_SEED) yield = plexusHeartSeed(ids.x, t).w;
    // (or of a rose petal as its ring opens)
    if (shape == PLEXUS_HEART_ROSE) yield = smoothstep(0.0, 0.25, plexusRoseOpen(floor(ids.x / 50.0), t));
    // (or of a fragment burst from a bloom, or a current, faint, each of
    // its lines as much as its fainter end)
    if (shape == PLEXUS_HEART_BURST) yield = plexusHeartBurst(ids.x, t).w;
    if (shape == PLEXUS_HEART_CURRENT) yield = min(min(plexusCurrentShow(ids.x, t), plexusCurrentShow(ids.y, t)), plexusCurrentShow(ids.z, t));
    // (or of the part the heart makes, each line and pane once its points
    // are there, or of the glowing spot it gathers in)
    if (shape == PLEXUS_HEART_MADE) yield = min(min(plexusHeartMade(ids.x, t, vec3(0.0)).w, plexusHeartMade(ids.y, t, vec3(0.0)).w), plexusHeartMade(ids.z, t, vec3(0.0)).w);
    if (shape == PLEXUS_HEART_MADE_GLOW) yield = plexusMadeGlow(t);
    // (or of a tendril's fragments, thinning at its ends, each line and
    // pane as much as its faintest point, or of the part riding it)
    if (shape >= PLEXUS_TENDRIL && shape < PLEXUS_TENDRIL_RIDE) yield = min(min(plexusTendril(ids.x, shape - PLEXUS_TENDRIL, t).w, plexusTendril(ids.y, shape - PLEXUS_TENDRIL, t).w), plexusTendril(ids.z, shape - PLEXUS_TENDRIL, t).w);
    if (shape >= PLEXUS_TENDRIL_RIDE && shape < PLEXUS_TENDRIL_RIDE + 3) yield = plexusTendrilRide(ids.x, shape - PLEXUS_TENDRIL_RIDE, t, vec3(0.0)).w;
    yield *= plexStoryShow;
    if (shape == PLEXUS_HEART_STEM) plexCrowd = mix(1.0, 0.35, plexusHeartMorph(t));
    if (shape == PLEXUS_HEART_ROSE || (shape >= PLEXUS_HEART_BUD && shape < PLEXUS_HEART_FILAMENT)) plexCrowd = 0.45;
    if (shape >= PLEXUS_HEART_PETLET && shape < PLEXUS_HEART_GRAND) plexCrowd = 0.6;
    if (shape >= PLEXUS_TENDRIL && shape < PLEXUS_TENDRIL_RIDE) plexCrowd = 0.55;
    plexMote = shape == PLEXUS_YIELD_LIGHT ? 1.0 : (shape == PLEXUS_YIELD_GATHERING || shape == PLEXUS_HEART_MADE_GLOW ? 2.0 : 0.0);
    // a stem's joints, where things fasten, hold larger lights
    bool stemmed = shape == PLEXUS_STEM || shape == PLEXUS_SPRIG_STEM || shape == PLEXUS_SPRIG_BRANCH || shape == PLEXUS_HEART_STEM;
    float swell = stemmed && plexusJoint(ids.x) ? 1.5 : 1.0;
    // how thin this layer's lines are: the companions' as their lights
    float thin = mix(PLEXUS_COMPANION, 1.0, step(0.0, twin));
    vec3 lp;
    if (plexKind < 0.5) {
      // a point: one light of its pair (pos.y 1 the first, -1 its
      // companion, the smaller)
      lp = A + nrm * (plexMote > 0.5 ? PLEXUS_MOTE_R * (1.0 + plexMote) : PLEXUS_POINT_R * swell) * thin * yield;
#ifdef AIR
      lp = A + (lp - A) * AIR_SPREAD;
#endif
      w = M * vec4(lp, 1.0);
      wn = mat3(M) * nrm;
    } else if (plexKind < 1.5 || plexKind > 2.5) {
      // a line (tu.x along it, tu.y which side): a ribbon turned to the
      // eye, pointed at both ends, thinning to nothing as its points part;
      // a bond always holds
      plexFade = (plexKind > 2.5 ? 1.0 : plexusLink(A, B, reach)) * yield;
      // (the bond fastening a settling heart's bloom snaps as it bursts free)
      if (plexKind > 2.5 && plexStage > 3.5 && shape == PLEXUS_HEART_STEM) plexFade *= 1.0 - smoothstep(0.0, 0.4, plexusSettleAt(t) - plexusSettleLet(int(ids.z) - PLEXUS_HEART_BUD)) * plexusSettleKeep(t);
      lp = mix(A, B, tu.x);
      vec3 wc = (M * vec4(lp, 1.0)).xyz;
      vec3 T = mat3(M) * (B - A);
      vec3 toEye = normalize(pc.eye_time.xyz - wc);
      vec3 across = cross(T, toEye);
      vec3 right = across / max(length(across), 1e-6);
      float pinch = sqrt(max(sin(0.5 * TAU * tu.x), 0.0));
      float lineW = PLEXUS_LINE_W;
#ifdef AIR
      lineW *= AIR_SPREAD;
#endif
      w = vec4(wc + right * tu.y * lineW * thin * pinch * plexFade, 1.0);
      wn = toEye;
    } else {
      // a pane (tu its corner's weights, pos.y its face): it shows while
      // all three of its lines do, drawn in toward its middle as any of
      // them breaks
      plexFade = min(min(plexusLink(A, B, reach), plexusLink(A, C, reach)), plexusLink(B, C, reach)) * yield;
      vec3 mid = (A + B + C) / 3.0;
      vec3 corner = A * tu.x + B * tu.y + C * (1.0 - tu.x - tu.y);
      vec3 cr = cross(B - A, C - A);
      vec3 n = cr / max(length(cr), 1e-6) * pos.y;
      lp = mid + (corner - mid) * 0.85 * plexFade + n * PLEXUS_PANE;
      w = M * vec4(lp, 1.0);
      wn = mat3(M) * n;
    }
    plexBeat = length(lp - H);
  } else if (mode == PLACE_CURVE) {
    // a curve (the tail): the mesh runs straight up +Y over 0..1; each point
    // goes to that fraction along the Catmull-Rom curve through c0..c3 (the
    // ends extended in line), its x laid toward the side (tint.xyz) and its
    // z across, so the vine bends here instead of being rebuilt each frame
    vec3 P[4] = vec3[4](c0.xyz, c1.xyz, c2.xyz, c3.xyz);
    // a beam from a bloom a forming halo draws in follows it: its ends
    // (ie.z 1 first, 2 last) spiral with the bloom, the points between by
    // how near they lie to it
    if (drawn) {
      int ends = int(ie.z + 0.5);
      float w0 = (ends & 1) != 0 ? 1.0 : 0.0;
      float w3 = (ends & 2) != 0 ? 1.0 : 0.0;
      for (int k = 0; k < 4; k++) P[k] = mix(P[k], haloSpiral(P[k], ih.xyz, ih.w), mix(w0, w3, float(k) / 3.0));
    }
    // how far along it reaches (a bloom thread extends as its bloom finishes)
    float u = clamp(p.y, 0.0, ie.y) * 3.0;
    int i = min(int(u), 2);
    float f = u - float(i);
    vec3 b = P[i], c = P[i + 1];
    vec3 a = i == 0 ? 2.0 * b - c : P[i - 1];
    vec3 d = i == 2 ? 2.0 * c - b : P[i + 2];
    vec3 T = normalize(catmullTan(a, b, c, d, f));
    vec3 C = catmull(a, b, c, d, f);
    if (part == PART_THREAD) {
      // soft rays: a spindle of light, narrow where it leaves one bloom and
      // reaches the other, widest between, its width (x, -1..1) turned to
      // face the eye from every side
      vec3 toEye = normalize(pc.eye_time.xyz - C);
      vec3 right = normalize(cross(T, toEye) + vec3(1e-5, 0.0, 0.0));
      // a halo's edge (flutter 1) runs even from corner to corner, so the
      // edges join into one ring
      float spindle = ip.y > 0.5 ? 0.7 : mix(0.3, 1.0, pow(sin(0.5 * TAU * clamp(tu.x, 0.0, 1.0)), 0.6));
      w = vec4(C + right * p.x * BEAM_HALF_WIDTH * spindle, 1.0);
      wn = toEye;
    } else {
      vec3 B = normalize(tint.xyz - T * dot(tint.xyz, T));
      vec3 N = cross(B, T);
      w = vec4(C + B * p.x + N * p.z, 1.0);
      // the mesh was squeezed to 0..1 along its length: undo that on its normals
      wn = B * nrm.x + T * (nrm.y / ie.w) + N * nrm.z;
    }
  } else if (mode == PLACE_BURST) {
    // a burst (ie.y how far through its life, 0..1): each bead flies out
    // the way it lies (its centre a radius in from its skin), fast then
    // slowing; motes of light (tu.y below 0.5) drift up, drops of sap arc
    // down; each its own pace (tu.y), all swelling in at once and shrinking
    // away over the burst's life
    float age = clamp(ie.y, 0.0, 1.0);
    bool drop = tu.y >= 0.5;
    float pace = mix(0.65, 1.3, fract(tu.y * 2.0));
    vec3 c = pos - nrm * BURST_BEAD;
    vec3 at = c * (1.0 - pow(1.0 - age, 3.0)) * pace;
    at.y += drop ? -BURST_FALL * age * age : BURST_RISE * age * pace;
    float size = (1.0 - age) * (drop ? 1.0 : 0.65) * smoothstep(0.0, 0.06, age);
    w = M * vec4(at + nrm * BURST_BEAD * size, 1.0);
    wn = mat3(M) * nrm;
  } else if (mode == PLACE_MOTE) {
    // a star mote: it turns slowly, tilts, twinkles and, resting, hovers
    // with a slow breath; falling, its echoes (ie.w 1..3) trail above it,
    // fading and shrinking
    float ph = ie.y;
    float echo = ie.w;
    twinkle = 0.75 + 0.25 * sin(t * 3.1 + ph * 40.0) * sin(t * 1.7 + ph * 13.0);
    float turn = t * MOTE_TURN + ph * TAU - max(echo, 0.0) * 0.3;
    float tilt = echo > 0.5 ? 0.0 : 0.25 * sin(t * 0.5 + ph * 9.0);
    float size = (0.55 + 0.55 * ie.z) * (0.9 + 0.1 * twinkle) * (1.0 - 0.22 * max(echo, 0.0));
    float hover = echo < 0.0 ? 0.05 * sin(t * 1.1 + ph * 30.0) : 0.0;
    mat3 R = mat3(cos(turn), 0.0, -sin(turn), 0.0, 1.0, 0.0, sin(turn), 0.0, cos(turn))
           * mat3(cos(tilt), sin(tilt), 0.0, -sin(tilt), cos(tilt), 0.0, 0.0, 0.0, 1.0);
    w = vec4(c3.xyz + vec3(0.0, hover + ECHO_RISE * max(echo, 0.0), 0.0) + R * p * size, 1.0);
    wn = R * nrm;
    if (echo > 0.5) twinkle = 1.0;
  } else {
    w = M * vec4(p, 1.0);
#ifdef SHADOW
    // a shadow caster needs no normals
    wn = nm;
    if (false) {
#else
    if (mode == PLACE_SKINNED) {
#endif
      // a skinned mesh's bones may swell it unevenly (the belly): its
      // normals take the inverse-transpose of how the skin truly moves
      // there, the blended bones plus where each bone would take this
      // point times how fast its weight changes across the skin (without
      // that, where a swollen sac hangs from the body the normals turn
      // away from a surface still facing the eye)
      Bones B = Bones(pc.bones);
      int base = int(ie.y + 0.5);
      mat3 J = mat3(M);
      // (where each bone would take it, from where the blend does: the
      // slopes need not sum to nothing once the slightest bones are
      // dropped, and the wolf's place in the world must not leak in)
      vec4 hp = vec4(p, 1.0);
      for (int k = 0; k < 4; k++) {
        vec3 at = (bone(B, base, k) * hp).xyz - w.xyz;
        J += mat3(at * sgx[k], at * sgy[k], at * sgz[k]);
      }
      wn = transpose(inverse(J)) * nm;
    } else wn = mat3(M) * nm;
    // a shadow under a bloom a forming halo draws in follows it over the
    // ground (fading as the bloom folds, below)
    if (drawn && part == PART_SHADOW) w.xz += haloSpiral(c3.xyz, ih.xyz, ih.w).xz - c3.xz;
  }
  // ... and bend from their root in the garden's wind, as the plants do:
  // more toward the top, the lean slow and late at the tip (a smooth field
  // of world height, so shared vertices move alike)
  if (sway > 0.0) {
    vec3 root = c3.xyz - vec3(0.0, iw.z, 0.0);
    float h = clamp((w.y - root.y) / iw.y, 0.0, 1.5);
    float ang = windLean(t, wind, ip.z * TAU, h, sway) * h * h;
    w.xyz = root + bendIn(w.xyz - root, wind.xy, ang);
    wn = bendIn(wn, wind.xy, ang);
  }
  v_pos = w.xyz;
  v_nrm = normalize(wn);
  vec3 c = srgb2lin(col.rgb);
  // (the ring's tint is its points' light, not a colour)
  v_col = (mode == PLACE_CURVE || part == PART_HALO) ? c : mix(c, c * tint.rgb, tint.w);
  // essence is the colour of what it is (sRGB; along a curve in iq.yzw)
  if (part == PART_ESSENCE) v_col = c * srgb2lin(clamp(mode == PLACE_CURVE ? iq.yzw : tint.rgb, 0.0, 1.0));
  // sap pulses travel along the part
  float pulse = 0.65 + 0.35 * sin(t * PULSE_RATE - tu.x * 8.0 + ip.z * TAU);
  v_glow = ip.x * ((part == PART_BLOOM || part == PART_THREAD) ? 1.0 : DIM_GLOW) * pulse * twinkle;
  // a flash, a halo's projection and research energy shine as bright as
  // their glow, never pulsing, as does a spark (it flickers on its own);
  // a prism has no light of its own
  if (part == PART_FLASH || part == PART_PROJECTION || part == PART_ENERGY || part == PART_SPARK) v_glow = ip.x;
  // the ring: an arc is as bright as the points at its ends (tint holds
  // the four points' light, east, south, west, north; tu.x its angle)
  if (part == PART_HALO) {
    float a = fract(tu.x) * 4.0;
    int i = int(a) % 4;
    v_glow = mix(tint[i], tint[(i + 1) % 4], fract(a));
  }
  if (part == PART_PRISM) v_glow = 0.0;
  // essence carries as much light of its own as its glow, never pulsing
  if (part == PART_ESSENCE) v_glow = ip.x;
  // a conduit's core: its sap forever runs the way it carries, in faint
  // amber pulses (brighter while it is busy, ip.x); essence carried
  // through it takes it over in its own colour, its wake fading behind
  if (part == PART_CORE) {
    float run = pow(0.5 + 0.5 * sin(tu.x * TAU * 2.0 - t * CORE_RUN_RATE + ip.z * TAU), 6.0);
    v_col = mix(v_col, AMBER * 0.8, run * 0.6);
    v_col = mix(v_col, srgb2lin(clamp(ie.yzw, 0.0, 1.0)), max(carried, wake * 0.6));
    v_glow = run * (0.1 + 0.2 * ip.x) + carried * 0.55 + wake * 0.2;
  }
  // an arsthraxia's nerve (tu.x 0 at its roots .. 1 at its crown, or out
  // along an offshoot): while it studies (ip.x) thought climbs it in violet
  // pulses, and a unit done (ip.y, 1 fading to 0) sends one surge up it from
  // the roots, its front climbing as the flare fades. At rest, dark wood.
  if (part == PART_NERVE) {
    float study = clamp(ip.x, 0.0, 1.0);
    float rise = pow(0.5 + 0.5 * sin(tu.x * TAU * NERVE_PULSES - t * NERVE_RISE + ip.z * TAU), 6.0) * study;
    float front = tu.x - (1.0 - ip.y);
    float surge = ip.y > 0.0 ? exp(-front * front / (NERVE_SURGE_W * NERVE_SURGE_W)) * sqrt(ip.y) : 0.0;
    float lit = max(rise, surge);
    v_col = mix(v_col, THOUGHT, lit * 0.85);
    v_glow = rise * 0.45 + surge * 1.1 + study * 0.03;
  }
  v_part = float(part);
  v_t = tu.x;
  // a beam carries its length instead, so its rays and motes keep their size
  v_fade = part == PART_THREAD ? length(c3.xyz - c0.xyz) : ip.w;
  // the halo's ring and its projection carry their radius (their scale)
  if (part == PART_HALO || part == PART_PROJECTION) v_fade = length(c0.xyz);
  if (drawn && part == PART_SHADOW) v_fade *= 1.0 - haloFold(ih.w);
  v_u = tu.y;
  v_sheet = vec2(tu.y, tu.z);
  // the constellate web carries how far its beat runs to reach here, what
  // it is, and how much of it shows (as its glow)
  if (part == PART_PLEXUS) {
    v_t = plexBeat;
    // what it is, 4 more on the companions' layer, 8 more for a mote of light
    v_u = plexKind + 4.0 * plexLayer + 8.0 * step(0.5, plexMote);
    // (a pane shines whole, crowded or not, so the rose's petals read)
    v_glow = plexFade * (plexKind > 1.5 && plexKind < 2.5 ? 1.0 : plexCrowd);
  }
  v_obj = p;
  // a constellate line: how far across it (-1 to 1), for its glow
  if (part == PART_PLEXUS) v_obj = vec3(tu.y, 0.0, 0.0);
  v_phase = ip.z;
  v_aux = ip.y;
  // the halo's ring and the rays making it appear as its diamond forms
  // (from its shards, as its blooms close in)
  if (part == PART_HALO || part == PART_PROJECTION) v_aux = drawn ? sqrt(haloPull(ih.w)) : 1.0;
#ifdef AIR
  // the air round what glows: any glow but the constellate's swelled out
  // along its normal into a soft shell; what does not glow, and the
  // constellate's panes (glass, not light), unseen
  if (PART_IN(PARTS_LIGHT, part) && part != PART_PLEXUS) w.xyz += normalize(wn) * AIR_REACH;
#endif
  gl_Position = project(w.xyz);
#ifdef AIR
  if (!PART_IN(PARTS_LIGHT, part) || (part == PART_PLEXUS && plexKind > 1.5 && plexKind < 2.5)) gl_Position = UNSEEN;
#endif
#ifndef SHADOW
  // a skinned mesh may hide what some of its bones carry (the wolf's head,
  // seen from its own eyes): ie.zw a mask of bones, 24 to a float. Clipped
  // where those bones carry it more than half, so the cut follows the skin
  // weights, clean across the mesh; its shadow is still cast.
  float hidden = 0.0;
  if (mode == PLACE_SKINNED && ie.z + ie.w > 0.0) {
    for (int k = 0; k < 4; k++) {
      uint b = (sbones >> (8u * uint(k))) & 255u;
      uint word = b < 24u ? uint(ie.z) : uint(ie.w);
      hidden += sweights[k] * float((word >> (b % 24u)) & 1u);
    }
  }
  gl_ClipDistance[0] = 0.5 - hidden;
#endif
#ifdef SHADOW
  // what is light itself casts no shadow (a star mote, PARTS_LIGHT: a beam,
  // a halo's flash, ring and rays), nor does the soft shadow under a floater
  // or a placement preview
  if (mode == PLACE_MOTE || mode == PLACE_BURST || part == PART_SHADOW || PART_IN(PARTS_LIGHT, part) || (iflags & PART_GHOST) != 0u) gl_Position = UNSEEN;
#endif
}

