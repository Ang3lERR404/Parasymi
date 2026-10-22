//! mesh: WOLF JOINT. unit-radius knot of vines that hides the seam where two limbs meet
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

const V3 = m.V3;
const v3 = m.v3;
const core = pal.core;
const vine = pal.vine;

pub fn build(b:*mg.Builder) !void {
  try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(1, 1, 1), .col = core, .rings = 8, .segs = 10, .t = 0.5});
  for (0..3) |i| {
    const tilt = m.f(i) * 1.05;
    var loop:[13]V3 = undefined;
    var ts:[13]f32 = undefined;
    for (0..13) |j| {
      const a = m.f(j) / 12 * m.tau;
      const p = v3(@cos(a), 0, @sin(a)) * m.splat(1.02);
      loop[j] = v3(p[0], p[1] * @cos(tilt) - p[2] * @sin(tilt), p[1] * @sin(tilt) + p[2] * @cos(tilt));
      ts[j] = 0.5;
    }
    try b.tube(&loop, &ts, 0.22, 0.22, vine, .stem, 5);
  }
}
