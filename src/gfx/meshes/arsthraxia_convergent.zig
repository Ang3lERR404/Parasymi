//! mesh: ARSTHRAXIA, CONVERGENT. two looks for the arsthraxia the
//! unforming evolves into the convergent lineage, laid beside it to
//! compare (`--samples=arsthraxiaWhole,arsthraxiaWoven,arsthraxiaBloomed`).
//! Both keep its stand: three stems rising out of its foot, twining,
//! parting into a cage round a sac and gathering under its flower, its
//! nerve rising up the cage's middle. But each stem is the convergence
//! kit's weave of green and pale strands, the resin pod a marbled sac of
//! both saps, the root mat and foot leaves the kit's foot (a pale bulb, five
//! pale roots, five green braided ones), and each tendril a lilac frond
//! rolling into a crozier. WOVEN keeps its own two whorls, coloured as the
//! kit's living petals (warm at the heart to violet at the rim); BLOOMED
//! opens the kit's flower of both instead, a great one, pale frondlets
//! round living petals and pearl stamens. They grow along growth splines.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// all the maths: vectors, matrices, splines
const m=lib.engine.core.math;
/// the mesh builder and its primitives
const mg=lib.meshgen;
/// the garden's growth timing: the skeleton it grows along
const growth=lib.growth;
/// the parasites' kit: the weave's stalk shape and sections
const pk=lib.parasiteKit;
/// the convergence kit: weave, sac, fronds, flower, foot, palette
const kit=lib.convergenceKit;
/// the arsthraxia's own stand: its stems' course, cage and flower
const ax=lib.arsthraxia;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// a stem's weave: a plain braid of both, opening a little where the
/// stems part round the cage
const stemStalk:pk.Stalk=.{.girth=0.055,.part=1.2,.from=0.55,.to=0.85};
/// the look with its own whorls in the kit's living colours
pub const woven=struct{
  /// builds it at rest, its whorls set on its heart
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try stand(b);
    // where the whorls' vertices begin, so only they are moved up to the heart
    const s=b.mark();
    try ax.petals(b,9,0,0,.{
      .base=v3(0,0,0),.out=undefined,.len=0.62,.width=0.3,.rise=0.55,.flare=0.7,.cup=0.4,
      .col=kit.petalBase,.tip=kit.petalTip,.t=1,.part=.leaf,
    });
    try ax.petals(b,5,0.5,9,.{
      .base=v3(0,0,0),.out=undefined,.len=0.42,.width=0.22,.rise=1.15,.flare=0.4,.cup=0.4,
      .col=kit.petalBase,.tip=kit.petalTip,.t=1,.part=.leaf,
    });
    try mg.stamens(b,.{
      .heart=v3(0,0,0),.axis=v3(0,1,0),.n=9,.len=0.32,.r=0.009,.anther=0.055,
      .lean=0.4,.arch=0.6,.col=kit.pearl,.t=1,.seed=0x7C05,
    });
    b.xform(s,m.translate(ax.heartAt));
  }
};
/// the look crowned with the kit's flower of both
pub const bloomed=struct{
  /// builds it at rest, a great flower of both on its heart
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try stand(b);
    try kit.bloom(b,.{.heart=ax.heartAt,.len=0.55,.petals=9,.seed=0x7C06});
  }
};
/// the convergent stand: three woven stems on the kit's foot, a frond off
/// each, the cage's nerve and its sac, and the calyx
fn stand(b:*mg.Builder)Allocator.Error!void{
  // the growth skeleton the whole stand is hung on
  var sk=growth.Skeleton.begin(b);
  // the three stems' splines, the first the trunk the rest hang on
  var stems:[ax.stemCount]growth.Id=undefined;
  for(&stems,0..)|*id,k|id.*=try stem(b,&sk,if(k==0)null else stems[0],k);
  try kit.footOn(b,&sk,stems[0],.{.r=0.13,.reach=0.9,.rootR=0.026,.seed=0x7C01});
  for(stems,0..)|id,k|{
    // this frond's heading: the stem's own where the cage is widest
    const a=ax.stemAngle(k)+ax.stemAt[6][2];
    // how far along the stem that widest point is (0..1)
    const u=sk.nearest(id,v3(@cos(a)*ax.stemAt[6][1],ax.stemAt[6][0],@sin(a)*ax.stemAt[6][1]));
    _=try kit.frondOn(b,&sk,id,u,.{
      .from=sk.point(id,u),.out=v3(@cos(a),0,@sin(a)),.len=0.45,.r=0.012,
      .rise=1.1,.curl=3.0,.pairs=5,.leafLen=0.07,.leafW=0.02,
      .t0=0.75,.t1=0.95,.seed=0x7C40,.leafSeed=0x7C41+%k*97,
    },.{.after=.passing});
  }
  try cage(b,&sk,stems[0]);
  try calyx(b,&sk,stems[0]);
  sk.finish(b);
}
/// stem `k` along the arsthraxia's own course, woven of both lineages
fn stem(b:*mg.Builder,sk:*growth.Skeleton,first:?growth.Id,k:usize)Allocator.Error!growth.Id{
  // this stem's starting heading (radians)
  const a0=ax.stemAngle(k);
  // its control points, laid from the stand's course round its heading
  var ctrl:[ax.stemAt.len]V3=undefined;
  for(&ctrl,ax.stemAt)|*c,p|c.*=v3(@cos(a0+p[2])*p[1],p[0],@sin(a0+p[2])*p[1]);
  // where it gathers under the flower, kept through the wobble
  const top=ctrl[ctrl.len-1];
  mg.grow(&ctrl,.{.start=ctrl[0],.direction=v3(0,1,0),.length=ax.height,.wobble=0.05,.seed=0x7C10+%k*31});
  ctrl[ctrl.len-1]=top;
  // its spline: the trunk, or a branch growing with it from the root
  const id=if(first)|f|sk.branch(f,0,&ctrl,.{.after=.with,.pace=ax.stalkPace})else sk.trunk(&ctrl,.{.pace=ax.stalkPace});
  // the weave's path and sections (unused beyond it)
  var sp:[growth.res]V3=undefined;
  var sec:[growth.res]pk.Section=undefined;
  try kit.weaveOn(b,sk,id,stemStalk,.{.seed=0x7C20+%k*7},0.05,0.6,&sp,&sec);
  return id;
}
/// inside the cage: the nerve rising up its middle from the trunk to the
/// flower's heart, a sac of both saps threaded on it where the cage is widest
fn cage(b:*mg.Builder,sk:*growth.Skeleton,trunk:growth.Id)Allocator.Error!void{
  // where up the trunk the nerve leaves it (0..1)
  const from=sk.nearest(trunk,v3(0,ax.stemAt[4][0]-0.06,0));
  // the nerve's own spline, up the cage's middle to under the heart
  const id=sk.branch(trunk,from,&.{v3(0,0,0),v3(0,0.95,0),v3(0,ax.cageY,0),v3(0,ax.heartAt[1]-0.03,0)},.{.after=.passing});
  // its resampled points, and each ring's nerve tu and radius, pointed at both ends
  const path=&sk.get(id).pts;
  var ts:[growth.res]f32=undefined;
  var rs:[growth.res]f32=undefined;
  for(&ts,&rs,path,0..)|*t,*r,p,i|{
    // how far along the nerve this ring is (0..1)
    const u=m.ratio(i,growth.res-1);
    t.*=ax.nerveAt(p[1]);
    r.*=@max(0.017*m.pow(f32,@sin(m.pi*u),0.4),2e-4);
  }
  // where the nerve's vertices begin, so it rises along its spline
  const s=b.mark();
  try b.tubeR(path,&ts,&rs,ax.nerve,.nerve,6);
  try sk.along(b,s,id);
  // where the sac sits, threaded on the nerve
  const at=v3(0,ax.cageY,0);
  // where the sac's vertices begin, so it swells as the nerve passes
  const p=b.mark();
  try kit.sac(b,.{.center=at,.radii=v3(0.11,0.14,0.11),.t=0.7,.arms=3,.phase=0.9});
  try sk.on(b,p,id,sk.nearest(id,at),.{.from=at});
}
/// the calyx the stems gather into: five pale frondlet sepals, exactly
/// alike, cupped up under the flower, greening at their tips
fn calyx(b:*mg.Builder,sk:*growth.Skeleton,trunk:growth.Id)Allocator.Error!void{
  // where the sepals spring from, just under the flower's heart
  const heart=ax.heartAt-v3(0,0.05,0);
  for(0..kit.fold)|i|{
    // this sepal's angle round the heart (radians), and the way out along it
    const a=(m.f(i)+0.5)/m.f(kit.fold)*m.tau;
    const out=v3(@cos(a),0,@sin(a));
    // where its vertices begin, so it opens in its turn
    const s=b.mark();
    try mg.petal(b,.{
      .base=heart+out*m.splat3(0.03),.out=out,.len=0.26,.width=0.12,
      .rise=0.75,.flare=0.35,.cup=0.5,
      .col=kit.pale,.tip=kit.leafLite,.t=1,.part=.leaf,
    });
    try sk.on(b,s,trunk,1,.{.from=heart,.delay=ax.petalStagger*m.f(i)});
  }
}
