//! mesh: NODE FIBRE. a clump of fibre plant: long fibrous stalks rising
//! from a tuft of roots in a loose vase, arching out under their own weight,
//! green at the root and drying to straw at their tapering tips, small
//! leaves along a few of them. It sways like any plant (the instance's
//! sway). Tile space, centred on the tile.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const engine = lib.engine;
const m = engine.core.math;
const mg = lib.meshgen;
const pal = lib.palette;
const color = engine.core.color;
const kit = lib.structure_kit;

const V3 = m.V3;
const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var rng = pal.rngFor("node_fibre");
  try kit.rootMat(b, 5, 0.22, 0.025, 0x1F1B, null);
  const straw = color.rgb(0.62, 0.52, 0.3).toRgba8(255);
  const green = color.rgb(0.32, 0.5, 0.24).toRgba8(255);
  for (0..16) |i| {
    const a = m.ratio(i, 16) * m.tau + rng.range(-0.2, 0.2);
    const out = v3(@cos(a), 0, @sin(a));
    const len = rng.range(0.28, 0.5);
    const lean = rng.range(0.25, 0.7);
    var c:[6]V3 = undefined;
    mg.growthPath(.{.start = out * m.splat3(0.02), .direction = m.norm(out * m.splat3(lean) + v3(0, 1, 0)), .length = len, .wobble = 0.2, .curl = 0.05, .seed = 0xF1B0 +% i}, &c);
    // they arch out and over as they go (the root stays put)
    for (c[1..], 1..) |*p, j| {
      const k = m.ratio(j, 5);
      p.* += out * m.splat3(0.12 * k * k * lean) - v3(0, 0.08 * k * k * k * lean, 0);
    }
    var p:[14]V3 = undefined;
    m.splineResample(&c, &p);
    var ts:[14]f32 = undefined;
    var rs:[14]f32 = undefined;
    var cs:[14]color.Rgba8 = undefined;
    for (&ts, &rs, &cs, 0..) |*t, *r, *cc, j| {
      const k = m.ratio(j, 13);
      t.* = k;
      r.* = @max(0.011 * (1 - k * 0.9), 0.0007);
      cc.* = color.mix(green, straw, m.smooth(k));
    }
    try b.tubeC(&p, &ts, &rs, &cs, null, .stem, 4);
    if (i % 3 == 0) try mg.leavesAlong(b, &p, 3, 0.09, 0.025, 0.2, 0.7, 0.2, 0.7, pal.leaf_dark, pal.leaf_lite, 0xF1C0 +% i);
  }
}
