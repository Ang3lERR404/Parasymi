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
const hud = lib.hud;
const txt = lib.txt;
const Input = lib.engine.platform.input.Input;

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

/// a row of the menu
pub const Pick = union(enum) { row:play.PauseRow };

/// a click does what the row says
pub fn click(g:*play.Game, p:Pick, press:hud.Press, _:*const Input) void {
  if (press == .use) switch (p) { .row => |r| g.choose(r) };
}

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  try d.glow(W / 2, H / 2, @max(W, H) * s.veil_reach, s.veil);
  const keys = txt.s.hud.pause_keys;
  const labels = txt.s.hud.pause_labels;
  // one label and key per row (the strings test checks the counts)
  const n = rows;
  const ph = header_h + option_h * m.f(n) + pad_bottom;
  const px = (W - pw) / 2;
  const py = (H - ph) / 2;
  try d.trellis(px, py, pw, ph, s.pause_panel, 0.55);
  g.rows.add(.{.x = px, .y = py, .w = pw, .h = ph}, .panel);
  const title = txt.s.hud.paused;
  _ = try d.text(W / 2 - Draw.width(title, s.text_banner) / 2, py + s.title_y, s.text_banner, s.gold, title);
  for (0..n) |i| {
    const y = py + header_h + option_h * m.f(i);
    const row:play.PauseRow = @enumFromInt(i);
    const over = g.points(hud.row(.pause, .{.row = row}));
    if (over) try d.glow(px + pw / 2, y + 8, pw * 0.42, s.menu_hover);
    try hud.bullet(d, px + pod_x, y + 8, 9, s.gold, if (over) 1 else 0.15, m.f(i) * 0.4);
    _ = try d.text(px + key_x, y, s.text_label, s.dim, txt.nth(keys, i));
    _ = try d.text(px + label_x, y, s.text_label, if (over) s.gold else s.white, txt.nth(labels, i));
    g.rows.add(.{.x = px + pod_x - row_inset, .y = y - option_h / 2 + 8, .w = pw - 2 * (pod_x - row_inset), .h = option_h}, hud.row(.pause, .{.row = row}));
  }
}
