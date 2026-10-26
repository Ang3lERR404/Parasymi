//! gathering progress grows a tendril above the wolf's focus.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const play = lib.play;
const actions = lib.actions;
const Draw = lib.engine.ui.draw.Draw;
const s = lib.style;
const m = lib.engine.core.math;

const tendril_w:f32 = 120;
const tendril_h = s.bar_h_bold;
const above_head:f32 = 120;

pub fn visible(g:*const play.Game) bool { return g.gather_t > 0 and g.hover != null; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  const t = m.clamp01(g.gather_t / actions.GATHER_TIME);
  try d.tendril(W / 2 - tendril_w / 2, H / 2 - above_head, tendril_w, tendril_h, s.gold, t, 0.9);
}   