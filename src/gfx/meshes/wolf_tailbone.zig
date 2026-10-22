//! mesh: WOLF TAILBONE. the knot where the rear's vine structure converges
//! into the tail: short grown stubs radiating out and down into the rump,
//! with one small sap node at the centre where the tail connects. Origin at
//! the knot's centre, in the hips' frame (+Z forward).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

const v3 = m.v3;

/// where the knot sits in the hips' frame: top-centre of the rear, just
/// above and behind the two lobes
pub const at = v3(0, 0.13, -0.11);

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const dirs = [_]m.V3{
    m.norm(v3(1, -0.45, 0.25)), m.norm(v3(-1, -0.45, 0.25)),
    m.norm(v3(0, -0.6, 1)), m.norm(v3(0, -1, -0.35)),
  };
  for (dirs, 0..) |d, i| {
    try mg.vine(b, .{
      .start = v3(0, 0, 0), .direction = d, .length = 0.075,
      .wobble = 0.03, .curl = 0, .taper = 0.5, .seed = 0x7B0 +% i,
    }, 4, 8, 0.04, pal.wolf_core, .stem, 6, 0.3, 0.6);
  }
  // the connection point: translucent through the instance's fade
  try mg.ellipsoid(b, .{.center = v3(0, 0.012, 0), .radii = m.splat(0.03), .col = pal.sap, .part = .bloom, .rings = 6, .segs = 9, .t = 0.3});
}
