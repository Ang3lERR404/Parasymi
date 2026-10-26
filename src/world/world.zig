//! the garden's world: the engine's streamed chunk map (engine
//! world/world.zig) over the garden's tiles (chunk.zig) and generation (gen.zig).
const std = @import("std");
const testing = std.testing;
const engine = @import("engine");
const ck = @import("chunk.zig");
const gen = @import("gen.zig");

pub const Chunk = ck.Chunk;
pub const Coord = ck.Coord;
pub const Occ = ck.Occ;

/// the garden as the engine's world sees it
const Land = struct {
  pub const Chunk = ck.Chunk;
  pub const Kind = ck.Kind;
  pub const Occ = ck.Occ;
  pub const blank = ck.blank;
  pub const generate = gen.generate;
  pub const heightAt = gen.heightAt;
};

pub const World = engine.world.World(Land);

test "garden chunks generated over the pool match those made one by one" {
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
