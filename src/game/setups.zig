//! prepared worlds for showcasing and testing (`--demo`, `--stress`).
//! Not part of play: they place things on the gardener's behalf.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ck = @import("../world/chunk.zig");
const species = @import("../sim/species.zig");
const prog = @import("progression.zig");
const play = @import("play.zig");
const m = @import("../core/math.zig");

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
  for ([_]prog.Id{.ley_sight, .drift_spores, .root_communion, .canopy_weaving}) |id| g.prog.done.insert(id);
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

  var t:f32 = 0;
  while (t < seconds) : (t += play.TICK) try g.step();
  _ = g.player.inv.add(.grit, 34);
  _ = g.player.inv.add(.fibre, 21);
  _ = g.player.inv.add(.starlight, 7);
  _ = g.player.inv.add(.seed_lumenroot, 5);
  _ = g.player.inv.add(.conduit, 6);
}

/// fill a side x side field with the three first species at random (perf testing).
pub fn stress(g:*Game, side:i32) Allocator.Error!void {
  const cx, const cz = m.tileAt(g.player.pos);
  const r = @divFloor(side, 2);
  try g.world.stream(g.focus(), @divFloor(r, ck.SIZE) + 2, 1 << 20);
  const first = [_]species.Id{.lumenroot, .thornleech, .vesper};
  var dz:i32 = -r;
  while (dz < r) : (dz += 1) {
    var dx:i32 = -r;
    while (dx < r) : (dx += 1) {
      const sp = first[@intFromFloat(g.rng.float() * 2.999)];
      _ = try g.plants.place(g.gpa, &g.world, cx + dx, cz + dz, sp, g.rng.float());
    }
  }
}
