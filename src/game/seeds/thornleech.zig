//! THORNLEECH seed: a pale twisted stalk with a bulb and fronds curling
//! round it, a bead of red sap drawn into it from a green leaf beside it
//! (it drains its neighbours).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("engine").core.math;
const items = @import("../../sim/items.zig");
const icon_kit = @import("../icon.zig");
const Color = @import("engine").ui.draw.Color;

pub const item:items.Item = .seed_thornleech;

pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const bulb:icon_kit.P = .{0.02, 0.62};
  // the victim and what is drawn out of it
  const prey:icon_kit.P = .{-0.7, -0.2};
  try ic.stem(.{.{prey[0], prey[1] - 0.2}, .{prey[0], prey[1] - 0.1}, .{prey[0] - 0.02, prey[1]}, prey}, 0.06, prey_stem);
  const k = @mod(ic.t * RUN + ic.phase, 1);
  // the leaf droops as each bead leaves it
  try ic.leaf(prey, m.pi - 0.9 - 0.3 * @sin(k * m.pi), 0.22, 0.13, prey_leaf, 0.9);
  const path = [4]icon_kit.P{prey, .{-0.5, 0.25}, .{-0.2, 0.2}, .{0, 0.3}};
  try ic.bud(icon_kit.curve(path, k), 0.065, sap, @sin(k * m.pi));
  // three strands wound round each other
  for (0..3) |i| {
    const a = m.tau * m.ratio(i, 3);
    const w:f32 = 0.07;
    try ic.stem(.{.{0, icon_kit.TOP}, .{w * @cos(a), 0.25}, .{w * @cos(a + 2.4), 0.42}, bulb}, 0.07, stalk[i]);
  }
  // fronds curling down round the bulb
  for ([_]f32{-1, 1, -0.5}, 0..) |sx, i| {
    const tip:icon_kit.P = .{0.34 * sx, 0.48 + 0.08 * m.f(i)};
    try ic.stem(.{bulb, .{0.3 * sx, 0.92}, .{0.5 * sx, 0.7}, tip}, 0.06, frond);
  }
  try ic.bud(.{0.06, 0.24}, 0.05, bladder, 0.5);
  try ic.bud(.{-0.05, 0.4}, 0.045, bladder, 0.5);
  try ic.bud(bulb, 0.12, pearl, 0.7);
  try ic.coat(col);
}

/// beads drawn in a second
const RUN:f32 = 0.5;
const stalk = [3]Color{.{150, 145, 168, 255}, .{170, 165, 190, 255}, .{135, 130, 155, 255}};
const frond:Color = .{185, 185, 210, 255};
const bladder:Color = .{200, 200, 230, 255};
const pearl:Color = .{215, 205, 240, 255};
const sap:Color = .{240, 90, 120, 255};
const prey_stem:Color = .{90, 130, 80, 255};
const prey_leaf:Color = .{110, 170, 95, 255};
