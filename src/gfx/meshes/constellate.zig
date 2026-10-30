//! a rough sketch of the constellate lineage (tier 4), for the gardener to
//! check we see the same thing (`--samples=`): blue fragments floating
//! free, a thin line of light joining any two near enough (the plexus web),
//! and a solid pane filling every three that are all joined. One cluster of
//! fragments shown at three moments, the lines reaching further each time:
//! loose, forming, crystalline. Still, for now: the shifting is the GPU's,
//! once the look is settled.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, distances, normals
const m=engine.core.math;
/// the mesh builder and its tubes
const mg=lib.meshgen;
/// colours of the fragments, lines and panes
const color=engine.core.color;
/// the mineral kit: crystals and flat facets
const mineral=lib.mineralKit;
/// the engine's deterministic random stream, for where fragments float
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// how many fragments float in the cluster
const count=30;
/// the seed the cluster is scattered from, the same at every moment
const seed:u64=0xC0457E11A7E;
/// a fragment's deep blue, at its foot
const deep=color.rgb(0.10,0.30,0.95).toRgba8(255);
/// the pale blue it shifts to toward its point
const pale=color.rgb(0.55,0.85,1.0).toRgba8(255);
/// the light the lines are drawn in
const lineBlue=color.rgb(0.35,0.70,1.0).toRgba8(255);
/// a pane's ice blue, catching the light
const paneBlue=color.rgb(0.30,0.55,0.90).toRgba8(255);
/// how thick a pane is
const paneThick:f32=0.012;
/// how thick a line is at its middle
const lineR:f32=0.008;
/// where each fragment floats: an upright spindle of them, widest in the
/// middle, from knee height to over the wolf's head
fn points()[count]V3{
  // the cluster's own random stream, and where each fragment floats
  var rng=Rng.init(seed);
  var ps:[count]V3=undefined;
  for(&ps,0..)|*p,i|{
    // how far up the spindle, and how wide it is there
    const h=m.ratio(i,count-1);
    const w=0.2+0.4*@sin(m.pi*h);
    // its bearing round the spindle
    const a=rng.range(0,m.tau);
    const r=w*rng.range(0.35,1.0);
    p.*=v3(@cos(a)*r,0.5+1.2*h+rng.range(-0.06,0.06),@sin(a)*r);
  }
  return ps;
}
/// one cluster: every fragment, a line between each two within `reach`, a
/// pane across each three all within `reach` of one another
fn cluster(b:*mg.Builder,reach:f32)Allocator.Error!void{
  // where the fragments float, and the stream that turns them
  const ps=points();
  var rng=Rng.init(seed^0x5EED);
  // each fragment: a small crystal pointing a random way
  for(ps)|p|{
    // which way it points, and how long it is
    const d=m.norm(v3(rng.range(-1,1),rng.range(-0.4,1),rng.range(-1,1)));
    const len=rng.range(0.07,0.13);
    try mineral.crystal(b,.{.base=p-d*m.splat3(len*0.5),.dir=d,.len=len,.r=len*0.28,.col=deep,.tip=pale,.part=.bloom},&rng);
  }
  // the lines, each a tube pointed at both ends
  for(0..count)|i|for(i+1..count)|j|{
    if(m.len(ps[j]-ps[i])>reach)continue;
    try line(b,ps[i],ps[j]);
  };
  // the panes, across each three all joined
  for(0..count)|i|for(i+1..count)|j|for(j+1..count)|k|{
    // whether all three are joined to one another
    const near=m.len(ps[j]-ps[i])<=reach and m.len(ps[k]-ps[i])<=reach and m.len(ps[k]-ps[j])<=reach;
    if(near)try pane(b,.{ps[i],ps[j],ps[k]});
  };
}
/// a thin line of light from `a` to `z`, pointed at both ends
fn line(b:*mg.Builder,a:V3,z:V3)Allocator.Error!void{
  // how many rings run along it
  const steps=8;
  // its path, its flow and its radius, ring by ring
  var path:[steps]V3=undefined;
  var ts:[steps]f32=undefined;
  var rs:[steps]f32=undefined;
  for(&path,&ts,&rs,0..)|*p,*t,*r,i|{
    // how far along the line this ring is (0..1)
    const k=m.ratio(i,steps-1);
    p.*=a+(z-a)*m.splat3(k);
    t.*=k;
    r.*=@max(lineR*@sqrt(@max(0,@sin(m.pi*k))),2e-4);
  }
  try b.tubeR(&path,&ts,&rs,lineBlue,.bloom,4);
}
/// a solid pane across three fragments: a thin closed slab, two faces and
/// three edges
fn pane(b:*mg.Builder,c:[3]V3)Allocator.Error!void{
  // its face's normal and middle, and the half thickness either side
  const n=m.norm(m.cross(c[1]-c[0],c[2]-c[0]));
  const mid=m.centroid(c[0],c[1],c[2]);
  const o=n*m.splat3(paneThick*0.5);
  // drawn a little inside the fragments, so it hangs between them
  var top:[3]V3=undefined;
  var bot:[3]V3=undefined;
  for(c,&top,&bot)|p,*t,*u|{
    // this corner, drawn in toward the middle
    const q=mid+(p-mid)*m.splat3(0.85);
    t.*=q+o;
    u.*=q-o;
  }
  // every corner in the same ice blue
  const cs=[3]color.Rgba8{paneBlue,paneBlue,paneBlue};
  try mineral.facet(b,top,mid,cs,0.5,.bloom);
  try mineral.facet(b,bot,mid,cs,0.5,.bloom);
  for(0..3)|i|{
    // the next corner round
    const j=(i+1)%3;
    try mineral.facet(b,.{top[i],top[j],bot[j]},mid,cs,0.5,.bloom);
    try mineral.facet(b,.{top[i],bot[j],bot[i]},mid,cs,0.5,.bloom);
  }
}
/// mesh: CONSTELLATE, LOOSE. the fragments drifting, few of them joined
pub const loose=struct{
  /// builds the cluster, lines short
  pub fn build(b:*mg.Builder)Allocator.Error!void{try cluster(b,0.26);}
};
/// mesh: CONSTELLATE, FORMING. more joined, the first panes filling in
pub const forming=struct{
  /// builds the cluster, lines longer
  pub fn build(b:*mg.Builder)Allocator.Error!void{try cluster(b,0.38);}
};
/// mesh: CONSTELLATE, CRYSTALLINE. joined through, panes across most of it
pub const crystalline=struct{
  /// builds the cluster, lines long
  pub fn build(b:*mg.Builder)Allocator.Error!void{try cluster(b,0.5);}
};
