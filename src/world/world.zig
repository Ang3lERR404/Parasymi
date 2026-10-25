//! the infinite world: a sparse map of generated chunks streamed around a focus.
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const m = @import("../core/math.zig");
const ck = @import("chunk.zig");
const gen = @import("gen.zig");
const jobs = @import("../core/jobs.zig");
const Io = std.Io;

pub const Chunk = ck.Chunk;
pub const Coord = ck.Coord;
pub const Occ = ck.Occ;
const Error = Allocator.Error;

pub const World = struct {
  gpa:Allocator,
  seed:u64,
  map:std.AutoHashMapUnmanaged(Coord, *Chunk) = .empty,
  /// chunks loaded by the last `stream` call.
  fresh:std.ArrayList(*Chunk) = .empty,
  /// gpu slots of chunks that were unloaded; the renderer drains this.
  evicted:std.ArrayList(ck.MeshSlot) = .empty,
  /// the thread pool work on the world is split over (chunks generated,
  /// meshed, plants relinked); none (headless) does it all in place.
  // decision: the pool rides on the world, which every such caller holds,
  // set by main once the game is made or loaded
  io:?Io = null,

  pub fn init(gpa:Allocator, seed:u64) World { return .{.gpa = gpa, .seed = seed}; }

  pub fn deinit(w:*World) void {
    var it = w.map.valueIterator();
    while (it.next()) |c| w.gpa.destroy(c.*);
    w.map.deinit(w.gpa);
    w.fresh.deinit(w.gpa);
    w.evicted.deinit(w.gpa);
  }

  pub fn get(w:*const World, at:Coord) ?*Chunk { return w.map.get(at); }

  pub fn chunkOfTile(w:*const World, wx:i32, wy:i32) ?*Chunk { return w.map.get(Coord.ofTile(wx, wy)); }

  /// occupant of a tile (none if empty or not loaded).
  pub fn occAt(w:*const World, wx:i32, wy:i32) Occ {
    const c = w.chunkOfTile(wx, wy) orelse return .none;
    return c.occ[ck.localIndex(wx, wy)];
  }

  /// claim (or release, with .none) a size x size footprint anchored at
  /// (wx, wy), pinning/unpinning each chunk once per tile.
  pub fn setFootprint(w:*World, wx:i32, wy:i32, size:u8, o:Occ) void {
    var it = m.footprint(wx, wy, size);
    while (it.next()) |p| {
      const c = w.chunkOfTile(p[0], p[1]) orelse continue;
      const t = ck.localIndex(p[0], p[1]);
      if (c.occ[t] == .none and o != .none) c.pins += 1;
      if (c.occ[t] != .none and o == .none) c.pins -= 1;
      c.occ[t] = o;
    }
  }

  /// re-point an existing footprint at a new occupant id (after a swap-remove).
  pub fn moveFootprint(w:*World, wx:i32, wy:i32, size:u8, o:Occ) void {
    var it = m.footprint(wx, wy, size);
    while (it.next()) |p| {
      if (w.chunkOfTile(p[0], p[1])) |c| c.occ[ck.localIndex(p[0], p[1])] = o;
    }
  }

  /// height of a loaded tile something can stand on (null over void).
  pub fn walkable(w:*const World, wx:i32, wy:i32) ?f32 {
    const c = w.chunkOfTile(wx, wy) orelse return null;
    return c.height[ck.localIndex(wx, wy)];
  }

  /// a tile's height (generated when not loaded)
  fn tileH(w:*const World, wx:i32, wy:i32) struct { h:f32 } {
    if (w.chunkOfTile(wx, wy)) |c| return .{.h = c.height[ck.localIndex(wx, wy)]};
    return .{.h = gen.sample(w.seed, wx, wy).height};
  }

  /// the ground's height at a corner where four tiles meet (the corner at
  /// the low x/z of tile (wx, wy)): their average
  fn cornerH(w:*const World, wx:i32, wy:i32) f32 {
    var h:f32 = 0;
    for ([_][2]i32{.{-1, -1}, .{0, -1}, .{-1, 0}, .{0, 0}}) |d| h += w.tileH(wx + d[0], wy + d[1]).h;
    return h / 4;
  }

  /// the ground's height at (x, z) as it is drawn (render/terrain_mesh):
  /// each tile a fan of four triangles from its centre, at its own height,
  /// to its corners, shared with its neighbours. Whatever stands on the
  /// ground (the wolf's paws) stands on this, not on the tile.
  pub fn surfaceAt(w:*const World, x:f32, z:f32) f32 {
    const wx = m.tileOf(x);
    const wy = m.tileOf(z);
    const c = w.tileH(wx, wy);
    const dx = x - m.f(wx) - 0.5;
    const dz = z - m.f(wy) - 0.5;
    const ax = @abs(dx);
    const az = @abs(dz);
    if (ax < 1e-6 and az < 1e-6) return c.h;
    // which triangle of the fan (the edge it faces), how far out toward
    // that edge (0 centre .. 1 edge) and where along it (0..1)
    const across = ax >= az;
    const e0:f32, const e1:f32 = if (across) blk: {
      const ex = if (dx < 0) wx else wx + 1;
      break :blk .{w.cornerH(ex, wy), w.cornerH(ex, wy + 1)};
    } else blk: {
      const ey = if (dz < 0) wy else wy + 1;
      break :blk .{w.cornerH(wx, ey), w.cornerH(wx + 1, ey)};
    };
    const s = 2 * @max(ax, az);
    const v = if (across) dz / ax * 0.5 + 0.5 else dx / az * 0.5 + 0.5;
    return m.lerp(c.h, m.lerp(e0, e1, v), s);
  }

  /// a footprint is free if every tile is loaded, unoccupied, level with the
  /// anchor and passes `ok` (e.g. fertile for roots).
  pub fn footprintFree(w:*const World, wx:i32, wy:i32, size:u8, comptime ok:fn (ck.Kind) bool) bool {
    const c0 = w.chunkOfTile(wx, wy) orelse return false;
    const h0 = c0.height[ck.localIndex(wx, wy)];
    var it = m.footprint(wx, wy, size);
    while (it.next()) |p| {
      const c = w.chunkOfTile(p[0], p[1]) orelse return false;
      const t = ck.localIndex(p[0], p[1]);
      if (c.occ[t] != .none or !ok(c.kind[t]) or c.height[t] != h0) return false;
    }
    return true;
  }

  fn load(w:*World, at:Coord) Error!*Chunk {
    const c = try w.gpa.create(Chunk);
    errdefer w.gpa.destroy(c);
    c.* = ck.blank(at);
    gen.generate(w.seed, c);
    try w.map.put(w.gpa, at, c);
    try w.fresh.append(w.gpa, c);
    return c;
  }

  /// resident chunks whose ground is not meshed yet (or has changed since).
  pub fn unmeshed(w:*const World) u32 {
    var n:u32 = 0;
    var it = w.map.valueIterator();
    while (it.next()) |c| n += @intFromBool(c.*.dirty);
    return n;
  }

  /// the chunk at `at`, generating it first if it is not resident.
  pub fn ensure(w:*World, at:Coord) Error!*Chunk { return w.map.get(at) orelse w.load(at); }

  /// generate missing chunks nearest-first, at most `budget` per call: made
  /// blank here, generated together over the pool (each fills only itself)
  pub fn stream(w:*World, focus:Coord, radius:i32, budget:u32) Error!void {
    w.fresh.clearRetainingCapacity();
    errdefer {
      for (w.fresh.items) |c| w.gpa.destroy(c);
      w.fresh.clearRetainingCapacity();
    }
    var r:i32 = 0;
    rings: while (r <= radius) : (r += 1) {
      var it = m.ring(r);
      while (it.next()) |o| {
        const at:Coord = .{.x = focus.x + o[0], .y = focus.y + o[1]};
        if (w.map.contains(at)) continue;
        if (w.fresh.items.len >= budget) break :rings;
        try w.fresh.ensureUnusedCapacity(w.gpa, 1);
        const c = try w.gpa.create(Chunk);
        c.* = ck.blank(at);
        w.fresh.appendAssumeCapacity(c);
      }
    }
    const made = w.fresh.items;
    try w.map.ensureUnusedCapacity(w.gpa, @intCast(made.len));
    jobs.each(w.io, made.len, 1, Generate, .{.seed = w.seed, .cs = made}, Generate.run);
    for (made) |c| w.map.putAssumeCapacityNoClobber(c.at, c);
  }

  /// one range of fresh chunks generated
  const Generate = struct {
    seed:u64,
    cs:[]const *Chunk,

    fn run(g:Generate, lo:usize, hi:usize) void { for (g.cs[lo..hi]) |c| gen.generate(g.seed, c); }
  };

  /// unpinned chunks well outside `radius`, ready to `unload`.
  pub fn far(w:*World, focus:Coord, radius:i32, out:*std.ArrayList(*Chunk)) Error!void {
    out.clearRetainingCapacity();
    const keep = radius + 2;
    var it = w.map.valueIterator();
    while (it.next()) |cp| {
      const c = cp.*;
      if (c.pins > 0) continue;
      if (@max(@abs(c.at.x - focus.x), @abs(c.at.y - focus.y)) > keep) try out.append(w.gpa, c);
    }
  }

  pub fn unload(w:*World, c:*Chunk) Error!void {
    assert(c.pins == 0);
    _ = w.map.remove(c.at);
    if (c.gpu_slot) |s| try w.evicted.append(w.gpa, s);
    w.gpa.destroy(c);
  }
};

test "stream loads and unloads" {
  var w = World.init(testing.allocator, 9);
  defer w.deinit();
  try w.stream(.{.x = 0, .y = 0}, 1, 100);
  try testing.expectEqual(@as(u32, 9), w.map.count());
  var far:std.ArrayList(*Chunk) = .empty;
  defer far.deinit(testing.allocator);
  try w.far(.{.x = 50, .y = 0}, 0, &far);
  try testing.expectEqual(@as(usize, 9), far.items.len);
  for (far.items) |c| try w.unload(c);
  try testing.expectEqual(@as(u32, 0), w.map.count());
}

test "the drawn ground meets each tile's height at its centre and runs on unbroken" {
  // unloaded: every height comes from the generator, as the mesh's border does
  const w = World.init(testing.allocator, 9);
  var wy:i32 = -6;
  while (wy < 6) : (wy += 1) {
    var wx:i32 = -6;
    while (wx < 6) : (wx += 1) {
      const t = w.tileH(wx, wy);
      try testing.expectApproxEqAbs(t.h, w.surfaceAt(m.f(wx) + 0.5, m.f(wy) + 0.5), 1e-5);
      // either side of a shared edge, and at a corner, the tiles agree
      const e = 1e-4;
      try testing.expectApproxEqAbs(w.surfaceAt(m.f(wx) + 0.3, m.f(wy) - e), w.surfaceAt(m.f(wx) + 0.3, m.f(wy) + e), 1e-3);
      try testing.expectApproxEqAbs(w.surfaceAt(m.f(wx) - e, m.f(wy) + 0.7), w.surfaceAt(m.f(wx) + e, m.f(wy) + 0.7), 1e-3);
      try testing.expectApproxEqAbs(w.cornerH(wx, wy), w.surfaceAt(m.f(wx) + e, m.f(wy) + e), 1e-3);
    }
  }
}

test "chunks generated over the pool match those made one by one" {
  var a = World.init(testing.allocator, 9);
  defer a.deinit();
  var b = World.init(testing.allocator, 9);
  defer b.deinit();
  b.io = testing.io;
  try a.stream(.{.x = 0, .y = 0}, 2, 100);
  try b.stream(.{.x = 0, .y = 0}, 2, 100);
  try testing.expectEqual(a.map.count(), b.map.count());
  var it = a.map.valueIterator();
  while (it.next()) |c| {
    const d = b.get(c.*.at).?;
    try testing.expectEqualSlices(f32, &c.*.height, &d.height);
    try testing.expectEqualSlices(ck.Kind, &c.*.kind, &d.kind);
    try testing.expectEqualSlices(f32, &c.*.ley, &d.ley);
  }
}
