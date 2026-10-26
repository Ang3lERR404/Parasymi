//! what the wolf does to the world: gather, put (sow/grow), weave, feed and
//! take from structures, interact with them, harvest, uproot, turn what
//! stands, pick up the seed of what stands, catch starlight. Each action works
//! on the Game and reports through the progression log.
const lib = @import("../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const indexOfScalar = std.mem.indexOfScalar;
const testing = std.testing;
const m = lib.engine.core.math;
const ck = lib.ck;
const species = lib.species;
const items = lib.items;
const craft = lib.craft;
const st = lib.structures;
const resources = lib.resources;
const play = lib.play;
const txt = lib.txt;

const Game = play.Game;

pub const GATHER_TIME:f32 = 0.45;
/// how long a one-off gesture keeps the hands busy (s): putting something
/// down or uprooting it, feeding or emptying a structure, harvesting
pub const LINGER_PUT:f32 = 0.35;
const LINGER_TRADE:f32 = 0.4;
const LINGER_HARVEST:f32 = 0.5;
/// wait before the next put (s): after one, and after warning of none left
const PUT_COOLDOWN:f32 = 0.25;
/// remove, held and swept: the wait before the next tile's thing goes (s)
pub const REMOVE_COOLDOWN:f32 = 0.2;
const WARN_COOLDOWN:f32 = 1.5;
/// starlight within `ATTRACT` drifts to the chest, faster the closer
/// (`PULL` less `PULL_FALLOFF` per unit away), and is absorbed within `ABSORB`
const ATTRACT:f32 = 2.4;
const PULL:f32 = 5;
const PULL_FALLOFF:f32 = 1.5;
const ABSORB:f32 = 0.45;

/// returns whether the wolf keeps working this tile.
pub fn gather(g:*Game, c:*ck.Chunk, t:usize, dt:f32) bool {
  const node = resources.of(c.kind[t]) orelse return false;
  g.gather_t += dt;
  if (g.gather_t < GATHER_TIME) return true;
  g.gather_t = 0;
  if (g.player.inv.add(node.item, 1) == 0) {
    if (!g.full_warned) g.prog.say(txt.s.msg.belly_full, .{});
    g.full_warned = true;
    return false;
  }
  c.res[t] -= 1;
  return c.res[t] > 0;
}

/// put the selected hotbar item into the world: sow a seed or grow a bulb.
pub fn put(g:*Game, h:[2]i32) Allocator.Error!void {
  const item = g.selected() orelse return;
  // anything but a seed or a bulb stays in the belly
  if (item.plants() == null and st.kindOf(item) == null) return;
  if (!play.known(g, item)) return;
  if (g.player.inv.count(item) == 0) {
    g.prog.say(txt.s.msg.no_item, .{txt.item(item).name});
    g.plant_cd = WARN_COOLDOWN;
    return;
  }
  // a plant faces the way the next thing put down does, as a structure
  const ok = if (item.plants()) |sp|
    try g.plants.placeEx(g.gpa, &g.world, h[0], h[1], .{
      .x = h[0], .y = h[1], .chunk = undefined, .tile = undefined, .sp = sp, .seed = g.rng.float(), .dir = g.place_dir,
    })
  else if (st.kindOf(item)) |k|
    try g.structs.place(g.gpa, &g.world, h[0], h[1], k, g.place_dir, g.rng.float())
  else false;
  if (ok) {
    if (st.kindOf(item) != null) g.structs.sprout(g.structs.at(&g.world, h[0], h[1]).?);
    _ = g.player.inv.take(item, 1);
    g.plant_cd = PUT_COOLDOWN;
    g.linger = LINGER_PUT;
  }
}

pub fn canPut(g:*const Game, h:[2]i32) bool {
  const item = g.selected() orelse return false;
  if (item.plants()) |sp| return g.plants.canPlace(&g.world, h[0], h[1], sp);
  if (st.kindOf(item)) |k| return g.structs.canPlace(&g.world, h[0], h[1], k);
  return false;
}

pub fn weaveByHand(g:*Game, i:usize) void {
  // seeds (and what binds the lineages) come only from a germinator
  if (craft.germinatorOnly(i)) return;
  const r = craft.hand[i];
  if (!r.unlocked(&g.prog)) return g.prog.say(txt.s.msg.not_understood, .{txt.item(r.out).name});
  if (!g.weave.push(g.player.inv.bag(), i)) g.prog.say(txt.s.msg.cannot_weave, .{txt.item(r.out).name});
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
  g.linger = LINGER_TRADE;
  if (moved == 0) g.prog.say(txt.s.msg.wants_nothing, .{});
}

/// what a click (or the interact key) on a structure does: one that keeps
/// items opens its panel, one that is paired is configured, any other is
/// fed from the belly.
pub fn interact(g:*Game, h:[2]i32, j:st.Id) void {
  const s = g.structs.get(j);
  if (s.def().store) {
    g.open = h;
    g.mode = .structure;
  } else if (st.configurable(s.kind())) st.configure(&g.structs, j, &g.prog)
  else feed(g, j);
}

/// turn what stands at a tile a quarter, clockwise or `back`: a rooted
/// thing uproots itself on its roots and digs back in facing its new way,
/// a floater only turns (sim/turn.zig). Not again until it has finished.
/// Returns whether anything stands there.
pub fn turnAt(g:*Game, h:[2]i32, back:bool) bool {
  const by:m.Dir = if (back) 3 else 1;
  if (g.structs.at(&g.world, h[0], h[1])) |j| {
    const s = g.structs.get(j);
    if (!s.turn.busy(g.time, !s.def().floating)) {
      s.turn = .{.from = s.dir, .at = g.time};
      s.dir +%= by;
    }
    return true;
  }
  const id = g.plants.at(&g.world, h[0], h[1]) orelse return false;
  const p = g.plants.list.slice();
  const i = id.idx();
  const rooted = !species.get(p.items(.sp)[i]).floating;
  if (!p.items(.turn)[i].busy(g.time, rooted)) {
    p.items(.turn)[i] = .{.from = p.items(.dir)[i], .at = g.time};
    p.items(.dir)[i] +%= by;
  }
  return true;
}

/// take up the seed (or bulb) of what stands at a tile, facing as it does:
/// the hotbar slot holding it is chosen; else, from the belly, it goes on
/// the chosen slot if that is empty, else the first empty one, else over
/// the chosen one. Returns whether anything stands there.
pub fn pick(g:*Game, h:[2]i32) bool {
  const item:items.Item, const dir:m.Dir = if (g.structs.at(&g.world, h[0], h[1])) |j| blk: {
    const s = g.structs.get(j);
    // (what forms by itself, a diamond, has no bulb to pick)
    if (st.kindOf(s.def().item) != s.kind()) return true;
    break :blk .{s.def().item, s.dir};
  } else if (g.plants.at(&g.world, h[0], h[1])) |id| blk: {
    const p = g.plants.list.slice();
    const seed = species.get(p.items(.sp)[id.idx()]).seed orelse return true;
    break :blk .{seed, p.items(.dir)[id.idx()]};
  } else return false;
  g.place_dir = dir;
  if (indexOfScalar(?items.Item, &g.bar, item)) |i| {
    g.hot = i;
    return true;
  }
  if (g.player.inv.count(item) == 0) {
    g.prog.say(txt.s.msg.no_item, .{txt.item(item).name});
    return true;
  }
  const slot = if (g.bar[g.hot] == null) g.hot else indexOfScalar(?items.Item, &g.bar, null) orelse g.hot;
  g.bar[slot] = item;
  g.hot = slot;
  return true;
}

/// empty a structure into the belly (what fits).
pub fn takeFrom(g:*Game, j:st.Id) void {
  const s = g.structs.get(j);
  for (&s.inv.slot) |*slot| if (slot.*) |*it| {
    const n = g.player.inv.add(it.item, it.n);
    it.n -= n;
    if (it.n == 0) slot.* = null;
  };
  if (st.release(s)) |h| if (g.player.inv.add(h, 1) == 0) g.prog.say(txt.s.msg.belly_full, .{});
  g.linger = LINGER_TRADE;
}

/// uproot a structure: its bulb and contents come back (what fits).
/// anything that doesn't fit is lost.
pub fn unbuild(g:*Game, j:st.Id) void {
  var s = g.structs.remove(&g.world, j);
  defer s.deinit(g.gpa);
  var lost:u32 = 0;
  // add returns how many fit; 1 - that = how many were lost
  lost += 1 - g.player.inv.add(s.def().item, 1);
  // (first: it may put what it has out back into its slots)
  if (st.release(&s)) |h| lost += 1 - g.player.inv.add(h, 1);
  for (s.inv.slot) |slot| if (slot) |it| {
    lost += it.n - g.player.inv.add(it.item, it.n);
  };
  if (lost > 0) g.prog.say(txt.s.msg.spilled, .{lost});
}

/// take a mature plant's yield. Plants never set seed (a germinator weaves them).
pub fn harvest(g:*Game, h:[2]i32) void {
  const id = g.plants.at(&g.world, h[0], h[1]) orelse return;
  const i = id.idx();
  const s = g.plants.list.slice();
  const sp = s.items(.sp)[i];
  if (s.items(.growth)[i] < 1) {
    g.prog.say(txt.s.msg.still_growing, .{txt.plant(sp).name, s.items(.growth)[i] * 100});
    return;
  }
  const es = m.floorTo(u16, s.items(.essence)[i]);
  if (es == 0) {
    g.prog.say(txt.s.msg.not_ripe, .{});
    return;
  }
  const yields = species.get(sp).yields;
  const got_es = g.player.inv.add(yields, es);
  s.items(.essence)[i] -= m.f(got_es);
  // what an unstudied plant gives is learned only by taking it
  if (got_es > 0 and !g.prog.yieldKnown(sp)) g.prog.say(txt.s.msg.gives_up, .{got_es, txt.item(yields).name});
  g.linger = LINGER_HARVEST;
  if (got_es < es) g.prog.say(txt.s.msg.belly_full, .{});
}

/// pull a plant up: a sown plant always comes back as its seed, ready to be
/// sown again, so it stays in the ground while the belly has no room for it.
/// One that was never sown (a confluence) gives nothing back.
pub fn uproot(g:*Game, h:[2]i32) void {
  const id = g.plants.at(&g.world, h[0], h[1]) orelse return;
  if (species.get(g.plants.list.items(.sp)[id.idx()]).seed) |seed| {
    if (g.player.inv.add(seed, 1) == 0) return g.prog.say(txt.s.msg.belly_full, .{});
  }
  _ = g.plants.removeAt(&g.world, h[0], h[1]);
}

/// starlight drifts toward the wolf's chest and is absorbed on touch.
pub fn catchStarlight(g:*Game, dt:f32) void {
  const chest = g.player.chest();
  var i:usize = 0;
  while (i < g.stars.motes.items.len) {
    const mo = &g.stars.motes.items[i];
    const d = chest - mo.pos;
    const dist = m.len(d);
    if (dist < ATTRACT) mo.pos += d * m.splat3(@min(1, dt * (PULL - dist * PULL_FALLOFF)));
    if (dist < ABSORB and g.player.inv.add(.starlight, 1) == 1) {
      _ = g.stars.motes.swapRemove(i);
      continue;
    }
    i += 1;
  }
}

test "plants never set seed; an uprooted plant comes back as its seed" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, play.DEFAULT_SEED);
  defer g.deinit();
  const x, const z = m.tileAt(g.player.pos);
  const cc = g.world.chunkOfTile(x + 2, z).?;
  const t = ck.localIndex(x + 2, z);
  cc.kind[t] = .soil;
  cc.res[t] = 0;
  try testing.expect(try g.plants.placeEx(gpa, &g.world, x + 2, z, .{
    .x = x + 2, .y = z, .chunk = undefined, .tile = undefined, .sp = .lumenroot,
    .seed = 0.5, .growth = 1, .essence = 2.5,
  }));
  harvest(&g, .{x + 2, z});
  try testing.expectEqual(@as(u32, 2), g.player.inv.count(.essence));
  try testing.expectEqual(@as(u32, 0), g.player.inv.count(.seed_lumenroot));
  uproot(&g, .{x + 2, z});
  try testing.expect(g.plants.at(&g.world, x + 2, z) == null);
  try testing.expectEqual(@as(u32, 1), g.player.inv.count(.seed_lumenroot));
}

test "seeds are woven only by a germinator, which is woven from gathered matter" {
  for (craft.by_hand) |i| try testing.expect(!craft.germinatorOnly(i));
  for (craft.hand) |r| if (r.out == .germinator) for (r.in) |ing| {
    try testing.expect(ing.item == .fibre or ing.item == .grit or ing.item == .starlight);
  };
}

test "a confluence gives only convergence essence" {
  const gpa = testing.allocator;
  var g = try Game.init(gpa, play.DEFAULT_SEED);
  defer g.deinit();
  const x, const z = m.tileAt(g.player.pos);
  var fp = m.footprint(x + 2, z, 2);
  while (fp.next()) |p| {
    const cc = g.world.chunkOfTile(p[0], p[1]).?;
    const t = ck.localIndex(p[0], p[1]);
    cc.kind[t] = .soil;
    cc.res[t] = 0;
  }
  try testing.expect(try g.plants.placeEx(gpa, &g.world, x + 2, z, .{
    .x = x + 2, .y = z, .chunk = undefined, .tile = undefined, .sp = .confluence,
    .seed = 0.5, .growth = 1, .essence = 3.5,
  }));
  harvest(&g, .{x + 3, z + 1});
  try testing.expectEqual(@as(u32, 3), g.player.inv.count(.convergence_essence));
  try testing.expectEqual(@as(u32, 0), g.player.inv.count(.seed_lumenroot));
  try testing.expectEqual(@as(u32, 0), g.player.inv.count(.seed_thornleech));
  try testing.expect(species.fromSeed(.convergence_essence) == null);
  // never sown, so uprooting it gives nothing back
  uproot(&g, .{x + 3, z + 1});
  try testing.expect(g.plants.at(&g.world, x + 3, z + 1) == null);
  try testing.expectEqual(@as(u32, 3), g.player.inv.total());
}