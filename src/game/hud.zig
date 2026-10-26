//! the HUD, composed only from grown shapes (ui/draw.zig): vine trellises
//! for panels, husks hanging from vines for slots, leafy stems for progress,
//! buds for bullets, seeds for ingredients, glows for focus.
//!
//! Each panel is its own module under `hud/` declaring
//!   draw(g, d, W, H) !void
//!   visible(g) bool              (optional; always drawn when absent)
//! Panels draw in declaration order, so later ones sit on top. A new panel is
//! one new file plus one line in `panels`.
const lib = @import("../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const eqlDeep = std.meta.eql;
const registry = lib.engine.core.registry;
const play = lib.play;
const prog = lib.progression;
const opt = lib.options;
const Draw = lib.engine.ui.draw.Draw;
const Color = lib.engine.ui.draw.Color;
const m = lib.engine.core.math;

/// what a click on the HUD lands on: a research node, a weave recipe, a
/// belly slot, a hotbar slot, a slot of the open structure, a recipe it may
/// be set to weave, a pause menu row, an option, the way back to the pause
/// menu, a saved garden (0: a fresh one), a button under them, their
/// scroll groove, or just a panel (which keeps the click out of the world
/// beneath it).
pub const Pick = union(enum) {
  panel, research:prog.Id, weave:usize, slot:usize, bar:usize,
  store:usize, recipe:u8,
  pause:play.PauseRow, option:opt.Setting, back,
  garden:usize, garden_act:play.GardenAct, scroll,
};

/// the research sapling's growth, kept between frames.
pub const Sapling = panels.research.Sapling;

/// the clickable areas the panels drew last frame. Panels add them as they
/// draw (backdrop first, rows on top); `build` clears them; play.update
/// hit-tests the mouse against them, one frame behind the draw.
pub const Rows = struct {
  const MAX = 96;
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

  /// the area last added for `p`, if any.
  pub fn find(r:*const Rows, p:Pick) ?[4]f32 {
    var i = r.len;
    while (i > 0) {
      i -= 1;
      if (eqlDeep(r.pick[i], p)) return r.rect[i];
    }
    return null;
  }
};

pub const panels = struct {
  pub const status = @import("hud/status.zig");
  pub const hotbar = @import("hud/hotbar.zig");
  pub const hover = @import("hud/hover.zig");
  pub const gather = @import("hud/gather.zig");
  pub const belly = @import("hud/belly.zig");
  pub const structure = @import("hud/structure.zig");
  pub const research = @import("hud/research.zig");
  pub const log = @import("hud/log.zig");
  pub const debug = @import("hud/debug.zig");
  pub const inspect = @import("hud/inspect.zig");
  pub const eyes = @import("hud/eyes.zig");
  pub const tooltip = @import("hud/tooltip.zig");
  pub const carry = @import("hud/carry.zig");
  pub const pause = @import("hud/pause.zig");
  pub const options = @import("hud/options.zig");
  pub const gardens = @import("hud/gardens.zig");
  pub const naming = @import("hud/naming.zig");
};
const reg = registry.Registry(panels);

/// a row's bullet: a bud of radius `r` at (cx, cy), opening as `open` runs
/// to 1 (the row under the mouse).
pub fn bullet(d:*Draw, cx:f32, cy:f32, r:f32, col:Color, open:f32, seed:f32) Allocator.Error!void {
  try d.leaf(.{cx, cy + r}, -m.half_pi, 2 * r, 1.1 * r, col, open, seed);
}

pub fn build(g:*play.Game, screen:[2]f32) Allocator.Error!void {
  const d = &g.ui;
  d.clear(@floatCast(g.ui_time));
  g.rows.len = 0;
  inline for (reg.ids) |id| {
    const p = reg.module(id);
    const show = if (comptime reg.has(id, "visible")) p.visible(g) else true;
    if (show) try p.draw(g, d, screen[0], screen[1]);
  }
}
