//! mesh: SAP CACHE
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");

const V3 = m.V3;
const v3 = m.v3;
const vine = pal.vine;
const leaf_dark = pal.leaf_dark;
const leaf_lite = pal.leaf_lite;
const sap = pal.sap;

pub fn build(b:*mg.Builder) Allocator.Error!void { try gourd(b, 1); }

/// the sap gourd: a vine-netted body with a sap window and a leaf crown,
/// `scale` times its full size, standing on the origin.
pub fn gourd(b:*mg.Builder, scale:f32) Allocator.Error!void {
  const s = b.mark();
  try mg.ellipsoid(b, .{.center = v3(0, 0.3, 0), .radii = v3(0.33, 0.32, 0.33), .col = color.rgb(.{0.55, 0.38, 0.18}, 255), .rings = 9, .segs = 12, .t = 0.4});
  try mg.ellipsoid(b, .{.center = v3(0, 0.3, 0.27), .radii = v3(0.13, 0.15, 0.08), .col = sap, .part = .bloom, .t = 0.4});
  for (0..5) |i| {
    const a = m.f(i) / 5 * m.tau;
    var path:[7]V3 = undefined;
    var ts:[7]f32 = undefined;
    for (0..7) |j| {
      const th = m.f(j) / 6 * m.pi;
      path[j] = v3(@sin(th) * @cos(a + th * 0.4) * 0.35, 0.3 + @cos(th) * 0.34, @sin(th) * @sin(a + th * 0.4) * 0.35);
      ts[j] = 0.5;
    }
    try b.tube(&path, &ts, 0.025, 0.025, vine, .stem, 4);
  }
  for (0..5) |i| {
    const a = m.f(i) / 5 * m.tau;
    try b.blade(v3(0, 0.6, 0), v3(@cos(a), 0, @sin(a)), 0.22, 0.08, -0.5, leaf_dark, leaf_lite, 1, .leaf);
  }
  if (scale != 1) b.xform(s, m.scale3(m.splat(scale)));
}
