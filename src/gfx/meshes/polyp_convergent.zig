//! mesh: POLYP, CONVERGENT. the polyp's hydra moved onto the convergence
//! kit, two looks laid beside it to compare
//! (`--samples=polyp,polypWoven,polypMarbled`). WOVEN: its stem the kit's
//! weave of green and pale strands, parting into a cage round a marbled
//! sac of both saps at its gut and gathering again under a violet mouth
//! disc; five lilac fronds rolling into croziers crown it, five pale
//! plumed tentacles hang from under them with amber knots, and five
//! offshoots spiral up its foot, each ending in a flower of both. MARBLED:
//! its smooth pale flesh swirled with violet and amber, a see-through sac
//! of both saps swelling at its gut, its crown five feathery tentacles
//! between five fronds, five plumed tentacles hanging, and five offshoots
//! of its own, each crowned with feathers. Both stand on the kit's foot
//! (a pale bulb, five pale roots and five green braided ones) and grow
//! along growth splines.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, splines, easing
const m=engine.core.math;
/// the mesh builder and its primitives
const mg=lib.meshgen;
/// colour conversions and blends
const color=engine.core.color;
/// the shared swatches, and the per-mesh random stream
const pal=lib.palette;
/// the garden's growth timing: the skeleton both grow along
const growth=lib.growth;
/// the parasites' kit: the weave's stalk shape and sections
const pk=lib.parasiteKit;
/// the convergence kit: weave, sac, fronds, flowers, foot, palette
const kit=lib.convergenceKit;
/// the hydra: its long plumed tentacles
const hydra=lib.polypHydra;
/// the colony: its mouth, feathery tentacles
const colony=lib.polypMesh;
/// the seeded random stream their crowns are varied by
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// the stem's hidden spline, rising in a soft S (both looks)
const stemCtrl=[_]V3{v3(0,-0.03,0),v3(0.02,0.25,0.01),v3(-0.025,0.5,0.03),v3(0.02,0.76,0)};
/// the stems grow this much slower than a unit a second's share
const stemPace:f32=1.6;
/// how far up the stem the gut swells
const gutU:f32=0.64;
/// the woven stem's weave: a cage opening round the gut, gathered again
/// under the head
const wovenStalk:pk.Stalk=.{.girth=0.03,.part=2.6,.from=0.48,.to=0.84};
/// a mouth disc's radius
const discR:f32=0.075;
/// how long the crowns' long plumed tentacles hang
const hangLen:f32=0.95;
/// points along a drawn marbled body
const bodyRings=40;
/// the violet-rose of a convergent mouth disc
const discCol=color.rgb(0.66,0.46,0.86);
/// builds the woven look
pub const woven=struct{
  /// builds the polyp woven of both lineages
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // its own random stream, the same every build
    var rng=pal.rngFor("polypWoven");
    // the skeleton every part is timed along
    var k=growth.Skeleton.begin(b);
    // its stem's hidden spline
    const stem=k.trunk(&stemCtrl,.{.pace=stemPace});
    try kit.footOn(b,&k,stem,.{.r=0.07,.reach=0.32,.rootR=0.013,.seed=0x9A01});
    // the stem's path and its weave's sections, for what rides inside
    var sp:[growth.res]V3=undefined;
    var sec:[growth.res]pk.Section=undefined;
    try kit.weaveOn(b,&k,stem,wovenStalk,.{.seed=0x9A02},0,0.7,&sp,&sec);
    {
      // the gut: a sac of both saps held in the cage
      const at=k.point(stem,gutU);
      // where its vertices begin
      const s=b.mark();
      try kit.sac(b,.{.center=at,.radii=v3(0.05,0.075,0.05),.t=0.6,.arms=3,.phase=0.4});
      try k.on(b,s,stem,gutU,.{.from=at});
    }
    // the head: where the stem ends and the way it faces
    const top=k.point(stem,1);
    const up=k.tangent(stem,0.98);
    try trumpet(b,&k,stem,top,up,wovenStalk.girth*1.1,kit.pale.toRgb(),discCol);
    try crown(b,&k,stem,top,up,.fronds,&rng);
    // five offshoots spiralling up its foot, exactly alike, each ending in a flower of both
    for(0..kit.fold)|i|{
      // where it buds, and the flat way out it reaches
      const u=0.14+0.07*m.f(i);
      const a=m.ratio(i,kit.fold)*m.tau*2;
      const side=k.point(stem,u);
      const out=v3(@cos(a),0,@sin(a));
      // out of the stem, then turning upward
      const id=k.branch(stem,u,&.{side,side+out*m.splat3(0.06),side+out*m.splat3(0.11)+v3(0,0.06,0),side+out*m.splat3(0.13)+v3(0,0.16,0)},.{.pace=stemPace,.delay=0.1+0.03*m.f(i)});
      try k.tube(b,id,.{.r0=0.012,.tip=0.6,.col=kit.lilac,.part=.tendril,.sides=6,.t0=0.5,.t1=0.9});
      // where its flower's vertices begin, so it opens last
      const s=b.mark();
      // where the flower sits
      const tip=k.point(id,1);
      try kit.bloom(b,.{.heart=tip,.len=0.05,.spin=a,.petals=6,.seed=0x9A20});
      try k.on(b,s,id,1,.{.from=tip});
    }
    k.finish(b);
  }
};
/// builds the marbled look
pub const marbled=struct{
  /// builds the polyp of marbled flesh
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // its own random stream, the same every build
    var rng=pal.rngFor("polypMarbled");
    // the skeleton every part is timed along
    var k=growth.Skeleton.begin(b);
    // its stem's hidden spline
    const stem=k.trunk(&stemCtrl,.{.pace=stemPace});
    try kit.footOn(b,&k,stem,.{.r=0.07,.reach=0.32,.rootR=0.013,.seed=0x9A31});
    try flesh(b,&k,stem,0.03,discR);
    {
      // the gut: a see-through sac of both saps swelling out of the flesh
      const at=k.point(stem,gutU);
      // where its vertices begin
      const s=b.mark();
      try kit.sac(b,.{.center=at,.radii=v3(0.048,0.07,0.048),.t=0.6,.arms=3,.phase=1.1});
      try k.on(b,s,stem,gutU,.{.from=at});
    }
    // the head: where the stem ends and the way it faces
    const top=k.point(stem,1);
    const up=k.tangent(stem,0.98);
    try crown(b,&k,stem,top,up,.mixed,&rng);
    // five offshoots spiralling up its stem, each its own size, crowned with feathers
    for(0..kit.fold)|i|{
      // where it buds, the flat way out it reaches, and its size
      const u=0.24+0.1*m.f(i);
      const a=m.ratio(i,kit.fold)*m.tau*2+rng.range(-0.3,0.3);
      const side=k.point(stem,u);
      const out=v3(@cos(a),0,@sin(a));
      const size=rng.range(0.75,1.15)*(1-0.12*m.f(i));
      // out of the stem, then turning upward
      const id=k.branch(stem,u,&.{side,side+out*m.splat3(0.06*size),side+out*m.splat3(0.12*size)+v3(0,0.06*size,0),side+out*m.splat3(0.14*size)+v3(0,0.17*size,0)},.{.pace=stemPace,.delay=0.1+0.04*m.f(i)});
      // its disc's radius
      const dr=0.032*size;
      try flesh(b,&k,id,0.013*size,dr);
      // its head: where it ends and the way it faces, two ways across it
      const t=k.point(id,1);
      const tu=k.tangent(id,0.98);
      const e1=m.norm(m.cross(tu,if(@abs(tu[2])<m.nearParallel)v3(0,0,1)else v3(1,0,0)));
      const e2=m.cross(tu,e1);
      try colony.mouthOn(b,&k,id,t,tu,dr,&rng);
      for(0..kit.fold)|j|try colony.tentacle(b,&k,id,.{.top=t,.up=tu,.e1=e1,.e2=e2,.dr=dr,.r=dr/colony.flare},(m.f(j)+rng.range(-0.15,0.15))/m.f(kit.fold)*m.tau,&rng);
    }
    k.finish(b);
  }
};
/// how a convergent polyp's crown is made
const Crown=enum{
  /// five lilac fronds with green leaflets, rolling into croziers
  fronds,
  /// five feathery tentacles between five fronds
  mixed,
};
/// the crown on a mouth disc at `top` of spline `stem`, facing `up`: the
/// mouth, the fronds (and feathers, mixed), and five pale plumed
/// tentacles hanging from under them, their knots amber
fn crown(b:*mg.Builder,k:*growth.Skeleton,stem:growth.Id,top:V3,up:V3,c:Crown,rng:*Rng)Allocator.Error!void{
  // two ways across the disc
  const e1=m.norm(m.cross(up,if(@abs(up[2])<m.nearParallel)v3(0,0,1)else v3(1,0,0)));
  const e2=m.cross(up,e1);
  try colony.mouthOn(b,k,stem,top,up,discR,rng);
  for(0..kit.fold)|i|{
    // this frond's bearing, exact, and the flat way out along it
    const a=m.ratio(i,kit.fold)*m.tau;
    const out=e1*m.splat3(@cos(a))+e2*m.splat3(@sin(a));
    _=try kit.frondOn(b,k,stem,1,.{
      .from=top+out*m.splat3(discR*0.8),.out=out,.len=0.3,.r=0.008,
      .rise=1.0,.curl=3.0,.pairs=6,.leafLen=0.05,.leafW=0.014,
      .t0=0.8,.t1=1,.seed=0x9A40,.leafSeed=0x9A41+%i*97,
    },.{});
    if(c==.mixed)try colony.tentacle(b,k,stem,.{.top=top,.up=up,.e1=e1,.e2=e2,.dr=discR,.r=discR/colony.flare},a+0.5/m.f(kit.fold)*m.tau,rng);
    // the long tentacle between this frond and the next, hanging from under the disc
    const ha=a+(if(c==.mixed)@as(f32,0.25)else 0.5)/m.f(kit.fold)*m.tau;
    const ho=e1*m.splat3(@cos(ha))+e2*m.splat3(@sin(ha));
    try hydra.hanging(b,k,stem,.{.root=top+ho*m.splat3(discR*0.8)-up*m.splat3(discR*0.18),.out=ho,.up=up,.len=hangLen*rng.range(0.85,1.15),.r0=0.009,.tip=.plume,.col=kit.pale.toRgb(),.knotCol=kit.amber.toRgb()},rng);
  }
}
/// the woven stem's head: a short trumpet out of the weave's top at `top`
/// (facing `up`), from `r0` to the disc's radius, `col0` to `col1`, its
/// flat end the mouth disc
fn trumpet(b:*mg.Builder,k:*growth.Skeleton,stem:growth.Id,top:V3,up:V3,r0:f32,col0:color.Rgb,col1:color.Rgb)Allocator.Error!void{
  // its points, tu.x, radii and colours
  var p:[8]V3=undefined;
  var ts:[8]f32=undefined;
  var rs:[8]f32=undefined;
  var cs:[8]color.Rgba8=undefined;
  for(&p,&ts,&rs,&cs,0..)|*q,*t,*r,*c,i|{
    // how far up the trumpet, 0 its foot .. 1 the rim
    const f=m.ratio(i,7);
    q.*=top+up*m.splat3((f-1)*0.07);
    t.*=0.7+0.3*f;
    r.*=m.lerp(r0,discR,f*f*f);
    c.*=col0.lerp(col1,m.smooth(f)).toRgba8(255);
  }
  // where its vertices begin
  const s=b.mark();
  try b.tubeC(&p,&ts,&rs,&cs,null,.tendril,12);
  try k.along(b,s,stem);
}
/// a smooth marbled body the length of spline `id`, `r` thick, swelling at
/// its gut and opening at its head into a disc `dr` wide: pale flesh
/// swirled with violet and amber bands (a smooth field of its place, so
/// shared vertices agree)
fn flesh(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,r:f32,dr:f32)Allocator.Error!void{
  // the drawn body, and its tu.x, radius and colour per ring
  var sp:[bodyRings]V3=undefined;
  k.path(id,0,1,&sp);
  var ts:[bodyRings]f32=undefined;
  var rs:[bodyRings]f32=undefined;
  var cs:[bodyRings]color.Rgba8=undefined;
  for(&ts,&rs,&cs,0..)|*t,*rr,*c,j|{
    // how far up the body, 0 foot .. 1 head, and how far into the head's flare
    const f=m.ratio(j,bodyRings-1);
    const ff=m.clamp01((f-0.84)/0.16);
    t.*=f;
    rr.*=m.lerp(r*(0.8+0.3*@exp(-(f-gutU)*(f-gutU)*20)),dr,ff*ff);
    c.*=kit.pale;
  }
  // where its vertices begin
  const s=b.mark();
  try b.tubeC(&sp,&ts,&rs,&cs,null,.tendril,10);
  // the bands: two arms of violet and amber winding up it, the disc violet-rose
  for(b.v.items[s..])|*vx|{
    // its height along the body, and its bearing round it
    const h=vx.tu[0];
    const ph=m.atan2(vx.nrm[2],vx.nrm[0]);
    const band=@sin(2*ph+h*18);
    const sap=if(band>0)kit.violet else kit.amber;
    const base=color.mix(kit.pale,sap,0.45*m.smooth(m.clamp01(@abs(band)*1.6-0.5)));
    vx.col=color.mix(base,discCol.toRgba8(255),m.smooth(m.clamp01((h-0.86)/0.14)));
  }
  try k.along(b,s,id);
}
