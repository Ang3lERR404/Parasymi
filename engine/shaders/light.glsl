//! the engine's light as a world shader reads it: the frame's `Lighting` record (render/light.zig), the key light's cascaded shadows, the points of light and the shadow cubes of those holding one (render/cube.zig).
// The including shader declares first: the extensions GL_EXT_buffer_reference
// and GL_EXT_buffer_reference_uvec2 (and, when built with SHADOW, or with
// CUBE and SHADOW both, drawing a shadow cube's casters,
// GL_EXT_multiview); push constants `pc` holding `mat4 vp`, `vec4 eye_time`
// (xyz the eye) and `uvec2 light` (the record's address, set by the
// renderer); and `SUN`, the unit direction toward the key light.

// this frame's light (render/light.zig `Lighting`): the key light's shadow
// cascades and the points of light a game makes
const int CASCADES = 3;
const int MAX_LIGHTS = 32;
const int MAX_CUBES = 4;
struct PointLight {
  vec4 pos; // xyz where, w how far it reaches
  vec4 col; // linear rgb times its strength; w its shadow cube plus one (0 none)
};
// a point of light's shadow cube (render/cube.zig `Cube`)
struct Cube {
  vec4 at;      // xyz the light it was drawn round, w how far it reaches (its far plane)
  vec4 lit;     // x which point of light, y how much of its shadow shows, z its near plane
  mat4 face[6]; // world to each face's clip space (+x, -x, +y, -y, +z, -z)
};
layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer Lighting {
  mat4 cascade[CASCADES]; // world to each cascade's clip space
  float texel[4];         // the world size of each cascade's texels
  vec4 info;              // x points of light, y how far from the eye shadows reach
  PointLight lights[MAX_LIGHTS];
  Cube cubes[MAX_CUBES];
};
#ifdef CUBE
// drawing a shadow cube's casters (built with CUBE, which brings SHADOW):
// `pc.light` points at the face being drawn in the record instead
layout(buffer_reference, std430, buffer_reference_align = 16) readonly buffer CubeFace {
  mat4 face;
};
#endif
// the shadow map: a depth layer per cascade, read with depth compares
layout(set = 0, binding = 0) uniform sampler2DArrayShadow shadow_map;
// the same map's raw depths (how far a shadow falls from what casts it)
layout(set = 0, binding = 1) uniform sampler2DArray shadow_depth;
// the points of light's shadow cubes, one a cube, read with depth compares
layout(set = 0, binding = 2) uniform samplerCubeArrayShadow cube_map;

// where a world point lands on screen (or, drawing shadow casters, in the
// cascade this view draws, or the face of the shadow cube)
vec4 project(vec3 w) {
#ifdef CUBE
  return CubeFace(pc.light).face * vec4(w, 1.0);
#elif defined(SHADOW)
  return Lighting(pc.light).cascade[gl_ViewIndex] * vec4(w, 1.0);
#else
  return pc.vp * vec4(w, 1.0);
#endif
}
// a vertex placed here is clipped away (what casts no shadow)
const vec4 UNSEEN = vec4(0.0, 0.0, 2.0, 1.0);

// the shadow filter's taps: a Poisson disc of sixteen, the first eight of
// them (every other one) searching for what casts the shadow
const vec2 POISSON[16] = vec2[16](
  vec2(-0.94201624, -0.39906216), vec2(0.94558609, -0.76890725), vec2(-0.09418410, -0.92938870), vec2(0.34495938, 0.29387760),
  vec2(-0.91588581, 0.45771432), vec2(-0.81544232, -0.87912464), vec2(-0.38277543, 0.27676845), vec2(0.97484398, 0.75648379),
  vec2(0.44323325, -0.97511554), vec2(0.53742981, -0.47373420), vec2(-0.26496911, -0.41893023), vec2(0.79197514, 0.19090188),
  vec2(-0.24188840, 0.99706507), vec2(-0.81409955, 0.91437590), vec2(0.19984126, 0.78641367), vec2(0.14383161, -0.14100790));
// how wide the key light looks (radians): a shadow's edge softens by this
// much for each unit it falls from what casts it, sharp where they touch
const float LIGHT_SPREAD = 0.02;
// how far round (texels) what casts a shadow is searched for, and the
// narrowest and widest a shadow's soft edge grows (texels)
const float BLOCKER_REACH = 6.0;
const float PENUMBRA_MIN = 1.0;
const float PENUMBRA_MAX = 7.0;
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
// in shadow); `edge` how far out across the cascade it lies (0 centre .. 1
// rim; 2 outside it). The point is pushed off its surface toward the light
// by a texel or so (more on slopes the light grazes) so a surface never
// shadows itself. The shadow's edge hardens where it meets what casts it
// and softens as it falls away (the light has a breadth, LIGHT_SPREAD):
// the depth of what stands between is searched round the point, its
// distance gives the soft edge's width, and sixteen compares over a
// Poisson disc that wide (turned by a hash of the place, so no pattern
// bands) filter it.
float cascadeLit(Lighting L, int i, vec3 wpos, vec3 nl, float slope, out float edge) {
  float tx = L.texel[i];
  mat4 C = L.cascade[i];
  vec4 q = C * vec4(wpos + nl * tx * (SHADOW_BIAS + SHADOW_SLOPE_BIAS * slope), 1.0);
  edge = max(abs(q.x), abs(q.y));
  if (edge >= 1.0 || q.z >= 1.0) {
    edge = 2.0;
    return 1.0;
  }
  vec2 uv = q.xy * 0.5 + 0.5;
  vec2 texel = 1.0 / vec2(textureSize(shadow_map, 0).xy);
  // the surface's own plane across the map (receiver plane): how its depth
  // runs per unit of uv, so a tap off to the side is compared with the
  // surface there, never with the point's own depth (a surface tilted to
  // the light, or curving, would shadow itself in dotted lines). The
  // normal in the map's space comes from the cascade's rows' cross products.
  vec3 r0 = vec3(C[0][0], C[1][0], C[2][0]), r1 = vec3(C[0][1], C[1][1], C[2][1]), r2 = vec3(C[0][2], C[1][2], C[2][2]);
  vec3 nc = vec3(dot(cross(r1, r2), nl), dot(cross(r2, r0), nl), dot(cross(r0, r1), nl));
  vec2 dzduv = -2.0 * nc.xy / (sign(nc.z) * max(abs(nc.z), 0.25 * length(nc)));
  // the taps turned by a hash of the place: steady in the world, never banding
  uvec3 cell = uvec3(ivec3(floor(wpos * 512.0)));
  uint h = cell.x * 73856093u ^ cell.y * 19349663u ^ cell.z * 83492791u;
  h = (h ^ (h >> 16)) * 0x7feb352du;
  h = (h ^ (h >> 15)) * 0x846ca68bu;
  h ^= h >> 16;
  float ang = 6.2831853 * float(h) * (1.0 / 4294967296.0);
  mat2 turn = mat2(cos(ang), sin(ang), -sin(ang), cos(ang));
  // what stands between: the mean depth of the blockers round about (all
  // sixteen taps and the point itself, so a thin caster is not missed)
  float sum = 0.0, count = 0.0;
  for (int k = 0; k <= 16; k++) {
    vec2 o = k < 16 ? turn * POISSON[k] * BLOCKER_REACH * texel : vec2(0.0);
    float d = texture(shadow_depth, vec3(uv + o, float(i))).r;
    float z = q.z + min(dot(dzduv, o), 0.0);
    if (d < z) { sum += d; count += 1.0; }
  }
  // nothing found round about: one filtered compare at the point itself
  if (count < 0.5) return texture(shadow_map, vec4(uv, float(i), q.z));
  // how far (world units) the shadow falls from them: the depth between,
  // over the cascade's depth per unit along the light
  float perUnit = length(vec3(L.cascade[i][0][2], L.cascade[i][1][2], L.cascade[i][2][2]));
  float gap = (q.z - sum / count) / max(perUnit, 1e-6);
  float pen = clamp(gap * LIGHT_SPREAD / tx, PENUMBRA_MIN, PENUMBRA_MAX);
  float s = 0.0;
  for (int k = 0; k < 16; k++) {
    vec2 o = turn * POISSON[k] * pen * texel;
    s += texture(shadow_map, vec4(uv + o, float(i), q.z + min(dot(dzduv, o), 0.0)));
  }
  return s / 16.0;
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

// the depth a shadow cube from `near` to `far` holds for a point `along`
// units out along the axis of the face it lies in (render/cube.zig `depth`)
float cubeDepth(float near, float far, float along) { return far / (far - near) - far * near / ((far - near) * along); }
// how far a point is held back toward its light before its cube is
// compared (texels of the face there), so what casts never shades itself
const float CUBE_BIAS = 1.5;
// how much of shadow cube `s`'s light reaches `wpos` (1 lit, 0 in its
// shadow): one hardware-filtered compare (its 2x2 texels, across the faces'
// seams as one surface) along the way from the light. Nearer the light than
// its near plane, or beyond its reach, all of it.
float cubeLit(Lighting L, int s, vec3 wpos) {
  vec4 at = L.cubes[s].at;
  vec3 d = wpos - at.xyz;
  vec3 ad = abs(d);
  float along = max(ad.x, max(ad.y, ad.z));
  float near = L.cubes[s].lit.z;
  if (along >= at.w) return 1.0;
  float texel = 2.0 * along / float(textureSize(cube_map, 0).x);
  float z = cubeDepth(near, at.w, max(along - CUBE_BIAS * texel, near));
  return texture(cube_map, vec4(d, float(s)), z);
}
// how far a surface point is lifted off its surface toward a shadowed
// light before it is looked up (texels of the face there)
const float CUBE_NORMAL_BIAS = 2.0;
// how much of point of light `i`'s light reaches a surface at `wpos`
// facing `n` (either side), through its shadow cube if it holds one, as
// far as that shadow has eased in; 1 for a light with none
float pointShadow(Lighting L, int i, vec3 wpos, vec3 n, vec3 d) {
  int s = int(L.lights[i].col.w + 0.5) - 1;
  if (s < 0) return 1.0;
  float shown = L.cubes[s].lit.y;
  if (shown <= 0.0) return 1.0;
  vec3 nl = dot(n, d) >= 0.0 ? n : -n;
  float texel = 2.0 * length(d) / float(textureSize(cube_map, 0).x);
  return mix(1.0, cubeLit(L, s, wpos + nl * CUBE_NORMAL_BIAS * texel), shown);
}

// the light the points of light (a game's blooms, motes, flashes) shed on a
// surface at `wpos` facing `n`: each brightest beside it, gone at its
// reach, and where it holds a shadow cube, blocked by what stands between.
// `wrap` > 0 lets light reach round thin tissue (0 a plain surface).
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
    float win = (1.0 - k) * (1.0 - k) * pointShadow(L, i, wpos, n, d);
    float facing = (dot(n, d) * inversesqrt(max(d2, 1e-6)) + wrap) / (1.0 + wrap);
    sum += L.lights[i].col.rgb * max(facing, 0.0) * win / (1.0 + LIGHT_FALLOFF * k);
  }
  return sum;
}
