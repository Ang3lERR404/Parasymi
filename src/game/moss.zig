//! ground the garden has changed: soil a moss creeper has turned to moss
//! where the rain soaked it, so a grove may root there, and moss a night
//! beam has turned to a ley line now and then (`beamGround`). The world
//! regrows its ground from the seed whenever a chunk streams in, so the
//! changed ground is kept here, tile by tile (and saved), and laid back
//! onto every chunk as it comes (`Chunk.mossed`).
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type growing moss may fail with
const Allocator=std.mem.Allocator;
/// all the maths: tiles, rings
const m=lib.engine.core.math;
/// the species registry: which plants creep
const species=lib.species;
/// the chunk: tiles, kinds, water
const ck=lib.ck;
/// the ecology: how wet ground must be to count as soaked
const ecology=lib.ecology;
/// the garden's world, its chunks streamed in
const World=lib.world.World;
/// the game: its plants, world, random stream
const Game=lib.play.Game;
/// the water a tile grown to moss holds, at the least (a third and more,
/// as the generator's moss)
pub const mossWater:f32=0.4;
/// how many tiles a creeper tries for each new tile of moss before it gives up
const tries=6;
/// the ley a beam-born ley line holds (the generator's run 0.2 to about 4)
pub const bornLey:f32=1.6;
/// what a changed tile has become
pub const Grown=enum(u8){
  /// moss, from soil a creeper reached in the rain
  moss,
  /// a ley line, from moss under a night beam
  ley,
};
/// a changed tile as stored: its column, its row, what it has become
pub const Kept=extern struct{x:i32,y:i32,grown:u32};
/// a tile's place, packed into one key
fn key(x:i32,y:i32)u64{return(@as(u64,@as(u32,@bitCast(x)))<<32)|@as(u32,@bitCast(y));}
/// the tile a key names
fn unkey(k:u64)m.Vice(i32,2){return.{@bitCast(@as(u32,@truncate(k>>32))),@bitCast(@as(u32,@truncate(k)))};}
/// every tile the garden has changed
pub const Moss=struct{
  /// the tiles, by their packed place, and what each has become
  tiles:std.AutoHashMapUnmanaged(u64,Grown)=.empty,
  /// frees the tiles
  pub fn deinit(s:*Moss,gpa:Allocator)void{s.tiles.deinit(gpa);}
  /// how many tiles have changed
  pub fn count(s:*const Moss)usize{return s.tiles.count();}
  /// every changed tile, by place and what it became, into `out`
  pub fn list(s:*const Moss,gpa:Allocator,out:*std.ArrayList(Kept))Allocator.Error!void{
    var it=s.tiles.iterator();
    while(it.next())|e|{
      // the tile's place
      const t=unkey(e.key_ptr.*);
      try out.append(gpa,.{.x=t[0],.y=t[1],.grown=@intFromEnum(e.value_ptr.*)});
    }
  }
  /// tile (x, y) grown to moss: kept, and laid on its chunk if streamed in
  pub fn grow(s:*Moss,gpa:Allocator,w:*World,x:i32,y:i32)Allocator.Error!void{try s.become(gpa,w,x,y,.moss);}
  /// tile (x, y) become `to`: kept, and laid on its chunk if streamed in
  pub fn become(s:*Moss,gpa:Allocator,w:*World,x:i32,y:i32,to:Grown)Allocator.Error!void{
    try s.tiles.put(gpa,key(x,y),to);
    if(w.chunkOfTile(x,y))|c|lay(c,ck.localIndex(x,y),to);
  }
  /// the grown moss laid onto every chunk streamed in since it was last
  /// laid (fresh from the seed, it has none)
  pub fn apply(s:*const Moss,w:*World)void{
    var it=w.map.valueIterator();
    while(it.next())|cp|{
      // the chunk
      const c=cp.*;
      if(c.mossed)continue;
      c.mossed=true;
      if(s.tiles.count()==0)continue;
      for(0..ck.tileCount)|t|{
        // the tile's place
        const x,const y=c.tileOf(t);
        if(s.tiles.get(key(x,y)))|to|lay(c,t,to);
      }
    }
  }
};
/// tile `t` of chunk `c` turned to `to`: moss holding a moss's water, or a
/// ley line rich in ley; its ground meshed again
fn lay(c:*ck.Chunk,t:usize,to:Grown)void{
  switch(to){
    .moss=>{
      c.kind[t]=.moss;
      c.waterCap[t]=@max(c.waterCap[t],mossWater);
    },
    .ley=>{
      c.kind[t]=.ley;
      c.leyCap[t]=@max(c.leyCap[t],bornLey);
    },
  }
  c.dirty=true;
}
/// one tick (`dt` s) of the garden's creepers: each grown, healthy one now
/// and then (once every `Species.creeps` s, on the garden's random stream)
/// turns a soil tile within its `creepReach` to moss, if the rain has
/// soaked it
pub fn creep(g:*Game,dt:f32)Allocator.Error!void{
  // the plants' columns
  const s=g.plants.list.slice();
  for(0..g.plants.len())|i|{
    // its kind
    const def=species.get(s.items(.sp)[i]);
    if(def.creeps<=0 or s.items(.growth)[i]<1 or s.items(.health)[i]<0.5)continue;
    if(g.rng.float()>=dt/def.creeps)continue;
    // where it roots, and how far it reaches
    const x=s.items(.x)[i];
    const y=s.items(.y)[i];
    const reach:i32=def.creepReach;
    for(0..tries)|_|{
      // a tile within its reach
      const tx=x+@as(i32,@intCast(g.rng.below(@intCast(2*reach+1))))-reach;
      const ty=y+@as(i32,@intCast(g.rng.below(@intCast(2*reach+1))))-reach;
      const c=g.world.chunkOfTile(tx,ty) orelse continue;
      const t=ck.localIndex(tx,ty);
      if(c.kind[t]!=.soil or c.wet[t]<ecology.soakedAt)continue;
      try g.moss.grow(g.gpa,&g.world,tx,ty);
      break;
    }
  }
}
test"grown moss is laid back onto a chunk streamed in afresh"{
  // the test allocator, a small world, and the moss
  const gpa=std.testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  var s=Moss{};
  defer s.deinit(gpa);
  // a soil tile grown to moss
  const c=w.chunkOfTile(3,4).?;
  const t=ck.localIndex(3,4);
  c.kind[t]=.soil;
  c.waterCap[t]=0;
  try s.grow(gpa,&w,3,4);
  try std.testing.expectEqual(ck.Kind.moss,c.kind[t]);
  try std.testing.expect(c.waterCap[t]>=mossWater);
  // regrown from the seed, it is soil again until the moss is laid back
  c.kind[t]=.soil;
  c.mossed=false;
  s.apply(&w);
  try std.testing.expectEqual(ck.Kind.moss,c.kind[t]);
  try std.testing.expectEqual(m.Vice(i32,2){3,4},unkey(key(3,4)));
  try std.testing.expectEqual(m.Vice(i32,2){-7,-2},unkey(key(-7,-2)));
}
test"a grown creeper turns soaked soil round it to moss, never dry soil"{
  // the test allocator; for dry soil then soaked
  const gpa=std.testing.allocator;
  for([_]f32{0,1})|wetness|{
    // a fresh game, and the tile two right of the wolf
    var g=try Game.init(gpa,lib.play.defaultSeed);
    defer g.deinit();
    const x,const z=m.tileAt(g.player.pos);
    // the ground round it: soil, wet as this case, nothing on it
    var dy:i32=-3;
    while(dy<=3):(dy+=1){
      var dx:i32=-1;
      while(dx<=5):(dx+=1){
        const c=g.world.chunkOfTile(x+dx,z+dy).?;
        const t=ck.localIndex(x+dx,z+dy);
        c.kind[t]=.soil;
        c.res[t]=0;
        c.wet[t]=wetness;
      }
    }
    try std.testing.expect(try g.plants.placeEx(gpa,&g.world,x+2,z,.{.x=x+2,.y=z,.chunk=undefined,.tile=undefined,.sp=.mossCreeper,.seed=0.5,.growth=1}));
    // ten minutes of creeping
    for(0..600)|_|try creep(&g,1);
    if(wetness==0){
      try std.testing.expectEqual(@as(usize,0),g.moss.count());
    }else{
      try std.testing.expect(g.moss.count()>=5);
      // every tile it grew lies within its reach, and is moss
      var tiles:std.ArrayList(Kept)=.empty;
      defer tiles.deinit(gpa);
      try g.moss.list(gpa,&tiles);
      for(tiles.items)|t|{
        try std.testing.expect(@abs(t.x-(x+2))<=2 and @abs(t.y-z)<=2 and t.grown==@intFromEnum(Grown.moss));
        try std.testing.expectEqual(ck.Kind.moss,g.world.chunkOfTile(t.x,t.y).?.kind[ck.localIndex(t.x,t.y)]);
      }
    }
  }
}
