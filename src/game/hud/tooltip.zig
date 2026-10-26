//! an item's full name, on a small trellis beside the cursor, while the
//! mouse rests on a row showing one (a slot holding one, a recipe).
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const play = lib.play;
const items = lib.items;
const Draw = lib.engine.ui.draw.Draw;
const s = lib.style;
const txt = lib.txt;
const hud = lib.hud;

/// from the cursor to the card, the card's margin and line height
const offset = [2]f32{20, 10};
const margin:f32 = 12;
const line_h:f32 = 22;
const edge:f32 = 8;

/// the item on the row under the mouse, as its panel shows it.
fn pointed(g:*const play.Game) ?items.Item {
  return hud.shows(g, g.pointed orelse return null);
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
  try d.trellis(x, y, w, h, s.card, 0.8);
  _ = try d.text(x + margin, y + margin * 0.75, s.text_sub, item.info().col, name);
  if (!known) _ = try d.text(x + margin, y + margin * 0.75 + line_h, s.text_fine, s.dim, txt.s.hud.not_understood);
}
