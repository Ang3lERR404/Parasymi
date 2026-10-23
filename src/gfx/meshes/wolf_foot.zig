//! mesh: WOLF FOOT. origin at the ball of the foot (the end of the
//! metatarsal), sole flat on the ground, toes forward along +Z: a long, flat
//! foot with four slightly splayed toes and small claws at their very tips.
//! The pads under it are their own instances (`paw_pad`, `paw_bean`).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

const V3 = m.V3;
const v3 = m.v3;

/// the sole's height below the origin, and where the central pad and the
/// four toe pads sit on it (x, z)
pub const SOLE_Y:f32 = -0.006;
pub const pad_at = v3(0, SOLE_Y + 0.002, 0.035);
pub const toes = [4][2]f32{.{-0.027, 0.098}, .{-0.009, 0.108}, .{0.009, 0.108}, .{0.027, 0.098}};

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try mg.ellipsoid(b, .{.center = v3(0, 0.012, 0.035), .radii = v3(0.035, 0.018, 0.072), .col = pal.wolf_core, .rings = 7, .segs = 10});
  for (toes) |t| {
    const splay = m.norm(v3(t[0] * 2.5, 0, 1));
    const c = v3(t[0], 0.008, t[1]);
    try mg.ellipsoid(b, .{.center = c, .radii = v3(0.011, 0.0105, 0.018), .col = pal.wolf_core, .rings = 5, .segs = 8});
    try b.cone(c + splay * m.splat(0.015) + v3(0, 0.002, 0), m.norm(splay + v3(0, -0.5, 0)), 0.012, 0.004, pal.wolf_claw, 0, .thorn);
  }
}
