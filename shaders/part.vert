#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

// per-vertex (mesh library)
layout(location = 0) in vec3 pos;
layout(location = 1) in vec3 nrm;
layout(location = 2) in vec4 col;
layout(location = 3) in vec2 tu;
layout(location = 4) in uint part;  // 0 vine 1 leaf 2 sap/glow 3 claw/thorn 4 root 5 sap-lined leaf (ear) 6 resin
// per-instance
layout(location = 5) in vec4 c0;
layout(location = 6) in vec4 c1;
layout(location = 7) in vec4 c2;
layout(location = 8) in vec4 c3;
layout(location = 9) in vec4 ip;    // glow, flutter, phase, fade
layout(location = 10) in vec4 tint; // rgb multiply, w amount
layout(location = 11) in vec4 iq;   // sag, give (resin surface push)
layout(location = 12) in vec4 iw;   // sway, height of the sway, how far below the origin it is rooted, grown
layout(location = 13) in vec4 ie;   // placement: 0 matrix, 1 curve (tail), 2 star mote; then its parameters
layout(location = 14) in vec4 ih;   // a forming halo it belongs to: its centre, how far along (< 0 none)

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
  vec3 p = pos;
  // a full sac sags: pushed out along its radius, most at the bottom and
  // front. A field of position, so the vine net on it follows the surface.
  // a filling sac swells from its centre, most low and forward, only where
  // it is gut (tu.x), so its tongue stays put on the chest; a smooth field
  // of position, so the net and leaves on it move with it
  if (iq.x > 0.0) {
    vec3 r = normalize(pos + vec3(0.0, 0.0, 1e-4));
    p += r * iq.x * tu.x * (0.6 + 0.6 * max(-r.y, 0.0) + 0.4 * max(r.z, 0.0));
  }
  // the belly button (tu.y 2) surfaces from inside the sap as the belly
  // fills (fill in iq.y), and pops out past it when full
  if (tu.y > 1.5) p.z += 0.04 * pow(clamp(iq.y, 0.0, 1.0), 1.5);
  // secondary motion. Offsets must be identical for every copy of a shared
  // vertex (faceted parts carry different normals per face), so they use a
  // fixed axis scaled by position along the leaf: tips move, bases stay put.
  float sway = iw.x;
  // a growing structure's leaves and petals come up folded and open from
  // the bottom up, tips last (weighted along the leaf so its base holds)
  if (iw.w < 1.0 && (part == 1u || part == 5u)) {
    float open = smoothstep(pos.y / iw.y * 0.7, pos.y / iw.y * 0.7 + 0.35, iw.w);
    p.xz *= mix(1.0, mix(0.2, 1.0, open), tu.y);
  }
  vec4 wind = gardenWind(t, c3.xz);
  // grown structures move as the plants do: leaves and petals breathe
  // slowly and lift a little in the gusts, tips most, bases held
  if (sway > 0.0 && (part == 1u || part == 5u)) {
    p.y += tu.y * tu.y * (0.012 * wind.z * sin(t * 1.7 + ip.z * 11.0 + tu.x * 3.0) + 0.01 * sin(t * 0.9 + ip.z * TAU));
  } else if (part == 1u || part == 5u) p.y += 0.03 * ip.y * tu.y * tu.y * sin(t * 7.0 + ip.z * 40.0 + tu.y * 2.0);
  if (part == 4u) p.y += 0.006 * sin(t * 2.0 + ip.z * 20.0 + tu.x * 9.0);
  // resin gives like dense gel: its surface follows the spring, its base on
  // the body holds (a smooth field of height, so shared vertices move alike)
  if (part == 6u) p += iq.yzw * smoothstep(0.0, 1.0, tu.y);
  bool drawn = ih.w >= 0.0;
  // the halo's diamond forms as its blooms close in (how far they have come,
  // haloPull): its facets gather from shards turning in around it, each
  // drawn in along its face and growing as it comes, fitting together as
  // the blooms meet; then it is still
  if (part == 10u && drawn) {
    float form = sqrt(haloPull(ih.w));
    float a = (1.0 - form) * 3.0;
    p = p * form + nrm * (1.0 - form) * 0.45;
    p.xz = mat2(cos(a), -sin(a), sin(a), cos(a)) * p.xz;
  }
  // the flash where the blooms met: a disc of light (tu.x its radius
  // 0..1) thrown outward from the diamond, fast then slowing (age 0..1)
  if (part == 9u) p.xz *= mix(0.1, 3.2, 1.0 - pow(1.0 - clamp(ip.y, 0.0, 1.0), 3.0));

  vec4 w;
  vec3 wn;
  float twinkle = 1.0;
  if (mode == 1) {
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
    if (part == 8u) {
      // soft rays: a spindle of light, narrow where it leaves one bloom and
      // reaches the other, widest between, its width (x, -1..1) turned to
      // face the eye from every side
      vec3 toEye = normalize(pc.eye_time.xyz - C);
      vec3 right = normalize(cross(T, toEye) + vec3(1e-5, 0.0, 0.0));
      // a halo's edge (flutter 1) runs even from corner to corner, so the
      // edges join into one ring
      float spindle = ip.y > 0.5 ? 0.7 : mix(0.3, 1.0, pow(sin(0.5 * TAU * clamp(tu.x, 0.0, 1.0)), 0.6));
      w = vec4(C + right * p.x * 0.42 * spindle, 1.0);
      wn = toEye;
    } else {
      vec3 B = normalize(tint.xyz - T * dot(tint.xyz, T));
      vec3 N = cross(B, T);
      w = vec4(C + B * p.x + N * p.z, 1.0);
      // the mesh was squeezed to 0..1 along its length: undo that on its normals
      wn = B * nrm.x + T * (nrm.y / ie.w) + N * nrm.z;
    }
  } else if (mode == 2) {
    // a star mote: it turns slowly, tilts, twinkles and, resting, hovers
    // with a slow breath; falling, its echoes (ie.w 1..3) trail above it,
    // fading and shrinking
    float ph = ie.y;
    float echo = ie.w;
    twinkle = 0.75 + 0.25 * sin(t * 3.1 + ph * 40.0) * sin(t * 1.7 + ph * 13.0);
    float turn = t * 0.35 + ph * TAU - max(echo, 0.0) * 0.3;
    float tilt = echo > 0.5 ? 0.0 : 0.25 * sin(t * 0.5 + ph * 9.0);
    float size = (0.55 + 0.55 * ie.z) * (0.9 + 0.1 * twinkle) * (1.0 - 0.22 * max(echo, 0.0));
    float hover = echo < 0.0 ? 0.05 * sin(t * 1.1 + ph * 30.0) : 0.0;
    mat3 R = mat3(cos(turn), 0.0, -sin(turn), 0.0, 1.0, 0.0, sin(turn), 0.0, cos(turn))
           * mat3(cos(tilt), sin(tilt), 0.0, -sin(tilt), cos(tilt), 0.0, 0.0, 0.0, 1.0);
    w = vec4(c3.xyz + vec3(0.0, hover + 0.16 * max(echo, 0.0), 0.0) + R * p * size, 1.0);
    wn = R * nrm;
    if (echo > 0.5) twinkle = 1.0;
  } else {
    w = M * vec4(p, 1.0);
    wn = mat3(M) * nrm;
    // a shadow under a bloom a forming halo draws in follows it over the
    // ground (fading as the bloom folds, below)
    if (drawn && part == 7u) w.xz += haloSpiral(c3.xyz, ih.xyz, ih.w).xz - c3.xz;
  }
  // ... and bend from their root in the garden's wind, as the plants do:
  // more toward the top, the lean slow and late at the tip (a smooth field
  // of world height, so shared vertices move alike)
  if (sway > 0.0) {
    vec3 root = c3.xyz - vec3(0.0, iw.z, 0.0);
    float h = clamp((w.y - root.y) / iw.y, 0.0, 1.5);
    float own = sin(t * 0.85 - wind.w * 0.3 + ip.z * TAU - h * 0.9);
    float ang = sway * (0.05 * wind.z + 0.025 * (0.4 + wind.z) * own) * h * h;
    w.xyz = root + bendIn(w.xyz - root, wind.xy, ang);
    wn = bendIn(wn, wind.xy, ang);
  }
  v_pos = w.xyz;
  v_nrm = normalize(wn);
  vec3 c = srgb2lin(col.rgb);
  // (the ring's tint is its points' light, not a colour)
  v_col = (mode == 1 || part == 11u) ? c : mix(c, c * tint.rgb, tint.w);
  // sap pulses travel along the part
  float pulse = 0.65 + 0.35 * sin(t * 3.0 - tu.x * 8.0 + ip.z * TAU);
  v_glow = ip.x * ((part == 2u || part == 8u) ? 1.0 : 0.06) * pulse * twinkle;
  // a flash and a halo's projection shine as bright as their glow, never
  // pulsing; a prism has no light of its own
  if (part == 9u || part == 12u) v_glow = ip.x;
  // the ring: an arc is as bright as the points at its ends (tint holds
  // the four points' light, east, south, west, north; tu.x its angle)
  if (part == 11u) {
    float a = fract(tu.x) * 4.0;
    int i = int(a) % 4;
    v_glow = mix(tint[i], tint[(i + 1) % 4], fract(a));
  }
  if (part == 10u) v_glow = 0.0;
  v_part = float(part);
  v_t = tu.x;
  // a beam carries its length instead, so its rays and motes keep their size
  v_fade = part == 8u ? length(c3.xyz - c0.xyz) : ip.w;
  // the halo's ring and its projection carry their radius (their scale)
  if (part == 11u || part == 12u) v_fade = length(c0.xyz);
  if (drawn && part == 7u) v_fade *= 1.0 - haloFold(ih.w);
  v_u = tu.y;
  v_obj = p;
  v_phase = ip.z;
  v_aux = ip.y;
  // the halo's ring and the rays making it appear as its diamond forms
  // (from its shards, as its blooms close in)
  if (part == 11u || part == 12u) v_aux = drawn ? sqrt(haloPull(ih.w)) : 1.0;
  gl_Position = pc.vp * w;
}
