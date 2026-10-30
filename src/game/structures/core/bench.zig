//! the test bench: a little patch of ground every structure's tests grow on,
//! and the clock that runs them. One shared copy instead of one per kind.
const lib=@import("../../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the test allocator the bench's ticks run on
const testing=std.testing;
/// the chunk's tile layout and ground kinds
const ck=lib.ck;
/// the garden's world of chunks
const World=lib.world.World;
/// every plant in the garden
const Plants=lib.plants.Plants;
/// what the gardener has understood
const prog=lib.progression;
/// every structure standing
const Structures=lib.structures.list.Structures;
/// one beat of the bench's clock: how many seconds each test tick lasts
pub const testDt:f32=0.05;
/// the shape of the patch to lay: `width` tiles east and `depth` tiles south
/// from the origin, all of one ground `kind`, raised one step
pub const Patch=struct{
  /// how many tiles east the patch runs
  width:usize,
  /// how many tiles south the patch runs
  depth:usize,
  /// what the patch is made of
  kind:ck.Kind=.soil,
  /// strip every resource from every streamed chunk first, so nothing
  /// buried waits outside the patch
  bare:bool=false,
};
/// wakes the chunk at the origin and lays a patch of ground on it, empty of
/// resources; hands back that chunk so a test can bury or change a tile.
pub fn ground(w:*World,p:Patch)!*ck.Chunk{
  try w.stream(.{.x=0,.y=0},1,100);
  if(p.bare){
    // every streamed chunk, emptied of what it held underground
    var it=w.map.valueIterator();
    while(it.next())|cp|@memset(&cp.*.res,0);
  }
  // the chunk the patch lies on
  const c=w.chunkOfTile(0,0).?;
  for(0..p.width)|x|for(0..p.depth)|y|{
    // the tile's index inside its chunk
    const t=y*ck.sizeTiles+x;
    c.kind[t]=p.kind;
    c.height[t]=1;
    c.res[t]=0;
  };
  return c;
}
/// lets the structures live for `seconds`, one bench beat at a time.
pub fn run(ss:*Structures,w:*World,plants:*Plants,g:*prog.Progression,seconds:f32)!void{
  // how long they have lived so far
  var t:f32=0;
  while(t<seconds):(t+=testDt)try ss.tick(testing.allocator,w,plants,g,testDt);
}
