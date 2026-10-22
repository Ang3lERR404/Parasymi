//! mesh: ROOT-DIGGER. the central knot: a sap gourd at 40%, sunk into a
//! woody collar the roots (`digger_root`, emitted per root) grow out of
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const sap_cache = @import("sap_cache.zig");

const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try mg.ellipsoid(b, .{.center = v3(0, 0.05, 0), .radii = v3(0.17, 0.09, 0.17), .col = pal.core, .rings = 6, .segs = 10, .t = 0.2});
  const s = b.mark();
  try sap_cache.gourd(b, 0.4);
  b.xform(s, m.translate(v3(0, 0.06, 0)));
}
