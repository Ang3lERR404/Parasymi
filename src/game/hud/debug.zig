//! F3: frame/sim timings and world counts.
const std = @import("std");
const Allocator = std.mem.Allocator;
const play = @import("../play.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("style.zig");

pub fn visible(g:*const play.Game) bool { return g.debug; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, _:f32) Allocator.Error!void {
  const rs = g.render_stats;
  const bx = W - 380;
  try d.membrane(bx, 14, 364, 150, s.skin, 0.8);
  _ = try d.print(bx + 18, 28, 1.75, s.white, "FPS {d:.0}  {d:.2} MS", .{1000 / @max(g.frame_ms, 0.01), g.frame_ms});
  _ = try d.print(bx + 18, 50, 1.75, s.white, "SIM {d:.3} MS  TICK {d}", .{g.sim_ms, g.ticks});
  _ = try d.print(bx + 18, 72, 1.75, s.white, "CHUNKS {d}  PLANTS {d}  BUILT {d}", .{g.world.map.count(), g.plants.len(), g.structs.list.items.len});
  _ = try d.print(bx + 18, 94, 1.75, s.white, "INST {d}  PARTS {d}  DRAWS {d}", .{rs.instances, rs.parts, rs.draws});
  _ = try d.print(bx + 18, 116, 1.75, s.white, "POS {d:.0},{d:.0}  TOD {d:.2}", .{g.player.pos[0], g.player.pos[2], g.sky.tod});
  _ = try d.print(bx + 18, 138, 1.75, s.dim, "MOTES {d}  MESHED {d}", .{g.stars.motes.items.len, rs.meshed});
}
