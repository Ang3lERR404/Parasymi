//! the sap belly (Tab): the wolf's inventory, and the weave list below it.
const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const play = @import("../play.zig");
const player_mod = @import("../player.zig");
const prog = @import("../progression.zig");
const craft = @import("../craft.zig");
const Draw = @import("engine").ui.draw.Draw;
const s = @import("../style.zig");
const txt = @import("../text.zig");
const m = @import("engine").core.math;
const icon = @import("../icon.zig");
const items = @import("../../sim/items.zig");
const hud = @import("../hud.zig");

pub const cols = 6;
const rows = player_mod.SLOTS / cols;
comptime { assert(player_mod.SLOTS % cols == 0); }

const gap = s.slot_gap;
const pw:f32 = 780;
const header_h:f32 = 72;
const weave_row_h:f32 = 52;
const slot_r:f32 = 24;
const lifted_alpha:u8 = 50;
/// a recipe's output, and how faded while it cannot be woven yet
const recipe_r:f32 = 15;
const unready_alpha:u8 = 150;

pub fn visible(g:*const play.Game) bool { return g.mode == .belly; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  const weave_rows = (craft.by_hand.len + 1) / 2;
  const slots_h = gap * m.f(rows);
  const weave_h = 42 + weave_row_h * m.f(weave_rows);
  const ph = header_h + slots_h + weave_h + 40;
  const px = (W - pw) / 2;
  const py = (H - ph) / 2 - s.panel_lift;

  try d.membrane(px, py, pw, ph, s.membrane, 0.33);
  g.rows.add(px, py, pw, ph, .panel);
  _ = try d.text(px + 72, py + s.title_y, s.text_title, s.gold, txt.s.hud.belly_title);
  _ = try d.print(px + pw - 200, py + 38, s.text_sub, s.dim, txt.s.hud.belly_fill, .{g.player.inv.fill() * 100});
  _ = try d.text(px + 72, py + 58, s.text_fine, s.dim, txt.s.hud.belly_hint);

  var y = py + header_h;
  try grid(g, d, .slot, &g.player.inv.slot, cols, px + (pw - gap * cols) / 2, y);
  y += slots_h + 6;
  try weaves(g, d, px, y);
}

/// the side of a slot grid: the belly's, or the open structure's
pub const Side = enum { slot, store };
/// the belly's slot grid is this wide
pub const width = gap * cols;
pub const height = gap * m.f(rows);

/// the slots of one side, `columns` across from `gx`, in the order the
/// gardener keeps them: a click lifts a stack onto the cursor, the next
/// puts it down (play.Game.clickSlot / clickStore).
pub fn grid(g:*play.Game, d:*Draw, comptime side:Side, stacks:[]const ?items.Stack, columns:usize, gx:f32, py:f32) Allocator.Error!void {
  const t = g.uiT();
  const carrying = g.held != null;
  for (stacks, 0..) |slot, i| {
    const cx = gx + gap * (m.f(i % columns) + 0.5);
    const cy = py + gap * (m.f(i / columns) + 0.5);
    const phase = m.f(i) * 0.13;
    const pick = @unionInit(hud.Pick, @tagName(side), i);
    g.rows.add(cx - gap / 2, cy - gap / 2, gap, gap, pick);
    if (g.points(pick)) try d.glow(cx, cy, 36, if (carrying) s.drop_target else s.slot_hover);
    try d.pod(cx, cy, 21, s.pod_empty, 0, phase);
    const it = slot orelse continue;
    // lifted onto the cursor: only a faint trace stays behind
    const lifted = g.holds(@unionInit(play.Held, @tagName(side), i));
    const full = m.ratio(it.n, items.STACK);
    try icon.draw(d, it.item, .{cx, cy}, slot_r, t, phase, 0.3 + 0.7 * full, if (lifted) lifted_alpha else 255);
    if (!lifted) try icon.count(d, .{cx, cy}, slot_r, it.n);
  }
}

/// two columns of the recipes woven by hand (no seeds: a germinator weaves
/// those); locked ones shown as unknown. Clicking one weaves it.
fn weaves(g:*play.Game, d:*Draw, px:f32, wy:f32) Allocator.Error!void {
  _ = try d.text(px + 72, wy, s.text_heading, s.gold, txt.s.hud.weave);
  _ = try d.text(px + pw - 260, wy + 6, s.text_fine, s.dim, txt.s.hud.weave_hint);
  if (g.weave.busy()) {
    try d.tendril(px + 130, wy + 6, 200, s.bar_h_bold, s.gold, g.weave.progress(), 0.4);
    _ = try d.print(px + 346, wy + 2, s.text_note, s.dim, txt.s.hud.queued, .{g.weave.len});
  }
  const col_w = (pw - 60) / 2;
  for (craft.by_hand, 0..) |i, k| {
    const r = craft.hand[i];
    const colx = px + 70 + m.f(k % 2) * col_w;
    const y = wy + 42 + weave_row_h * m.f(k / 2);
    g.rows.add(colx - 10, y - 24, col_w - 20, weave_row_h, .{.weave = i});
    const open = r.unlocked(&g.prog);
    const ok = open and craft.Crafter.can(g.player.inv.bag(), r);
    if (open) try icon.draw(d, r.out, .{colx + 16, y}, recipe_r, g.uiT(), m.f(i) * 0.5, if (ok) 0.9 else 0.1, if (ok) 255 else unready_alpha)
    else try d.pod(colx + 16, y, recipe_r, s.unknown, 0.1, m.f(i) * 0.5);
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