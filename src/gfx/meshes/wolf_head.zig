//! mesh: WOLF HEAD. neck joint at origin, snout along +Z
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");

const v3 = m.v3;
const core = pal.core;
const vine = pal.vine;
const leaf_dark = pal.leaf_dark;
const leaf_lite = pal.leaf_lite;
const sap = pal.sap;

fn snoutProfile(k:f32) f32 { return 0.055 * (1 - 0.45 * k); }

pub fn build(b:*mg.Builder) !void {
  var rng = pal.rngFor("wolf_head");
  try mg.ellipsoid(b, .{.center = v3(0, 0.08, 0.0), .radii = v3(0.1, 0.095, 0.11), .col = core, .t = 1});
  const s = b.mark();
  try mg.bundle(b, snoutProfile, 5, 1.6, core, vine);
  b.xform(s, m.chain(.{m.translate(v3(0, 0.06, 0.05)), m.rotX(m.pi / 2.0 - 0.15), m.scale3(v3(1, 0.17, 1))}));
  try mg.ellipsoid(b, .{.center = v3(0, 0.085, 0.225), .radii = v3(0.022, 0.018, 0.018), .col = color.rgb(.{0.08, 0.06, 0.05}, 255), .t = 1});
  for ([_]f32{-1, 1}) |side| {
    // glowing sap eyes
    try mg.ellipsoid(b, .{.center = v3(side * 0.055, 0.12, 0.085), .radii = v3(0.02, 0.016, 0.014), .col = sap, .part = .bloom, .rings = 5, .segs = 7, .t = 1});
    // ears: upright curled leaves
    try b.blade(v3(side * 0.06, 0.16, -0.01), m.norm(v3(side * 0.35, 0, -0.25)), 0.15, 0.055, -2.2, leaf_dark, leaf_lite, 1, .leaf);
  }
  // mane: leaves sweeping back off the skull
  for (0..6) |i| {
    const a = (m.f(i) - 2.5) * 0.35;
    try b.blade(v3(0, 0.15, -0.05), m.norm(v3(@sin(a) * 0.6, 0, -1)), 0.14 * rng.range(0.8, 1.2), 0.035, 0.6, leaf_dark, leaf_lite, 1, .leaf);
  }
}
