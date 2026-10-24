//! DRIFTWISP spore: the sprout has let go of its seed and floats above
//! it, a sap float under a catcher dish, filaments trailing, a mote of
//! starlight falling into the dish (it drinks the sky into starlight).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const items = @import("../../sim/items.zig");
const icon_kit = @import("../icon.zig");
const Color = @import("../../ui/draw.zig").Color;

pub const item:items.Item = .seed_driftwisp;

pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const bob = BOB * @sin(ic.t * BOB_RATE + ic.phase * 6);
  const float:icon_kit.P = .{0, 0.48 + bob};
  const dish:icon_kit.P = .{0, 0.58 + bob};
  // filaments trailing beneath, drifting
  for (0..FILAMENTS) |i| {
    const x = (m.ratio(i, FILAMENTS - 1) - 0.5) * 0.24;
    const drift = 0.06 * @sin(ic.t * 1.7 + m.f(i) * 1.9 + ic.phase * 4);
    try ic.stem(.{.{x, float[1] - 0.06}, .{x * 1.3, float[1] - 0.18}, .{x * 1.6 + drift, float[1] - 0.28}, .{x * 1.8 + 2 * drift, float[1] - 0.38}}, 0.04, filament);
  }
  // the catcher dish: a cup of petals opening upward
  for (0..PETALS) |i| {
    const a = m.pi / 2.0 + (m.ratio(i, PETALS - 1) - 0.5) * 2.2;
    try ic.leaf(dish, a, 0.3, 0.12, petal, 0.8);
  }
  try ic.stamens(dish, m.pi / 2.0, 0.6, 4, 0.2, filament_lite);
  try ic.glow(float, 0.24, float_glow);
  try ic.bud(float, 0.12, sap, 0.8);
  // starlight falling into the dish
  const k = @mod(ic.t * FALL + ic.phase, 1);
  try ic.bud(.{0.04, m.lerp(0.98, dish[1] + 0.1, k)}, 0.045, star, @sin(k * m.pi));
  try ic.coat(col);
}

const FILAMENTS = 4;
const PETALS = 5;
/// how far it bobs (icon units) and how fast
const BOB:f32 = 0.05;
const BOB_RATE:f32 = 1.6;
/// motes falling a second
const FALL:f32 = 0.5;
const filament:Color = .{150, 170, 220, 200};
const petal:Color = .{200, 215, 255, 230};
const filament_lite:Color = .{230, 238, 255, 240};
const sap:Color = .{215, 230, 255, 200};
const float_glow:Color = .{190, 210, 255, 70};
const star:Color = .{255, 245, 190, 255};
