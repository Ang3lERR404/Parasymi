#version 450
//! pooled rain grown on the GPU from the moisture field (render/passes/pools.zig): a quad between every four texels near the view, lifted to the water's level where it pools (the field's alpha past 1, moisture.frag), folded away where all four are dry.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
#include "volume.glsl"
#include "moisture.glsl"

// Each instance is one quad of the water's surface, its corners on four
// neighbouring texels' middles of a grid fixed to the world round the view
// (so the water never swims as the camera moves). Each corner stands at the
// ground's height there with the water pooled on it: where pools meet they
// level out flat, and over a dry texel the surface keeps its level, flat, the
// ground rising through it at the shore (the depth test cutting it off).

// how deep the water stands here (world units), and where it is
layout(location = 0) out float v_depth;
layout(location = 1) out vec3 v_pos;

// texels along each side of the grid (match render/passes/pools.zig `quads`)
const int COLS = 96;
// the shallowest water drawn at all (world units)
const float SHALLOWEST = 0.004;
// the two triangles of a quad, corner by corner (0..1 each way)
const vec2 QUAD[6] = vec2[](vec2(0.0, 0.0), vec2(1.0, 0.0), vec2(1.0, 1.0), vec2(0.0, 0.0), vec2(1.0, 1.0), vec2(0.0, 1.0));
// what folds a vertex away: outside the view
const vec4 GONE = vec4(2.0, 2.0, 2.0, 1.0);

// the texel whose middle is at world (x, z) `c` + 0.5: the water's depth
// there, and the ground's height
vec2 water(vec2 c) {
  vec2 uv = overheadUv(vec3(c.x + 0.5, 0.0, c.y + 0.5));
  return vec2(moisturePool(texture(field_map, uv).a), texture(overhead_map, uv).a);
}

void main() {
  // the quad: the grid's corner under the view, this quad's cell from it
  vec2 corner = floor(pc.view.xy) - float(COLS / 2);
  vec2 cell = corner + vec2(float(gl_InstanceIndex % COLS), float(gl_InstanceIndex / COLS));
  // its four corners, and the highest level the water stands at among
  // them; folded away where all four are dry
  float most = 0.0, level = -1e9;
  for (int i = 0; i < 4; i++) {
    vec2 w = water(cell + vec2(float(i & 1), float(i >> 1)));
    most = max(most, w.x);
    if (w.x >= SHALLOWEST) level = max(level, w.x + w.y);
  }
  if (most < SHALLOWEST) { gl_Position = GONE; return; }
  // this vertex's corner: the water's level over it; a dry corner keeps
  // its neighbours' level, flat, so the shore is where the ground rises
  // through it (the depth test), never a notch where the face sinks
  vec2 c = cell + QUAD[gl_VertexIndex];
  vec2 w = water(c);
  vec3 p = vec3(c.x + 0.5, w.x >= SHALLOWEST ? w.y + w.x : max(w.y, level), c.y + 0.5);
  v_depth = w.x;
  v_pos = p;
  gl_Position = pc.vp * vec4(p, 1.0);
}
