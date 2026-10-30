#version 450
//! terrain shading: tile colour, ley sight and its plexus, the ley lines
//! sealing (the unforming), shadows, fog. With OVERHEAD, the ground seen
//! from above for the fog: the glow it sends into the air, and its height.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

layout(location = 0) in vec3 v_pos;
layout(location = 1) in vec3 v_nrm;
layout(location = 2) in vec3 v_col;
layout(location = 3) in vec4 v_info;
layout(location = 0) out vec4 o;

// ley sight: the currents' colour (plain, veiled), and the plexus's pale tint
const vec3 LEY = vec3(0.45, 0.3, 1.0);
const vec3 LEY_VEILED = vec3(1.0, 0.7, 1.0);
const vec3 PLEXUS_PALE = vec3(0.9, 0.85, 1.0);
// a ley line sealing: the bare soil it closes to (terrain_mesh.zig's soil, sRGB),
// the bright seam where it is closing, and how wide that seam is (in ley)
const vec3 SEALED_SOIL = vec3(0.36, 0.27, 0.19);
const vec3 SEAM = vec3(0.75, 0.5, 1.0);
const float SEAM_WIDTH = 0.06;
// the hovered tile's highlight, pulsing at this rate (rad/s)
const vec3 HOVER = vec3(0.25, 0.25, 0.2);
const float HOVER_PULSE = 6.0;
// a paw's contact shadow: its radii (side, forward) on the ground, and its
// darkness there
const vec2 PAW_SHADOW = vec2(0.12, 0.18);
const float PAW_SHADOW_DARK = 0.7;
// seen from above, a ley line's plexus as the air takes it: its threads too
// fine to tell apart, an even glow this strong over the line
const float PLEXUS_AIR = 0.35;

void main() {
  vec3 n = normalize(v_nrm);
  float t = pc.eye_time.w;
  float ley = v_info.y;
  bool ground = v_info.z > 0.5;
  // the ley lines sealing: a front closing from each line's edges in to its
  // heart (by its depth into the line, terrain_mesh.zig), behind it bare
  // soil, at it a bright seam; grass on a line browns as it seals
  float seal = sealed();
  float depth = ground ? v_info.w : 0.0;
  float line = ground ? smoothstep(0.0, 0.12, depth) : smoothstep(0.25, 0.35, ley);
  float front = mix(0.0, 1.0 + SEAM_WIDTH, seal);
  float closed = seal <= 0.0 ? 0.0 : ground ? line * smoothstep(depth - SEAM_WIDTH * 0.5, depth + SEAM_WIDTH * 0.5, front) : line * seal;
  float seam = ground && seal > 0.0 && seal < 1.0 ? line * (1.0 - smoothstep(0.0, SEAM_WIDTH, abs(depth - front))) : 0.0;
  // the light the ground gives off itself
  vec3 glow = vec3(0.0);
  if (ground || v_info.w > 0.0) {
    // ley currents: everywhere with ley sight, on the ground and its grass,
    // fading smoothly across tile borders (ley is shared at tile edges)
#ifdef OVERHEAD
    // (the map is kept for many frames: the fog pulses it itself)
    float pulse = 0.5;
#else
    float pulse = leyPulse(v_pos, t);
#endif
    vec3 leyc = mix(LEY, LEY_VEILED, VEIL);
    glow += leyc * pc.misc.y * ley * ley * 0.45 * pulse * (1.0 - closed);
    glow += SEAM * seam * (0.6 + 0.4 * pulse);
    // a faint plexus drifting over the ley lines themselves
    // (only evaluated where it shows: it is the costliest thing on the ground)
    float on = smoothstep(0.5, 0.85, ley) * (1.0 - closed);
#ifdef OVERHEAD
    float web = PLEXUS_AIR;
#else
    float web = on > 0.0 ? plexus(v_pos.xz, t) : 0.0;
#endif
    if (ground && on > 0.0) glow += mix(leyc, PLEXUS_PALE, 0.4) * web * on * mix(0.32, 0.16, DAYLIGHT);
  }
#ifdef OVERHEAD
  o = vec4(glow, v_pos.y);
  return;
#endif
  // how much of the key light reaches here: what stands between it and the
  // sun or moon (a plant, a structure, the wolf, a hill) shades it
  float sh = keyShadow(v_pos, n);
  vec3 c = shadeLit(mix(v_col, srgb2lin(SEALED_SOIL), closed), n, v_pos, sh) + glow;
  // hovered tile
  if (ground && all(equal(floor(v_pos.xz), pc.misc.zw))) c += HOVER * (0.7 + 0.3 * sin(t * HOVER_PULSE));
  // contact shadows: a soft ellipse under each paw, long along the facing,
  // spreading and fading as the paw lifts. Only upward faces at or below the
  // paw receive one.
  if (n.y > 0.5) for (int i = 0; i < 2; i++) {
    vec4 f = vec4(pc.feet[i].xyz, pc.feet[0].w);
    float lift = f.y - v_pos.y;
    if (lift < -0.05) continue;
    lift = max(lift, 0.0);
    vec2 d = v_pos.xz - f.xz;
    float s = sin(f.w), co = cos(f.w);
    vec2 local = vec2(d.x * co - d.y * s, d.x * s + d.y * co); // (side, forward)
    vec2 radii = PAW_SHADOW * (1.0 + lift * 3.0);
    float e = length(local / radii);
    float strength = PAW_SHADOW_DARK / ((1.0 + lift * 5.0) * (1.0 + lift * 5.0));
    c *= 1.0 - strength * (1.0 - smoothstep(0.1, 1.0, e));
  }
  o = vec4(applyFog(c, v_pos), 1.0);
}
