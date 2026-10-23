//! what is under the cursor: a structure (its own description and contents),
//! or the tile with its resource node and any plant growing there.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ck = @import("../../world/chunk.zig");
const species = @import("../../sim/species.zig");
const play = @import("../play.zig");
const st = @import("../structures.zig");
const resources = @import("../resources.zig");
const Draw = @import("../../ui/draw.zig").Draw;
const s = @import("../style.zig");
const m = @import("../../core/math.zig");

const panel_x:f32 = 16;
const panel_y:f32 = 104;
const text_x:f32 = 32;
const text_top:f32 = 116;
const line_h:f32 = 24;
const inv_cols:usize = 8;
const inv_gap:f32 = 44;

pub fn visible(g:*const play.Game) bool { return g.hover != null; }

pub fn draw(g:*play.Game, d:*Draw, _:f32, _:f32) Allocator.Error!void {
  const h = g.hover.?;
  const c = g.world.chunkOfTile(h[0], h[1]) orelse return;
  const near = g.player.inReach(h[0], h[1]);
  if (g.structs.at(&g.world, h[0], h[1])) |j| return structure(g, d, g.structs.get(j), near);
  return tile(g, d, c, ck.localIndex(h[0], h[1]), h, near);
}

fn structure(g:*play.Game, d:*Draw, sp:*const st.Structure, near:bool) Allocator.Error!void {
  const inv_rows = @max((sp.inv.used() + inv_cols - 1) / inv_cols, 1);
  const ph = 60 + 14 + inv_gap * m.f(inv_rows) + 16;
  try d.membrane(panel_x, panel_y, 400, ph, s.skin, 0.6);
  _ = try d.text(text_x, text_top, 1.75, s.gold, sp.def().name);
  if (!near) _ = try d.text(text_x + 290, text_top, 1.25, s.dim, "TOO FAR");
  try st.describe(sp, d, &g.prog, text_x, text_top + 26);
  const y = text_top + 60;
  var k:usize = 0;
  for (sp.inv.slot) |slot| if (slot) |it| {
    const px = text_x + 16 + inv_gap * m.f(k % inv_cols);
    const py = y + 14 + inv_gap * m.f(k / inv_cols);
    try d.pod(px, py, 16, it.item.info().col, 0.6, m.f(k) * 0.2);
    _ = try d.print(px - 8, py - 6, 1.2, s.dark, "{d}", .{it.n});
    k += 1;
  };
  if (k == 0) _ = try d.text(text_x, y + 6, 1.25, s.dim, "EMPTY");
}

fn tile(g:*play.Game, d:*Draw, c:*ck.Chunk, t:usize, h:[2]i32, near:bool) Allocator.Error!void {
  const pi = g.plants.at(&g.world, h[0], h[1]);
  const ph:f32 = if (pi != null) 112 else 60;
  try d.membrane(panel_x, panel_y, 360, ph, s.skin, 0.6);
  if (c.res[t] > 0 and c.occ[t] == .none) {
    const item = resources.of(c.kind[t]).?.item;
    _ = try d.print(text_x, text_top, 1.75, item.info().col, "{s} X{d}", .{item.info().name, c.res[t]});
  } else {
    _ = try d.print(text_x, text_top, 1.75, s.white, "{s}  LEY {d:.1}", .{@tagName(c.kind[t]), c.ley_cap[t]});
  }
  if (!near) _ = try d.text(text_x + 248, text_top + 2, 1.25, s.dim, "TOO FAR");
  const i = pi orelse return;
  const p = g.plants.list.get(i.idx());
  const def = species.get(p.sp);
  var y = text_top + 26;
  _ = try d.text(text_x, y, 1.75, s.white, def.name);
  y += line_h;
  try d.tendril(text_x, y, 150, 12, s.growth, p.growth, 0.5);
  if (def.stages) |names| {
    const k = def.stage(p.growth);
    _ = try d.print(text_x + 164, y - 4, 1.25, s.dim, "{s} {d}/{d}  {d:.0}%", .{names[k], k + 1, names.len, p.growth * 100});
  } else {
    _ = try d.print(text_x + 164, y - 4, 1.25, s.dim, "GROWTH {d:.0}%", .{p.growth * 100});
  }
  y += 22;
  const yields = if (g.prog.yieldKnown(p.sp)) def.yields.info().short else "??";
  _ = try d.print(text_x, y, 1.4, s.gold, "{s} {d:.1}  SEEDS {d}  HP {d:.0}%", .{yields, p.essence, m.floorTo(u32, p.seeds), p.health * 100});
}