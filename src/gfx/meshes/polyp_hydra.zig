//! mesh: POLYP. the heart of a halo: one tall, slender, stretchy hydra
//! gripping the soil with a foot disc, swelling a little at its gut,
//! opening at its head into a mouth disc (a dark slit on a raised mound,
//! a bead of resin in it), ringed by feathery tentacles, with long thin
//! tentacles beaded with stinging knots hanging from under them, plumed
//! at their tips. Offshoots bud up its stem, each its own size and
//! bearing, crowned alike. The diamond forms high over it as the halo
//! completes. Also looks to compare (`--samples=`): the hydra crowned with
//! feathers alone (`polypHydraFeathered`) or plumes alone
//! (`polypHydraPlumed`), with a single young bud, and a colony of
//! cone-headed hydras on a fleshy mound (`polypHydras`). They grow along
//! growth splines.
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
/// the shared swatches, and the per-mesh random stream
const pal=lib.palette;
/// colour conversions and blends, for the hydra's flesh
const color=engine.core.color;
/// the structure kit: the root mat under its foot
const kit=lib.structureKit;
/// the garden's growth timing: the skeleton the hydra grows along
const growth=lib.growth;
/// the seeded random stream its tentacles are varied by
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// the pale pearl-cream of its body
const pearl=color.rgb(0.8,0.74,0.86);
/// the dusky violet of its foot
const foot=color.rgb(0.5,0.42,0.6);
/// the deeper lilac of its gut, where it swells
const gut=color.rgb(0.7,0.6,0.78);
/// the pale lilac of its tentacles
const thread=color.rgb(0.72,0.64,0.84);
/// the white of a stinging knot on a tentacle
const knot=color.rgb(0.98,0.96,1);
/// the dark violet of its mouth
const mouth=color.rgb(0.22,0.15,0.28);
/// points along a drawn body
const bodyRings=40;
/// points along a drawn tentacle (fine enough for its knots)
const tentacleRings=48;
/// stinging knots along a tentacle
const knots:f32=9;
/// the bodies grow this much slower than a unit a second's share
const bodyPace:f32=1.6;
/// one hydra body grown along a spline: how thick, how many tentacles and
/// how long, and the colour at its foot
pub const Body=struct{
  /// its body's radius
  r:f32,
  /// how many tentacles crown it
  arms:u32,
  /// how long each tentacle runs
  reach:f32,
  /// the colour at its foot (the young one's is its parent's flesh)
  base:color.Rgb,
  /// how its head is made
  head:Head=.cone,
  /// how many feathery tentacles crown an open head
  feathers:u32=8,
  /// whether its mouth holds a bead of resin
  bead:bool=false,
};
/// how wide an open head's disc flares, as a share of its body's radius
const openFlare:f32=2.6;
/// builds the hydra. It grows on a hidden stalk (gfx/growth.zig): the roots
/// and foot disc spread, the body rises, its head cone closes, the long
/// tentacles reach out of it and down, and last the young one buds from its side.
/// how a hydra's head is made
pub const Head=enum{
  /// a pointed cone, the mouth at its tip, the long knotted tentacles
  /// leaving from under it
  cone,
  /// opening into the polyp's oral disc and slit mouth, crowned with its
  /// eight feathery tentacles
  feathered,
  /// opening into the polyp's oral disc and slit mouth, its long knotted
  /// tentacles ending in feathery plumes
  plumed,
  /// opening into the polyp's oral disc and slit mouth, crowned with both:
  /// the feathery tentacles round the rim, the long plumed ones hanging
  /// from under them
  both,
};
/// builds the polyp: the single hydra opening into the mouth disc, its
/// feathery crown round the rim and its long plumed tentacles hanging from
/// under it, offshoots of its own budding up its stem, each crowned alike
pub fn build(b:*mg.Builder)Allocator.Error!void{try single(b,.both);}
/// one offshoot budding from the stem: where along it, which way, how far
/// out and up it reaches, and how big its crown is
const Offshoot=struct{
  /// how far up the stem it buds (0 foot .. 1 head)
  u:f32,
  /// its bearing round the stem (radians)
  a:f32,
  /// how far out it reaches
  out:f32,
  /// how far up it rises
  rise:f32,
  /// its body's radius
  r:f32,
  /// how long its plumed tentacles hang
  reach:f32,
  /// how many feathery tentacles crown it
  feathers:u32,
  /// how many plumed tentacles hang from it
  arms:u32,
};
/// the offshoots up the stem, each its own size and bearing, low and large
/// to high and small (`single` with an open head)
const offshoots=[_]Offshoot{
  .{.u=0.26,.a=0.4,.out=0.13,.rise=0.16,.r=0.015,.reach=0.24,.feathers=6,.arms=3},
  .{.u=0.42,.a=2.6,.out=0.17,.rise=0.22,.r=0.018,.reach=0.3,.feathers=6,.arms=3},
  .{.u=0.57,.a=4.3,.out=0.13,.rise=0.15,.r=0.014,.reach=0.22,.feathers=6,.arms=3},
  .{.u=0.71,.a=5.6,.out=0.09,.rise=0.11,.r=0.011,.reach=0.16,.feathers=5,.arms=3},
};
/// a mixed look (`--samples=polyp,polypHydraFeathered`): the single hydra
/// opening into the polyp's mouth disc, crowned with its feathery tentacles
pub const feathered=struct{
  /// builds the hydra, feathered
  pub fn build(b:*mg.Builder)Allocator.Error!void{try single(b,.feathered);}
};
/// a mixed look (`--samples=polyp,polypHydraPlumed`): the single hydra
/// opening into the polyp's mouth disc, its long tentacles ending in
/// feathery plumes
pub const plumed=struct{
  /// builds the hydra, plumed
  pub fn build(b:*mg.Builder)Allocator.Error!void{try single(b,.plumed);}
};
/// the single hydra, headed as `head` says
fn single(b:*mg.Builder,head:Head)Allocator.Error!void{
  // its own random stream, the same every build
  var rng=pal.rngFor("polypHydra");
  // the skeleton every part is timed along
  var k=growth.Skeleton.begin(b);
  // its body, rising in a soft S
  const trunk=k.trunk(&.{v3(0,0,0),v3(0.02,0.25,0.01),v3(-0.025,0.5,0.03),v3(0.02,0.76,0)},.{.pace=bodyPace});
  try kit.rootMat(b,4,0.32,0.035,0x9171,.{.k=&k,.id=trunk});
  {
    // the foot disc gripping the soil
    const s=b.mark();
    try mg.ellipsoid(b,.{.center=v3(0,0.005,0),.radii=v3(0.065,0.018,0.065),.col=foot.toRgba8(255),.part=.tendril,.rings=6,.segs=14});
    try k.along(b,s,trunk);
  }
  try body(b,&k,trunk,.{.r=0.03,.arms=6,.reach=1,.base=foot,.head=head,.bead=true},&rng);
  if(head!=.cone){
    for(offshoots,0..)|o,i|{
      // where it buds, the flat way out it reaches, and a little drift aside
      const side=k.point(trunk,o.u);
      const out=v3(@cos(o.a),0,@sin(o.a));
      const aside=m.cross(v3(0,1,0),out)*m.splat3(rng.range(-0.03,0.03));
      // out of the stem, then turning upward
      const id=k.branch(trunk,o.u,&.{side,side+out*m.splat3(o.out*0.45)+v3(0,o.rise*0.05,0),side+out*m.splat3(o.out*0.85)+v3(0,o.rise*0.35,0)+aside,side+out*m.splat3(o.out)+v3(0,o.rise,0)+aside},.{.pace=bodyPace,.delay=0.1+0.05*m.f(i)});
      try body(b,&k,id,.{.r=o.r,.arms=o.arms,.reach=o.reach,.base=gut,.head=head,.feathers=o.feathers},&rng);
    }
    k.finish(b);
    return;
  }
  // the young one, budding from its side and turning upward
  const side=k.point(trunk,0.42);
  const bud=k.branch(trunk,0.42,&.{side,side+v3(0.07,0.02,0.04),side+v3(0.13,0.08,0.07),side+v3(0.15,0.17,0.08)},.{.pace=bodyPace,.delay=0.2});
  try body(b,&k,bud,.{.r=0.016,.arms=4,.reach=0.2,.base=gut,.head=head},&rng);
  k.finish(b);
}
/// a mixed look, to compare beside it (`--samples=polyp,polypHydras`): a
/// colony of slender hydras on the polyp's fleshy mound, the tallest
/// budding a young one, the closed buds low on the mound
pub const colony=struct{
  /// builds the hydra colony
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // its own random stream, the same every build
    var rng=pal.rngFor("polypHydras");
    // the skeleton every part is timed along
    var k=growth.Skeleton.begin(b);
    // the mound's hidden heart, which every hydra grows off
    const heart=try lib.polypMesh.base(b,&k);
    // the tallest's body, kept for the young one it buds
    var first:?growth.Id=null;
    for(hydras,0..)|h,i|{
      // its body's control points (the first left for the skeleton to root):
      // up out of the mound in a soft S, leaning out a little
      const d=h.top-h.foot;
      const sway=m.norm(m.cross(d,v3(0,1,0))+v3(0.001,0,0))*m.splat3(0.03);
      const c=[_]V3{h.foot,h.foot,h.foot+v3(d[0]*0.2,d[1]*0.33,d[2]*0.2)+sway,h.foot+v3(d[0]*0.6,d[1]*0.66,d[2]*0.6)-sway,h.top};
      // its branch on the skeleton, the smaller ones a little later
      const id=k.branch(heart,1,&c,.{.pace=bodyPace,.delay=0.08*m.f(i)});
      if(first==null)first=id;
      try body(b,&k,id,.{.r=h.r,.arms=5,.reach=h.reach,.base=gut},&rng);
    }
    // the young one, budding from the tallest's side and turning upward
    const t=first.?;
    const side=k.point(t,0.5);
    const bud=k.branch(t,0.5,&.{side,side+v3(-0.06,0.02,0.04),side+v3(-0.11,0.07,0.07),side+v3(-0.13,0.15,0.08)},.{.pace=bodyPace,.delay=0.2});
    try body(b,&k,bud,.{.r=0.013,.arms=4,.reach=0.16,.base=gut},&rng);
    try lib.polypMesh.budsOn(b,&k,heart);
    k.finish(b);
  }
};
/// one hydra of the colony: where it rises from the mound, where its head
/// stands, how thick it is and how far its tentacles hang
const Hydra=struct{
  /// where its body rises out of the mound
  foot:V3,
  /// where its head sits
  top:V3,
  /// its body's radius
  r:f32,
  /// how long its tentacles run
  reach:f32,
};
/// the hydra colony, tallest first, each leaning a little out from the mound's heart
const hydras=[_]Hydra{
  .{.foot=v3(0.02,0.03,-0.01),.top=v3(0.03,0.72,-0.02),.r=0.026,.reach=0.7},
  .{.foot=v3(0.14,0.02,0.09),.top=v3(0.25,0.5,0.16),.r=0.022,.reach=0.5},
  .{.foot=v3(-0.13,0.02,0.1),.top=v3(-0.24,0.42,0.17),.r=0.02,.reach=0.42},
  .{.foot=v3(-0.02,0.02,-0.16),.top=v3(-0.05,0.34,-0.29),.r=0.018,.reach=0.36},
};
/// one hydra along spline `id`: its body, head cone and mouth, and its
/// crown of tentacles (shared with the hydra colony)
pub fn body(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,o:Body,rng:*Rng)Allocator.Error!void{
  // the drawn body, and its tu.x, radius and colour per ring
  var sp:[bodyRings]V3=undefined;
  k.path(id,0,1,&sp);
  var ts:[bodyRings]f32=undefined;
  var rs:[bodyRings]f32=undefined;
  var cs:[bodyRings]color.Rgba8=undefined;
  for(&ts,&rs,&cs,0..)|*t,*r,*c,j|{
    // how far up the body, 0 foot .. 1 head
    const f=m.ratio(j,bodyRings-1);
    t.*=f;
    // slender, swelling at its gut, narrowing to the head
    r.*=o.r*(0.8+0.45*@exp(-(f-0.66)*(f-0.66)*20))*(1-0.2*m.smooth(m.clamp01((f-0.88)/0.12)));
    c.*=o.base.lerp(pearl,m.smooth(m.clamp01(f/0.4))).lerp(gut,0.5*@exp(-(f-0.66)*(f-0.66)*30)).toRgba8(255);
    if(o.head!=.cone){
      // an open head: the body opens like a trumpet into its disc
      const ff=m.clamp01((f-0.84)/0.16);
      r.*=m.lerp(r.*,o.r*openFlare,ff*ff);
      c.*=c.toRgb().lerp(lib.polypMesh.disc,m.smooth(ff)).toRgba8(255);
    }
  }
  {
    // where the body's vertices begin
    const s=b.mark();
    try b.tubeC(&sp,&ts,&rs,&cs,null,.tendril,10);
    try k.along(b,s,id);
  }
  // the head: where the body ends, the way it faces, two ways across it
  const top=sp[bodyRings-1];
  const up=m.norm(sp[bodyRings-1]-sp[bodyRings-3]);
  const e1=m.norm(m.cross(up,if(@abs(up[2])<m.nearParallel)v3(0,0,1)else v3(1,0,0)));
  const e2=m.cross(up,e1);
  // the head's radius, where the body ends
  const hr=rs[bodyRings-1];
  if(o.head!=.cone){
    try lib.polypMesh.mouthOn(b,k,id,top,up,hr,rng);
    if(o.bead){
      // where its vertices begin
      const s=b.mark();
      try kit.resinPod(b,top+up*m.splat3(hr*0.3),v3(hr*0.3,hr*0.24,hr*0.3),6,10);
      try k.on(b,s,id,1,.{.from=top,.delay=0.05});
    }
    if(o.head!=.plumed)for(0..o.feathers)|j|{
      // this feathery tentacle's bearing
      const a=(m.f(j)+rng.range(-0.15,0.15))/m.f(o.feathers)*m.tau;
      try lib.polypMesh.tentacle(b,k,id,.{.top=top,.up=up,.e1=e1,.e2=e2,.dr=hr,.r=hr/lib.polypMesh.flare},a,rng);
    };
    if(o.head!=.feathered)for(0..o.arms)|j|{
      // this long tentacle's bearing (between the feathery ones, crowned
      // with both), and the flat way out along it
      const a=(m.f(j)+@as(f32,if(o.head==.both)0.5 else 0)+rng.range(-0.15,0.15))/m.f(o.arms)*m.tau;
      const out=e1*m.splat3(@cos(a))+e2*m.splat3(@sin(a));
      // where it leaves: the rim, or from under the feathery crown
      const root=if(o.head==.both)top+out*m.splat3(hr*0.8)-up*m.splat3(hr*0.18)else top+out*m.splat3(hr*0.86)+up*m.splat3(hr*0.04);
      try hanging(b,k,id,.{.root=root,.out=out,.up=up,.len=o.reach*rng.range(0.85,1.15),.r0=o.r*0.3,.tip=.plume},rng);
    };
    return;
  }
  {
    // the head cone, closing to a point round the mouth at its tip
    var cp:[6]V3=undefined;
    var ct:[6]f32=undefined;
    var cr:[6]f32=undefined;
    for(&cp,&ct,&cr,[_]f32{0,0.2,0.45,0.7,0.88,1},[_]f32{1,0.96,0.82,0.58,0.32,0})|*p,*t,*r,f,w|{
      p.*=top+up*m.splat3(f*o.r*2.4);
      t.*=1;
      r.*=hr*w;
    }
    // where the head's vertices begin
    const s=b.mark();
    try b.tubeR(&cp,&ct,&cr,pearl.lerp(thread,0.4).toRgba8(255),.tendril,10);
    try mg.ellipsoid(b,.{.center=top+up*m.splat3(o.r*2.25),.radii=m.splat3(o.r*0.28),.col=mouth.toRgba8(255),.part=.tendril,.rings=4,.segs=6,.t=1});
    try k.on(b,s,id,1,.{.from=top});
  }
  for(0..o.arms)|j|{
    // this tentacle's bearing, and the flat way out along it
    const a=(m.f(j)+rng.range(-0.2,0.2))/m.f(o.arms)*m.tau;
    const out=e1*m.splat3(@cos(a))+e2*m.splat3(@sin(a));
    // where it leaves the head, just under the cone
    const root=top+out*m.splat3(hr*0.85)+up*m.splat3(o.r*0.3);
    try hanging(b,k,id,.{.root=root,.out=out,.up=up,.len=o.reach*rng.range(0.85,1.15),.r0=o.r*0.3},rng);
  }
}
/// a long tentacle hanging from a head: where it leaves, which ways, how
/// long and thick
pub const Hang=struct{
  /// where it leaves the head
  root:V3,
  /// the flat way out it reaches
  out:V3,
  /// the way the head faces
  up:V3,
  /// how long it runs
  len:f32,
  /// its radius at the root
  r0:f32,
  /// how its tip ends
  tip:Tip=.bare,
};
/// how a hanging tentacle's tip ends
pub const Tip=enum{
  /// tapering to a bare point
  bare,
  /// in a feathery plume of the polyp's soft pinnules
  plume,
};
/// where along a plumed tentacle its plume begins (0 root .. 1 tip)
const plumeFrom:f32=0.62;
/// pinnule pairs in a plume
const plumePairs=7;
/// one tentacle off spline `head`'s tip as `o` says: up and out, over,
/// then hanging far down, drifting aside, beaded with stinging knots,
/// tapering to a point (shared with the mixed polyps)
pub fn hanging(b:*mg.Builder,k:*growth.Skeleton,head:growth.Id,o:Hang,rng:*Rng)Allocator.Error!void{
  // the way across it, and how far it drifts aside as it hangs
  const across=m.norm(m.cross(o.up,o.out));
  const drift=rng.range(-0.25,0.25)*o.len;
  // its shape: up and out, over, then hanging far down, drifting aside
  const shape=[_][3]f32{.{0,0,0},.{0.08,0.12,0},.{0.22,0.24,0.1},.{0.38,0.22,0.3},.{0.5,0.06,0.55},.{0.56,-0.14,0.78},.{0.58,-0.34,0.92},.{0.57,-0.5,1}};
  // its control points (the first left for the skeleton to root)
  var c:[9]V3=undefined;
  for(shape,c[1..])|q,*pt|pt.*=o.root+o.out*m.splat3(q[0]*o.len)+o.up*m.splat3(q[1]*o.len)+across*m.splat3(q[2]*drift);
  // keep its far end above the soil
  for(c[1..])|*pt|pt[1]=@max(pt[1],0.08+0.05*rng.float());
  // its branch on the skeleton, off the head
  const arm=k.branch(head,1,&c,.{});
  // the drawn tentacle, and its tu.x, radius and colour per ring
  var p:[tentacleRings]V3=undefined;
  m.splineResample(c[1..],&p);
  var tts:[tentacleRings]f32=undefined;
  var trs:[tentacleRings]f32=undefined;
  var tcs:[tentacleRings]color.Rgba8=undefined;
  // how many knots it carries: as many a metre, three at least
  const n=@max(3,knots*o.len);
  for(&tts,&trs,&tcs,0..)|*t,*r,*cc,i|{
    // how far along, 0 root .. 1 tip
    const f=m.ratio(i,tentacleRings-1);
    t.*=m.lerp(0.6,1,f);
    // a stinging knot swelling here and there along it (a smooth field)
    // (a plumed one's knots stop where its plume begins)
    const bead=if(o.tip==.plume and f>plumeFrom-0.05)0 else m.smooth(m.clamp01(@sin(f*n*m.tau)*2-1));
    r.*=o.r0*@min(1,f*6+0.4)*(1-f*0.9)*(1+0.9*bead);
    cc.*=thread.lerp(knot,bead).toRgba8(255);
  }
  // where its vertices begin
  const s=b.mark();
  try b.tubeC(&p,&tts,&trs,&tcs,null,.tendril,6);
  try k.along(b,s,arm);
  if(o.tip==.bare)return;
  for(0..plumePairs)|q|{
    // how far along this pair sits, and how far into the plume
    const u=m.lerp(plumeFrom,0.95,m.ratio(q,plumePairs-1));
    const g=m.ratio(q,plumePairs-1);
    // fullest a little into the plume, shorter toward its tip
    const size=@sin(m.pi*m.lerp(0.25,1,g));
    try lib.polypMesh.pinnulePair(b,k,arm,&p,u,across,o.len*0.09*size,o.r0*0.5,thread.lerp(knot,0.4+0.5*g).toRgba8(255));
  }
}
