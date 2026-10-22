//! mesh: NODE FIBRE
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");

const V3 = m.V3;
const v3 = m.v3;

pub fn build(b:*mg.Builder) !void {
  var rng = pal.rngFor("node_fibre");
  for (0..7) |_| {
    const a = rng.range(0, m.tau);
    const r0 = rng.range(0.05, 0.2);
    const r1 = r0 + rng.range(0.12, 0.25);
    const h = rng.range(0.08, 0.2);
    var path:[6]V3 = undefined;
    var ts:[6]f32 = undefined;
    for (0..6) |j| {
      const k = m.f(j) / 5;
      const r = m.lerp(r0, r1, k);
      path[j] = v3(@cos(a + k * 0.6) * r, @sin(k * m.pi) * h - 0.02, @sin(a + k * 0.6) * r);
      ts[j] = k;
    }
    try b.tube(&path, &ts, 0.022, 0.012, color.rgb(.{0.55, 0.45, 0.28}, 255), .tendril, 4);
  }
  try mg.ellipsoid(b, .{.center = v3(0, 0.02, 0), .radii = v3(0.09, 0.05, 0.09), .col = color.rgb(.{0.3, 0.5, 0.22}, 255), .rings = 4, .segs = 7});
}
