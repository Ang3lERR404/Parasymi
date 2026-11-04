//! the frame's lighting record as every shader reads it (render/light.zig `Head`, its points of light after it), and the cells the view is cut into, each listing the points of light that reach it (render/cells.zig).
// The including shader declares first the extensions GL_EXT_buffer_reference
// and GL_EXT_buffer_reference_uvec2.

// the record's sizes: slices of the view in the key light's shadow map,
// shadow cubes (render/light.zig `cascades`, render/cube.zig `maxCubes`)
const int CASCADES = 3;
const int MAX_CUBES = 4;
struct PointLight {
  vec4 pos; // xyz where, w how far it reaches
  vec4 col; // linear rgb times its strength; w its shadow cube plus one (0 none)
  vec4 dir; // a cone it is thrown in: xyz the way its middle points, w the cosine of its half-width (below -1: all round)
};
// a point of light's shadow cube (render/cube.zig `Cube`)
struct Cube {
  vec4 at;      // xyz the light it was drawn round, w how far it reaches (its far plane)
  vec4 lit;     // x which point of light, y how much of its shadow shows, z its near plane
  mat4 face[6]; // world to each face's clip space (+x, -x, +y, -y, +z, -z)
};
// the record: the cascades, what the frame holds, how the view is cut into
// cells and where their lists lie, the shadow cubes, then every point of
// light (as many as the frame makes: the record grows to hold them)
layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer Lighting {
  mat4 cascade[CASCADES]; // world to each cascade's clip space
  float texel[4];         // the world size of each cascade's texels
  vec4 info;              // x points of light, y how far from the eye shadows reach, z 1 traced as rays, w the world's samples a pixel
  mat4 grid;              // world to the eye's clip space, as the cells are cut in it
  vec4 slicing;           // x the far edge of the nearest slice of depth, y slices for each e-fold of depth beyond it
  uvec2 cells;            // where the cells' lists lie (`Cells`)
  Cube cubes[MAX_CUBES];
  PointLight lights[];
};

// The cells (render/cells.zig): the screen cut into CELLS_X by CELLS_Y
// tiles, each tile cut along the eye's depth into SLICES slices, the
// nearest from the eye to `slicing.x`, the rest each further by a constant
// share (so near cells are as shallow as they are wide on screen, far ones
// deep), the last running on without end. After them, one more cell a tile:
// the whole of its depth (a ray through the air passes every slice). A cell
// lists the points of light whose reach touches it as bits, one a light, in
// as many words as the frame's lights need (`lightWords`), filled on the
// GPU each frame (cells.comp).
const int CELLS_X = 32;
const int CELLS_Y = 18;
const int SLICES = 32;
// the cells in all: every slice of every tile, and a tile's whole depth
const int CELLS = CELLS_X * CELLS_Y * (SLICES + 1);
layout(buffer_reference, std430, buffer_reference_align = 4) readonly buffer Cells { uint bits[]; };

// the frame's points of light
int lightCount(Lighting L) { return int(L.info.x + 0.5); }
// the words a cell's list takes: a bit for each of `count` lights
int lightWords(int count) { return (count + 31) / 32; }
// which slice of depth a point `w` deep before the eye lies in
int sliceOf(Lighting L, float w) {
  if (w < L.slicing.x) return 0;
  return min(1 + int(log(w / L.slicing.x) * L.slicing.y), SLICES - 1);
}
// how deep slice `s` begins and ends (the last ends nowhere: below 0)
vec2 sliceSpan(Lighting L, int s) {
  float from = s == 0 ? 0.0 : L.slicing.x * exp(float(s - 1) / L.slicing.y);
  float to = s == SLICES - 1 ? -1.0 : L.slicing.x * exp(float(s) / L.slicing.y);
  return vec2(from, to);
}
// the tile a point `q` in the eye's clip space falls in, or (-1, -1) off
// the screen or behind the eye
ivec2 tileOf(vec4 q) {
  if (q.w <= 0.0) return ivec2(-1);
  vec2 ndc = q.xy / q.w;
  if (abs(ndc.x) >= 1.0 || abs(ndc.y) >= 1.0) return ivec2(-1);
  return min(ivec2((ndc * 0.5 + 0.5) * vec2(CELLS_X, CELLS_Y)), ivec2(CELLS_X - 1, CELLS_Y - 1));
}
// the cell holding the world point `wpos`, or -1 outside them all (off the
// screen, behind the eye: a shadow cube's face, the overhead map)
int cellAt(Lighting L, vec3 wpos) {
  vec4 q = L.grid * vec4(wpos, 1.0);
  ivec2 t = tileOf(q);
  if (t.x < 0) return -1;
  return (sliceOf(L, q.w) * CELLS_Y + t.y) * CELLS_X + t.x;
}
// the cell of every depth a ray from the eye along `dir` passes through,
// or -1 off the screen
int columnAt(Lighting L, vec3 eye, vec3 dir) {
  ivec2 t = tileOf(L.grid * vec4(eye + dir, 1.0));
  if (t.x < 0) return -1;
  return (SLICES * CELLS_Y + t.y) * CELLS_X + t.x;
}
// word `w` of cell `cell`'s list: a bit for each light reaching it among
// lights 32w .. 32w+31. Outside the cells (-1), every light the frame holds.
uint lightsIn(Lighting L, int cell, int w, int count) {
  if (cell < 0) {
    int left = count - w * 32;
    return left >= 32 ? 0xffffffffu : (1u << uint(left)) - 1u;
  }
  return Cells(L.cells).bits[cell * lightWords(count) + w];
}
