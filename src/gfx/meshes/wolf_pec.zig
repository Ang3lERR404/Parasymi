//! mesh: WOLF PECTORAL. unit lobe of solidified sap; instances squash it into
//! a plump seed shape over each side of the chest (see wolf_torso `pecs`)
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try mg.ellipsoid(b, .{.center = m.v3(0, 0, 0), .radii = m.v3(1, 1, 1), .col = pal.sap, .part = .bloom, .rings = 9, .segs = 14, .t = 0.6});
}
