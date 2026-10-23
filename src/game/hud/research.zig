//! the research tree (T): every technology with its per-unit ingredients,
//! units, status and a tendril of progress; 1-n chooses what blooms study.
const std = @import("std");
const Allocator = std.mem.Allocator;
const play = @import("../play.zig");
const prog = @import("../progression.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("../style.zig");
const m = @import("../../core/math.zig");

const pw:f32 = 720;
const margin:f32 = 24;
const panel_lift:f32 = 30;
const header_h:f32 = 80;
const row_h:f32 = 70;
const pad_bottom:f32 = 20;
const tendril_w:f32 = 170;
const tendril_h:f32 = 12;
const tendril_right:f32 = 200; // distance from panel right edge

pub fn visible(g:*const play.Game) bool { return g.mode == .research; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  const n = m.f(prog.tree.values.len);
  const ph = header_h + row_h * n + pad_bottom;
  const px = W - pw - margin;
  const py = @max(10, (H - ph) / 2 - panel_lift);
  try d.membrane(px, py, pw, ph, s.research_panel, 0.77);
  _ = try d.text(px + 72, py + 30, 2.5, s.gold, "RESEARCH");
  _ = try d.text(px + 72, py + 58, 1.2, s.dim, "RESEARCH BLOOMS STUDY WHAT IS CHOSEN, EATING WHAT THEY ARE FED. NUMBER KEYS CHOOSE");

  for (prog.tree.values, 0..) |r, i| {
    const id:prog.Id = @enumFromInt(i);
    const status = g.prog.status(id);
    const y = py + header_h + row_h * m.f(i);
    const cur = g.prog.current == id;
    const col = switch (status) {
      .done => s.research_done,
      .open => s.white,
      .locked => s.research_locked,
    };
    if (cur) try d.glow(px + 40, y + 8, 22, s.research_active);
    _ = try d.print(px + 46, y, 1.6, if (cur) s.gold else col, "{d} {s}", .{i + 1, r.name});
    _ = try d.text(px + 70, y + 20, 1.15, s.dim, r.desc);

    var x = px + 70;
    for (r.per_unit, 0..) |ing, j| {
      try d.pod(x + 6, y + 42, 6, ing.item.info().col, 0.6, m.f(j) * 0.3);
      x = try d.print(x + 14, y + 37, 1.15, s.dim, "{d}{s}", .{ing.n, ing.item.info().short}) + 10;
    }
    _ = try d.print(x + 8, y + 37, 1.15, s.dim, "X{d}  {d:.0}S", .{r.units, r.unit_time});

    const done = g.prog.progress.get(id);
    const frac = if (status == .done) 1 else m.ratio(done, r.units);
    try d.tendril(px + pw - tendril_right, y + 10, tendril_w, tendril_h, col, frac, m.f(i) * 0.21);
  }
}