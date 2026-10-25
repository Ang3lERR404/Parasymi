//! WEFTSTONE seed: a green strand and a pale one twining up into a crop of
//! violet sap with a grit crystal in it, fern fronds arching out either
//! side (green leaflets on lilac stems), grains of grit dropping out of it.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const items = @import("../../sim/items.zig");
const icon_kit = @import("../icon.zig");
const Color = @import("../../ui/draw.zig").Color;

pub const item:items.Item = .seed_weftstone;

pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const crop:icon_kit.P = .{0, 0.5};
  try twine(ic, crop, 0.06);
  // a frond each way: a lilac stem arching out, green leaflets in pairs
  for ([_]f32{-1, 1}) |sx| {
    const path = [4]icon_kit.P{.{0.02 * sx, 0.36}, .{0.35 * sx, 0.7}, .{0.65 * sx, 0.6}, .{0.78 * sx, 0.32}};
    try ic.stem(path, 0.045, frond);
    for (0..4) |j| {
      const k = 0.3 + 0.17 * m.f(j);
      const at = icon_kit.curve(path, k);
      const out:f32 = if (sx > 0) 0 else m.pi;
      try ic.leaf(at, out + sx * (0.9 - 0.25 * m.f(j)), 0.14 - 0.02 * m.f(j), 0.06, icon_kit.sprout, 0.9);
      try ic.leaf(at, out - sx * (0.6 + 0.2 * m.f(j)), 0.12 - 0.02 * m.f(j), 0.05, icon_kit.sprout, 0.9);
    }
  }
  // grit dropping out of the crop, one grain after another
  const k = @mod(ic.t * RUN + ic.phase, 1);
  try ic.bud(.{0.04, crop[1] - 0.12 - 0.5 * k}, 0.04, grit, 1 - k);
  try ic.bud(crop, 0.17, sap, 0.6);
  try ic.gem(crop, 0.08, grit);
  try ic.coat(col);
}

/// a green strand and a pale one wound round each other up to `top`
pub fn twine(ic:icon_kit.Icon, top:icon_kit.P, w:f32) Allocator.Error!void {
  for ([_]f32{1, -1}, [_]Color{green, pale}) |way, c| {
    try ic.stem(.{.{0, icon_kit.TOP}, .{0.09 * way, 0.2}, .{-0.09 * way, top[1] - 0.18}, top}, w, c);
  }
}

/// grains a second
const RUN:f32 = 0.6;
pub const green:Color = .{80, 150, 95, 255};
pub const pale:Color = .{185, 180, 205, 255};
const frond:Color = .{175, 160, 210, 255};
const sap:Color = .{170, 120, 235, 255};
const grit:Color = .{175, 165, 150, 255};
