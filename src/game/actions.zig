//! what the wolf does to the world: gather, put (sow/grow), weave, feed and
//! take from structures, harvest, uproot, catch starlight. Each action works
//! on the Game and reports through the progression log.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../core/math.zig");
const ck = @import("../world/chunk.zig");
const species = @import("../sim/species.zig");
const plants_mod = @import("../sim/plants.zig");
const items = @import("../sim/items.zig");
const craft = @import("craft.zig");
const st = @import("structures.zig");
const resources = @import("resources.zig");
const play = @import("play.zig");

const Game = play.Game;

pub const GATHER_TIME:f32 = 0.45;

/// returns whether the wolf keeps working this tile.
pub fn gather(g:*Game, c:*ck.Chunk, t:usize, dt:f32) bool {
  const node = resources.of(c.kind[t]) orelse return false;
  g.gather_t += dt;
  if (g.gather_t < GATHER_TIME) return true;
  g.gather_t = 0;
  if (g.player.inv.add(node.item, 1) == 0) {
    if (!g.full_warned) g.prog.say("YOUR BELLY CAN HOLD NO MORE", .{});
    g.full_warned = true;
    return false;
  }
  c.res[t] -= 1;
  return c.res[t] > 0;
}

/// put the selected hotbar item into the world: sow a seed or grow a bulb.
pub fn put(g:*Game, h:[2]i32) Allocator.Error!void {
  const item = play.hotbar[g.hot];
  if (!play.known(g, item)) return;
  if (g.player.inv.count(item) == 0) {
    g.prog.say("NO {s}. WEAVE ONE IN YOUR BELLY (TAB)", .{item.info().name});
    g.plant_cd = 1.5;
    return;
  }
  const ok = if (item.plants()) |sp|
    try g.plants.place(g.gpa, &g.world, h[0], h[1], sp, g.rng.float())
  else if (st.kindOf(item)) |k|
    try g.structs.place(g.gpa, &g.world, h[0], h[1], k, g.place_dir, g.rng.float())
  else false;
  if (ok) {
    _ = g.player.inv.take(item, 1);
    g.plant_cd = 0.25;
    g.linger = 0.35;
  }
}

pub fn canPut(g:*const Game, h:[2]i32) bool {
  const item = play.hotbar[g.hot];
  if (item.plants()) |sp| return g.plants.canPlace(&g.world, h[0], h[1], sp);
  if (st.kindOf(item)) |k| return g.structs.canPlace(&g.world, h[0], h[1], k);
  return false;
}

pub fn weaveByHand(g:*Game, i:usize) void {
  const r = craft.hand[i];
  if (!r.unlocked(&g.prog)) return g.prog.say("{s} IS NOT YET UNDERSTOOD", .{r.out.info().name});
  if (!g.weave.push(g.player.inv.bag(), i)) g.prog.say("NOT ENOUGH TO WEAVE {s}", .{r.out.info().name});
}

/// give a structure everything from the belly it will take.
pub fn feed(g:*Game, j:st.Id) void {
  var moved:u32 = 0;
  for (&g.player.inv.slot) |*slot| if (slot.*) |*s| {
    // seeds and bulbs stay in the belly, ready to be placed
    if (s.item.plants() != null or st.kindOf(s.item) != null) continue;
    const n = g.structs.insert(&g.prog, j, s.item, s.n);
    moved += n;
    s.n -= n;
    if (s.n == 0) slot.* = null;
  };
  g.linger = 0.4;
  if (moved == 0) g.prog.say("IT WANTS NOTHING YOU CARRY", .{});
}

/// empty a structure into the belly (what fits).
pub fn takeFrom(g:*Game, j:st.Id) void {
  const s = g.structs.get(j);
  for (&s.inv.slot) |*slot| if (slot.*) |*it| {
    const n = g.player.inv.add(it.item, it.n);
    it.n -= n;
    if (it.n == 0) slot.* = null;
  };
  if (st.release(s)) |h| if (g.player.inv.add(h, 1) == 0) g.prog.say("YOUR BELLY CAN HOLD NO MORE", .{});
  g.linger = 0.4;
}

/// uproot a structure: its bulb and contents come back (what fits).
pub fn unbuild(g:*Game, j:st.Id) void {
  var s = g.structs.remove(&g.world, j);
  var lost:u32 = 0;
  lost += 1 - g.player.inv.add(s.def().item, 1);
  for (s.inv.slot) |slot| if (slot) |it| { lost += it.n - g.player.inv.add(it.item, it.n); };
  if (st.release(&s)) |h| lost += 1 - g.player.inv.add(h, 1);
  if (lost > 0) g.prog.say("{d} THINGS SPILLED AND WITHERED", .{lost});
}

/// take a mature plant's yield and ripe seeds. Where lineages touch and
/// splicing is understood, one seed comes out a hybrid.
pub fn harvest(g:*Game, h:[2]i32) void {
  const id = g.plants.at(&g.world, h[0], h[1]) orelse return;
  const i = id.idx();
  const s = g.plants.list.slice();
  const sp = s.items(.sp)[i];
  if (s.items(.growth)[i] < 1) {
    g.prog.say("{s} IS STILL GROWING ({d:.0}%)", .{species.get(sp).name, s.items(.growth)[i] * 100});
    return;
  }
  const es = m.floorTo(u16, s.items(.essence)[i]);
  var seeds = m.floorTo(u16, s.items(.seeds)[i]);
  if (es == 0 and seeds == 0) {
    g.prog.say("NOTHING IS RIPE YET", .{});
    return;
  }
  const got_es = g.player.inv.add(species.get(sp).yields, es);
  s.items(.essence)[i] -= m.f(got_es);
  if (seeds > 0 and g.prog.done.contains(.seed_splicing) and touchesOtherLineage(s, i)) {
    if (g.player.inv.add(.seed_vesper, 1) == 1) {
      seeds -= 1;
      s.items(.seeds)[i] -= 1;
    }
  }
  const got_sd = g.player.inv.add(items.Item.seedOf(sp), seeds);
  s.items(.seeds)[i] -= m.f(got_sd);
  g.linger = 0.5;
  if (got_es + got_sd < es + seeds) g.prog.say("YOUR BELLY CAN HOLD NO MORE", .{});
}

fn touchesOtherLineage(s:std.MultiArrayList(plants_mod.Plant).Slice, i:usize) bool {
  const mine = species.get(s.items(.sp)[i]).lineage;
  for (s.items(.n1)[i]) |id| {
    if (id == .none) break;
    const j = id.idx();
    if (species.get(s.items(.sp)[j]).lineage != mine and s.items(.growth)[j] >= 1) return true;
  }
  return false;
}

/// starlight drifts toward the wolf's chest and is absorbed on touch.
pub fn catchStarlight(g:*Game, dt:f32) void {
  const chest = g.player.chest();
  var i:usize = 0;
  while (i < g.stars.motes.items.len) {
    const mo = &g.stars.motes.items[i];
    const d = chest - mo.pos;
    const dist = m.len(d);
    if (dist < 2.4) mo.pos += d * m.splat(@min(1, dt * (5 - dist * 1.5)));
    if (dist < 0.45 and g.player.inv.add(.starlight, 1) == 1) {
      _ = g.stars.motes.swapRemove(i);
      continue;
    }
    i += 1;
  }
}
