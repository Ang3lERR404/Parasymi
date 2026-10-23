//! the wolf's rear: one lobe per side, a plump knotted ball of dense vine
//! with small sap nodes at the hip joint and along its lower edge. The two
//! nearly meet at the centre line, reading as one form split down the
//! middle, and hang below the hip joints. Built per side (`wolf_rump_l`,
//! `wolf_rump_r`) rather than mirrored, so winding and lighting stay correct.
//! Origin at the lobe's centre; +X outward for the right lobe, +Z forward.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

const V3 = m.V3;
const v3 = m.v3;

/// each lobe's radii and centre (right side; mirrored) in the hips' frame:
/// nearly round, inner edges 0.004 apart, bottoms below the hip joints (y 0)
pub const radii = v3(0.09, 0.095, 0.09);
pub const centre = v3(radii[0] + 0.002, 0.03, -0.07);

pub fn lobe(b:*mg.Builder, side:f32) Allocator.Error!void {
  // a slightly faceted ball: fewer rings than the soft sap reads as knotted
  try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = radii, .col = pal.wolf_core, .rings = 7, .segs = 10, .t = 0.3});
  // grown vine bands wrapping around it along its curvature
  try mg.bands(b, v3(0, 0, 0), radii, &.{
    .{0.3, 0.2, 2.7, 0.9}, .{0.3, 1.3, 2.7, 2.0}, .{0.3, 2.5, 2.7, 3.3}, .{0.4, -0.9, 2.6, -0.2},
  }, side, 0.016, 0.05, 0x2B0 +% @as(u64, @intFromFloat(side + 2)), pal.wolf_vine);
  // sap nodes: one where the thigh joins (the lobe's outer, lower front) and
  // a few along the lower edge; translucent through the instance's fade
  const nodes = [_]V3{
    v3(0.85, -0.25, 0.3), v3(0.45, -0.85, -0.2), v3(-0.1, -0.9, -0.45), v3(-0.55, -0.75, -0.3),
  };
  for (nodes, 0..) |n, i| {
    const r:f32 = if (i == 0) 0.024 else 0.016;
    try mg.ellipsoid(b, .{.center = n * radii * v3(side, 1, 1), .radii = m.splat3(r), .col = pal.sap, .part = .bloom, .rings = 5, .segs = 7, .t = 0.3});
  }
}
