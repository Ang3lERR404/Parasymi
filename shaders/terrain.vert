#version 450
//! terrain tiles (the smooth fans of render/terrain_mesh.zig) to clip space.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

layout(location = 0) in vec3 pos;
layout(location = 1) in vec3 nrm;
layout(location = 2) in vec4 col;
layout(location = 3) in vec4 info; // kind/255, ley, top, depth into a ley line
layout(location = 4) in vec4 mat;  // the share of soil, moss, stone, ley here

layout(location = 0) out vec3 v_pos;
layout(location = 1) out vec3 v_nrm;
layout(location = 2) out vec3 v_col;
layout(location = 3) out vec4 v_info;
layout(location = 4) out vec4 v_mat;

void main() {
  vec3 p = pos;
  v_pos = p;
  v_nrm = nrm;
  v_col = srgb2lin(col.rgb);
  v_info = info;
  v_mat = mat;
  gl_Position = project(p);
}
