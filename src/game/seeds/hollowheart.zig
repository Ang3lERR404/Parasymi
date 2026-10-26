//! HOLLOWHEART seed: a stout trunk carrying a broad crown, an amber heart
//! glowing in its hollow and pulsing (a deep reservoir that feeds around it).
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const m = lib.engine.core.math;
const items = lib.items;
const icon_kit = lib.icon;
const Color = lib.engine.ui.draw.Color;

pub const item:items.Item = .seed_hollowheart;

pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const crown:icon_kit.P = .{0, 0.62};
  const heart:icon_kit.P = .{0, 0.36};
  try ic.stem(.{.{0, icon_kit.TOP}, .{-0.04, 0.25}, .{0.04, 0.45}, crown}, 0.22, trunk);
  for (0..LEAVES) |i| {
    const a = 0.25 + (m.pi - 0.5) * m.ratio(i, LEAVES - 1);
    try ic.leaf(crown, a, 0.38, 0.2, if (i % 2 == 0) leaf else leaf_young, 0.9);
  }
  const beat = 0.5 + 0.5 * @sin(ic.t * BEAT + ic.phase * 6);
  try ic.glow(heart, 0.2 + 0.08 * beat, heart_glow);
  try ic.bud(heart, 0.07, amber, beat);
  try ic.coat(col);
}

const LEAVES = 6;
/// heartbeats (radians a second)
const BEAT:f32 = 2.2;
const trunk:Color = .{105, 80, 58, 255};
const leaf:Color = .{70, 160, 100, 255};
const leaf_young:Color = .{100, 190, 115, 255};
const amber:Color = .{255, 200, 120, 255};
const heart_glow:Color = .{255, 200, 120, 100};
