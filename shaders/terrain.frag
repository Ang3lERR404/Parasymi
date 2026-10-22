#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

layout(location = 0) in vec3 v_pos;
layout(location = 1) in vec3 v_nrm;
layout(location = 2) in vec3 v_col;
layout(location = 3) in vec4 v_info;
layout(location = 0) out vec4 o;

void main() {
  vec3 n = normalize(v_nrm);
  int kind = int(v_info.x * 255.0 + 0.5);
  float t = pc.eye_time.w;
  vec3 c = shade(v_col, n, v_pos);

  if (v_info.z > 0.5) {
    // tile grid for readability
    vec2 f = fract(v_pos.xz);
    float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
    c *= mix(0.78, 1.0, smoothstep(0.0, 0.04, edge));
    // ley currents: faint always on ley tiles, everywhere with ley sight
    float ley = v_info.y;
    float pulse = 0.5 + 0.5 * sin(t * 2.0 + v_pos.x * 0.45 + v_pos.z * 0.3);
    vec3 leyc = mix(vec3(0.45, 0.3, 1.0), vec3(1.0, 0.7, 1.0), pc.misc.x);
    float k = (kind == 4 ? 0.35 : 0.0) + pc.misc.y * ley * ley * 0.9;
    c += leyc * k * pulse;
    // hovered tile
    if (all(equal(floor(v_pos.xz), pc.misc.zw))) c += vec3(0.25, 0.25, 0.2) * (0.7 + 0.3 * sin(t * 6.0));
  }
  if (kind == 0) {
    float spec = pow(max(dot(reflect(-SUN, n), normalize(pc.eye_time.xyz - v_pos)), 0.0), 40.0);
    c += vec3(0.6, 0.7, 0.8) * spec * 0.4;
  }
  o = vec4(applyFog(c, v_pos), 1.0);
}
