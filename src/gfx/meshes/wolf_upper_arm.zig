//! mesh: WOLF UPPER ARM. shoulder at origin, elbow at +Y LEN (the rig turns
//! it downward, so mesh -Z faces the arm's front). Forms of planes: a
//! squared core with two separate muscles over it, a bicep peaking at 30%
//! on the front and a tricep peaking at 70% on the back, a groove between
//! them where a vine tendon runs.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("wolf_kit.zig");

const v3 = m.v3;

pub const LEN:f32 = 0.25;
/// the arm's reference radius (the deltoid is 1.4x this)
pub const ARM_R:f32 = 0.06;

fn radius(k:f32) f32 { return ARM_R * m.lerp(0.82, 0.72, k); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try kit.limbCore(b, LEN, radius, pal.wolf_core);
  try kit.muscle(b, v3(0, 0.3 * LEN, -0.02), v3(0.05, 0.072, 0.042), -0.08, pal.wolf_vine);
  try kit.muscle(b, v3(0, 0.68 * LEN, 0.022), v3(0.048, 0.078, 0.042), 0.08, pal.wolf_vine);
  for ([_]f32{-1, 1}) |side| {
    try kit.tendon(b, v3(side * radius(0.1) * 0.95, 0.1 * LEN, 0), v3(side * radius(0.95) * 0.95, 0.95 * LEN, 0), v3(side * 0.006, 0, 0), 0.006, pal.wolf_vine);
  }
}
