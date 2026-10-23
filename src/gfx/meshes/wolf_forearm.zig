//! mesh: WOLF FOREARM. elbow at origin, wrist at +Y LEN (mesh -Z faces the
//! arm's front). A squared core tapering from 1.1x the arm radius to 0.7x,
//! the brachioradialis swelling forward near the elbow as a form of its
//! own, and vine tendons running down the back to the wrist.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("wolf_kit.zig");
const upper = @import("wolf_upper_arm.zig");

const v3 = m.v3;

pub const LEN:f32 = 0.24;
/// overall forearm scale relative to the upper arm (thinner)
const FOREARM_SCALE:f32 = 0.8;

fn radius(k:f32) f32 { return upper.ARM_R * FOREARM_SCALE * m.lerp(1.05, 0.68, k); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try kit.limbCore(b, LEN, radius, pal.wolf_core);
  try kit.muscle(b, v3(0, 0.32 * LEN, -0.018), v3(0.04, 0.075, 0.03), -0.12, pal.wolf_vine);
  for ([_]f32{-0.4, 0.4}) |x| {
    try kit.tendon(b, v3(x * radius(0.2), 0.2 * LEN, radius(0.2) * 0.9), v3(x * radius(1), LEN, radius(1) * 0.9), v3(0, 0, 0.004), 0.005, pal.wolf_vine);
  }
}
