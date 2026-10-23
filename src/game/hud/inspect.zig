//! the free camera's reminder: a small glowing tendril by the top-left with
//! how to get back.
const std = @import("std");
const Allocator = std.mem.Allocator;
const play = @import("../play.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("../style.zig");

const ox:f32 = 344;
const oy:f32 = 46;
const tendril_w:f32 = 300;
const tendril_h:f32 = 14;
const glow_r:f32 = 22;

pub fn visible(g:*const play.Game) bool { return g.mode == .inspect; }

pub fn draw(_:*play.Game, d:*Draw, _:f32, _:f32) Allocator.Error!void {
  try d.glow(ox + 8, oy + 8, glow_r, s.freecam_glow);
  try d.tendril(ox, oy, tendril_w, tendril_h, s.freecam, 1, 0.7);
  _ = try d.text(ox + 14, oy + 24, 1.4, s.white, "FREE CAM  CTRL+F TO EXIT");
  _ = try d.text(ox + 14, oy + 44, 1.1, s.dim, "CLICK TO LOOK  WASD FLY  Q/E ROLL  WHEEL DOLLY");
}