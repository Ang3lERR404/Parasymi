//! the options panel (pause menu, OPTIONS): the world stays frozen behind
//! the veil. Each setting is a row, its value held between two leaves; a
//! click turns it on, the other button turns it back. BACK (or Esc) returns
//! to the pause menu.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const play = @import("../play.zig");
const opt = @import("../options.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("../style.zig");
const txt = @import("../text.zig");

const pw:f32 = 620;
const header_h:f32 = 104;
const row_h:f32 = 50;
const back_h:f32 = 56;
const hint_h:f32 = 40;
const pad_x:f32 = 64;
/// the value's centre, from the panel's right edge
const value_x:f32 = 150;
/// the leaves either side of the value: from its centre, length and width
const leaf_off:f32 = 84;
const leaf_len:f32 = 20;
const leaf_w:f32 = 12;
const settings = std.meta.fields(opt.Setting).len;

pub fn visible(g:*const play.Game) bool { return g.mode == .options; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  try d.glow(W / 2, H / 2, @max(W, H) * 0.75, s.veil);
  const labels = txt.s.hud.option_labels;
  const ph = header_h + row_h * m.f(settings) + back_h + hint_h;
  const px = (W - pw) / 2;
  const py = (H - ph) / 2;
  const t = g.uiT();
  try d.membrane(px, py, pw, ph, s.pause_panel, 0.71);
  g.rows.add(px, py, pw, ph, .panel);
  const title = txt.s.hud.options_title;
  _ = try d.text(W / 2 - Draw.width(title, s.text_banner) / 2, py + 30, s.text_banner, s.gold, title);

  for (0..settings) |i| {
    const set:opt.Setting = @enumFromInt(i);
    const y = py + header_h + row_h * m.f(i);
    const mid = y + 8;
    const over = g.points(.{.option = set});
    if (over) try d.glow(px + pw / 2, mid, pw * 0.45, s.menu_hover);
    _ = try d.text(px + pad_x, y, s.text_label, if (over) s.gold else s.white, txt.nth(labels, i));
    const val = opt.shown(&g.opts, set);
    const vx = px + pw - value_x;
    _ = try d.text(vx - Draw.width(val, s.text_label) / 2, y, s.text_label, s.gold, val);
    // leaves pointing either way, swaying a little, opening under the mouse
    const open:f32 = if (over) 1 else 0.6;
    const sway = 0.08 * @sin(t * 2 + m.f(i));
    try d.leaf(.{vx - leaf_off, mid}, m.pi + sway, leaf_len, leaf_w, s.leaf, open, m.f(i) * 0.3);
    try d.leaf(.{vx + leaf_off, mid}, -sway, leaf_len, leaf_w, s.leaf, open, m.f(i) * 0.3 + 0.5);
    g.rows.add(px + pad_x / 2, y - row_h / 2 + 8, pw - pad_x, row_h, .{.option = set});
  }

  const by = py + header_h + row_h * m.f(settings) + 14;
  const back = txt.s.hud.options_back;
  const over = g.points(.back);
  if (over) try d.glow(W / 2, by + 8, pw * 0.25, s.menu_hover);
  try d.pod(W / 2 - Draw.width(back, s.text_label) / 2 - 26, by + 8, 9, s.gold, if (over) 1 else 0.5, 0.2);
  _ = try d.text(W / 2 - Draw.width(back, s.text_label) / 2, by, s.text_label, if (over) s.gold else s.white, back);
  g.rows.add(W / 2 - pw / 4, by - back_h / 2 + 8, pw / 2, back_h, .back);

  const hint = txt.s.hud.options_hint;
  _ = try d.text(W / 2 - Draw.width(hint, s.text_fine) / 2, py + ph - hint_h + 4, s.text_fine, s.dim, hint);
}
