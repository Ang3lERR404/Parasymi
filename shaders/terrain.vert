#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

layout(location = 0) in vec3 pos;
layout(location = 1) in vec3 nrm;
layout(location = 2) in vec4 col;
layout(location = 3) in vec4 info; // kind/255, ley, top, grass height (0 not grass)

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
  // grass blades (info.w: 1/255 at the root .. 1 at the tip) bend in the
  // garden's wind, tips most, each with a little sway of its own
  if (info.w > 0.0) {
    float t = pc.eye_time.w;
    float hf = (info.w * 255.0 - 1.0) / 254.0;
    vec4 wind = gardenWind(t, p.xz);
    float own = sin(t * 1.4 - wind.w * 0.4 + dot(floor(p.xz * 8.0), vec2(1.7, 2.3)));
    float bend = (0.09 * wind.z + 0.035 * (0.4 + wind.z) * own) * hf * hf;
    p.xz += wind.xy * bend;
    p.y -= 0.3 * bend * bend;
  }
  v_pos = p;
  v_nrm = nrm;
  v_col = srgb2lin(col.rgb);
  v_info = info;
  gl_Position = pc.vp * vec4(p, 1.0);
}
