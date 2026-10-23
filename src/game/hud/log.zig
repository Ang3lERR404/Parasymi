//! recent messages (newest first, fading) and the control hint line.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const play = @import("../play.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("../style.zig");

const line_h:f32 = 22;
const start_y:f32 = 160;
const fade_dur:f32 = 8;
const max_age:f32 = 12;

const controls = "WASD MOVE  SHIFT RUN  Q/E TURN  CTRL+W/S TILT  CTRL+F FREE CAM  LMB GATHER/PLACE  R ROTATE  F HARVEST/FEED  SHIFT+F TAKE  C RECIPE  RMB UPROOT  1-9 HOTBAR  TAB BELLY  T RESEARCH";

pub fn draw(g:*play.Game, d:*Draw, _:f32, H:f32) Allocator.Error!void {
  for (g.prog.log, 0..) |msg, i| {
    if (msg.len == 0 or msg.age > max_age) continue;
    const a:u8 = @intFromFloat(255 * m.clamp01(1.5 - msg.age / fade_dur));
    _ = try d.text(24, H - start_y - m.f(i) * line_h, 1.75, .{220, 210, 255, a}, msg.buf[0..msg.len]);
  }
  _ = try d.text(24, H - 22, 1.2, s.dim, controls);
}