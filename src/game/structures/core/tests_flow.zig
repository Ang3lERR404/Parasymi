//! structures tested: harvesting, handing off, the tile index, records.
const lib=@import("../../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the test allocator and expectations
const testing=std.testing;
/// the engine package: maths and the random stream
const engine=lib.engine;
/// all the maths: the four ways, footprints
const m=engine.core.math;
/// the chunks: tile layout and ground kinds
const ck=lib.ck;
/// the garden's world of chunks
const World=lib.world.World;
/// every plant in the garden
const Plants=lib.plants.Plants;
/// what the gardener has understood
const prog=lib.progression;
/// everything a structure's behaviour may touch
const Ctx=lib.structures.structure.Ctx;
/// a placed structure's slot in the list
const Id=lib.structures.Id;
/// which kind of structure
const Kind=lib.structures.Kind;
/// the ring of tiles round a footprint
const Ring=lib.structures.handoff.Ring;
/// the garden's list of structures
const Structures=lib.structures.list.Structures;
/// hand one thing on to a neighbour
const handOff=lib.structures.handoff.handOff;
/// hand on further and more, as asked
const handOffWith=lib.structures.handoff.handOffWith;
test"conduits harvest plants into a cache"{
  // the test allocator, and the world it grows on
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  // the chunk at the origin, its first row laid as soil
  const c=w.chunkOfTile(0,0).?;
  for(0..4)|x|{c.kind[x]=.soil;c.height[x]=1;c.res[x]=0;}
  // the plants, the structures and what is understood
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  // plant -> conduit -> conduit -> cache, left to right
  try testing.expect(try plants.placeEx(gpa,&w,0,0,.{.x=0,.y=0,.chunk=undefined,.tile=undefined,.sp=.lumenroot,.seed=0,.growth=1,.essence=3}));
  try testing.expect(try ss.place(gpa,&w,1,0,.conduit,0,0));
  try testing.expect(try ss.place(gpa,&w,2,0,.conduit,0,0));
  try testing.expect(try ss.place(gpa,&w,3,0,.sapCache,0,0));
  for(0..200)|_|try ss.tick(gpa,&w,&plants,&g,0.05);
  // the cache at the line's end
  const cache=ss.at(&w,3,0).?;
  try testing.expectEqual(@as(u32,3),ss.get(cache).inv.count(.essence));
  // removing the middle conduit keeps the others addressable
  _=ss.remove(&w,ss.at(&w,1,0).?);
  try testing.expect(ss.get(ss.at(&w,3,0).?).kind()==.sapCache);
}
test"a conduit's side root reaches a plant beside it and harvests it"{
  // the test allocator, and the world it grows on
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  // the chunk at the origin, a 3×2 patch laid as soil
  const c=w.chunkOfTile(0,0).?;
  for(0..3)|x|for(0..2)|y|{const t=y*ck.sizeTiles+x;c.kind[t]=.soil;c.height[t]=1;c.res[t]=0;};
  // the plants, the structures and what is understood
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  // conduit -> cache along +x, a mature plant beside the conduit (+y)
  try testing.expect(try plants.placeEx(gpa,&w,1,1,.{.x=1,.y=1,.chunk=undefined,.tile=undefined,.sp=.lumenroot,.seed=0,.growth=1,.essence=2}));
  try testing.expect(try ss.place(gpa,&w,1,0,.conduit,0,0));
  try testing.expect(try ss.place(gpa,&w,2,0,.sapCache,0,0));
  // nothing moves until the root has grown out to it
  try ss.tick(gpa,&w,&plants,&g,0.05);
  try testing.expect(ss.get(ss.at(&w,1,0).?).state.conduit.held==null);
  for(0..200)|_|try ss.tick(gpa,&w,&plants,&g,0.05);
  try testing.expectEqual(@as(u32,2),ss.get(ss.at(&w,2,0).?).inv.count(.essence));
}
test"a footprint's ring holds every tile that many steps out, once, beside ones first in `m.dirs` order"{
  // a single tile's first ring: its four neighbours
  var one:Ring=.{.x0=0,.y0=0,.x1=0,.y1=0,.d=1};
  for(m.dirs)|d|{
    // the step that way
    const v=m.dirVec(d);
    try testing.expectEqual(m.Vice(i32,2){v.x,v.z},one.next().?);
  }
  try testing.expect(one.next()==null);
  for([_]i32{1,2})|n|for([_]i32{1,2,3})|d|{
    // ring `d` round an `n`×`n` footprint, the tiles seen and their count
    var r:Ring=.{.x0=0,.y0=0,.x1=n-1,.y1=n-1,.d=d};
    var seen:[64]m.Vice(i32,2)=undefined;
    var c:usize=0;
    while(r.next())|t|:(c+=1){
      // the tile's steps out from the footprint, across and down
      const dx=@max(0-t[0],0,t[0]-(n-1));
      const dy=@max(0-t[1],0,t[1]-(n-1));
      try testing.expectEqual(d,dx+dy);
      for(seen[0..c])|s|try testing.expect(!(s[0]==t[0] and s[1]==t[1]));
      seen[c]=t;
    }
    try testing.expectEqual(@as(usize,@intCast(4*n+4*(d-1))),c);
  };
}
test"handing off reaches further and hands more when asked, the nearest first"{
  // the test allocator, and the world it grows on
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  // the chunk at the origin, its first row laid as soil
  const c=w.chunkOfTile(0,0).?;
  for(0..4)|x|{c.kind[x]=.soil;c.height[x]=1;c.res[x]=0;}
  // the plants, the structures and what is understood
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  // the context the hand-offs run in
  const ctx:Ctx=.{.gpa=gpa,.w=&w,.plants=&plants,.g=&g,.ss=&ss};
  // loomfern, a gap, a cache two steps out
  try testing.expect(try ss.place(gpa,&w,0,0,.loomfern,0,0));
  try testing.expect(try ss.place(gpa,&w,2,0,.sapCache,0,0));
  // the fern that gives and the cache two steps off
  const fern=ss.at(&w,0,0).?;
  const cache=ss.at(&w,2,0).?;
  _=ss.get(fern).inv.add(.fibre,6);
  try testing.expect(!handOff(ctx,fern));
  try testing.expectEqual(@as(u16,4),handOffWith(ctx,fern,.{.range=2,.amount=4}));
  try testing.expectEqual(@as(u32,4),ss.get(cache).inv.count(.fibre));
  // a cache beside it now comes first; asked for more than it has, all go
  try testing.expect(try ss.place(gpa,&w,1,0,.sapCache,0,0));
  // the cache right beside the fern
  const near=ss.at(&w,1,0).?;
  try testing.expectEqual(@as(u16,2),handOffWith(ctx,fern,.{.range=2,.amount=9}));
  try testing.expectEqual(@as(u32,2),ss.get(near).inv.count(.fibre));
  try testing.expectEqual(@as(u32,0),ss.get(fern).inv.count(.fibre));
}
/// `find` and `getChildren` as walking the whole list answers them
fn expectIndexed(ss:*const Structures)!void{
  try testing.expectEqual(ss.list.items.len,ss.where.count());
  try testing.expectEqual(ss.list.items.len,ss.kin.items.len);
  for(ss.list.items,0..)|*s,i|{
    try testing.expectEqual(Id.of(i),ss.find(s.ref()).?);
    // its children as the index walks them
    var it=ss.getChildren(Id.of(i));
    for(ss.list.items,0..)|*o,j|if(o.parent)|p|if(p.eql(s.ref())){
      try testing.expectEqual(Id.of(j),it.next().?);
    };
    try testing.expect(it.next()==null);
  }
}
test"the tile index and the children agree with the list through placing, adopting, uprooting and a reload"{
  // the test allocator, and the world it grows on
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  // the chunk at the origin, a 10×10 patch laid as soil
  const c=w.chunkOfTile(0,0).?;
  for(0..10)|x|for(0..10)|y|{const t=y*ck.sizeTiles+x;c.kind[t]=.soil;c.height[t]=1;c.res[t]=0;};
  // the structures, and the random stream that churns them
  var ss:Structures=.{};
  defer ss.deinit(gpa);
  var rng=engine.core.rng.Rng.init(7);
  // the kinds put down: a store, a parent and the children it adopts
  const ks=[_]Kind{.sapCache,.monfris,.vultrixi,.vultrixi};
  for(0..400)|_|{
    // how many stand now
    const n=ss.list.items.len;
    switch(rng.below(4)){
      0,1=>_=try ss.place(gpa,&w,@intCast(rng.below(10)),@intCast(rng.below(10)),ks[rng.below(ks.len)],0,0),
      2=>if(n>0){_=ss.dependOn(Id.of(rng.below(@intCast(n))),Id.of(rng.below(@intCast(n))));},
      else=>if(n>0){
        if(rng.below(3)==0)ss.detach(Id.of(rng.below(@intCast(n))))else _=ss.remove(&w,Id.of(rng.below(@intCast(n))));
      },
    }
    try expectIndexed(&ss);
  }
  // put back as saved, in the same order
  var again:Structures=.{};
  defer again.deinit(gpa);
  // a second world for the reloaded garden
  var w2=World.init(gpa,5);
  defer w2.deinit();
  try w2.stream(.{.x=0,.y=0},1,100);
  // its origin chunk, laid the same
  const c2=w2.chunkOfTile(0,0).?;
  for(0..10)|x|for(0..10)|y|{const t=y*ck.sizeTiles+x;c2.kind[t]=.soil;c2.height[t]=1;c2.res[t]=0;};
  for(ss.list.items)|s|try testing.expect(try again.restore(gpa,&w2,s));
  again.relink();
  try expectIndexed(&again);
  for(0..ss.list.items.len)|i|try testing.expectEqual(ss.childCount(Id.of(i)),again.childCount(Id.of(i)));
}
test"uprooting keeps the others in the order they were put down, each found on its own tiles"{
  // the test allocator, and the world it grows on
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  // the chunk at the origin, a 12×2 patch laid as soil
  const c=w.chunkOfTile(0,0).?;
  for(0..12)|x|for(0..2)|y|{const t=y*ck.sizeTiles+x;c.kind[t]=.soil;c.height[t]=1;c.res[t]=0;};
  // the structures
  var ss:Structures=.{};
  defer ss.deinit(gpa);
  // what is put down, and at which column, west to east
  const put=[_]struct{x:i32,k:Kind}{.{.x=0,.k=.sapCache},.{.x=1,.k=.monfris},.{.x=3,.k=.sapCache},.{.x=4,.k=.monfris},.{.x=6,.k=.loomfern}};
  for(put)|p|try testing.expect(try ss.place(gpa,&w,p.x,0,p.k,0,0));
  _=ss.remove(&w,ss.at(&w,0,0).?);
  _=ss.remove(&w,ss.at(&w,3,0).?);
  // the columns of those left, in order
  const left=[_]i32{1,4,6};
  try testing.expectEqual(left.len,ss.list.items.len);
  for(ss.list.items,left,0..)|*s,x,i|{
    try testing.expectEqual(x,s.x);
    // the walk over its footprint's tiles
    var it=m.footprint(s.x,s.y,s.def().size);
    while(it.next())|t|try testing.expectEqual(Id.of(i),w.occAt(t[0],t[1]).asStructure().?);
  }
  try testing.expect(w.occAt(0,0).asStructure()==null and w.occAt(3,0).asStructure()==null);
  try expectIndexed(&ss);
}
test"floating structures hang off the grid, a tile's width apart at least"{
  // the test allocator, a small loaded world, and the structures
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try w.stream(.{.x=0,.y=0},1,100);
  var ss:Structures=.{};
  defer ss.deinit(gpa);
  // one hung off its tile's centre keeps its own point, found by the tile under it
  try testing.expect(try ss.placeNear(gpa,&w,m.v3(2.2,0,3.9),.weftstone,0,0));
  try testing.expectEqual(@as(f32,2.2),ss.get(.of(0)).at[0]);
  try testing.expect(ss.floaterAt(2,3)!=null);
  // too near it, or over its tile, it may not hang; a metre off it may
  try testing.expect(!ss.canPlaceNear(&w,m.v3(2.9,0,3.9),.weftstone));
  try testing.expect(!ss.canPlaceNear(&w,m.v3(2.95,0,3.05),.weftstone));
  try testing.expect(try ss.placeNear(gpa,&w,m.v3(3.25,0,3.9),.weftstone,0,0));
  try testing.expect(ss.floaterAt(3,3)!=null);
}
