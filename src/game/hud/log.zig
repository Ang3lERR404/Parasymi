//! recent messages (newest first, fading) and the control hint line.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const play = @import("../play.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("style.zig");

const controls = "WASD MOVE  SHIFT RUN  Q/E TURN  LMB GATHER/PLACE  R ROTATE  F HARVEST/FEED  SHIFT+F TAKE  C RECIPE  RMB UPROOT  1-9 HOTBAR  TAB BELLY  T RESEARCH";

pub fn draw(g:*play.Game, d:*Draw, _:f32, H:f32) Allocator.Error!void {
  for (g.prog.log, 0..) |msg, i| {
    if (msg.len == 0 or msg.age > 12) continue;
    const a:u8 = @intFromFloat(255 * m.clamp01(1.5 - msg.age / 8));
    _ = try d.text(24, H - 160 - m.f(i) * 22, 1.75, .{220, 210, 255, a}, msg.buf[0..msg.len]);
  }
  _ = try d.text(24, H - 22, 1.2, s.dim, controls);
}
