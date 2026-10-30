//! mesh: TURN ROOT. one of the roots a rooted plant or structure walks on
//! while it turns (R, sim/turn.zig): built straight up +Y over 0..1 (bent on
//! the GPU along its curve, from under the body to its tip in the soil),
//! swelling out of the body and tapering to a hair at its tip, three
//! rootlets forking off its far half. Bark for the symbiotic lineage
//! (`build`), pale for the parasites' (`pale`). Out of the ground only
//! while it turns; at rest the whole of it is in the soil.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const mg=lib.meshgen;
const color=engine.core.color;
const vertex=lib.vertex;
const pal=lib.palette;
const pk=lib.parasiteKit;
const V3=m.V3;
const v3=m.v3;
/// its girth where it is thickest (world units: a curve keeps its girth)
const girth:f32=0.032;
/// it swells to `GIRTH` over this share of its length, from a point
const swell:f32=0.12;
/// where its rootlets fork off, how long they run (a share of its length)
/// and how far out they reach
const forks=[3]f32{0.45,0.62,0.78};
const forkLen:f32=0.16;
const forkOut:f32=0.05;
fn root(b:*mg.Builder,base:color.Rgba8,tip:color.Rgba8,part:vertex.Part)Allocator.Error!void{
  const n=20;
  var p:[n]V3=undefined;
  var ts:[n]f32=undefined;
  var rs:[n]f32=undefined;
  var cs:[n]color.Rgba8=undefined;
  for(&p,&ts,&rs,&cs,0..)|*q,*t,*r,*c,i|{
    const f=m.ratio(i,n-1);
    // a slight wander, so a root is never a rod
    q.*=v3(0.006*@sin(f*9),f,0.006*@cos(f*7));
    t.*=f;
    r.*=girth*m.smooth(m.clamp01(f/swell))*(1-f*0.94);
    c.*=color.mix(base,tip,m.smooth(f));
  }
  try b.tubeC(&p,&ts,&rs,&cs,null,part,6);
  for(forks,0..)|k,j|{
    const a=m.f(j)*2.4;
    const out=v3(@cos(a),0,@sin(a));
    var c:[5]V3=undefined;
    for(&c,0..)|*q,i|{
      const f=m.ratio(i,4);
      q.*=v3(0,k+forkLen*f,0)+out*m.splat3(forkOut*@sin(m.pi*0.5*f));
    }
    var fp:[8]V3=undefined;
    m.splineResample(&c,&fp);
    var ft:[8]f32=undefined;
    var fr:[8]f32=undefined;
    const r0=girth*(1-k*0.94)*0.55;
    for(&ft,&fr,0..)|*t,*r,i|{
      const f=m.ratio(i,7);
      t.*=k+forkLen*f;
      // out of its root from a point, and down to a hair
      r.*=r0*m.smooth(m.clamp01(f/0.2))*(1-f*0.9);
    }
    try b.tubeR(&fp,&ft,&fr,color.mix(base,tip,k),part,4);
  }
}
pub fn build(b:*mg.Builder)Allocator.Error!void{try root(b,pal.rootBark,pal.rootLite,.stem);}
pub const pale=struct{
  pub fn build(b:*mg.Builder)Allocator.Error!void{try root(b,pk.core,pk.pearl,.tendril);}
};
