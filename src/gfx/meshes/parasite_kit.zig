//! the parasitic lineage's body, shared by its plants (`plant`, the
//! `coil` form) and its structures: alien, not hostile, and plainly a
//! deviation from the symbiotes. A symbiote winds its strands tight round
//! its core, each a little different from the next; a parasite's strands
//! come up woven the same way (both ways at once), then part from the core
//! into an open lattice cage (`lattice`), pearl beads where they cross, the
//! core thinned inside it and sacs of thin-film sap hanging on it in plain
//! view (`organs`), and gather to it again. And it is too exact: all of it
//! comes in fives (`fold`), turned evenly and grown alike (one seed for
//! every frond of a crown), never by a golden angle; and it repeats
//! itself, each frond ending in a small cage of its own crowned in turn
//! (`pod`). A pale pearl skin, lilac fronds, a bulbous foot half sunk in
//! the soil, pale roots. On a structure every piece grows on its growth
//! splines (gfx/growth.zig); a plant grows by tu.x and its cage parts as
//! it matures (plant.vert: tu.y how far each strand has parted).
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// checks a lattice's arrays agree in length
const assert=std.debug.assert;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, splines, angles
const m=engine.core.math;
/// the mesh builder and its primitives
const mg=lib.meshgen;
/// colour conversions, for paling strands to pearl
const color=engine.core.color;
/// the garden's growth timing: skeletons, splines, branches
const growth=lib.growth;
/// the vertex layout: the part role each piece is drawn as
const vertex=lib.vertex;
/// the species registry, whose genomes shape a coil plant
const species=lib.species;
/// the engine's deterministic random stream
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// a vertex colour: four bytes, red, green, blue and alpha
const Rgba8=color.Rgba8;
/// the lineage's colours: its skin, a pale lavender grey
pub const skin=color.rgb(0.56,0.54,0.62).toRgba8(255);
/// the core showing between its strands, darker
pub const core=color.rgb(0.39,0.37,0.45).toRgba8(255);
/// pearl, where it is youngest and where its strands cross
pub const pearl=color.rgb(0.78,0.74,0.84).toRgba8(255);
/// its fronds: lilac
pub const lilac=color.rgb(0.68,0.62,0.82).toRgba8(255);
/// its sap: a cool thin-film blue
pub const sac=color.rgb(0.46,0.62,0.86).toRgba8(255);
/// how many of everything it grows, turned evenly
pub const fold:u32=5;
/// the turn its strands make along a stalk, each way (radians)
pub const twist:f32=1.6*m.pi;
/// a plain weave of it (a nerve) is wound by something alive, but tighter
/// than a symbiote's
pub const wobble:f32=0.05;
/// points a lattice may have along it
const max=m.maxSpline;
/// a lattice's cross-section at one point along it
pub const Section=struct{
  /// the core's radius
  core:f32,
  /// the radius its strands lie at woven tight
  tight:f32,
  /// the radius they have parted to (never less than `tight`)
  open:f32,
  /// a strand's own radius
  strand:f32
};
/// how far a section has parted: 0 woven tight .. toward 1 far off its core
pub fn parting(s:Section)f32{return if(s.open>m.eps)1-s.tight/s.open else 0;}
/// how a lattice is woven: its strands, their turn and girth, its beads
/// and colours
pub const Lattice=struct{
  /// strands each way
  n:u32=fold,
  /// the turn each makes along it (radians)
  twist:f32=twist,
  /// sides round each strand's tube
  sides:u32=4,
  /// pearl beads where its strands cross, a multiple of a strand's radius
  /// (0: none), only where parted at least `nodeFrom`
  node:f32=1.9,
  /// how far parted (0..1) the lattice must be before beads appear
  nodeFrom:f32=0.3,
  /// the part role it is drawn as
  part:vertex.Part=.stem,
  /// the core's colour
  core:Rgba8=core,
  /// the strands' colour where woven tight
  strand:Rgba8=skin,
  /// the beads' colour, which the strands pale toward as they part
  bead:Rgba8=pearl,
};
/// the lattice along `spine` (tu.x `ts`, cross-sections `sec`): a core,
/// and `l.n` strands wound each way round it at exactly even turns, lying
/// in it where woven and lifting off it into a cage where parted, paling to
/// pearl as they go; a bead where two cross once parted. Each strand's tu.y
/// is how far it has parted there (`parting`).
pub fn lattice(b:*mg.Builder,spine:[]const V3,ts:[]const f32,sec:[]const Section,l:Lattice)Allocator.Error!void{
  // points along it
  const n=spine.len;
  assert(n>=2 and n<=max and ts.len==n and sec.len==n);
  // a twist-free frame along the spine: its normals and binormals
  var frameNormal:[max]V3=undefined;
  var fb:[max]V3=undefined;
  mg.transport(spine,frameNormal[0..n],fb[0..n]);
  // radii along it: first the core's, then reused for the strands'
  var rs:[max]f32=undefined;
  for(rs[0..n],sec)|*r,s|r.*=s.core;
  try b.tubeR(spine,ts,rs[0..n],l.core,l.part,8);
  // each strand point's parting (its tu.y) and colour
  var us:[max]f32=undefined;
  var cs:[max]Rgba8=undefined;
  for(rs[0..n],us[0..n],cs[0..n],sec)|*r,*u,*c,s|{
    r.*=s.strand;
    u.*=parting(s);
    c.*=color.mix(l.strand,l.bead,u.* * 0.6);
  }
  // one strand's path, laid round the spine
  var path:[max]V3=undefined;
  for([_]f32{1,-1})|way|for(0..l.n)|si|{
    for(path[0..n],0..)|*p,i|p.*=round(spine[i],frameNormal[i],fb[i],strandAngle(l,si,way,m.ratio(i,n-1)),sec[i].open);
    try b.tubeC(path[0..n],ts,rs[0..n],cs[0..n],us[0..n],l.part,l.sides);
  };
  // decision: beads are left out at the coarsest level of detail, where
  // they are under a pixel
  if(l.node<=0 or b.lod+1>=mg.lods)return;
  // strand i one way meets one the other way wherever twice its turn is a
  // whole share of the circle: every pi / (n twist) along it, n at a time
  const every=m.pi/(m.f(l.n)*l.twist);
  // which crossing row, counting up from the foot
  var k:u32=1;
  while(m.f(k)*every<1):(k+=1){
    // how far along the crossing row lies (0..1), and that as a point index
    const u=m.f(k)*every;
    const x=u*m.f(n-1);
    // the points either side of it, and how far between them
    const lo=m.floorTo(usize,x);
    const hi=@min(lo+1,n-1);
    const f=x-m.f(lo);
    // the cross-section there, blended between the two
    const s:Section=.{
      .core=m.lerp(sec[lo].core,sec[hi].core,f),.tight=m.lerp(sec[lo].tight,sec[hi].tight,f),
      .open=m.lerp(sec[lo].open,sec[hi].open,f),.strand=m.lerp(sec[lo].strand,sec[hi].strand,f),
    };
    // how far parted it is there
    const pt=parting(s);
    if(pt<l.nodeFrom)continue;
    // the spine point and frame there
    const at=m.lerpV(spine[lo],spine[hi],f);
    const nv=m.norm(m.lerpV(frameNormal[lo],frameNormal[hi],f));
    const bv=m.norm(m.lerpV(fb[lo],fb[hi],f));
    for(0..l.n)|si|{
      // where this bead's vertices begin
      const mk=b.mark();
      try mg.ellipsoid(b,.{
        .center=round(at,nv,bv,strandAngle(l,si,1,u),s.open),.radii=m.splat3(s.strand*l.node),
        .col=l.bead,.part=l.part,.rings=4,.segs=6,.t=m.lerp(ts[lo],ts[hi],f),
      });
      for(b.v.items[mk..])|*vx|vx.tu[1]=pt;
    }
  }
}
/// the bearing (radians) of strand `si`, wound `way` (1 or -1), at `u`
/// along the lattice (0..1)
fn strandAngle(l:Lattice,si:usize,way:f32,u:f32)f32{return m.ratio(si,l.n)*m.tau+way*l.twist*u;}
/// the point `r` out from `at` at bearing `a`, in the frame `nv`, `bv`
fn round(at:V3,nv:V3,bv:V3,a:f32,r:f32)V3{return at+(nv*m.splat3(@cos(a))+bv*m.splat3(@sin(a)))*m.splat3(r);}
/// a stalk's shape: woven tight at its foot, parting into a cage over
/// `from..to` of it and gathering again above
pub const Stalk=struct{
  /// its radius at its middle, as a braid's
  girth:f32,
  /// how far its strands part where they part most, a multiple of the
  /// radius they are woven at (0: a plain weave)
  part:f32=2.6,
  /// where along it (0..1) the cage starts to open
  from:f32=0.15,
  /// where along it (0..1) the cage has gathered again
  to:f32=0.85,
  /// how hard it swells into its foot
  foot:f32=0.9,
  /// the turn its strands make along it (radians)
  twist:f32=twist,
  /// sides round each strand's tube
  sides:u32=4,
  /// its beads where strands cross, a multiple of a strand's radius (0: none)
  node:f32=1.9,
};
/// how far a stalk's cage has opened at `u` (0 woven .. 1 widest): eased
/// both ways, so its strands leave the core and gather to it with no kink
pub fn parted(s:Stalk,u:f32)f32{
  if(u<=s.from or u>=s.to)return 0;
  // a cosine over the cage's stretch, raised to soften both ends
  const c=@cos(m.pi*(u-s.from)/(s.to-s.from));
  return 1-c*c*c*c;
}
/// a stalk's cross-section at `u` along it: woven as a braid is (the same
/// core and strands), its core thinning to a filament where the cage opens
pub fn section(s:Stalk,u:f32)Section{
  // how near the foot (1 at the ground), and the girth there, swelling into it
  const low=1-u;
  const g=s.girth*m.lerp(1.15,0.75,u)*(1+s.foot*low*low*low*low*low);
  // how far the cage has opened, and where the strands lie woven tight
  const w=parted(s,u);
  const tight=g*mg.braidOff;
  return.{.core=g*mg.braidCore*(1-0.65*w),.tight=tight,.open=tight*(1+s.part*w),.strand=g*mg.braidStrand*(1-0.3*w)};
}
/// the stalk along spline `id`, grown along it
pub fn stalk(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,s:Stalk)Allocator.Error!void{
  // its points, growth stamps and cross-sections along the spline
  var sp:[growth.res]V3=undefined;
  var ts:[growth.res]f32=undefined;
  var sec:[growth.res]Section=undefined;
  k.path(id,0,1,&sp);
  for(&ts,&sec,0..)|*t,*c,i|{
    // how far up the stalk, 0..1
    const u=m.ratio(i,growth.res-1);
    t.*=u*0.85;
    c.*=section(s,u);
  }
  // where the lattice's vertices begin
  const mk=b.mark();
  try lattice(b,&sp,&ts,&sec,.{.twist=s.twist,.sides=s.sides,.node=s.node});
  try k.along(b,mk,id);
}
/// where one sac hangs in a stalk's cage and how big it is
const Organ=struct{
  /// how far along the stalk it hangs, 0..1
  u:f32,
  /// its radius
  r:f32
};
/// where the `i`th of `n` sacs hangs in a stalk `len` long, and how big:
/// evenly over where it is parted, each filling `fill` of the cage there,
/// never touching the next
fn organ(s:Stalk,len:f32,i:usize,n:u32,fill:f32)Organ{
  // how far along it hangs, and the cross-section there
  const u=m.lerp(s.from,s.to,(m.f(i)+0.5)/m.f(n));
  const c=section(s,u);
  // the length of stalk each sac has to itself
  const gap=(s.to-s.from)/m.f(n)*len;
  return.{.u=u,.r=@min((c.open-c.strand)*fill,gap*0.42)};
}
/// `n` sacs of thin-film sap threaded on the core inside a stalk's cage
/// (spline `id`), swelling once its front reaches each
pub fn organs(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,s:Stalk,n:u32,fill:f32)Allocator.Error!void{
  for(0..n)|i|{
    // where this sac hangs and how big it is
    const o=organ(s,k.get(id).len,i,n,fill);
    try bladder(b,k,id,o.u,k.point(id,o.u),v3(o.r,o.r*1.15,o.r),o.u,.{});
  }
}
/// the bulbous foot at `at`, half sunk in the soil, swelling out of the
/// stalk's root as it starts
pub fn foot(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,at:V3,radii:V3)Allocator.Error!void{
  // where the foot's vertices begin
  const s=b.mark();
  try nodule(b,at,radii,0,skin,core,pearl);
  try k.on(b,s,id,0,.{.from=at,.span=k.get(id).time*0.3});
}
/// a bulb of the lineage's skin at `at`: pearl where it swells toward the
/// light, its core showing dark underneath, so it reads round however
/// pale (a smooth field of its normal, so shared vertices match)
pub fn nodule(b:*mg.Builder,at:V3,radii:V3,t:f32,sk:Rgba8,dark:Rgba8,light:Rgba8)Allocator.Error!void{
  // where the bulb's vertices begin
  const s=b.mark();
  try mg.ellipsoid(b,.{.center=at,.radii=radii,.col=sk,.rings=9,.segs=14,.t=t});
  for(b.v.items[s..])|*vx|{
    // how much this vertex faces up, 0 straight down .. 1 straight up
    const up=m.clamp01(0.5+0.5*vx.nrm[1]);
    vx.col=if(up>0.5)color.mix(sk,light,(up-0.5)*2)else color.mix(dark,sk,up*2);
  }
}
/// the `i`th of `n` roots out of a foot, reaching `reach`: out low over the
/// ground, then down into it, every one alike; fills `c`
fn rootPath(i:usize,n:u32,reach:f32,seed:u64,c:*[6]V3)void{
  // its bearing, the flat way out along it, and where it leaves the foot
  const a=m.ratio(i,n)*m.tau;
  const out=v3(@cos(a),0,@sin(a));
  const from=out*m.splat3(0.05)+v3(0,0.03,0);
  for(c,0..)|*p,j|{
    // how far out along the root, 0..1
    const f=m.ratio(j,5);
    p.*=from+out*m.splat3(reach*f)+v3(0,0.03*@sin(m.pi*f*0.8)-0.09*f*f,0);
  }
  mg.grow(c,.{.start=from,.direction=out,.length=reach,.wobble=0.3,.seed=seed});
}
/// `n` pale roots out of the foot, reaching `reach` and sinking into the
/// ground, `r` thick at their roots, each a branch growing with the stalk
pub fn roots(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,n:u32,reach:f32,r:f32,seed:u64)Allocator.Error!void{
  for(0..n)|i|{
    // its control points, and its branch on the skeleton
    var c:[6]V3=undefined;
    rootPath(i,n,reach,seed,&c);
    const root=k.branch(id,0,&c,.{.after=.with});
    try k.tube(b,root,.{.r0=r,.tip=0.1,.col=pearl,.part=.tendril,.sides=5,.t0=0,.t1=0.1});
  }
}
/// a translucent bladder of thin-film sap (part `.bloom`: the instance's
/// `fade` makes it see-through) at `center`, swelling out of spline `id`
/// at `u` once its front reaches it
pub fn bladder(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,u:f32,center:V3,radii:V3,t:f32,o:growth.Skeleton.On)Allocator.Error!void{
  // where the bladder's vertices begin
  const s=b.mark();
  try mg.ellipsoid(b,.{.center=center,.radii=radii,.col=sac,.part=.bloom,.rings=8,.segs=12,.t=t});
  // how it grows on the spline: swelling from the spline's point if not told
  var on=o;
  if(on.from==null)on.from=k.point(id,u);
  try k.on(b,s,id,u,on);
}
/// a frond's control points from `from` out along `out` (horizontal, unit):
/// its heading starts at `rise` and turns ever faster (by `curl` at its tip;
/// negative turns it up), so it rises and arcs, never quite smooth. One
/// seed for a crown's fronds makes them alike, turned
pub fn frondPath(from:V3,out:V3,len:f32,rise:f32,curl:f32,seed:u64,pts:[]V3)void{
  // how many points it fills
  const n=pts.len;
  pts[0]=from;
  for(1..n)|j|{
    // how far along, its heading there (radians up from level), and the step
    const s=m.ratio(j,n-1);
    const heading=rise-s*s*curl;
    const step=len/m.f(n-1)*(1-0.55*s);
    pts[j]=pts[j-1]+(out*m.splat3(@cos(heading))+v3(0,@sin(heading),0))*m.splat3(step);
  }
  mg.grow(pts,.{.start=from,.direction=m.norm(pts[n-1]-from),.length=len,.wobble=0.08,.seed=seed});
}
/// how one frond grows: which way, how long and thick, how it rises and curls
pub const Frond=struct{
  /// the flat way out it heads (unit)
  out:V3,
  /// its length
  len:f32,
  /// its radius at its root
  r:f32,
  /// the heading it starts at (radians up from level)
  rise:f32=1.25,
  /// how far its heading turns down by its tip (negative: up)
  curl:f32=5.2,
  /// its radius at its tip, a share of `r`
  tip:f32=0.12,
  /// the growth stamp at its root (it grows to 1 at its tip)
  t0:f32=0.6,
  /// its wander
  seed:u64,
  /// how its branch grows on the skeleton
  grow:growth.Branch=.{},
};
/// a frond off spline `parent` at `u`, grown along its own spline, tapering
/// to its tip; returns its spline
pub fn frond(b:*mg.Builder,k:*growth.Skeleton,parent:growth.Id,u:f32,f:Frond)Allocator.Error!growth.Id{
  // its control points
  var c:[10]V3=undefined;
  frondPath(k.point(parent,u),f.out,f.len,f.rise,f.curl,f.seed,&c);
  // its branch on the skeleton
  const id=k.branch(parent,u,&c,f.grow);
  try k.tube(b,id,.{.r0=f.r,.tip=f.tip,.col=lilac,.part=.tendril,.sides=5,.t0=f.t0,.t1=1});
  return id;
}
/// a crown: `fold` fronds alike, turned evenly from `spin`
pub const Crown=struct{
  /// the bearing of the first frond (radians)
  spin:f32=0,
  /// each frond's length
  len:f32,
  /// each frond's radius at its root
  r:f32,
  /// the heading each starts at (radians up from level)
  rise:f32=0.4,
  /// how far each turns by its tip (negative: up)
  curl:f32=-1.1,
  /// the growth stamp at their roots
  t0:f32=0.6,
  /// one wander shared by every frond, so they grow alike
  seed:u64,
  /// how their branches grow on the skeleton
  grow:growth.Branch=.{},
  /// each frond ends in a `pod` this long (0: tapering to a point)
  pod:f32=0,
};
/// a crown off spline `parent` at `u`, every frond growing at once
pub fn crown(b:*mg.Builder,k:*growth.Skeleton,parent:growth.Id,u:f32,c:Crown)Allocator.Error!void{
  // the girth of the pods they end in
  const girth=podGirth(c.pod);
  for(0..fold)|i|{
    // this frond's bearing
    const a=c.spin+m.ratio(i,fold)*m.tau;
    // the frond, its tip narrowed to meet its pod's foot
    const id=try frond(b,k,parent,u,.{
      .out=v3(@cos(a),0,@sin(a)),.len=c.len,.r=c.r,.rise=c.rise,.curl=c.curl,
      .tip=if(c.pod>0)@min(1,podFoot(girth)/c.r)else 0.12,.t0=c.t0,.seed=c.seed,.grow=c.grow,
    });
    if(c.pod>0)_=try pod(b,k,id,.{.len=c.pod,.girth=girth,.seed=c.seed});
  }
}
/// how a pod is made: its size, its growth stamp, its colours
pub const Pod=struct{
  /// its length along its axis
  len:f32,
  /// as a stalk's
  girth:f32,
  /// its growth stamp, the same all over
  t:f32=1,
  /// the part role its lattice and frondlets are drawn as
  part:vertex.Part=.tendril,
  /// its strands' colour
  skin:Rgba8=skin,
  /// its core's colour
  core:Rgba8=core,
  /// its beads' and crown's colour
  pearl:Rgba8=pearl,
  /// its frondlets' colour
  frond:Rgba8=lilac,
  /// its sac's colour
  sac:Rgba8=sac,
  /// its frondlets' wander
  seed:u64,
};
/// a pod's girth for its length
pub fn podGirth(len:f32)f32{return len*0.085;}
/// how wide a pod of `girth` is at its foot (where the frond it ends meets it)
pub fn podFoot(girth:f32)f32{return girth*1.15*(mg.braidOff+mg.braidStrand);}
/// the lineage's body again, small, from `at` along `axis`: its strands
/// woven at its foot, parting round a sac of sap and gathering at its
/// crown into a pearl bead, out of which `fold` frondlets spring alike,
/// rising, arcing out and curling down softly, tapering to points
pub fn podAt(b:*mg.Builder,at:V3,axis:V3,p:Pod)Allocator.Error!void{
  // points along it, and its stalk shape: caged all along, no beads
  const steps=9;
  const s:Stalk=.{.girth=p.girth,.part=2.2,.from=0,.to=1,.foot=0,.twist=m.pi,.sides=3,.node=0};
  // its points, growth stamps and cross-sections
  var sp:[steps]V3=undefined;
  var ts:[steps]f32=undefined;
  var sec:[steps]Section=undefined;
  for(&sp,&ts,&sec,0..)|*q,*t,*c,i|{
    // how far along the pod, 0..1
    const u=m.ratio(i,steps-1);
    q.*=at+axis*m.splat3(p.len*u);
    t.*=p.t;
    c.*=section(s,u);
  }
  try lattice(b,&sp,&ts,&sec,.{.twist=s.twist,.sides=s.sides,.node=0,.part=p.part,.core=p.core,.strand=p.skin,.bead=p.pearl});
  // the cage's middle section, and the sac's radius filling it
  const mid=section(s,0.5);
  const r=(mid.open-mid.strand)*0.6;
  try mg.ellipsoid(b,.{.center=at+axis*m.splat3(p.len*0.5),.radii=v3(r,r*1.15,r),.col=p.sac,.part=.bloom,.rings=5,.segs=8,.t=p.t});
  // its crown, where the bead sits
  const top=sp[steps-1];
  try mg.ellipsoid(b,.{.center=top,.radii=m.splat3(p.girth),.col=p.pearl,.part=p.part,.rings=4,.segs=6,.t=p.t});
  // decision: frondlets only at full detail; past the first detail step
  // (`mg.lodAt`) they are under a pixel
  if(b.lod>0)return;
  // they rise the way the pod points, laid out in a frame turned with it
  // about the vertical (so the pods of a crown stay alike, turned)
  const side=if(@abs(axis[1])<m.nearParallel)m.norm(m.cross(axis,v3(0,1,0)))else v3(1,0,0);
  const fwd=m.cross(side,axis);
  for(0..fold)|i|{
    // this frondlet's bearing, and its control points (laid out upright first)
    const a=m.ratio(i,fold)*m.tau;
    var c:[6]V3=undefined;
    frondPath(v3(0,0,0),v3(@cos(a),0,@sin(a)),p.len*0.55,0.9,2.6,p.seed^0x90D,&c);
    for(&c)|*q|q.*=top+side*m.splat3(q[0])+axis*m.splat3(q[1])+fwd*m.splat3(q[2]);
    try frondTube(b,&c,p.girth*0.45,0.05,p.t,p.t,p.frond,p.part,3);
  }
}
/// a pod at the tip of frond `id`, the way it ends, grown along a spline of
/// its own once the frond is done; returns that spline
pub fn pod(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,p:Pod)Allocator.Error!growth.Id{
  // the frond's tip and the way it points there
  const at=k.point(id,1);
  const ax=k.tangent(id,1);
  // the pod's own short spline on the skeleton
  const pid=k.branch(id,1,&.{at,at+ax*m.splat3(p.len*0.5),at+ax*m.splat3(p.len)},.{});
  // where the pod's vertices begin
  const mk=b.mark();
  try podAt(b,at,ax,p);
  try k.along(b,mk,pid);
  return pid;
}
/// a tube through control points `c` (resampled smooth), `r` at its root
/// tapering to `tip` of it, tu.x `t0`..`t1`
fn frondTube(b:*mg.Builder,c:[]const V3,r:f32,tip:f32,t0:f32,t1:f32,col:Rgba8,part:vertex.Part,sides:u32)Allocator.Error!void{
  // points along it, and the tube resampled smooth
  const steps=14;
  var path:[steps]V3=undefined;
  m.splineResample(c,&path);
  // each point's growth stamp and radius
  var ts:[steps]f32=undefined;
  var rs:[steps]f32=undefined;
  for(&ts,&rs,0..)|*t,*q,j|{
    // how far along, 0..1
    const f=m.ratio(j,steps-1);
    t.*=m.lerp(t0,t1,f);
    q.*=r*m.lerp(1,tip,f);
  }
  try b.tubeR(&path,&ts,&rs,col,part,sides);
}
/// a parasite plant (the `coil` form), from its genome: upright and exactly
/// symmetric, its variants differing in proportion alone. A bulbous foot
/// half sunk in the soil and `fold` pale roots; the stalk woven tight out
/// of it, parting into a tall cage with its sacs (`thorns` of them) on the
/// core inside, gathering at its neck round a bulb of sap; and a crown of
/// `fold` fronds rising like a candelabrum, each ending in a pod crowned in
/// turn. tu.x is height (the crown 0.85..1); plant.vert parts the cage
/// (tu.y) and opens the crown as it matures.
pub fn plant(b:*mg.Builder,g:species.Genome,seed:u64)Allocator.Error!void{
  // the plant's own random stream
  var rng=Rng.init(seed);
  // its skin, the darker core, and the pearl light it pales to
  const sk=g.stemCol.toRgba8(255);
  const dark=color.shade(g.stemCol,0.7);
  const light=color.mix(sk,color.rgb(1,0.97,1).toRgba8(255),0.45);
  // its fronds' colour, and its sap's
  const frondC=g.leafCol.toRgba8(255);
  const sap=g.bloomCol.toRgba8(255);
  // its height, and its stalk's shape
  const h=g.stemH*rng.range(0.9,1.1);
  const s:Stalk=.{.girth=g.stemR,.part=rng.range(2.6,3.2),.from=0.12,.to=rng.range(0.74,0.82)};
  // the stalk, dead upright
  const steps=25;
  // its points, growth stamps and cross-sections
  var sp:[steps]V3=undefined;
  var ts:[steps]f32=undefined;
  var sec:[steps]Section=undefined;
  for(&sp,&ts,&sec,0..)|*q,*t,*c,i|{
    // how far up the stalk, 0..1
    const u=m.ratio(i,steps-1);
    q.*=v3(0,h*u,0);
    t.*=u*0.85;
    c.*=section(s,u);
  }
  try lattice(b,&sp,&ts,&sec,.{.core=dark,.strand=sk,.bead=light});
  try nodule(b,v3(0,g.stemR*0.3,0),v3(g.stemR*2.4,g.stemR*1.2,g.stemR*2.4),0,sk,dark,light);
  for(0..fold)|i|{
    // this root's control points
    var c:[6]V3=undefined;
    rootPath(i,fold,g.stemR*4.5,seed^0x2007,&c);
    try frondTube(b,&c,g.stemR*0.45,0.1,0,0.03,light,.stem,4);
  }
  // its sacs, on the core inside the cage: its yield ripens in them, a
  // pod a sac (as many as it has pods)
  for(0..g.thorns)|i|{
    // where this sac hangs and how big it is, and where its vertices begin
    const o=organ(s,h,i,g.thorns,0.6);
    const at=b.mark();
    try mg.ellipsoid(b,.{.center=v3(0,h*o.u,0),.radii=v3(o.r,o.r*1.15,o.r),.col=sap,.part=.bloom,.rings=6,.segs=9,.t=o.u*0.85});
    if(i<g.pods)mg.pods.mark(b,at,i,g.pods,o.r*1.05);
  }
  // a bulb at its neck, the crown springing round it
  const neck=sp[steps-1];
  try mg.ellipsoid(b,.{
    .center=neck+v3(0,g.bloomR*0.45,0),.radii=v3(g.bloomR*0.8,g.bloomR,g.bloomR*0.8),
    .col=sap,.part=.bloom,.rings=7,.segs=9,.t=1,
  });
  // the pods' length and girth, and the fronds' radius at their roots
  const plen=h*0.2;
  const girth=podGirth(plen);
  const r=g.stemR*0.45;
  // one wander shared by every frond and pod, so they grow alike
  const frondSeed=seed^0xF20D;
  for(0..g.tendrils)|i|{
    // this frond's bearing, and its control points
    const a=m.ratio(i,g.tendrils)*m.tau;
    var c:[10]V3=undefined;
    frondPath(neck,v3(@cos(a),0,@sin(a)),h*0.55,0.35,-1.15,frondSeed,&c);
    try frondTube(b,&c,r,@min(1,podFoot(girth)/r),0.85,1,frondC,.tendril,5);
    // the way the frond points at its tip, which the pod carries on
    const ax=m.norm(c[9]-c[8]);
    try podAt(b,c[9],ax,.{.len=plen,.girth=girth,.skin=sk,.core=dark,.pearl=light,.frond=frondC,.sac=sap,.seed=frondSeed});
  }
}
