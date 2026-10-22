//! gathering progress grows a tendril above the wolf's focus.
const std = @import("std");
const Allocator = std.mem.Allocator;
const play = @import("../play.zig");
const actions = @import("../actions.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("style.zig");

pub fn visible(g:*const play.Game) bool { return g.gather_t > 0 and g.hover != null; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  try d.tendril(W / 2 - 60, H / 2 - 120, 120, 14, s.gold, g.gather_t / actions.GATHER_TIME, 0.9);
}
