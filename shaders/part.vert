#version 450
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"

// per-vertex (mesh library)
layout(location = 0) in vec3 pos;
layout(location = 1) in vec3 nrm;
layout(location = 2) in vec4 col;
layout(location = 3) in vec2 tu;
layout(location = 4) in uint part;  // 0 vine 1 leaf 2 sap/glow 3 claw/thorn 4 root 5 sap-lined leaf (ear) 6 resin
// per-instance
layout(location = 5) in vec4 c0;
layout(location = 6) in vec4 c1;
layout(location = 7) in vec4 c2;
layout(location = 8) in vec4 c3;
layout(location = 9) in vec4 ip;    // glow, flutter, phase, fade
layout(location = 10) in vec4 tint; // rgb multiply, w amount
layout(location = 11) in vec4 iq;   // sag, give (resin surface push)
layout(location = 12) in vec4 iw;   // sway, height of the sway, how far below the origin it is rooted, grown

layout(location = 0) out vec3 v_pos;
layout(location = 1) out vec3 v_nrm;
layout(location = 2) out vec3 v_col;
layout(location = 3) out float v_glow;
layout(location = 4) flat out float v_part;
layout(location = 5) out float v_t;         // position along the part (tube tangent source)
layout(location = 6) flat out float v_fade; // opacity of translucent sap at its centre
layout(location = 7) out float v_u;
layout(location = 8) out vec3 v_obj;       // mesh-space point (sap bubbles ride with the body)         // across a leaf; through a resin part (0 base .. 1 surface)

void main() {
  float t = pc.eye_time.w;
  mat4 M = mat4(c0, c1, c2, c3);
  vec3 p = pos;
  // a full sac sags: pushed out along its radius, most at the bottom and
  // front. A field of position, so the vine net on it follows the surface.
  // a filling sac swells from its centre, most low and forward, only where
  // it is gut (tu.x), so its tongue stays put on the chest; a smooth field
  // of position, so the net and leaves on it move with it
  if (iq.x > 0.0) {
    vec3 r = normalize(pos + vec3(0.0, 0.0, 1e-4));
    p += r * iq.x * tu.x * (0.6 + 0.6 * max(-r.y, 0.0) + 0.4 * max(r.z, 0.0));
  }
  // the belly button (tu.y 2) surfaces from inside the sap as the belly
  // fills (fill in iq.y), and pops out past it when full
  if (tu.y > 1.5) p.z += 0.04 * pow(clamp(iq.y, 0.0, 1.0), 1.5);
  // secondary motion. Offsets must be identical for every copy of a shared
  // vertex (faceted parts carry different normals per face), so they use a
  // fixed axis scaled by position along the leaf: tips move, bases stay put.
  float sway = iw.x;
  // a growing structure's leaves and petals come up folded and open from
  // the bottom up, tips last (weighted along the leaf so its base holds)
  if (iw.w < 1.0 && (part == 1u || part == 5u)) {
    float open = smoothstep(pos.y / iw.y * 0.7, pos.y / iw.y * 0.7 + 0.35, iw.w);
    p.xz *= mix(1.0, mix(0.2, 1.0, open), tu.y);
  }
  vec4 wind = gardenWind(t, c3.xz);
  // grown structures move as the plants do: leaves and petals breathe
  // slowly and lift a little in the gusts, tips most, bases held
  if (sway > 0.0 && (part == 1u || part == 5u)) {
    p.y += tu.y * tu.y * (0.012 * wind.z * sin(t * 1.7 + ip.z * 11.0 + tu.x * 3.0) + 0.01 * sin(t * 0.9 + ip.z * 6.28));
  } else if (part == 1u || part == 5u) p.y += 0.03 * ip.y * tu.y * tu.y * sin(t * 7.0 + ip.z * 40.0 + tu.y * 2.0);
  if (part == 4u) p.y += 0.006 * sin(t * 2.0 + ip.z * 20.0 + tu.x * 9.0);
  // resin gives like dense gel: its surface follows the spring, its base on
  // the body holds (a smooth field of height, so shared vertices move alike)
  if (part == 6u) p += iq.yzw * smoothstep(0.0, 1.0, tu.y);

  vec4 w = M * vec4(p, 1.0);
  vec3 wn = mat3(M) * nrm;
  // ... and bend from their root in the garden's wind, as the plants do:
  // more toward the top, the lean slow and late at the tip (a smooth field
  // of world height, so shared vertices move alike)
  if (sway > 0.0) {
    vec3 root = c3.xyz - vec3(0.0, iw.z, 0.0);
    float h = clamp((w.y - root.y) / iw.y, 0.0, 1.5);
    float own = sin(t * 0.85 - wind.w * 0.3 + ip.z * 6.28 - h * 0.9);
    float ang = sway * (0.05 * wind.z + 0.025 * (0.4 + wind.z) * own) * h * h;
    w.xyz = root + bendIn(w.xyz - root, wind.xy, ang);
    wn = bendIn(wn, wind.xy, ang);
  }
  v_pos = w.xyz;
  v_nrm = normalize(wn);
  vec3 c = srgb2lin(col.rgb);
  v_col = mix(c, c * tint.rgb, tint.w);
  // sap pulses travel along the part
  float pulse = 0.65 + 0.35 * sin(t * 3.0 - tu.x * 8.0 + ip.z * 6.28);
  v_glow = ip.x * (part == 2u ? 1.0 : 0.06) * pulse;
  v_part = float(part);
  v_t = tu.x;
  v_fade = ip.w;
  v_u = tu.y;
  v_obj = p;
  gl_Position = pc.vp * w;
}
