//! mesh: WOLF TAIL. a braided vine with rings of fur leaves lying back
//! along it toward the tip, built straight up +Y and stored with its length
//! as 0..1 (x and z stay in metres). The part shader carries every point to
//! the same fraction along the tail's curve (the rig's spring-steered
//! joints, passed per instance), laying its x and z across the curve, so
//! the tail bends on the GPU instead of being rebuilt every frame.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("wolf_kit.zig");

const V3 = m.V3;
const v3 = m.v3;

/// the tail's length at rest (its joints' total), which the 0..1 is of
pub const LEN:f32 = 0.48;
const RES = 20;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const s = b.mark();
  var spine:[RES]V3 = undefined;
  var ts:[RES]f32 = undefined;
  var radii:[RES]f32 = undefined;
  for (&spine, &ts, 0..) |*p, *t, i| {
    t.* = m.ratio(i, RES - 1);
    p.* = v3(0, t.* * LEN, 0);
  }
  mg.taperRadii(0.06, 0.2, &radii);
  try mg.braid(b, &spine, &ts, &radii, 3, 4.0, pal.STRAND_WOBBLE, 0x7A11, pal.wolf_core, pal.wolf_vine);
  // fur: rings of leaves all the way around, longer toward the tip, each
  // ring turned from the last
  for (0..6) |ring| {
    const k = 0.3 + 0.1 * m.f(ring);
    const i = m.floorTo(usize, k * (RES - 1));
    for (0..3) |j| {
      const a = m.f(j) / 3 * m.tau + m.f(ring) * 1.05;
      const radial = v3(@cos(a), 0, @sin(a));
      try kit.leaf(b, .{
        .base = spine[i] + radial * m.splat3(radii[i] * 0.85), .along = v3(0, 1, 0), .out = radial,
        .len = 0.055 + 0.03 * k, .width = 0.02, .lift = 0.45, .curl = 0.4, .cup = 0.3,
        .col = pal.wolf_leaf_dark, .tip = pal.wolf_leaf_lite,
      });
    }
  }
  b.xform(s, m.scale3(v3(1, 1 / LEN, 1)));
}
