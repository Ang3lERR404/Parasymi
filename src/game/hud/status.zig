//! time of day (a sun or moon pod) and how full the wolf's sap belly is.
const play = @import("../play.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("style.zig");

pub fn draw(g:*play.Game, d:*Draw, _:f32, _:f32) !void {
  try d.membrane(16, 14, 300, 74, s.skin, 0.1);
  const day = g.sky.daylight();
  const orb = if (day > 0.5) [4]u8{255, 210, 120, 255} else [4]u8{170, 190, 255, 255};
  try d.glow(52, 50, 30, .{orb[0], orb[1], orb[2], 90});
  try d.pod(52, 50, 17, orb, 0.4 + 0.6 * (if (day > 0.5) day else 1 - day), 0.3);
  _ = try d.text(84, 30, 2, s.white, g.sky.name());
  _ = try d.text(84, 56, 1.5, s.dim, "SAP");
  try d.tendril(118, 52, 180, 14, .{255, 190, 90, 255}, g.player.inv.fill(), 0.2);
}
