#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

// per-vertex (mesh library)
layout(location = 0) in vec3 pos;
layout(location = 1) in vec3 nrm;
layout(location = 2) in vec4 col;
layout(location = 3) in vec2 tu;
layout(location = 4) in uint part;  // 0 vine 1 leaf 2 sap/glow 3 claw/thorn 4 root 5 sap-lined leaf (ear)
// per-instance
layout(location = 5) in vec4 c0;
layout(location = 6) in vec4 c1;
layout(location = 7) in vec4 c2;
layout(location = 8) in vec4 c3;
layout(location = 9) in vec4 ip;    // glow, flutter, phase, fade
layout(location = 10) in vec4 tint; // rgb multiply, w amount
layout(location = 11) in vec4 iq;   // sag

layout(location = 0) out vec3 v_pos;
layout(location = 1) out vec3 v_nrm;
layout(location = 2) out vec3 v_col;
layout(location = 3) out float v_glow;
layout(location = 4) flat out float v_part;
layout(location = 5) out float v_t;         // position along the part (tube tangent source)
layout(location = 6) flat out float v_fade; // opacity of translucent sap at its centre

void main() {
  float t = pc.eye_time.w;
  mat4 M = mat4(c0, c1, c2, c3);
  vec3 p = pos;
  // a full sac sags: pushed out along its radius, most at the bottom and
  // front. A field of position, so the vine net on it follows the surface.
  if (iq.x > 0.0) {
    vec3 r = normalize(pos);
    p += r * iq.x * max((1.0 - r.y) * 0.7 + r.z * 0.3, 0.0);
  }
  // secondary motion. Offsets must be identical for every copy of a shared
  // vertex (faceted parts carry different normals per face), so they use a
  // fixed axis scaled by position along the leaf: tips move, bases stay put.
  if (part == 1u || part == 5u) p.y += 0.03 * ip.y * tu.y * tu.y * sin(t * 7.0 + ip.z * 40.0 + tu.y * 2.0);
  if (part == 4u) p.y += 0.006 * sin(t * 2.0 + ip.z * 20.0 + tu.x * 9.0);

  vec4 w = M * vec4(p, 1.0);
  v_pos = w.xyz;
  v_nrm = normalize(mat3(M) * nrm);
  vec3 c = srgb2lin(col.rgb);
  v_col = mix(c, c * tint.rgb, tint.w);
  // sap pulses travel along the part
  float pulse = 0.65 + 0.35 * sin(t * 3.0 - tu.x * 8.0 + ip.z * 6.28);
  v_glow = ip.x * (part == 2u ? 1.0 : 0.06) * pulse;
  v_part = float(part);
  v_t = tu.x;
  v_fade = ip.w;
  gl_Position = pc.vp * w;
}
