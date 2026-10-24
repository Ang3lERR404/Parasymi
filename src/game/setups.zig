//! prepared worlds for showcasing and testing (`--demo`, `--stress`).
//! Not part of play: they place things on the gardener's behalf.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ck = @import("../world/chunk.zig");
const species = @import("../sim/species.zig");
const prog = @import("progression.zig");
const play = @import("play.zig");
const m = @import("../core/math.zig");
const halo = @import("structures/halo.zig");

const Game = play.Game;

/// a starter garden around the player plus the first automation, fast-forwarded.
pub fn demo(g:*Game, seconds:f32) Allocator.Error!void {
  const cx, const cz = m.tileAt(g.player.pos);
  var dz:i32 = -4;
  while (dz <= 4) : (dz += 1) {
    var dx:i32 = -6;
    while (dx <= 6) : (dx += 1) {
      if (@abs(dx) <= 1 and @abs(dz) <= 1) continue;
      const sp:species.Id = if (dx > 2) .thornleech else if (dx < -2 or @mod(dz, 2) == 0) .lumenroot else continue;
      _ = try g.plants.place(g.gpa, &g.world, cx + dx, cz + dz, sp, g.rng.float());
    }
  }
  // a lumenroot harvested by conduits into a cache, a germinator and research
  // bloom already fed, the new plant forms around
  for ([_]prog.Id{ .ley_sight, .drift_spores, .root_communion, .canopy_weaving }) |id| g.prog.done.insert(id);
  _ = try g.structs.place(g.gpa, &g.world, cx - 2, cz - 3, .conduit, 0, 0.1);
  _ = try g.structs.place(g.gpa, &g.world, cx - 1, cz - 3, .conduit, 0, 0.2);
  _ = try g.structs.place(g.gpa, &g.world, cx, cz - 3, .sap_cache, 0, 0.3);
  if (try g.structs.place(g.gpa, &g.world, cx - 2, cz + 5, .germinator, 0, 0.4)) {
    const j = g.structs.at(&g.world, cx - 2, cz + 5).?;
    _ = g.structs.insert(&g.prog, j, .fibre, 20);
    _ = g.structs.insert(&g.prog, j, .starlight, 20);
  }
  if (try g.structs.place(g.gpa, &g.world, cx + 1, cz + 5, .research_bloom, 0, 0.5)) {
    g.prog.select(.hungering_tendrils);
    const j = g.structs.at(&g.world, cx + 1, cz + 5).?;
    _ = g.structs.insert(&g.prog, j, .essence, 20);
    _ = g.structs.insert(&g.prog, j, .grit, 20);
  }
  _ = try g.plants.place(g.gpa, &g.world, cx - 6, cz + 6, .hollowheart, 0.7);
  _ = try g.plants.place(g.gpa, &g.world, cx - 5, cz - 1, .driftwisp, 0.8);
  _ = try g.plants.place(g.gpa, &g.world, cx - 4, cz + 2, .driftwisp, 0.9);
  try digger(g, cx, cz);
  try confluences(g, cx, cz);
  try blooms(g, cx, cz);

  var t:f32 = 0;
  while (t < seconds) : (t += play.TICK) try g.step();
  try haloGarden(g, cx, cz);
  _ = g.player.inv.add(.grit, 34);
  _ = g.player.inv.add(.fibre, 21);
  _ = g.player.inv.add(.starlight, 7);
  _ = g.player.inv.add(.seed_lumenroot, 5);
  _ = g.player.inv.add(.conduit, 6);
  _ = g.player.inv.add(.root_digger, 2);
}

/// a symbiote and a parasite two tiles apart, left to converge, and a row of
/// confluences held at each growth stage.
fn confluences(g:*Game, cx:i32, cz:i32) Allocator.Error!void {
  _ = try g.plants.place(g.gpa, &g.world, cx + 4, cz - 7, .lumenroot, 0.3);
  _ = try g.plants.place(g.gpa, &g.world, cx + 6, cz - 7, .thornleech, 0.6);
  for ([_]f32{ 0.1, 0.35, 0.6, 0.95 }, 0..) |growth, i| {
    const x = cx - 6 + 3 * @as(i32, @intCast(i));
    // effectively infinite: holds the stage for viewing without growing
    _ = try g.plants.placeEx(g.gpa, &g.world, x, cz + 9, .{
      .x = x, .y = cz + 9, .chunk = undefined, .tile = undefined, .sp = .confluence,
      .seed = 0.2 * m.f(i), .growth = growth, .span = 1e9, .mana = 20,
    });
  }
}

/// an arc of celestial blooms around the garden, each ~5 tiles from the next
/// and > 10 (their link reach) from the one after, so they link in a chain
/// whose beams never overlap. Mature ones keep the network radiating; the
/// others are held mid-assembly and as a beam still reaching out (> 0.85).
/// None sits beside a parasite (the thornleech bed, the converging pair): it
/// would be drained and wither.
fn blooms(g:*Game, cx:i32, cz:i32) Allocator.Error!void {
  const at = [_][2]i32{ .{ -8, -3 }, .{ -4, -7 }, .{ 1, -8 }, .{ 8, -6 }, .{ 10, -2 } };
  const growth = [_]f32{ 1, 0.3, 1, 0.6, 0.95 };
  for (at, growth, 0..) |o, gr, i| {
    const x = cx + o[0];
    const z = cz + o[1];
    _ = try g.plants.placeEx(g.gpa, &g.world, x, z, .{
      .x = x, .y = z, .chunk = undefined, .tile = undefined, .sp = .bloom,
      .seed = 0.13 + 0.21 * m.f(i), .growth = gr, .span = 1e9, .mana = 10,
    });
  }
}

/// the last corner's bloom starts this far grown and, full of sky and
/// linked to no kin, grows 1/`LAST_SPAN` a second: done ~20 s in
const LAST_FROM:f32 = 0.85;
const LAST_SPAN:f32 = 133;

/// west of the garden, put down after the fast-forward so it plays out
/// live: a polyp growing in, three grown blooms on the points of its
/// halo's ring and a fourth finishing (in ~20 s, time to walk over); as
/// it does, the halo forms. Two vespers draw on the east point's
/// bloom: one inside the ring, which it keeps once the bloom is drawn
/// away, one outside it, which only the diamond's wider field reaches.
fn haloGarden(g:*Game, cx:i32, cz:i32) Allocator.Error!void {
  const r = halo.R;
  const x = cx - 19;
  const z = cz + 2;
  if (!try g.structs.place(g.gpa, &g.world, x, z, .polyp, 0, 0.45)) return;
  g.structs.sprout(g.structs.at(&g.world, x, z).?);
  for (halo.POINTS, 0..) |c, i| {
    const bx = x + c[0] * r;
    const bz = z + c[1] * r;
    _ = try g.plants.placeEx(g.gpa, &g.world, bx, bz, .{
      .x = bx, .y = bz, .chunk = undefined, .tile = undefined, .sp = .bloom,
      .seed = 0.31 + 0.17 * m.f(i), .growth = if (i == 3) LAST_FROM else 1, .span = if (i == 3) LAST_SPAN else 1e9, .mana = 10,
    });
  }
  _ = try g.plants.place(g.gpa, &g.world, x + 3, z, .vesper, 0.5);
  _ = try g.plants.place(g.gpa, &g.world, x + 5, z + 3, .vesper, 0.6);
}

/// the nearest free spot beside a resource node gets a root-digger, with a
/// sap cache next to it to fill.
fn digger(g:*Game, cx:i32, cz:i32) Allocator.Error!void {
  g.prog.done.insert(.deep_rooting);
  var r:i32 = 2;
  while (r < 12) : (r += 1) {
    var it = m.ring(r);
    while (it.next()) |o| {
      const x = cx + o[0];
      const z = cz + o[1];
      if (!nodeBeside(g, x, z) or !g.structs.canPlace(&g.world, x, z, .root_digger)) continue;
      _ = try g.structs.place(g.gpa, &g.world, x, z, .root_digger, 0, 0.6);
      for (m.dirs) |d| {
        const v = m.dirVec(d);
        if (try g.structs.place(g.gpa, &g.world, x + v.x, z + v.z, .sap_cache, 0, 0.7)) return;
      }
      return;
    }
  }
}

fn nodeBeside(g:*const Game, x:i32, z:i32) bool {
  for (m.dirs) |d| {
    const v = m.dirVec(d);
    const c = g.world.chunkOfTile(x + v.x, z + v.z) orelse continue;
    const t = ck.localIndex(x + v.x, z + v.z);
    if (c.res[t] > 0 and c.occ[t] == .none and c.kind[t] != .water) return true;
  }
  return false;
}

/// fill a side x side field with the three first species at random (perf testing).
pub fn stress(g:*Game, side:i32) Allocator.Error!void {
  const cx, const cz = m.tileAt(g.player.pos);
  const r = @divFloor(side, 2);
  try g.world.stream(g.focus(), @divFloor(r, ck.SIZE) + 2, 1 << 20);
  const first = [_]species.Id{ .lumenroot, .thornleech, .vesper };
  var dz:i32 = -r;
  while (dz < r) : (dz += 1) {
    var dx:i32 = -r;
    while (dx < r) : (dx += 1) {
      // pick one of the three species uniformly
      const sp = first[m.floorTo(usize, g.rng.float() * m.f(first.len))];
      _ = try g.plants.place(g.gpa, &g.world, cx + dx, cz + dz, sp, g.rng.float());
    }
  }
}