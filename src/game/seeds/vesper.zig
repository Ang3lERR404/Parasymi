//! VESPER seed: a dusky violet sprout, thorned and leaved (both lineages),
//! opening a pale flower under the evening star that feeds it (it needs
//! radiance).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const items = @import("../../sim/items.zig");
const icon_kit = @import("../icon.zig");
const Color = @import("../../ui/draw.zig").Color;

pub const item:items.Item = .seed_vesper;

pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const top:icon_kit.P = .{-0.06, 0.6};
  const star:icon_kit.P = .{0.42, 0.86};
  try ic.stem(.{.{0, icon_kit.TOP}, .{0.1, 0.28}, .{-0.12, 0.42}, top}, 0.1, stem);
  try ic.leaf(.{0.03, 0.26}, 0.45, 0.3, 0.15, leaf, 0.9);
  try ic.bud(.{-0.05, 0.42}, 0.035, thorn, 0.3);
  try ic.bud(.{0.06, 0.18}, 0.035, thorn, 0.3);
  // starlight falling from the star to the flower
  const k = @mod(ic.t * FALL + ic.phase, 1);
  try ic.bud(.{m.lerp(star[0], top[0], k), m.lerp(star[1], top[1], k)}, 0.04, ray, @sin(k * m.pi));
  try ic.glow(top, 0.28, bloom_glow);
  for (0..PETALS) |i| {
    try ic.leaf(top, m.pi / 2.0 + m.tau * m.ratio(i, PETALS), 0.2, 0.1, petal, 1);
  }
  try ic.stamens(top, m.pi / 2.0, 0.75, 5, 0.16, filament);
  try ic.bud(top, 0.05, core, 1);
  const twinkle = 0.75 + 0.25 * @sin(ic.t * 3 + ic.phase * 4);
  try ic.glow(star, 0.22 * twinkle, star_glow);
  try ic.gem(star, 0.09 * twinkle, star_col);
  try ic.coat(col);
}

const PETALS = 9;
/// motes from the star a second
const FALL:f32 = 0.6;
const stem:Color = .{75, 60, 125, 255};
const leaf:Color = .{115, 105, 220, 255};
const thorn:Color = .{150, 140, 175, 255};
const petal:Color = .{240, 195, 255, 255};
const core:Color = .{255, 240, 255, 255};
const filament:Color = .{250, 230, 255, 255};
const bloom_glow:Color = .{230, 190, 255, 80};
const ray:Color = .{255, 245, 200, 255};
const star_col:Color = .{255, 245, 210, 255};
const star_glow:Color = .{255, 240, 200, 110};
