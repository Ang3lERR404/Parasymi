//! the pause menu (Esc): the world holds its breath behind a soft veil.
//! Each row is clicked (or its key pressed) to do what it says.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const fields = std.meta.fields;
const m = lib.engine.core.math;
const play = lib.play;
const Draw = lib.engine.ui.draw.Draw;
const s = lib.style;
const txt = lib.txt;

const pw:f32 = 480;
const header_h:f32 = 100;
const option_h:f32 = 44;
const pad_bottom:f32 = 30;
const pod_x:f32 = 90;
const key_x:f32 = 112;
const label_x:f32 = 190;
/// a row's clickable band, from this far left of its pod
const row_inset:f32 = 50;
const rows = fields(play.PauseRow).len;

pub fn visible(g:*const play.Game) bool { return g.mode == .paused; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  try d.glow(W / 2, H / 2, @max(W, H) * s.veil_reach, s.veil);
  const keys = txt.s.hud.pause_keys;
  const labels = txt.s.hud.pause_labels;
  // one label and key per row (the strings test checks the counts)
  const n = rows;
  const ph = header_h + option_h * m.f(n) + pad_bottom;
  const px = (W - pw) / 2;
  const py = (H - ph) / 2;
  try d.membrane(px, py, pw, ph, s.pause_panel, 0.55);
  g.rows.add(px, py, pw, ph, .panel);
  const title = txt.s.hud.paused;
  _ = try d.text(W / 2 - Draw.width(title, s.text_banner) / 2, py + s.title_y, s.text_banner, s.gold, title);
  for (0..n) |i| {
    const y = py + header_h + option_h * m.f(i);
    const row:play.PauseRow = @enumFromInt(i);
    const over = g.points(.{.pause = row});
    if (over) try d.glow(px + pw / 2, y + 8, pw * 0.42, s.menu_hover);
    try d.pod(px + pod_x, y + 8, 9, s.gold, if (over) 1 else 0.5, m.f(i) * 0.4);
    _ = try d.text(px + key_x, y, s.text_label, s.dim, txt.nth(keys, i));
    _ = try d.text(px + label_x, y, s.text_label, if (over) s.gold else s.white, txt.nth(labels, i));
    g.rows.add(px + pod_x - row_inset, y - option_h / 2 + 8, pw - 2 * (pod_x - row_inset), option_h, .{.pause = row});
  }
}
