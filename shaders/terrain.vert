#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

layout(location = 0) in vec3 pos;
layout(location = 1) in vec3 nrm;
layout(location = 2) in vec4 col;
layout(location = 3) in vec4 info; // kind/255, ley, top, -

layout(location = 0) out vec3 v_pos;
layout(location = 1) out vec3 v_nrm;
layout(location = 2) out vec3 v_col;
layout(location = 3) out vec4 v_info;

void main() {
  vec3 p = pos;
  int kind = int(info.x * 255.0 + 0.5);
  if (kind == 0 && info.z > 0.5) {
    float t = pc.eye_time.w;
    p.y += 0.04 * sin(t * 1.3 + p.x * 0.9) * cos(t * 0.9 + p.z * 0.7) - 0.08;
  }
  v_pos = p;
  v_nrm = nrm;
  v_col = srgb2lin(col.rgb);
  v_info = info;
  gl_Position = project(p);
}
