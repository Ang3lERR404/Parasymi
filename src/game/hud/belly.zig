//! the sap belly (Tab): the wolf's inventory, and the weave list below it.
const std = @import("std");
const Allocator = std.mem.Allocator;
const play = @import("../play.zig");
const player_mod = @import("../player.zig");
const prog = @import("../progression.zig");
const craft = @import("../craft.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("../style.zig");
const txt = @import("../text.zig");
const m = @import("../../core/math.zig");

const cols = 6;
const rows = player_mod.SLOTS / cols;
comptime { std.debug.assert(player_mod.SLOTS % cols == 0); }

const gap:f32 = 64;
const pw:f32 = 780;
const header_h:f32 = 72;
const weave_row_h:f32 = 52;
const panel_lift:f32 = 30; // shift up to clear the hotbar

pub fn visible(g:*const play.Game) bool { return g.mode == .belly; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  const weave_rows = (craft.hand.len + 1) / 2;
  const slots_h = gap * m.f(rows);
  const weave_h = 42 + weave_row_h * m.f(weave_rows);
  const ph = header_h + slots_h + weave_h + 40;
  const px = (W - pw) / 2;
  const py = (H - ph) / 2 - panel_lift;

  try d.membrane(px, py, pw, ph, s.membrane, 0.33);
  g.rows.add(px, py, pw, ph, .panel);
  _ = try d.text(px + 72, py + 30, s.text_title, s.gold, txt.s.hud.belly_title);
  _ = try d.print(px + pw - 200, py + 38, s.text_sub, s.dim, txt.s.hud.belly_fill, .{g.player.inv.fill() * 100});

  var y = py + header_h;
  try slots(g, d, px, y);
  y += slots_h + 6;
  try weaves(g, d, px, y);
}

fn slots(g:*play.Game, d:*Draw, px:f32, py:f32) Allocator.Error!void {
  const gx = px + (pw - gap * cols) / 2;
  for (g.player.inv.slot, 0..) |slot, i| {
    const cx = gx + gap * (m.f(i % cols) + 0.5);
    const cy = py + gap * (m.f(i / cols) + 0.5);
    if (slot) |st| {
      const info = st.item.info();
      const full = m.ratio(st.n, info.stack);
      try d.pod(cx, cy, 24, info.col, 0.3 + 0.7 * full, m.f(i) * 0.13);
      _ = try d.text(cx - 12, cy - 12, s.text_heading, s.dark, txt.item(st.item).short);
      _ = try d.number(cx - 10, cy + 8, s.text_note, s.white, st.n);
    } else {
      try d.pod(cx, cy, 19, s.pod_empty, 0, m.f(i) * 0.13);
    }
  }
}

/// two columns of recipes; locked ones shown as unknown. Clicking one weaves it.
fn weaves(g:*play.Game, d:*Draw, px:f32, wy:f32) Allocator.Error!void {
  _ = try d.text(px + 72, wy, s.text_heading, s.gold, txt.s.hud.weave);
  _ = try d.text(px + pw - 260, wy + 6, s.text_fine, s.dim, txt.s.hud.weave_hint);
  if (g.weave.busy()) {
    try d.tendril(px + 130, wy + 6, 200, s.bar_h_bold, s.gold, g.weave.progress(), 0.4);
    _ = try d.print(px + 346, wy + 2, s.text_note, s.dim, txt.s.hud.queued, .{g.weave.len});
  }
  const col_w = (pw - 60) / 2;
  for (craft.hand, 0..) |r, i| {
    const colx = px + 70 + m.f(i % 2) * col_w;
    const y = wy + 42 + weave_row_h * m.f(i / 2);
    g.rows.add(colx - 10, y - 24, col_w - 20, weave_row_h, .{.weave = i});
    const open = r.unlocked(&g.prog);
    const ok = open and craft.Crafter.can(g.player.inv.bag(), r);
    const info = r.out.info();
    try d.pod(colx + 16, y, 15, if (open) info.col else s.unknown, if (ok) 0.9 else 0.1, m.f(i) * 0.5);
    if (!open) {
      const need_name = if (r.needs) |n| txt.research(n).name else txt.s.hud.unknown;
      _ = try d.print(colx + 40, y - 14, s.text_body, s.unknown, txt.s.hud.recipe_needs, .{need_name});
      continue;
    }
    _ = try d.print(colx + 40, y - 14, s.text_body, if (ok) s.white else s.dim, if (r.n > 1) txt.s.hud.recipe_many else txt.s.hud.recipe, .{txt.item(r.out).name, r.n});
    var x = colx + 44;
    for (r.in, 0..) |ing, j| {
      const have = g.player.inv.count(ing.item) >= ing.n;
      try d.pod(x + 6, y + 10, 6, ing.item.info().col, if (have) 0.7 else 0.05, m.f(j) * 0.3);
      x = try d.print(x + 14, y + 5, s.text_fine, if (have) s.white else s.dim, txt.s.hud.ingredient, .{ing.n, txt.item(ing.item).short}) + 10;
    }
  }
}   