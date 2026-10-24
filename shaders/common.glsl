// shared push constants + lighting for world passes.
#extension GL_EXT_buffer_reference : require
#extension GL_EXT_buffer_reference_uvec2 : require
#ifdef SHADOW
// a shadow caster draws into every cascade at once, one view each
#extension GL_EXT_multiview : require
#endif
layout(push_constant) uniform Push {
  mat4 vp;
  vec4 eye_time;  // xyz camera eye, w time (s)
  vec4 fog;       // rgb fog/sky colour (linear), w fog density
  vec4 misc;      // x veil 0..1, y ley sight 0/1, zw hovered tile (x,z)
  vec4 sun;       // xyz direction toward the key light (sun or moon), w daylight 0..1
  vec4 feet[2];   // the wolf's paws: xyz world position, w facing yaw
  vec4 view;      // xy camera target (x,z), z fog-out start, w fog-out end (horizontal)
  uvec2 bones;    // the parts pass: the address of this frame's bones (part.vert)
  uvec2 light;    // the address of this frame's Lighting
} pc;

#define SUN pc.sun.xyz

// this frame's light (render/light.zig `Lighting`): the key light's shadow
// cascades and the points of light the garden makes
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

const float TAU = 6.2831853;
// how tight the sheen along fibres is (anisotropic highlight exponent)
const float SHEEN_POWER = 40.0;

// a thin film's hue: one turn of the rainbow per unit of `x`.
vec3 filmHue(float x) { return 0.5 + 0.5 * cos(TAU * (vec3(0.0, 0.33, 0.67) + x)); }

// the highlight of light (half vector `H`) along fibres running `tgrad`
// (unnormalised, its length `tl` > 0) over a surface with normal `n`.
float fibreSheen(vec3 tgrad, float tl, vec3 n, vec3 H) {
  vec3 T = normalize(tgrad / tl - n * dot(tgrad / tl, n) + 1e-6);
  float th = dot(T, H);
  return pow(sqrt(max(1.0 - th * th, 0.0)), SHEEN_POWER);
}

// the one wind over the whole garden at a point (x,z): its heading (xy,
// unit) drifts slowly, and broad gusts (z, 0..1, mostly calm) roll across
// it as a wave, so neighbours lean together; w is the point's distance
// along the wind, which later motion is phased by.
vec4 gardenWind(float t, vec2 at) {
  float head = 0.6 + 0.35 * sin(t * 0.031);
  vec2 wdir = vec2(cos(head), sin(head));
  float along = dot(at, wdir);
  float gust = 0.5 + 0.5 * sin(t * 0.32 - along * 0.16);
  return vec4(wdir, gust * gust, along);
}

// turn `v` about the origin by `ang` in the vertical plane holding `wdir`
// (positive: its top toward the wind's heading).
vec3 bendIn(vec3 v, vec2 wdir, float ang) {
  float ca = cos(ang), sa = sin(ang);
  float a0 = dot(v.xz, wdir);
  float a1 = a0 * ca + v.y * sa;
  v.y = v.y * ca - a0 * sa;
  v.xz += wdir * (a1 - a0);
  return v;
}

vec3 hash33(vec3 p) {
  p = fract(p * vec3(0.1031, 0.1030, 0.0973));
  p += dot(p, p.yxz + 33.33);
  return fract((p.xxy + p.yxx) * p.zyx);
}

// bubbles floating up through sap: a rim-lit ring mask, sampled at two
// depths behind the surface along the view so they hang inside it. `obj`
// is the mesh-space point (they ride with the body), `view` toward the eye.
float sapBubbles(vec3 obj, vec3 view, float t) {
  float b = 0.0;
  for (int l = 0; l < 2; l++) {
    float fl = float(l);
    vec3 q = (obj - view * (0.012 + 0.02 * fl)) * (36.0 - 10.0 * fl) - vec3(0.0, t * (0.3 + 0.12 * fl), 0.0);
    vec3 id = floor(q);
    vec3 h = hash33(id + fl * 19.0);
    if (h.x > 0.3) continue;
    vec3 c = id + 0.3 + 0.4 * h.yzx;
    c.x += 0.1 * sin(t * 0.8 + h.z * TAU);
    float r = 0.08 + 0.14 * h.y;
    float d = length(q - c);
    // a thin bright skin, a clear middle
    b += (smoothstep(r, r * 0.78, d) - 0.7 * smoothstep(r * 0.72, r * 0.35, d)) * (1.0 - 0.45 * fl);
  }
  return b;
}

// beads of sap clinging to a surface, sliding slowly down it: x the bead,
// y its glint (a dome lit off-centre by `light`)
vec2 sapDroplets(vec3 obj, vec3 n, vec3 light, vec3 view, float t) {
  vec3 q = obj * 52.0 + vec3(0.0, t * 0.1, 0.0);
  vec3 id = floor(q);
  vec3 h = hash33(id + 7.0);
  if (h.x > 0.4) return vec2(0.0);
  vec3 c = id + 0.28 + 0.44 * h.yzx;
  float r = 0.14 + 0.16 * h.z;
  // drawn out down the surface, heavier at the bottom
  vec3 d = q - c;
  d.y *= d.y > 0.0 ? 1.4 : 0.8;
  float l = length(d);
  float bead = smoothstep(r, r * 0.7, l);
  vec3 bn = normalize(n + (d / r) * 0.9);
  float glint = pow(max(dot(reflect(-light, bn), view), 0.0), 48.0);
  return vec2(bead, bead * glint);
}

vec3 srgb2lin(vec3 c) { return pow(c, vec3(2.2)); }

// texels apart the shadow filter's taps are
const float SHADOW_TAP = 1.2;

// how much of the key light reaches `wpos` through cascade `i` (1 lit, 0
// in shadow), filtered over 2x2 taps of 2x2 compares each; `edge` how far
// out across the cascade it lies (0 centre .. 1 rim; 2 outside it). The
// point is pushed off its surface toward the light by a texel or so (more
// on slopes the light grazes) so a surface never shadows itself.
float cascadeLit(Lighting L, int i, vec3 wpos, vec3 nl, float slope, out float edge) {
  float tx = L.texel[i];
  vec4 q = L.cascade[i] * vec4(wpos + nl * tx * (0.8 + 2.0 * slope), 1.0);
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
    float b = smoothstep(0.82, 0.97, edge);
    if (b > 0.0) {
      float e2;
      float s2 = i + 1 < CASCADES ? cascadeLit(L, i + 1, wpos, nl, slope, e2) : 1.0;
      s = mix(s, s2, b);
    }
    lit = s;
    break;
  }
  return mix(lit, 1.0, smoothstep(far * 0.8, far, dist));
}

// the light the garden's points of light (blooms, motes, a halo) shed on a
// surface at `wpos` facing `n`: each brightest beside it, gone at its
// reach. `wrap` > 0 lets light reach round thin tissue (0 a plain surface).
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
    sum += L.lights[i].col.rgb * max(facing, 0.0) * win / (1.0 + 8.0 * k);
  }
  return sum;
}

// the key light's colour and strength (the sun by day, the moon by night)
vec3 keyLight() {
  return mix(vec3(0.35, 0.45, 0.8) * 0.35, vec3(1.0, 0.95, 0.85) * 1.1, pc.sun.w);
}

// a surface lit by the sky, the key light (`sh` of it reaching it, see
// keyShadow) and the points of light
vec3 shadeLit(vec3 albedo, vec3 n, vec3 wpos, float sh) {
  float ndl = max(dot(n, SUN), 0.0);
  float day = pc.sun.w;
  vec3 sky = mix(vec3(0.35, 0.40, 0.50), vec3(0.45, 0.30, 0.65), pc.misc.x);
  sky = mix(vec3(0.07, 0.09, 0.18), sky, day);
  vec3 ground = vec3(0.12, 0.10, 0.08) * mix(0.3, 1.0, day);
  vec3 amb = mix(ground, sky, n.y * 0.5 + 0.5) * 0.55;
  vec3 sun = keyLight() * ndl * sh;
  return albedo * (amb + sun + pointLight(wpos, n, 0.0));
}

vec3 shade(vec3 albedo, vec3 n, vec3 wpos) { return shadeLit(albedo, n, wpos, keyShadow(wpos, n)); }


vec3 applyFog(vec3 c, vec3 wpos) {
  float d = length(wpos - pc.eye_time.xyz);
  float f = 1.0 - exp(-pow(d * pc.fog.w, 2.0));
  // the drawn world ends a little before the streamed one: close it into the
  // horizon so a low camera never sees an edge
  f = max(f, smoothstep(pc.view.z, pc.view.w, length(wpos.xz - pc.view.xy)));
  return mix(c, pc.fog.rgb, clamp(f, 0.0, 1.0));
}

// a halo forming (game/structures/polyp.zig): over k 0..1 its blooms spiral
// in from their corners to its centre, the share of the way covered growing
// as e^(HALO_RUSH k) (a crawl, then a rush) while they turn HALO_TURNS times
// around it, folding back toward buds over the last HALO_FOLD of it
const float HALO_RUSH = 4.0;
const float HALO_TURNS = 1.25;
const float HALO_FOLD = 0.3;
float haloPull(float k) { return (exp(HALO_RUSH * clamp(k, 0.0, 1.0)) - 1.0) / (exp(HALO_RUSH) - 1.0); }
float haloFold(float k) { return smoothstep(1.0 - HALO_FOLD, 1.0, k); }
// how far around the centre a bloom has turned by k (radians)
float haloTurn(float k) { return HALO_TURNS * TAU * haloPull(k); }
// where a point riding with a bloom is at k: its way out from the centre
// turned and shortened
vec3 haloSpiral(vec3 p, vec3 centre, float k) {
  float pull = haloPull(k);
  float a = haloTurn(k);
  vec3 d = p - centre;
  float c = cos(a), s = sin(a);
  return centre + vec3(d.x * c - d.z * s, d.y, d.x * s + d.z * c) * (1.0 - pull);
}

// light split into its spectrum, x 0 red .. 1 violet, as a prism or an ice
// halo fans it out
vec3 spectral(float x) {
  x = clamp(x, 0.0, 1.0);
  return vec3(
    smoothstep(0.42, 0.0, x) + 0.55 * smoothstep(0.78, 1.0, x),
    smoothstep(0.02, 0.32, x) * smoothstep(0.82, 0.45, x),
    smoothstep(0.38, 0.75, x)
  );
}
