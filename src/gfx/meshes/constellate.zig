//! a rough sketch of the constellate lineage (tier 4), for the gardener to
//! check we see the same thing (`--samples=`): solid points of light
//! floating free, a thin line of light joining any two near enough (the
//! plexus web), and a pane filling every three that are all joined. Each
//! web has a heart, the point most joined; it beats, and every beat runs
//! out through the web as a wave, lightening the blue of each point, line
//! and pane it passes (part.frag `PART_PLEXUS`, on the GPU). One cluster
//! shown at three moments, the lines reaching further each time: loose,
//! forming, crystalline. The points hold still for now.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, distances, normals
const m=engine.core.math;
/// the mesh builder, its tubes and balls
const mg=lib.meshgen;
/// colours of the points, lines and panes
const color=engine.core.color;
/// the mineral kit: flat facets, for the panes
const mineral=lib.mineralKit;
/// the engine's deterministic random stream, for where points float
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// how many points float in the cluster
const count=30;
/// the seed the cluster is scattered from, the same at every moment
const seed:u64=0xC0457E11A7E;
/// the blue everything is drawn in (part.frag lightens it as a beat passes)
const blue=color.rgb(0.25,0.55,1.0).toRgba8(255);
/// how big a point of light is
const pointR:f32=0.015;
/// how thick a pane is
const paneThick:f32=0.01;
/// how thick a line is at its middle
const lineR:f32=0.007;
/// what a piece of the web is (tu.y): part.frag draws each its own way
const Kind=enum(u8){
  /// a solid point of light
  point,
  /// a line of light between two points
  line,
  /// a pane across three
  pane,
};
/// a point the beat reaches, and how far it has run through the web to
/// get there (from its heart, along the lines)
const Reached=struct{
  /// where the point floats
  at:V3,
  /// how far the beat runs to reach it
  dist:f32,
};
/// where each point floats: an upright spindle of them, widest in the
/// middle, from knee height to over the wolf's head
fn points()[count]V3{
  // the cluster's own random stream, and where each point floats
  var rng=Rng.init(seed);
  var ps:[count]V3=undefined;
  for(&ps,0..)|*p,i|{
    // how far up the spindle, and how wide it is there
    const h=m.ratio(i,count-1);
    const w=0.2+0.4*@sin(m.pi*h);
    // its bearing round the spindle, and how far out
    const a=rng.range(0,m.tau);
    const r=w*rng.range(0.35,1.0);
    p.*=v3(@cos(a)*r,0.5+1.2*h+rng.range(-0.06,0.06),@sin(a)*r);
  }
  return ps;
}
/// whether points `i` and `j` are joined by a line
fn joined(ps:[count]V3,i:usize,j:usize,reach:f32)bool{return i!=j and m.len(ps[j]-ps[i])<=reach;}
/// how far the beat runs to reach each point: each web's heart is its most
/// joined point (the first, if even), and the beat runs out from it along
/// the lines, the shortest way (Dijkstra)
fn distances(ps:[count]V3,reach:f32)[count]f32{
  // how far to each point, and which are settled
  var d=[_]f32{m.inf(f32)}**count;
  var done=[_]bool{false}**count;
  // each point's lines
  var links=[_]u32{0}**count;
  for(0..count)|i|for(0..count)|j|{
    if(joined(ps,i,j,reach))links[i]+=1;
  };
  while(true){
    // the next web's heart: the most joined point not yet reached
    var heart:?usize=null;
    for(0..count)|i|{
      if(done[i] or d[i]<m.inf(f32))continue;
      if(heart==null or links[i]>links[heart.?])heart=i;
    }
    const h=heart orelse break;
    d[h]=0;
    while(true){
      // the nearest unsettled point reached so far
      var near:?usize=null;
      for(0..count)|i|{
        if(done[i] or d[i]==m.inf(f32))continue;
        if(near==null or d[i]<d[near.?])near=i;
      }
      const n=near orelse break;
      done[n]=true;
      for(0..count)|j|{
        if(!joined(ps,n,j,reach))continue;
        d[j]=@min(d[j],d[n]+m.len(ps[j]-ps[n]));
      }
    }
  }
  return d;
}
/// tag every vertex since `start` as `kind`, with how far the beat runs to
/// reach it: from the nearest of `from`, straight across to it
fn tag(b:*mg.Builder,start:usize,from:[]const Reached,kind:Kind)void{
  for(b.v.items[start..])|*v|{
    // the soonest the beat reaches this vertex
    var t:f32=m.inf(f32);
    for(from)|f|t=@min(t,f.dist+m.len(v.pos-f.at));
    v.tu=.{t,m.f(@intFromEnum(kind))};
  }
}
/// one cluster: every point, a line between each two within `reach`, a
/// pane across each three all within `reach` of one another
fn cluster(b:*mg.Builder,reach:f32)Allocator.Error!void{
  // where the points float, and how far the beat runs to each
  const ps=points();
  const ds=distances(ps,reach);
  // each point: a ball of light
  for(ps,ds)|p,d|{
    // where its vertices begin
    const s=b.mark();
    try mg.ellipsoid(b,.{.center=p,.radii=m.splat3(pointR),.col=blue,.part=.plexus,.rings=6,.segs=8});
    tag(b,s,&.{.{.at=p,.dist=d}},.point);
  }
  // the lines, each a tube pointed at both ends
  for(0..count)|i|for(i+1..count)|j|{
    if(!joined(ps,i,j,reach))continue;
    // where its vertices begin
    const s=b.mark();
    try line(b,ps[i],ps[j]);
    tag(b,s,&.{.{.at=ps[i],.dist=ds[i]},.{.at=ps[j],.dist=ds[j]}},.line);
  };
  // the panes, across each three all joined
  for(0..count)|i|for(i+1..count)|j|for(j+1..count)|k|{
    if(!(joined(ps,i,j,reach) and joined(ps,i,k,reach) and joined(ps,j,k,reach)))continue;
    // where its vertices begin
    const s=b.mark();
    try pane(b,.{ps[i],ps[j],ps[k]});
    tag(b,s,&.{.{.at=ps[i],.dist=ds[i]},.{.at=ps[j],.dist=ds[j]},.{.at=ps[k],.dist=ds[k]}},.pane);
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
  try b.tubeR(&path,&ts,&rs,blue,.plexus,4);
}
/// a pane across three points: a thin closed slab, two faces and three
/// edges, drawn a little inside the points so it hangs between them
fn pane(b:*mg.Builder,c:[3]V3)Allocator.Error!void{
  // its face's normal and middle, and the half thickness either side
  const n=m.norm(m.cross(c[1]-c[0],c[2]-c[0]));
  const mid=m.centroid(c[0],c[1],c[2]);
  const o=n*m.splat3(paneThick*0.5);
  // its corners on either face
  var top:[3]V3=undefined;
  var bot:[3]V3=undefined;
  for(c,&top,&bot)|p,*t,*u|{
    // this corner, drawn in toward the middle
    const q=mid+(p-mid)*m.splat3(0.85);
    t.*=q+o;
    u.*=q-o;
  }
  // every corner in the same blue
  const cs=[3]color.Rgba8{blue,blue,blue};
  try mineral.facet(b,top,mid,cs,0,.plexus);
  try mineral.facet(b,bot,mid,cs,0,.plexus);
  for(0..3)|i|{
    // the next corner round
    const j=(i+1)%3;
    try mineral.facet(b,.{top[i],top[j],bot[j]},mid,cs,0,.plexus);
    try mineral.facet(b,.{top[i],bot[j],bot[i]},mid,cs,0,.plexus);
  }
}
/// mesh: CONSTELLATE, LOOSE. the points drifting, few of them joined
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
