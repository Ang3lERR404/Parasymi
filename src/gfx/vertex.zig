//! GPU vertex/instance layouts. Pipelines derive their attribute descriptions
//! from these (gfx/pipeline.zig), and the GLSL `layout(location=..)` must match
//! field order.
const color = @import("../core/color.zig");

pub const Terrain = extern struct {
  pos:[3]f32,
  nrm:[3]f32,
  col:color.Rgba8,
  /// x: tile kind, y: ley intensity, z: is-top-face, w: unused
  info:[4]u8,
};

/// shading role of a vertex; shaders key secondary motion and glow off it.
/// `ear`: a leaf whose inner face (opposite its normal) is lined with sap.
/// `resin`: solidified sap, thick and dense at its base (tu.y 0) thinning
/// toward its surface (tu.y 1); the instance's `give` moves the surface
/// while the base holds.
pub const Part = enum(u32) { stem, leaf, bloom, thorn, tendril, ear, resin };

pub const Mesh = extern struct {
  pos:[3]f32,
  nrm:[3]f32,
  col:color.Rgba8,
  /// x: height along the plant 0..1 (growth/sway), y: position along a leaf/petal 0..1
  tu:[2]f32,
  part:u32,
};

/// the leading fields of `Mesh`, read from a second growth key of the same
/// mesh buffer (same stride) so a plant can blend between keys.
pub const MeshPose = extern struct {
  pos:[3]f32,
  nrm:[3]f32,
};
comptime {
  if (@offsetOf(MeshPose, "pos") != @offsetOf(Mesh, "pos") or @offsetOf(MeshPose, "nrm") != @offsetOf(Mesh, "nrm"))
    @compileError("MeshPose must mirror the start of Mesh");
}

pub const PlantInstance = extern struct {
  pos:[3]f32,
  /// growth 0..1, mana fill 0..1, seed 0..1, lineage affinity -1..1
  a:[4]f32,
  /// flow, health, sway amplitude, genome form (species.Form)
  b:[4]f32,
  /// x: blend toward the next growth key (0..1); y, z, w unused
  c:[4]f32 = .{0, 0, 0, 0},
};

/// a rigid procedural part (creature limb, resource node, mote, structure piece).
pub const PartInstance = extern struct {
  /// model matrix columns
  c0:[4]f32,
  c1:[4]f32,
  c2:[4]f32,
  c3:[4]f32,
  /// x glow, y flutter (leaf secondary motion), z phase 0..1, w alpha-ish fade
  p:[4]f32,
  /// rgb colour multiply, w blend amount
  tint:[4]f32,
  /// x sag: outward bulge of a sac, heavier at its bottom and front (0 = none);
  /// yzw give: how far a resin part's surface is pushed (mesh space), its base held
  q:[4]f32,
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
