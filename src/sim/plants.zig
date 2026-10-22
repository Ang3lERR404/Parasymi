//! plant storage: one struct-of-arrays for every living plant in the world.
//! Rooted plants claim a size x size footprint of tiles (see world occupancy);
//! floating plants claim none and are tracked by the tile they hover over.
//! Neighbour links are cached as plain indices and rebuilt only when the
//! topology changes, so the per-tick ecology loop never touches a hash map.
const std = @import("std");
const ck = @import("../world/chunk.zig");
const World = @import("../world/world.zig").World;
const species = @import("species.zig");

pub const NONE = ck.NONE;
const Occ = ck.Occ;
/// neighbours touching the footprint (ring 1) and one tile further (ring 2).
pub const R1 = 12;
pub const R2 = 20;

pub const Plant = struct {
  /// anchor tile (top-left of the footprint, or the tile hovered over)
  x:i32, y:i32,
  chunk:*ck.Chunk,
  tile:u16,
  sp:species.Id,
  growth:f32 = 0,
  mana:f32 = 1,
  health:f32 = 1,
  /// 0..1 random, drives animation phase and mesh variation.
  seed:f32,
  /// smoothed magnitude of mana moving through the plant (animation/glow).
  flow:f32 = 0,
  /// harvestable stores: the species' yield condensed from mana, and ripening seeds.
  essence:f32 = 0,
  seeds:f32 = 0,
  n1:[R1]u32 = @splat(NONE),
  n2:[R2]u32 = @splat(NONE),
};

pub const Plants = struct {
  list:std.MultiArrayList(Plant) = .empty,
  floaters:std.AutoHashMapUnmanaged([2]i32, u32) = .empty,
  topology_dirty:bool = false,

  pub fn deinit(p:*Plants, gpa:std.mem.Allocator) void {
    p.list.deinit(gpa);
    p.floaters.deinit(gpa);
  }
  pub fn len(p:*const Plants) usize { return p.list.len; }

  pub fn canPlace(p:*const Plants, w:*const World, wx:i32, wy:i32, sp:species.Id) bool {
    const def = species.get(sp);
    if (def.floating) return w.chunkOfTile(wx, wy) != null and !p.floaters.contains(.{wx, wy});
    return w.footprintFree(wx, wy, def.size, ck.Kind.fertile);
  }

  pub fn place(p:*Plants, gpa:std.mem.Allocator, w:*World, wx:i32, wy:i32, sp:species.Id, seed:f32) !bool {
    return p.placeEx(gpa, w, wx, wy, .{.sp = sp, .seed = seed, .x = wx, .y = wy, .chunk = undefined, .tile = undefined});
  }

  /// place a fully specified plant (x/y/chunk/tile are filled in here).
  pub fn placeEx(p:*Plants, gpa:std.mem.Allocator, w:*World, wx:i32, wy:i32, proto:Plant) !bool {
    if (!p.canPlace(w, wx, wy, proto.sp)) return false;
    const def = species.get(proto.sp);
    const c = w.chunkOfTile(wx, wy).?;
    const idx:u32 = @intCast(p.list.len);
    var pl = proto;
    pl.x = wx;
    pl.y = wy;
    pl.chunk = c;
    pl.tile = @intCast(ck.localIndex(wx, wy));
    try p.list.append(gpa, pl);
    if (def.floating) {
      try p.floaters.put(gpa, .{wx, wy}, idx);
      c.pins += 1;
    } else w.setFootprint(wx, wy, def.size, Occ.plant(idx));
    p.topology_dirty = true;
    return true;
  }

  /// the plant at a tile: a rooted one first, else one floating over it.
  pub fn at(p:*const Plants, w:*const World, wx:i32, wy:i32) ?u32 {
    const o = w.occAt(wx, wy);
    if (Occ.isPlant(o)) return Occ.index(o);
    return p.floaters.get(.{wx, wy});
  }

  pub fn removeAt(p:*Plants, w:*World, wx:i32, wy:i32) bool {
    const i = p.at(w, wx, wy) orelse return false;
    p.remove(w, i);
    return true;
  }

  /// swap-remove; re-points the footprint of the plant that moved into slot `i`.
  pub fn remove(p:*Plants, w:*World, i:u32) void {
    const s = p.list.slice();
    const def = species.get(s.items(.sp)[i]);
    if (def.floating) {
      _ = p.floaters.remove(.{s.items(.x)[i], s.items(.y)[i]});
      s.items(.chunk)[i].pins -= 1;
    } else w.setFootprint(s.items(.x)[i], s.items(.y)[i], def.size, NONE);
    const last:u32 = @intCast(p.list.len - 1);
    if (i != last) {
      const ld = species.get(s.items(.sp)[last]);
      const lx = s.items(.x)[last];
      const ly = s.items(.y)[last];
      if (ld.floating) p.floaters.getPtr(.{lx, ly}).?.* = i
      else w.moveFootprint(lx, ly, ld.size, Occ.plant(i));
    }
    p.list.swapRemove(i);
    p.topology_dirty = true;
  }

  /// world-space centre of a plant's footprint (x, z).
  pub fn centre(p:*const Plants, i:usize) [2]f32 {
    const s = p.list.slice();
    const size:f32 = @floatFromInt(species.get(s.items(.sp)[i]).size);
    return .{@as(f32, @floatFromInt(s.items(.x)[i])) + size / 2, @as(f32, @floatFromInt(s.items(.y)[i])) + size / 2};
  }

  pub fn rebuildLinks(p:*Plants, w:*World) void {
    const s = p.list.slice();
    const xs = s.items(.x);
    const ys = s.items(.y);
    const sps = s.items(.sp);
    const n1 = s.items(.n1);
    const n2 = s.items(.n2);
    const any_floaters = p.floaters.count() > 0;
    for (0..p.list.len) |i| {
      n1[i] = @splat(NONE);
      n2[i] = @splat(NONE);
      const def = species.get(sps[i]);
      const size:i32 = if (def.floating) 1 else def.size;
      var dy:i32 = -2;
      while (dy < size + 2) : (dy += 1) {
        var dx:i32 = -2;
        while (dx < size + 2) : (dx += 1) {
          const rx = if (dx < 0) -dx else if (dx >= size) dx - size + 1 else 0;
          const ry = if (dy < 0) -dy else if (dy >= size) dy - size + 1 else 0;
          // tiles under the footprint count as touching (a floater over a root)
          const ring = @max(@max(rx, ry), 1);
          const wx = xs[i] + dx;
          const wy = ys[i] + dy;
          const o = w.occAt(wx, wy);
          if (Occ.isPlant(o)) link(n1, n2, i, Occ.index(o), ring);
          if (any_floaters) if (p.floaters.get(.{wx, wy})) |f| link(n1, n2, i, f, ring);
        }
      }
    }
    p.topology_dirty = false;
  }

  fn link(n1:[][R1]u32, n2:[][R2]u32, i:usize, j:u32, ring:i32) void {
    if (j == i) return;
    // a multi-tile neighbour shows up on several tiles: keep it once, in the nearest ring
    for (n1[i]) |e| if (e == j) return;
    if (ring == 1) {
      for (&n2[i]) |*e| if (e.* == j) { e.* = NONE; };
      compact(&n2[i]);
      put(&n1[i], j);
    } else {
      for (n2[i]) |e| if (e == j) return;
      put(&n2[i], j);
    }
  }
  fn put(arr:anytype, j:u32) void {
    for (arr) |*e| if (e.* == NONE) { e.* = j; return; };
  }
  fn compact(arr:anytype) void {
    var k:usize = 0;
    for (arr.*) |e| if (e != NONE) { arr[k] = e; k += 1; };
    while (k < arr.len) : (k += 1) arr[k] = NONE;
  }
};

test "footprints, floaters and links" {
  const gpa = std.testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{.x = 0, .y = 0}, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..5) |y| for (0..5) |x| { c.kind[y * ck.SIZE + x] = .soil; c.height[y * ck.SIZE + x] = 1; };
  var p:Plants = .{};
  defer p.deinit(gpa);
  try std.testing.expect(try p.place(gpa, &w, 1, 1, .hollowheart, 0.5));
  // the heart covers (1..2, 1..2): nothing else may root there
  try std.testing.expect(!try p.place(gpa, &w, 2, 2, .lumenroot, 0.5));
  try std.testing.expect(try p.place(gpa, &w, 3, 1, .lumenroot, 0.5));
  // a floater may hover over the heart itself, but not over another floater
  try std.testing.expect(try p.place(gpa, &w, 2, 2, .driftwisp, 0.5));
  try std.testing.expect(!try p.place(gpa, &w, 2, 2, .driftwisp, 0.5));
  p.rebuildLinks(&w);
  var links:usize = 0;
  for (p.list.items(.n1)[0]) |e| if (e != NONE) { links += 1; };
  try std.testing.expectEqual(@as(usize, 2), links);
  // 4 heart tiles + 1 root + 1 floater
  try std.testing.expectEqual(@as(u32, 6), c.pins);
  p.remove(&w, 0);
  try std.testing.expectEqual(@as(u32, 2), c.pins);
  try std.testing.expect(p.at(&w, 3, 1) != null and p.at(&w, 2, 2) != null);
}
