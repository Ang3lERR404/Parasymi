//! the hotbar: a row of husks hanging from a vine, each empty or holding an item the gardener
//! dropped on it from the belly, with the belly's count of it and the
//! selection's name. Click selects; with the belly open, click lifts and
//! puts down.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const m = lib.engine.core.math;
const play = lib.play;
const Draw = lib.engine.ui.draw.Draw;
const s = lib.style;
const txt = lib.txt;
const st = lib.structures;
const items = lib.items;
const icon = lib.icon;
const belly = lib.hud_belly;

const gap = s.slot_gap;
const pod_r:f32 = 20;
const pod_r_sel:f32 = 24;
const glow_alpha:u8 = 110;
/// how see-through a seed not yet understood is
const unknown_alpha:u8 = 110;
/// the vine's seed and growth key
const vine_seed:f32 = 5.5;
/// the selection's name sits this far above the husks, clear of the vine
const label_up:f32 = 70;

/// whether placing `item` puts down a structure that faces a way (R turns it).
fn turns(item:items.Item) bool {
  const k = st.kindOf(item) orelse return false;
  return st.defs.get(k).carrier;
}

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  const n = play.BAR;
  const x0 = W / 2 - gap * m.f(n - 1) / 2;
  const hy = H - 86;
  const t = g.uiT();
  const carrying = g.held != null;
  const vine = belly.rowVine(d, x0 - gap / 2, hy, n, vine_seed);
  try vine.draw(d, t);

  for (g.bar, 0..) |slot, i| {
    const x = x0 + gap * m.f(i);
    const sel = i == g.hot;
    const r = if (sel) pod_r_sel else pod_r;
    g.rows.add(x - gap / 2, hy - gap / 2, gap, gap, .{.bar = i});
    // lifted onto the cursor, it is shown there instead
    const item = if (g.holds(.{.bar = i})) null else slot;
    const col = if (item) |it| it.info().col else s.gold;
    if (sel) try d.glow(x, hy, 40, .{col[0], col[1], col[2], glow_alpha});
    if (g.points(.{.bar = i})) try d.glow(x, hy, 34, if (carrying) s.drop_target else s.slot_hover);
    const grown = vine.reached(x);
    if (grown <= 0) continue;
    try d.husk(x, hy, r * m.smooth(grown), s.pod_empty, if (sel) 1 else 0.25, m.f(i) * 0.37);
    if (item) |it| {
      const alpha = if (play.known(g, it)) 255 else unknown_alpha;
      try icon.draw(d, it, .{x, hy}, r, t, m.f(i) * 0.37, if (sel) 1 else 0.6, alpha);
      try icon.count(d, .{x, hy}, r, g.player.inv.count(it));
    }
    _ = try d.text(x - 4, hy + 28, s.text_small, s.dim, txt.nth(txt.s.hud.hotbar_keys, i));
  }

  const item = g.selected() orelse return;
  var buf:[64]u8 = undefined;
  const name = txt.item(item).name;
  const label = if (!play.known(g, item)) txt.s.hud.not_understood
    else if (turns(item)) txt.bufRender(&buf, txt.s.hud.facing_label, .{name, txt.nth(txt.s.hud.facing, g.place_dir)})
    else name;
  _ = try d.text(W / 2 - Draw.width(label, s.text_sub) / 2, hy - label_up, s.text_sub, s.gold, label);
}
