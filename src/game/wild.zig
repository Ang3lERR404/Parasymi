//! wild flowers: birds of paradise springing up of themselves on the wet
//! ground round where rain has pooled, a tile apart, and growing there
//! (gfx/meshes/bird_of_paradise.zig). They belong to no lineage and do
//! nothing but stand there, kept when the pools dry (they mark where water
//! stood) and through the unforming; whatever is planted or grown on their
//! tile takes it. Kept here tile by tile (and saved), drawn by the view
//! (view.zig `wild`), glowing softly by night.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type sprouting may fail with
const Allocator=std.mem.Allocator;
/// all the maths: tiles, clamps
const m=lib.engine.core.math;
/// the chunk: tiles, kinds, water, occupants
const ck=lib.ck;
/// the ecology: how wet ground must be to count as soaked
const ecology=lib.ecology;
/// the garden's world, its chunks streamed in
const World=lib.world.World;
/// the game: its world, random stream and clock
const Game=lib.play.Game;
/// how often the garden looks for new flowers (s)
const every:f32=5;
/// the chance each look that a tile fit for one sprouts one (so one
/// springs up on a pool's edge within a few minutes)
const chance:f32=0.04;
/// how deep the water must stand on a tile next to it (m) for a tile to
/// count as on a pool's edge
const edgeDeep:f32=0.01;
/// how deep the water may rise over a flower's tile before it drowns (m;
/// a flood over most of it; shallower, it stands on in the water)
// decision: a flower the pool spreads over keeps standing in the shallows
const drownDeep:f32=0.3;
/// how far a flower stands from the next (tiles, every way)
const apart:i32=1;
/// how long a flower takes to grow (s)
pub const growTime:f32=150;
/// every library mesh a wild flower is drawn with
pub const meshes=[_]lib.meshlib.Id{.birdOfParadiseYoung,.birdOfParadise,.birdOfParadiseOld};
/// how a clump grows: young, plain or old (its mesh)
pub const Kind=enum(u8){
  /// four leaves and a flower
  young,
  /// six leaves and two flowers
  plain,
  /// eight leaves and three flowers
  old,
};
/// one wild flower: when it sprang up, how grown a clump it becomes, and
/// how it is turned on its tile
pub const Flower=struct{
  /// when it sprang up (the game's clock, s)
  born:f64,
  /// the clump it grows into
  kind:Kind,
  /// how it is turned (0..1 of a turn)
  turn:f32,
};
/// a tile's place, packed into one key
fn key(x:i32,y:i32)u64{return(@as(u64,@as(u32,@bitCast(x)))<<32)|@as(u32,@bitCast(y));}
/// the tile a key names
pub fn unkey(k:u64)m.Vice(i32,2){return.{@bitCast(@as(u32,@truncate(k>>32))),@bitCast(@as(u32,@truncate(k)))};}
/// every wild flower in the garden
pub const Wild=struct{
  /// the flowers, by their tile's packed place
  flowers:std.AutoHashMapUnmanaged(u64,Flower)=.empty,
  /// seconds until the garden looks for new flowers
  left:f32=0,
  /// frees the flowers
  pub fn deinit(w:*Wild,gpa:Allocator)void{w.flowers.deinit(gpa);}
  /// how many flowers grow wild
  pub fn count(w:*const Wild)usize{return w.flowers.count();}
  /// a flower sprung up on tile (x, y)
  pub fn put(w:*Wild,gpa:Allocator,x:i32,y:i32,f:Flower)Allocator.Error!void{try w.flowers.put(gpa,key(x,y),f);}
  /// the flower on tile (x, y), if one grows there
  pub fn at(w:*const Wild,x:i32,y:i32)?Flower{return w.flowers.get(key(x,y));}
  /// how far grown a flower is at clock `now` (0..1)
  pub fn grown(f:Flower,now:f64)f32{return m.clamp01(@as(f32,@floatCast(now-f.born))/growTime);}
};
/// one tick (`dt` s): every `every` s the garden drops the flowers whose
/// tiles something now stands on, then looks over every tile streamed in
/// for new ones
pub fn tick(g:*Game,dt:f32)Allocator.Error!void{
  g.wild.left-=dt;
  if(g.wild.left>0)return;
  g.wild.left+=every;
  try clear(g);
  try sprout(g);
}
/// the flowers whose tiles a plant or structure has taken, or that the
/// water has risen over (`drownDeep`), gone
fn clear(g:*Game)Allocator.Error!void{
  // the flowers taken, gathered first (none may go while the walk is on)
  var gone:std.ArrayList(u64)=.empty;
  defer gone.deinit(g.gpa);
  var it=g.wild.flowers.keyIterator();
  while(it.next())|k|{
    // its tile, and the chunk under it (not streamed in: left alone)
    const t=unkey(k.*);
    const c=g.world.chunkOfTile(t[0],t[1]) orelse continue;
    const i=ck.localIndex(t[0],t[1]);
    if(c.occ[i]!=.none or c.pool[i]>=drownDeep)try gone.append(g.gpa,k.*);
  }
  for(gone.items)|k|_=g.wild.flowers.remove(k);
}
/// every tile streamed in, now and then, sprouts a flower if it is fit
/// for one (`fits`)
fn sprout(g:*Game)Allocator.Error!void{
  var it=g.world.map.valueIterator();
  while(it.next())|cp|{
    // the chunk
    const c=cp.*;
    for(0..ck.tileCount)|t|{
      // (the roll first: most tiles never get further)
      if(g.rng.float()>=chance)continue;
      if(!soaked(c,t))continue;
      // the tile's place
      const x,const y=c.tileOf(t);
      if(!fits(g,x,y))continue;
      // the clump it grows into: most plain, some young, a few old
      const r=g.rng.float();
      const kind:Kind=if(r<0.35).young else if(r<0.8).plain else.old;
      try g.wild.put(g.gpa,x,y,.{.born=g.time,.kind=kind,.turn=g.rng.float()});
    }
  }
}
/// whether tile `t` of chunk `c` could hold a flower by itself: fertile,
/// soaked, not under water, nothing on it
fn soaked(c:*const ck.Chunk,t:usize)bool{
  return c.kind[t].fertile() and c.wet[t]>=ecology.soakedAt and c.pool[t]<edgeDeep and c.occ[t]==.none;
}
/// whether tile (x, y) is on a pool's edge (water standing on a tile next
/// to it) and no flower stands within `apart` of it
fn fits(g:*const Game,x:i32,y:i32)bool{
  // whether a tile next to it has water standing on it
  var edge=false;
  var dy:i32=-apart;
  while(dy<=apart):(dy+=1){
    var dx:i32=-apart;
    while(dx<=apart):(dx+=1){
      if(g.wild.at(x+dx,y+dy)!=null)return false;
      const c=g.world.chunkOfTile(x+dx,y+dy) orelse continue;
      if(c.pool[ck.localIndex(x+dx,y+dy)]>=edgeDeep)edge=true;
    }
  }
  return edge;
}
/// the test helpers
const testing=std.testing;
test"flowers spring up on a pool's soaked edge, a tile apart, never in it, on dry ground or on what stands there"{
  // a fresh game, and the tile two right of the wolf
  const gpa=testing.allocator;
  var g=try Game.init(gpa,lib.play.defaultSeed);
  defer g.deinit();
  const x,const z=m.tileAt(g.player.pos);
  // the pool's tile
  const px=x+4;
  // every tile streamed in dry and bare
  var it=g.world.map.valueIterator();
  while(it.next())|cp|{
    // the chunk
    const c=cp.*;
    @memset(&c.wet,0);
    @memset(&c.pool,0);
  }
  // a pool on one tile, soaked soil round it
  var dy:i32=-2;
  while(dy<=2):(dy+=1){
    var dx:i32=-2;
    while(dx<=2):(dx+=1){
      const c=g.world.chunkOfTile(px+dx,z+dy).?;
      const t=ck.localIndex(px+dx,z+dy);
      c.kind[t]=.soil;
      c.occ[t]=.none;
      c.wet[t]=1;
    }
  }
  g.world.chunkOfTile(px,z).?.pool[ck.localIndex(px,z)]=0.05;
  // long enough that its edge fills
  for(0..200)|_|try tick(&g,every);
  try testing.expect(g.wild.count()>=2);
  var fl=g.wild.flowers.keyIterator();
  while(fl.next())|k|{
    // where it grew: next to the pool, not in it
    const t=unkey(k.*);
    try testing.expect(@abs(t[0]-px)<=1 and @abs(t[1]-z)<=1);
    try testing.expect(!(t[0]==px and t[1]==z));
    // and no other within a tile of it
    var o=g.wild.flowers.keyIterator();
    while(o.next())|k2|{
      if(k2.*==k.*)continue;
      const u=unkey(k2.*);
      try testing.expect(@abs(u[0]-t[0])>apart or @abs(u[1]-t[1])>apart);
    }
  }
  // something set down on a flower's tile takes it
  var one=g.wild.flowers.keyIterator();
  const taken=unkey(one.next().?.*);
  g.world.chunkOfTile(taken[0],taken[1]).?.occ[ck.localIndex(taken[0],taken[1])]=.structure(.of(0));
  g.wild.left=0;
  try tick(&g,0);
  try testing.expect(g.wild.at(taken[0],taken[1])==null);
}
test"a flower grows over its time"{
  // one sprung up at 10 s
  const f=Flower{.born=10,.kind=.plain,.turn=0};
  try testing.expectEqual(@as(f32,0),Wild.grown(f,10));
  try testing.expectEqual(@as(f32,0.5),Wild.grown(f,10+growTime/2));
  try testing.expectEqual(@as(f32,1),Wild.grown(f,10+growTime*2));
}
