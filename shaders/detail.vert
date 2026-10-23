#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

// The ground's detail, grown here from one record per tile (DetailTile):
// up to 8 thin grass blades on any tile but water and soil, coloured by the
// tile, swaying in the garden wind; on soil, a clod heaped up and a small
// stone half sunk in it, each a faceted lump. Every tile runs 60 vertices;
// what it does not use folds to nothing outside the view. All placement is
// hashed from the tile's position, so a tile always grows the same.

layout(location = 0) in vec3 at;      // tile corner x, centre height, corner z
layout(location = 1) in vec4 corners; // corner heights (x0,z0) (x0,z1) (x1,z1) (x1,z0)
layout(location = 2) in vec4 col;
layout(location = 3) in vec4 info;    // kind/255, ley, blades/255, -

layout(location = 0) out vec3 v_pos;
layout(location = 1) out vec3 v_nrm;
layout(location = 2) out vec3 v_col;
layout(location = 3) out vec4 v_info;

const int SOIL = 1;

float hash13(vec3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.zyx + 31.32);
  return fract((p.x + p.y) * p.z);
}

// the ground's height at (fx, fz) within the tile: the fan of four
// triangles from its centre to its corners
float groundAt(float fx, float fz) {
  float h00 = corners.x, h01 = corners.y, h11 = corners.z, h10 = corners.w;
  vec2 d = vec2(fx, fz) - 0.5;
  // which triangle of the fan, and how far toward its two corners
  vec2 a = abs(d);
  float c = at.y;
  if (a.x >= a.y) {
    float side = d.x < 0.0 ? 0.0 : 1.0;
    float e0 = side < 0.5 ? h00 : h10;
    float e1 = side < 0.5 ? h01 : h11;
    float s = a.x * 2.0;               // 0 at centre .. 1 at the edge
    float v = s > 0.0 ? (d.y / a.x) * 0.5 + 0.5 : 0.5;
    return mix(c, mix(e0, e1, v), s);
  }
  float side = d.y < 0.0 ? 0.0 : 1.0;
  float e0 = side < 0.5 ? h00 : h01;
  float e1 = side < 0.5 ? h10 : h11;
  float s = a.y * 2.0;
  float v = s > 0.0 ? (d.x / a.y) * 0.5 + 0.5 : 0.5;
  return mix(c, mix(e0, e1, v), s);
}

void hide() {
  gl_Position = vec4(0.0, 0.0, -2.0, 1.0);
  v_pos = vec3(0.0);
  v_nrm = vec3(0.0, 1.0, 0.0);
  v_col = vec3(0.0);
  v_info = vec4(0.0);
}

void main() {
  float t = pc.eye_time.w;
  int kind = int(info.x * 255.0 + 0.5);
  int vi = gl_VertexIndex;
  vec3 tile = srgb2lin(col.rgb);
  vec2 cell = at.xz;

  if (kind != SOIL) {
    // a grass blade: two root corners and a tip
    int blade = vi / 3;
    int corner = vi - blade * 3;
    if (blade >= int(info.z * 255.0 + 0.5)) { hide(); return; }
    vec3 k = vec3(cell, float(blade));
    float fx = mix(0.06, 0.94, hash13(k + 0.1));
    float fz = mix(0.06, 0.94, hash13(k + 1.7));
    float len = mix(0.09, 0.23, hash13(k + 3.3));
    float ang = TAU * hash13(k + 5.9);
    float lean = 0.25 * hash13(k + 7.1);
    vec3 base = vec3(cell.x + fx, groundAt(fx, fz) - 0.01, cell.y + fz);
    vec3 side = vec3(cos(ang), 0.0, sin(ang)) * 0.014;
    vec3 p;
    float hf;
    if (corner == 2) {
      p = base + vec3(-sin(ang) * lean * len, len, cos(ang) * lean * len);
      hf = 1.0;
    } else {
      p = base + (corner == 0 ? -side : side);
      hf = 0.0;
    }
    // it bends in the garden's wind, the tip most, with a sway of its own
    vec4 wind = gardenWind(t, p.xz);
    float own = sin(t * 1.4 - wind.w * 0.4 + dot(floor(base.xz * 8.0), vec2(1.7, 2.3)));
    float bend = (0.09 * wind.z + 0.035 * (0.4 + wind.z) * own) * hf * hf;
    p.xz += wind.xy * bend;
    p.y -= 0.3 * bend * bend;
    v_pos = p;
    v_nrm = vec3(0.0, 1.0, 0.0);
    v_col = hf > 0.5 ? min(tile * vec3(1.35, 1.45, 1.3), vec3(1.0)) : tile * vec3(0.7, 0.75, 0.7);
    // w > 0 marks grass for terrain.frag (ley glow), z 0: not the ground
    v_info = vec4(info.x, info.y, 0.0, max(hf, 0.004));
    gl_Position = pc.vp * vec4(p, 1.0);
    return;
  }

  // soil: lumps of 10 triangles (5 around the crown, 5 under), two per tile
  int lump = vi / 30;
  int j = vi - lump * 30;
  int tri = j / 3;
  int corner = j - tri * 3;
  vec3 k = vec3(cell, float(lump) + 11.0);
  if (hash13(vec3(cell, 0.5)) < 0.35) { hide(); return; }
  bool stone = lump == 1;
  float fx = mix(0.12, 0.88, hash13(k + 0.3));
  float fz = mix(0.12, 0.88, hash13(k + 2.1));
  float r = stone ? mix(0.025, 0.055, hash13(k + 4.4)) : mix(0.05, 0.1, hash13(k + 4.4));
  float flat_ = stone ? 0.7 : 0.35;
  vec3 c = vec3(cell.x + fx, groundAt(fx, fz), cell.y + fz);
  float turn = TAU * hash13(k + 6.6);
  // the triangle's three points: ring i, ring i+1 and the crown (top) or
  // the buried bottom
  int i = tri - (tri >= 5 ? 5 : 0);
  bool top = tri < 5;
  vec3 q[3];
  for (int n = 0; n < 2; n++) {
    int ri = (i + n) - ((i + n) >= 5 ? 5 : 0);
    float a = turn + TAU * float(ri) / 5.0;
    vec3 kr = k + float(ri) * 13.1;
    float d = r * mix(0.75, 1.25, hash13(kr + 0.7));
    q[n] = c + vec3(cos(a) * d, r * flat_ * 0.25 * hash13(kr + 1.9), sin(a) * d);
  }
  q[2] = top ? c + vec3(r * (hash13(k + 8.1) - 0.5) * 0.16, r * flat_, r * (hash13(k + 9.3) - 0.5) * 0.16) : c - vec3(0.0, r * flat_ * 0.6, 0.0);
  vec3 n = normalize(cross(q[1] - q[0], q[2] - q[0]));
  if (dot(n, q[0] + q[1] + q[2] - 3.0 * c) < 0.0) n = -n;
  vec3 p = corner == 0 ? q[0] : (corner == 1 ? q[1] : q[2]);
  vec3 grey = vec3(0.42, 0.4, 0.38) * mix(0.75, 1.15, hash13(k + 10.7));
  v_pos = p;
  v_nrm = n;
  v_col = stone ? srgb2lin(grey) : tile * vec3(0.78, 0.72, 0.68);
  v_info = vec4(info.x, info.y, 0.0, 0.0);
  gl_Position = pc.vp * vec4(p, 1.0);
}
