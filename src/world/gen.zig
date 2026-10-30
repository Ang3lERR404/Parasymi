//! world generation: a pure function of (seed, tile coordinate). Chunks never
//! depend on neighbours being loaded, so meshing and streaming stay order-free.
const lib=@import("../lib.zig");
const std=lib.std;
const engine=lib.engine;
const ck=lib.ck;
const testing=std.testing;
const m=engine.core.math;
const noise=engine.core.noise;
const rng=engine.core.rng;
pub const terrace=0.35;
/// terrace levels per unit of elevation noise; below `LOW` the ground lies
/// level on the lowest terrace (basins are lowland meadows)
const levels:f32=4;
const lowLevel:f32=-0.28;
/// elevation above which the ground is bare stone
const stone:f32=0.62;
/// ridged vein noise above this is a ley line; ley lines carry 4x the ley
const veinAmount:f32=0.955;
const leyBase:f32=0.2;
const leyLine:f32=4;
/// wetness above which the ground is moss, not soil
const wetAmount:f32=0.05;
/// noise wavelengths (tiles): domain warp (and how far it pushes),
/// continents, hills (and their share), wetness, veins, resource patches
const warpL:f32=90;
const warp:f32=14;
const continentL:f32=70;
const intra:f32=0.04;
const roughL:f32=120;
const hillL:f32=14;
const hillAmount:f32=0.25;
const wetL:f32=55;
const veinL:f32=45;
const patchL:f32=16;
/// octaves of each: warp, continents, hills, wetness, veins, patches
const warpOct=3;
const continentOct=5;
const hillOct=2;
const wetOct=3;
const veinOct=3;
const patchOct=2;
/// resource nodes: in patches denser than `PATCH`, on `NODE_CHANCE` of their
/// tiles, holding `RES_MIN` plus up to `RES_SPREAD` scaled by the tile hash
const patchAmount:f32=0.22;
const nodeChance:f32=0.6;
const resMin:f32=1500;
const resSpread:f32=3000;
/// the yardstick for how full a node looks (drawn at full size)
pub const resFull:f32=resMin+resSpread;
/// the most ley a tile holds (a ley line at full vein strength)
pub const leyMax:f32=leyBase+leyLine;
const slotL:f32=5;
const slotAmount:f32=0.4;
pub const Sample=struct{height:f32,kind:ck.Kind,ley:f32,res:ck.Res=0};
pub fn sample(seed:u64,wx:i32,wy:i32)Sample{
  const x=m.f(wx);
  const y=m.f(wy);
  // domain warp keeps coastlines and ridges organic instead of blobby.
  const wx2=x+warp*noise.fbm(seed+%11,x/warpL,y/warpL,warpOct);
  const wy2=y+warp*noise.fbm(seed+%12,x/warpL,y/warpL,warpOct);
  const continent=noise.fbm(seed,wx2/continentL,wy2/continentL,continentOct);
  const hills=hillAmount*noise.fbm(seed+%1,x/hillL,y/hillL,hillOct);
  const e=continent+hills;
  const wet=noise.fbm(seed+%2,x/wetL,y/wetL,wetOct);
  const vein=noise.ridged(seed+%3,wx2/veinL,wy2/veinL,veinOct);
  const level:f32=@floor(@max(continent-lowLevel,0)*levels)+1;
  const height=level*terrace+intra*hills;
  const kind:ck.Kind=if(e>stone).stone
    else if(vein>veinAmount).ley
    else if(wet>wetAmount).moss
    else.soil;
  const ley=leyBase+vein*vein*vein*(if(kind==.ley)leyLine else 1);
  // resource nodes cluster in noisy patches. No flora: every plant is seeded.
  const h=rng.unit(rng.hash2(seed+%7,wx,wy));
  const slot=noise.fbm(seed+%8,x/slotL,y/slotL,1);
  const patch=noise.fbm(seed+%5,x/patchL,y/patchL,patchOct);
  const res:ck.Res=if(patch>patchAmount and slot>slotAmount)@intFromFloat(resMin+h*resSpread)else 0;
  return.{.height=height,.kind=kind,.ley=ley,.res=res};
}
pub fn heightAt(seed:u64,wx:i32,wy:i32)f32{return sample(seed,wx,wy).height;}
pub fn generate(seed:u64,c:*ck.Chunk)void{
  for(0..ck.tileCount)|i|{
    const wx,const wy=c.tileOf(i);
    const s=sample(seed,wx,wy);
    c.height[i]=s.height;
    c.kind[i]=s.kind;
    c.ley[i]=s.ley;
    c.leyCap[i]=s.ley;
    c.res[i]=s.res;
    c.occ[i]=.none;
  }
}
test"generation is deterministic"{
  var a=ck.blank(.{.x=-3,.y=7});
  var b=a;
  generate(1234,&a);
  generate(1234,&b);
  try testing.expectEqualSlices(f32,&a.height,&b.height);
  try testing.expectEqualSlices(ck.Kind,&a.kind,&b.kind);
}
