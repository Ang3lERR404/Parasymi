//! VESPER seed: an evening star come down over the seed, held up on a
//! thread of light: a gold core in a star of five dusk-violet rays, two
//! dusky leaves floating free beneath it, and starlight falling to it from
//! the star that feeds it (it needs radiance).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("engine").core.math;
const items = @import("../../sim/items.zig");
const icon_kit = @import("../icon.zig");
const Color = @import("engine").ui.draw.Color;

pub const item:items.Item = .seed_vesper;

pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const bob = BOB * @sin(ic.t * BOB_RATE + ic.phase * 6);
  const core:icon_kit.P = .{-0.04, 0.58 + bob};
  const star:icon_kit.P = .{0.42, 0.88};
  try ic.stem(.{.{0, icon_kit.TOP}, .{0.03, 0.24}, .{-0.06, 0.38}, .{core[0], core[1] - 0.1}}, 0.035, thread);
  // its leaves, floating apart under it
  for (LEAVES, 0..) |a, i| {
    const at:icon_kit.P = .{core[0] + 0.1 * @cos(a), core[1] - 0.15 + 0.02 * m.f(i)};
    try ic.leaf(at, a - 0.35, 0.2, 0.08, leaf, 0.9);
  }
  // starlight falling from the star to the flower
  const k = @mod(ic.t * FALL + ic.phase, 1);
  try ic.bud(.{m.lerp(star[0], core[0], k), m.lerp(star[1], core[1], k)}, 0.04, ray, @sin(k * m.pi));
  try ic.glow(core, 0.3, bloom_glow);
  // the star of rays, turning slowly round the core, a gap off it
  const turn = ic.t * TURN + ic.phase;
  for (0..RAYS) |i| {
    const a = turn + m.half_pi + m.tau * m.ratio(i, RAYS);
    try ic.leaf(.{core[0] + GAP * @cos(a), core[1] + GAP * @sin(a)}, a, 0.22, 0.06, petal, 1);
  }
  try ic.stamens(core, m.half_pi, 0.7, 5, 0.12, filament);
  try ic.bud(core, 0.06, core_col, 1);
  const twinkle = 0.75 + 0.25 * @sin(ic.t * 3 + ic.phase * 4);
  try ic.glow(star, 0.22 * twinkle, star_glow);
  try ic.gem(star, 0.09 * twinkle, star_col);
  try ic.coat(col);
}

const RAYS = 5;
/// the leaves' bearings (radians: one each way, below the core)
const LEAVES = [_]f32{ -2.6, -0.55 };
/// the rays float this far from the core, turning this fast (radians/s)
const GAP:f32 = 0.05;
const TURN:f32 = 0.25;
const BOB:f32 = 0.03;
const BOB_RATE:f32 = 1.1;
/// motes from the star a second
const FALL:f32 = 0.6;
const thread:Color = .{255, 225, 170, 140};
const leaf:Color = .{95, 125, 160, 255};
const petal:Color = .{150, 115, 225, 255};
const core_col:Color = .{255, 235, 190, 255};
const filament:Color = .{255, 235, 200, 255};
const bloom_glow:Color = .{255, 215, 160, 80};
const ray:Color = .{255, 245, 200, 255};
const star_col:Color = .{255, 245, 210, 255};
const star_glow:Color = .{255, 240, 200, 110};
