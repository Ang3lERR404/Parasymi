//! the HUD, composed only from grown shapes (ui/draw.zig): vine trellises
//! for panels, husks hanging from vines for slots, leafy stems for progress,
//! buds for bullets, seeds for ingredients, glows for focus.
//!
//! Each panel is its own module under `hud/` declaring
//!   draw(g, d, W, H) !void
//!   visible(g) bool              (optional; always drawn when absent)
//!   Pick                         (optional; what its rows are, as `row` makes them)
//!   click(g, p, press, in) void  (optional; what a click on one of its rows does)
//!   shows(g, p) ?Item            (optional; the item a row shows, for the tooltip)
//! Panels draw in declaration order, so later ones sit on top. A new panel is
//! one new file plus one line in `panels`.
const lib = @import("../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const eqlDeep = std.meta.eql;
const registry = lib.engine.core.registry;
const play = lib.play;
const items = lib.items;
const Input = lib.engine.platform.input.Input;
const Draw = lib.engine.ui.draw.Draw;
const Color = lib.engine.ui.draw.Color;
pub const Box = lib.engine.ui.box.Box;
const m = lib.engine.core.math;

/// what a click on the HUD lands on: one of a panel's own rows (its `Pick`),
/// or just a panel (which keeps the click out of the world beneath it).
pub const Pick = union(enum) { panel, row:Row };
/// a row of some panel: tagged by the panel, holding that panel's `Pick`
/// (void for a panel without one)
const Row = reg.Union("Pick");
/// the panels, by name
pub const Panel = reg.Id;

/// panel `id`'s row `p`, as the HUD picks it
pub fn row(comptime id:Panel, p:@FieldType(Row, @tagName(id))) Pick {
  return .{.row = @unionInit(Row, @tagName(id), p)};
}
/// `p`, if it is one of panel `id`'s rows
pub fn own(comptime id:Panel, p:?Pick) ?@FieldType(Row, @tagName(id)) {
  const r = switch (p orelse return null) { .panel => return null, .row => |r| r };
  return if (r == id) @field(r, @tagName(id)) else null;
}

/// how a row was clicked: used (left), the other button (taking back, or
/// turning an option back), or thrown away
pub const Press = enum { use, remove, discard };

/// a click on `p`: the panel that owns the row does what it does (its
/// `click` hook); a click on a bare panel puts down what is carried.
pub fn click(g:*play.Game, p:Pick, press:Press, in:*const Input) void {
  switch (p) {
    .panel => if (press == .use and g.mode.live()) g.drop(),
    .row => |r| switch (r) {
      inline else => |q, id| if (comptime reg.has(id, "click")) reg.module(id).click(g, q, press, in),
    },
  }
}

/// the item shown on the row `p`, if any (its panel's `shows` hook)
pub fn shows(g:*const play.Game, p:Pick) ?items.Item {
  return switch (p) {
    .panel => null,
    .row => |r| switch (r) {
      inline else => |q, id| if (comptime reg.has(id, "shows")) reg.module(id).shows(g, q) else null,
    },
  };
}

/// the research sapling's growth, kept between frames.
pub const Sapling = panels.research.Sapling;

/// the clickable areas the panels drew last frame. Panels add them as they
/// draw (backdrop first, rows on top); `build` clears them; play.update
/// hit-tests the mouse against them, one frame behind the draw.
pub const Rows = struct {
  const MAX = 96;
  box:[MAX]Box = undefined,
  pick:[MAX]Pick = undefined,
  len:usize = 0,

  pub fn add(r:*Rows, b:Box, p:Pick) void {
    if (r.len == MAX) @panic("more clickable HUD rows than Rows.MAX");
    r.box[r.len] = b;
    r.pick[r.len] = p;
    r.len += 1;
  }

  /// the topmost area under `pos` (screen pixels), if any.
  pub fn at(r:*const Rows, pos:[2]f32) ?Pick {
    var i = r.len;
    while (i > 0) {
      i -= 1;
      if (r.box[i].contains(pos)) return r.pick[i];
    }
    return null;
  }

  /// the area last added for `p`, if any.
  pub fn find(r:*const Rows, p:Pick) ?Box {
    var i = r.len;
    while (i > 0) {
      i -= 1;
      if (eqlDeep(r.pick[i], p)) return r.box[i];
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
