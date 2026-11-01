//! mesh: the MOISTURE TREE's looks, grown full, for the gardener to pick
//! between (`--samples=`): a tree of both lineages on its 3x3 ground, the
//! first thing to breathe moisture into the air (convergenceKit, the
//! driftbraid's look). Each rises on one great weave of green and pale
//! strands, knotted violet where they cross, rooted both ways:
//! - `weeping` (Rorifera, the dew-bearer): five boughs arch up out of a
//!   sac of both saps at its crown and fall away, and from the outer half
//!   of each a curtain of lilac strands hangs nearly to the ground, leaved
//!   green, each ending in a bead of dew;
//! - `cloud` (Nimbifera, the cloud-bearer): five limbs climb out of its
//!   trunk, each forking in two, every fork crowned with a tuft of upright
//!   leaves, so the crown spreads flat as an umbrella for its cloud to
//!   gather over; a sac and a flower of both at each fork;
//! - `blend`: the cloud-bearer's umbrella, a curtain of the dew-bearer's
//!   strands hanging from its rim.
//! Laid out on a hidden skeleton (gfx/growth.zig), as every structure is.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, angles, easing
const m=engine.core.math;
/// the mesh builder and its primitives
const mg=lib.meshgen;
/// colour conversions, for greening a strand toward its tip
const color=engine.core.color;
/// the garden's growth timing: the skeleton the tree grows along
const growth=lib.growth;
/// the parasite kit: stalk shapes
const pk=lib.parasiteKit;
/// the convergence kit: weaves, sacs, blooms, feet of both lineages
const kit=lib.convergenceKit;
/// the shared swatches: how far a living strand wanders
const pal=lib.palette;
/// the seeded random stream that makes each strand and leaf its own
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// the trunk's great weave: thick, caged over its upper stretch
const trunkStalk:pk.Stalk=.{.girth=0.17,.part=1.8,.from=0.5,.to=0.9,.foot=0.5};
/// a bough or limb: slim, opening a little along its middle
const limbStalk:pk.Stalk=.{.girth=0.055,.part=1.5,.from=0.3,.to=0.75,.foot=0.3};
/// how many limbs, forks, boughs: the lineages' fivefold
const fold=kit.fold;
/// points along a hanging strand
const strandPts=14;
/// the trunk up from under the middle of its ground to `top`, a weave of
/// both along it and its foot rooted both ways; returns its spline
fn trunkUp(b:*mg.Builder,k:*growth.Skeleton,top:V3,seed:u64)Allocator.Error!growth.Id{
  // its control points: under the ground, up through it, leaning to its top
  const c=[_]V3{v3(0,-0.3,0),v3(0,0.3,0),v3(top[0]*0.35,top[1]*0.45,top[2]*0.35),v3(top[0]*0.8,top[1]*0.8,top[2]*0.8),top};
  const id=k.trunk(&c,.{.pace=1.2});
  // scratch for the weave's points and cross-sections
  var sp:[growth.res]V3=undefined;
  var sec:[growth.res]pk.Section=undefined;
  try kit.weaveOn(b,k,id,trunkStalk,.{.seed=seed},0,0.5,&sp,&sec);
  try kit.footOn(b,k,id,.{.r=0.3,.reach=1.45,.rootR=0.05,.seed=seed^0xF007});
  return id;
}
/// a limb of both off `parent` at `u`, through `c`, woven to `s`; returns its spline
fn limb(b:*mg.Builder,k:*growth.Skeleton,parent:growth.Id,u:f32,c:[]const V3,s:pk.Stalk,seed:u64,delay:f32)Allocator.Error!growth.Id{
  const id=k.branch(parent,u,c,.{.delay=delay});
  // scratch for the weave's points and cross-sections
  var sp:[growth.res]V3=undefined;
  var sec:[growth.res]pk.Section=undefined;
  try kit.weaveOn(b,k,id,s,.{.seed=seed},0.5,0.85,&sp,&sec);
  return id;
}
/// a slender bough off `parent` at `u`, through `c`, tapering to a point:
/// five green strands wound round a pale core, both lineages in it; returns its spline
fn bough(b:*mg.Builder,k:*growth.Skeleton,parent:growth.Id,u:f32,c:[]const V3,girth:f32,seed:u64,delay:f32)Allocator.Error!growth.Id{
  const id=k.branch(parent,u,c,.{.delay=delay});
  try k.braid(b,id,.{.girth=girth,.tip=0.2,.strands=fold,.twist=3,.wobble=pal.strandWobble,.seed=seed,.core=kit.pale,.strand=kit.green,.t0=0.6,.t1=0.9});
  return id;
}
/// a curtain of `n` strands hanging off spline `id` between `from` and `to`
/// along it, each falling to about `bottom` over the ground: a lilac
/// strand greening toward its tip, pairs of small green leaves down it, a
/// bead of dew at its end. Every strand its own length and sway.
fn curtain(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,n:usize,from:f32,to:f32,bottom:f32,seed:u64)Allocator.Error!void{
  // the curtain's own stream, so its strands are its own
  var rng=Rng.init(seed);
  for(0..n)|i|{
    // how far along the spline this strand hangs from, and the point there
    const u=m.lerp(from,to,(m.f(i)+0.5)/m.f(n));
    const top=k.point(id,u);
    // the way out from the trunk, flat, and the way across it
    const out=m.norm(v3(top[0],0,top[2])+v3(1e-3,0,0));
    const side=m.norm(m.cross(v3(0,1,0),out));
    // how far it falls, and how it sways out and across as it falls
    const len=@max(top[1]-bottom,0.2)*rng.range(0.78,1.04);
    const bow=rng.range(0.03,0.08);
    const ph=rng.range(0,m.tau);
    // its points, its growth tu.x, radius and colour
    var p:[strandPts]V3=undefined;
    var ts:[strandPts]f32=undefined;
    var rs:[strandPts]f32=undefined;
    var cs:[strandPts]color.Rgba8=undefined;
    for(&p,&ts,&rs,&cs,0..)|*q,*t,*r,*cl,j|{
      // how far down the strand this point is (0..1)
      const f=m.ratio(j,strandPts-1);
      q.*=top+out*m.splat3(bow*@sin(m.pi*f))+side*m.splat3(0.025*@sin(f*5+ph)*f)-v3(0,len*f,0);
      t.*=m.lerp(0.9,1,f);
      r.*=m.lerp(0.009,0.0035,f);
      cl.*=color.mix(kit.lilac,kit.leafLite,m.smooth(m.unlerp(0.3,1,f)));
    }
    // where the strand's vertices begin, so it all grows out of the bough
    const mk=b.mark();
    try b.tubeC(&p,&ts,&rs,&cs,null,.tendril,5);
    for(0..4)|j|{
      // how far down this leaf pair sits, and the point there
      const f=m.lerp(0.18,0.8,m.ratio(j,3));
      const at=m.alongPath(&p,f);
      for([_]f32{1,-1})|sgn|{
        // which way this leaf points: out to its side, hanging, jittered
        const dir=m.norm(side*m.splat3(sgn)+out*m.splat3(rng.range(-0.3,0.3))-v3(0,rng.range(0.3,0.7),0));
        try mg.natural(b,at,dir,0.07*(1-0.4*f),0.025,0.3,kit.leafDark,kit.leafLite,1,.sessile);
      }
    }
    // the bead of dew at its end, both saps in it
    try kit.sac(b,.{.center=p[strandPts-1]-v3(0,0.022,0),.radii=v3(0.024,0.03,0.024),.t=1,.phase=ph,.rings=6,.segs=8});
    try k.on(b,mk,id,u,.{.from=top});
  }
}
/// a tuft of upright leaves crowning spline `id`'s tip, spread like an
/// umbrella's ribs: `n` long natural leaves, every one its own lean
fn tuft(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,n:usize,seed:u64)Allocator.Error!void{
  // the tuft's own stream, so its leaves are its own
  var rng=Rng.init(seed);
  // the twig's tip, and the way out from the trunk there, flat
  const at=k.point(id,1);
  const out=m.norm(v3(at[0],0,at[2])+v3(1e-3,0,0));
  // where the tuft's vertices begin, so it unfolds as one
  const mk=b.mark();
  for(0..n)|i|{
    // this leaf's bearing round the tip, and how far it leans off upright
    const az=(m.f(i)+rng.range(-0.3,0.3))/m.f(n)*m.tau;
    const lean=rng.range(0.45,1.25);
    // its way: leaning out round the tip, a little more toward the rim
    const dir=m.norm(v3(@sin(lean)*@cos(az),@cos(lean),@sin(lean)*@sin(az))+out*m.splat3(0.25));
    try mg.natural(b,at,dir,rng.range(0.3,0.42),0.07,0.35,kit.leafDark,kit.leafLite,1,.sessile);
  }
  try k.on(b,mk,id,1,.{.from=at});
}
/// the dew-bearer's crown on `trunk`, whose top is `top`: a sac of both
/// saps, five boughs arching out of it and falling, each with a flower of
/// both at its height and a curtain hanging off its outer half
fn weepingCrown(b:*mg.Builder,k:*growth.Skeleton,trunk:growth.Id,top:V3)Allocator.Error!void{
  // the sac at the crown
  const sacR=v3(0.2,0.24,0.2);
  const sacAt=top+v3(0,sacR[1]*0.7,0);
  const sac=b.mark();
  try kit.sac(b,.{.center=sacAt,.radii=sacR,.t=0.85,.arms=3,.swirl=1.1,.phase=0.7});
  try k.on(b,sac,trunk,1,.{.from=top});
  for(0..fold)|i|{
    // this bough's bearing, and the way out along it, flat
    const a=(m.f(i)+0.25)/m.f(fold)*m.tau;
    const out=v3(@cos(a),0,@sin(a));
    // its control points: up out of the sac, arching over, falling away
    var c:[7]V3=undefined;
    for(&c,[_]f32{0.08,0.4,0.75,1.05,1.3,1.42,1.48},[_]f32{0.05,0.42,0.6,0.5,0.22,-0.12,-0.42})|*q,r,h|q.*=top+out*m.splat3(r)+v3(0,h,0);
    const id=try bough(b,k,trunk,0.97,&c,0.05,0x2E01+%i*53,0.05);
    // a flower of both where it arches highest
    const fl=b.mark();
    const heart=k.point(id,0.38)+v3(0,0.04,0);
    try kit.bloom(b,.{.heart=heart,.len=0.1,.spin=a,.petals=6,.seed=0x2E02+%i});
    try k.on(b,fl,id,0.38,.{.from=heart,.delay=0.1});
    try curtain(b,k,id,7,0.42,1,0.4,0x2E03+%i*131);
  }
  // a flower of both crowning the sac
  const crown=b.mark();
  const heart=sacAt+v3(0,sacR[1],0);
  try kit.bloom(b,.{.heart=heart,.len=0.15,.petals=8,.seed=0x2E04});
  try k.on(b,crown,trunk,1,.{.from=heart,.delay=0.1});
}
/// the cloud-bearer's crown on `trunk`, whose top is `top`: five limbs
/// climbing out, each with a sac and a flower of both where it forks, its
/// two twigs each crowned with a tuft, the tufts spreading flat as an
/// umbrella; `hang` strands of the dew-bearer's off each twig (none: none)
fn umbrellaCrown(b:*mg.Builder,k:*growth.Skeleton,trunk:growth.Id,top:V3,hang:usize)Allocator.Error!void{
  for(0..fold)|i|{
    // this limb's bearing, and the way out along it, flat
    const a=(m.f(i)+0.1)/m.f(fold)*m.tau;
    const out=v3(@cos(a),0,@sin(a));
    // its control points: out of the trunk's top, climbing as it spreads
    var c:[5]V3=undefined;
    for(&c,[_]f32{0,0.2,0.4,0.56,0.66},[_]f32{0,0.22,0.48,0.66,0.74})|*q,r,h|q.*=top+out*m.splat3(r)+v3(0,h,0);
    const id=try limb(b,k,trunk,0.98,&c,limbStalk,0x3C01+%i*53,0);
    // where it forks
    const fork=k.point(id,1);
    // a sac of both swelling at the fork, and a flower of both on it
    const sac=b.mark();
    try kit.sac(b,.{.center=fork+v3(0,0.03,0),.radii=v3(0.075,0.09,0.075),.t=0.9,.arms=2,.phase=m.f(i)*1.3});
    try k.on(b,sac,id,1,.{.from=fork});
    const fl=b.mark();
    try kit.bloom(b,.{.heart=fork+v3(0,0.11,0),.len=0.085,.spin=a,.petals=6,.seed=0x3C02+%i});
    try k.on(b,fl,id,1,.{.from=fork,.delay=0.15});
    for([_]f32{-1,1},0..)|sgn,j|{
      // this twig's bearing, a little either side of its limb's
      const a2=a+sgn*0.42;
      const out2=v3(@cos(a2),0,@sin(a2));
      // its control points: on out and up to the umbrella's rim
      var tc:[4]V3=undefined;
      for(&tc,[_]f32{0,0.24,0.46,0.6},[_]f32{0,0.17,0.3,0.36})|*q,r,h|q.*=fork+out2*m.splat3(r)+v3(0,h,0);
      const tw=try bough(b,k,id,1,&tc,0.035,0x3C03+%i*17+%j,0.05);
      try tuft(b,k,tw,22,0x3C04+%i*29+%j*7);
      if(hang>0)try curtain(b,k,tw,hang,0.35,0.95,0.85,0x3C05+%i*37+%j*11);
    }
  }
}
/// mesh: the dew-bearer (Rorifera): five boughs arching out of its crown
/// and falling away, curtains of lilac strands hanging from them
pub const weeping=struct{
  /// builds the dew-bearer whole: trunk, foot, crown, boughs, curtains
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the skeleton every part is timed along
    var k=growth.Skeleton.begin(b);
    // the trunk's top, leaning a little
    const top=v3(0.06,2.25,-0.04);
    const trunk=try trunkUp(b,&k,top,0x2E00);
    try weepingCrown(b,&k,trunk,top);
    k.finish(b);
  }
};
/// mesh: the cloud-bearer (Nimbifera): five forking limbs crowned with
/// tufts spreading flat as an umbrella, for its cloud to gather over
pub const cloud=struct{
  /// builds the cloud-bearer whole: trunk, foot, limbs, forks, tufts
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the skeleton every part is timed along
    var k=growth.Skeleton.begin(b);
    // the trunk's top, short and stout under its umbrella
    const top=v3(0.03,1.65,0.02);
    const trunk=try trunkUp(b,&k,top,0x3C00);
    try umbrellaCrown(b,&k,trunk,top,0);
    k.finish(b);
  }
};
/// mesh: the two blended: the cloud-bearer's umbrella with the
/// dew-bearer's strands hanging from its rim
pub const blend=struct{
  /// builds the blend whole: the umbrella, three strands off every twig
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the skeleton every part is timed along
    var k=growth.Skeleton.begin(b);
    // the trunk's top, under its umbrella
    const top=v3(0.03,1.75,0.02);
    const trunk=try trunkUp(b,&k,top,0x4B00);
    try umbrellaCrown(b,&k,trunk,top,3);
    k.finish(b);
  }
};
