//! mesh: MOTE
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const color = @import("../../core/color.zig");

const V3 = m.V3;
const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(0.06, 0.06, 0.06), .col = color.rgb(.{1, 0.95, 0.75}, 255), .part = .bloom, .rings = 4, .segs = 6, .t = 1});
  for ([_]V3{v3(1, 0, 0), v3(-1, 0, 0), v3(0, 1, 0), v3(0, -1, 0), v3(0, 0, 1), v3(0, 0, -1)}) |d| {
    try b.cone(d * m.splat(0.03), d, 0.11, 0.018, color.rgb(.{1, 0.9, 0.6}, 255), 1, .bloom);
  }
}
