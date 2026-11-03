//! mesh: LITHOPHAGE. a stone coral that eats stone: half plant, half
//! mineral. A pale bulbous foot half sunk in the soil (the lineage's
//! tissue), a cup of five stony septa on its crown where the grit it saps
//! pools (`germinatorPool`, emitted), and five coral limbs rising out of
//! it, exactly alike (the parasites' fives), each forking in two, crystals
//! budding on them. The crystal it condenses from what it draws buds on
//! the first limb (`crystal`, emitted at `budAt`) and is sapped away down
//! into the cup (`germinatorPour`).
//! It grows on forever, never scaled up whole: the young coral (`build`)
//! is grown in at once; each later tier (`Tier(n)`) grows on from the tips
//! the one before left, wider and higher, the coral's foot creeping out
//! over the ground between its limbs with an upright where it ends, its
//! crystals bigger tier by tier. The structure grows each tier over the
//! step of its life before it reaches a tile further; the last never
//! quite ends. One coral (`colony`) is laid out for all of them, so a tier
//! grows exactly from where the last left off.
//! Its tendrils to the nodes it drains are its own (`Tendril(n)`, one for
//! each length in `tendrilLens`): built straight along +Y over 0..1 (bent
//! on the GPU along their curves), each runs under the ground near the
//! coral, a line of cracks with a glow showing through, surfaces through
//! a few heaved stones and creeps on over the ground as a pale coral
//! runner, small crystals budding along it, to dig into its node with
//! five rootlets and a last cluster of crystals. It grows out along its
//! own spline as it reaches (emitted with that as `grown`) and withers
//! back down it.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, rng, the mesh builder underneath
const engine=lib.engine;
/// all the maths: vectors, matrices, easing
const m=engine.core.math;
/// the plant-piece mesher: tubes, ellipsoids, the builder itself
const mg=lib.meshgen;
/// colour conversions, for the coral's bone and the crystals' lilac
const color=engine.core.color;
/// a colour as four bytes
const Rgba8=color.Rgba8;
/// the garden's growth timing: the hidden splines everything grows along
const growth=lib.growth;
/// the parasite kit: the foot, its palette and its fives
const pk=lib.parasiteKit;
/// the mineral kit: faceted crystals and weathered stones
const mineral=lib.mineralKit;
/// part roles: how the shader draws each piece
const vertex=lib.vertex;
/// the seeded random stream crystals and cracks are shaped by
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a point in space from three numbers
const v3=m.v3;
/// straight up
const up=v3(0,1,0);
/// up in a tendril's own frame (x across it, y along it, z up)
const lie=v3(0,0,1);
/// how many tiers of later growth its coral has
pub const tiers=4;
/// the lengths its tendril meshes are built at (tiles): the structure
/// bends the nearest along each tendril's curve
pub const tendrilLens=[_]f32{1,1.41,2,2.24,2.83,3.16,3.61,4.12,4.6,5.1,5.8,6.5};
/// where the cup of septa on its foot sits, which the grit runs down into
pub const cupAt=v3(0,0.045,0);
/// where the crystal it condenses buds: on the first limb's outer flank,
/// just above its fork
pub const budAt=budPoint();
/// where the foot sits, half sunk in the soil
const footAt=v3(0,-0.02,0);
/// the foot's half-sizes along x, y and z
const footR=v3(0.12,0.085,0.12);
/// the dark under the foot, where its tissue shows beneath the stone
const footDark=color.rgb(0.42,0.39,0.46).toRgba8(255);
/// the coral's bone pale, where it is old
const bone=color.rgb(0.76,0.73,0.77).toRgba8(255);
/// the paler bone of its growing tips
const tipCol=color.rgb(0.92,0.9,0.94).toRgba8(255);
/// the crystals' clear lilac body
const gemBody=color.rgb(0.8,0.77,0.98).toRgba8(255);
/// the near-white their points pale to
const gemTip=color.rgb(0.98,0.96,1.0).toRgba8(255);
/// the dark of a crack's lips in the ground
const lipCol=color.rgb(0.1,0.075,0.065).toRgba8(255);
/// the glow showing through a crack: the tendril's light under the ground
const seamCol=color.rgb(0.5,0.42,0.62).toRgba8(255);
/// the part role coral is drawn with: weathered stone, grained and flecked
const coralPart:vertex.Part=.stone;
/// how many sides round a coral limb
const sides=7;
/// how many rings along a coral limb
const rings=12;
/// how many control points a coral limb is laid out by
const limbPts=6;
/// the most limbs one fifth of the coral holds, all tiers together
const mostLimbs=64;
/// the first limb, rising out of the foot and leaning far out, a vase's
/// rim (in its fifth, facing +X)
const primary=[limbPts]V3{v3(0.05,0,0),v3(0.08,0.06,0),v3(0.12,0.13,0),v3(0.16,0.2,0),v3(0.2,0.26,0),v3(0.23,0.31,0)};
/// how far up the first limb it forks in two
const forkAt:f32=0.42;
/// how far along a fork its twig springs off
const twigAt:f32=0.55;
/// the most limbs one fifth of a tier grows (its skeleton holds 64 splines
/// for all five)
const perTier=12;
/// how far up the first limb the crystal it condenses buds
const budU:f32=0.62;
/// where that crystal buds: just off the first limb's outer flank
fn budPoint()V3{
  @setEvalBranchQuota(100000);
  return pointOn(&primary,budU)+v3(0.035,0.012,0);
}
/// one coral limb in one fifth of the coral (turned into place for each)
const Limb=struct{
  /// its control points
  ctrl:[limbPts]V3,
  /// its girth at its root
  r0:f32,
  /// its girth at its tip, a share of that
  tip:f32,
  /// the tier it is grown in (0: the young coral)
  tier:u8,
  /// the limb of its own tier it forks off (an index into the colony;
  /// null: it grows on from an older tier, or out of the foot)
  parent:?u8=null,
  /// how far along that limb it forks off
  at:f32=1,
  /// whether it swells into what it grows out of (a fork, a limb grown on
  /// from an old tip)
  flare:bool=false,
  /// where along it a cluster of crystals buds (null: none)
  bud:?f32=null,
};
/// the whole coral, one fifth of it, every tier
const Colony=struct{
  /// its limbs, the first `n` in use, each after the one it forks off
  limbs:[mostLimbs]Limb=undefined,
  /// how many limbs it has
  n:u8=0,
  /// a limb added; returns its index
  fn add(c:*Colony,l:Limb)u8{
    c.limbs[c.n]=l;
    c.n+=1;
    return c.n-1;
  }
};
/// control points stepped out from `from` heading `dir`, `len` long, the
/// heading turned by `bend` at each step
fn stepped(from:V3,dir:V3,len:f32,bend:V3)[limbPts]V3{
  // the points, where the next goes, and the heading now
  var out:[limbPts]V3=undefined;
  var p=from;
  var d=m.norm(dir);
  for(&out)|*q|{
    q.*=p;
    p+=d*m.splat3(len/(limbPts-1));
    d=m.norm(d+bend);
  }
  return out;
}
/// where a limb ends
fn endOf(l:Limb)V3{return l.ctrl[limbPts-1];}
/// which way a limb runs at its end
fn headOf(l:Limb)V3{return m.norm(l.ctrl[limbPts-1]-l.ctrl[limbPts-2]);}
/// the point `u` along the curve through `ctrl`, by its length
fn pointOn(ctrl:[]const V3,u:f32)V3{
  // the curve, resampled evenly by length
  var pts:[growth.res]V3=undefined;
  m.splineResample(ctrl,&pts);
  return m.alongPath(&pts,u);
}
/// the coral, one fifth of it, laid out for every tier: the young limb
/// leaning out of the foot, forking in two, each fork throwing a twig
/// further out; then for each tier every tip grown on outward (side twigs
/// off some in the first), as many as `perTier` allows, and its foot
/// creeping on over the ground with an upright where it ends
fn colony()Colony{
  // the coral, and the tips of the tier last laid, to grow on from
  var c:Colony=.{};
  var tips:[mostLimbs]u8=undefined;
  var nt:usize=0;
  // the young limb, a cluster of crystals budding near its tip
  const p=c.add(.{.ctrl=primary,.r0=0.032,.tip=0.75,.tier=0,.bud=0.86});
  tips[nt]=p;
  nt+=1;
  // where it forks, and which way it runs there
  const fork=pointOn(&primary,forkAt);
  const head=m.norm(pointOn(&primary,forkAt+0.05)-fork);
  for([_]f32{-1,1})|sd|{
    // the fork, curling up as it goes
    const d=c.add(.{.ctrl=stepped(fork,head*m.splat3(0.7)+v3(0.25,0,0.55*sd),0.21,v3(0,0.07,0)),.r0=0.023,.tip=0.8,.tier=0,.parent=p,.at=forkAt,.flare=true});
    tips[nt]=d;
    nt+=1;
    // its twig, thrown further out to the side, crystals budding on one
    const df=pointOn(&c.limbs[d].ctrl,twigAt);
    const dh=m.norm(pointOn(&c.limbs[d].ctrl,twigAt+0.05)-df);
    tips[nt]=c.add(.{.ctrl=stepped(df,dh*m.splat3(0.6)+v3(0.1,0.15,0.6*sd),0.12,v3(0,0.08,0)),.r0=0.016,.tip=0.85,.tier=0,.parent=d,.at=twigAt,.flare=true,.bud=if(sd>0)0.7 else null});
    nt+=1;
  }
  // the creeping foot of the tier last laid (none yet), and which way
  // it creeps: between this fifth and the next
  var basal:?u8=null;
  const between=v3(@cos(m.tau/10.0),0,@sin(m.tau/10.0));
  for(1..tiers+1)|n|{
    // this tier, how many limbs it has laid, and the tips it leaves
    const t:u8=@intCast(n);
    var laid:usize=0;
    var next:[mostLimbs]u8=undefined;
    var nn:usize=0;
    for(tips[0..nt],0..)|ti,j|{
      if(laid+2>=perTier)break;
      // the old tip: where it ends, which way, which way is out from the
      // coral's heart there, and how thick it ends
      const old=c.limbs[ti];
      const end=endOf(old);
      const hd=headOf(old);
      const out=m.norm(v3(end[0],0,end[2]));
      const rr=old.r0*old.tip;
      // grown on from inside its rounded tip, out and a little up
      const on=c.add(.{.ctrl=stepped(end-hd*m.splat3(rr*0.6),hd*m.splat3(0.45)+out*m.splat3(0.75)+up*m.splat3(0.2),0.15+0.02*m.f(n),up*m.splat3(0.05)),.r0=rr,.tip=0.9,.tier=t,.flare=true,.bud=if((j+n)%2==0)0.6 else null});
      laid+=1;
      next[nn]=on;
      nn+=1;
      // in the first tier, every other one throws a side twig
      if(n>1 or j%2==1 or laid+2>=perTier)continue;
      const e=c.limbs[on];
      const tf=pointOn(&e.ctrl,twigAt);
      const th=m.norm(pointOn(&e.ctrl,twigAt+0.05)-tf);
      // which way is across it, and which side the twig takes
      const side=m.norm(m.cross(th,up));
      const sd:f32=if(j%4==0)1 else-1;
      next[nn]=c.add(.{.ctrl=stepped(tf,th+side*m.splat3(0.7*sd)+up*m.splat3(0.3),0.1,up*m.splat3(0.06)),.r0=e.r0*e.tip*0.85,.tip=0.88,.tier=t,.parent=on,.at=twigAt,.flare=true});
      laid+=1;
      nn+=1;
    }
    // the foot creeps on over the ground, from the foot's rim or from
    // where it last stopped, a cluster of crystals budding on it
    const from=if(basal)|b|endOf(c.limbs[b])-between*m.splat3(0.02)else between*m.splat3(0.06)+v3(0,0.006,0);
    const r0=if(basal)|b|c.limbs[b].r0*c.limbs[b].tip else 0.026;
    const b=c.add(.{.ctrl=stepped(from,between+v3(0,0.02,0),if(basal==null)0.34 else 0.22,v3(0,-0.004,0)),.r0=r0,.tip=0.88,.tier=t,.flare=basal!=null,.bud=0.55});
    basal=b;
    // an upright rising where it ends, leaning out
    next[nn]=c.add(.{.ctrl=stepped(pointOn(&c.limbs[b].ctrl,0.86),up+between*m.splat3(0.45),0.15+0.02*m.f(n),between*m.splat3(0.05)),.r0=r0*0.85,.tip=0.85,.tier=t,.parent=b,.at=0.86,.flare=true});
    nn+=1;
    tips=next;
    nt=nn;
  }
  return c;
}
/// a coral limb along spline `id`: a tube tapering from `l.r0` to its
/// blunt rounded tip, bone pale paling toward it, swelling into what it
/// grows out of where it flares
fn limbTube(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,l:Limb)Allocator.Error!void{
  // its rings: where, how far along, how thick, what colour
  var pts:[rings]V3=undefined;
  var ts:[rings]f32=undefined;
  var rs:[rings]f32=undefined;
  var cs:[rings]Rgba8=undefined;
  k.path(id,0,1,&pts);
  for(&ts,&rs,&cs,0..)|*t,*r,*c,i|{
    // how far along it this ring is (0..1)
    const f=m.ratio(i,rings-1);
    t.*=f;
    r.*=l.r0*(1-f*(1-l.tip))*(if(l.flare)mg.collar(f)else 1);
    c.*=color.mix(bone,tipCol,m.smooth(f));
  }
  // where the limb's vertices begin
  const s=b.mark();
  try b.tubeC(&pts,&ts,&rs,&cs,null,coralPart,sides);
  try creep(b,k,s,id);
}
/// how long a creeping limb's front is, as a share of its spline's time:
/// short, so its growing end stays blunt
const creepFront:f32=0.05;
/// everything built since `s` grows along spline `id` as coral does: at
/// its full girth from the first, a short blunt front creeping out to its
/// tip (never a thin sprout with a long pointed front, which on a tier
/// grown over days would stand as spikes)
// decision: coral limbs and runners grow this way rather than by
// `Skeleton.along`, whose thin sprout and long front taper read as thorns
fn creep(b:*mg.Builder,k:*const growth.Skeleton,s:usize,id:growth.Id)Allocator.Error!void{
  // how long the front is, in the skeleton's time
  const span=k.get(id).time*creepFront;
  for(b.v.items[s..],try b.growOf(s))|v,*g|{
    // how far along the spline the vertex lies
    const u=k.nearest(id,v.pos);
    g.*=.{.from=k.point(id,u),.at=.{k.when(id,u),span,0,0}};
  }
}
/// a cluster of three crystals budding at `at`, out of a limb or runner
/// along `out`, tipped toward `sky` (the mesh's up), `size` long at most,
/// grown out of `at` once the front passes `u` along spline `id`: every
/// cluster alike
fn cluster(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,u:f32,at:V3,out:V3,sky:V3,size:f32)Allocator.Error!void{
  // the same stream for every cluster, so they are alike
  var rng=Rng.init(0x11C7);
  // which way is across the way it buds
  const side=m.norm(m.cross(out,if(@abs(m.dot(out,sky))<m.nearParallel)sky else v3(1,0,0)));
  // where the cluster's vertices begin
  const s=b.mark();
  for([_]V3{out+sky*m.splat3(0.5),out*m.splat3(0.6)+side*m.splat3(0.75)+sky*m.splat3(0.35),out*m.splat3(0.6)-side*m.splat3(0.75)+sky*m.splat3(0.2)},[_]f32{1,0.72,0.58})|d,l|{
    try mineral.crystal(b,.{.base=at,.dir=m.norm(d),.len=size*l,.r=size*l*0.24,.col=gemBody,.tip=gemTip},&rng);
  }
  try k.on(b,s,id,u,.{.from=at,.delay=0.02});
}
/// a cluster budding on limb `l` (spline `id`) at `u`: on its outer side
/// (away from the coral's heart), bigger tier by tier
fn budOn(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,u:f32,l:Limb)Allocator.Error!void{
  // the point there, the way the limb runs, and the way out from the heart, square to it
  const p=k.point(id,u);
  const tan=k.tangent(id,u);
  const o=m.norm(v3(p[0],0.4,p[2]));
  const out=m.norm(o-tan*m.splat3(m.dot(o,tan)));
  // the limb's girth there
  const r=l.r0*(1-u*(1-l.tip));
  try cluster(b,k,id,u,p+out*m.splat3(r*0.6),out,up,0.065*(1+0.3*m.f(l.tier)));
}
/// builds tier `n` of the coral, in all five of its fifths, alike: its
/// limbs on its own growth skeleton (those grown on from an older tier
/// begin at once, forks as the front passes them), its crystals on them;
/// the young coral (`n` 0) on its foot, with its cup
fn tier(b:*mg.Builder,n:u8)Allocator.Error!void{
  // the coral laid out, and the skeleton this tier grows on
  const c=colony();
  var k=growth.Skeleton.begin(b);
  if(n==0)try foot(b,&k);
  for(0..pk.fold)|i|{
    // this fifth's turn, and each limb's spline in it
    const rot=m.rotY(m.ratio(i,pk.fold)*m.tau);
    var ids:[mostLimbs]?growth.Id=@splat(null);
    for(c.limbs[0..c.n],0..)|l,j|{
      if(l.tier!=n)continue;
      // its control points turned into this fifth
      var ctrl:[limbPts]V3=undefined;
      for(&ctrl,l.ctrl)|*q,p|q.*=m.mulPoint(rot,p);
      // its spline: off the limb it forks from, or its own from the start
      const id=if(l.parent)|pa|k.branch(ids[pa].?,l.at,&ctrl,.{.after=if(l.at<0.9).passing else.done})else k.trunk(&ctrl,.{.delay=if(n==0)0.3 else 0});
      ids[j]=id;
      try limbTube(b,&k,id,l);
      if(l.bud)|u|try budOn(b,&k,id,u,l);
    }
  }
  k.finish(b);
}
/// the young coral's foot: the lineage's bulb gone to stone, half sunk
/// in the soil on a hidden stalk, and on its crown a cup of five stony
/// septa, set between its limbs, where the grit it saps pools
fn foot(b:*mg.Builder,k:*growth.Skeleton)Allocator.Error!void{
  // the hidden stalk the foot swells round
  const stalk=k.trunk(&.{v3(0,-0.05,0),v3(0,0,0),cupAt},.{.pace=3});
  // the mound's vertices begin here: the lineage's bulb, gone to stone
  const mound=b.mark();
  try pk.nodule(b,footAt,footR,0,bone,footDark,tipCol);
  for(b.v.items[mound..])|*vx|vx.part=@intFromEnum(coralPart);
  try k.on(b,mound,stalk,0,.{.from=footAt,.span=k.get(stalk).time*0.3});
  for(0..pk.fold)|i|{
    // this septum's bearing, between two limbs
    const a=(m.f(i)+0.5)/pk.fold*m.tau;
    // where its vertices begin
    const s=b.mark();
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(0.032,0.02,0.007),.col=bone,.part=coralPart,.rings=5,.segs=8,.t=0.1});
    b.xform(s,m.chain(&.{m.translate(cupAt+v3(@cos(a)*0.042,0,-@sin(a)*0.042)),m.rotY(a)}));
    try k.on(b,s,stalk,1,.{.from=cupAt,.delay=0.05});
  }
}
/// builds the young lithophage: its foot and cup, and its five limbs,
/// each forking in two, a cluster of crystals budding near each tip
pub fn build(b:*mg.Builder)Allocator.Error!void{try tier(b,0);}
/// mesh: LITHOPHAGE TIER. tier `n` of its coral's later growth, grown on
/// from the tips the tier before left: what it adds as it reaches a tile
/// further
pub fn Tier(comptime n:u8)type{
  return struct{
    /// builds the tier: every tip grown on, its foot crept on, its crystals
    pub fn build(b:*mg.Builder)Allocator.Error!void{try tier(b,n);}
  };
}
/// mesh: LITHOPHAGE CRYSTAL. what the coral condenses from the ground: a
/// cluster of faceted crystals (part `.prism`, no light of their own) about
/// its own origin, a unit `radius` across; the structure grows it with
/// what it has drawn and shrinks it as it saps it away.
pub const crystal=struct{
  /// how far the cluster reaches from its heart, before the structure scales it
  pub const radius:f32=0.09;
  /// builds the cluster: nine crystals pointing out every way from the heart,
  /// spread evenly on a golden spiral, each sized a little differently
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the cluster's own seeded rng, so every crystal is alike
    var rng=Rng.init(0x117C);
    // the crystals' violet body and their amber tips
    const body=color.rgb(0.62,0.5,0.86).toRgba8(255);
    const tip=color.rgb(1.0,0.86,0.6).toRgba8(255);
    // points out every way from the heart, as it grows in sap
    for(0..9)|i|{
      // this crystal's angle round the heart (the golden angle per step)
      const th=m.f(i)*m.goldenAngle;
      // its height on the unit sphere, from near the top down to near the bottom
      const y=m.lerp(0.85,-0.85,m.ratio(i,8));
      // the sphere's radius at that height
      const rr=@sqrt(1-y*y);
      // which way this crystal points
      const dir=m.norm(v3(@cos(th)*rr,y,@sin(th)*rr));
      try mineral.crystal(b,.{
        .base=dir*m.splat3(-radius*0.25),.dir=dir,.len=radius*rng.range(0.85,1.15),.r=radius*rng.range(0.22,0.3),
        .col=body,.tip=tip,.part=.prism,
      },&rng);
    }
  }
};
/// mesh: LITHOPHAGE TENDRIL. one of its tendrils, built `tendrilLens[n]`
/// tiles long; see the file's header
pub fn Tendril(comptime n:usize)type{
  return struct{
    /// builds the tendril at its length
    pub fn build(b:*mg.Builder)Allocator.Error!void{try tendril(b,tendrilLens[n],0x11B0+%@as(u64,n));}
  };
}
/// how far out a tendril `len` long runs under the ground before it surfaces
fn surfaceOf(len:f32)f32{return@min(0.3+0.2*len,1.3);}
/// how far short of its node's middle a tendril digs in
const digShort:f32=0.2;
/// a runner's girth at its thickest
const runR:f32=0.026;
/// how far apart crystals bud along a runner
const budEvery:f32=0.3;
/// how far apart short coral side limbs spring off a runner
const sprigEvery:f32=0.75;
/// builds one tendril `len` long along +Y, then squeezes it into 0..1:
/// its hidden spline under the ground to where it surfaces, then over it
/// (x across, z up) to its node; the cracks over the first stretch, the
/// runner from there on with its crystals and side limbs, the heaved
/// stones where it surfaces, the rootlets and crystals where it digs in
fn tendril(b:*mg.Builder,len:f32,seed:u64)Allocator.Error!void{
  // where its vertices begin, its skeleton, and the stream its cracks wander by
  const first=b.mark();
  var k=growth.Skeleton.begin(b);
  var rng=Rng.init(seed);
  // where it surfaces, and where it digs in
  const rise=surfaceOf(len);
  const end=len-digShort;
  // its hidden spline: under the crust, up out of it, creeping on in low
  // swells, wandering a little, and down into the node
  var c:[m.maxSpline]V3=undefined;
  c[0]=v3(0,0.08,-0.02);
  c[1]=v3(0,rise*0.55,-0.02);
  c[2]=v3(0,rise-0.04,-0.012);
  // how many points the runner is laid out by, and how far apart
  const steps=@max(2,m.floorTo(usize,(end-rise)/0.32));
  for(0..steps)|j|{
    // how far along the runner this point is, and where
    const f=m.ratio(j+1,steps+1);
    const y=m.lerp(rise+0.06,end-0.1,f);
    c[3+j]=v3(0.025*@sin(y*3.1+m.f(seed%7)),y,runR*0.6+0.012*@sin((y-rise)*m.pi/0.5)*@sin((y-rise)*m.pi/0.5));
  }
  c[3+steps]=v3(0,end,-0.05);
  const sp=k.trunk(c[0..steps+4],.{});
  try cracks(b,&k,sp,0.1,rise+0.03,&rng);
  // the runner, from just under where it surfaces to its node
  const surf=k.nearest(sp,v3(0,rise-0.06,-0.015));
  try runner(b,&k,sp,surf);
  // the crust it heaves where it breaks through: three small stones
  // where they begin, so they rise as it surfaces
  const crust=b.mark();
  for([_]f32{-1,0.3,1})|sd|{
    // where this stone's vertices begin: built upright, laid into the tendril's frame
    const one=b.mark();
    try mineral.stone(b,v3(0,0,0),0.016+0.004*@abs(sd),0.6,color.rgb(0.42,0.38,0.36).toRgba8(255),color.rgb(0.62,0.58,0.55).toRgba8(255),&rng);
    b.xform(one,m.chain(&.{m.translate(v3(sd*0.035,rise+0.02*sd,0)),m.rotX(m.halfPi)}));
  }
  try k.on(b,crust,sp,surf,.{.from=v3(0,rise,0)});
  // crystals budding along it, side to side
  var y=rise+0.22;
  var sd:f32=1;
  while(y<end-0.25):(y+=budEvery){
    // how far along its spline, the point there, and which way it buds
    const u=k.nearest(sp,v3(0,y,0));
    const p=k.point(sp,u);
    const out=m.norm(v3(sd,0,0.7));
    try cluster(b,&k,sp,u,p+out*m.splat3(runR*0.6),out,lie,0.034);
    sd=-sd;
  }
  // short coral side limbs, flaring out of it
  y=rise+0.45;
  sd=-1;
  while(y<end-0.3):(y+=sprigEvery){
    // where it springs off, and its own spline
    const u=k.nearest(sp,v3(0,y,0));
    const from=k.point(sp,u);
    const ctrl=stepped(from,v3(sd*0.8,0.35,0.45),0.09,v3(0,0,0.06));
    const id=k.branch(sp,u,&ctrl,.{.after=.passing});
    try limbTube(b,&k,id,.{.ctrl=ctrl,.r0=0.014,.tip=0.8,.tier=0,.flare=true});
    sd=-sd;
  }
  try dig(b,&k,sp,end);
  k.finish(b);
  b.xform(first,m.scale3(v3(1,1/len,1)));
}
/// the runner from `surf` along spline `sp` to its node: a pale coral tube
/// swelling as it surfaces, thinning toward where it digs in
fn runner(b:*mg.Builder,k:*growth.Skeleton,sp:growth.Id,surf:f32)Allocator.Error!void{
  // its rings: where, how far along, how thick, what colour
  const n=40;
  var pts:[n]V3=undefined;
  var ts:[n]f32=undefined;
  var rs:[n]f32=undefined;
  var cs:[n]Rgba8=undefined;
  k.path(sp,surf,1,&pts);
  for(&ts,&rs,&cs,0..)|*t,*r,*c,i|{
    // how far along the runner this ring is (0..1)
    const f=m.ratio(i,n-1);
    t.*=f;
    r.*=runR*(0.6+0.4*m.smooth(m.clamp01(f/0.12)))*(1-0.45*f);
    c.*=color.mix(bone,tipCol,0.3+0.5*f);
  }
  // where the runner's vertices begin
  const s=b.mark();
  try b.tubeC(&pts,&ts,&rs,&cs,null,coralPart,6);
  try creep(b,k,s,sp);
}
/// the cracks over its first stretch, `from`..`to` along +Y: a zigzag
/// line in the ground, three shorter cracks branching off it
fn cracks(b:*mg.Builder,k:*growth.Skeleton,sp:growth.Id,from:f32,to:f32,rng:*Rng)Allocator.Error!void{
  // how many kinks the line has, and where each is
  const n=@min(m.maxSpline,@max(4,m.floorTo(usize,(to-from)/0.045)));
  var p:[m.maxSpline]V3=undefined;
  // how far off the line it has wandered, a step at a time, drawn back toward it
  var off:f32=0;
  for(p[0..n],0..)|*q,i|{
    off=off*0.5+rng.range(-0.018,0.018);
    q.*=v3(off,m.lerp(from,to,m.ratio(i,n-1))+rng.range(-0.01,0.01)*(if(i==0 or i==n-1)@as(f32,0)else 1),0);
  }
  try fissure(b,k,sp,p[0..n],0.024);
  for([_]f32{0.3,0.55,0.8},[_]f32{1,-1,1})|f,sd|{
    // where the branch leaves the line, which way, and how long
    const at=p[m.floorTo(usize,f*m.f(n-1))];
    const dir=m.norm(v3(sd*0.8,0.6,0));
    const l=rng.range(0.05,0.09);
    // its kinks
    var q:[5]V3=undefined;
    for(&q,0..)|*e,i|e.*=at+dir*m.splat3(l*m.ratio(i,4))+v3(if(i%2==0)0 else 0.005*sd,0,0);
    try fissure(b,k,sp,&q,0.015);
  }
}
/// one crack along the points `p` in the ground, `w` wide: its dark lips
/// pressed flat into the ground, the glow of the tendril under it showing
/// through a seam down its middle; narrowing to a point at both ends
fn fissure(b:*mg.Builder,k:*growth.Skeleton,sp:growth.Id,p:[]const V3,w:f32)Allocator.Error!void{
  // each kink's place along it, the lips' width there, the seam's, and their colours
  var ts:[m.maxSpline]f32=undefined;
  var rs:[m.maxSpline]f32=undefined;
  var ss:[m.maxSpline]f32=undefined;
  var lc:[m.maxSpline]Rgba8=undefined;
  var sc:[m.maxSpline]Rgba8=undefined;
  for(0..p.len)|i|{
    // how far along the crack this kink is (0..1)
    const f=m.ratio(i,p.len-1);
    ts[i]=f;
    rs[i]=w*@max(@sqrt(@sin(m.pi*f)),0.05);
    ss[i]=rs[i]*0.28;
    lc[i]=lipCol;
    sc[i]=seamCol;
  }
  // where the crack's vertices begin: its lips, pressed flat
  const s=b.mark();
  try b.tubeC(p,ts[0..p.len],rs[0..p.len],lc[0..p.len],null,.stem,6);
  b.xform(s,m.chain(&.{m.translate(v3(0,0,0.006)),m.scale3(v3(1,1,0.22))}));
  // its seam, a little proud of them
  const seam=b.mark();
  try b.tubeC(p,ts[0..p.len],ss[0..p.len],sc[0..p.len],null,.bloom,5);
  b.xform(seam,m.chain(&.{m.translate(v3(0,0,0.009)),m.scale3(v3(1,1,0.5))}));
  try k.along(b,s,sp);
}
/// where it digs into its node at `end`: five rootlets clawing down round
/// it and a last cluster of crystals over them
fn dig(b:*mg.Builder,k:*growth.Skeleton,sp:growth.Id,end:f32)Allocator.Error!void{
  // where it goes in
  const at=k.point(sp,0.97);
  for(0..pk.fold)|i|{
    // this rootlet's bearing round it, and the way it reaches out
    const a=m.ratio(i,pk.fold)*m.tau;
    const out=v3(@cos(a),@sin(a)*0.8,0);
    // the rootlet's control points, reaching out and clawing down
    var g:[5]V3=undefined;
    for(&g,0..)|*p,j|{
      // how far along the rootlet this point is (0..1)
      const f=m.ratio(j,4);
      p.*=at+out*m.splat3(0.07*@sin(f*1.4))+v3(0,0.03*f,-0.06*f*f);
    }
    // the rootlet's own branch, off the runner's end
    const id=k.branch(sp,0.97,&g,.{});
    try k.tube(b,id,.{.r0=0.008,.tip=0.12,.col=pk.pearl,.part=.tendril,.sides=4,.t0=0.2,.t1=0.25});
  }
  // the crystals over where it digs in
  const u=k.nearest(sp,v3(0,end-0.12,0));
  try cluster(b,k,sp,u,k.point(sp,u)+v3(0,0,runR*0.5),m.norm(v3(0,0.3,1)),lie,0.05);
}
