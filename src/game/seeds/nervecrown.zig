//! NERVECROWN seed: a twined stalk on two broad leaves, a knot of five
//! pearl nodules round a violet sac at its top, motes running out along
//! pale nerves to the sprouts beside it (it shares far).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const items = @import("../../sim/items.zig");
const icon_kit = @import("../icon.zig");
const Color = @import("../../ui/draw.zig").Color;
const weft = @import("weftstone.zig");

pub const item:items.Item = .seed_nervecrown;

pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const knot:icon_kit.P = .{0, 0.6};
  try ic.leaf(.{0, 0.14}, 0.35, 0.42, 0.2, icon_kit.sprout, 0.9);
  try ic.leaf(.{0, 0.14}, m.pi - 0.35, 0.42, 0.2, icon_kit.sprout, 0.9);
  try weft.twine(ic, knot, 0.07);
  // the kin it feeds, and the nerves and motes running out to them
  for ([_]f32{-1, 1}, 0..) |sx, i| {
    const kin:icon_kit.P = .{0.75 * sx, -0.3};
    try ic.stem(.{.{kin[0], kin[1] - 0.18}, .{kin[0], kin[1] - 0.08}, .{kin[0] + 0.02 * sx, kin[1]}, kin}, 0.06, weft.green);
    try ic.leaf(kin, if (sx < 0) m.pi - 0.7 else 0.7, 0.17, 0.1, icon_kit.sprout, 0.9);
    const run = [4]icon_kit.P{knot, .{0.4 * sx, 0.75}, .{0.75 * sx, 0.2}, kin};
    try ic.stem(run, 0.025, nerve);
    const k = @mod(ic.t * RUN + ic.phase + m.f(i) * 0.5, 1);
    try ic.bud(icon_kit.curve(run, k), 0.05, mote, @sin(k * m.pi));
  }
  try ic.bud(knot, 0.13, sap, 0.7);
  for (0..5) |i| {
    const a = m.half_pi + m.ratio(i, 5) * m.tau;
    try ic.bud(.{knot[0] + 0.15 * @cos(a), knot[1] + 0.13 * @sin(a)}, 0.05, pearl, 0.8);
  }
  try ic.stamens(.{knot[0], knot[1] + 0.12}, m.half_pi, 0.6, 3, 0.14, pearl);
  try ic.coat(col);
}

/// motes out to the neighbours a second
const RUN:f32 = 0.45;
const nerve:Color = .{200, 195, 220, 255};
const pearl:Color = .{220, 212, 238, 255};
const sap:Color = .{235, 160, 120, 255};
const mote:Color = .{245, 200, 150, 255};
