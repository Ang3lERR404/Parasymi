//! F3: frame/sim timings and world counts.
const std = @import("std");
const Allocator = std.mem.Allocator;
const play = @import("../play.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("../style.zig");
const m = @import("../../core/math.zig");

const margin = s.edge;
const bw:f32 = 364;
const line_h:f32 = 22;

pub fn visible(g:*const play.Game) bool { return g.debug; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, _:f32) Allocator.Error!void {
  const rs = g.render_stats;
  const bx = W - bw - margin;
  const lines = 6;
  const bh = line_h * m.f(lines) + 28;
  try d.membrane(bx, 14, bw, bh, s.skin, 0.8);
  var y:f32 = 28;
  _ = try d.print(bx + 18, y, s.text_label, s.white, "FPS {d:.0}  {d:.2} MS", .{m.MS_PER_S / @max(g.frame_ms, 0.01), g.frame_ms});
  y += line_h;
  _ = try d.print(bx + 18, y, s.text_label, s.white, "SIM {d:.3} MS  TICK {d}", .{g.sim_ms, g.ticks});
  y += line_h;
  _ = try d.print(bx + 18, y, s.text_label, s.white, "CHUNKS {d}  PLANTS {d}  BUILT {d}", .{g.world.map.count(), g.plants.len(), g.structs.list.items.len});
  y += line_h;
  _ = try d.print(bx + 18, y, s.text_label, s.white, "INST {d}  PARTS {d}  DRAWS {d}", .{rs.instances, rs.parts, rs.draws});
  y += line_h;
  _ = try d.print(bx + 18, y, s.text_label, s.white, "POS {d:.0},{d:.0}  TOD {d:.2}", .{g.player.pos[0], g.player.pos[2], g.sky.tod});
  y += line_h;
  _ = try d.print(bx + 18, y, s.text_label, s.dim, "MOTES {d}  MESHED {d}", .{g.stars.motes.items.len, rs.meshed});
}