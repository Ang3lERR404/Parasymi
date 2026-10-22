//! GPU vertex/instance layouts. Pipelines derive their attribute descriptions
//! from these (gfx/pipeline.zig), and the GLSL `layout(location=..)` must match
//! field order.

pub const Terrain = extern struct {
  pos:[3]f32,
  nrm:[3]f32,
  col:[4]u8,
  /// x: tile kind, y: ley intensity, z: is-top-face, w: unused
  info:[4]u8,
};

pub const Part = enum(u32) { stem, leaf, bloom, thorn, tendril };

pub const Plant = extern struct {
  pos:[3]f32,
  nrm:[3]f32,
  col:[4]u8,
  /// x: height along the plant 0..1 (growth/sway), y: position along a leaf/petal 0..1
  tu:[2]f32,
  part:u32,
};

pub const PlantInstance = extern struct {
  pos:[3]f32,
  /// growth 0..1, mana fill 0..1, seed 0..1, lineage affinity -1..1
  a:[4]f32,
  /// flow, health, 0, 0
  b:[4]f32,
};

pub const Ui = extern struct {
  pos:[2]f32,
  /// glyph-cell coordinates (0..6, 0..8) for bitmap lookup
  uv:[2]f32,
  col:[4]u8,
  /// 5x7 glyph bitmap packed row-major (bit 0 = top-left); all ones = solid quad
  bits:[2]u32,
};
