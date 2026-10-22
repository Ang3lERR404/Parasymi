//! mesh: WOLF TORSO. hips at origin, chest top at y=0.5, forward is +Z
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

const v3 = m.v3;
const core = pal.core;
const vine = pal.vine;
const leaf_dark = pal.leaf_dark;
const leaf_lite = pal.leaf_lite;

fn torsoProfile(k:f32) f32 {
  // narrow waist at the hips, broad ribcage, tapering into the neck
  return 0.085 + 0.05 * @sin(k * m.pi * 0.85) + 0.02 * k;
}

pub fn build(b:*mg.Builder) !void {
  const s = b.mark();
  try mg.bundle(b, torsoProfile, 7, 2.4, core, vine);
  b.xform(s, m.scale3(v3(1.25, 0.5, 0.95)));
  // pectorals: broad leaf-plated muscles over the ribcage
  for ([_]f32{-1, 1}) |side| {
    try mg.ellipsoid(b, .{.center = v3(side * 0.065, 0.36, 0.075), .radii = v3(0.07, 0.055, 0.04), .col = leaf_dark, .t = 0.7});
    try mg.ellipsoid(b, .{.center = v3(side * 0.07, 0.365, 0.09), .radii = v3(0.055, 0.04, 0.025), .col = leaf_lite, .part = .leaf, .t = 0.7});
  }
  // collarbone vine across the shoulders
  try b.tube(&.{v3(-0.17, 0.46, 0.0), v3(0, 0.44, 0.06), v3(0.17, 0.46, 0.0)}, &.{0.9, 0.9, 0.9}, 0.022, 0.022, vine, .stem, 5);
}
