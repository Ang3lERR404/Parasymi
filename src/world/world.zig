//! the garden's world: the engine's streamed chunk map (engine
//! world/world.zig) over the garden's tiles (chunk.zig) and generation (gen.zig).
const lib=@import("../lib.zig");
/// the engine package, reached through the hub
const engine=lib.engine;
/// the standard library
const std=lib.std;
/// the world module (this one, through the hub)
const world=lib.world;
/// the garden's chunk: tiles, kinds, occupants
const ck=lib.ck;
/// the world generator
const gen=lib.gen;
/// the test allocator and expectations
const testing=std.testing;
/// one block of tiles
pub const Chunk=ck.Chunk;
/// a chunk's place on the grid
pub const Coord=ck.Coord;
/// what sits on a tile
pub const Occ=ck.Occ;
/// the garden as the engine's world sees it
const Land=struct{
  /// the garden's chunk
  pub const Chunk=ck.Chunk;
  /// a tile's ground kind
  pub const Kind=ck.Kind;
  /// what sits on a tile
  pub const Occ=ck.Occ;
  /// a chunk not yet filled
  pub const blank=ck.blank;
  /// fills a chunk from the generator
  pub const generate=gen.generate;
  /// the ground height of a world tile
  pub const heightAt=gen.heightAt;
};
/// the garden's streamed world of chunks, loaded and evicted round the player
pub const World=engine.world.World(Land);
test"garden chunks generated over the pool match those made one by one"{
  // one world filled one chunk at a time, and one over the pool
  var a=World.init(testing.allocator,9);
  defer a.deinit();
  var b=World.init(testing.allocator,9);
  defer b.deinit();
  b.io=testing.io;
  try a.stream(.{.x=0,.y=0},2,100);
  try b.stream(.{.x=0,.y=0},2,100);
  try testing.expectEqual(a.map.count(),b.map.count());
  // walks every chunk of the first
  var it=a.map.valueIterator();
  while(it.next())|c|{
    // the same chunk in the second
    const d=b.get(c.*.at).?;
    try testing.expectEqualSlices(f32,&c.*.height,&d.height);
    try testing.expectEqualSlices(ck.Kind,&c.*.kind,&d.kind);
    try testing.expectEqualSlices(f32,&c.*.ley,&d.ley);
  }
}
