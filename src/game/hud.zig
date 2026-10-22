//! the HUD, composed only from living shapes (ui/draw.zig): membranes for
//! panels, seed pods for slots, tendrils for progress, glows for focus.
//!
//! Each panel is its own module under `hud/` declaring
//!   draw(g, d, W, H) !void
//!   visible(g) bool              (optional; always drawn when absent)
//! Panels draw in declaration order, so later ones sit on top. A new panel is
//! one new file plus one line in `panels`.
const registry = @import("../core/registry.zig");
const play = @import("play.zig");

const panels = struct {
  pub const status = @import("hud/status.zig");
  pub const hotbar = @import("hud/hotbar.zig");
  pub const hover = @import("hud/hover.zig");
  pub const gather = @import("hud/gather.zig");
  pub const belly = @import("hud/belly.zig");
  pub const research = @import("hud/research.zig");
  pub const log = @import("hud/log.zig");
  pub const debug = @import("hud/debug.zig");
  pub const pause = @import("hud/pause.zig");
};
const reg = registry.Registry(panels);

pub fn build(g:*play.Game, screen:[2]f32) !void {
  const d = &g.ui;
  d.clear();
  inline for (reg.ids) |id| {
    const p = reg.module(id);
    const show = if (comptime reg.has(id, "visible")) p.visible(g) else true;
    if (show) try p.draw(g, d, screen[0], screen[1]);
  }
}
