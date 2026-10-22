//! grown structures: the first steps from hand work toward automation.
//! Each claims a footprint of tiles (shared occupancy with plants) and owns a
//! small inventory. Root conduits are the logistics: one item at a time they
//! pull from whatever is behind them (a structure, or a mature plant, which
//! harvests it) and pass it forward to the next conduit or structure.
const std = @import("std");
const ck = @import("../world/chunk.zig");
const World = @import("../world/world.zig").World;
const items = @import("../sim/items.zig");
const species = @import("../sim/species.zig");
const Plants = @import("../sim/plants.zig").Plants;
const meshlib = @import("../gfx/meshlib.zig");
const prog = @import("progression.zig");
const craft = @import("craft.zig");

const Occ = ck.Occ;

pub const Kind = enum(u8) { conduit, sap_cache, germinator, research_bloom };

pub const Def = struct {
  name:[]const u8,
  item:items.Item,
  size:u8,
  mesh:meshlib.Id,
};

pub const defs = std.enums.EnumArray(Kind, Def).init(.{
  .conduit = .{.name = "ROOT CONDUIT", .item = .conduit, .size = 1, .mesh = .conduit},
  .sap_cache = .{.name = "SAP CACHE", .item = .sap_cache, .size = 1, .mesh = .sap_cache},
  .germinator = .{.name = "GERMINATOR", .item = .germinator, .size = 2, .mesh = .germinator},
  .research_bloom = .{.name = "RESEARCH BLOOM", .item = .research_bloom, .size = 2, .mesh = .research_bloom},
});

pub fn kindOf(item:items.Item) ?Kind {
  return switch (item) {
    .conduit => .conduit, .sap_cache => .sap_cache, .germinator => .germinator, .research_bloom => .research_bloom,
    else => null,
  };
}

pub const SLOTS = 16;
/// most of one ingredient a germinator or bloom will hold
const STOCK = 20;
/// tiles per second an item travels along conduits
const CONDUIT_SPEED:f32 = 2.5;
const GERMINATOR_SPEED:f32 = 0.6;

/// direction a conduit faces: +x, +z, -x, -z
pub fn dirVec(d:u2) [2]i32 {
  return switch (d) { 0 => .{1, 0}, 1 => .{0, 1}, 2 => .{-1, 0}, 3 => .{0, -1} };
}

pub const Structure = struct {
  kind:Kind,
  x:i32, y:i32,
  dir:u2 = 0,
  seed:f32,
  inv:items.Inventory(SLOTS) = .{},
  /// germinator: which recipe (index into craft.hand) it weaves
  recipe:u8 = 0,
  weave:craft.Crafter = .{},
  lab:prog.Lab = .{},
  /// conduit: the item in transit and how far along it is (0..1)
  held:?items.Item = null,
  move_t:f32 = 0,
  /// smoothed 0..1, drives glow and motion
  activity:f32 = 0,

  pub fn def(s:*const Structure) Def { return defs.get(s.kind); }
};

fn dry(k:ck.Kind) bool { return k != .water; }

pub const Structures = struct {
  list:std.ArrayList(Structure) = .empty,

  pub fn deinit(ss:*Structures, gpa:std.mem.Allocator) void { ss.list.deinit(gpa); }

  pub fn canPlace(_:*const Structures, w:*const World, wx:i32, wy:i32, kind:Kind) bool {
    return w.footprintFree(wx, wy, defs.get(kind).size, dry);
  }

  pub fn place(ss:*Structures, gpa:std.mem.Allocator, w:*World, wx:i32, wy:i32, kind:Kind, dir:u2, seed:f32) !bool {
    if (!ss.canPlace(w, wx, wy, kind)) return false;
    const idx:u32 = @intCast(ss.list.items.len);
    try ss.list.append(gpa, .{.kind = kind, .x = wx, .y = wy, .dir = dir, .seed = seed});
    w.setFootprint(wx, wy, defs.get(kind).size, Occ.structure(idx));
    return true;
  }

  pub fn at(_:*const Structures, w:*const World, wx:i32, wy:i32) ?u32 {
    const o = w.occAt(wx, wy);
    return if (Occ.isStructure(o)) Occ.index(o) else null;
  }

  /// swap-remove; returns the removed structure so its contents can be refunded.
  pub fn remove(ss:*Structures, w:*World, i:u32) Structure {
    const s = ss.list.items[i];
    w.setFootprint(s.x, s.y, s.def().size, ck.NONE);
    const last:u32 = @intCast(ss.list.items.len - 1);
    if (i != last) {
      const l = ss.list.items[last];
      w.moveFootprint(l.x, l.y, l.def().size, Occ.structure(i));
    }
    _ = ss.list.swapRemove(i);
    return s;
  }

  /// how many of `item` structure `i` will still take in.
  pub fn wants(ss:*const Structures, g:*const prog.Progression, i:u32, item:items.Item) u32 {
    const s = &ss.list.items[i];
    switch (s.kind) {
      .conduit => return 0,
      .sap_cache => return 1 << 16,
      .germinator => for (craft.hand[s.recipe].in) |ing| {
        if (ing.item == item) return STOCK -| s.inv.count(item);
      },
      .research_bloom => if (g.current) |id| for (prog.tree.get(id).per_unit) |ing| {
        if (ing.item == item) return STOCK -| s.inv.count(item);
      },
    }
    return 0;
  }

  pub fn insert(ss:*Structures, g:*const prog.Progression, i:u32, item:items.Item, n:u16) u16 {
    const k:u16 = @intCast(@min(n, ss.wants(g, i, item)));
    if (k == 0) return 0;
    return ss.list.items[i].inv.add(item, k);
  }

  /// the next thing that may leave a structure: anything from a cache, only
  /// finished weaves from a germinator, nothing from a research bloom.
  pub fn output(ss:*const Structures, i:u32) ?items.Item {
    const s = &ss.list.items[i];
    var k:usize = SLOTS;
    while (k > 0) {
      k -= 1;
      const st = s.inv.slot[k] orelse continue;
      switch (s.kind) {
        .sap_cache => return st.item,
        .germinator => if (st.item == craft.hand[s.recipe].out) return st.item,
        else => {},
      }
    }
    return null;
  }

  pub fn tick(ss:*Structures, w:*World, plants:*Plants, g:*prog.Progression, dt:f32) void {
    for (ss.list.items, 0..) |*s, idx| {
      const i:u32 = @intCast(idx);
      var active = false;
      switch (s.kind) {
        .germinator => {
          const r = craft.hand[s.recipe];
          if (!s.weave.busy() and r.unlocked(g) and craft.Crafter.can(&s.inv, r)) _ = s.weave.push(&s.inv, s.recipe);
          _ = s.weave.tick(&s.inv, dt * GERMINATOR_SPEED);
          active = s.weave.busy();
        },
        .research_bloom => {
          g.labTick(&s.lab, &s.inv, dt);
          active = s.lab.busy;
        },
        .conduit => active = ss.conduit(w, plants, g, i, dt),
        .sap_cache => {},
      }
      s.activity += ((if (active) @as(f32, 1) else 0) - s.activity) * @min(1, dt * 3);
    }
  }

  fn conduit(ss:*Structures, w:*World, plants:*Plants, g:*const prog.Progression, i:u32, dt:f32) bool {
    const s = &ss.list.items[i];
    const v = dirVec(s.dir);
    if (s.held == null) {
      s.move_t = 0;
      const bx = s.x - v[0];
      const by = s.y - v[1];
      if (ss.at(w, bx, by)) |j| {
        if (ss.list.items[j].kind == .conduit) return false; // conduits push, they never pull
        const item = ss.output(j) orelse return false;
        _ = ss.list.items[j].inv.take(item, 1);
        ss.list.items[i].held = item;
      } else if (plants.at(w, bx, by)) |p| {
        ss.list.items[i].held = harvestOne(plants, p) orelse return false;
      }
      return ss.list.items[i].held != null;
    }
    s.move_t = @min(1, s.move_t + dt * CONDUIT_SPEED);
    if (s.move_t < 1) return true;
    const item = s.held.?;
    const fx = s.x + v[0];
    const fy = s.y + v[1];
    const j = ss.at(w, fx, fy) orelse return false;
    const t = &ss.list.items[j];
    if (t.kind == .conduit) {
      const back = dirVec(t.dir);
      // never hand back into a conduit facing us
      if (t.held != null or (back[0] == -v[0] and back[1] == -v[1])) return false;
      t.held = item;
      t.move_t = 0;
      ss.list.items[i].held = null;
      return true;
    }
    if (ss.insert(g, j, item, 1) == 1) ss.list.items[i].held = null;
    return true;
  }
};

/// take one ripe unit from a mature plant: its yield first, then a seed.
pub fn harvestOne(plants:*Plants, p:u32) ?items.Item {
  const s = plants.list.slice();
  if (s.items(.growth)[p] < 1) return null;
  const sp = s.items(.sp)[p];
  if (s.items(.essence)[p] >= 1) {
    s.items(.essence)[p] -= 1;
    return species.get(sp).yields;
  }
  if (s.items(.seeds)[p] >= 1) {
    s.items(.seeds)[p] -= 1;
    return items.Item.seedOf(sp);
  }
  return null;
}

test "conduits harvest plants into a cache" {
  const gpa = std.testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{.x = 0, .y = 0}, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..4) |x| { c.kind[x] = .soil; c.height[x] = 1; c.res[x] = 0; }
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  // plant -> conduit -> conduit -> cache, left to right
  try std.testing.expect(try plants.placeEx(gpa, &w, 0, 0, .{.x = 0, .y = 0, .chunk = undefined, .tile = undefined, .sp = .lumenroot, .seed = 0, .growth = 1, .essence = 3}));
  try std.testing.expect(try ss.place(gpa, &w, 1, 0, .conduit, 0, 0));
  try std.testing.expect(try ss.place(gpa, &w, 2, 0, .conduit, 0, 0));
  try std.testing.expect(try ss.place(gpa, &w, 3, 0, .sap_cache, 0, 0));
  for (0..200) |_| ss.tick(&w, &plants, &g, 0.05);
  const cache = ss.at(&w, 3, 0).?;
  try std.testing.expectEqual(@as(u32, 3), ss.list.items[cache].inv.count(.essence));
  // removing the middle conduit keeps the others addressable
  _ = ss.remove(&w, ss.at(&w, 1, 0).?);
  try std.testing.expect(ss.list.items[ss.at(&w, 3, 0).?].kind == .sap_cache);
}
