//! the air as a volume pass reads it (render/volume.zig): the world's depth under each volume texel, the overhead map and the field (fixed to the world, wrapping), the eye's ray through a texel.
// The including shader declares push constants `pc` as light.glsl asks
// (`vp`, `eye_time`, `light`) and includes light.glsl first.

// the world's depth, and the overhead map (what the game drew from straight
// above, a texel a world unit, wrapping every OVERHEAD_SIZE units)
layout(set = 1, binding = 0) uniform sampler2D scene_depth;
layout(set = 1, binding = 1) uniform sampler2D overhead_map;
// the field: the game's own state over the world, laid out as the overhead
// map is (read at `overheadUv`); a `.field` pass reads the last step here
// and writes the next, every pass after it reads the new step
layout(set = 1, binding = 2) uniform sampler2D field_map;

// the pixel volume texel `t` stands for: its 2x2 block's first
ivec2 volumePixel(ivec2 t) { return min(t * 2, textureSize(scene_depth, 0) - 1); }
// the world's depth there (1 where nothing was drawn: the sky)
float volumeDepth(ivec2 t) { return texelFetch(scene_depth, volumePixel(t), 0).r; }
// the world point seen through that pixel at depth `d`, through the inverse
// view-projection `inv`
vec3 volumePoint(mat4 inv, ivec2 t, float d) {
  vec2 ndc = (vec2(volumePixel(t)) + 0.5) / vec2(textureSize(scene_depth, 0)) * 2.0 - 1.0;
  vec4 w = inv * vec4(ndc, d, 1.0);
  return w.xyz / w.w;
}
const float OVERHEAD_SIZE = 512.0; // (render/volume.zig overheadSize; must match)
// where world point `w` lies on the overhead map (its repeating sampler
// wraps it onto the map)
vec2 overheadUv(vec3 w) { return vec2(w.x, -w.z) / OVERHEAD_SIZE; }
