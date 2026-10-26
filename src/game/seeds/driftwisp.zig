//! DRIFTWISP spore: the sprout has let go of its seed and floats above
//! it, a comb-jelly lantern of clear sap (its comb rows splitting the light
//! into colours, a golden spore inside) under a catcher dish, hair-thin
//! filaments waving beneath, a mote of starlight falling into the dish (it
//! drinks the sky into starlight).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("engine").core.math;
const items = @import("../../sim/items.zig");
const icon_kit = @import("../icon.zig");
const Color = @import("engine").ui.draw.Color;

pub const item:items.Item = .seed_driftwisp;

pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const bob = BOB * @sin(ic.t * BOB_RATE + ic.phase * 6);
  const float:icon_kit.P = .{0, 0.46 + bob};
  const top = float[1] + LANTERN_H;
  const mouth = float[1] - LANTERN_H;
  const dish:icon_kit.P = .{0, top + 0.03};
  // filaments out of the lantern's mouth, two lengths, waving
  for (0..FILAMENTS) |i| {
    const k = m.ratio(i, FILAMENTS - 1) - 0.5;
    const len:f32 = if (i % 2 == 0) 0.4 else 0.28;
    try ic.thread(.{k * LANTERN_W * 0.9, mouth + 0.02}, len, 1.6, 0.05, 0.03, m.f(i) * 1.9 + ic.phase * 4, filament);
  }
  // the catcher dish: a cup of petals opening upward
  for (0..PETALS) |i| {
    const a = m.half_pi + (m.ratio(i, PETALS - 1) - 0.5) * 2.2;
    try ic.leaf(dish, a, 0.3, 0.12, petal, 0.8);
  }
  try ic.stamens(dish, m.half_pi, 0.6, 4, 0.2, filament_lite);
  // the lantern: clear sap, the spore inside, comb rows over it in colours
  try ic.glow(float, 0.26, float_glow);
  try ic.bud(float, LANTERN_W, sap, 0.6);
  try ic.bud(.{0, float[1] - 0.01}, 0.05, spore, 1);
  for (0..ROWS) |i| {
    const k = m.ratio(i, ROWS - 1) * 2 - 1;
    const x = k * LANTERN_W * 0.95;
    try ic.stem(.{.{0, mouth}, .{x * 1.3, float[1] - LANTERN_H * 0.6}, .{x * 1.3, float[1] + LANTERN_H * 0.6}, .{0, top}}, 0.025, rows[i]);
  }
  // starlight falling into the dish
  const f = @mod(ic.t * FALL + ic.phase, 1);
  try ic.bud(.{0.04, m.lerp(0.98, dish[1] + 0.1, f)}, 0.045, star, @sin(f * m.pi));
  try ic.coat(col);
}

const FILAMENTS = 5;
const PETALS = 5;
/// the lantern's half width and half height (icon units), and its comb rows seen
const LANTERN_W:f32 = 0.15;
const LANTERN_H:f32 = 0.16;
const ROWS = 5;
/// how far it bobs (icon units) and how fast
const BOB:f32 = 0.05;
const BOB_RATE:f32 = 1.6;
/// motes falling a second
const FALL:f32 = 0.5;
const filament:Color = .{170, 185, 230, 210};
const petal:Color = .{200, 215, 255, 230};
const filament_lite:Color = .{230, 238, 255, 240};
const sap:Color = .{215, 230, 255, 120};
const spore:Color = .{255, 235, 160, 255};
const float_glow:Color = .{200, 225, 255, 80};
const star:Color = .{255, 245, 190, 255};
/// the comb rows, each splitting the light a different colour
const rows = [ROWS]Color{
  .{255, 190, 220, 230}, .{255, 235, 170, 230}, .{190, 255, 210, 230}, .{170, 220, 255, 230}, .{210, 185, 255, 230},
};
