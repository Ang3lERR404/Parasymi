//! mesh: three new bodies for the convergence kit, to choose between side by
//! side (`--samples=driftbraidGrafted,driftbraidStrangler,driftbraidTissue,driftbraidBlend`), each
//! the size of a driftbraid and crowned as it is (a sac of both saps, five
//! boughs each ending in the kit's flower of both, kept as they are). The
//! lineages still mix at every scale, but grown as living things grow into
//! each other, uneven, not wound as an exact cage:
//! - grafted: a symbiote's braided stem and a parasite's smooth pale one
//!   rising side by side, winding loosely round each other, grown together
//!   where they touch (violet scars, lumpy, neither one's colour) and fused
//!   at last into one stem of green strands over a pale core;
//! - strangler: a symbiote's living trunk, leafy, netted in the parasites'
//!   five pale roots let down from its crown as a strangler fig's are,
//!   bridged to each other where they meet round it (violet knots), and
//!   standing on the ground as prop roots;
//! - tissue: one soft see-through body (as the polyp's), green strands and
//!   amber lanes of sap winding inside it, the parasites' five pale ribs
//!   exact up its skin, leaves sprouting out of it and five plumed pale
//!   tentacles hanging from a collar under its crown.
//! Grown along one skeleton each: roots, then the body, the crown last.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, rng
const engine=lib.engine;
/// all the maths: vectors, lerps, splines
const m=engine.core.math;
/// the garden's meshgen: builder, leaves, ellipsoids, tubes
const mg=lib.meshgen;
/// colour types and mixing
const color=engine.core.color;
/// growth splines: the skeleton each look grows along
const growth=lib.growth;
/// the garden's palette: the symbiotes' core and strand wander
const pal=lib.palette;
/// the parasite kit: frond paths, nodules
const pk=lib.parasiteKit;
/// the convergence kit: its foot, sac, flowers and colours
const kit=lib.convergenceKit;
/// the seeded random stream that makes each symbiote's piece its own
const Rng=engine.core.rng.Rng;
/// a vertex colour
const Rgba8=color.Rgba8;
/// a point or direction in 3D
const V3=m.V3;
/// builds a point or direction
const v3=m.v3;
/// how many points a spline is resampled into
const res=growth.res;
/// the soft body of both: the parasites' pale skin flushed with violet, see-through
const tissue=color.rgb(0.66,0.46,0.95).toRgba8(255);
/// the body's foot, a little deeper, warmed by the amber rising in it
const tissueLow=color.rgb(0.92,0.6,0.38).toRgba8(255);
/// a graft's scar: where the two have grown into each other, violet
const scar=kit.violet;
// ---- the crown every look ends in ----
/// how a bough is built
const Bough=enum{
  /// a braid of green strands over a pale core, grafted as the stem is
  grafted,
  /// the parasites' lilac, as the kit's fronds are
  lilac,
  /// see-through tissue round a green vein
  tissue,
};
/// how a look's crown is laid: the sac it holds up, its boughs, its seed
const Crown=struct{
  /// the sac's half-sizes
  sacR:V3,
  /// how far a bough reaches out
  reach:f32,
  /// a bough's radius at its foot
  r:f32,
  /// how its boughs are built
  bough:Bough,
  /// its own seed
  seed:u64,
};
/// the crown on top of spline `stem`: a sac of both saps, young folded
/// leaves round its foot, and five boughs arching out under it, alike in
/// count and turn, each its own length, leaves along it and the kit's
/// flower of both at its tip
fn crown(b:*mg.Builder,k:*growth.Skeleton,stem:growth.Id,c:Crown)Allocator.Error!void{
  // the stem's top, and the sac sat on it
  const top=k.point(stem,1);
  const at=top+v3(0,c.sacR[1]*0.75,0);
  const sacMk=b.mark();
  try kit.sac(b,.{.center=at,.radii=c.sacR,.t=0.75,.arms=3,.phase=0.6});
  try k.on(b,sacMk,stem,1,.{.from=top});
  // the crown's own stream, so each bough is its own length
  var rng=Rng.init(c.seed);
  // young leaves folded upward round the sac's foot
  for(0..3)|i|{
    // its bearing, and where it springs
    const a=m.ratio(i,3)*m.tau+rng.range(-0.4,0.4);
    const out=v3(@cos(a),0,@sin(a));
    const base=top+out*m.splat3(c.r*1.2);
    const mk=b.mark();
    try mg.natural(b,base,m.norm(out*m.splat3(0.35)+v3(0,1,0)),0.045*rng.range(0.8,1.2),0.016,0.05,kit.leafDark,kit.leafLite,0.9,.stalked);
    try k.on(b,mk,stem,1,.{.from=base,.delay=0.12});
  }
  for(0..kit.fold)|i|{
    // this bough's bearing, set evenly between the others
    const a=(m.f(i)+0.5)/m.f(kit.fold)*m.tau;
    const out=v3(@cos(a),0,@sin(a));
    // its course: out from under the sac, arching and curling down
    var p:[8]V3=undefined;
    pk.frondPath(top,out,c.reach*rng.range(0.85,1.12),0.6,2.0,c.seed^0xB0,&p);
    const id=k.branch(stem,1,&p,.{.delay=0.06});
    switch(c.bough){
      .grafted=>try k.braid(b,id,.{.girth=c.r,.tip=0.45,.strands=3,.twist=1.6,.wobble=pal.strandWobble,.seed=c.seed+%i*13,.core=kit.pale,.strand=kit.green,.t0=0.75,.t1=1}),
      .lilac=>try k.tube(b,id,.{.r0=c.r,.tip=0.45,.col=kit.lilac,.part=.tendril,.sides=5,.t0=0.75,.t1=1}),
      .tissue=>{
        try k.tube(b,id,.{.r0=c.r,.tip=0.5,.col=tissue,.part=.bloom,.sides=7,.t0=0.75,.t1=1});
        try k.tube(b,id,.{.r0=c.r*0.35,.tip=0.5,.col=kit.green,.part=.stem,.sides=4,.t0=0.75,.t1=1});
      },
    }
    try k.leaves(b,id,.{.n=6,.len=0.08,.width=0.028,.from=0.25,.to=0.9,.t0=0.75,.t1=1,.col=kit.leafDark,.tip=kit.leafLite,.seed=c.seed+%i*97});
    // the flower at its tip, opening last
    const fl=b.mark();
    const tip=k.point(id,1);
    try kit.bloom(b,.{.heart=tip,.len=0.06,.spin=a,.petals=6,.seed=0xD1F4});
    try k.on(b,fl,id,1,.{.from=tip});
  }
}
/// green braided roots out of spline `id` where it meets the ground, each
/// its own bearing and reach
fn greenRoots(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,at:V3,n:usize,reach:f32,girth:f32,seed:u64)Allocator.Error!void{
  // where along the spline the ground is
  const u=k.nearest(id,at);
  var rng=Rng.init(seed);
  for(0..n)|i|{
    // its bearing, jittered off even
    const a=(m.f(i)+rng.range(-0.3,0.3))/m.f(n)*m.tau+0.3;
    var c:[6]V3=undefined;
    kit.rootPath(at,a,girth,reach*rng.range(0.75,1.1),0.3,seed+%i*41,&c);
    const r=k.branch(id,u,&c,.{.after=.with});
    try k.braid(b,r,.{.girth=girth*0.55,.tip=0.3,.wobble=pal.strandWobble,.seed=seed+%i*7,.core=pal.core,.strand=kit.green,.t0=0.03,.t1=0});
  }
}
/// a run of natural leaves on their own stalks springing off the surface
/// round spline `id` (`r(u)` out from it), each at its own height and
/// bearing over `from..to`
fn sprouts(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,n:usize,from:f32,to:f32,len:f32,comptime r:fn(f32)f32,seed:u64)Allocator.Error!void{
  var rng=Rng.init(seed);
  for(0..n)|i|{
    // how far up, its bearing (the golden angle on, jittered), and the way out
    const u=m.lerp(from,to,(m.f(i)+rng.range(0.2,0.8))/m.f(n));
    const a=m.f(i)*2.39996+rng.range(-0.3,0.3);
    const out=v3(@cos(a),0,@sin(a));
    const base=k.point(id,u)+out*m.splat3(r(u)*0.92);
    const mk=b.mark();
    try mg.natural(b,base,m.norm(out+v3(0,rng.range(0.15,0.6),0)),len*rng.range(0.7,1.25),len*0.38,0.4,kit.leafDark,kit.leafLite,0.5,.stalked);
    try k.on(b,mk,id,u,.{.from=base});
  }
}
// ---- grafted ----
/// how high the grafted look's two stems climb before they are one
const fuseH:f32=0.62;
/// the grafted look's top
const graftTop=v3(0.015,0.95,-0.01);
/// where the stems have grown together (shares of their climb), before
/// they fuse for good at the top
const grafts=[_]f32{0.25,0.75};
/// where the green (`side` 1) or pale (`side` -1) stem lies `u` up a climb
/// `h` high: opposite each other round the middle, winding loosely, apart
/// most between the grafts, touching at each and meeting at the top; the
/// green wandering a little, the pale exact
fn stemAt(side:f32,u:f32,h:f32)V3{
  // their turn round the middle, and how far from it each lies
  const a=0.4+(if(side>0)@as(f32,0)else m.pi)+2.1*u;
  const s=@sin(m.pi*(2*u+0.5));
  const sep=m.lerp(0.09,0.042,u)*(0.22+0.78*s*s)*(1-m.smooth(m.clamp01((u-0.86)/0.14)));
  // the green's wander
  const wd:f32=if(side>0)0.008*@sin(u*9+1.3)else 0;
  return v3(@cos(a)*(sep+wd),u*h,@sin(a)*(sep+wd));
}
/// where two stems have grown together, and how big the callus round it is
const Union=struct{
  /// its middle
  at:V3,
  /// the green stem's middle there
  green:V3,
  /// the pale stem's middle there
  pale:V3,
  /// how far it swells past the stems' middles, and how deep it is square to them
  r:f32,
  /// half its length up the stems
  h:f32,
  /// its growth tu.x
  t:f32,
  /// turns its seam's wander, so no two seams run alike
  phase:f32,
};
/// a graft's union: one smooth callus round where the two stems have grown
/// together, long up them and wide across the join, its ends sinking into
/// both; green on the green stem's side, pale on the pale one's, and
/// between them a violet seam wandering up it, lit lilac along its middle
fn graftUnion(b:*mg.Builder,u:Union)Allocator.Error!void{
  // the way across the join (flat, pale to green), square to it, and half the join's width
  const d0=v3(u.green[0]-u.pale[0],0,u.green[2]-u.pale[2]);
  const across=if(m.len(d0)>1e-4)m.norm(d0)else v3(1,0,0);
  const side=m.cross(v3(0,1,0),across);
  const half=m.len(d0)*0.5;
  // built round the origin in its own frame, then turned onto the join
  const mk=b.mark();
  try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(half+u.r,u.h,u.r*0.9),.col=scar,.part=.stem,.rings=14,.segs=18,.t=u.t});
  for(b.v.items[mk..])|*vx|{
    // its place and facing in its own frame
    const q:V3=vx.pos;
    const n:V3=vx.nrm;
    vx.pos=u.at+across*m.splat3(q[0])+v3(0,q[1],0)+side*m.splat3(q[2]);
    vx.nrm=across*m.splat3(n[0])+v3(0,n[1],0)+side*m.splat3(n[2]);
    // how far to either side of the seam: -1 the pale's, 1 the green's,
    // the seam wandering as it climbs
    const s=q[0]/(half+u.r)+0.2*@sin(q[1]/u.h*4.2+u.phase)+0.08*@sin(q[2]/u.r*3+u.phase*2);
    // how far into its own side, past the seam's width
    const w=m.smooth(m.clamp01((@abs(s)-0.06)/0.3));
    const seam=color.mix(kit.knot,scar,m.smooth(m.clamp01(@abs(s)/0.06)));
    vx.col=color.mix(seam,if(s>0)kit.green else kit.pale,w);
  }
}
/// how a grafted foot is laid: how high its stems climb, the tu.x they
/// reach at the top, how many leaves the green one carries, its seed
const Base=struct{
  /// how high the stems climb before they fuse
  h:f32,
  /// their tu.x at the top
  t1:f32,
  /// leaves along the green stem
  leaves:u32,
  /// its own seed
  seed:u64,
};
/// what a grafted foot is built on: the hidden middle the stems rise
/// round, and the two stems
const Stems=struct{
  /// the hidden middle, its top where the two fuse
  mid:growth.Id,
  /// the symbiote's green braided stem
  green:growth.Id,
  /// the parasite's pale smooth stem
  pale:growth.Id,
};
/// two stems grafted into one: a green braided stem and a pale smooth one,
/// each rooted its own way, rising round each other, grown together in a
/// callus at each graft and fused in a long callus at the top; the pale one
/// swelling at its exact nodes, the green one leafy
fn graftedBase(b:*mg.Builder,k:*growth.Skeleton,o:Base)Allocator.Error!Stems{
  // a hidden middle the two rise round, timing them together
  const mid=k.trunk(&.{v3(0,-0.12,0),v3(0,o.h*0.5,0),v3(0,o.h,0)},.{.pace=1.5});
  var stems:[2]growth.Id=undefined;
  for(&stems,[_]f32{1,-1})|*st,side|{
    // its course: up out of the soil beside the middle, round it
    var c:[12]V3=undefined;
    c[0]=v3(0,-0.12,0);
    c[1]=stemAt(side,0,o.h)-v3(0,0.05,0);
    for(c[2..],0..)|*q,j|q.*=stemAt(side,m.ratio(j,9),o.h);
    st.*=k.branch(mid,0,&c,.{.after=.with,.pace=1.5});
  }
  const green=stems[0];
  const pale=stems[1];
  try k.braid(b,green,.{.girth=0.032,.tip=0.5,.strands=4,.twist=2.4,.wobble=pal.strandWobble*1.4,.seed=o.seed,.core=pal.core,.strand=kit.green,.t0=0,.t1=o.t1});
  // the pale stem, swelling at its exact nodes between the grafts: its
  // own skin thickening and paling to pearl into each, lilac at the
  // middle, and out again, never a ring stuck on
  {
    var nodes:[3]f32=undefined;
    for(&nodes,[_]f32{0.12,0.45,0.58})|*nu,u|nu.*=k.nearest(pale,stemAt(-1,u,o.h));
    var pp:[tentRes]V3=undefined;
    var pts:[tentRes]f32=undefined;
    var prs:[tentRes]f32=undefined;
    var pcs:[tentRes]Rgba8=undefined;
    k.path(pale,0,1,&pp);
    for(&pts,&prs,&pcs,0..)|*t,*r,*cl,i|{
      const u=m.ratio(i,tentRes-1);
      // how far into a node this point is (0 between, 1 at its middle)
      var node:f32=0;
      for(nodes)|nu|node=@max(node,m.smooth(m.clamp01(1-@abs(u-nu)/0.045)));
      t.*=u*o.t1;
      r.*=0.031*m.lerp(1,0.75,u)*(1+0.32*node);
      cl.*=color.mix(color.mix(kit.pale,kit.pearl,node),kit.lilac,m.smooth(m.clamp01((node-0.75)/0.25))*0.6);
    }
    const mk=b.mark();
    try b.tubeC(&pp,&pts,&prs,&pcs,null,.stem,8);
    try k.along(b,mk,pale);
  }
  // where they have grown into each other: one callus round each join,
  // the last (where they fuse for good) the longest
  for(grafts++[_]f32{0.97},0..)|u,j|{
    const g=stemAt(1,u,o.h);
    const p=stemAt(-1,u,o.h);
    const at=m.lerpV(g,p,0.5);
    const last=u>0.9;
    const mk=b.mark();
    try graftUnion(b,.{.at=at+v3(0,if(last)@as(f32,0.035)else 0,0),.green=g,.pale=p,.r=if(last)@as(f32,0.036)else 0.027,.h=if(last)@as(f32,0.13)else 0.088,.t=u*o.t1,.phase=m.f(j)*2.1});
    try k.on(b,mk,mid,u,.{.from=at,.delay=0.05});
  }
  try k.leaves(b,green,.{.n=o.leaves,.len=0.095,.width=0.036,.from=0.18,.to=0.92,.t0=o.t1*0.35,.t1=o.t1,.col=kit.leafDark,.tip=kit.leafLite,.seed=o.seed^0x1EAF});
  // rooted both ways: a pale bulb and five exact pale roots under the pale
  // stem, green braided roots under the green
  {
    const at=stemAt(-1,0,o.h);
    const mk=b.mark();
    try pk.nodule(b,at+v3(0,0.012,0),v3(0.05,0.028,0.05),0,kit.pale,color.mix(kit.pale,kit.lilac,0.4),kit.pearl);
    try k.on(b,mk,pale,k.nearest(pale,at),.{.from=at});
    for(0..kit.fold)|i|{
      var c:[6]V3=undefined;
      kit.rootPath(at,m.ratio(i,kit.fold)*m.tau,0.03,0.3,0.2,o.seed^0x9A1E,&c);
      const r=k.branch(pale,k.nearest(pale,at),&c,.{.after=.with});
      try k.tube(b,r,.{.r0=0.011,.tip=0.06,.col=kit.pearl,.sides=5,.t0=0,.t1=0.03});
    }
  }
  try greenRoots(b,k,green,stemAt(1,0,o.h),4,0.3,0.03,o.seed^0x5007);
  return.{.mid=mid,.green=green,.pale=pale};
}
/// the grafted look
pub const grafted=struct{
  /// builds it
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    var k=growth.Skeleton.begin(b);
    const st=try graftedBase(b,&k,.{.h=fuseH,.t1=0.55,.leaves=9,.seed=0x6AF1});
    // fused: one stem of green strands over the pale core, to the top,
    // rising out of the last callus (no collar: the callus is its foot)
    const f0=stemAt(1,1,fuseH);
    const fused=k.branch(st.green,1,&.{f0,f0+v3(0.012,0.1,0),f0+v3(-0.01,0.22,0.012),graftTop},.{});
    {
      var fp:[res]V3=undefined;
      var fts:[res]f32=undefined;
      var frs:[res]f32=undefined;
      k.path(fused,0,1,&fp);
      for(&fts,&frs,0..)|*t,*r,i|{
        const u=m.ratio(i,res-1);
        t.*=m.lerp(0.55,0.72,u);
        r.*=0.046*m.lerp(1,0.72,u)*m.lerp(0.45,1,m.smooth(m.clamp01(u/0.2)));
      }
      const mk=b.mark();
      try mg.braid(b,&fp,&fts,&frs,5,1.3,pal.strandWobble*1.2,0x6AF3,kit.pale,kit.green);
      try k.along(b,mk,fused);
    }
    try k.leaves(b,fused,.{.n=6,.len=0.09,.width=0.034,.from=0.15,.to=0.85,.t0=0.6,.t1=0.75,.col=kit.leafDark,.tip=kit.leafLite,.seed=0x6AF5});
    // a green shoot off the green stem, and a pale spur off the pale one,
    // ending in a pearl
    {
      const at=stemAt(1,0.5,fuseH);
      const out=m.norm(v3(at[0],0,at[2]));
      const sh=k.branch(st.green,0.5,&.{at,at+out*m.splat3(0.08)+v3(0,0.05,0),at+out*m.splat3(0.17)+v3(0,0.14,0),at+out*m.splat3(0.22)+v3(0,0.2,0)},.{.after=.passing,.delay=0.05});
      try k.tube(b,sh,.{.r0=0.011,.tip=0.4,.col=kit.green,.sides=5,.t0=0.4,.t1=0.6});
      try k.leaves(b,sh,.{.n=4,.len=0.065,.width=0.026,.from=0.3,.to=1,.t0=0.45,.t1=0.65,.col=kit.leafDark,.tip=kit.leafLite,.seed=0x6AF6});
    }
    {
      const at=stemAt(-1,0.35,fuseH);
      const out=m.norm(v3(at[0],0,at[2]));
      const tip=at+out*m.splat3(0.13)+v3(0,0.06,0);
      const sp=k.branch(st.pale,0.35,&.{at,at+out*m.splat3(0.07)+v3(0,0.01,0),tip},.{.after=.passing});
      try k.tube(b,sp,.{.r0=0.009,.tip=0.5,.col=kit.pale,.sides=5,.t0=0.3,.t1=0.45});
      const mk=b.mark();
      try pk.nodule(b,tip,m.splat3(0.014),0.45,kit.pearl,kit.lilac,kit.pearl);
      try k.on(b,mk,sp,1,.{.from=tip});
    }
    try crown(b,&k,fused,.{.sacR=v3(0.09,0.105,0.09),.reach=0.4,.r=0.016,.bough=.grafted,.seed=0x6AF9});
    k.finish(b);
  }
};
// ---- strangler ----
/// how many pale roots net the trunk: the parasites' count
const netRoots=kit.fold;
/// the strangler's trunk girth at its foot
const trunkGirth:f32=0.05;
/// the trunk's girth `u` up it
fn trunkR(u:f32)f32{return trunkGirth*m.lerp(1,0.6,u);}
/// the strangler look
pub const strangler=struct{
  /// builds it
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    var k=growth.Skeleton.begin(b);
    // the symbiote's living trunk, leaning a little, wandering
    const trunk=k.trunk(&.{v3(0,-0.08,0),v3(0.012,0.25,-0.01),v3(-0.016,0.5,0.012),v3(0.01,0.75,0),v3(0,0.95,0)},.{.pace=1.4});
    try k.braid(b,trunk,.{.girth=trunkGirth,.tip=0.6,.strands=6,.twist=1.4,.wobble=pal.strandWobble*1.5,.seed=0x57A1,.core=pal.core,.strand=kit.green,.t0=0,.t1=0.5});
    try greenRoots(b,&k,trunk,v3(0,0,0),4,0.26,0.05,0x57A2);
    try k.leaves(b,trunk,.{.n=11,.len=0.1,.width=0.038,.from=0.22,.to=0.92,.t0=0.3,.t1=0.55,.col=kit.leafDark,.tip=kit.leafLite,.seed=0x57A3});
    // two green shoots escaping the net
    for([_]f32{0.55,0.76},0..)|u,i|{
      const at=k.point(trunk,u);
      const a=m.f(i)*2.6+0.9;
      const out=v3(@cos(a),0,@sin(a));
      const sh=k.branch(trunk,u,&.{at,at+out*m.splat3(0.09)+v3(0,0.03,0),at+out*m.splat3(0.19)+v3(0,0.11,0),at+out*m.splat3(0.24)+v3(0,0.19,0)},.{.after=.passing});
      try k.tube(b,sh,.{.r0=0.012,.tip=0.4,.col=kit.green,.sides=5,.t0=0.4,.t1=0.55});
      try k.leaves(b,sh,.{.n=4,.len=0.07,.width=0.027,.from=0.3,.to=1,.t0=0.45,.t1=0.6,.col=kit.leafDark,.tip=kit.leafLite,.seed=0x57A4+%i*31});
    }
    // the net: five pale roots let down from the crown, spiralling round
    // the trunk as they fall, standing out onto the ground as prop roots
    var net:[netRoots]growth.Id=undefined;
    for(&net,0..)|*id,i|{
      const a0=m.ratio(i,netRoots)*m.tau;
      var c:[11]V3=undefined;
      c[0]=k.point(trunk,0.93);
      for(c[1..],0..)|*q,j|{
        // how far down (0 at the crown, 1 in the soil), the height, its
        // bearing round the trunk and how far out from it
        const s=m.ratio(j,9);
        const y=m.lerp(0.86,-0.03,s);
        const ax=k.point(trunk,m.clamp01(y/0.95));
        const a=a0+1.5*s+0.18*@sin(s*7+m.f(i)*1.7);
        const prop=m.smooth(m.clamp01((s-0.72)/0.28));
        const r=trunkR(y/0.95)+0.013+prop*0.2;
        q.*=v3(ax[0]+@cos(a)*r,y,ax[2]+@sin(a)*r);
      }
      id.*=k.branch(trunk,0.93,&c,.{.after=.passing,.pace=1.1,.delay=0.02*m.f(i)});
      try k.tube(b,id.*,.{.r0=0.009,.tip=1.6,.col=kit.pale,.part=.stem,.sides=6,.t0=0.55,.t1=0.85});
    }
    // where neighbouring roots meet round the trunk they grow together: a
    // pale bridge across, knotted violet at both ends
    var rng=Rng.init(0x57A5);
    for(0..netRoots)|i|for([_]f32{0.28,0.52})|s0|{
      const ra=net[i];
      const rb=net[(i+1)%netRoots];
      const sa=s0+rng.range(-0.05,0.05);
      const sb=sa+0.08;
      const p0=k.point(ra,sa);
      const p1=k.point(rb,sb);
      // the trunk's middle at both ends, their bearings and how far out
      const c0=k.point(trunk,k.nearest(trunk,p0));
      const c1=k.point(trunk,k.nearest(trunk,p1));
      const a0=m.atan2(p0[2]-c0[2],p0[0]-c0[0]);
      const da=m.angleDiff(a0,m.atan2(p1[2]-c1[2],p1[0]-c1[0]));
      const r0=m.len(v3(p0[0]-c0[0],0,p0[2]-c0[2]));
      const r1=m.len(v3(p1[0]-c1[0],0,p1[2]-c1[2]));
      // the bridge's course, round the trunk's skin, not through it
      var c:[5]V3=undefined;
      for(&c,0..)|*q,j|{
        const w=m.ratio(j,4);
        const ctr=m.lerpV(c0,c1,w);
        const a=a0+da*w;
        const r=m.lerp(r0,r1,w)*(1+0.12*@sin(m.pi*w));
        q.*=v3(ctr[0]+@cos(a)*r,m.lerp(p0[1],p1[1],w),ctr[2]+@sin(a)*r);
      }
      var p:[12]V3=undefined;
      m.splineResample(&c,&p);
      const mk=b.mark();
      try kit.taper(b,&p,0.0065,0.85,0.8,0.82,kit.pale,.stem,5);
      for([_]V3{p0,p1})|e|try mg.ellipsoid(b,.{.center=e,.radii=m.splat3(0.015*rng.range(0.85,1.2)),.col=kit.knot,.part=.stem,.rings=4,.segs=6,.t=0.82});
      try k.on(b,mk,ra,sa,.{.from=p0,.delay=0.05});
    };
    // the net gathered at the crown into a pale collar
    {
      const at=k.point(trunk,0.92);
      const mk=b.mark();
      try pk.nodule(b,at,v3(trunkR(0.92)*1.35,0.022,trunkR(0.92)*1.35),0.55,kit.pale,kit.lilac,kit.pearl);
      try k.on(b,mk,trunk,0.92,.{.from=at});
    }
    try crown(b,&k,trunk,.{.sacR=v3(0.095,0.11,0.095),.reach=0.42,.r=0.015,.bough=.lilac,.seed=0x57A6});
    k.finish(b);
  }
};
// ---- tissue ----
/// a radius along a body, `u` up it (0..1)
const Profile=fn(f32)f32;
/// a profile's radius `u` up it, eased between its knots `us` (how far up)
/// and `rs` (the radius there)
fn profileAt(us:[]const f32,rs:[]const f32,u:f32)f32{
  for(1..us.len)|i|if(u<=us[i])return m.lerp(rs[i-1],rs[i],m.smooth(m.unlerp(us[i-1],us[i],u)));
  return rs[rs.len-1];
}
/// the tissue body's radius `u` up it: a narrow foot, a swollen belly, a
/// waist, a collar under the crown, closing round the sac
fn bodyR(u:f32)f32{return profileAt(&.{0,0.14,0.36,0.56,0.72,0.86,1},&.{0.05,0.072,0.102,0.074,0.046,0.062,0.036},u);}
/// where the tissue's tentacles hang from
const collarU:f32=0.86;
/// how many points a tentacle (or a pale stem) is built of, fine, so its
/// swellings are smooth
const tentRes=64;
/// where down a tentacle its beads of sap swell (shares of it)
const beads=[_]f32{0.3,0.48,0.66,0.84};
/// half a bead's length (a share of the tentacle)
const beadHalf:f32=0.06;
/// one soft see-through body up spline `axis` (radius `r(u)`, tu.x
/// `t0`..`t1`): two skins, the outer the parasites' pale flushed violet,
/// warmed amber at its foot; inside three green strands winding up, two
/// amber lanes the other way and a pale vein up the middle; outside five
/// pale ribs, exact
fn tissueBody(b:*mg.Builder,k:*growth.Skeleton,axis:growth.Id,comptime r:Profile,t0:f32,t1:f32)Allocator.Error!void{
  const sp=&k.get(axis).pts;
  const mk=b.mark();
  var ts:[res]f32=undefined;
  var rs:[res]f32=undefined;
  var cs:[res]Rgba8=undefined;
  for(&ts,&rs,&cs,0..)|*t,*q,*cl,i|{
    const u=m.ratio(i,res-1);
    t.*=m.lerp(t0,t1,u);
    q.*=r(u);
    cl.*=color.mix(tissueLow,tissue,m.smooth(m.clamp01(u*1.6)));
  }
  try b.tubeC(sp,&ts,&rs,&cs,null,.bloom,14);
  // a second skin just inside the first, so the flesh reads as a body
  // and not a pane: its rim doubled, its middle clouded
  var inner:[res]f32=undefined;
  for(&inner,rs)|*q,o|q.*=o*0.88;
  try b.tubeC(sp,&ts,&inner,&cs,null,.bloom,12);
  // a twist-free frame up the middle
  var nv:[res]V3=undefined;
  var bv:[res]V3=undefined;
  mg.transport(sp,&nv,&bv);
  // one run of strands: how many, how far out (shares of the body's
  // radius), how many turns, how thick, its colour, its turn at the foot
  const Run=struct{n:usize,out:f32,turns:f32,r:f32,col:Rgba8,from:f32};
  const runs=[_]Run{
    .{.n=3,.out=0.5,.turns=1.6,.r=0.009,.col=kit.green,.from=0},
    .{.n=2,.out=0.3,.turns=-1.1,.r=0.007,.col=kit.amber,.from=0.9},
    .{.n=1,.out=0,.turns=0,.r=0.011,.col=color.mix(kit.pale,kit.lilac,0.5),.from=0},
    .{.n=kit.fold,.out=1.005,.turns=0,.r=0.0042,.col=kit.pale,.from=0.3},
  };
  for(runs)|run|for(0..run.n)|j|{
    var p:[res]V3=undefined;
    var rr:[res]f32=undefined;
    for(&p,&rr,0..)|*q,*w,i|{
      const u=m.ratio(i,res-1);
      const a=m.ratio(j,run.n)*m.tau+run.from+run.turns*m.tau*u+(if(run.n==3)0.15*@sin(u*8+m.f(j))else 0);
      q.*=sp[i]+(nv[i]*m.splat3(@cos(a))+bv[i]*m.splat3(@sin(a)))*m.splat3(r(u)*run.out);
      w.*=run.r*(if(run.out>1)m.lerp(0.6,1.2,m.smooth(@sin(m.pi*u)))else 1);
    }
    try b.tubeR(&p,&ts,&rr,run.col,.stem,if(run.out>1)4 else 5);
  };
  try k.along(b,mk,axis);
}
/// five pale tentacles hanging from the collar `cu` up spline `axis` (the
/// body `r0` round there), exact, swelling into beads of amber sap down
/// them, fine pearl plumes at full detail; tu.x from `t0`
fn tentacles(b:*mg.Builder,k:*growth.Skeleton,axis:growth.Id,cu:f32,r0:f32,t0:f32)Allocator.Error!void{
  const ca=k.point(axis,cu);
  for(0..kit.fold)|i|{
    const a=(m.f(i)+0.5)/m.f(kit.fold)*m.tau+0.3;
    const out=v3(@cos(a),0,@sin(a));
    const c=[_]V3{ca,ca+out*m.splat3(r0*1.4)+v3(0,-0.01,0),ca+out*m.splat3(r0*2.0)+v3(0,-0.1,0),ca+out*m.splat3(r0*2.1)+v3(0,-0.22,0),ca+out*m.splat3(r0*1.7)+v3(0,-0.33,0),ca+out*m.splat3(r0*1.3)+v3(0,-0.37,0)};
    const t=k.branch(axis,cu,&c,.{.after=.passing,.pace=1.3});
    // the tentacle, swelling into beads of amber sap down it, not beads
    // stuck on: its own skin thickening and warming into each and out
    // again, the beads smaller toward its tip
    {
      var tp:[tentRes]V3=undefined;
      var tts:[tentRes]f32=undefined;
      var trs:[tentRes]f32=undefined;
      var tcs:[tentRes]Rgba8=undefined;
      k.path(t,0,1,&tp);
      for(&tts,&trs,&tcs,0..)|*tt,*r,*cl,j|{
        const u=m.ratio(j,tentRes-1);
        // how far into a bead this point is (0 between, 1 at its middle)
        var bead:f32=0;
        for(beads)|bu|bead=@max(bead,m.smooth(m.clamp01(1-@abs(u-bu)/beadHalf)));
        tt.*=m.lerp(t0,t0+0.2,u);
        r.*=0.008*m.lerp(1,0.3,u)*mg.collar(u)*(1+bead*m.lerp(1.5,0.9,u));
        cl.*=color.mix(kit.pale,kit.amber,bead*0.9);
      }
      const mk=b.mark();
      try b.tubeC(&tp,&tts,&trs,&tcs,null,.tendril,7);
      try k.along(b,mk,t);
    }
    for(beads)|u|{
      const at=k.point(t,u);
      const mk=b.mark();
      // decision: plumes only at full detail; past it they are under a pixel
      if(b.lod==0)for([_]f32{-1,1})|s|{
        const side=m.norm(m.cross(k.tangent(t,u),out));
        const q=[_]V3{at,at+side*m.splat3(s*0.022)+out*m.splat3(0.01)-v3(0,0.008,0),at+side*m.splat3(s*0.038)+out*m.splat3(0.02)-v3(0,0.024,0)};
        var p:[6]V3=undefined;
        m.splineResample(&q,&p);
        try kit.taper(b,&p,0.0022,0.3,t0+0.15,t0+0.18,kit.pearl,.tendril,4);
      };
      try k.on(b,mk,t,u,.{.from=at});
    }
  }
}
/// the tissue look
pub const tissueLook=struct{
  /// builds it
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    var k=growth.Skeleton.begin(b);
    // the body's middle, a slow S up out of the soil
    const axis=k.trunk(&.{v3(0,-0.05,0),v3(0.012,0.25,0),v3(-0.02,0.5,0.012),v3(0,0.72,-0.01),v3(0.01,0.9,0)},.{.pace=1.6});
    try tissueBody(b,&k,axis,bodyR,0,0.6);
    try kit.footOn(b,&k,axis,.{.r=0.07,.reach=0.3,.rootR=0.014,.seed=0x7155});
    try sprouts(b,&k,axis,9,0.16,0.74,0.105,bodyR,0x7156);
    try tentacles(b,&k,axis,collarU,bodyR(collarU),0.6);
    try crown(b,&k,axis,.{.sacR=v3(0.085,0.1,0.085),.reach=0.42,.r=0.017,.bough=.tissue,.seed=0x7157});
    k.finish(b);
  }
};
// ---- grafted and tissue blended ----
/// how high the blend's stems climb before they fuse into its body
const blendH:f32=0.4;
/// the blend's top
const blendTop:f32=1.05;
/// the blend's body radius `u` up it: rising thin out of the fusing
/// callus, swelling into a belly, a waist, a collar, closing round the sac
fn blendR(u:f32)f32{return profileAt(&.{0,0.12,0.36,0.58,0.72,0.86,1},&.{0.036,0.07,0.104,0.074,0.05,0.064,0.036},u);}
/// the blend: two stems grafted into one, as the grafted look's, and where
/// they fuse for good the one body they become, as the tissue look's: the
/// green stem going on as the green strands winding inside it, the pale as
/// the pale vein up its middle, amber lanes rising between; leaves out of
/// both, tentacles beaded with sap from its collar, the crown on top
pub const blend=struct{
  /// builds it
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    var k=growth.Skeleton.begin(b);
    const st=try graftedBase(b,&k,.{.h=blendH,.t1=0.3,.leaves=6,.seed=0xB1E0});
    // the body, out of the fusing callus up to the crown, a slow S
    const f0=v3(0,blendH-0.01,0);
    const h=blendTop-blendH;
    const axis=k.branch(st.mid,1,&.{f0,f0+v3(0.012,h*0.25,0),f0+v3(-0.016,h*0.55,0.01),f0+v3(0,h*0.8,-0.01),v3(0.01,blendTop,0)},.{.pace=1.6});
    try tissueBody(b,&k,axis,blendR,0.3,0.65);
    try sprouts(b,&k,axis,7,0.14,0.74,0.105,blendR,0xB1E1);
    try tentacles(b,&k,axis,collarU,blendR(collarU),0.62);
    try crown(b,&k,axis,.{.sacR=v3(0.085,0.1,0.085),.reach=0.42,.r=0.017,.bough=.tissue,.seed=0xB1E2});
    k.finish(b);
  }
};
