//! mesh: WOLF UPPER ARM. shoulder at origin, elbow at +Y LEN (the rig turns
//! it downward, so mesh -Z faces the arm's front). A lean core with two
//! separate muscle forms over it: a bicep peaking at 30% on the front and a
//! tricep peaking at 70% on the back, a groove between them.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

const V3 = m.V3;
const v3 = m.v3;

pub const LEN:f32 = 0.25;
/// the arm's reference radius (the deltoid is 1.4x this)
pub const ARM_R:f32 = 0.06;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const N = 12;
  var spine:[N]V3 = undefined;
  var ts:[N]f32 = undefined;
  var radii:[N]f32 = undefined;
  for (0..N) |i| {
    const k = m.ratio(i, N - 1);
    spine[i] = v3(0, k * LEN, 0);
    ts[i] = k;
    radii[i] = ARM_R * m.lerp(0.85, 0.75, k);
  }
  try b.tubeR(&spine, &ts, &radii, pal.wolf_core, .stem, 8);
  try mg.ellipsoid(b, .{.center = v3(0, 0.3 * LEN, -0.02), .radii = v3(0.052, 0.072, 0.045), .col = pal.wolf_vine, .rings = 8, .segs = 10, .t = 0.35});
  try mg.ellipsoid(b, .{.center = v3(0, 0.7 * LEN, 0.022), .radii = v3(0.05, 0.078, 0.044), .col = pal.wolf_vine, .rings = 8, .segs = 10, .t = 0.65});
}
