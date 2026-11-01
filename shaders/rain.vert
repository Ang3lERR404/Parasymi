#version 450
//! rain grown on the GPU from the moisture field (render/passes/rain.zig): a drop over every spot near the view, falling from the cloud's belly wherever the field rains there, as many as the rain is heavy, leaning on the wind, splashing a ring where it lands.
#extension GL_GOOGLE_include_directive : require
#include "common.glsl"
#include "volume.glsl"

// Each instance is one drop: a spot on a grid fixed to the world round the
// view (so drops never swim as the camera moves), two layers of them, each
// falling on its own from the cloud's belly to the ground over and over. A
// drop shows only where the field rains (its blue), and only as many drops
// as the rain is heavy. Its first six vertices are its streak, a thin strip
// along its fall turned toward the eye; the last six its splash, a ring
// flat on the ground, spreading and fading after it lands. Whichever of the
// two is not showing folds to nothing outside the view.

// where on the drop (streak: along 0 tail .. 1 head, across -1..1; splash:
// across the ring, -1..1 each way), which it is (0 streak, 1 splash), how
// far through its splash, and where it is in the world
layout(location = 0) out vec2 v_local;
layout(location = 1) flat out float v_kind;
layout(location = 2) out float v_fade;
layout(location = 3) out vec3 v_pos;

// spots along each side of the grid, how far apart, and its layers (match
// render/passes/rain.zig `drops`)
const int COLS = 136;
const float SPACING = 0.32;
const int LAYERS = 2;
// the cloud's belly the drops fall from (over the ground) and how fast they
// fall (units/s); how long a streak is, how wide, how far the wind leans it
// (a share of its pace); how long a splash spreads (s) and how wide it grows
const float BELLY = 4.7;
const float FALL = 9.0;
const float STREAK = 0.6;
const float WIDTH = 0.013;
const float WIND_LEAN = 0.12;
const float SPLASH = 0.22;
const float SPLASH_R = 0.09;
// the two triangles of a quad, corner by corner
const vec2 QUAD[6] = vec2[](vec2(-1.0, 0.0), vec2(1.0, 0.0), vec2(1.0, 1.0), vec2(-1.0, 0.0), vec2(1.0, 1.0), vec2(-1.0, 1.0));
// what folds a vertex away: outside the view
const vec4 GONE = vec4(2.0, 2.0, 2.0, 1.0);

void main() {
  float t = pc.eye_time.w;
  int per = COLS * COLS;
  int layer = gl_InstanceIndex / per;
  int k = gl_InstanceIndex - layer * per;
  // the spot: the grid's corner under the view, this drop's cell from it,
  // jittered in its cell
  vec2 corner = floor(pc.view.xy / SPACING) - float(COLS / 2);
  vec2 cell = corner + vec2(float(k % COLS), float(k / COLS));
  vec3 h = hash33(vec3(cell, float(layer) * 17.0));
  vec2 xz = (cell + h.xy) * SPACING;
  // the rain there, and whether this drop falls in it
  vec2 uv = overheadUv(vec3(xz.x, 0.0, xz.y));
  float rain = texture(field_map, uv).b;
  int corner6 = gl_VertexIndex % 6;
  bool splash = gl_VertexIndex >= 6;
  if (h.z >= rain) { gl_Position = GONE; return; }
  // its fall: from the belly over the ground to it, then its splash
  float ground = texture(overhead_map, uv).a;
  float fallT = BELLY / FALL;
  float period = fallT + SPLASH;
  float into = fract(t / period + hash33(vec3(cell, 3.0 + float(layer))).x) * period;
  bool landed = into >= fallT;
  if (splash != landed) { gl_Position = GONE; return; }
  // the wind leaning it, and the way it falls
  vec2 w = gardenWind(t, xz).xy * WIND_LEAN;
  vec3 down = normalize(vec3(w.x, -1.0, w.y));
  vec2 q = QUAD[corner6];
  vec3 p;
  if (!landed) {
    // the streak: its head falling from the belly, its tail behind it,
    // its width turned toward the eye
    vec3 head = vec3(xz.x, ground, xz.y) - down * (BELLY - into * FALL);
    vec3 tail = head - down * STREAK;
    vec3 side = normalize(cross(down, pc.eye_time.xyz - head)) * WIDTH;
    p = mix(tail, head, q.y) + side * q.x;
    v_local = vec2(q.y, q.x);
    v_kind = 0.0;
    v_fade = 0.0;
  } else {
    // the splash: a ring flat on the ground where it landed, spreading
    float s = (into - fallT) / SPLASH;
    float r = SPLASH_R * (0.3 + 0.7 * s);
    vec2 c = vec2(q.x, q.y * 2.0 - 1.0);
    p = vec3(xz.x, ground + 0.01, xz.y) + vec3(c.x, 0.0, c.y) * r;
    v_local = c;
    v_kind = 1.0;
    v_fade = s;
  }
  v_pos = p;
  gl_Position = pc.vp * vec4(p, 1.0);
}
