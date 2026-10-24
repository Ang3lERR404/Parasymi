// shared by the post-processing passes (render/post.zig): each reads the
// screen triangle's uv (post.vert) and writes one colour. Their push
// constants (not common.glsl's: these passes draw no world).
layout(location = 0) in vec2 v_uv;
layout(location = 0) out vec4 o;
layout(push_constant) uniform Push {
  vec2 texel;      // one texel of the image read (uv)
  float threshold; // bloom's first step down: what counts as brighter than white (0 later steps)
  float intensity; // how strongly the glow is laid over the scene
} pc;
