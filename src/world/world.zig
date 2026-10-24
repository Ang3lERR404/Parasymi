//! the infinite world: a sparse map of generated chunks streamed around a focus.
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const m = @import("../core/math.zig");
const ck = @import("chunk.zig");
const gen = @import("gen.zig");

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

  /// height of a loaded tile something can stand on (null over water or void).
  pub fn walkable(w:*const World, wx:i32, wy:i32) ?f32 {
    const c = w.chunkOfTile(wx, wy) orelse return null;
    const t = ck.localIndex(wx, wy);
    return if (c.kind[t] == .water) null else c.height[t];
  }

  /// a tile's height and whether it is water (generated when not loaded)
  fn tileH(w:*const World, wx:i32, wy:i32) struct { h:f32, wet:bool } {
    if (w.chunkOfTile(wx, wy)) |c| {
      const t = ck.localIndex(wx, wy);
      return .{.h = c.height[t], .wet = c.kind[t] == .water};
    }
    const s = gen.sample(w.seed, wx, wy);
    return .{.h = s.height, .wet = s.kind == .water};
  }

  /// the ground's height at a corner where four tiles meet (the corner at
  /// the low x/z of tile (wx, wy)): the land's average, just under the
  /// water at a shore, the water's level in open water
  fn cornerH(w:*const World, wx:i32, wy:i32) f32 {
    var h:f32 = 0;
    var land:f32 = 0;
    var wet = false;
    for ([_][2]i32{.{-1, -1}, .{0, -1}, .{-1, 0}, .{0, 0}}) |d| {
      const t = w.tileH(wx + d[0], wy + d[1]);
      if (t.wet) {
        wet = true;
        continue;
      }
      h += t.h;
      land += 1;
    }
    if (land == 0) return gen.WATER_H;
    return if (wet) gen.SHORE else h / land;
  }

  /// the ground's height at (x, z) as it is drawn (render/terrain_mesh):
  /// each tile a fan of four triangles from its centre, at its own height,
  /// to its corners, shared with its neighbours; water flat. Whatever
  /// stands on the ground (the wolf's paws) stands on this, not on the tile.
  pub fn surfaceAt(w:*const World, x:f32, z:f32) f32 {
    const wx = m.tileOf(x);
    const wy = m.tileOf(z);
    const c = w.tileH(wx, wy);
    if (c.wet) return c.h;
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
  /// anchor and passes `ok` (e.g. fertile for roots, dry for structures).
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

  /// the chunk at `at`, generating it first if it is not resident.
  pub fn ensure(w:*World, at:Coord) Error!*Chunk { return w.map.get(at) orelse w.load(at); }

  /// generate missing chunks nearest-first, at most `budget` per call.
  pub fn stream(w:*World, focus:Coord, radius:i32, budget:u32) Error!void {
    w.fresh.clearRetainingCapacity();
    var r:i32 = 0;
    while (r <= radius) : (r += 1) {
      var it = m.ring(r);
      while (it.next()) |o| {
        const at:Coord = .{.x = focus.x + o[0], .y = focus.y + o[1]};
        if (w.map.contains(at)) continue;
        if (w.fresh.items.len >= budget) return;
        _ = try w.load(at);
      }
    }
  }

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
      if (t.wet) continue;
      // either side of a shared edge, and at a corner, the tiles agree
      const e = 1e-4;
      try testing.expectApproxEqAbs(w.surfaceAt(m.f(wx) + 0.3, m.f(wy) - e), w.surfaceAt(m.f(wx) + 0.3, m.f(wy) + e), 1e-3);
      try testing.expectApproxEqAbs(w.surfaceAt(m.f(wx) - e, m.f(wy) + 0.7), w.surfaceAt(m.f(wx) + e, m.f(wy) + 0.7), 1e-3);
      try testing.expectApproxEqAbs(w.cornerH(wx, wy), w.surfaceAt(m.f(wx) + e, m.f(wy) + e), 1e-3);
    }
  }
}
