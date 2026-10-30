//! mesh: ARSTHRAXIA, WOVEN. the arsthraxia the unforming evolves into the
//! convergent lineage. Its stand is the arsthraxia's own: three stems
//! rising out of its foot, twining, parting into a cage round a sac and
//! gathering under its flower, its nerve rising up the cage's middle. But
//! each stem is the convergence kit's weave of green and pale strands, the
//! resin pod a marbled sac of both saps, the root mat and foot leaves the
//! kit's foot (a pale bulb, five pale roots, five green braided ones), each
//! tendril a lilac frond rolling into a crozier, the calyx pale frondlets.
//! Its flower is the kit's own, two nested: a broad bloom (`whorl`) and a
//! smaller one rising out of it (`cup`), each a bead of both saps in a
//! calyx of lilac frondlets, living petals and pearl stamens. It floats a
//! little over the calyx, not quite let go: tethered to it by thin strands
//! of both lineages drawn in to its heart (`tethers`). The structure emits
//! the blooms as it does the arsthraxia's whorls, `lift` over its heart;
//! `whole` is its preview. It grows along growth splines.
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
/// how far over the arsthraxia's heart its flower floats, held by its tethers
pub const lift:f32=0.13;
/// how many tethers hold it (alternately green and pale: both lineages)
const tetherCount=6;
/// mesh: ARSTHRAXIA WOVEN. the evolved arsthraxia's stand alone, as the
/// structure grows it: its whorls and core are emitted
pub const stand=struct{
  /// builds the woven stand
  pub fn build(b:*mg.Builder)Allocator.Error!void{try standOf(b);}
};
/// mesh: ARSTHRAXIA WOVEN WHORL. its broad flower, the kit's: a bead of
/// both saps in a calyx of five lilac frondlets, nine living petals warm at
/// the heart to violet at the rim, pearl stamens; its heart the origin. It
/// turns slowly while it studies.
pub const whorl=struct{
  /// builds the broad bloom, opening in the arsthraxia's flower's time
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try bloomAt(b,.{.heart=v3(0,0,0),.len=0.5,.petals=9,.seed=0x7C50},0);
  }
};
/// mesh: ARSTHRAXIA WOVEN CUP. the smaller bloom rising out of the broad
/// one's heart, the kit's too: five living petals, its own calyx and bead;
/// it turns against the broad one while it studies
pub const cup=struct{
  /// builds the small bloom, opening after the broad one
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try bloomAt(b,.{.heart=v3(0,0.09,0),.len=0.28,.petals=5,.spin=0.63,.seed=0x7C51},12);
  }
};
/// the kit's bloom `f`, opening as the arsthraxia's flower does, `after`
/// petals' staggers late
fn bloomAt(b:*mg.Builder,f:kit.Bloom,after:usize)Allocator.Error!void{
  // where its vertices begin, so it opens in its turn
  const s=b.mark();
  try kit.bloom(b,f);
  try growth.tag(b,s,f.heart,.{1-ax.form+ax.whorlStagger*m.f(after),ax.petalOpen*3});
}
/// mesh: ARSTHRAXIA WOVEN WHOLE. it at rest with its flower: the evolved
/// arsthraxia's preview
pub const whole=struct{
  /// builds it at rest, its whorls set on its heart
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try standOf(b);
    // where the whorls' vertices begin, so only they are moved up to the heart
    const s=b.mark();
    try whorl.build(b);
    try cup.build(b);
    b.xform(s,m.translate(ax.heartAt+v3(0,lift,0)));
  }
};
/// the convergent stand: three woven stems on the kit's foot, a frond off
/// each, the cage's nerve and its sac, and the calyx, leaving the last
/// `form` of the growth for the emitted whorls
fn standOf(b:*mg.Builder)Allocator.Error!void{
  // the growth skeleton the whole stand is hung on
  var sk=growth.Skeleton.begin(b);
  sk.tail=ax.form;
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
  try tethers(b,&sk,stems[0]);
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
/// the strands its floating flower is held by: from round the calyx's
/// heart they bow out a little and draw in again to the flower's own heart
/// on its axis (so it may turn and bob, still held), alternately a
/// symbiote's green and a parasite's pale, thinning as they rise
fn tethers(b:*mg.Builder,sk:*growth.Skeleton,trunk:growth.Id)Allocator.Error!void{
  // where they spring from, and where they are drawn in to (inside its bead)
  const from=ax.heartAt-v3(0,0.04,0);
  const to=ax.heartAt+v3(0,lift+0.05,0);
  for(0..tetherCount)|i|{
    // this tether's bearing (radians), the way out along it, and its own sway
    const a=(m.f(i)+0.25)/m.f(tetherCount)*m.tau;
    const out=v3(@cos(a),0,@sin(a));
    const w=0.015*@sin(m.f(i)*2.7);
    // its course: out of the calyx, bowing out, in to the flower's heart
    const c=[_]V3{
      from+out*m.splat3(0.035),
      from+out*m.splat3(0.08+w)+v3(0,lift*0.45,0),
      to-v3(0,0.06,0)+out*m.splat3(0.05),
      to,
    };
    // its course resampled smooth
    var p:[10]V3=undefined;
    m.splineResample(&c,&p);
    // where its vertices begin, so it draws out after the calyx opens
    const s=b.mark();
    try kit.taper(b,&p,0.007,0.35,1,1,if(i%2==0)kit.green else kit.pale,.tendril,4);
    try sk.on(b,s,trunk,1,.{.from=from,.delay=ax.petalStagger*m.f(kit.fold+i)});
  }
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
