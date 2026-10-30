#version 450
//! the air laid over the world: each pixel takes the 4x4 half-size volume texels round it, softly weighted and by how near their depth lies to its own, and veils the HDR image with them.

// the air laid over the world (render/volume.zig). The volume is half the
// screen's size, each texel marched from the depth of its 2x2 block's first
// pixel; a pixel takes the 4x4 texels round it under a tent two texels
// wide (smoothing away the march's dither), each weighted down as its depth
// parts from the pixel's own, so the air in front of a stem does not bleed
// onto the ground behind it. Where none of them matches,
// the nearest in depth is taken. The pipeline blends premultiplied: what the
// air sends is added on, what lies behind kept by how much shows through.
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 o;
layout(set = 0, binding = 0) uniform sampler2D volume;
layout(set = 0, binding = 1) uniform sampler2D depth;

// how sharply a texel's weight falls as its depth parts from the pixel's
// (per unit of log distance)
const float EDGE = 10.0;
// below this summed weight no texel matches the pixel
const float NONE = 1e-3;

// a depth as the log of a distance (up to a constant): 1 / (1 - d) grows
// with distance for any perspective whose far plane lies far past its near
float logDist(float d) { return log(1.0 / max(1.0 - d, 1e-7)); }

void main() {
  ivec2 px = ivec2(gl_FragCoord.xy);
  ivec2 last = textureSize(volume, 0) - 1;
  ivec2 full = textureSize(depth, 0) - 1;
  float here = logDist(texelFetch(depth, px, 0).r);
  // the pixel in the volume's texels (texel i is pixel 2i's)
  vec2 p = vec2(px) * 0.5;
  ivec2 base = ivec2(floor(p));
  vec4 sum = vec4(0.0);
  float weight = 0.0;
  vec4 best = vec4(0.0, 0.0, 0.0, 1.0);
  float bestGap = 1e9;
  for (int i = 0; i < 16; i++) {
    ivec2 off = ivec2(i & 3, i >> 2) - 1;
    ivec2 t = clamp(base + off, ivec2(0), last);
    float gap = abs(logDist(texelFetch(depth, min(t * 2, full), 0).r) - here);
    vec4 v = texelFetch(volume, t, 0);
    vec2 b = max(1.0 - abs(vec2(base + off) - p) * 0.5, 0.0);
    float w = b.x * b.y * exp(-EDGE * gap);
    sum += v * w;
    weight += w;
    if (gap < bestGap) { bestGap = gap; best = v; }
  }
  vec4 air = weight > NONE ? sum / weight : best;
  o = vec4(air.rgb, 1.0 - air.a);
}
