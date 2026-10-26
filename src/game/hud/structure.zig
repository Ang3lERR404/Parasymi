//! a structure's panel (a click on one that keeps items): its slots beside
//! the belly's, lifted and put down between them as in the belly, and the
//! weaves it may be set to (a germinator's `recipes`).
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const m = lib.engine.core.math;
const play = lib.play;
const st = lib.structures;
const craft = lib.craft;
const Draw = lib.engine.ui.draw.Draw;
const s = lib.style;
const hud = lib.hud;
const txt = lib.txt;
const icon = lib.icon;
const belly = lib.hud_belly;
const Slot = lib.hud_slot.Slot;

/// its slots, this many across (the belly's grid sits to their right)
const cols = 4;
const gap = s.slot_gap;
const store_w = gap * cols;
const store_h = gap * m.f((st.SLOTS + cols - 1) / cols);
comptime { assert(store_h <= belly.height); }

const margin:f32 = 76;
const between:f32 = 72;
const pw = margin + store_w + between + belly.width + margin;
const header_h:f32 = 116;
const label_h:f32 = 34;
const hint_h:f32 = 76;
/// the weave choices: rows of seed pods, the shown one's ingredients beside
/// them, one to a line
const recipe_cols = 7;
const recipe_gap:f32 = 58;
const recipe_line:f32 = 18;
fn recipesH(n:usize) f32 { return 104 + recipe_gap * m.f((n + recipe_cols - 1) / recipe_cols - 1); }
const recipe_r:f32 = 19;
const unready_alpha:u8 = 120;

pub fn visible(g:*const play.Game) bool { return g.opened() != null; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  const sp = g.structs.get(g.opened().?);
  const choices = st.recipes(sp.kind());
  const ph = header_h + (if (choices.len > 0) recipesH(choices.len) else 0) + label_h + belly.height + hint_h;
  const px = (W - pw) / 2;
  const py = (H - ph) / 2 - s.panel_lift;

  try d.trellis(px, py, pw, ph, s.panel, 0.41);
  g.rows.add(.{.x = px, .y = py, .w = pw, .h = ph}, .panel);
  _ = try d.text(px + margin, py + 40, s.text_title, s.gold, txt.structure(sp.kind()));
  try st.describe(sp, d, &g.prog, px + margin, py + 80);

  var y = py + header_h;
  if (choices.len > 0) {
    try recipes(g, d, sp, choices, px + margin, y);
    y += recipesH(choices.len);
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
  const row0 = y + 58;
  for (choices, 0..) |r, k| {
    const cx = x + recipe_gap * (m.f(k % recipe_cols) + 0.5);
    const cy = row0 + recipe_gap * m.f(k / recipe_cols);
    const on = chosen == r;
    var sl = Slot.around(.{cx, cy}, recipe_gap, recipe_gap, .{.recipe = r}, (recipe_r + 3) / recipe_gap);
    sl.lit = if (on) 1 else 0;
    sl.halo = if (on) s.research_active else null;
    sl.takes = false;
    sl.phase = m.f(k) * 0.29;
    if (g.points(sl.pick)) shown = r;
    _ = try sl.draw(g, d);
    if (craft.hand[r].unlocked(&g.prog)) {
      try icon.draw(d, craft.hand[r].out, sl.center(), recipe_r, t, sl.phase, if (on) 1 else 0.3, if (on) 255 else unready_alpha);
    } else try hud.bullet(d, cx, cy - recipe_r * 0.3, recipe_r * 0.6, s.unknown, 0, sl.phase);
  }

  const r = craft.hand[shown orelse return];
  const ix = x + recipe_gap * m.f(@min(choices.len, recipe_cols)) + 24;
  const cy = row0;
  if (!r.unlocked(&g.prog)) {
    const need = if (r.needs) |n| txt.research(n).name else txt.s.hud.unknown;
    _ = try d.print(ix, cy - 10, s.text_body, s.unknown, txt.s.hud.recipe_needs, .{need});
    return;
  }
  _ = try d.print(ix, cy - 24, s.text_body, if (shown == chosen) s.gold else s.white, if (r.n > 1) txt.s.hud.recipe_many else txt.s.hud.recipe, .{txt.item(r.out).name, r.n});
  for (r.in, 0..) |ing, j| {
    const have = sp.inv.count(ing.item);
    const enough = have >= ing.n;
    const ly = cy + 4 + recipe_line * m.f(j);
    try d.grain(ix + 10, ly + 5, 9, 13, ing.item.info().col, if (enough) 0.7 else 0, m.f(j) * 0.3);
    _ = try d.print(ix + 22, ly, s.text_fine, if (enough) s.white else s.dim, txt.s.hud.stock, .{have, ing.n, txt.item(ing.item).short});
  }
}
