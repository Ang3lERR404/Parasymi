//! the sap belly (Tab): the wolf's inventory, slots hanging in rows from
//! vines on a trellis whose main stem fills with sap as the belly does, and
//! the weave list below it.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const play = lib.play;
const player_mod = lib.player;
const prog = lib.progression;
const craft = lib.craft;
const Draw = lib.engine.ui.draw.Draw;
const s = lib.style;
const txt = lib.txt;
const m = lib.engine.core.math;
const icon = lib.icon;
const items = lib.items;
const hud = lib.hud;
const Slot = lib.hud_slot.Slot;

pub const cols = 6;
const rows = player_mod.SLOTS / cols;
comptime { assert(player_mod.SLOTS % cols == 0); }

const gap = s.slot_gap;
const pw:f32 = 830;
/// room for the title, the hint and the first row's vine above its husks
const header_h:f32 = 88;
const weave_row_h:f32 = 52;
const slot_r:f32 = 24;
const husk_r:f32 = 21;
const lifted_alpha:u8 = 50;
/// a recipe's output, and how faded while it cannot be woven yet
const recipe_r:f32 = 15;
const unready_alpha:u8 = 150;
/// seconds a row's vine takes to grow across
const vine_grow:f32 = 0.7;
/// the main stem: in from the panel's left, how far below its top it ends
const stem_x:f32 = 40;
const stem_top:f32 = 26;

pub fn visible(g:*const play.Game) bool { return g.mode == .belly; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  const weave_rows = (craft.by_hand.len + 1) / 2;
  const slots_h = gap * m.f(rows);
  const weave_h = 42 + weave_row_h * m.f(weave_rows);
  const ph = header_h + slots_h + weave_h + 40;
  const px = (W - pw) / 2;
  const py = (H - ph) / 2 - s.panel_lift;

  try d.trellis(px, py, pw, ph, s.panel, 0.33);
  g.rows.add(.{.x = px, .y = py, .w = pw, .h = ph}, .panel);
  _ = try d.text(px + 72, py + s.title_y, s.text_title, s.gold, txt.s.hud.belly_title);
  _ = try d.print(px + pw - 200, py + 38, s.text_sub, s.dim, txt.s.hud.belly_fill, .{g.player.inv.fill() * 100});
  _ = try d.text(px + 72, py + 58, s.text_fine, s.dim, txt.s.hud.belly_hint);

  var y = py + header_h;
  // the trellis's main stem up its left side, sap rising in it as the belly fills
  try d.stem(.{px + stem_x, y + slots_h}, -m.half_pi, slots_h + header_h - stem_top, s.bar_h_bold, s.sap, g.player.inv.fill(), 0.27);
  try grid(g, d, .slot, &g.player.inv.slot, cols, px + (pw - gap * cols) / 2, y);
  y += slots_h + 6;
  try weaves(g, d, px, y);
}

/// the side of a slot grid: the belly's, or the open structure's
pub const Side = enum { slot, store };
/// the belly's slot grid is this wide
pub const width = gap * cols;
pub const height = gap * m.f(rows);

/// a vine slots hang from: it runs `y` above their centres, a little wavy,
/// from `x0` to `x1`, grown from its left end to `grow` of its length, a
/// pair of leaves unfurling between each two slots `step` apart once it has
/// passed. Returns how far grown it is at `x` (0 before the tip, 1 well past).
pub const Vine = struct {
  x0:f32, x1:f32, y:f32, step:f32, grow:f32, seed:f32,

  const seg:f32 = 12;
  /// how far it runs past its first and last slots' outer edges
  const end_pad:f32 = 8;
  const wave:f32 = 2.5;
  const r0:f32 = 3.2;
  const r1:f32 = 2.4;
  /// px of vine behind its tip that tapers, and that a slot or leaf takes to
  /// grow once the tip has passed it
  const tip:f32 = 40;
  const leaf_len:f32 = 13;
  const leaf_wid:f32 = 5;
  /// the slot's husk hangs this far below the vine (its stalk's reach)
  pub const drop:f32 = 34;

  fn at(v:Vine, x:f32) f32 { return v.y + wave * @sin(x * 0.045 + v.seed * 7); }
  fn tipX(v:Vine) f32 { return m.lerp(v.x0, v.x1, v.grow); }
  /// how far grown the vine is at `x`
  pub fn reached(v:Vine, x:f32) f32 { return m.clamp01((v.tipX() - x) / tip); }

  pub fn draw(v:Vine, d:*Draw, t:f32) Allocator.Error!void {
    const end = v.tipX();
    if (end <= v.x0) return;
    const n:usize = @intFromFloat(@ceil((end - v.x0) / seg));
    var a:[2]f32 = .{v.x0, v.at(v.x0)};
    var arc:f32 = 0;
    for (0..n) |i| {
      const x = @min(v.x0 + seg * m.f(i + 1), end);
      const b:[2]f32 = .{x, v.at(x)};
      const k = (x - v.x0) / @max(v.x1 - v.x0, 1);
      const ra = m.lerp(r0, r1, (a[0] - v.x0) / @max(v.x1 - v.x0, 1)) * @sqrt(m.clamp01((end - a[0]) / tip));
      const rb = m.lerp(r0, r1, k) * @sqrt(m.clamp01((end - x) / tip));
      try d.limb(a, b, @max(ra, 0.6), @max(@min(rb, ra), 0.4), s.bark_young, arc);
      arc += b[0] - a[0];
      a = b;
    }
    // leaves between the slots, one up one down, swaying
    var x = v.x0 + end_pad + v.step;
    var i:usize = 0;
    while (x < v.x1 - end_pad - 1) : ({ x += v.step; i += 1; }) {
      const open = v.reached(x);
      if (open <= 0) continue;
      const sway = 0.12 * @sin(t * 1.6 + m.f(i) * 1.9 + v.seed * 5);
      const base:[2]f32 = .{x, v.at(x)};
      try d.leaf(base, -2.2 + sway, leaf_len * open, leaf_wid * open, s.leaf, open, v.seed + m.f(i));
      try d.leaf(base, -0.9 - sway, leaf_len * 0.85 * open, leaf_wid * open, s.leaf, open, v.seed + m.f(i) + 0.5);
    }
  }
};

/// the slots of one side, `columns` across from `gx`, in the order the
/// gardener keeps them, each hanging from its row's vine: a click lifts a
/// stack onto the cursor, the next puts it down (play.Game.clickSlot /
/// clickStore).
pub fn grid(g:*play.Game, d:*Draw, comptime side:Side, stacks:[]const ?items.Stack, columns:usize, gx:f32, py:f32) Allocator.Error!void {
  const t = g.uiT();
  const n_rows = (stacks.len + columns - 1) / columns;
  for (0..n_rows) |row| {
    const vine = rowVine(d, gx, py + gap * (m.f(row) + 0.5), columns, rowSeed(side, row));
    try vine.draw(d, t);
  }
  for (stacks, 0..) |slot, i| {
    const cx = gx + gap * (m.f(i % columns) + 0.5);
    const cy = py + gap * (m.f(i / columns) + 0.5);
    var sl = Slot.around(.{cx, cy}, gap, gap, @unionInit(hud.Pick, @tagName(side), i), husk_r / gap);
    sl.grown = rowVine(d, gx, cy, columns, rowSeed(side, i / columns)).reached(cx);
    sl.phase = m.f(i) * 0.13;
    if (!try sl.draw(g, d)) continue;
    const it = slot orelse continue;
    // lifted onto the cursor: only a faint trace stays behind
    const lifted = g.holds(@unionInit(play.Held, @tagName(side), i));
    const full = m.ratio(it.n, items.STACK);
    try icon.draw(d, it.item, sl.center(), slot_r, t, sl.phase, 0.3 + 0.7 * full, if (lifted) lifted_alpha else 255);
    if (!lifted) try icon.count(d, sl.center(), slot_r, it.n);
  }
}

/// a row's vine's seed (and growth key): apart from every panel's
fn rowSeed(side:Side, row:usize) f32 { return 7 + m.f(@intFromEnum(side)) * 0.37 + m.f(row) * 0.11; }

/// the vine a row of `columns` slots centred at `cy` hangs from, grown as
/// far as its panel has (keyed by `seed`, as `Draw.grown`).
pub fn rowVine(d:*Draw, gx:f32, cy:f32, columns:usize, seed:f32) Vine {
  return .{
    .x0 = gx - Vine.end_pad, .x1 = gx + gap * m.f(columns) + Vine.end_pad, .y = cy - Vine.drop,
    .step = gap, .grow = d.grown(seed, vine_grow), .seed = seed,
  };
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
    g.rows.add(.{.x = colx - 10, .y = y - 24, .w = col_w - 20, .h = weave_row_h}, .{.weave = i});
    const open = r.unlocked(&g.prog);
    const ok = open and craft.Crafter.can(g.player.inv.bag(), r);
    if (open) try icon.draw(d, r.out, .{colx + 16, y}, recipe_r, g.uiT(), m.f(i) * 0.5, if (ok) 0.9 else 0.1, if (ok) 255 else unready_alpha)
    else try d.leaf(.{colx + 16, y + recipe_r * 0.8}, -m.half_pi, recipe_r * 1.6, recipe_r * 0.7, s.unknown, 0, m.f(i) * 0.5);
    if (!open) {
      const need_name = if (r.needs) |n| txt.research(n).name else txt.s.hud.unknown;
      _ = try d.print(colx + 40, y - 14, s.text_body, s.unknown, txt.s.hud.recipe_needs, .{need_name});
      continue;
    }
    _ = try d.print(colx + 40, y - 14, s.text_body, if (ok) s.white else s.dim, if (r.n > 1) txt.s.hud.recipe_many else txt.s.hud.recipe, .{txt.item(r.out).name, r.n});
    var x = colx + 44;
    for (r.in, 0..) |ing, j| {
      const have = g.player.inv.count(ing.item) >= ing.n;
      try d.grain(x + 6, y + 10, 9, 13, ing.item.info().col, if (have) 0.7 else 0, m.f(j) * 0.3);
      x = try d.print(x + 14, y + 5, s.text_fine, if (have) s.white else s.dim, txt.s.hud.ingredient, .{ing.n, txt.item(ing.item).short}) + 10;
    }
  }
}   