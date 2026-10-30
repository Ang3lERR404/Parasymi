//! the engine's light as a world shader reads it: the frame's `Lighting` record (render/light.zig), the key light's cascaded shadows and the points of light.
// The including shader declares first: the extensions GL_EXT_buffer_reference
// and GL_EXT_buffer_reference_uvec2 (and, when built with SHADOW,
// GL_EXT_multiview); push constants `pc` holding `mat4 vp`, `vec4 eye_time`
// (xyz the eye) and `uvec2 light` (the record's address, set by the
// renderer); and `SUN`, the unit direction toward the key light.

// this frame's light (render/light.zig `Lighting`): the key light's shadow
// cascades and the points of light a game makes
const int CASCADES = 3;
const int MAX_LIGHTS = 32;
struct PointLight {
  vec4 pos; // xyz where, w how far it reaches
  vec4 col; // linear rgb times its strength
};
layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer Lighting {
  mat4 cascade[CASCADES]; // world to each cascade's clip space
  float texel[4];         // the world size of each cascade's texels
  vec4 info;              // x points of light, y how far from the eye shadows reach
  PointLight lights[MAX_LIGHTS];
};
// the shadow map: a depth layer per cascade, read with depth compares
layout(set = 0, binding = 0) uniform sampler2DArrayShadow shadow_map;

// where a world point lands on screen (or, drawing shadow casters, in the
// cascade this view draws)
vec4 project(vec3 w) {
#ifdef SHADOW
  return Lighting(pc.light).cascade[gl_ViewIndex] * vec4(w, 1.0);
#else
  return pc.vp * vec4(w, 1.0);
#endif
}
// a vertex placed here is clipped away (what casts no shadow)
const vec4 UNSEEN = vec4(0.0, 0.0, 2.0, 1.0);

// texels apart the shadow filter's taps are
const float SHADOW_TAP = 1.2;
// how far a point is pushed off its surface toward the light (texels), and
// how much more where the light grazes it
const float SHADOW_BIAS = 0.8;
const float SHADOW_SLOPE_BIAS = 2.0;
// how far out across a cascade (0 centre .. 1 rim) it starts blending into
// the next, and is wholly the next
const float CASCADE_BLEND_FROM = 0.82;
const float CASCADE_BLEND_TO = 0.97;
// the share of the shadows' reach past which they fade out
const float SHADOW_FADE = 0.8;

// how much of the key light reaches `wpos` through cascade `i` (1 lit, 0
// in shadow), filtered over 2x2 taps of 2x2 compares each; `edge` how far
// out across the cascade it lies (0 centre .. 1 rim; 2 outside it). The
// point is pushed off its surface toward the light by a texel or so (more
// on slopes the light grazes) so a surface never shadows itself.
float cascadeLit(Lighting L, int i, vec3 wpos, vec3 nl, float slope, out float edge) {
  float tx = L.texel[i];
  vec4 q = L.cascade[i] * vec4(wpos + nl * tx * (SHADOW_BIAS + SHADOW_SLOPE_BIAS * slope), 1.0);
  edge = max(abs(q.x), abs(q.y));
  if (edge >= 1.0 || q.z >= 1.0) {
    edge = 2.0;
    return 1.0;
  }
  vec2 uv = q.xy * 0.5 + 0.5;
  vec2 tap = SHADOW_TAP / vec2(textureSize(shadow_map, 0).xy);
  float s = 0.0;
  for (int y = 0; y < 2; y++) for (int x = 0; x < 2; x++) {
    s += texture(shadow_map, vec4(uv + (vec2(x, y) - 0.5) * tap, float(i), q.z));
  }
  return s * 0.25;
}

// how much of the key light (sun or moon) reaches a surface at `wpos`
// facing `n`: from the nearest cascade holding it, blended into the next
// over its rim so no seam shows, fading out toward the shadows' reach
float keyShadow(vec3 wpos, vec3 n) {
  Lighting L = Lighting(pc.light);
  float far = L.info.y;
  float dist = length(wpos - pc.eye_time.xyz);
  if (dist >= far) return 1.0;
  float ndl = dot(n, SUN);
  vec3 nl = ndl >= 0.0 ? n : -n;
  float slope = sqrt(clamp(1.0 - ndl * ndl, 0.0, 1.0));
  float lit = 1.0;
  for (int i = 0; i < CASCADES; i++) {
    float edge;
    float s = cascadeLit(L, i, wpos, nl, slope, edge);
    if (edge > 1.0) continue;
    float b = smoothstep(CASCADE_BLEND_FROM, CASCADE_BLEND_TO, edge);
    if (b > 0.0) {
      float e2;
      float s2 = i + 1 < CASCADES ? cascadeLit(L, i + 1, wpos, nl, slope, e2) : 1.0;
      s = mix(s, s2, b);
    }
    lit = s;
    break;
  }
  return mix(lit, 1.0, smoothstep(far * SHADOW_FADE, far, dist));
}

// how much of the key light reaches a point in the air `dist` from the eye
// (nothing to push off, so one hardware-filtered tap of the nearest cascade
// holding it, a hair toward the light), fading to lit toward the shadows'
// reach
const float AIR_BIAS = 0.0004;
float airLit(Lighting L, vec3 wpos, float dist) {
  float far = L.info.y;
  if (dist >= far) return 1.0;
  for (int i = 0; i < CASCADES; i++) {
    vec4 q = L.cascade[i] * vec4(wpos, 1.0);
    if (max(abs(q.x), abs(q.y)) >= CASCADE_BLEND_TO || q.z >= 1.0) continue;
    float s = texture(shadow_map, vec4(q.xy * 0.5 + 0.5, float(i), q.z - AIR_BIAS));
    return mix(s, 1.0, smoothstep(far * SHADOW_FADE, far, dist));
  }
  return 1.0;
}

// the light the points of light (a game's blooms, motes, flashes) shed on a
// surface at `wpos` facing `n`: each brightest beside it, gone at its
// reach. `wrap` > 0 lets light reach round thin tissue (0 a plain surface).
const float LIGHT_FALLOFF = 8.0; // how fast a point of light dims with (distance / reach)^2
vec3 pointLight(vec3 wpos, vec3 n, float wrap) {
  Lighting L = Lighting(pc.light);
  int count = int(L.info.x + 0.5);
  vec3 sum = vec3(0.0);
  for (int i = 0; i < count; i++) {
    vec4 lp = L.lights[i].pos;
    vec3 d = lp.xyz - wpos;
    float d2 = dot(d, d);
    float k = d2 / (lp.w * lp.w);
    if (k >= 1.0) continue;
    float win = (1.0 - k) * (1.0 - k);
    float facing = (dot(n, d) * inversesqrt(max(d2, 1e-6)) + wrap) / (1.0 + wrap);
    sum += L.lights[i].col.rgb * max(facing, 0.0) * win / (1.0 + LIGHT_FALLOFF * k);
  }
  return sum;
}
