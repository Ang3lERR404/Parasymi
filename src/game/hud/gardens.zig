//! the saved gardens (pause menu): the world stays frozen behind the veil.
//! A fresh garden heads the list, then every saved one, the most recent
//! first; the list scrolls (wheel, or drag its stem) past what fits. A
//! click chooses one; SAVE writes the garden as it (a fresh one asks its
//! name, a saved one is saved over only when clicked twice), LOAD returns
//! to it, the chosen one's small DELETE lets it go (clicked twice). BACK
//! (or Esc) returns to the pause menu.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const m = lib.engine.core.math;
const play = lib.play;
const save = lib.save;
const Draw = lib.engine.ui.draw.Draw;
const Color = lib.engine.ui.draw.Color;
const s = lib.style;
const hud = lib.hud;
const txt = lib.txt;
const Input = lib.engine.platform.input.Input;

const pw:f32 = 680;
const header_h:f32 = 104;
const row_h:f32 = 46;
const list_h:f32 = row_h * play.GARDENS_SHOWN;
const acts_h:f32 = 64;
const hint_h:f32 = 40;
const pad_x:f32 = 64;
const pod_r:f32 = 9;
const chosen_glow:f32 = 34;
/// a row's text, from its pod
const text_x:f32 = 26;
/// the scroll stem, from the panel's right edge, and its clickable width
const stem_x:f32 = 34;
const stem_w:f32 = 28;
/// rows fade out over this much of a row past the list's ends
const fade_rows:f32 = 0.5;
const seconds_per = [_]i64{ 60, 3600, 86400 };

pub fn visible(g:*const play.Game) bool { return g.mode == .gardens; }

/// a garden's row (0: a fresh one), a button (the name prompt's too), BACK,
/// the scroll stem
pub const Pick = union(enum) { garden:usize, act:play.GardenAct, back, scroll };

/// a click chooses a garden, presses a button, returns to the pause menu,
/// or takes hold of the stem (dragged while held)
pub fn click(g:*play.Game, p:Pick, press:hud.Press, _:*const Input) void {
  if (press != .use) return;
  switch (p) {
    .garden => |i| if (i != g.garden) {
      g.garden = i;
      g.overwrite = false;
      g.deleting = false;
    },
    .act => |a| g.gardenAct(a),
    .back => g.mode = .paused,
    .scroll => g.scrolling = true,
  }
}

/// `c` with its alpha scaled by `a`
pub fn faded(c:Color, a:f32) Color {
  return .{ c[0], c[1], c[2], @intFromFloat(m.f(c[3]) * m.clamp01(a)) };
}

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  try d.glow(W / 2, H / 2, @max(W, H) * s.veil_reach, s.veil);
  const ph = header_h + list_h + acts_h + hint_h;
  const px = (W - pw) / 2;
  const py = (H - ph) / 2;
  const t = g.uiT();
  try d.trellis(px, py, pw, ph, s.pause_panel, 0.83);
  g.rows.add(.{.x = px, .y = py, .w = pw, .h = ph}, .panel);
  const title = txt.s.hud.gardens_title;
  _ = try d.text(W / 2 - Draw.width(title, s.text_banner) / 2, py + s.title_y, s.text_banner, s.gold, title);

  // the list, scrolled to `garden_at`; rows fade in and out at its ends
  const top = py + header_h - 12;
  const n = g.gardens.items.len + 1;
  const last = m.f(play.GARDENS_SHOWN - 1);
  for (0..n) |i| {
    const pos = m.f(i) - g.garden_at;
    const a = 1 - @max(-pos, pos - last, 0) / fade_rows;
    if (a <= 0) continue;
    const mid = top + row_h * (pos + 0.5);
    // (under the chosen row's DELETE, added as it is drawn)
    if (a > 0.5) {
      const y0 = @max(mid - row_h / 2, top);
      const y1 = @min(mid + row_h / 2, top + list_h);
      g.rows.add(.{.x = px + pad_x / 2, .y = y0, .w = pw - pad_x - stem_w, .h = y1 - y0}, hud.row(.gardens, .{.garden = i}));
    }
    try row(g, d, i, px, mid, a, t);
  }
  try stem(g, d, px + pw - stem_x, top, t);

  // the buttons: SAVE (asking first before saving over a garden), LOAD, BACK
  const by = top + list_h + acts_h / 2;
  const saved = g.garden > 0;
  const save_label = if (g.overwrite) txt.s.hud.gardens_overwrite else txt.s.hud.gardens_save;
  try button(g, d, px + pw * 0.22, by, save_label, hud.row(.gardens, .{.act = .save}), true, if (g.overwrite) 0.5 + 0.5 * @sin(t * 6) else 0);
  try button(g, d, px + pw * 0.55, by, txt.s.hud.gardens_load, hud.row(.gardens, .{.act = .load}), saved, 0);
  try button(g, d, px + pw * 0.82, by, txt.s.hud.options_back, hud.row(.gardens, .back), true, 0);

  const hint = txt.s.hud.gardens_hint;
  _ = try d.text(W / 2 - Draw.width(hint, s.text_fine) / 2, py + ph - hint_h + 4, s.text_fine, s.dim, hint);
}

/// row `i` (0: a fresh garden) centred at `mid`, at opacity `a`
fn row(g:*play.Game, d:*Draw, i:usize, px:f32, mid:f32, a:f32, t:f32) Allocator.Error!void {
  const chosen = g.garden == i;
  const over = g.points(hud.row(.gardens, .{.garden = i}));
  const x = px + pad_x;
  if (over) try d.glow(px + pw / 2, mid, pw * 0.3, faded(s.menu_hover, a));
  // the chosen one: its pod glows and a tendril runs under it
  if (chosen) {
    try d.glow(x, mid, chosen_glow, faded(s.research_active, a));
    try d.limb(.{x + text_x - 4, mid + 14}, .{px + pw - stem_w - pad_x / 2, mid + 14 + 2 * @sin(t)}, 2, 0.8, faded(s.leaf, a), 0);
  }
  const lit:f32 = if (chosen) 1 else if (over) 0.8 else 0.4;
  const label_col = faded(if (chosen or over) s.gold else s.white, a);
  if (i == 0) {
    // a fresh garden: a sprout from its pod
    try d.pod(x, mid, pod_r, faded(s.leaf, a), lit, 0.1);
    try d.leaf(.{x, mid - pod_r * 0.5}, -m.half_pi + 0.15 * @sin(t * 2), 16, 9, faded(s.leaf, a), if (chosen or over) 1 else 0.6, 0.3);
    _ = try d.text(x + text_x, mid - 8, s.text_label, label_col, txt.s.hud.gardens_fresh);
    return;
  }
  const e = &g.gardens.items[i - 1];
  try d.grain(x, mid, pod_r * 1.5, pod_r * 2.1, faded(s.gold, a), lit, m.f(i) * 0.4);
  const name = if (e.name.is(save.AUTO)) txt.s.hud.gardens_auto else e.name.slice();
  const end = try d.text(x + text_x, mid - 8, s.text_label, label_col, name);
  if (g.slot) |sl| if (sl.is(e.name.slice())) {
    _ = try d.text(end + 14, mid - 6, s.text_note, faded(s.growth, a), txt.s.hud.gardens_playing);
  };
  // how long ago, right-aligned before the scroll stem (the chosen one's
  // DELETE before it)
  var age_buf:[64]u8 = undefined;
  const age = ago(&age_buf, e.age + @as(i64, @intFromFloat(g.ui_time - g.listed_at)));
  const ax = px + pw - stem_w - pad_x / 2 - Draw.width(age, s.text_note) - 12;
  _ = try d.text(ax, mid - 6, s.text_note, faded(s.dim, a), age);
  if (chosen and a > 0.5) {
    const label = if (g.deleting) txt.s.hud.gardens_delete_sure else txt.s.hud.gardens_delete;
    try small(g, d, ax - 24 - Draw.width(label, s.text_note) / 2, mid, label, if (g.deleting) 0.5 + 0.5 * @sin(t * 6) else 0);
  }
}

/// the chosen garden's DELETE: a small button centred on (cx, mid), its
/// glow pulsing with `call` (asking)
fn small(g:*play.Game, d:*Draw, cx:f32, mid:f32, label:[]const u8, call:f32) Allocator.Error!void {
  const p:hud.Pick = hud.row(.gardens, .{.act = .delete});
  const over = g.points(p);
  const w = Draw.width(label, s.text_note);
  if (over or call > 0) try d.glow(cx, mid, w * 0.7 + 16, faded(s.menu_hover, if (over) 1 else call * 2));
  try hud.bullet(d, cx - w / 2 - 12, mid, pod_r * 0.6, s.bud, if (over) 1 else 0.15, cx * 0.01);
  _ = try d.text(cx - w / 2, mid - 6, s.text_note, if (over or call > 0) s.gold else s.dim, label);
  g.rows.add(.{.x = cx - w / 2 - 22, .y = mid - row_h / 2 + 6, .w = w + 30, .h = row_h - 12}, p);
}

/// `secs` as shown: just now, minutes, hours or days ago
fn ago(buf:[]u8, secs:i64) []const u8 {
  const list = txt.s.hud.gardens_age;
  if (secs < seconds_per[0]) return txt.nth(list, 0);
  var k:usize = seconds_per.len - 1;
  while (secs < seconds_per[k]) k -= 1;
  return txt.bufRender(buf, txt.nth(list, k + 1), .{@divFloor(secs, seconds_per[k])});
}

/// the list's scroll stem down the right side, a bud riding it where the
/// list is; only there while the list runs past what fits
fn stem(g:*play.Game, d:*Draw, x:f32, top:f32, t:f32) Allocator.Error!void {
  const most = m.f((g.gardens.items.len + 1) -| play.GARDENS_SHOWN);
  if (most <= 0) return;
  const over = g.points(hud.row(.gardens, .scroll)) or g.scrolling;
  const sway = 1.5 * @sin(t * 1.3);
  try d.limb(.{x + sway, top + 4}, .{x - sway, top + list_h - 4}, 3, 2, s.bark_young, 0);
  const y = top + 12 + (list_h - 24) * m.clamp01(g.garden_at / most);
  try d.grain(x, y, 14, 22, if (over) s.gold else s.bud, if (over) 0.4 else 0.1, t * 0.2);
  g.rows.add(.{.x = x - stem_w / 2, .y = top, .w = stem_w, .h = list_h}, hud.row(.gardens, .scroll));
}

/// a button: a pod and its label centred on (cx, mid); dim when it would
/// do nothing; `call` pulses its glow (asking)
pub fn button(g:*play.Game, d:*Draw, cx:f32, mid:f32, label:[]const u8, p:hud.Pick, live:bool, call:f32) Allocator.Error!void {
  const over = live and g.points(p);
  const w = Draw.width(label, s.text_label);
  if (over or call > 0) try d.glow(cx, mid, w * 0.8 + 30, faded(s.menu_hover, if (over) 1 else call * 2));
  const col = if (!live) s.unknown else if (over or call > 0) s.gold else s.white;
  try hud.bullet(d, cx - w / 2 - 22, mid, pod_r, if (live) s.gold else s.unknown, if (over) 1 else 0.15, cx * 0.01);
  _ = try d.text(cx - w / 2, mid - 8, s.text_label, col, label);
  g.rows.add(.{.x = cx - w / 2 - 40, .y = mid - acts_h / 2 + 6, .w = w + 60, .h = acts_h - 12}, p);
}
