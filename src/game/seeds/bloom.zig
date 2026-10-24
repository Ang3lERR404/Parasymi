//! CELESTIAL BLOOM seed: a luminous core floating free of the seed on a
//! thread of light, its petals hanging apart from it and turning slowly,
//! each held by a thread (it radiates a field of celestial energy).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const items = @import("../../sim/items.zig");
const icon_kit = @import("../icon.zig");
const Color = @import("../../ui/draw.zig").Color;

pub const item:items.Item = .seed_bloom;

pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const bob = BOB * @sin(ic.t * BOB_RATE + ic.phase * 6);
  const core:icon_kit.P = .{0, 0.56 + bob};
  try ic.stem(.{.{0, icon_kit.TOP}, .{0.04, 0.22}, .{-0.04, 0.36}, .{0, core[1] - 0.08}}, 0.04, thread);
  const pulse = 0.85 + 0.15 * @sin(ic.t * 2.4 + ic.phase * 3);
  try ic.glow(core, 0.42 * pulse, field);
  const turn = ic.t * TURN + ic.phase;
  for (0..PETALS) |i| {
    const a = turn + m.tau * m.ratio(i, PETALS);
    const dir:icon_kit.P = .{@cos(a), @sin(a)};
    const at:icon_kit.P = .{core[0] + GAP * dir[0], core[1] + GAP * dir[1] * SQUASH};
    const from:icon_kit.P = .{core[0] + 0.06 * dir[0], core[1] + 0.06 * dir[1] * SQUASH};
    try ic.stem(.{from, from, at, at}, 0.025, thread);
    try ic.leaf(at, a, 0.18, 0.1, petal, 0.8);
  }
  // its crown of stamens
  try ic.stamens(core, m.half_pi, 0.7, 5, 0.15, thread);
  try ic.bud(core, 0.09, core_col, 1);
  try ic.coat(col);
}

const PETALS = 6;
/// petals float this far from the core, their ring tilted (squashed in y)
const GAP:f32 = 0.2;
const SQUASH:f32 = 0.75;
/// radians a second the petals turn
const TURN:f32 = 0.35;
const BOB:f32 = 0.04;
const BOB_RATE:f32 = 1.3;
const thread:Color = .{220, 255, 245, 150};
const petal:Color = .{235, 245, 255, 235};
const core_col:Color = .{240, 255, 250, 255};
const field:Color = .{140, 255, 215, 90};
