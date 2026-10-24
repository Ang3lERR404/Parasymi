//! a structure's panel (a click on one that keeps items): its slots beside
//! the belly's, lifted and put down between them as in the belly, and the
//! seeds it may be set to weave (a germinator's `recipes`).
const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const m = @import("../../core/math.zig");
const play = @import("../play.zig");
const st = @import("../structures.zig");
const craft = @import("../craft.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("../style.zig");
const txt = @import("../text.zig");
const icon = @import("../icon.zig");
const belly = @import("belly.zig");

/// its slots, this many across (the belly's grid sits to their right)
const cols = 4;
const gap:f32 = 64;
const store_w = gap * cols;
const store_h = gap * m.f((st.SLOTS + cols - 1) / cols);
comptime { assert(store_h <= belly.height); }

const margin:f32 = 76;
const between:f32 = 72;
const pw = margin + store_w + between + belly.width + margin;
const header_h:f32 = 116;
const label_h:f32 = 34;
const hint_h:f32 = 76;
const panel_lift:f32 = 30; // shift up to clear the hotbar
/// the weave choices: a row of seed pods, the shown one's ingredients beside
const recipes_h:f32 = 104;
const recipe_gap:f32 = 58;
const recipe_r:f32 = 19;
const unready_alpha:u8 = 120;

pub fn visible(g:*const play.Game) bool { return g.opened() != null; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  const sp = g.structs.get(g.opened().?);
  const choices = st.recipes(sp.kind());
  const ph = header_h + (if (choices.len > 0) recipes_h else 0) + label_h + belly.height + hint_h;
  const px = (W - pw) / 2;
  const py = (H - ph) / 2 - panel_lift;

  try d.membrane(px, py, pw, ph, s.membrane, 0.41);
  g.rows.add(px, py, pw, ph, .panel);
  _ = try d.text(px + margin, py + 40, s.text_title, s.gold, txt.structure(sp.kind()));
  try st.describe(sp, d, &g.prog, px + margin, py + 80);

  var y = py + header_h;
  if (choices.len > 0) {
    try recipes(g, d, sp, choices, px + margin, y);
    y += recipes_h;
  }
  const bx = px + margin + store_w + between;
  _ = try d.text(px + margin, y, s.text_heading, s.gold, txt.s.hud.holds);
  _ = try d.text(bx, y, s.text_heading, s.gold, txt.s.hud.belly_title);
  _ = try d.print(bx + belly.width - 100, y + 6, s.text_note, s.dim, txt.s.hud.belly_fill, .{g.player.inv.fill() * 100});
  y += label_h;
  try belly.grid(g, d, .store, &sp.inv.slot, cols, px + margin, y);
  try belly.grid(g, d, .slot, &g.player.inv.slot, belly.cols, bx, y);
  _ = try d.text(px + margin, y + belly.height + 18, s.text_fine, s.dim, txt.s.hud.store_hint);
}

/// the recipes it may be set to weave, the chosen one lit; beside them, what
/// the one under the mouse (else the chosen one) is woven from, against
/// what the structure holds. A click chooses.
fn recipes(g:*play.Game, d:*Draw, sp:*const st.Structure, choices:[]const u8, x:f32, y:f32) Allocator.Error!void {
  _ = try d.text(x, y, s.text_heading, s.gold, txt.s.hud.weave_choose);
  const t = g.uiT();
  const chosen = st.chosen(sp);
  var shown = chosen;
  const cy = y + 58;
  for (choices, 0..) |r, k| {
    const cx = x + recipe_gap * (m.f(k) + 0.5);
    const phase = m.f(k) * 0.29;
    const on = chosen == r;
    g.rows.add(cx - recipe_gap / 2, cy - recipe_gap / 2, recipe_gap, recipe_gap, .{.recipe = r});
    if (g.points(.{.recipe = r})) {
      shown = r;
      try d.glow(cx, cy, 34, s.slot_hover);
    }
    if (on) try d.glow(cx, cy, 38, s.research_active);
    try d.pod(cx, cy, recipe_r + 3, s.pod_empty, if (on) 1 else 0, phase);
    if (craft.hand[r].unlocked(&g.prog)) {
      try icon.draw(d, craft.hand[r].out, .{cx, cy}, recipe_r, t, phase, if (on) 1 else 0.3, if (on) 255 else unready_alpha);
    } else try d.pod(cx, cy, recipe_r * 0.7, s.unknown, 0.1, phase);
  }

  const r = craft.hand[shown orelse return];
  const ix = x + recipe_gap * m.f(choices.len) + 24;
  if (!r.unlocked(&g.prog)) {
    const need = if (r.needs) |n| txt.research(n).name else txt.s.hud.unknown;
    _ = try d.print(ix, cy - 10, s.text_body, s.unknown, txt.s.hud.recipe_needs, .{need});
    return;
  }
  _ = try d.print(ix, cy - 24, s.text_body, if (shown == chosen) s.gold else s.white, if (r.n > 1) txt.s.hud.recipe_many else txt.s.hud.recipe, .{txt.item(r.out).name, r.n});
  var ex = ix + 4;
  for (r.in, 0..) |ing, j| {
    const have = sp.inv.count(ing.item);
    const enough = have >= ing.n;
    try d.pod(ex + 6, cy + 14, 6, ing.item.info().col, if (enough) 0.7 else 0.05, m.f(j) * 0.3);
    ex = try d.print(ex + 14, cy + 9, s.text_fine, if (enough) s.white else s.dim, txt.s.hud.stock, .{have, ing.n, txt.item(ing.item).short}) + 12;
  }
}
