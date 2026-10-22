//! mesh: WOLF HEAD. neck joint at origin, snout along +Z
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");

const V3 = m.V3;
const v3 = m.v3;
const core = pal.wolf_core;
const vine = pal.wolf_vine;
const leaf_dark = pal.wolf_leaf_dark;
const leaf_lite = pal.wolf_leaf_lite;
const sap = pal.sap;

fn snoutProfile(k:f32) f32 { return 0.055 * (1 - 0.45 * k); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var rng = pal.rngFor("wolf_head");
  try mg.ellipsoid(b, .{.center = v3(0, 0.08, 0.0), .radii = v3(0.1, 0.095, 0.11), .col = core, .t = 1});
  const s = b.mark();
  try mg.bundle(b, snoutProfile, 5, 1.6, pal.STRAND_WOBBLE, 0x5A0, core, vine);
  b.xform(s, m.chain(.{m.translate(v3(0, 0.06, 0.05)), m.rotX(m.pi / 2.0 - 0.15), m.scale3(v3(1, 0.17, 1))}));
  try mg.ellipsoid(b, .{.center = v3(0, 0.085, 0.225), .radii = v3(0.022, 0.018, 0.018), .col = color.rgb(.{0.08, 0.06, 0.05}, 255), .t = 1});
  for ([_]f32{-1, 1}) |side| {
    // glowing sap eyes
    try mg.ellipsoid(b, .{.center = v3(side * 0.055, 0.12, 0.085), .radii = v3(0.02, 0.016, 0.014), .col = sap, .part = .bloom, .rings = 5, .segs = 7, .t = 1});
    // ears: upright leaves, sap-lined inside, grown so each curls a little
    const out = m.norm(v3(side * 0.35, 0, -0.25));
    var ear:[mg.BLADE_SEGS + 1]V3 = undefined;
    mg.bladeSpine(&ear, v3(side * 0.06, 0.16, -0.01), out, 0.15, -2.2);
    const reach = ear[mg.BLADE_SEGS] - ear[0];
    mg.grow(&ear, .{
      .start = ear[0], .direction = m.norm(reach), .length = m.len(reach),
      .curl = 0.3, .wobble = 0.1, .taper = 0.1, .seed = if (side > 0) 0xEA5 else 0xEA6,
    });
    try b.bladeAlong(&ear, m.norm(m.cross(out, v3(0, 1, 0))), 0.055, leaf_dark, leaf_lite, 1, .ear);
  }
  // mane: living tendrils sweeping back off the skull
  for (0..6) |i| {
    const a = (m.f(i) - 2.5) * 0.35;
    try mg.vine(b, .{
      .start = v3(0, 0.15, -0.05), .direction = m.norm(v3(@sin(a) * 0.6, 0.3, -1)), .length = 0.14 * rng.range(0.8, 1.2),
      .curl = 0.3, .wobble = 0.1, .taper = 0.1, .seed = 0x3A9E +% i,
    }, 5, 12, 0.014, leaf_dark, .tendril, 4, 0.8, 1);
  }
}
