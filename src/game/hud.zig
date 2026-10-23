//! the HUD, composed only from living shapes (ui/draw.zig): membranes for
//! panels, seed pods for slots, tendrils for progress, glows for focus.
//!
//! Each panel is its own module under `hud/` declaring
//!   draw(g, d, W, H) !void
//!   visible(g) bool              (optional; always drawn when absent)
//! Panels draw in declaration order, so later ones sit on top. A new panel is
//! one new file plus one line in `panels`.
const std = @import("std");
const Allocator = std.mem.Allocator;
const registry = @import("../core/registry.zig");
const play = @import("play.zig");
const prog = @import("progression.zig");

/// what a click on the HUD lands on: a research node, a weave recipe, or
/// just a panel (which keeps the click out of the world beneath it).
pub const Pick = union(enum) { panel, research:prog.Id, weave:usize };

/// the clickable areas the panels drew last frame. Panels add them as they
/// draw (backdrop first, rows on top); `build` clears them; play.update
/// hit-tests the mouse against them, one frame behind the draw.
pub const Rows = struct {
  const MAX = 48;
  rect:[MAX][4]f32 = undefined,
  pick:[MAX]Pick = undefined,
  len:usize = 0,

  pub fn add(r:*Rows, x:f32, y:f32, w:f32, h:f32, p:Pick) void {
    if (r.len == MAX) @panic("more clickable HUD rows than Rows.MAX");
    r.rect[r.len] = .{x, y, w, h};
    r.pick[r.len] = p;
    r.len += 1;
  }

  /// the topmost area under `pos` (screen pixels), if any.
  pub fn at(r:*const Rows, pos:[2]f32) ?Pick {
    var i = r.len;
    while (i > 0) {
      i -= 1;
      const q = r.rect[i];
      if (pos[0] >= q[0] and pos[0] < q[0] + q[2] and pos[1] >= q[1] and pos[1] < q[1] + q[3]) return r.pick[i];
    }
    return null;
  }
};

const panels = struct {
  pub const status = @import("hud/status.zig");
  pub const hotbar = @import("hud/hotbar.zig");
  pub const hover = @import("hud/hover.zig");
  pub const gather = @import("hud/gather.zig");
  pub const belly = @import("hud/belly.zig");
  pub const research = @import("hud/research.zig");
  pub const log = @import("hud/log.zig");
  pub const debug = @import("hud/debug.zig");
  pub const inspect = @import("hud/inspect.zig");
  pub const pause = @import("hud/pause.zig");
};
const reg = registry.Registry(panels);

pub fn build(g:*play.Game, screen:[2]f32) Allocator.Error!void {
  const d = &g.ui;
  d.clear();
  g.rows.len = 0;
  inline for (reg.ids) |id| {
    const p = reg.module(id);
    const show = if (comptime reg.has(id, "visible")) p.visible(g) else true;
    if (show) try p.draw(g, d, screen[0], screen[1]);
  }
}
