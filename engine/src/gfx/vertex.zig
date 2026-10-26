//! the GPU layouts the engine itself defines: built meshes (with skin and
//! growth records beside them), UI quads and points of light. A game's own
//! instance layouts live with the game.
//! Pipelines derive their attribute descriptions from these
//! (gfx/pipeline.zig), and the GLSL `layout(location=..)` must match field order.
const color = @import("../core/color.zig");

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

pub const Mesh = extern struct {
  pos:[3]f32,
  nrm:[3]f32,
  col:color.Rgba8,
  /// x: height along the thing 0..1 (a game drives growth and sway off it),
  /// y: position along a sheet (a leaf, a petal) 0..1
  tu:[2]f32,
  /// its role (the game's enum, see gfx/meshgen.zig `Mesher`)
  part:u32,
};

/// which bones move a skinned vertex (up to four indices, one per byte,
/// lowest first) and how much each (unorm, summing to one), read beside the
/// mesh buffer vertex for vertex. Meshes that are not skinned leave it zero.
pub const Skin = extern struct {
  bones:u32 = 0,
  weights:[4]u8 = .{0, 0, 0, 0},
  /// how each of the four weights changes across the mesh (per unit of
  /// mesh space, its x, y and z): a skin swelling under a scaled bone
  /// (a filling belly) bends its normals by them, not by the blended bones
  /// alone. Zero where the weights hold still or are not known.
  gx:[4]f32 = @splat(0),
  gy:[4]f32 = @splat(0),
  gz:[4]f32 = @splat(0),
};

/// where a vertex grown along a growth spline grows out of and when, read
/// beside the mesh buffer vertex for vertex. A game's shader keeps it shrunk into `from`
/// until the structure's growth reaches `at[0]`, grows it out over
/// `at[1]`, and thickens it as its spline goes from started (`at[2]`) to
/// done (`at[3]`; equal: no thickening). `at[1]` 0: not on a spline.
pub const Grow = extern struct {
  from:[3]f32 = @splat(0),
  at:[4]f32 = @splat(0),
};

/// the leading fields of `Mesh`, read from a second growth key of the same
/// mesh buffer (same stride) so a mesh can blend between keys.
pub const MeshPose = extern struct {
  pos:[3]f32,
  nrm:[3]f32,
};
comptime {
  if (@offsetOf(MeshPose, "pos") != @offsetOf(Mesh, "pos") or @offsetOf(MeshPose, "nrm") != @offsetOf(Mesh, "nrm"))
    @compileError("MeshPose must mirror the start of Mesh");
}
