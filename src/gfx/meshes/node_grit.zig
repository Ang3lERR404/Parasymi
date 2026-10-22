//! mesh: NODE GRIT. resource nodes, in tile space centred on the tile
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");

const v3 = m.v3;

pub fn build(b:*mg.Builder) !void {
  var rng = pal.rngFor("node_grit");
  for (0..6) |_| {
    const r = rng.range(0.06, 0.14);
    const col = color.rgb(.{rng.range(0.45, 0.6), rng.range(0.42, 0.52), rng.range(0.4, 0.48)}, 255);
    try mg.ellipsoid(b, .{.center = v3(rng.range(-0.3, 0.3), r * 0.4, rng.range(-0.3, 0.3)), .radii = v3(r, r * 0.7, r * rng.range(0.8, 1.2)), .col = col, .rings = 3, .segs = 5});
  }
}
