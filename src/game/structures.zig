//! grown structures: the first steps from hand work toward automation.
//!
//! Each kind is its own module under `structures/` declaring:
//!   def:Def                     name, bulb item, footprint, mesh   (required)
//!   State                       per-kind data (optional, see `State` union)
//!   tick(ctx, id, dt) bool      advance; returns whether it is active
//!   wants(s, g, item) u32       how many of `item` it will still take in
//!   output(s) ?Item             what may leave it (pulled by conduits)
//!   release(s) ?Item            hand back anything it holds outside `inv`
//!   configure(s, g)             the player's "C" interaction
//!   emit(s, out, ctr, tf)       extra visuals beyond its mesh
//!   describe(s, d, g, x, y)     one line of hover text
//!   ground(kind) bool           which tiles it may stand on (default: any dry tile)
//! Missing hooks fall back to doing nothing. A new structure is one new file
//! plus one line in `kinds`.
const std = @import("std");
const Allocator = std.mem.Allocator;
const activeTag = std.meta.activeTag;
const testing = std.testing;
const m = @import("../core/math.zig");
const registry = @import("../core/registry.zig");
const ck = @import("../world/chunk.zig");
const World = @import("../world/world.zig").World;
const items = @import("../sim/items.zig");
const species = @import("../sim/species.zig");
const Plants = @import("../sim/plants.zig").Plants;
const meshlib = @import("../gfx/meshlib.zig");
const prog = @import("progression.zig");
const Parts = @import("parts.zig").Parts;
const Draw = @import("../ui/draw.zig").Draw;

const kinds = struct {
  pub const conduit = @import("structures/conduit.zig");
  pub const sap_cache = @import("structures/sap_cache.zig");
  pub const germinator = @import("structures/germinator.zig");
  pub const research_bloom = @import("structures/research_bloom.zig");
  pub const root_digger = @import("structures/root_digger.zig");
};
const reg = registry.Registry(kinds);
const Occ = ck.Occ;
const PlantId = ck.PlantId;

pub const Kind = reg.Id;
/// a placed structure's slot in `Structures.list`.
pub const Id = ck.StructId;

pub const Def = struct {
  name:[]const u8,
  item:items.Item,
  size:u8,
  mesh:meshlib.Id,
};

pub const defs = reg.table(Def, "def");
/// per-kind state; the active tag is the structure's kind.
pub const State = reg.Union("State");

pub fn kindOf(item:items.Item) ?Kind {
  inline for (reg.ids) |k| if (defs.get(k).item == item) return k;
  return null;
}

pub const SLOTS = 16;
/// how quickly a structure's activity glow eases toward its target
const ACTIVITY_EASE:f32 = 3;

pub const Structure = struct {
  x:i32,
  y:i32,
  dir:m.Dir = 0,
  seed:f32,
  inv:items.Inventory(SLOTS) = .{},
  state:State,
  /// smoothed 0..1, drives glow and motion
  activity:f32 = 0,

  pub fn kind(s:*const Structure) Kind { return activeTag(s.state); }
  pub fn def(s:*const Structure) Def { return defs.get(s.kind()); }
};

/// everything a structure's behaviour may touch.
pub const Ctx = struct {
  w:*World,
  plants:*Plants,
  g:*prog.Progression,
  ss:*Structures,
};

fn freshState(k:Kind) State {
  return switch (k) {
    inline else => |t| blk: {
      const T = @FieldType(State, @tagName(t));
      break :blk @unionInit(State, @tagName(t), if (T == void) {} else .{});
    },
  };
}

fn dry(k:ck.Kind) bool { return k != .water; }

pub const Structures = struct {
  list:std.ArrayList(Structure) = .empty,

  pub fn deinit(ss:*Structures, gpa:Allocator) void { ss.list.deinit(gpa); }

  pub fn get(ss:*Structures, id:Id) *Structure { return &ss.list.items[id.idx()]; }

  pub fn canPlace(_:*const Structures, w:*const World, wx:i32, wy:i32, k:Kind) bool {
    return switch (k) {
      inline else => |t| w.footprintFree(wx, wy, defs.get(t).size, if (comptime reg.has(t, "ground")) reg.module(t).ground else dry),
    };
  }

  pub fn place(ss:*Structures, gpa:Allocator, w:*World, wx:i32, wy:i32, k:Kind, dir:m.Dir, seed:f32) Allocator.Error!bool {
    if (!ss.canPlace(w, wx, wy, k)) return false;
    const idx = Id.of(ss.list.items.len);
    try ss.list.append(gpa, .{ .x = wx, .y = wy, .dir = dir, .seed = seed, .state = freshState(k) });
    w.setFootprint(wx, wy, defs.get(k).size, Occ.structure(idx));
    return true;
  }

  pub fn at(_:*const Structures, w:*const World, wx:i32, wy:i32) ?Id {
    return w.occAt(wx, wy).asStructure();
  }

  /// swap-remove; returns the removed structure so its contents can be refunded.
  pub fn remove(ss:*Structures, w:*World, id:Id) Structure {
    const s = ss.get(id).*;
    w.setFootprint(s.x, s.y, s.def().size, .none);
    const last = ss.list.items.len - 1;
    if (id.idx() != last) {
      const l = ss.list.items[last];
      w.moveFootprint(l.x, l.y, l.def().size, Occ.structure(id));
    }
    _ = ss.list.swapRemove(id.idx());
    return s;
  }

  // ---- hook dispatch: one comptime switch each, no per-kind code here ----

  pub fn wants(ss:*Structures, g:*const prog.Progression, id:Id, item:items.Item) u32 {
    const s = ss.get(id);
    return switch (s.kind()) {
      inline else => |k| if (comptime reg.has(k, "wants")) reg.module(k).wants(s, g, item) else 0,
    };
  }

  pub fn output(ss:*Structures, id:Id) ?items.Item {
    const s = ss.get(id);
    return switch (s.kind()) {
      inline else => |k| if (comptime reg.has(k, "output")) reg.module(k).output(s) else null,
    };
  }

  /// insert up to `n` of `item` (capped by what the structure still wants).
  /// Returns how many were actually inserted.
  pub fn insert(ss:*Structures, g:*const prog.Progression, id:Id, item:items.Item, n:u16) u16 {
    const k:u16 = @intCast(@min(n, ss.wants(g, id, item)));
    if (k == 0) return 0;
    return ss.get(id).inv.add(item, k);
  }

  pub fn tick(ss:*Structures, w:*World, plants:*Plants, g:*prog.Progression, dt:f32) void {
    const ctx:Ctx = .{ .w = w, .plants = plants, .g = g, .ss = ss };
    for (0..ss.list.items.len) |idx| {
      const id = Id.of(idx);
      const active = switch (ss.get(id).kind()) {
        inline else => |k| if (comptime reg.has(k, "tick")) reg.module(k).tick(ctx, id, dt) else false,
      };
      const s = ss.get(id);
      s.activity += ((if (active) @as(f32, 1) else 0) - s.activity) * @min(1, dt * ACTIVITY_EASE);
    }
  }
};

pub fn release(s:*Structure) ?items.Item {
  return switch (s.kind()) {
    inline else => |k| if (comptime reg.has(k, "release")) reg.module(k).release(s) else null,
  };
}

pub fn configure(s:*Structure, g:*prog.Progression) void {
  switch (s.kind()) {
    inline else => |k| if (comptime reg.has(k, "configure")) reg.module(k).configure(s, g),
  }
}

pub fn emit(s:*const Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  switch (s.kind()) {
    inline else => |k| if (comptime reg.has(k, "emit")) try reg.module(k).emit(s, out, ctr, tf),
  }
}

pub fn describe(s:*const Structure, d:*Draw, g:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  switch (s.kind()) {
    inline else => |k| if (comptime reg.has(k, "describe")) try reg.module(k).describe(s, d, g, x, y),
  }
}

/// take one ripe unit from a mature plant: its yield first, then a seed.
pub fn harvestOne(plants:*Plants, id:PlantId) ?items.Item {
  const p = id.idx();
  const s = plants.list.slice();
  if (s.items(.growth)[p] < 1) return null;
  const sp = s.items(.sp)[p];
  if (s.items(.essence)[p] >= 1) {
    s.items(.essence)[p] -= 1;
    return species.get(sp).yields;
  }
  if (s.items(.seeds)[p] >= 1) {
    s.items(.seeds)[p] -= 1;
    return species.ripeSeed(sp, m.floorTo(u32, s.items(.seeds)[p]));
  }
  return null;
}

test "conduits harvest plants into a cache" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..4) |x| { c.kind[x] = .soil; c.height[x] = 1; c.res[x] = 0; }
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  // plant -> conduit -> conduit -> cache, left to right
  try testing.expect(try plants.placeEx(gpa, &w, 0, 0, .{ .x = 0, .y = 0, .chunk = undefined, .tile = undefined, .sp = .lumenroot, .seed = 0, .growth = 1, .essence = 3 }));
  try testing.expect(try ss.place(gpa, &w, 1, 0, .conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 0, .conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 3, 0, .sap_cache, 0, 0));
  for (0..200) |_| ss.tick(&w, &plants, &g, 0.05);
  const cache = ss.at(&w, 3, 0).?;
  try testing.expectEqual(@as(u32, 3), ss.get(cache).inv.count(.essence));
  // removing the middle conduit keeps the others addressable
  _ = ss.remove(&w, ss.at(&w, 1, 0).?);
  try testing.expect(ss.get(ss.at(&w, 3, 0).?).kind() == .sap_cache);
}