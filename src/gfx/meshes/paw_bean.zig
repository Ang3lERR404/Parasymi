//! mesh: PAW BEAN. a small rounded oval of sap, unit size: the toe pads
//! under each foot, and the wolf's nose pad.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try mg.ellipsoid(b, .{.center = m.v3(0, 0, 0), .radii = m.v3(1, 1, 1), .col = pal.sap, .part = .bloom, .rings = 6, .segs = 9, .t = 0.5});
}
