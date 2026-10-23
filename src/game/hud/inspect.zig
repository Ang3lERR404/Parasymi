//! the free camera's reminder: a small glowing tendril by the top-left with
//! how to get back.
const std = @import("std");
const Allocator = std.mem.Allocator;
const play = @import("../play.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("style.zig");

pub fn visible(g:*const play.Game) bool { return g.mode == .inspect; }

pub fn draw(_:*play.Game, d:*Draw, _:f32, _:f32) Allocator.Error!void {
  const x:f32 = 344;
  const y:f32 = 46;
  try d.glow(x + 8, y + 8, 22, .{150, 230, 190, 90});
  try d.tendril(x, y, 300, 14, .{150, 230, 190, 255}, 1, 0.7);
  _ = try d.text(x + 14, y + 24, 1.4, s.white, "FREE CAM  CTRL+F TO EXIT");
  _ = try d.text(x + 14, y + 44, 1.1, s.dim, "CLICK TO LOOK  WASD FLY  Q/E ROLL  WHEEL DOLLY");
}
