//! the pause menu (Esc): the world holds its breath behind a soft veil.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const play = @import("../play.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("style.zig");

const options = [_][2][]const u8{
  .{"ESC", "RESUME"},
  .{"F5", "SAVE THE GARDEN"},
  .{"F9", "RETURN TO THE LAST SAVE"},
  .{"F11", "FULLSCREEN"},
  .{"Q", "SAVE AND LEAVE"},
};

pub fn visible(g:*const play.Game) bool { return g.mode == .paused; }

pub fn draw(_:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  // a radial veil dims the world without drawing any edge
  try d.glow(W / 2, H / 2, @max(W, H) * 0.75, .{4, 6, 10, 200});
  const pw:f32 = 480;
  const ph:f32 = 130 + 44 * m.f(options.len);
  const px = (W - pw) / 2;
  const py = (H - ph) / 2;
  try d.membrane(px, py, pw, ph, .{24, 30, 40, 235}, 0.55);
  _ = try d.text(W / 2 - Draw.width("PAUSED", 3.5) / 2, py + 30, 3.5, s.gold, "PAUSED");
  for (options, 0..) |o, i| {
    const y = py + 100 + 44 * m.f(i);
    try d.pod(px + 90, y + 8, 9, s.gold, 0.5, m.f(i) * 0.4);
    _ = try d.text(px + 112, y, 1.75, s.dim, o[0]);
    _ = try d.text(px + 190, y, 1.75, s.white, o[1]);
  }
}
