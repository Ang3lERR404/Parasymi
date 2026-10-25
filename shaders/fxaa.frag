#version 450
//! FXAA 3.11 (quality) on the tone-mapped scene, before the UI.
#extension GL_GOOGLE_include_directive : require
#include "post.glsl"

// FXAA (the quality path of Lottes' FXAA 3.11), on the tone-mapped scene
// before the UI goes over it. The composite left each pixel's perceptual
// luma in alpha. Where the local contrast is high enough this finds the
// edge's direction, walks along it both ways to its ends and slides the
// sample across it by how near the pixel is to the closer end, so stair
// steps blend into a line; a sub-pixel term softens what falls between
// pixels (thin stalks, grass tips, motes) so it no longer crawls.
layout(set = 0, binding = 0) uniform sampler2D scene;

// darkest contrast worth smoothing, and contrast needed relative to the
// brightest neighbour
const float EDGE_MIN = 0.0312;
const float EDGE_REL = 0.125;
// how much sub-pixel aliasing is softened (0 none .. 1 soft)
const float SUBPIX = 0.75;
// steps along an edge (texels each), and the guess past the last one
const int STEPS = 12;
const float STEP[STEPS] = float[](1.0, 1.0, 1.0, 1.0, 1.0, 1.5, 2.0, 2.0, 2.0, 2.0, 4.0, 8.0);
const float GUESS = 8.0;

float lumaAt(vec2 uv) { return textureLod(scene, uv, 0.0).a; }
#define LUMA(dx, dy) textureLodOffset(scene, v_uv, 0.0, ivec2(dx, dy)).a

void main() {
  vec2 t = pc.texel;
  vec4 c = textureLod(scene, v_uv, 0.0);
  float lm = c.a;
  float ln = LUMA(0, 1), ls = LUMA(0, -1), le = LUMA(1, 0), lw = LUMA(-1, 0);
  float hi = max(max(max(ln, ls), max(le, lw)), lm);
  float lo = min(min(min(ln, ls), min(le, lw)), lm);
  float contrast = hi - lo;
  if (contrast < max(EDGE_MIN, hi * EDGE_REL)) { o = vec4(c.rgb, 1.0); return; }
  float lne = LUMA(1, 1), lnw = LUMA(-1, 1), lse = LUMA(1, -1), lsw = LUMA(-1, -1);

  // sub-pixel: how far the centre stands out from its neighbourhood
  float avg = (2.0 * (ln + ls + le + lw) + lne + lnw + lse + lsw) / 12.0;
  float sub = smoothstep(0.0, 1.0, clamp(abs(avg - lm) / contrast, 0.0, 1.0));
  sub = sub * sub * SUBPIX;

  // which way the edge runs: a horizontal one changes from row to row
  float horzE = 2.0 * abs(ln + ls - 2.0 * lm) + abs(lne + lse - 2.0 * le) + abs(lnw + lsw - 2.0 * lw);
  float vertE = 2.0 * abs(le + lw - 2.0 * lm) + abs(lne + lnw - 2.0 * ln) + abs(lse + lsw - 2.0 * ls);
  bool horz = horzE >= vertE;
  float across = horz ? t.y : t.x;
  float lp = horz ? ln : le;
  float lq = horz ? ls : lw;
  float gp = abs(lp - lm);
  float gq = abs(lq - lm);
  float other = lp;
  float grad = gp;
  if (gp < gq) { across = -across; other = lq; grad = gq; }

  // walk along the edge (half a texel across it, between the two rows) to
  // where the luma there leaves the edge's
  vec2 at = v_uv;
  vec2 along;
  if (horz) { at.y += 0.5 * across; along = vec2(t.x, 0.0); }
  else { at.x += 0.5 * across; along = vec2(0.0, t.y); }
  float edge = 0.5 * (lm + other);
  float limit = 0.25 * grad;
  vec2 pu = at + along * STEP[0];
  vec2 qu = at - along * STEP[0];
  float pd = lumaAt(pu) - edge;
  float qd = lumaAt(qu) - edge;
  bool pend = abs(pd) >= limit;
  bool qend = abs(qd) >= limit;
  for (int i = 1; i < STEPS && !(pend && qend); i++) {
    if (!pend) { pu += along * STEP[i]; pd = lumaAt(pu) - edge; pend = abs(pd) >= limit; }
    if (!qend) { qu -= along * STEP[i]; qd = lumaAt(qu) - edge; qend = abs(qd) >= limit; }
  }
  if (!pend) pu += along * GUESS;
  if (!qend) qu -= along * GUESS;

  // blend across by how near the closer end is, if that end bends this way
  float pdist = horz ? pu.x - v_uv.x : pu.y - v_uv.y;
  float qdist = horz ? v_uv.x - qu.x : v_uv.y - qu.y;
  float near = min(pdist, qdist);
  bool sign_end = (pdist <= qdist ? pd : qd) >= 0.0;
  float blend = sign_end == (lm - edge >= 0.0) ? 0.0 : 0.5 - near / (pdist + qdist);
  blend = max(blend, sub);

  vec2 uv = v_uv;
  if (horz) uv.y += across * blend;
  else uv.x += across * blend;
  o = vec4(textureLod(scene, uv, 0.0).rgb, 1.0);
}
