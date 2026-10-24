//! grown structures: the first steps from hand work toward automation.
//!
//! Each kind is its own module under `structures/` declaring:
//!   def:Def                     name, bulb item, footprint, mesh   (required)
//!   State                       per-kind data (optional, see `State` union)
//!   tick(ctx, id, dt) [!]bool   advance; returns whether it is active
//!   wants(s, g, item) u32       how many of `item` it will still take in
//!   output(s) ?Item             what may leave it (pulled by conduits)
//!   release(s) ?Item            hand back anything it holds outside `inv`
//!   configure(s, g)             the player's "C" interaction
//!   emit(s, out, ctr, tf)       extra visuals beyond its mesh
//!   describe(s, d, g, x, y)     one line of hover text
//!   ground(kind) bool           which tiles it may stand on (default: any dry tile)
//!   field(s) ?Field             a field of celestial energy it holds
//!   hold(s, x, y) ?Hold         how it draws the floater at a tile toward itself
//!   icon(ic, col)               its bulb in the HUD: the seed (`ic.coat`) and a
//!                               sprout or two showing what it does (`icon.zig`)
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
const Field = @import("../sim/ecology.zig").Field;
const meshlib = @import("../gfx/meshlib.zig");
const prog = @import("progression.zig");
const Parts = @import("parts.zig").Parts;
const Draw = @import("../ui/draw.zig").Draw;
const Color = @import("../ui/draw.zig").Color;
const icon_kit = @import("icon.zig");

const kinds = struct {
  pub const conduit = @import("structures/conduit.zig");
  pub const sap_cache = @import("structures/sap_cache.zig");
  pub const germinator = @import("structures/germinator.zig");
  pub const research_bloom = @import("structures/research_bloom.zig");
  pub const root_digger = @import("structures/root_digger.zig");
  pub const polyp = @import("structures/polyp.zig");
  pub const diamond = @import("structures/diamond.zig");
};
const reg = registry.Registry(kinds);
const Occ = ck.Occ;
const PlantId = ck.PlantId;

pub const Kind = reg.Id;
/// a placed structure's slot in `Structures.list`.
pub const Id = ck.StructId;

pub const Def = struct {
  item:items.Item,
  size:u8,
  mesh:meshlib.Id,
  /// how see-through its sap (resin pods, sap beads) is at its thinnest;
  /// like the wolf's, it has no light of its own
  sap:f32 = SAP,
  /// grown structures that stand up move like plants: how far they bend in
  /// the wind (0 rigid) and over what height
  sway:f32 = 0,
  tall:f32 = 1,
  /// seconds it takes to grow from a sprout once the gardener puts it down
  /// (0: there at once); it does no work until grown
  grow:f32 = 0,
  /// carries items tile to tile the way it faces (R turns it): carriers
  /// chain into one line, and producers leave them to pull through `output`
  carrier:bool = false,
  /// floats over its tile, `hover` over the ground, instead of standing on
  /// it: it takes no room there, so it may float over a structure or a
  /// plant (never over water or another floating one)
  floating:bool = false,
  hover:f32 = 0,
  /// its mesh is drawn by its own `emit` (a diamond: it forms on the GPU),
  /// not breathing and growing in as the others do; `mesh` is its preview
  bare:bool = false,
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
/// how see-through structures' sap is at its thinnest, unless a def says otherwise
pub const SAP:f32 = 0.78;
/// growing in: it reaches full height by 1/`SHOOT` of its growth, from
/// `SPROUT_H` of it, and fills out from `SPROUT_W` of its width
const SHOOT:f32 = 1.4;
const SPROUT_H:f32 = 0.1;
const SPROUT_W:f32 = 0.2;

pub const Structure = struct {
  x:i32,
  y:i32,
  dir:m.Dir = 0,
  seed:f32,
  inv:items.Inventory(SLOTS) = .{},
  state:State,
  /// smoothed 0..1, drives glow and motion
  activity:f32 = 0,
  /// 0 a sprout .. 1 grown (see `Def.grow`)
  grown:f32 = 1,

  pub fn kind(s:*const Structure) Kind { return activeTag(s.state); }
  /// how big a growing structure is drawn: it shoots up from the ground
  /// first and fills out after, as the plants do
  pub fn grownScale(s:*const Structure) m.V3 {
    const up = m.smooth(m.clamp01(s.grown * SHOOT));
    const out = m.smooth(s.grown);
    return m.v3(m.lerp(SPROUT_W, 1, out), m.lerp(SPROUT_H, 1, up), m.lerp(SPROUT_W, 1, out));
  }
  pub fn def(s:*const Structure) Def { return defs.get(s.kind()); }
};

/// everything a structure's behaviour may touch.
pub const Ctx = struct {
  /// for a structure that puts another down (a polyp, its diamond)
  gpa:Allocator,
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

/// a hook result that may be an error union, as one
fn orFail(r:anytype) Allocator.Error!bool { return r; }

pub const Structures = struct {
  list:std.ArrayList(Structure) = .empty,

  pub fn deinit(ss:*Structures, gpa:Allocator) void { ss.list.deinit(gpa); }

  pub fn get(ss:*Structures, id:Id) *Structure { return &ss.list.items[id.idx()]; }

  pub fn canPlace(ss:*const Structures, w:*const World, wx:i32, wy:i32, k:Kind) bool {
    if (defs.get(k).floating) {
      // over any dry tile, whatever stands on it, but not over another
      const c = w.chunkOfTile(wx, wy) orelse return false;
      return c.kind[ck.localIndex(wx, wy)] != .water and ss.floaterAt(wx, wy) == null;
    }
    return switch (k) {
      inline else => |t| w.footprintFree(wx, wy, defs.get(t).size, if (comptime reg.has(t, "ground")) reg.module(t).ground else dry),
    };
  }

  pub fn place(ss:*Structures, gpa:Allocator, w:*World, wx:i32, wy:i32, k:Kind, dir:m.Dir, seed:f32) Allocator.Error!bool {
    if (!ss.canPlace(w, wx, wy, k)) return false;
    const idx = Id.of(ss.list.items.len);
    try ss.list.append(gpa, .{ .x = wx, .y = wy, .dir = dir, .seed = seed, .state = freshState(k) });
    if (!defs.get(k).floating) w.setFootprint(wx, wy, defs.get(k).size, Occ.structure(idx));
    return true;
  }

  /// a structure the gardener has just put down starts as a sprout.
  pub fn sprout(ss:*Structures, id:Id) void {
    const s = ss.get(id);
    if (s.def().grow > 0) s.grown = 0;
  }

  /// what stands at a tile: what floats over it first (it is drawn over
  /// whatever is under it), else what stands on it.
  pub fn at(ss:*const Structures, w:*const World, wx:i32, wy:i32) ?Id {
    return ss.floaterAt(wx, wy) orelse w.occAt(wx, wy).asStructure();
  }

  /// the floating structure over a tile; they are few, so the list is walked
  pub fn floaterAt(ss:*const Structures, wx:i32, wy:i32) ?Id {
    for (ss.list.items, 0..) |*s, i| if (s.def().floating and s.x == wx and s.y == wy) return Id.of(i);
    return null;
  }

  /// swap-remove; returns the removed structure so its contents can be refunded.
  /// note to CLAUDE, I changed the code, it is bad to do repeated get calls.
  pub fn remove(ss:*Structures, w:*World, id:Id) Structure {
    const s = ss.get(id).*;
    // calls should always be at the top;
    const stct = s.def();
    const idx = id.idx();
    if (!stct.floating) w.setFootprint(s.x, s.y, stct.size, .none);
    const last = ss.list.items.len - 1;
    if (idx != last) {
      const l = ss.list.items[last];
      const lstct = l.def();
      if (!lstct.floating) w.moveFootprint(l.x, l.y, lstct.size, Occ.structure(id));
    }
    _ = ss.list.swapRemove(idx);
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

  pub fn tick(ss:*Structures, gpa:Allocator, w:*World, plants:*Plants, g:*prog.Progression, dt:f32) Allocator.Error!void {
    const ctx:Ctx = .{ .gpa = gpa, .w = w, .plants = plants, .g = g, .ss = ss };
    for (0..ss.list.items.len) |idx| {
      const id = Id.of(idx);
      const g0 = ss.get(id);
      const active = if (g0.grown < 1) blk: {
        g0.grown = @min(1, g0.grown + dt / g0.def().grow);
        break :blk false;
      } else switch (g0.kind()) {
        // a tick that may put something down can fail for room
        inline else => |k| if (comptime reg.has(k, "tick")) try orFail(reg.module(k).tick(ctx, id, dt)) else false,
      };
      const s = ss.get(id);
      s.activity += ((if (active) @as(f32, 1) else 0) - s.activity) * @min(1, dt * ACTIVITY_EASE);
    }
  }
};

/// a floating plant a structure draws in toward itself: how far along the
/// way it is (0 leaving its tile .. 1 there; the GPU moves it, see
/// common.glsl `haloSpiral`) and how high over the structure's ground it
/// is drawn to.
pub const Hold = struct { k:f32, seat:f32 };

/// every field of celestial energy a structure holds, into `out`.
pub fn fields(ss:*const Structures, gpa:Allocator, out:*std.ArrayList(Field)) Allocator.Error!void {
  out.clearRetainingCapacity();
  for (ss.list.items) |*s| switch (s.kind()) {
    inline else => |k| if (comptime reg.has(k, "field")) if (reg.module(k).field(s)) |f| try out.append(gpa, f),
  };
}

/// the structure drawing the floater at a tile toward itself, if any.
pub fn hold(ss:*const Structures, wx:i32, wy:i32) ?struct { s:*const Structure, h:Hold } {
  for (ss.list.items) |*s| switch (s.kind()) {
    inline else => |k| if (comptime reg.has(k, "hold")) if (reg.module(k).hold(s, wx, wy)) |h| return .{ .s = s, .h = h },
  };
  return null;
}

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

/// draws kind `k`'s bulb in the HUD, its seed tinted `col`.
pub fn icon(k:Kind, ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  switch (k) {
    inline else => |t| if (comptime reg.has(t, "icon")) try reg.module(t).icon(ic, col) else try icon_kit.plain(ic, col),
  }
}

/// take one ripe unit of a mature plant's yield (plants never set seed).
pub fn harvestOne(plants:*Plants, id:PlantId) ?items.Item {
  const p = id.idx();
  const s = plants.list.slice();
  if (s.items(.growth)[p] < 1 or s.items(.essence)[p] < 1) return null;
  s.items(.essence)[p] -= 1;
  return species.get(s.items(.sp)[p]).yields;
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
  for (0..200) |_| try ss.tick(gpa, &w, &plants, &g, 0.05);
  const cache = ss.at(&w, 3, 0).?;
  try testing.expectEqual(@as(u32, 3), ss.get(cache).inv.count(.essence));
  // removing the middle conduit keeps the others addressable
  _ = ss.remove(&w, ss.at(&w, 1, 0).?);
  try testing.expect(ss.get(ss.at(&w, 3, 0).?).kind() == .sap_cache);
}
test "a conduit's side root reaches a plant beside it and harvests it" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..3) |x| for (0..2) |y| { const t = y * ck.SIZE + x; c.kind[t] = .soil; c.height[t] = 1; c.res[t] = 0; };
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  // conduit -> cache along +x, a mature plant beside the conduit (+y)
  try testing.expect(try plants.placeEx(gpa, &w, 1, 1, .{ .x = 1, .y = 1, .chunk = undefined, .tile = undefined, .sp = .lumenroot, .seed = 0, .growth = 1, .essence = 2 }));
  try testing.expect(try ss.place(gpa, &w, 1, 0, .conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 0, .sap_cache, 0, 0));
  // nothing moves until the root has grown out to it
  try ss.tick(gpa, &w, &plants, &g, 0.05);
  try testing.expect(ss.get(ss.at(&w, 1, 0).?).state.conduit.held == null);
  for (0..200) |_| try ss.tick(gpa, &w, &plants, &g, 0.05);
  try testing.expectEqual(@as(u32, 2), ss.get(ss.at(&w, 2, 0).?).inv.count(.essence));
}

test "a structure put down grows before it works" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..2) |x| for (0..2) |y| { const t = y * ck.SIZE + x; c.kind[t] = .soil; c.height[t] = 1; c.res[t] = 0; };
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 0, 0, .germinator, 0, 0));
  const id = ss.at(&w, 0, 0).?;
  ss.sprout(id);
  try testing.expectEqual(@as(f32, 0), ss.get(id).grown);
  const secs = defs.get(.germinator).grow;
  var t:f32 = 0;
  while (t < secs * 0.5) : (t += 0.05) try ss.tick(gpa, &w, &plants, &g, 0.05);
  try testing.expect(ss.get(id).grown > 0.4 and ss.get(id).grown < 0.6);
  try testing.expect(ss.get(id).activity < 0.01);
  while (t < secs + 0.1) : (t += 0.05) try ss.tick(gpa, &w, &plants, &g, 0.05);
  try testing.expectEqual(@as(f32, 1), ss.get(id).grown);
}
