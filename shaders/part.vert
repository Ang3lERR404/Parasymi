#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
// the solid and glass passes rasterize it at the very same depth (the
// glass pass tests `less` against what the solid one wrote)
invariant gl_Position;

// per-vertex (mesh library)
layout(location = 0) in vec3 pos;
layout(location = 1) in vec3 nrm;
layout(location = 2) in vec4 col;
layout(location = 3) in vec2 tu;
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
// per-vertex skin (skinned meshes only): four bone indices, one per byte, and their weights
layout(location = 16) in uint sbones;
layout(location = 17) in vec4 sweights;
// how each of those weights changes across the mesh: its x, y and z
layout(location = 18) in vec4 sgx;
layout(location = 19) in vec4 sgy;
layout(location = 20) in vec4 sgz;
// per-vertex growth (structures grown along growth splines, gfx/growth.zig):
// where it grows out of, and when it begins, how long it takes, when its
// spline began and was done (gat.y 0: not on a spline)
layout(location = 21) in vec3 gfrom;
layout(location = 22) in vec4 gat;

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

// how an instance is placed (vertex.zig `PartInstance.e.x`; must match)
const int PLACE_MATRIX = 0;
const int PLACE_CURVE = 1;   // along a Catmull-Rom curve (the tail, beams)
const int PLACE_MOTE = 2;    // a star mote
const int PLACE_SKINNED = 3; // by its bones

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
// sap pulses running along a part (rad/s), and a part's own glow beside a
// glowing sap part's
const float PULSE_RATE = 3.0;
const float DIM_GLOW = 0.06;
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
// grown along a growth spline: how thin it is while its spline is still
// growing, and how far into its own growth a leaf's tip lags its base
const float SPROUT_THIN = 0.5;
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
  vec3 p = pos;
  vec3 nm = nrm;
  // grown along a growth spline: shrunk into it (or the point it grows
  // from) until its front comes by, then grown out, thin at first and
  // thickening as its spline finishes; a leaf unfolds from its base, tips
  // last. Shrunk about a point, so its normal holds.
  bool on_spline = gat.y > 0.0;
  if (on_spline) {
    float lag = PART_IN(FOLIAGE, part) ? LEAF_LAG * gat.y * tu.y : 0.0;
    float out_ = smoothstep(gat.x + lag, gat.x + gat.y, iw.w);
    if (gat.w > gat.z) out_ *= mix(SPROUT_THIN, 1.0, smoothstep(gat.z, gat.w, iw.w));
    p = gfrom + (p - gfrom) * out_;
  }
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
    float away = gatherAway(fragmentOf(tu, col.a).order, PRISM_PACE, PRISM_SPAN, sqrt(haloPull(ih.w)));
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
  if (mode == PLACE_CURVE) {
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
  // their glow, never pulsing; a prism has no light of its own
  if (part == PART_FLASH || part == PART_PROJECTION || part == PART_ENERGY) v_glow = ip.x;
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
  v_obj = p;
  v_phase = ip.z;
  v_aux = ip.y;
  // the halo's ring and the rays making it appear as its diamond forms
  // (from its shards, as its blooms close in)
  if (part == PART_HALO || part == PART_PROJECTION) v_aux = drawn ? sqrt(haloPull(ih.w)) : 1.0;
  gl_Position = project(w.xyz);
#ifdef SHADOW
  // what is light itself casts no shadow (a star mote, PARTS_LIGHT: a beam,
  // a halo's flash, ring and rays), nor does the soft shadow under a floater
  // or a placement preview
  if (mode == PLACE_MOTE || part == PART_SHADOW || PART_IN(PARTS_LIGHT, part) || (iflags & PART_GHOST) != 0u) gl_Position = UNSEEN;
#endif
}

