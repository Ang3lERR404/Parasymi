//! the infinite world: a sparse map of generated chunks streamed around a focus.
const std = @import("std");
const ck = @import("chunk.zig");
const gen = @import("gen.zig");

pub const Chunk = ck.Chunk;
pub const Coord = ck.Coord;

pub const World = struct {
  gpa:std.mem.Allocator,
  seed:u64,
  map:std.AutoHashMapUnmanaged(Coord, *Chunk) = .empty,
  /// gpu slots of chunks that were unloaded; the renderer drains this.
  evicted:std.ArrayList(u32) = .empty,
  /// chunks generated this frame (stats).
  generated:u32 = 0,

  pub fn init(gpa:std.mem.Allocator, seed:u64) World { return .{.gpa = gpa, .seed = seed}; }

  pub fn deinit(w:*World) void {
    var it = w.map.valueIterator();
    while (it.next()) |c| w.gpa.destroy(c.*);
    w.map.deinit(w.gpa);
    w.evicted.deinit(w.gpa);
  }

  pub fn get(w:*const World, at:Coord) ?*Chunk { return w.map.get(at); }

  pub fn chunkOfTile(w:*const World, wx:i32, wy:i32) ?*Chunk { return w.map.get(Coord.ofTile(wx, wy)); }

  fn load(w:*World, at:Coord) !*Chunk {
    const c = try w.gpa.create(Chunk);
    c.* = .{.at = at, .height = undefined, .kind = undefined, .ley = undefined, .ley_cap = undefined, .plant = undefined};
    gen.generate(w.seed, c);
    try w.map.put(w.gpa, at, c);
    w.generated += 1;
    return c;
  }

  /// generate missing chunks nearest-first (at most `budget` per call) and
  /// unload empty chunks well outside `radius`. Chunks holding plants stay
  /// resident so the ecosystem keeps simulating off-screen.
  pub fn stream(w:*World, focus:Coord, radius:i32, budget:u32) !void {
    w.generated = 0;
    var r:i32 = 0;
    ring: while (r <= radius) : (r += 1) {
      var dy:i32 = -r;
      while (dy <= r) : (dy += 1) {
        var dx:i32 = -r;
        while (dx <= r) : (dx += 1) {
          if (@max(@abs(dx), @abs(dy)) != r) continue;
          const at:Coord = .{.x = focus.x + dx, .y = focus.y + dy};
          if (w.map.contains(at)) continue;
          if (w.generated >= budget) break :ring;
          _ = try w.load(at);
        }
      }
    }

    const keep = radius + 2;
    var drop:std.ArrayList(Coord) = .empty;
    defer drop.deinit(w.gpa);
    var it = w.map.iterator();
    while (it.next()) |e| {
      const at = e.key_ptr.*;
      if (e.value_ptr.*.plants > 0) continue;
      if (@max(@abs(at.x - focus.x), @abs(at.y - focus.y)) > keep) try drop.append(w.gpa, at);
    }
    for (drop.items) |at| {
      const c = w.map.fetchRemove(at).?.value;
      if (c.gpu_slot != ck.NONE) try w.evicted.append(w.gpa, c.gpu_slot);
      w.gpa.destroy(c);
    }
  }
};

test "stream loads and unloads" {
  var w = World.init(std.testing.allocator, 9);
  defer w.deinit();
  try w.stream(.{.x = 0, .y = 0}, 1, 100);
  try std.testing.expectEqual(@as(u32, 9), w.map.count());
  try w.stream(.{.x = 50, .y = 0}, 0, 100);
  try std.testing.expectEqual(@as(u32, 1), w.map.count());
}
