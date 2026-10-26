//! mesh: NODE GRIT. mineral grit breaking out of the ground: a cluster of
//! faceted stones half sunk in the soil, grit and pebbles heaped around
//! them, and pale quartz chips glinting out of the cracks. Tile space,
//! centred on the tile.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const engine = lib.engine;
const m = engine.core.math;
const mg = lib.meshgen;
const pal = lib.palette;
const color = engine.core.color;
const kit = lib.mineral_kit;

const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var rng = pal.rngFor("node_grit");
  // the big stones, then a scatter of grit around them
  for (0..13) |i| {
    const big = i < 4;
    const a = rng.range(0, m.tau);
    const d = if (big) rng.range(0.0, 0.2) else rng.range(0.18, 0.38);
    const r = if (big) rng.range(0.09, 0.15) else rng.range(0.025, 0.05);
    const g = rng.range(0.42, 0.56);
    const col = color.rgb(g + 0.04, g, g - 0.03).toRgba8(255);
    const lite = color.rgb(g + 0.16, g + 0.13, g + 0.1).toRgba8(255);
    try kit.stone(b, v3(@cos(a) * d, -0.01, @sin(a) * d), r, if (big) rng.range(0.7, 1.0) else 0.6, col, lite, &rng);
  }
  // quartz chips in the cracks between the stones
  for (0..5) |_| {
    const a = rng.range(0, m.tau);
    const d = rng.range(0.06, 0.22);
    try kit.crystal(b, .{
      .base = v3(@cos(a) * d, 0.0, @sin(a) * d), .dir = m.norm(v3(@cos(a) * 0.5, 1, @sin(a) * 0.5)),
      .len = rng.range(0.06, 0.12), .r = rng.range(0.012, 0.02), .sides = 5,
      .col = color.rgb(0.78, 0.76, 0.72).toRgba8(255), .tip = color.rgb(0.95, 0.94, 0.9).toRgba8(255), .part = .thorn,
    }, &rng);
  }
}
