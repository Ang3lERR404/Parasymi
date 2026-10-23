//! mesh: WOLF BELLY. unit sphere of sap wrapped in a vine net; scaled by how full the player is
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("wolf_kit.zig");

const V3 = m.V3;
const v3 = m.v3;
const vine = pal.wolf_vine;
const sap = pal.sap;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(1, 1, 1), .col = sap, .part = .bloom, .rings = 10, .segs = 14, .t = 0.4});
  // the net: grown vines running pole to pole, twisting as they go,
  // tapering to points at both poles, small leaves lying along them
  for (0..6) |i| {
    const a = m.f(i) / 6 * m.tau;
    var ctrl:[9]V3 = undefined;
    for (0..9) |j| {
      const th = 0.15 + m.f(j) / 8 * (m.pi - 0.3);
      const tw = a + th * 0.5;
      ctrl[j] = v3(@sin(th) * @cos(tw), @cos(th), @sin(th) * @sin(tw)) * m.splat3(1.05);
    }
    var path:[20]V3 = undefined;
    m.splineResample(&ctrl, &path);
    var ts:[20]f32 = undefined;
    var rs:[20]f32 = undefined;
    for (&ts, &rs, 0..) |*t, *r, j| {
      const k = m.ratio(j, 19);
      t.* = 0.4;
      r.* = @max(0.07 * @sqrt(@sin(m.pi * k)), 0.004);
    }
    try b.tubeR(&path, &ts, &rs, vine, .stem, 5);
    for ([_]usize{6, 13}, 0..) |j, n| {
      const out = m.norm(path[j]);
      const tan = m.norm(path[j + 1] - path[j - 1]);
      try kit.leaf(b, .{
        .base = path[j] + out * m.splat3(0.03), .along = if (n == 0) tan else -tan, .out = out,
        .len = 0.4, .width = 0.13, .lift = 0.35, .curl = 0.4, .cup = 0.3,
        .col = pal.wolf_leaf_dark, .tip = pal.wolf_leaf_lite, .t = 0.4,
      });
    }
  }
}
