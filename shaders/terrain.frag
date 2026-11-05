#version 460
//! terrain shading: the ground's kinds melted together with their own
//! surfaces (ground.glsl), ley sight and its plexus, the ley lines
//! sealing (the unforming), rain soaking it darker, shadows, fog. With OVERHEAD, the ground seen
//! from above for the fog: the glow it sends into the air, and its height.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
#include "ground.glsl"
#ifndef OVERHEAD
#include "volume.glsl"
#include "moisture.glsl"
#endif

layout(location = 0) centroid in vec3 v_pos;
layout(location = 1) centroid in vec3 v_nrm;
layout(location = 2) in vec3 v_col;
layout(location = 3) in vec4 v_info;
layout(location = 4) in vec4 v_mat;
layout(location = 5) in vec4 v_star; // a starlit patch here: how far inside, how rich (terrain_mesh.zig)
layout(location = 0) out vec4 o;

// ley sight: the currents' colour (plain: common.glsl `LEY`; veiled), and
// the plexus's pale tint
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
// how deep the ground's bumps light it, and how far from the eye (world
// units a pixel spans) its finest grain fades out
const float GROUND_BUMP = 0.035;
const float GRAIN_FADE = 0.035;
// seen from above, a ley line's plexus as the air takes it: its threads too
// fine to tell apart, an even glow this strong over the line
const float PLEXUS_AIR = 0.35;
// ground soaked through by rain (the moisture field's alpha): how much
// darker it is, and how much bluer its darkening leans
const float WET_DARK = 0.42;
const vec3 WET_TINT = vec3(0.92, 0.96, 1.0);
// a starlit patch's field (game/starlight.zig): its dark blue, lighter the
// poorer the patch, nearly the constellate lineage's own the richer (linear);
// how much of the ground (and its grass) it covers; how far its rim frays
// in and out and over what width (m); how faintly it glows of its own,
// shimmering, and how fast that shimmer runs; the size of the faint star
// glints in it (cells a metre) and how often one twinkles
const vec3 STAR_POOR = vec3(0.025, 0.045, 0.15);
const vec3 STAR_RICH = vec3(0.004, 0.012, 0.11);
const float STAR_COVER = 0.92;
const float STAR_FRAY = 0.35;
const float STAR_FRAY_L = 1.6;
const float STAR_GLOW = 0.06;
const float STAR_SHIMMER = 0.9;
const float STAR_GLINTS = 5.0;
const float STAR_GLINT_RATE = 1.7;
// the debug grid (F3): tile edges, each tile's fan diagonals (where its four
// triangles meet) and chunk borders, their colours and widths (pixels)
const vec3 GRID_TILE = vec3(1.0, 0.85, 0.2);
const vec3 GRID_FAN = vec3(0.2, 0.9, 1.0);
const vec3 GRID_CHUNK = vec3(1.0, 0.2, 0.8);
const float GRID_CHUNK_TILES = 32.0; // (chunk.zig sizeTiles; must match)
const float GRID_WIDTH = 1.0;
// how near (pixels) point `d` lies to a line `d` = 0, its screen rate `w`:
// 1 on it, 0 a width away
float gridLine(vec2 d, vec2 w, float width) {
  vec2 k = 1.0 - smoothstep(vec2(0.0), w * width, abs(d));
  return max(k.x, k.y);
}

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
    glow += leyc * LEY_SIGHT * ley * ley * 0.45 * pulse * (1.0 - closed);
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
  vec3 albedo = v_col;
  if (ground) {
    // the ground's own stuff: its kinds melted along frayed borders, each
    // with its surface, the finest grain fading where a pixel spans too much
    vec2 p = v_pos.xz;
    float span = length(fwidth(p));
    float fine = 1.0 - smoothstep(GRAIN_FADE * 0.5, GRAIN_FADE, span);
    GroundSurface g = groundOf(p, groundBlend(p, v_mat), fine);
    albedo = g.albedo;
    // its bumps tip the normal (the surface gradient, from screen derivatives)
    vec3 dpx = dFdx(v_pos), dpy = dFdy(v_pos);
    vec3 r1 = cross(dpy, n), r2 = cross(n, dpx);
    float det = dot(dpx, r1);
    vec3 grad = sign(det) * (dFdx(g.height) * r1 + dFdy(g.height) * r2);
    n = normalize(abs(det) * n - grad * GROUND_BUMP * fine);
  }
  // a starlit patch: its dark-blue field over the ground and its grass, its
  // rim frayed in and out, deeper blue the richer it is, glowing faintly
  // with a slow shimmer and a few twinkling star glints; gone once the sky
  // has shifted (the unforming shot its light into the sky)
  if (v_star.x > 0.0) {
    vec2 fp = v_pos.xz / STAR_FRAY_L;
    vec2 fi = floor(fp);
    vec2 ff = fp - fi;
    ff = ff * ff * (3.0 - 2.0 * ff);
    float fray = mix(mix(hash12(fi), hash12(fi + vec2(1.0, 0.0)), ff.x), mix(hash12(fi + vec2(0.0, 1.0)), hash12(fi + vec2(1.0)), ff.x), ff.y);
    float cover = smoothstep(0.05, 0.4, v_star.x + STAR_FRAY * (fray - 0.5)) * (1.0 - SHIFT);
    vec3 field = mix(STAR_POOR, STAR_RICH, v_star.y);
    albedo = mix(albedo, field, cover * STAR_COVER);
    // its own faint light, shimmering, and its glints twinkling
    vec2 gc = floor(v_pos.xz * STAR_GLINTS);
    float gh = hash12(gc + 7.3);
    float glint = pow(max(sin(t * STAR_GLINT_RATE * (0.5 + gh) + gh * TAU), 0.0), 24.0) * step(0.8, gh) * smoothstep(0.22, 0.0, length(fract(v_pos.xz * STAR_GLINTS) - 0.5));
    float shimmer = 0.75 + 0.25 * sin(t * STAR_SHIMMER + fray * TAU);
    glow += normalize(field + 1e-4) * cover * (STAR_GLOW * shimmer + glint * 0.6);
  }
#ifndef OVERHEAD
  // the rain soaking it (and its grass) darker
  float wet = moistureWet(texture(field_map, overheadUv(v_pos)).a);
  albedo *= mix(vec3(1.0), WET_TINT * (1.0 - WET_DARK), wet);
#endif
  float sh = keyShadow(v_pos, n);
  vec3 c = shadeLit(mix(albedo, srgb2lin(SEALED_SOIL), closed), n, v_pos, sh) + glow;
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
  c = applyFog(c, v_pos);
  // the debug grid, over the fog so it reads at any distance
  if (DEBUG_GRID) {
    vec2 p = v_pos.xz;
    vec2 w = fwidth(p);
    vec2 f = fract(p);
    float tile = gridLine(f - round(f), w, GRID_WIDTH);
    float fan = gridLine(vec2(f.x - f.y, f.x + f.y - 1.0), vec2(w.x + w.y), GRID_WIDTH) * 0.6;
    vec2 q = p / GRID_CHUNK_TILES;
    float chunk = gridLine((q - round(q)) * GRID_CHUNK_TILES, w, GRID_WIDTH * 2.5);
    c = mix(c, GRID_FAN, fan);
    c = mix(c, GRID_TILE, tile * 0.8);
    c = mix(c, GRID_CHUNK, chunk);
  }
  o = vec4(c, 1.0);
}
