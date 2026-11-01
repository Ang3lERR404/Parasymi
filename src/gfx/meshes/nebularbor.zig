//! mesh: NEBULARBOR, the mist tree: a tree of both lineages on its 3x3
//! ground, the first thing to breathe moisture into the air
//! (convergenceKit, the driftbraid's look). It rises on one great weave of
//! green and pale strands, knotted violet where they cross, rooted both
//! ways; five limbs climb out of it, each forking in two under a sac and a
//! flower of both, every fork's twig crowned with a tuft of upright leaves,
//! so the crown spreads flat as an umbrella for its cloud to gather over;
//! from the umbrella's rim curtains of lilac strands hang, leaved green,
//! each ending in a bead of dew, the mist falling off them.
//! Beside it the two looks it was blended from, to compare (`--samples=`):
//! - `weeping` (Rorifera, the dew-bearer): five boughs arch up out of a
//!   sac of both saps at its crown and fall away, and from the outer half
//!   of each a curtain of strands hangs nearly to the ground;
//! - `cloud` (Nimbifera, the cloud-bearer): the umbrella alone.
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
/// how many young leaves the sapling puts out up its stem
const youngLeaves=2*fold;
/// how far up the stem the young leaves sit (shares of the trunk)
const youngFrom:f32=0.08;
/// (the highest)
const youngTo:f32=0.42;
/// how much longer its old age takes than its growing up: what it grows
/// after it is a real tree, as a share of all it grew before
const oldAge:f32=0.25;
/// builds the nebularbor's whole life on one skeleton (its structure
/// draws it ever more grown, slowing forever: structures/nebularbor.zig):
/// a sapling's stem putting out young leaves, rising into the trunk; the
/// umbrella spreading; the first young leaves falling as it does; the
/// curtains; a real tree. Then, slowly, old age: the last young leaves fall
/// one by one and an offshoot grows out where each was, crowned with its
/// own tuft and strands, and woven strands wrap its foot, hardening it.
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the skeleton every part is timed along
  var k=growth.Skeleton.begin(b);
  // the trunk's top, under its umbrella
  const top=v3(0.03,1.75,0.02);
  const trunk=try trunkUp(b,&k,top,0x4B00);
  try umbrellaCrown(b,&k,trunk,top,3);
  // when it is a real tree: everything grown so far is done
  const grown=k.latest(b);
  try young(b,&k,trunk,grown);
  try harden(b,&k,trunk,grown);
  k.finish(b);
}
/// where young leaf `i` sits up the stem (a share of the trunk) and its
/// bearing round it (the golden angle, so none shades the next)
fn youngAt(i:usize)m.Vice(f32,2){return.{m.lerp(youngFrom,youngTo,m.ratio(i,youngLeaves-1)),m.f(i)*2.39996};}
/// the sapling's young leaves up its stem, each on its own stalk: the
/// lower half fall as the crown spreads; the rest hold until it is a real
/// tree (`grown`), then fall one by one, an offshoot growing out where
/// each was
fn young(b:*mg.Builder,k:*growth.Skeleton,trunk:growth.Id,grown:f32)Allocator.Error!void{
  for(0..youngLeaves)|i|{
    // where it sits, its bearing, and the way out from the stem there
    const ya=youngAt(i);
    const out=v3(@cos(ya[1]),0,@sin(ya[1]));
    const at=k.point(trunk,ya[0])+out*m.splat3(trunkStalk.girth*0.9);
    // whether it holds until old age, becoming an offshoot
    const holds=i%2==1;
    // when it lets go, and how long it falls
    const fall:m.Vice(f32,2)=if(holds)offshootAt(i/2,grown)else.{grown*(0.5+0.04*m.f(i)),grown*0.06};
    const mk=b.mark();
    try mg.natural(b,at,m.norm(out+v3(0,0.55,0)),0.24,0.085,0.35,kit.leafDark,kit.leafLite,0.2,.stalked);
    try k.on(b,mk,trunk,ya[0],.{.from=at,.fall=fall});
    if(holds)try offshoot(b,k,trunk,i,grown);
  }
}
/// when offshoot `j` starts to grow, and the leaf there falls (in the
/// skeleton's time), and how long the fall takes: one after another
/// through its old age
fn offshootAt(j:usize,grown:f32)m.Vice(f32,2){return.{grown*(1+oldAge*0.08+oldAge*0.12*m.f(j)),grown*oldAge*0.2};}
/// an offshoot out of the stem where young leaf `i` was, late in its
/// life: a slender bough arching up and out, crowned with a small tuft,
/// two strands hanging from it
fn offshoot(b:*mg.Builder,k:*growth.Skeleton,trunk:growth.Id,i:usize,grown:f32)Allocator.Error!void{
  // where it leaves the stem, its bearing, and the way out
  const ya=youngAt(i);
  const out=v3(@cos(ya[1]),0,@sin(ya[1]));
  const from=k.point(trunk,ya[0]);
  // its control points: out of the stem, arching up and out
  var c:[4]V3=undefined;
  for(&c,[_]f32{0,0.25,0.5,0.64},[_]f32{0,0.1,0.28,0.38})|*q,r,h|q.*=from+out*m.splat3(r)+v3(0,h,0);
  // when it grows, and how long it takes
  const when=offshootAt(i/2,grown);
  const id=k.late(trunk,ya[0],&c,when[0],grown*oldAge*0.3);
  try k.braid(b,id,.{.girth=0.03,.tip=0.25,.strands=fold,.twist=3,.wobble=pal.strandWobble,.seed=0x5A00+%i,.core=kit.pale,.strand=kit.green,.t0=0.6,.t1=0.9});
  try tuft(b,k,id,12,0x5A10+%i*13);
  try curtain(b,k,id,2,0.5,0.95,0.35,0x5A20+%i*17);
}
/// its foot hardening with age: woven strands, a green one round a pale
/// core each, winding up round the base of the trunk one after another
/// once it is a real tree, thickening it
fn harden(b:*mg.Builder,k:*growth.Skeleton,trunk:growth.Id,grown:f32)Allocator.Error!void{
  for(0..fold)|i|{
    // where it starts round the trunk (radians)
    const a0=m.ratio(i,fold)*m.tau;
    // its control points: from inside the foot, winding up round the trunk
    var c:[8]V3=undefined;
    for(&c,0..)|*q,j|{
      // how far up its winding, the trunk's point there, and its bearing
      const f=m.ratio(j,7);
      const u=m.lerp(0.01,0.4,f);
      const a=a0+f*1.4*m.pi;
      // out from the trunk's core to just over its surface (none at the start)
      const r=if(j==0)0 else trunkStalk.girth*m.lerp(1.5,0.95,f);
      q.*=k.point(trunk,u)+v3(@cos(a)*r,0,@sin(a)*r);
    }
    const id=k.late(trunk,0.01,&c,grown*(1+oldAge*0.05*m.f(i)),grown*oldAge*0.6);
    try k.braid(b,id,.{.girth=0.04,.tip=0.4,.strands=3,.twist=2,.wobble=pal.strandWobble,.seed=0x5B00+%i,.core=kit.pale,.strand=kit.green,.t0=0.6,.t1=0.9});
  }
}
