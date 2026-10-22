//! mesh: NODE LEY
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");

const v3 = m.v3;

pub fn build(b:*mg.Builder) !void {
  var rng = pal.rngFor("node_ley");
  for (0..5) |_| {
    const base = v3(rng.range(-0.22, 0.22), -0.02, rng.range(-0.22, 0.22));
    const dir = m.norm(v3(rng.range(-0.45, 0.45), 1, rng.range(-0.45, 0.45)));
    try b.cone(base, dir, rng.range(0.25, 0.5), rng.range(0.04, 0.07), color.rgb(.{0.7, 0.5, 1.0}, 255), 1, .bloom);
  }
}
