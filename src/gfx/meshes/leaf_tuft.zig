//! mesh: LEAF TUFT
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

const v3 = m.v3;
const leaf_dark = pal.leaf_dark;
const leaf_lite = pal.leaf_lite;

pub fn build(b:*mg.Builder) !void {
  var rng = pal.rngFor("leaf_tuft");
  for (0..5) |i| {
    const a = m.f(i) / 5 * m.tau;
    try b.blade(v3(0, 0, 0), v3(@cos(a), 0, @sin(a)), 0.12 * rng.range(0.8, 1.2), 0.04, -0.4, leaf_dark, leaf_lite, 1, .leaf);
  }
}
