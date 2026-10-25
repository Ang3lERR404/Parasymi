//! DRIFTBRAID seed: a tall twined stalk up to a spore sac, five fronds
//! flaring round its pore, each tipped with a small flower, spores rising
//! out of it and drifting away.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const items = @import("../../sim/items.zig");
const icon_kit = @import("../icon.zig");
const Color = @import("../../ui/draw.zig").Color;
const weft = @import("weftstone.zig");

pub const item:items.Item = .seed_driftbraid;

pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const sac:icon_kit.P = .{0, 0.62};
  try weft.twine(ic, sac, 0.06);
  for ([_]f32{-0.85, -0.45, 0, 0.45, 0.85}) |sx| {
    const tip:icon_kit.P = .{0.62 * sx, 0.5 + 0.3 * (1 - @abs(sx))};
    try ic.stem(.{.{0, 0.7}, .{0.25 * sx, 0.92}, .{0.5 * sx, 0.85}, tip}, 0.04, frond);
    try ic.bud(tip, 0.05, flower, 0.8);
  }
  // spores rising out of the pore and drifting off
  for (0..2) |i| {
    const k = @mod(ic.t * RUN + ic.phase + m.f(i) * 0.5, 1);
    const sx:f32 = if (i == 0) 1 else -1;
    try ic.bud(.{sac[0] + 0.3 * sx * k, sac[1] + 0.12 + 0.3 * k}, 0.035, spore, @sin(k * m.pi));
  }
  try ic.bud(sac, 0.14, sap, 0.6);
  try ic.coat(col);
}

/// spores out a second
const RUN:f32 = 0.35;
const frond:Color = .{175, 160, 210, 255};
const flower:Color = .{235, 170, 120, 255};
const sap:Color = .{140, 150, 240, 255};
const spore:Color = .{225, 220, 250, 255};
