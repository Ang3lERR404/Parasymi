//! mesh: WOLF BELLY. unit sphere of sap wrapped in a vine net; scaled by how full the player is
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

const V3 = m.V3;
const v3 = m.v3;
const vine = pal.wolf_vine;
const sap = pal.sap;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(1, 1, 1), .col = sap, .part = .bloom, .rings = 10, .segs = 14, .t = 0.4});
  for (0..6) |i| {
    const a = m.f(i) / 6 * m.tau;
    var path:[9]V3 = undefined;
    var ts:[9]f32 = undefined;
    for (0..9) |j| {
      const th = m.f(j) / 8 * m.pi;
      const tw = a + th * 0.5;
      path[j] = v3(@sin(th) * @cos(tw), @cos(th), @sin(th) * @sin(tw)) * m.splat(1.05);
      ts[j] = 0.4;
    }
    try b.tube(&path, &ts, 0.07, 0.07, vine, .stem, 4);
  }
}
