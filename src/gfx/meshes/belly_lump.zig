//! mesh: BELLY LUMP. unit sphere: one of the heavier things the wolf carries,
//! a dark shape seen faintly through the sap belly. Listed before the belly
//! so it is drawn first and the translucent sac blends over it.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const color = @import("../../core/color.zig");

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try mg.ellipsoid(b, .{.center = m.v3(0, 0, 0), .radii = m.v3(1, 1, 1), .col = color.rgb(0.2, 0.09, 0.03).toRgba8(255), .part = .bloom, .rings = 6, .segs = 9, .t = 0.4});
}