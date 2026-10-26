//! the GPU layouts the engine itself draws with: UI quads and points of
//! light. A game's own vertex and instance layouts live with the game.
//! Pipelines derive their attribute descriptions from these
//! (gfx/pipeline.zig), and the GLSL `layout(location=..)` must match field order.

/// a point of light as the shaders read it from the frame's lighting record
/// (render/light.zig `Lighting`): it lights what lies within its reach,
/// brightest beside it, gone at the edge
pub const Light = extern struct {
  /// xyz where it is, w how far it reaches (world units)
  pos:[4]f32,
  /// linear rgb times its strength; w unused
  col:[4]f32,
};

pub const Ui = extern struct {
  pos:[2]f32,
  /// local coordinates inside the quad: glyph cells (0..6, 0..8) for text,
  /// pixels (0..size) for shapes
  uv:[2]f32,
  /// quad size in pixels (shapes need it for aspect-correct distance fields)
  size:[2]f32,
  col:[4]u8,
  /// glyph: 5x7 bitmap packed row-major (bit 0 = top-left).
  /// shape: x = 0xffffffff, y = shape kind (see ui/draw.zig `Shape`)
  bits:[2]u32,
  /// shape parameters: x value/selection 0..1, y phase/seed
  param:[2]f32,
};
