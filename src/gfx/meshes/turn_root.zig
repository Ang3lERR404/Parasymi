//! mesh: TURN ROOT. one of the roots a rooted plant or structure walks on
//! while it turns (R, sim/turn.zig): built straight up +Y over 0..1 (bent on
//! the GPU along its curve, from under the body to its tip in the soil),
//! swelling out of the body and tapering to a hair at its tip, three
//! rootlets forking off its far half. Bark for the symbiotic lineage
//! (`build`), pale for the parasites' (`pale`). Out of the ground only
//! while it turns; at rest the whole of it is in the soil.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error every building call may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, splines, easing
const m=engine.core.math;
/// the plant-piece mesh builder the root is laid into
const mg=lib.meshgen;
/// colour mixing, for the root's fade from base to tip
const color=engine.core.color;
/// part roles: how the shader draws each piece
const vertex=lib.vertex;
/// the garden's shared colours (root bark)
const pal=lib.palette;
/// the parasites' kit, whose pale colours the pale root wears
const pk=lib.parasiteKit;
/// a point or direction in 3D
const V3=m.V3;
/// makes a `V3` from three numbers
const v3=m.v3;
/// its girth where it is thickest (world units: a curve keeps its girth)
const girth:f32=0.032;
/// it swells to `girth` over this share of its length, from a point
const swell:f32=0.12;
/// where its three rootlets fork off, as shares of its length
const forks=m.Vice(f32,3){0.45,0.62,0.78};
/// how long each rootlet runs, as a share of the root's length
const forkLen:f32=0.16;
/// how far out a rootlet bows from the root at its widest (world units)
const forkOut:f32=0.05;
/// lays one root: a wandering tube up 0..1 that swells from a point and
/// thins to a hair, coloured `base` fading to `tip`, then its three
/// rootlets bowing out of its far half; every piece drawn as `part`
fn root(b:*mg.Builder,base:color.Rgba8,tip:color.Rgba8,part:vertex.Part)Allocator.Error!void{
  // how many rings the root is built of
  const n=20;
  // each ring's centre, its place along the root (0..1), its radius and its colour
  var p:[n]V3=undefined;
  var ts:[n]f32=undefined;
  var rs:[n]f32=undefined;
  var cs:[n]color.Rgba8=undefined;
  for(&p,&ts,&rs,&cs,0..)|*q,*t,*r,*c,i|{
    // how far up the root this ring sits, 0 at the body to 1 at the tip
    const f=m.ratio(i,n-1);
    // a slight wander, so a root is never a rod
    q.*=v3(0.006*@sin(f*9),f,0.006*@cos(f*7));
    t.*=f;
    r.*=girth*m.smooth(m.clamp01(f/swell))*(1-f*0.94);
    c.*=color.mix(base,tip,m.smooth(f));
  }
  try b.tubeC(&p,&ts,&rs,&cs,null,part,6);
  for(forks,0..)|k,j|{
    // the rootlet's heading round the root, and the flat direction it bows out along
    const a=m.f(j)*2.4;
    const out=v3(@cos(a),0,@sin(a));
    // the rootlet's five guide points, up the root and bowing outward
    var c:[5]V3=undefined;
    for(&c,0..)|*q,i|{
      // how far along the rootlet this guide point is, 0..1
      const f=m.ratio(i,4);
      q.*=v3(0,k+forkLen*f,0)+out*m.splat3(forkOut*@sin(m.pi*0.5*f));
    }
    // the guide points smoothed into eight rings along a spline
    var fp:[8]V3=undefined;
    m.splineResample(&c,&fp);
    // each rootlet ring's place along the root (0..1) and its radius
    var ft:[8]f32=undefined;
    var fr:[8]f32=undefined;
    // the rootlet's fullest radius: a little over half the root's girth where it forks
    const r0=girth*(1-k*0.94)*0.55;
    for(&ft,&fr,0..)|*t,*r,i|{
      // how far along the rootlet this ring is, 0..1
      const f=m.ratio(i,7);
      t.*=k+forkLen*f;
      // out of its root from a point, and down to a hair
      r.*=r0*m.smooth(m.clamp01(f/0.2))*(1-f*0.9);
    }
    try b.tubeR(&fp,&ft,&fr,color.mix(base,tip,k),part,4);
  }
}
/// the symbiotic root: dark bark lightening to its tip, drawn as stem
pub fn build(b:*mg.Builder)Allocator.Error!void{try root(b,pal.rootBark,pal.rootLite,.stem);}
/// mesh: TURN ROOT, PALE. the parasites' root, the same shape in their colours
pub const pale=struct{
  /// the pale root: parasite core fading to pearl at its tip, drawn as tendril
  pub fn build(b:*mg.Builder)Allocator.Error!void{try root(b,pk.core,pk.pearl,.tendril);}
};
