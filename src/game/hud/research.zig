//! the research tree (T): every technology with its per-unit ingredients,
//! units, status and a tendril of progress; 1-n chooses what blooms study.
const play = @import("../play.zig");
const prog = @import("../progression.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("style.zig");
const m = @import("../../core/math.zig");

const pw:f32 = 720;

pub fn visible(g:*const play.Game) bool { return g.show_research; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) !void {
  const n = m.f(prog.tree.values.len);
  const ph = 100 + 70 * n;
  const px = W - pw - 24;
  const py = @max(10, (H - ph) / 2 - 30);
  try d.membrane(px, py, pw, ph, .{26, 18, 44, 225}, 0.77);
  _ = try d.text(px + 72, py + 30, 2.5, s.gold, "RESEARCH");
  _ = try d.text(px + 72, py + 58, 1.2, s.dim, "RESEARCH BLOOMS STUDY WHAT IS CHOSEN, EATING WHAT THEY ARE FED. NUMBER KEYS CHOOSE");
  for (prog.tree.values, 0..) |r, i| {
    const id:prog.Id = @enumFromInt(i);
    const status = g.prog.status(id);
    const y = py + 80 + 70 * m.f(i);
    const cur = g.prog.current == id;
    const col = switch (status) { .done => [4]u8{140, 230, 170, 255}, .open => s.white, .locked => [4]u8{105, 105, 120, 255} };
    if (cur) try d.glow(px + 40, y + 8, 22, .{255, 210, 130, 120});
    _ = try d.print(px + 46, y, 1.6, if (cur) s.gold else col, "{d} {s}", .{i + 1, r.name});
    _ = try d.text(px + 70, y + 20, 1.15, s.dim, r.desc);
    var x = px + 70;
    for (r.per_unit) |ing| {
      try d.pod(x + 6, y + 42, 6, ing.item.info().col, 0.6, x * 0.01);
      x = try d.print(x + 14, y + 37, 1.15, s.dim, "{d}{s}", .{ing.n, ing.item.info().short}) + 10;
    }
    _ = try d.print(x + 8, y + 37, 1.15, s.dim, "X{d}  {d:.0}S", .{r.units, r.unit_time});
    const done = g.prog.progress.get(id);
    const frac = if (status == .done) 1 else m.ratio(done, r.units);
    try d.tendril(px + pw - 200, y + 10, 170, 12, col, frac, m.f(i) * 0.21);
  }
}
