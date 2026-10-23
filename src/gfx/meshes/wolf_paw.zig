//! mesh: WOLF PAW (hand). origin at the wrist, fingers forward along +Z,
//! palm down (-Y). Forms of planes like the rest of the wolf: a squared
//! back of the hand with tendons of vine running over it to four knuckled
//! fingers that arch down to curved claws, and a dewclaw high on the inner
//! side. The pads under it are their own instances (`paw_pad`, `paw_bean`).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("wolf_kit.zig");

const V3 = m.V3;
const v3 = m.v3;

/// where the palm pad and the four finger pads sit under the hand
pub const PALM_Y:f32 = -0.012;
pub const palm_at = v3(0, PALM_Y, 0.032);
pub const fingers = [4][2]f32{.{-0.027, 0.083}, .{-0.009, 0.091}, .{0.009, 0.091}, .{0.027, 0.083}};

pub fn build(b:*mg.Builder) Allocator.Error!void {
  // the back of the hand
  try kit.form(b, .{.center = v3(0, 0.006, 0.03), .radii = v3(0.04, 0.02, 0.042), .ns = 0.65, .ew = 0.6, .col = pal.wolf_core});
  // fingers, slightly splayed, arching down to the ground
  for (fingers) |f| {
    const dir = m.norm(v3(f[0] * 1.8, -0.15, 1));
    try kit.digit(b, .{
      .base = v3(f[0] * 0.85, 0.004, 0.058), .dir = dir, .len = 0.04, .r = 0.0105,
      .col = pal.wolf_core, .claw = pal.wolf_claw,
    });
  }
  // tendons over the back of the hand to the knuckles
  for (fingers) |f| {
    var path:[6]V3 = undefined;
    var ts:[6]f32 = undefined;
    var rs:[6]f32 = undefined;
    for (&path, &ts, &rs, 0..) |*p, *t, *r, i| {
      const k = m.ratio(i, 5);
      p.* = v3(f[0] * 0.85 * k, 0.025 - 0.01 * k * k, m.lerp(0.0, 0.058, k));
      t.* = 0.3;
      r.* = 0.0035;
    }
    try b.tubeR(&path, &ts, &rs, pal.wolf_vine, .stem, 5);
  }
  // the dewclaw, high on the inner side
  try kit.digit(b, .{
    .base = v3(-0.038, 0.002, 0.012), .dir = m.norm(v3(-0.5, -0.5, 0.7)), .len = 0.018, .r = 0.007,
    .col = pal.wolf_core, .claw = pal.wolf_claw,
  });
}
