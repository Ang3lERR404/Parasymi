//! plant storage: one struct-of-arrays for every living plant in the world.
//! Rooted plants claim a size x size footprint of tiles (see world occupancy);
//! floating plants claim none and are tracked by the tile they hover over.
//! Neighbour links are cached as plain indices and rebuilt only when the
//! topology changes, so the per-tick ecology loop never touches a hash map.
const std = @import("std");
const m = @import("engine").core.math;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const indexOfScalar = std.mem.indexOfScalar;
const ck = @import("../world/chunk.zig");
const World = @import("../world/world.zig").World;
const species = @import("species.zig");
const jobs = @import("engine").core.jobs;
const Turn = @import("turn.zig").Turn;

pub const Id = ck.PlantId;
const Occ = ck.Occ;
const Error = Allocator.Error;
/// neighbours touching the footprint (ring 1) and one tile further (ring 2).
pub const R1 = 12;
pub const R2 = 20;
/// fewer plants than this a thread are relinked in one go
const LINKS_MIN = 512;

/// a square of tiles: a footprint.
pub const Rect = struct {
  x:i32, y:i32, size:u8,

  /// Chebyshev tile distance between two squares: 0 when they overlap, 1
  /// when they touch, 2 with one tile between them.
  pub fn gap(a:Rect, b:Rect) i32 {
    const dx = @max(0, @max(b.x - (a.x + a.size - 1), a.x - (b.x + b.size - 1)));
    const dy = @max(0, @max(b.y - (a.y + a.size - 1), a.y - (b.y + b.size - 1)));
    return @max(dx, dy);
  }
};

pub const Plant = struct {
  /// anchor tile (top-left of the footprint, or the tile hovered over)
  x:i32, y:i32,
  chunk:*ck.Chunk,
  tile:u16,
  sp:species.Id,
  growth:f32 = 0,
  /// seconds to maturity at full mana, when not the species' own (0).
  span:f32 = 0,
  mana:f32 = 1,
  health:f32 = 1,
  /// 0..1 random, drives animation phase and mesh variation.
  seed:f32,
  /// smoothed magnitude of mana moving through the plant (animation/glow).
  flow:f32 = 0,
  /// harvestable store: the species' yield condensed from mana.
  essence:f32 = 0,
  /// the way it was turned to (R), and how it got there
  dir:m.Dir = 0,
  turn:Turn = .{},
  n1:[R1]Id = @splat(.none),
  n2:[R2]Id = @splat(.none),
};

pub const Plants = struct {
  list:std.MultiArrayList(Plant) = .empty,
  floaters:std.AutoHashMapUnmanaged([2]i32, Id) = .empty,
  topology_dirty:bool = false,

  pub fn deinit(p:*Plants, gpa:Allocator) void {
    p.list.deinit(gpa);
    p.floaters.deinit(gpa);
  }
  pub fn len(p:*const Plants) usize { return p.list.len; }

  pub fn canPlace(p:*const Plants, w:*const World, wx:i32, wy:i32, sp:species.Id) bool {
    const def = species.get(sp);
    if (def.floating) return w.chunkOfTile(wx, wy) != null and !p.floaters.contains(.{wx, wy});
    return w.footprintFree(wx, wy, def.size, ck.Kind.fertile);
  }

  pub fn place(p:*Plants, gpa:Allocator, w:*World, wx:i32, wy:i32, sp:species.Id, seed:f32) Error!bool {
    return p.placeEx(gpa, w, wx, wy, .{.sp = sp, .seed = seed, .x = wx, .y = wy, .chunk = undefined, .tile = undefined});
  }

  /// place a fully specified plant (x/y/chunk/tile are filled in here).
  pub fn placeEx(p:*Plants, gpa:Allocator, w:*World, wx:i32, wy:i32, proto:Plant) Error!bool {
    if (!p.canPlace(w, wx, wy, proto.sp)) return false;
    const def = species.get(proto.sp);
    const c = w.chunkOfTile(wx, wy).?;
    const idx = Id.of(p.list.len);
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
  pub fn at(p:*const Plants, w:*const World, wx:i32, wy:i32) ?Id {
    if (w.occAt(wx, wy).asPlant()) |i| return i;
    return p.floaters.get(.{wx, wy});
  }

  pub fn removeAt(p:*Plants, w:*World, wx:i32, wy:i32) bool {
    const i = p.at(w, wx, wy) orelse return false;
    p.remove(w, i);
    return true;
  }

  /// swap-remove; re-points the footprint of the plant that moved into slot `i`.
  pub fn remove(p:*Plants, w:*World, id:Id) void {
    const i = id.idx();
    const s = p.list.slice();
    const def = species.get(s.items(.sp)[i]);
    if (def.floating) {
      _ = p.floaters.remove(.{s.items(.x)[i], s.items(.y)[i]});
      s.items(.chunk)[i].pins -= 1;
    } else w.setFootprint(s.items(.x)[i], s.items(.y)[i], def.size, .none);
    const last = p.list.len - 1;
    if (i != last) {
      const ld = species.get(s.items(.sp)[last]);
      const lx = s.items(.x)[last];
      const ly = s.items(.y)[last];
      if (ld.floating) p.floaters.getPtr(.{lx, ly}).?.* = id
      else w.moveFootprint(lx, ly, ld.size, Occ.plant(id));
    }
    p.list.swapRemove(i);
    // links stay valid without waiting for a rebuild: the removed plant
    // drops out of every ring, and the plant that moved into its slot is
    // found there (readers outside the tick, e.g. harvesting, rely on this)
    const moved = Id.of(last);
    const s2 = p.list.slice();
    for (s2.items(.n1)) |*ring| relink(ring, id, moved);
    for (s2.items(.n2)) |*ring| relink(ring, id, moved);
    p.topology_dirty = true;
  }

  /// drop `gone` from a ring and re-point `from` at `gone`'s slot, keeping
  /// the ring packed (readers stop at the first `.none`).
  fn relink(ring:[]Id, gone:Id, from:Id) void {
    var k:usize = 0;
    for (ring) |e| {
      if (e == .none) break;
      if (e == gone) continue;
      ring[k] = if (e == from) gone else e;
      k += 1;
    }
    while (k < ring.len and ring[k] != .none) : (k += 1) ring[k] = .none;
  }

  /// the tiles a plant covers: its footprint, or the one tile it hovers over.
  pub fn extent(p:*const Plants, i:usize) Rect {
    const s = p.list.slice();
    const def = species.get(s.items(.sp)[i]);
    return .{.x = s.items(.x)[i], .y = s.items(.y)[i], .size = if (def.floating) 1 else def.size};
  }

  /// world-space centre of a plant's footprint (x, z).
  pub fn centre(p:*const Plants, i:usize) [2]f32 {
    const s = p.list.slice();
    const c = m.footprintCentre(s.items(.x)[i], s.items(.y)[i], species.get(s.items(.sp)[i]).size, 0);
    return .{c[0], c[2]};
  }

  pub fn rebuildLinks(p:*Plants, w:*World) void {
    // each plant fills only its own rows, so they are split over the pool
    jobs.each(w.io, p.list.len, LINKS_MIN, Relink, .{.p = p, .w = w}, Relink.run);
    p.topology_dirty = false;
  }

  /// one range of plants' neighbour rows, made afresh from occupancy
  const Relink = struct {
    p:*const Plants,
    w:*const World,

    fn run(r:Relink, lo:usize, hi:usize) void {
      const p = r.p;
      const w = r.w;
      const s = p.list.slice();
      const xs = s.items(.x);
      const ys = s.items(.y);
      const sps = s.items(.sp);
      const n1 = s.items(.n1);
      const n2 = s.items(.n2);
      const any_floaters = p.floaters.count() > 0;
      for (lo..hi) |i| {
        n1[i] = @splat(.none);
        n2[i] = @splat(.none);
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
            if (w.occAt(wx, wy).asPlant()) |j| link(n1, n2, i, j, ring);
            if (any_floaters) if (p.floaters.get(.{wx, wy})) |f| link(n1, n2, i, f, ring);
          }
        }
      }
    }
  };

  fn link(n1:[][R1]Id, n2:[][R2]Id, i:usize, j:Id, ring:i32) void {
    if (j.idx() == i) return;
    // a multi-tile neighbour shows up on several tiles: keep it once, in the nearest ring
    for (n1[i]) |e| if (e == j) return;
    if (ring == 1) {
      for (&n2[i]) |*e| if (e.* == j) { e.* = .none; };
      compact(&n2[i]);
      put(&n1[i], j);
    } else {
      for (n2[i]) |e| if (e == j) return;
      put(&n2[i], j);
    }
  }
  fn put(arr:[]Id, j:Id) void {
    for (arr) |*e| if (e.* == .none) { e.* = j; return; };
  }
  fn compact(arr:[]Id) void {
    var k:usize = 0;
    for (arr) |e| if (e != .none) { arr[k] = e; k += 1; };
    while (k < arr.len) : (k += 1) arr[k] = .none;
  }
};

test "footprints, floaters and links" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{.x = 0, .y = 0}, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..5) |y| for (0..5) |x| { c.kind[y * ck.SIZE + x] = .soil; c.height[y * ck.SIZE + x] = 1; };
  var p:Plants = .{};
  defer p.deinit(gpa);
  try testing.expect(try p.place(gpa, &w, 1, 1, .hollowheart, 0.5));
  // the heart covers (1..2, 1..2): nothing else may root there
  try testing.expect(!try p.place(gpa, &w, 2, 2, .lumenroot, 0.5));
  try testing.expect(try p.place(gpa, &w, 3, 1, .lumenroot, 0.5));
  // a floater may hover over the heart itself, but not over another floater
  try testing.expect(try p.place(gpa, &w, 2, 2, .driftwisp, 0.5));
  try testing.expect(!try p.place(gpa, &w, 2, 2, .driftwisp, 0.5));
  p.rebuildLinks(&w);
  var links:usize = 0;
  for (p.list.items(.n1)[0]) |e| if (e != .none) { links += 1; };
  try testing.expectEqual(@as(usize, 2), links);
  // 4 heart tiles + 1 root + 1 floater
  try testing.expectEqual(@as(u32, 6), c.pins);
  p.remove(&w, .of(0));
  try testing.expectEqual(@as(u32, 2), c.pins);
  try testing.expect(p.at(&w, 3, 1) != null and p.at(&w, 2, 2) != null);
}

test "links stay valid right after a remove, matching a rebuild" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{.x = 0, .y = 0}, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..6) |y| for (0..6) |x| { c.kind[y * ck.SIZE + x] = .soil; c.height[y * ck.SIZE + x] = 1; };
  var p:Plants = .{};
  defer p.deinit(gpa);
  // a 2x2 and a ring of 1x1s around it, plus a floater, all linked
  try testing.expect(try p.place(gpa, &w, 2, 2, .hollowheart, 0.5));
  for ([_][2]i32{.{1, 1}, .{4, 2}, .{2, 4}, .{1, 3}, .{4, 4}, .{0, 2}}) |t| try testing.expect(try p.place(gpa, &w, t[0], t[1], .lumenroot, 0.5));
  try testing.expect(try p.place(gpa, &w, 3, 3, .driftwisp, 0.5));
  // remove from the middle, from the front and the last slot, checking each time
  for ([_]usize{3, 0, 4}) |victim| {
    p.rebuildLinks(&w);
    p.remove(&w, .of(@min(victim, p.len() - 1)));
    const n = p.len();
    var got:[16][R1 + R2]Id = undefined;
    for (0..n) |i| {
      const s = p.list.slice();
      for (s.items(.n1)[i], 0..) |e, k| { if (e != .none) try testing.expect(e.idx() < n); got[i][k] = e; }
      for (s.items(.n2)[i], 0..) |e, k| { if (e != .none) try testing.expect(e.idx() < n); got[i][R1 + k] = e; }
    }
    // the patched links say exactly what a full rebuild says (as sets per ring)
    p.rebuildLinks(&w);
    const s = p.list.slice();
    for (0..n) |i| {
      for ([2][]const Id{got[i][0..R1], got[i][R1..]}, [2][]const Id{&s.items(.n1)[i], &s.items(.n2)[i]}) |a, b| {
        var ca:usize = 0;
        var cb:usize = 0;
        for (a) |e| if (e != .none) { ca += 1; try testing.expect(indexOfScalar(Id, b, e) != null); };
        for (b) |e| if (e != .none) { cb += 1; };
        try testing.expectEqual(cb, ca);
      }
    }
  }
}

test "links made over the pool match links made in place" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{.x = 0, .y = 0}, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (&c.kind, &c.height) |*k, *h| { k.* = .soil; h.* = 1; }
  var p:Plants = .{};
  defer p.deinit(gpa);
  // a chunk sown full (enough plants to split), a floater over every third
  for (0..ck.SIZE) |y| for (0..ck.SIZE) |x| {
    const wx:i32 = @intCast(x);
    const wy:i32 = @intCast(y);
    _ = try p.place(gpa, &w, wx, wy, .lumenroot, 0.5);
    if ((x + y) % 3 == 0) _ = try p.place(gpa, &w, wx, wy, .driftwisp, 0.5);
  };
  try testing.expect(p.len() > 2 * LINKS_MIN);
  p.rebuildLinks(&w);
  const n1 = try gpa.dupe([R1]Id, p.list.items(.n1));
  defer gpa.free(n1);
  const n2 = try gpa.dupe([R2]Id, p.list.items(.n2));
  defer gpa.free(n2);
  w.io = testing.io;
  p.rebuildLinks(&w);
  for (n1, p.list.items(.n1)) |a, b| try testing.expectEqualSlices(Id, &a, &b);
  for (n2, p.list.items(.n2)) |a, b| try testing.expectEqualSlices(Id, &a, &b);
}
