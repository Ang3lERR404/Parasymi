//! recent messages (newest first, fading) and the control hint line.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const m = lib.engine.core.math;
const play = lib.play;
const Draw = lib.engine.ui.draw.Draw;
const s = lib.style;
const txt = lib.txt;

const line_h:f32 = 22;
const start_y:f32 = 160;
const fade_dur:f32 = 8;
const max_age:f32 = 12;

pub fn draw(g:*play.Game, d:*Draw, _:f32, H:f32) Allocator.Error!void {
  for (g.prog.log, 0..) |msg, i| {
    if (msg.len == 0 or msg.age > max_age) continue;
    const a = m.unorm8(1.5 - msg.age / fade_dur);
    _ = try d.text(24, H - start_y - m.f(i) * line_h, s.text_label, .{220, 210, 255, a}, msg.buf[0..msg.len]);
  }
  _ = try d.text(24, H - 22, s.text_small, s.dim, txt.s.hud.controls);
}