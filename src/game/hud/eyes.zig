//! looking out of the wolf's eyes: a small lit seed at the middle of the
//! screen, in a soft glow, marking what a click lands on.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const play = lib.play;
const Draw = lib.engine.ui.draw.Draw;
const s = lib.style;

const seed_r:f32 = 4;
const glow_r:f32 = 14;

pub fn visible(g:*const play.Game) bool { return g.looking; }

pub fn draw(_:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  try d.glow(W / 2, H / 2, glow_r, s.aim_glow);
  try d.pod(W / 2, H / 2, seed_r, s.aim, 1, 0.3);
}
