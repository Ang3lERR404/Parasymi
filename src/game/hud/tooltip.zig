//! an item's full name, on a small membrane beside the cursor, while the
//! mouse rests on a belly or hotbar slot holding one.
const std = @import("std");
const Allocator = std.mem.Allocator;
const play = @import("../play.zig");
const items = @import("../../sim/items.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("../style.zig");
const txt = @import("../text.zig");
const craft = @import("../craft.zig");

/// from the cursor to the card, the card's margin and line height
const offset = [2]f32{20, 10};
const margin:f32 = 12;
const line_h:f32 = 22;
const edge:f32 = 8;

/// the item on the slot under the mouse (not one lifted from it).
fn pointed(g:*const play.Game) ?items.Item {
  const p = g.pointed orelse return null;
  return switch (p) {
    .slot => |i| if (g.holds(.{.slot = i})) null else if (g.player.inv.slot[i]) |it| it.item else null,
    .bar => |i| if (g.holds(.{.bar = i})) null else g.bar[i],
    .store => |i| if (g.holds(.{.store = i})) null else if (g.storeSlot(i)) |it| it.item else null,
    // what a recipe weaves, once it is understood
    .recipe => |r| if (craft.hand[r].unlocked(&g.prog)) craft.hand[r].out else null,
    .panel, .research, .weave, .pause, .option, .back => null,
  };
}

pub fn visible(g:*const play.Game) bool {
  return g.mode.live() and g.mode != .inspect and pointed(g) != null;
}

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  const item = pointed(g).?;
  const name = txt.item(item).name;
  const known = play.known(g, item);
  const w = @max(Draw.width(name, s.text_sub), if (known) 0 else Draw.width(txt.s.hud.not_understood, s.text_fine)) + 2 * margin;
  const h = line_h * @as(f32, if (known) 1 else 2) + margin;
  // beside the cursor, kept on screen
  const x = @min(g.mouse[0] + offset[0], W - w - edge);
  const y = @max(@min(g.mouse[1] - h - offset[1], H - h - edge), edge);
  try d.membrane(x, y, w, h, s.skin, 0.8);
  _ = try d.text(x + margin, y + margin * 0.75, s.text_sub, item.info().col, name);
  if (!known) _ = try d.text(x + margin, y + margin * 0.75 + line_h, s.text_fine, s.dim, txt.s.hud.not_understood);
}
