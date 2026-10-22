//! mesh: ITEM POD. a generic carried item, tinted per item
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const color = @import("../../core/color.zig");

const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(0.09, 0.08, 0.09), .col = color.rgb(.{0.9, 0.9, 0.9}, 255), .part = .bloom, .rings = 5, .segs = 7, .t = 1});
}
