//! time of day (a sun or moon pod) and how full the wolf's sap belly is.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const play = lib.play;
const Draw = lib.engine.ui.draw.Draw;
const s = lib.style;
const txt = lib.txt;

const panel_x = s.edge;
const panel_y:f32 = 14;
const panel_w:f32 = 300;
const panel_h:f32 = 74;
const orb_x:f32 = 52;
const orb_y:f32 = 50;
const orb_r:f32 = 17;
const glow_r:f32 = 30;
const glow_alpha:u8 = 90;

pub fn draw(g:*play.Game, d:*Draw, _:f32, _:f32) Allocator.Error!void {
  try d.trellis(panel_x, panel_y, panel_w, panel_h, s.card, 0.1);
  const day = g.sky.daylight();
  const orb = if (day > 0.5) s.sun else s.moon;
  const glow = [4]u8{ orb[0], orb[1], orb[2], glow_alpha };
  try d.glow(orb_x, orb_y, glow_r, glow);
  try d.pod(orb_x, orb_y, orb_r, orb, 0.4 + 0.6 * (if (day > 0.5) day else 1 - day), 0.3);
  _ = try d.text(orb_x + 32, 30, s.text_heading, s.white, g.sky.name());
  _ = try d.text(orb_x + 32, 56, s.text_sub, s.dim, txt.s.hud.sap);
  try d.tendril(118, 52, 180, s.bar_h_bold, s.sap, g.player.inv.fill(), 0.2);
}   