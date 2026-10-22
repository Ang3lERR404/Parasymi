//! the HUD, composed only from living shapes (ui/draw.zig): membranes for
//! panels, seed pods for slots, tendrils for progress, glows for focus.
const std = @import("std");
const m = @import("../core/math.zig");
const ck = @import("../world/chunk.zig");
const species = @import("../sim/species.zig");
const prog = @import("progression.zig");
const play = @import("play.zig");
const player_mod = @import("player.zig");
const craft = @import("craft.zig");
const Draw = @import("../ui/draw.zig").Draw;

const white = [4]u8{235, 240, 225, 255};
const dim = [4]u8{150, 170, 150, 255};
const gold = [4]u8{255, 215, 130, 255};
const skin = [4]u8{24, 40, 30, 215};
const unknown = [4]u8{70, 70, 80, 255};

pub fn build(g:*play.Game, screen:[2]f32) !void {
  const d = &g.ui;
  d.clear();
  const W = screen[0];
  const H = screen[1];

  // time of day + how full the wolf is
  try d.membrane(16, 14, 300, 74, skin, 0.1);
  const day = g.sky.daylight();
  const orb = if (day > 0.5) [4]u8{255, 210, 120, 255} else [4]u8{170, 190, 255, 255};
  try d.glow(52, 50, 30, .{orb[0], orb[1], orb[2], 90});
  try d.pod(52, 50, 17, orb, 0.4 + 0.6 * (if (day > 0.5) day else 1 - day), 0.3);
  _ = try d.text(84, 30, 2, white, g.sky.name());
  _ = try d.text(84, 56, 1.5, dim, "SAP");
  try d.tendril(118, 52, 180, 14, .{255, 190, 90, 255}, g.player.inv.fill(), 0.2);

  try hotbar(g, W, H);
  try hoverInfo(g);

  // gathering progress grows a tendril above the wolf's focus
  if (g.gather_t > 0) try d.tendril(W / 2 - 60, H / 2 - 120, 120, 14, gold, g.gather_t / play.GATHER_TIME, 0.9);

  if (g.show_inv) try inventory(g, W, H);
  if (g.show_research) try research(g, W, H);

  // messages, newest first, fading
  for (g.prog.log, 0..) |msg, i| {
    if (msg.len == 0 or msg.age > 12) continue;
    const a:u8 = @intFromFloat(255 * m.clamp01(1.5 - msg.age / 8));
    _ = try d.text(24, H - 160 - @as(f32, @floatFromInt(i)) * 22, 1.75, .{220, 210, 255, a}, msg.buf[0..msg.len]);
  }
  _ = try d.text(24, H - 22, 1.2, dim, "WASD MOVE  SHIFT RUN  Q/E TURN  LMB GATHER/PLACE  R ROTATE  F HARVEST/FEED  SHIFT+F TAKE  C RECIPE  RMB UPROOT  1-9 HOTBAR  TAB BELLY  T RESEARCH");

  if (g.debug) {
    const rs = g.render_stats;
    const bx = W - 380;
    try d.membrane(bx, 14, 364, 150, skin, 0.8);
    _ = try d.print(bx + 18, 28, 1.75, white, "FPS {d:.0}  {d:.2} MS", .{1000 / @max(g.frame_ms, 0.01), g.frame_ms});
    _ = try d.print(bx + 18, 50, 1.75, white, "SIM {d:.3} MS  TICK {d}", .{g.sim_ms, g.ticks});
    _ = try d.print(bx + 18, 72, 1.75, white, "CHUNKS {d}  PLANTS {d}  BUILT {d}", .{g.world.map.count(), g.plants.len(), g.structs.list.items.len});
    _ = try d.print(bx + 18, 94, 1.75, white, "INST {d}  PARTS {d}  DRAWS {d}", .{rs.instances, rs.parts, rs.draws});
    _ = try d.print(bx + 18, 116, 1.75, white, "POS {d:.0},{d:.0}  TOD {d:.2}", .{g.player.pos[0], g.player.pos[2], g.sky.tod});
    _ = try d.print(bx + 18, 138, 1.75, dim, "MOTES {d}  MESHED {d}", .{g.stars.motes.items.len, rs.meshed});
  }
}

fn hotbar(g:*play.Game, W:f32, H:f32) !void {
  const d = &g.ui;
  const n = play.hotbar.len;
  const gap:f32 = 64;
  const x0 = W / 2 - gap * @as(f32, @floatFromInt(n - 1)) / 2;
  const hy = H - 86;
  for (play.hotbar, 0..) |item, i| {
    const x = x0 + gap * @as(f32, @floatFromInt(i));
    const sel = i == g.hot;
    const col = if (play.known(g, item)) item.info().col else unknown;
    if (sel) try d.glow(x, hy, 40, .{col[0], col[1], col[2], 110});
    try d.pod(x, hy, if (sel) 24 else 20, col, if (sel) 1 else 0.25, @as(f32, @floatFromInt(i)) * 0.37);
    const cnt = g.player.inv.count(item);
    var buf:[8]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{cnt}) catch "";
    _ = try d.text(x - Draw.width(s, 1.75) / 2, hy - 7, 1.75, if (cnt > 0) white else dim, s);
    _ = try d.print(x - 4, hy + 28, 1.2, dim, "{d}", .{i + 1});
  }
  const item = play.hotbar[g.hot];
  var buf:[64]u8 = undefined;
  const label = if (!play.known(g, item)) "NOT YET UNDERSTOOD"
    else if (item == .conduit) std.fmt.bufPrint(&buf, "{s} FACING {s}", .{item.info().name, ([_][]const u8{"EAST", "SOUTH", "WEST", "NORTH"})[g.place_dir]}) catch item.info().name
    else item.info().name;
  _ = try d.text(W / 2 - Draw.width(label, 1.5) / 2, hy - 50, 1.5, gold, label);
}

fn hoverInfo(g:*play.Game) !void {
  const d = &g.ui;
  const h = g.hover orelse return;
  const c = g.world.chunkOfTile(h[0], h[1]) orelse return;
  const t = ck.localIndex(h[0], h[1]);
  const near = g.player.inReach(h[0], h[1]);
  const x:f32 = 32;
  var y:f32 = 116;

  if (g.structs.at(&g.world, h[0], h[1])) |j| {
    const s = &g.structs.list.items[j];
    try d.membrane(16, 104, 400, 150, skin, 0.6);
    _ = try d.text(x, y, 1.75, gold, s.def().name);
    y += 26;
    switch (s.kind) {
      .germinator => {
        const r = craft.hand[s.recipe];
        _ = try d.print(x, y, 1.4, white, "WEAVES {s} (C)", .{r.out.info().name});
        try d.tendril(x + 250, y + 2, 110, 12, gold, s.weave.progress(), 0.3);
      },
      .research_bloom => if (g.prog.current) |id| {
        const r = prog.tree.get(id);
        _ = try d.print(x, y, 1.4, white, "STUDIES {s}", .{r.name});
        try d.tendril(x + 250, y + 2, 110, 12, .{200, 160, 255, 255}, @as(f32, @floatFromInt(g.prog.progress.get(id))) / @as(f32, @floatFromInt(r.units)), 0.3);
      } else {
        _ = try d.text(x, y, 1.4, dim, "CHOOSE WHAT TO STUDY (T)");
      },
      .conduit => _ = try d.print(x, y, 1.4, white, "CARRIES {s}", .{if (s.held) |it| it.info().name else "NOTHING"}),
      .sap_cache => _ = try d.text(x, y, 1.4, dim, "HOLDS ANYTHING. FEED (F), TAKE (SHIFT+F)"),
    }
    y += 34;
    var k:usize = 0;
    for (s.inv.slot) |slot| if (slot) |it| {
      const px = x + 16 + 44 * @as(f32, @floatFromInt(k % 8));
      const py = y + 14 + 44 * @as(f32, @floatFromInt(k / 8));
      try d.pod(px, py, 16, it.item.info().col, 0.6, @as(f32, @floatFromInt(k)) * 0.2);
      _ = try d.print(px - 8, py - 6, 1.2, .{20, 20, 20, 255}, "{d}", .{it.n});
      k += 1;
    };
    if (k == 0) _ = try d.text(x, y + 6, 1.25, dim, "EMPTY");
    if (!near) _ = try d.text(x + 290, 116, 1.25, dim, "TOO FAR");
    return;
  }

  const pi = g.plants.at(&g.world, h[0], h[1]);
  try d.membrane(16, 104, 360, if (pi != null) 112 else 60, skin, 0.6);
  if (c.res[t] > 0 and c.occ[t] == ck.NONE) {
    const item = play.kindItem(c.kind[t]).?;
    _ = try d.print(x, y, 1.75, item.info().col, "{s} X{d}", .{item.info().name, c.res[t]});
  } else {
    _ = try d.print(x, y, 1.75, white, "{s}  LEY {d:.1}", .{@tagName(c.kind[t]), c.ley_cap[t]});
  }
  if (!near) _ = try d.text(x + 250, y + 24, 1.25, dim, "TOO FAR");
  y += 26;
  if (pi) |i| {
    const p = g.plants.list.get(i);
    const def = species.get(p.sp);
    _ = try d.text(x, y, 1.75, white, def.name);
    y += 24;
    try d.tendril(x, y, 150, 12, .{120, 230, 150, 255}, p.growth, 0.5);
    _ = try d.print(x + 164, y - 4, 1.25, dim, "GROWTH {d:.0}%", .{p.growth * 100});
    y += 22;
    _ = try d.print(x, y, 1.4, gold, "{s} {d:.1}  SEEDS {d}  HP {d:.0}%", .{def.yields.info().short, p.essence, @as(u32, @intFromFloat(@floor(p.seeds))), p.health * 100});
  }
}

fn inventory(g:*play.Game, W:f32, H:f32) !void {
  const d = &g.ui;
  const cols = 6;
  const rows = player_mod.SLOTS / cols;
  const gap:f32 = 64;
  const weave_rows = (craft.hand.len + 1) / 2;
  const pw:f32 = 720;
  const ph = gap * rows + 110 + 52 * @as(f32, @floatFromInt(weave_rows));
  const px = (W - pw) / 2;
  const py = (H - ph) / 2 - 30;
  try d.membrane(px, py, pw, ph, .{30, 22, 40, 225}, 0.33);
  _ = try d.text(px + 28, py + 22, 2.5, gold, "SAP BELLY");
  _ = try d.print(px + pw - 170, py + 30, 1.5, dim, "{d:.0}% FULL", .{g.player.inv.fill() * 100});
  const gx = px + (pw - gap * cols) / 2;
  for (g.player.inv.slot, 0..) |slot, i| {
    const cx = gx + gap * (@as(f32, @floatFromInt(i % cols)) + 0.5);
    const cy = py + 72 + gap * (@as(f32, @floatFromInt(i / cols)) + 0.5);
    if (slot) |s| {
      const info = s.item.info();
      const full = @as(f32, @floatFromInt(s.n)) / @as(f32, @floatFromInt(info.stack));
      try d.pod(cx, cy, 24, info.col, 0.3 + 0.7 * full, @as(f32, @floatFromInt(i)) * 0.13);
      _ = try d.text(cx - 12, cy - 12, 2, .{20, 20, 20, 255}, info.short);
      _ = try d.print(cx - 10, cy + 8, 1.25, white, "{d}", .{s.n});
    } else {
      try d.pod(cx, cy, 19, .{40, 55, 45, 160}, 0, @as(f32, @floatFromInt(i)) * 0.13);
    }
  }

  // weaving: two columns of recipes, locked ones shown as unknown
  const wy = py + 72 + gap * @as(f32, @floatFromInt(rows)) + 6;
  _ = try d.text(px + 28, wy, 2, gold, "WEAVE");
  if (g.weave.busy()) {
    try d.tendril(px + 130, wy + 6, 200, 14, gold, g.weave.progress(), 0.4);
    _ = try d.print(px + 346, wy + 2, 1.25, dim, "{d} QUEUED", .{g.weave.len});
  }
  for (craft.hand, 0..) |r, i| {
    const colx = px + 30 + @as(f32, @floatFromInt(i % 2)) * (pw / 2);
    const y = wy + 42 + 52 * @as(f32, @floatFromInt(i / 2));
    const open = r.unlocked(&g.prog);
    const ok = open and craft.Crafter.can(&g.player.inv, r);
    const info = r.out.info();
    try d.pod(colx + 16, y, 15, if (open) info.col else unknown, if (ok) 0.9 else 0.1, @as(f32, @floatFromInt(i)) * 0.5);
    if (!open) {
      _ = try d.print(colx + 40, y - 14, 1.4, unknown, "{d} ??? (NEEDS {s})", .{i + 1, prog.tree.get(r.needs.?).name});
      continue;
    }
    _ = try d.print(colx + 40, y - 14, 1.4, if (ok) white else dim, "{d} {s}{s}", .{i + 1, info.name, if (r.n > 1) " X2" else ""});
    var x = colx + 44;
    for (r.in) |ing| {
      const have = g.player.inv.count(ing.item) >= ing.n;
      try d.pod(x + 6, y + 10, 6, ing.item.info().col, if (have) 0.7 else 0.05, x * 0.01);
      x = try d.print(x + 14, y + 5, 1.15, if (have) white else dim, "{d}{s}", .{ing.n, ing.item.info().short}) + 10;
    }
  }
}

fn research(g:*play.Game, W:f32, H:f32) !void {
  const d = &g.ui;
  const pw:f32 = 660;
  const n:f32 = @floatFromInt(prog.tree.values.len);
  const ph = 100 + 70 * n;
  const px = W - pw - 24;
  const py = @max(10, (H - ph) / 2 - 30);
  try d.membrane(px, py, pw, ph, .{26, 18, 44, 225}, 0.77);
  _ = try d.text(px + 28, py + 22, 2.5, gold, "RESEARCH");
  _ = try d.text(px + 28, py + 52, 1.2, dim, "RESEARCH BLOOMS STUDY WHAT IS CHOSEN, EATING WHAT THEY ARE FED. 1-7 CHOOSES");
  for (prog.tree.values, 0..) |r, i| {
    const id:prog.Id = @enumFromInt(i);
    const status = g.prog.status(id);
    const y = py + 80 + 70 * @as(f32, @floatFromInt(i));
    const cur = g.prog.current == id;
    const col = switch (status) { .done => [4]u8{140, 230, 170, 255}, .open => white, .locked => [4]u8{105, 105, 120, 255} };
    if (cur) try d.glow(px + 40, y + 8, 22, .{255, 210, 130, 120});
    _ = try d.print(px + 30, y, 1.6, if (cur) gold else col, "{d} {s}", .{i + 1, r.name});
    _ = try d.text(px + 54, y + 20, 1.15, dim, r.desc);
    var x = px + 54;
    for (r.per_unit) |ing| {
      try d.pod(x + 6, y + 42, 6, ing.item.info().col, 0.6, x * 0.01);
      x = try d.print(x + 14, y + 37, 1.15, dim, "{d}{s}", .{ing.n, ing.item.info().short}) + 10;
    }
    _ = try d.print(x + 8, y + 37, 1.15, dim, "X{d}  {d:.0}S", .{r.units, r.unit_time});
    const done = g.prog.progress.get(id);
    const frac = if (status == .done) 1 else @as(f32, @floatFromInt(done)) / @as(f32, @floatFromInt(r.units));
    try d.tendril(px + pw - 200, y + 10, 170, 12, col, frac, @as(f32, @floatFromInt(i)) * 0.21);
  }
}
