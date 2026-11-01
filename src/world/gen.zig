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
/// the tile at world (wx, wy) for `seed`: its terraced height, kind, ley and
/// any resource node; the same for the same seed and tile, whatever is loaded
pub fn sample(seed:u64,wx:i32,wy:i32)Sample{
  // the tile's place as numbers
  const x=m.f(wx);
  const y=m.f(wy);
  // domain warp keeps coastlines and ridges organic instead of blobby.
  // the tile's place pushed by the domain warp
  const wx2=x+warp*noise.fbm(seed+%11,x/warpL,y/warpL,warpOct);
  const wy2=y+warp*noise.fbm(seed+%12,x/warpL,y/warpL,warpOct);
  // the continent's elevation, the hills on it, and the two together
  const continent=noise.fbm(seed,wx2/continentL,wy2/continentL,continentOct);
  const hills=hillAmount*noise.fbm(seed+%1,x/hillL,y/hillL,hillOct);
  const e=continent+hills;
  // how wet the ground is
  const wet=noise.fbm(seed+%2,x/wetL,y/wetL,wetOct);
  // how strong a ley vein runs here
  const vein=noise.ridged(seed+%3,wx2/veinL,wy2/veinL,veinOct);
  // which terrace the tile stands on, and its height there
  const level:f32=@floor(@max(continent-lowLevel,0)*levels)+1;
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
  for(0..ck.tileCount)|i|{
    // this tile's place in the world
    const wx,const wy=c.tileOf(i);
    // what the generator makes of it
    const s=sample(seed,wx,wy);
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
