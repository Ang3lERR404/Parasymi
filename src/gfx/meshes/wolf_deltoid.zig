//! mesh: WOLF DELTOID. a rounded cap of dense vine (1.4x the arm radius)
//! over the shoulder joint, overlapping both the upper arm and the torso,
//! so the arm reads as attached to a body. Origin at the joint.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const upper = @import("wolf_upper_arm.zig");

const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const r = upper.ARM_R * 1.4;
  const radii = v3(r * 0.95, r * 1.05, r);
  const at = v3(0, -0.015, 0);
  try mg.ellipsoid(b, .{.center = at, .radii = radii, .col = pal.wolf_core, .rings = 8, .segs = 10, .t = 0.3});
  try mg.bands(b, at, radii, &.{.{0.3, -1.2, 2.4, -0.4}, .{0.3, 1.9, 2.4, 2.8}}, 1, 0.012, 0.04, 0xDE17, pal.wolf_vine);
}
