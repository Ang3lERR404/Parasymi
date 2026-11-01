//! mesh: CONDUIT. a living root that digs up out of the soil near its
//! tile's back edge, arches over the tile and digs back in near its front
//! edge (+X, "forward"); the next conduit's root comes up where this one
//! went down, so a chain is joined under the ground whichever way it turns.
//! A core of sapwood (part `.core`: essence carried through it swells and
//! tints it as it passes, part.vert) wound tight in a weave of smaller
//! roots running over and under each other; branchlets peel off the weave
//! and rejoin it, and leaves sit over the top in twos and threes, swept
//! forward the way it carries, as weed combs out downstream. Soil is heaped
//! where it breaks the ground, rootlets reaching into it.
//! `left`/`right`: the same root turning in from the tile's +Z / -Z edge.
//! It grows along a growth spline (gfx/growth.zig) through its spine: up
//! out of the soil at its back edge (where the root behind went down),
//! over, and down in at its front.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, noise, rng, the builder underneath
const engine=lib.engine;
/// all the maths: vectors, matrices, splines
const m=engine.core.math;
/// the plant-piece mesher: tubes, blades, frames, the builder itself
const mg=lib.meshgen;
/// the garden's palette: sapwood, root bark, leaves and soil
const pal=lib.palette;
/// colour conversions, for mixing the core's grain and the strands' tones
const color=engine.core.color;
/// smooth noise, for the core's knots and grain
const noise=engine.core.noise;
/// the vertex layout, whose part roles name how a piece is shaded
const vertex=lib.vertex;
/// the seeded random stream each arch's jitter, leaves and clods come from
const Rng=engine.core.rng.Rng;
/// the structure kit: the rootlets reaching into the soil
const kit=lib.structureKit;
/// the garden's growth timing: the spline the root grows along
const growth=lib.growth;
/// a point or direction in space
const V3=m.V3;
/// makes a point in space from three numbers
const v3=m.v3;
/// how many rings run along the root
const res=48;
/// how many control points its spine's spline runs through
pub const ctrlCount=11;
/// how high its arch stands over the ground (tiles)
/// it rises long and dives short, its peak leaned back from the middle:
/// the way it carries
pub const peak:f32=0.23;
/// how deep its ends lie under the tile's edges
const depth:f32=0.12;
/// how far the peak leans back from the middle (0 none, 1 a lot)
const skew:f32=0.4;
/// how far a straight one wanders sideways over its tile
const meander:f32=0.06;
/// the core's radius, which the weave and soil scale by
const coreRadius:f32=0.036;
/// the core flares where it breaks the ground
pub const flareAmount:f32=0.25;
/// the weave: how thick each strand is
/// (the strand counts and turns are the `Arch`'s own)
const strandR:f32=0.011;
/// how far out a strand rides off the core, as a share of its own girth
const sinkAmount:f32=0.35;
/// how far over and under the strands pass each other, as a share of their girth
const over:f32=0.75;
/// a branchlet peeling off the weave and rejoining it: its girth
const runnerR:f32=0.008;
/// how far out from the weave a branchlet bows at its middle
const runnerOut:f32=0.04;
/// a leaf's length
const leafLen:f32=0.11;
/// a leaf's width
const leafW:f32=0.04;
/// how far apart a cluster's leaves splay (radians between neighbours)
const leafSplay:f32=0.55;
/// how far up a leaf tilts from flat as it sweeps forward
const leafLift:f32=0.3;
/// how long the twig bearing a cluster is
const twigLen:f32=0.03;
/// the soil it heaps diving in: mounds (how far on, how wide) running on
/// ahead of it, smaller as they go
const ridge=[_]m.Vice(f32,2){.{0.012,0.072},.{0.07,0.058},.{0.12,0.04}};
/// how one arch is laid: where it runs, how high and deep, how thick and
/// how it is wound, leaved and seeded
pub const Arch=struct{
  /// 0 straight across from `from` to `to` (x); ±1 turning in from the
  /// tile's +Z / -Z edge to its front
  turn:f32=0,
  /// where along x it comes up (straight ones only)
  from:f32=-0.5,
  /// where along x it goes down (straight ones only)
  to:f32=0.5,
  /// how high its arch stands over the ground
  peak:f32=peak,
  /// how deep its ends lie under the edges
  depth:f32=depth,
  /// its core's radius
  coreR:f32=coreRadius,
  /// how many strands wind each way round the core (even, so over and
  /// under alternate all the way round)
  strands:u32=4,
  /// how many turns each strand makes along it
  turns:f32=2,
  /// its core's part (none: a braided conduit lays its own cores)
  core:?vertex.Part=.core,
  /// clusters of leaves over its top: how many leaves each
  leaves:[]const u8=&.{2,3,2,3,2},
  /// whether branchlets peel off its weave
  runners:bool=true,
  /// its own seed: the same seed lays the same arch every time
  seed:u64,
};
/// where along its tile (s 0..1) it runs over the ground: returns x and z;
/// a gentle meander when straight, a quarter circle when turning
pub fn plan(a:Arch,s:f32)m.Vice(f32,2){
  if(a.turn==0)return.{m.lerp(a.from,a.to,s),meander*@sin(m.tau*s)*@sin(m.pi*s)};
  // a quarter circle from the side edge's middle to the front edge's
  const t=m.pi+s*m.pi/2;
  return.{0.5+0.5*@cos(t),a.turn*(0.5+0.5*@sin(t))};
}
/// its height over the ground at s: up out of the soil steeply, a round
/// arch leaning back, steeply down again
pub fn height(a:Arch,s:f32)f32{
  // s nudged on, so the peak leans back
  const w=s+skew*s*(1-s);
  // the arch's plain hump at that point, never below zero
  const b=@max(@sin(m.pi*w),0);
  return-a.depth+(a.peak+a.depth)*0.5*(b+@sqrt(b));
}
/// builds a straight conduit across its tile
pub fn build(b:*mg.Builder)Allocator.Error!void{try grown(b,.{.seed=0xC0D});}
/// mesh: CONDUIT LEFT. the same root turning in from the tile's +Z edge
pub const left=struct{
  /// builds the left-turning conduit
  pub fn build(b:*mg.Builder)Allocator.Error!void{try grown(b,.{.turn=1,.seed=0xC1D});}
};
/// mesh: CONDUIT RIGHT. the same root turning in from the tile's -Z edge
pub const right=struct{
  /// builds the right-turning conduit
  pub fn build(b:*mg.Builder)Allocator.Error!void{try grown(b,.{.turn=-1,.seed=0xC2D});}
};
/// one arch on a skeleton of its own: it grows up out of the soil at its
/// back edge, over and down into it at its front.
fn grown(b:*mg.Builder,a:Arch)Allocator.Error!void{
  // the growth skeleton the arch is hung on
  var k=growth.Skeleton.begin(b);
  _=try arch(b,&k,a);
  k.finish(b);
}
/// the control points of an arch's spine (what its growth spline runs
/// through), the same every time for the same arch
pub fn spineCtrl(a:Arch)[ctrlCount]V3{
  // the arch's own seeded rng, so its spine is the same each time
  var rng=Rng.init(a.seed);
  return spineWith(a,&rng);
}
/// lays the spine's control points from the plan and the height, jittered
/// a little by `rng` between the ends, which stay exactly put
fn spineWith(a:Arch,rng:*Rng)[ctrlCount]V3{
  // the control points being laid
  var ctrl:[ctrlCount]V3=undefined;
  for(&ctrl,0..)|*c,i|{
    // how far along the tile this point is (0..1), and where it lies over the ground
    const s=m.ratio(i,ctrlCount-1);
    const xz=plan(a,s);
    // never quite smooth, the ends held where the neighbours' meet them
    const j=0.012*@sin(m.pi*s);
    c.*=v3(xz[0]+j*rng.range(-1,1),height(a,s)+j*rng.range(-0.5,0.5),xz[1]+j*rng.range(-1,1));
  }
  return ctrl;
}
/// the root: its spine (tu.x 0 where it enters .. 1 where it leaves), the
/// spline it grows along on `k` (returned). The core and its weave grow
/// along it as its front digs on; leaves unfold and soil heaps up as the
/// front passes them.
pub fn arch(b:*mg.Builder,k:*growth.Skeleton,a:Arch)Allocator.Error!growth.Id{
  // the arch's seeded rng: spine, leaves and clods all draw from it in turn
  var rng=Rng.init(a.seed);
  // the spine's control points, and the spline the root grows along
  const ctrl=spineWith(a,&rng);
  const spine=k.trunk(&ctrl,.{});
  // where the root's vertices begin, so core and weave grow along the spine
  const start=b.mark();
  // the spine resampled to one point per ring
  var sp:[res]V3=undefined;
  m.splineResample(&ctrl,&sp);
  // the core's growth timing, radius and colour, ring by ring
  var ts:[res]f32=undefined;
  var rs:[res]f32=undefined;
  var cols:[res]color.Rgba8=undefined;
  for(&ts,&rs,&cols,sp,0..)|*t,*r,*c,p,i|{
    // how far along the root this ring is (0..1)
    const u=m.ratio(i,res-1);
    t.*=u;
    // a gentle knotting of the core's girth
    const knot=0.15*noise.grad(a.seed,u*6,0.5);
    // how much it flares here: most where it breaks the ground (y near 0)
    const flare=flareAmount*@exp(-p[1]*p[1]/0.0012);
    r.*=a.coreR*(1+knot+flare);
    c.*=color.mix(pal.sapwoodDark,pal.sapwood,m.clamp01(0.55+2.5*noise.grad(a.seed+%1,u*9,1.5)));
  }
  if(a.core)|part|try b.tubeC(&sp,&ts,&rs,&cols,null,part,8);
  // a twist-free frame along the spine: its normal and its binormal
  var frameNormal:[res]V3=undefined;
  var fb:[res]V3=undefined;
  mg.transport(&sp,&frameNormal,&fb);
  try weave(b,a,&sp,&ts,&rs,&frameNormal,&fb);
  if(a.runners)for([_]m.Vice(f32,2){.{0.2,0.42},.{0.55,0.8}},[_]f32{1,-1})|span,side|try runner(b,&sp,&rs,span,side);
  try k.along(b,start,spine);
  for(a.leaves,0..)|n,ci|{
    // where this cluster sits along the root, spread over its middle
    const u=m.lerp(0.2,0.78,(m.f(ci)+0.5)/m.f(a.leaves.len));
    // where the cluster's vertices begin, so it unfolds as the front passes
    const s=b.mark();
    try cluster(b,&sp,&rs,u,n,if(ci%2==0)1 else-1,&rng);
    try k.on(b,s,spine,u,.{});
  }
  // where it breaks the ground, coming up and going down
  for(1..res)|i|{
    // the heights of two neighbouring rings: the ground lies between if their signs differ
    const y0=sp[i-1][1];
    const y1=sp[i][1];
    if((y0<0)==(y1<0))continue;
    // where it crosses the ground, between the two rings
    const at=m.lerpV(sp[i-1],sp[i],y0/(y0-y1));
    // away from the arch: back where it comes up, on where it goes down
    const away=m.norm(if(y1>y0)sp[i-1]-sp[i]else sp[i]-sp[i-1]);
    // where the soil's vertices begin, so it heaps up as the front passes
    const s=b.mark();
    try ground(b,at,m.norm(v3(away[0],0,away[2])),a.coreR,y1<y0,&rng);
    try k.on(b,s,spine,k.nearest(spine,at),.{.from=at});
  }
  return spine;
}
/// smaller roots wound over and under each other round the core, each set
/// turning its own way. A strand of one set passes outside a strand of the
/// other where they cross when its index and theirs sum even, inside when
/// odd: plain weave, from each strand's own place alone.
fn weave(b:*mg.Builder,a:Arch,sp:[]const V3,ts:[]const f32,rs:[]const f32,frameNormal:[]const V3,fb:[]const V3)Allocator.Error!void{
  // how many strands go each way, and their girth scaled to the core's
  const n=m.f(a.strands);
  const sr=strandR*a.coreR/coreRadius;
  for(0..2)|set|for(0..a.strands)|i|{
    // which way this set winds: one forward, one back
    const sgn:f32=if(set==0)1 else-1;
    // the second set sits halfway between the first
    const shift=if(set==0)m.pi/n else 0;
    // where this strand starts round the core (radians)
    const start=(m.f(i)+0.5*m.f(set))*m.tau/n;
    // whether this strand starts over (1) or under (-1)
    const parity:f32=if(i%2==0)1 else-1;
    // the strand's path and radius along the core
    var path:[res]V3=undefined;
    var r:[res]f32=undefined;
    for(&path,&r,0..)|*q,*rr,j|{
      // how far along the core this point is (0..1)
      const u=ts[j];
      // how far this set has wound round the core by here (radians)
      const wind=a.turns*m.tau*u;
      // the strand's angle round the core here
      const th=start+sgn*wind;
      // where the other set's strands lie here decides over or under
      const other=th+sgn*wind-shift;
      // how far off the spine it rides: the core, then lifted over or sunk under
      const off=rs[j]+sr*sinkAmount+sgn*parity*sr*over*@cos(n*other/2);
      q.*=sp[j]+(frameNormal[j]*m.splat3(@cos(th))+fb[j]*m.splat3(@sin(th)))*m.splat3(off);
      // drawn to a point at both ends, under the soil
      rr.*=sr*(0.2+0.8*m.smooth(m.clamp01(@min(u,1-u)/0.1)));
    }
    // the strand's tone: the two sets' strands alternate light and dark
    const col=color.mix(pal.rootBark,pal.rootLite,if((i+set)%2==0)0.25 else 0.7);
    try b.tubeR(&path,ts,&r,col,.stem,5);
  };
}
/// a branchlet peeling off the weave beside the root (side 1 its left,
/// -1 its right) and winding back into it further on, pointed at both ends
fn runner(b:*mg.Builder,sp:[]const V3,rs:[]const f32,span:m.Vice(f32,2),side:f32)Allocator.Error!void{
  // the branchlet's control points, bowing out and back
  var c:[6]V3=undefined;
  for(&c,0..)|*p,k|{
    // how far along the branchlet this point is (0..1), and where that falls on the root
    const f=m.ratio(k,5);
    const u=m.lerp(span[0],span[1],f);
    // the root's point and direction there, and the way out to its side
    const at=m.alongPath(sp,u);
    const tan=tangent(sp,u);
    // the way out to the root's side, flat on the ground
    const out=m.norm(m.cross(v3(0,1,0),tan));
    // how far it bows out here: most at its middle
    const bulge=@sin(m.pi*f);
    // the core's girth there
    const r=radiusAt(rs,u);
    p.*=at+out*m.splat3(side*(r+strandR+runnerOut*bulge))+v3(0,0.6*r+0.012*bulge,0);
  }
  // the branchlet resampled smooth
  var p:[16]V3=undefined;
  m.splineResample(&c,&p);
  // its growth timing (matching the root's there) and its radius, pointed at both ends
  var ts:[16]f32=undefined;
  var r:[16]f32=undefined;
  for(&ts,&r,0..)|*t,*rr,j|{
    // how far along the branchlet this point is (0..1)
    const f=m.ratio(j,15);
    t.*=m.lerp(span[0],span[1],f);
    rr.*=runnerR*(0.15+0.85*@sin(m.pi*f));
  }
  try b.tubeR(&p,&ts,&r,pal.rootLite,.stem,4);
}
/// a short twig off the top of the weave at `u`, bearing `n` leaves swept
/// forward along the root (splayed a little either side)
fn cluster(b:*mg.Builder,sp:[]const V3,rs:[]const f32,u:f32,n:u8,side:f32,rng:*Rng)Allocator.Error!void{
  // the root's point and direction at `u`
  const at=m.alongPath(sp,u);
  const tan=tangent(sp,u);
  // the root's up, square to its direction
  const up=m.norm(v3(0,1,0)-tan*m.splat3(tan[1]));
  // its direction flattened onto the ground
  const flat=m.norm(v3(tan[0],0,tan[2]));
  // the way out to its side, flat on the ground
  const out=m.norm(m.cross(v3(0,1,0),flat));
  // the core's girth there
  const r=radiusAt(rs,u);
  // where the twig starts, on the weave's top, off to one side
  const from=at+up*m.splat3(r+strandR)+out*m.splat3(side*r*0.4);
  // where the twig ends and the leaves sprout
  const tip=from+m.norm(up+flat*m.splat3(0.9)+out*m.splat3(side*0.3))*m.splat3(twigLen);
  try b.tube(&.{from,tip},&.{u,u},runnerR*0.8,runnerR*0.45,pal.rootLite,.stem,4);
  for(0..n)|l|{
    // this leaf's angle off forward, splayed, nudged to its side and jittered
    const a=(m.f(l)-0.5*m.f(n-1))*leafSplay+side*0.12+rng.range(-0.08,0.08);
    // which way this leaf points: forward, splayed out and lifted
    const dir=m.norm(flat*m.splat3(@cos(a))+out*m.splat3(@sin(a))+v3(0,leafLift,0));
    // the middle leaf of three the longest
    const len=leafLen*rng.range(0.85,1.1)*(if(n==3 and l==1)@as(f32,1.2)else 1);
    try mg.natural(b,tip,dir,len,leafW,0.4,pal.leafDark,pal.leafLite,u,.stalked);
  }
}
/// soil heaped where the root breaks the ground at `at`, clods round it,
/// and rootlets reaching on into the soil away from the arch. Where it
/// dives (`ahead`) it pushes a ridge of soil on before it, the way it
/// carries, as a mole's run does.
fn ground(b:*mg.Builder,at:V3,away:V3,r:f32,ahead:bool,rng:*Rng)Allocator.Error!void{
  // the way across the root, flat on the ground
  const side=m.norm(m.cross(v3(0,1,0),away));
  // how many mounds it heaps: a ridge diving, one coming up
  const heaps:usize=if(ahead)ridge.len else 1;
  for(ridge[0..heaps])|h|{
    // this mound's centre, pushed on ahead and scaled to the core
    const c=at+away*m.splat3(h[0]*r/coreRadius);
    // this mound's radius, scaled to the core
    const hr=h[1]*r/coreRadius;
    try mg.ellipsoid(b,.{.center=v3(c[0],-0.006,c[2]),.radii=v3(hr,hr*0.6,hr),.col=pal.soil,.rings=5,.segs=9});
  }
  for(0..3)|k|{
    // this clod's angle round the break, and how far out it lies
    const a=m.f(k)*2.1+rng.range(-0.4,0.4);
    const d=rng.range(0.06,0.09);
    // where the clod sits
    const p=at+(side*m.splat3(@cos(a))+away*m.splat3(@sin(a)))*m.splat3(d);
    // how big the clod is
    const cr=rng.range(0.011,0.018);
    try mg.ellipsoid(b,.{.center=v3(p[0],0.002,p[2]),.radii=v3(cr,cr*0.7,cr*1.1),.col=pal.soilDark,.rings=3,.segs=5});
  }
  for([_]f32{1,-1},0..)|sgn,k|{
    // which way this rootlet reaches: away, out to its side, and down
    const dir=m.norm(away*m.splat3(0.5)+side*m.splat3(sgn*0.8)+v3(0,-0.45,0));
    try kit.rootlet(b,at+v3(0,r*0.5,0),dir,rng.range(0.12,0.17),r*0.32,rng.next()|k);
  }
}
/// the core's girth at `u` along it
fn radiusAt(rs:[]const f32,u:f32)f32{
  // where `u` falls between the rings, as a fractional ring index
  const k=u*m.f(rs.len-1);
  // the ring just before it, kept short of the last
  const i=@min(m.floorTo(usize,k),rs.len-2);
  return m.lerp(rs[i],rs[i+1],k-m.f(i));
}
/// the root's direction at `u` along it, from points just before and after
fn tangent(sp:[]const V3,u:f32)V3{
  return m.norm(m.alongPath(sp,@min(u+0.02,1))-m.alongPath(sp,@max(u-0.02,0)));
}
/// mesh: CONDUIT TAP. a side root a conduit sends from under its middle
/// along +X to the plant on the next tile: woven as the conduit's own, it
/// comes up beside it, arches low over the ground and digs in at the
/// plant's foot, splitting into rootlets around it. It grows along its own
/// spline by how far it has reached (emitted with that as `grown`), the
/// rootlets last, and withers back down it.
pub const tap=struct{
  /// how far the tap reaches: to just short of the plant's tile centre (tiles)
  pub const reachDistance:f32=0.74;
  /// how much later each rootlet spreads than the one before
  const rootletStagger:f32=0.04;
  /// builds the tap: a small woven arch out to the plant, then three rootlets
  /// splitting round its foot, each a little after the last
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the growth skeleton the tap is hung on
    var k=growth.Skeleton.begin(b);
    // the arch's spine, which the rootlets branch from at its end
    const spine=try arch(b,&k,.{.from=0,.to=reachDistance,.peak=0.1,.depth=0.07,.coreR=0.02,.strands=2,.turns=1.5,.core=.stem,.leaves=&.{2},.runners=false,.seed=0x7A9});
    // where the arch digs in, at the plant's foot
    const end=v3(reachDistance,-0.02,0);
    for([_]f32{-0.9,-0.1,0.8},0..)|a,i|{
      // where this rootlet's vertices begin, so it spreads in its turn
      const s=b.mark();
      try kit.rootlet(b,end,m.norm(v3(@cos(a)*0.8,-0.45,@sin(a)*0.8)),0.24,0.014,0x7AA+%i*29);
      try k.on(b,s,spine,1,.{.from=end,.delay=rootletStagger*m.f(i)});
    }
    k.finish(b);
  }
};
