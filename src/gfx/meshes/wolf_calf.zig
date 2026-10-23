//! mesh: WOLF CALF. knee at origin, hock (the backward-bending joint) at +Y
//! LEN: tendon and sinew. A squared core tapering from 1x the leg radius to
//! 0.7x, the gastrocnemius a form of its own swelling on its back (+Z here,
//! which faces backward once the rig turns the segment downward) at 30%,
//! running into an Achilles tendon of vine down to the hock, and one wrap.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("wolf_kit.zig");
const thigh = @import("wolf_thigh.zig");

const v3 = m.v3;

pub const LEN:f32 = 0.26;
const N = 16;

fn radius(k:f32) f32 { return thigh.LEG_R * m.lerp(0.9, 0.62, k); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try kit.limbCore(b, LEN, radius, pal.wolf_vine);
  try kit.muscle(b, v3(0, 0.3 * LEN, 0.03), v3(0.055, 0.085, 0.045), 0.1, pal.wolf_vine);
  try kit.tendon(b, v3(0, 0.5 * LEN, radius(0.5) * 0.95), v3(0, LEN, radius(1) * 0.95), v3(0, 0, 0.006), 0.008, pal.wolf_core);
  var radii:[N]f32 = undefined;
  for (&radii, 0..) |*r, i| r.* = radius(m.ratio(i, N - 1)) * 1.05;
  try thigh.wraps(b, &radii, LEN, 1, 1.2, 0xCA1F);
}
