//! the infinite world: a sparse map of generated chunks streamed around a focus.
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const testing = std.testing;
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
    for (0..size) |dy| for (0..size) |dx| {
      const x = wx + @as(i32, @intCast(dx));
      const y = wy + @as(i32, @intCast(dy));
      const c = w.chunkOfTile(x, y) orelse continue;
      const t = ck.localIndex(x, y);
      if (c.occ[t] == .none and o != .none) c.pins += 1;
      if (c.occ[t] != .none and o == .none) c.pins -= 1;
      c.occ[t] = o;
    };
  }

  /// re-point an existing footprint at a new occupant id (after a swap-remove).
  pub fn moveFootprint(w:*World, wx:i32, wy:i32, size:u8, o:Occ) void {
    for (0..size) |dy| for (0..size) |dx| {
      const x = wx + @as(i32, @intCast(dx));
      const y = wy + @as(i32, @intCast(dy));
      if (w.chunkOfTile(x, y)) |c| c.occ[ck.localIndex(x, y)] = o;
    };
  }

  /// height of a loaded tile something can stand on (null over water or void).
  pub fn walkable(w:*const World, wx:i32, wy:i32) ?f32 {
    const c = w.chunkOfTile(wx, wy) orelse return null;
    const t = ck.localIndex(wx, wy);
    return if (c.kind[t] == .water) null else c.height[t];
  }

  /// a footprint is free if every tile is loaded, unoccupied, level with the
  /// anchor and passes `ok` (e.g. fertile for roots, dry for structures).
  pub fn footprintFree(w:*const World, wx:i32, wy:i32, size:u8, comptime ok:fn (ck.Kind) bool) bool {
    const c0 = w.chunkOfTile(wx, wy) orelse return false;
    const h0 = c0.height[ck.localIndex(wx, wy)];
    for (0..size) |dy| for (0..size) |dx| {
      const x = wx + @as(i32, @intCast(dx));
      const y = wy + @as(i32, @intCast(dy));
      const c = w.chunkOfTile(x, y) orelse return false;
      const t = ck.localIndex(x, y);
      if (c.occ[t] != .none or !ok(c.kind[t]) or c.height[t] != h0) return false;
    };
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
      var dy:i32 = -r;
      while (dy <= r) : (dy += 1) {
        var dx:i32 = -r;
        while (dx <= r) : (dx += 1) {
          if (@max(@abs(dx), @abs(dy)) != r) continue;
          const at:Coord = .{.x = focus.x + dx, .y = focus.y + dy};
          if (w.map.contains(at)) continue;
          if (w.fresh.items.len >= budget) return;
          _ = try w.load(at);
        }
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
