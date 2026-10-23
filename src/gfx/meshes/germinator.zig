//! mesh: GERMINATOR
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");

const V3 = m.V3;
const v3 = m.v3;
const core = pal.core;
const vine = pal.vine;
const leaf_dark = pal.leaf_dark;
const leaf_lite = pal.leaf_lite;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try mg.ellipsoid(b, .{.center = v3(0, 0.05, 0), .radii = v3(0.95, 0.12, 0.95), .col = core, .rings = 5, .segs = 16});
  for (0..9) |i| {
    const a = m.f(i) / 9 * m.tau;
    try b.blade(v3(@cos(a) * 0.2, 0.12, @sin(a) * 0.2), v3(@cos(a), 0, @sin(a)), 0.8, 0.3, -0.9, leaf_dark, leaf_lite, 0.6, .leaf);
  }
  try mg.ellipsoid(b, .{.center = v3(0, 0.55, 0), .radii = v3(0.38, 0.45, 0.38), .col = color.rgb(0.75, 0.95, 0.5).toRgba8(255), .part = .bloom, .rings = 10, .segs = 14, .t = 0.8});
  for (0..4) |i| {
    const a = m.f(i) / 4 * m.tau + 0.4;
    var path:[8]V3 = undefined;
    var ts:[8]f32 = undefined;
    for (0..8) |j| {
      const k = m.f(j) / 7;
      path[j] = v3(@cos(a) * (0.8 - 0.75 * k), 0.1 + @sin(k * m.pi) * 0.9 + k * 0.3, @sin(a) * (0.8 - 0.75 * k));
      ts[j] = k;
    }
    try b.tube(&path, &ts, 0.05, 0.02, vine, .stem, 5);
  }
}
