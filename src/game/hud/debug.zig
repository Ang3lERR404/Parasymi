//! F3: frame/sim timings and world counts.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const play = lib.play;
const Draw = lib.engine.ui.draw.Draw;
const s = lib.style;
const txt = lib.txt;
const m = lib.engine.core.math;

const margin = s.edge;
const bw:f32 = 364;
const line_h:f32 = 22;

pub fn visible(g:*const play.Game) bool { return g.debug; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, _:f32) Allocator.Error!void {
  const rs = g.render_stats;
  const bx = W - bw - margin;
  const lines = 7;
  const bh = line_h * m.f(lines) + 28;
  try d.trellis(bx, 14, bw, bh, s.card, 0.85);
  var y:f32 = 28;
  _ = try d.print(bx + 18, y, s.text_label, s.white, txt.s.hud.fps, .{m.MS_PER_S / @max(g.frame_ms, 0.01), g.frame_ms});
  y += line_h;
  _ = try d.print(bx + 18, y, s.text_label, s.white, txt.s.hud.gpu, .{rs.gpu_ms});
  y += line_h;
  _ = try d.print(bx + 18, y, s.text_label, s.white, txt.s.hud.sim, .{g.sim_ms, g.ticks});
  y += line_h;
  _ = try d.print(bx + 18, y, s.text_label, s.white, txt.s.hud.counts, .{g.world.map.count(), g.plants.len(), g.structs.list.items.len});
  y += line_h;
  _ = try d.print(bx + 18, y, s.text_label, s.white, txt.s.hud.draws, .{rs.instances, rs.parts, rs.draws});
  y += line_h;
  _ = try d.print(bx + 18, y, s.text_label, s.white, txt.s.hud.pos, .{g.player.pos[0], g.player.pos[2], g.sky.tod});
  y += line_h;
  _ = try d.print(bx + 18, y, s.text_label, s.dim, txt.s.hud.motes, .{g.stars.motes.items.len, rs.meshed});
}