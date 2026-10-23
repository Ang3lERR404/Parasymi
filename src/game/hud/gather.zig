//! gathering progress grows a tendril above the wolf's focus.
const std = @import("std");
const Allocator = std.mem.Allocator;
const play = @import("../play.zig");
const actions = @import("../actions.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("../style.zig");
const m = @import("../../core/math.zig");

const tendril_w:f32 = 120;
const tendril_h:f32 = 14;
const above_head:f32 = 120;

pub fn visible(g:*const play.Game) bool { return g.gather_t > 0 and g.hover != null; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  const t = m.clamp01(g.gather_t / actions.GATHER_TIME);
  try d.tendril(W / 2 - tendril_w / 2, H / 2 - above_head, tendril_w, tendril_h, s.gold, t, 0.9);
}   