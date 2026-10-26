//! mesh: NODE LEY. ley shards: a cluster of crystals grown out of a ley
//! line, faceted prisms with pointed terminations fanning up and out from
//! a common root, the tallest at the heart, smaller ones leaning out at
//! its feet. Violet, paling to light at the points, glowing from within
//! (the instance's glow). Tile space, centred on the tile.
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
  var rng = pal.rngFor("node_ley");
  const body = color.rgb(0.42, 0.26, 0.78).toRgba8(255);
  const tip = color.rgb(0.86, 0.74, 1.0).toRgba8(255);
  // the heart: a few tall crystals, nearly upright
  for (0..3) |_| {
    try kit.crystal(b, .{
      .base = v3(rng.range(-0.05, 0.05), -0.03, rng.range(-0.05, 0.05)),
      .dir = m.norm(v3(rng.range(-0.25, 0.25), 1, rng.range(-0.25, 0.25))),
      .len = rng.range(0.38, 0.55), .r = rng.range(0.04, 0.055), .col = body, .tip = tip,
    }, &rng);
  }
  // a ring of smaller ones leaning out around it
  for (0..7) |i| {
    const a = m.ratio(i, 7) * m.tau + rng.range(-0.3, 0.3);
    const d = rng.range(0.07, 0.16);
    try kit.crystal(b, .{
      .base = v3(@cos(a) * d, -0.02, @sin(a) * d),
      .dir = m.norm(v3(@cos(a) * rng.range(0.5, 1.0), 1, @sin(a) * rng.range(0.5, 1.0))),
      .len = rng.range(0.12, 0.26), .r = rng.range(0.022, 0.035), .col = body, .tip = tip,
    }, &rng);
  }
  // a root of dark stone the cluster grows out of
  try kit.stone(b, v3(0, -0.02, 0), 0.13, 0.4, color.rgb(0.2, 0.17, 0.26).toRgba8(255), color.rgb(0.3, 0.26, 0.4).toRgba8(255), &rng);
}
