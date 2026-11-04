//! world generation: a pure function of (seed, tile coordinate). Chunks never
//! depend on neighbours being loaded, so meshing and streaming stay order-free.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the engine package
const engine=lib.engine;
/// one chunk: its tiles, kinds and resources
const ck=lib.ck;
/// the test expectations
const testing=std.testing;
/// what the tests' sweeps of tiles are allocated from
const Allocator=std.mem.Allocator;
/// all the maths: conversions
const m=engine.core.math;
/// smooth noise: fractal and ridged
const noise=engine.core.noise;
/// hashes, for each tile's own roll
const rng=engine.core.rng;
/// how high one terrace step stands (m)
pub const terrace=0.35;
/// terrace levels per unit of elevation noise: how many steps the land climbs
const levels:f32=4;
/// the elevation below which the ground lies level on the lowest terrace (lowland meadows)
const lowLevel:f32=-0.28;
/// elevation above which the ground is bare stone
const stone:f32=0.62;
/// ridged vein noise above this is a ley line
const veinAmount:f32=0.955;
/// the ley every tile holds at the least
const leyBase:f32=0.2;
/// how many times more ley a ley line carries
const leyLine:f32=4;
/// wetness above which the ground is moss, not soil
const wetAmount:f32=0.05;
/// the domain warp's wavelength (tiles): how broadly coastlines bend
const warpL:f32=90;
/// how far the domain warp pushes a tile (tiles)
const warp:f32=14;
/// the continents' wavelength (tiles)
const continentL:f32=70;
/// how much the hills lift a tile within its terrace (m per unit of hill noise)
const intra:f32=0.04;
/// a roughness wavelength (tiles), unused for now
const roughL:f32=120;
/// the hills' wavelength (tiles)
const hillL:f32=14;
/// the hills' share of a tile's elevation
const hillAmount:f32=0.25;
/// the wetness wavelength (tiles)
const wetL:f32=55;
/// the wetness at which a tile's ground holds no water, and the span over
/// which it comes to hold all it can (moss, past `wetAmount`, holds well
/// over a third)
const dryAt:f32=-0.3;
/// (the span)
const soakSpan:f32=0.9;
/// how much of its water stone keeps: it hardly holds any
const stoneWater:f32=0.15;
/// the ley veins' wavelength (tiles)
const veinL:f32=45;
/// the resource patches' wavelength (tiles)
const patchL:f32=16;
/// octaves of the domain warp's noise
const warpOct=3;
/// octaves of the continents' noise
const continentOct=5;
/// octaves of the hills' noise
const hillOct=2;
/// octaves of the wetness noise
const wetOct=3;
/// octaves of the ley veins' noise
const veinOct=3;
/// octaves of the resource patches' noise
const patchOct=2;
/// resource nodes cluster where patch noise rises above this
/// (a share of `nodeChance` of their tiles, each holding `resMin` and up to `resSpread` more)
const patchAmount:f32=0.22;
/// the share of a patch's tiles meant to bear a node (unused for now: `slotAmount` thins them)
const nodeChance:f32=0.6;
/// the least a node holds
const resMin:f32=1500;
/// how much more a node may hold, by its tile's roll
const resSpread:f32=3000;
/// the yardstick for how full a node looks (drawn at full size)
pub const resFull:f32=resMin+resSpread;
/// the most ley a tile holds (a ley line at full vein strength)
pub const leyMax:f32=leyBase+leyLine;
/// the wavelength of the noise that picks which patch tiles bear a node (tiles)
const slotL:f32=5;
/// the node noise above which a patch tile bears one
const slotAmount:f32=0.4;
/// what the generator makes of one tile: its height, ground kind, ley and resource
pub const Sample=struct{height:f32,kind:ck.Kind,ley:f32,res:ck.Res=0,sealed:f32=leyBase,water:f32=0};
/// what a tile becomes once the ley lines seal (the unforming): a ley line
/// closes to a scar of bare soil, holding only the ley a tile off the
/// lines would, its shards gone; any other tile is as it was
pub fn sealOf(s:Sample)Sample{
  if(s.kind!=.ley)return s;
  return.{.height=s.height,.kind=.soil,.ley=s.sealed,.res=0,.sealed=s.sealed,.water=s.water};
}
/// where the domain warp pushes tile (wx, wy): it keeps coastlines and
/// ridges organic instead of blobby
fn warped(seed:u64,wx:i32,wy:i32)m.Vec(f32,2){
  // the tile's place as numbers
  const x=m.f(wx);
  const y=m.f(wy);
  return.{x+warp*noise.fbm(seed+%11,x/warpL,y/warpL,warpOct),y+warp*noise.fbm(seed+%12,x/warpL,y/warpL,warpOct)};
}
/// the continent's elevation at warped place `p`
fn continentOf(seed:u64,p:m.Vec(f32,2))f32{return noise.fbm(seed,p[0]/continentL,p[1]/continentL,continentOct);}
/// the terrace a continent elevation `c` stands on, as the noise alone has it
fn stepOf(c:f32)f32{return @floor(@max(c-lowLevel,0)*levels)+1;}
/// the terrace tile (wx, wy) stands on, as the noise alone has it
fn rawStep(seed:u64,wx:i32,wy:i32)f32{return stepOf(continentOf(seed,warped(seed,wx,wy)));}
/// the terrace a tile of noise step `own` stands on: never above the highest
/// of its four neighbours, so no lone 1x1 column juts up out of the ground
/// (a tile so lowered is level with that neighbour, which is never lowered
/// below it, so the levelled land has no lone column either)
fn levelled(seed:u64,wx:i32,wy:i32,own:f32)f32{
  // the highest of the four neighbours' noise steps
  const near=@max(@max(rawStep(seed,wx-1,wy),rawStep(seed,wx+1,wy)),@max(rawStep(seed,wx,wy-1),rawStep(seed,wx,wy+1)));
  return @min(own,near);
}
/// how far (tiles) a terrace's edge eases into the land round it: a tile
/// stands on the levelled terraces within this reach of it, the nearer
/// counted more, so one terrace rolls into the next in a soft S over a few
/// tiles instead of a hard one-tile ramp; the heart of a wide terrace
/// stays level
const easeReach:f32=2.5;
/// how many whole tiles each way the ease looks
const easeSpan=2;
/// one tile the ease counts: how far off it lies, and its weight
const Ease=struct{
  /// its offset in tiles, across and down
  d:m.Vice(i32,2),
  /// how much it counts, falling smoothly to nothing at the reach
  w:f32,
};
/// every tile within the ease's reach, with its weight
const ease=blk:{
  // the tiles found so far, and how many
  var es:[(2*easeSpan+1)*(2*easeSpan+1)]Ease=undefined;
  var n:usize=0;
  var dy:i32=-easeSpan;
  while(dy<=easeSpan):(dy+=1){
    // the column offset being looked at
    var dx:i32=-easeSpan;
    while(dx<=easeSpan):(dx+=1){
      // how far it lies, as a share of the reach (squared)
      const d2=m.f(dx*dx+dy*dy)/(easeReach*easeReach);
      if(d2>=1)continue;
      es[n]=.{.d=.{dx,dy},.w=(1-d2)*(1-d2)};
      n+=1;
    }
  }
  break:blk es[0..n].*;
};
/// all the ease's weights together
const easeTotal=blk:{
  // the running sum
  var s:f32=0;
  for(ease)|e|s+=e.w;
  break:blk s;
};
/// the eased terrace (in steps) of one tile, from `src.step(dx, dy)`: the
/// levelled terrace of the tile `dx, dy` off it
fn eased(comptime t:type,src:t)f32{
  // the weighted terraces so far
  var sum:f32=0;
  for(ease)|e|sum+=e.w*src.step(e.d[0],e.d[1]);
  return sum/easeTotal;
}
/// the levelled terraces round one tile, each worked out from the noise
const Lone=struct{
  /// the world's seed
  seed:u64,
  /// the tile, across
  wx:i32,
  /// the tile, down
  wy:i32,
  /// the levelled terrace `dx, dy` tiles off it
  fn step(s:Lone,dx:i32,dy:i32)f32{
    // that tile
    const x=s.wx+dx;
    const y=s.wy+dy;
    return levelled(s.seed,x,y,rawStep(s.seed,x,y));
  }
};
/// the levelled terraces of a chunk's tiles and `easeSpan` beyond it, each
/// tile's noise read once (`generate` eases a whole chunk from it)
const Field=struct{
  /// how many tiles across it is
  const w=ck.sizeTiles+2*easeSpan;
  /// how many tiles across its noise steps are: one more each side, for the levelling
  const rw=w+2;
  /// each tile's levelled terrace, row by row
  lv:[w*w]f32=undefined,
  /// reads the field round the chunk whose first tile is (ox, oy)
  fn fill(f:*Field,seed:u64,ox:i32,oy:i32)void{
    // every noise step the field needs
    var raw:[rw*rw]f32=undefined;
    for(0..rw)|y|for(0..rw)|x|{
      raw[y*rw+x]=rawStep(seed,ox-easeSpan-1+@as(i32,@intCast(x)),oy-easeSpan-1+@as(i32,@intCast(y)));
    };
    for(0..w)|y|for(0..w)|x|{
      // this tile among the noise steps, and the highest of its four neighbours'
      const i=(y+1)*rw+x+1;
      const near=@max(@max(raw[i-1],raw[i+1]),@max(raw[i-rw],raw[i+rw]));
      f.lv[y*w+x]=@min(raw[i],near);
    };
  }
};
/// one chunk tile's levelled terraces round it, read from its field
const InField=struct{
  /// the field
  f:*const Field,
  /// the tile in its chunk, across
  lx:i32,
  /// the tile in its chunk, down
  ly:i32,
  /// the levelled terrace `dx, dy` tiles off it
  fn step(s:InField,dx:i32,dy:i32)f32{return s.f.lv[@intCast((s.ly+dy+easeSpan)*Field.w+s.lx+dx+easeSpan)];}
};
/// the tile at world (wx, wy) for `seed`: its eased terraced height, kind,
/// ley and any resource node; the same for the same seed and tile,
/// whatever is loaded
pub fn sample(seed:u64,wx:i32,wy:i32)Sample{return sampleOn(seed,wx,wy,eased(Lone,.{.seed=seed,.wx=wx,.wy=wy}));}
/// the tile at world (wx, wy) as `sample` makes it but for its height (the
/// lowest ground): its kind, ley, node and water, without easing the
/// terraces round it
pub fn plain(seed:u64,wx:i32,wy:i32)Sample{return sampleOn(seed,wx,wy,0);}
/// the tile at world (wx, wy) standing on terrace `level` (in steps, eased)
fn sampleOn(seed:u64,wx:i32,wy:i32,level:f32)Sample{
  // the tile's place as numbers
  const x=m.f(wx);
  const y=m.f(wy);
  // the tile's place pushed by the domain warp
  const p=warped(seed,wx,wy);
  const wx2=p[0];
  const wy2=p[1];
  // the continent's elevation, the hills on it, and the two together
  const continent=continentOf(seed,p);
  const hills=hillAmount*noise.fbm(seed+%1,x/hillL,y/hillL,hillOct);
  const e=continent+hills;
  // how wet the ground is
  const wet=noise.fbm(seed+%2,x/wetL,y/wetL,wetOct);
  // how strong a ley vein runs here
  const vein=noise.ridged(seed+%3,wx2/veinL,wy2/veinL,veinOct);
  // its height on its terrace
  const height=level*terrace+intra*hills;
  // its ground kind: stone up high, ley on veins, moss where wet, else soil
  const kind:ck.Kind=if(e>stone).stone
    else if(vein>veinAmount).ley
    else if(wet>wetAmount).moss
    else.soil;
  // the ley it holds, many times more on a ley line
  const ley=leyBase+vein*vein*vein*(if(kind==.ley)leyLine else 1);
  // resource nodes cluster in noisy patches. No flora: every plant is seeded.
  // the tile's own roll, the node noise, and the patch noise
  const h=rng.unit(rng.hash2(seed+%7,wx,wy));
  const slot=noise.fbm(seed+%8,x/slotL,y/slotL,1);
  const patch=noise.fbm(seed+%5,x/patchL,y/patchL,patchOct);
  // the resource it holds, if a node sits here
  const res:ck.Res=if(patch>patchAmount and slot>slotAmount)@intFromFloat(resMin+h*resSpread)else 0;
  // the water its ground holds: as wet as it is, little in stone
  const water=m.unlerp(dryAt,dryAt+soakSpan,wet)*(if(kind==.stone)stoneWater else 1);
  return.{.height=height,.kind=kind,.ley=ley,.res=res,.sealed=leyBase+vein*vein*vein,.water=water};
}
/// the ground height of world tile (wx, wy)
pub fn heightAt(seed:u64,wx:i32,wy:i32)f32{return sample(seed,wx,wy).height;}
/// fills every tile of chunk `c` from the generator, all of them empty
pub fn generate(seed:u64,c:*ck.Chunk)void{
  // the levelled terraces round the chunk, read once
  var f:Field=.{};
  f.fill(seed,c.originX(),c.originY());
  for(0..ck.tileCount)|i|{
    // this tile's place in the world
    const wx,const wy=c.tileOf(i);
    // what the generator makes of it, eased from the field
    const s=sampleOn(seed,wx,wy,eased(InField,.{.f=&f,.lx=wx-c.originX(),.ly=wy-c.originY()}));
    c.height[i]=s.height;
    c.kind[i]=s.kind;
    c.ley[i]=s.ley;
    c.leyCap[i]=s.ley;
    c.water[i]=s.water;
    c.waterCap[i]=s.water;
    c.res[i]=s.res;
    c.occ[i]=.none;
  }
}
test"generation is deterministic"{
  // a chunk off the origin, and a copy of it
  var a=ck.blank(.{.x=-3,.y=7});
  var b=a;
  generate(1234,&a);
  generate(1234,&b);
  try testing.expectEqualSlices(f32,&a.height,&b.height);
  try testing.expectEqualSlices(ck.Kind,&a.kind,&b.kind);
}
/// a square of tiles, each one's value worked out once, for the tests that
/// sweep wide stretches of land and read every tile many times over:
/// tiles [lo, hi) each way
const Sweep=struct{
  /// the westmost (and northmost) tile it holds
  lo:i32,
  /// how many tiles across it is
  w:usize,
  /// each tile's value, row by row
  v:[]f32,
  /// every tile of [lo, hi) each way, its value `of(seed, x, y)`
  fn init(gpa:Allocator,seed:u64,lo:i32,hi:i32,comptime of:fn(u64,i32,i32)f32)Allocator.Error!Sweep{
    // tiles across, and the sweep being filled
    const w:usize=@intCast(hi-lo);
    const s:Sweep=.{.lo=lo,.w=w,.v=try gpa.alloc(f32,w*w)};
    for(0..w)|y|for(0..w)|x|{
      s.v[y*w+x]=of(seed,lo+@as(i32,@intCast(x)),lo+@as(i32,@intCast(y)));
    };
    return s;
  }
  /// frees its values
  fn deinit(s:Sweep,gpa:Allocator)void{gpa.free(s.v);}
  /// tile (x, y)'s value
  fn at(s:Sweep,x:i32,y:i32)f32{return s.v[@as(usize,@intCast(y-s.lo))*s.w+@as(usize,@intCast(x-s.lo))];}
};
/// the levelled terrace of tile (x, y), as a single tile works it out
fn loneStep(seed:u64,x:i32,y:i32)f32{return Lone.step(.{.seed=seed,.wx=x,.wy=y},0,0);}
/// one tile's levelled terraces round it, read from a sweep of them
const InSweep=struct{
  /// the sweep
  s:*const Sweep,
  /// the tile, across
  x:i32,
  /// the tile, down
  y:i32,
  /// the levelled terrace `dx, dy` tiles off it
  fn step(t:InSweep,dx:i32,dy:i32)f32{return t.s.at(t.x+dx,t.y+dy);}
};
test"no lone tile juts up above its four neighbours"{
  // the lone columns the noise alone would raise, so the test is known to bite
  var raw:usize=0;
  // a wide stretch of land and a tile round it: each tile's noise step, and
  // its terrace levelled, worked out once
  // decision: read from sweeps, so each tile is worked out once instead of
  // once per neighbour that looks at it (the same numbers, far sooner)
  const steps=try Sweep.init(testing.allocator,1234,-121,121,rawStep);
  defer steps.deinit(testing.allocator);
  const lv=try Sweep.init(testing.allocator,1234,-121,121,loneStep);
  defer lv.deinit(testing.allocator);
  // the stretch, its terraces read tile by tile
  var y:i32=-120;
  while(y<120):(y+=1){
    // the column being read
    var x:i32=-120;
    while(x<120):(x+=1){
      // the tile's terrace and its four neighbours'
      const own=steps.at(x,y);
      const at=lv.at(x,y);
      const near=@max(@max(lv.at(x-1,y),lv.at(x+1,y)),@max(lv.at(x,y-1),lv.at(x,y+1)));
      try testing.expect(at<=near);
      const rawNear=@max(@max(steps.at(x-1,y),steps.at(x+1,y)),@max(steps.at(x,y-1),steps.at(x,y+1)));
      if(own>rawNear)raw+=1;
    }
  }
  try testing.expect(raw>0);
  // the noise step is the continent's, warped, stepped
  try testing.expectEqual(stepOf(continentOf(1234,warped(1234,7,-3))),steps.at(7,-3));
}
test"a chunk eases its terraces just as single tiles do"{
  // a chunk off the origin, generated whole
  var c=ck.blank(.{.x=2,.y=-5});
  generate(1234,&c);
  for(0..ck.tileCount)|i|{
    // the tile, and the generator's sample of it alone
    const wx,const wy=c.tileOf(i);
    try testing.expectEqual(sample(1234,wx,wy).height,c.height[i]);
  }
}
test"terraces ease into one another, never a hard step between tiles"{
  // the steepest rise between neighbours: eased, and as the levelled terraces stand
  var steep:f32=0;
  var hard:f32=0;
  // every levelled terrace the ease reads, each worked out once
  const s=try Sweep.init(testing.allocator,1234,-80-easeSpan,80+1+easeSpan,loneStep);
  defer s.deinit(testing.allocator);
  // a single tile eases the same from them as on its own
  try testing.expectEqual(eased(Lone,.{.seed=1234,.wx=5,.wy=-9}),eased(InSweep,.{.s=&s,.x=5,.y=-9}));
  var y:i32=-80;
  while(y<80):(y+=1){
    // the column being read
    var x:i32=-80;
    while(x<80):(x+=1){
      // this tile's terrace and the next one's across and down, eased and levelled
      const at=eased(InSweep,.{.s=&s,.x=x,.y=y});
      const lv=s.at(x,y);
      inline for(.{.{1,0},.{0,1}})|d|{
        const next=eased(InSweep,.{.s=&s,.x=x+d[0],.y=y+d[1]});
        steep=@max(steep,@abs(next-at));
        hard=@max(hard,@abs(s.at(x+d[0],y+d[1])-lv));
      }
    }
  }
  // the land does climb whole terraces, which the ease spreads over a few tiles
  try testing.expect(hard>=1);
  try testing.expect(steep<=0.5*hard);
}
