//! mesh: WOLF FOOT. origin at the ball of the foot (the end of the
//! metatarsal), sole flat on the ground, toes forward along +Z. Forms of
//! planes like the rest of the wolf: a long, squared foot with a raised
//! arch, tendons of vine running down its top to four knuckled toes that
//! splay a little and grip the ground with curved claws. The pads under it
//! are their own instances (`paw_pad`, `paw_bean`).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("wolf_kit.zig");

const V3 = m.V3;
const v3 = m.v3;

/// the sole's height below the origin, and where the central pad and the
/// four toe pads sit on it (x, z)
pub const SOLE_Y:f32 = -0.006;
pub const pad_at = v3(0, SOLE_Y + 0.002, 0.035);
pub const toes = [4][2]f32{.{-0.027, 0.098}, .{-0.009, 0.108}, .{0.009, 0.108}, .{0.027, 0.098}};

pub fn build(b:*mg.Builder) Allocator.Error!void {
  // the foot: long and flat, squared, rising into the arch behind
  try kit.form(b, .{.center = v3(0, 0.011, 0.034), .radii = v3(0.034, 0.017, 0.058), .ns = 0.6, .ew = 0.55, .col = pal.wolf_core});
  try kit.form(b, .{.center = v3(0, 0.02, -0.004), .radii = v3(0.026, 0.02, 0.03), .ns = 0.75, .ew = 0.65, .col = pal.wolf_core, .rings = 8, .segs = 10});
  for (toes) |t| {
    const dir = m.norm(v3(t[0] * 2.5, -0.1, 1));
    try kit.digit(b, .{
      .base = v3(t[0] * 0.9, 0.012, t[1] - 0.026), .dir = dir, .len = 0.034, .r = 0.0105,
      .col = pal.wolf_core, .claw = pal.wolf_claw,
    });
    // a tendon down the top of the foot to each toe
    var path:[6]V3 = undefined;
    var ts:[6]f32 = undefined;
    var rs:[6]f32 = undefined;
    for (&path, &ts, &rs, 0..) |*p, *tt, *r, i| {
      const k = m.ratio(i, 5);
      p.* = v3(t[0] * 0.9 * k, 0.03 - 0.008 * k, m.lerp(-0.01, t[1] - 0.026, k));
      tt.* = 0.3;
      r.* = 0.0035;
    }
    try b.tubeR(&path, &ts, &rs, pal.wolf_vine, .stem, 5);
  }
}
