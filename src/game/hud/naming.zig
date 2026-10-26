//! the name prompt: the garden being saved is given a name (saving a fresh
//! one from the saved gardens, or the save key before it has one). The
//! name grows along a young stem as it is typed, a bud blinking where the
//! next letter goes; OK saves (over a garden of that name only when clicked
//! twice), CANCEL (or Esc) returns to where it was asked.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const m = lib.engine.core.math;
const play = lib.play;
const Draw = lib.engine.ui.draw.Draw;
const s = lib.style;
const txt = lib.txt;
const gardens = lib.hud.panels.gardens;

const pw:f32 = 560;
const ph:f32 = 260;
const field_y:f32 = 112;
const field_pad:f32 = 56;
const acts_y:f32 = 190;
/// the bud where the next letter goes blinks this often (1/s)
const blink:f32 = 2.2;

pub fn visible(g:*const play.Game) bool { return g.mode == .naming; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  try d.glow(W / 2, H / 2, @max(W, H) * s.veil_reach, s.veil);
  const px = (W - pw) / 2;
  const py = (H - ph) / 2;
  const t = g.uiT();
  try d.trellis(px, py, pw, ph, s.pause_panel, 0.61);
  g.rows.add(px, py, pw, ph, .panel);
  const title = txt.s.hud.naming_title;
  _ = try d.text(W / 2 - Draw.width(title, s.text_title) / 2, py + s.title_y, s.text_title, s.gold, title);

  // the name on its stem, the bud after its last letter
  const name = g.typed.slice();
  const fy = py + field_y;
  const x0 = px + field_pad;
  const x1 = px + pw - field_pad;
  const sway = 1.5 * @sin(t * 1.3);
  try d.limb(.{x0, fy + 14 + sway}, .{x1, fy + 14 - sway}, 2.5, 1.5, s.bark_young, 0);
  const nx = W / 2 - Draw.width(name, s.text_heading) / 2;
  const end = try d.text(nx, fy - 8, s.text_heading, s.white, name);
  const open = 0.5 + 0.5 * @sin(t * blink * m.tau);
  try d.leaf(.{end + 6, fy + 12}, -m.half_pi, 18, 8, s.leaf, open, 0.2);

  // OK only for a name that can be one; asking first over a taken one
  const by = py + acts_y;
  const ok = g.typed.typed() != null;
  const ok_label = if (g.overwrite) txt.s.hud.gardens_overwrite else txt.s.hud.naming_ok;
  try gardens.button(g, d, px + pw * 0.32, by, ok_label, .{.garden_act = .ok}, ok, if (g.overwrite) 0.5 + 0.5 * @sin(t * 6) else 0);
  try gardens.button(g, d, px + pw * 0.7, by, txt.s.hud.naming_cancel, .{.garden_act = .cancel}, true, 0);

  const hint = txt.s.hud.naming_hint;
  _ = try d.text(W / 2 - Draw.width(hint, s.text_fine) / 2, py + ph - 36, s.text_fine, s.dim, hint);
}
