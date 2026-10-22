//! mesh: RESEARCH ORB. hovers above the research bloom; spun and bobbed per instance
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const color = @import("../../core/color.zig");

const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(0.22, 0.22, 0.22), .col = color.rgb(.{0.85, 0.7, 1.0}, 255), .part = .bloom, .rings = 10, .segs = 14, .t = 1});
  for (0..8) |i| {
    const a = m.f(i) / 8 * m.tau;
    try b.cone(v3(@cos(a) * 0.32, 0, @sin(a) * 0.32), v3(-@sin(a), 0.2, @cos(a)), 0.14, 0.025, color.rgb(.{1, 0.85, 0.6}, 255), 1, .bloom);
  }
}
