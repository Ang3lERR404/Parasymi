//! mesh: WEFTSTONE. a loomfern and a lithophage grown into one floating
//! ionizer (convergence_kit), hanging `hover` over the tile it floats
//! above: a clear chamber of both saps, where what it gathers is ionized
//! into ley crystals (emitted), caged in a net of five green strands wound
//! one way and five pale the other, gathered into a knot under it (where
//! its tendrils leave, emitted, `tendril`) and a knot over it, a violet
//! knot wherever two cross; five pale nodes reaching in off the pale
//! strands round its middle, which the lightning jumps between (emitted,
//! `spark`); and over it five vanes fanned out of its top knot, each two
//! pale ribs and a bar strung across with fine green threads, as a loom's
//! warp, combing the air it draws in.
//! It grows on a hidden stalk (gfx/growth.zig) from the knot under: the
//! net climbs round, the chamber swells inside it, the nodes reach in, and
//! the vanes fan out of the top knot, their threads strung last.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error every building call may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, splines, easing
const m=engine.core.math;
/// the plant-piece mesh builder: tubes, ellipsoids
const mg=lib.meshgen;
/// colour mixing, for the tendril greening toward its end
const color=engine.core.color;
/// the garden's growth skeleton, which times every piece's growing
const growth=lib.growth;
/// the parasites' kit: nodules
const pk=lib.parasiteKit;
/// the convergence kit: the sac, the strands' colours, tapering tubes
const kit=lib.convergenceKit;
/// a point or direction in 3D
const V3=m.V3;
/// makes a `V3` from three numbers
const v3=m.v3;
/// how high its chamber hangs over its tile (world units; its mesh carries
/// it: breathing lifts and lowers it, a slow bob)
pub const hover:f32=0.85;
/// the chamber's heart, hanging `hover` over the tile's centre
pub const bulbAt=v3(0,hover,0);
/// the chamber's radii across, up and deep (world units): a touch taller than wide
pub const bulbR=v3(0.12,0.13,0.12);
/// the net's half-sizes round the chamber: across, up, deep
const netR=v3(0.138,0.17,0.138);
/// how far the net's strands wind round, foot to top (radians)
const netTwist:f32=0.9*m.pi;
/// the knot under the chamber, where its tendrils leave
pub const underAt=bulbAt-v3(0,netR[1],0);
/// the knot over it, where the vanes fan out
const overAt=bulbAt+v3(0,netR[1],0);
/// how far in from the chamber's axis its nodes reach
const nodeIn:f32=0.085;
/// each node's radius
pub const nodeR:f32=0.015;
/// how many nodes the lightning jumps between: one off each pale strand
pub const nodes=kit.fold;
/// a pale strand's bearing at its foot
fn paleAt(i:usize)f32{return(m.f(i)+0.5)/m.f(kit.fold)*m.tau;}
/// where node `i` (of `kit.fold`) sits, which the lightning jumps between:
/// round the chamber's middle, where its pale strand crosses it
pub fn node(i:usize)V3{
  // the pale strand's bearing halfway up
  const a=paleAt(i)-netTwist*0.5;
  return bulbAt+v3(@cos(a)*nodeIn,0,@sin(a)*nodeIn);
}
/// how far out a vane reaches from the top knot
const vaneReach:f32=0.23;
/// how high a vane rises over the top knot at its outer edge
const vaneRise:f32=0.055;
/// half the angle a vane spans round the top knot (radians)
const vaneHalf:f32=0.23;
/// how far a vane is pitched, its leading rib higher than its trailing one
const vanePitch:f32=0.035;
/// threads strung across each vane
const threads=15;
/// grows the whole Weftstone on a hidden stalk up through its chamber:
/// the net climbs round from the knot under, the chamber swells, the nodes
/// reach in, then the vanes fan out of the top knot
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the skeleton every piece is hung on and timed by
  var k=growth.Skeleton.begin(b);
  // the hidden stalk from the knot under, through the heart, to the knot over
  const stalk=k.trunk(&.{underAt,bulbAt,overAt},.{.pace=1.2});
  try knotAt(b,&k,stalk,0,underAt,0.026);
  // the net's strands: the pale ones exact, the green wandering
  var pale:[kit.fold]growth.Id=undefined;
  for([_]f32{-1,1})|way|for(0..kit.fold)|i|{
    // this strand's bearing at its foot
    const a0=if(way<0)paleAt(i)else m.ratio(i,kit.fold)*m.tau;
    // its guide points, from the knot under round the chamber to the knot over
    var c:[14]V3=undefined;
    for(&c,0..)|*q,j|{
      // how far up the strand this point is (0..1), its height round the net and its bearing
      const u=m.ratio(j,13);
      const th=m.pi*(1-u);
      const ph=a0+way*netTwist*u+if(way>0)mg.strandTurn(0x3EF1+%i*mg.strandSalt,u,0.08)else 0;
      q.*=bulbAt+v3(@sin(th)*@cos(ph)*netR[0],@cos(th)*netR[1],@sin(th)*@sin(ph)*netR[2]);
    }
    const id=k.branch(stalk,0,&c,.{.after=.with,.pace=0.8});
    if(way<0){
      pale[i]=id;
      try k.tube(b,id,.{.r0=0.0065,.tip=0.55,.col=kit.pale,.sides=5,.t0=0.1,.t1=0.45});
    }else try k.tube(b,id,.{.r0=0.0075,.tip=0.55,.col=kit.green,.sides=5,.t0=0.1,.t1=0.45});
  };
  // a violet knot wherever a green strand crosses a pale one
  for(0..kit.fold)|i|for(0..kit.fold)|j|{
    // their bearings at the foot, green and pale
    const ag=m.ratio(i,kit.fold)*m.tau;
    const ap=paleAt(j);
    // the turns round between them, each a crossing
    var n:i32=-2;
    while(n<=2):(n+=1){
      // where up the net they cross
      const u=(ap-ag+m.f(n)*m.tau)/(2*netTwist);
      if(u<0.12 or u>0.88)continue;
      // the crossing, on the exact pale strand
      const at=k.point(pale[j],u);
      // where the knot's vertices begin
      const mk=b.mark();
      try mg.ellipsoid(b,.{.center=at,.radii=m.splat3(0.0105),.col=kit.knot,.part=.stem,.rings=4,.segs=6,.t=0.3});
      try k.on(b,mk,pale[j],u,.{.from=at});
    }
  };
  // the chamber, swelling inside the net once the stalk reaches its heart
  const sac=b.mark();
  try kit.sac(b,.{.center=bulbAt,.radii=bulbR,.t=0.25,.arms=2,.swirl=1.1,.phase=1.3});
  try k.on(b,sac,stalk,0.5,.{.from=bulbAt,.span=k.get(stalk).time*0.6});
  // the nodes: each off its pale strand halfway up, reaching in to a pearl
  for(pale,0..)|id,i|{
    // where the strand crosses the chamber's middle, and the node in from it
    const from=k.point(id,0.5);
    const to=node(i);
    // the node's stalk, bowing a little, and its bead
    const c:[3]V3=.{from,m.lerpV(from,to,0.5)+v3(0,0.01,0),to};
    var p:[8]V3=undefined;
    m.splineResample(&c,&p);
    const mk=b.mark();
    try kit.taper(b,&p,0.0055,0.6,0.3,0.35,kit.pale,.stem,5);
    try pk.nodule(b,to,m.splat3(nodeR),0.35,kit.pearl,kit.lilac,kit.pearl);
    try k.on(b,mk,id,0.5,.{.from=from,.delay=0.1});
  }
  try knotAt(b,&k,stalk,1,overAt,0.024);
  // the vanes, fanned out of the top knot, pitched alike
  for(0..kit.fold)|i|{
    // this vane's bearing
    const a=0.2+m.ratio(i,kit.fold)*m.tau;
    // its two ribs, leading and trailing, out and up from the knot
    var ribs:[2]growth.Id=undefined;
    for(&ribs,[_]f32{-1,1})|*rb,s|{
      // the rib's guide points
      var c:[6]V3=undefined;
      for(&c,0..)|*q,j|{
        // how far out the rib this point is, its bearing narrowing in toward the knot
        const u=m.ratio(j,5);
        const ba=a+s*vaneHalf*m.smooth(@min(1,u*1.6));
        // it leaves the knot low and level, then sweeps up toward its edge
        const y=vaneRise*u*u+if(s<0)vanePitch*u else -vanePitch*0.5*u;
        q.*=overAt+v3(@cos(ba)*vaneReach*u,y,@sin(ba)*vaneReach*u);
      }
      rb.*=k.branch(stalk,1,&c,.{.delay=0.04*m.f(i)});
      try k.tube(b,rb.*,.{.r0=0.0068,.tip=0.6,.col=kit.pale,.sides=5,.t0=0.5,.t1=0.9});
    }
    // the bar across its outer edge, bowing out, from the leading rib's end to the trailing's
    const e0=k.point(ribs[0],1);
    const e1=k.point(ribs[1],1);
    const mid=m.lerpV(e0,e1,0.5);
    const bow=m.norm(v3(mid[0]-overAt[0],0,mid[2]-overAt[2]))*m.splat3(0.03);
    const bar=k.branch(ribs[0],1,&.{e0,m.lerpV(e0,e1,0.25)+bow*m.splat3(0.8),mid+bow,m.lerpV(e0,e1,0.75)+bow*m.splat3(0.8),e1},.{});
    try k.tube(b,bar,.{.r0=0.0055,.tip=0.9,.col=kit.pale,.sides=5,.t0=0.9,.t1=0.95});
    // pearls where the bar meets each rib, closing their ends
    for([_]V3{e0,e1},[_]f32{0,1})|e,u|{
      // where the pearl's vertices begin
      const mk=b.mark();
      try pk.nodule(b,e,m.splat3(0.0085),0.95,kit.pearl,kit.lilac,kit.pearl);
      try k.on(b,mk,bar,u,.{.from=e});
    }
    // the threads strung across, rib to rib, each sagging a little, green and pale-green in turn
    for(0..threads)|j|{
      // how far out the vane this thread is strung, and its two ends
      const u=m.lerp(0.22,0.95,m.ratio(j,threads-1));
      const p0=k.point(ribs[0],u);
      const p1=k.point(ribs[1],u);
      const sag=v3(0,-0.006*u,0);
      const c:[3]V3=.{p0,m.lerpV(p0,p1,0.5)+sag,p1};
      var p:[8]V3=undefined;
      m.splineResample(&c,&p);
      const mk=b.mark();
      try kit.taper(b,&p,0.0014,1,0.9,0.92,if(j%2==0)kit.green else kit.leafLite,.tendril,4);
      try k.on(b,mk,bar,0,.{.from=p0,.delay=0.03*m.f(j)});
    }
  }
  k.finish(b);
}
/// a knot of the pale skin at `at`, `r` across, grown out of `u` along `id`
fn knotAt(b:*mg.Builder,k:*growth.Skeleton,id:growth.Id,u:f32,at:V3,r:f32)Allocator.Error!void{
  // where the knot's vertices begin
  const mk=b.mark();
  try pk.nodule(b,at,v3(r,r*0.9,r),0.3,kit.pale,kit.lilac,kit.pearl);
  try k.on(b,mk,id,u,.{.from=at});
}
/// mesh: WEFTSTONE TENDRIL. one tendril from under the bulb to a node it
/// latches onto: built straight up +Y over 0..1 (bent on the GPU along its
/// curve, drawn out as far as it has reached): a lilac stem greening
/// toward its end, two small leaves of its own along it, and at its end
/// three pale claws gripping the node.
pub const tendril=struct{
  /// lays the tendril up 0..1: a wandering lilac stem greening toward its
  /// end, two small leaves along it, and three pale claws at its tip
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // how many rings the stem is built of
    const n=24;
    // each ring's centre, its place along the tendril (0..1), its radius and its colour
    var p:[n]V3=undefined;
    var ts:[n]f32=undefined;
    var rs:[n]f32=undefined;
    var cs:[n]color.Rgba8=undefined;
    for(&p,&ts,&rs,&cs,0..)|*q,*t,*r,*c,i|{
      // how far up this ring sits: the stem stops at 0.94, where the claws take over
      const f=m.ratio(i,n-1)*0.94;
      q.*=v3(0.004*@sin(f*11),f,0.004*@cos(f*9));
      t.*=f;
      r.*=0.009*m.lerp(1,0.55,f);
      c.*=color.mix(kit.lilac,kit.leafLite,m.smooth(m.unlerp(0.3,0.9,f)));
    }
    try b.tubeC(&p,&ts,&rs,&cs,null,.tendril,5);
    try mg.leavesAlong(b,&p,4,0.05,0.018,0.3,0.7,0,0.94,kit.leafDark,kit.leafLite,0x3E71);
    // the grip: three claws splaying out of its end and hooking in
    for(0..3)|i|{
      // this claw's heading round the stem, and the flat direction it splays along
      const a=m.ratio(i,3)*m.tau;
      const out=v3(@cos(a),0,@sin(a));
      // the claw's five guide points, out of the stem's end and hooking up
      var c:[5]V3=undefined;
      for(&c,0..)|*q,j|{
        // how far along the claw this guide point is, 0..1
        const f=m.ratio(j,4);
        q.*=v3(0,0.94,0)+out*m.splat3(0.035*@sin(m.pi*0.8*f))+v3(0,0.06*f,0);
      }
      // the guide points smoothed into ten points along a spline
      var cp:[10]V3=undefined;
      m.splineResample(&c,&cp);
      try kit.taper(b,&cp,0.006,0.15,0.94,1,kit.pearl,.tendril,4);
    }
  }
};
/// mesh: WEFTSTONE SPARK. one spark of lightning, built straight up +Y over
/// 0..1 (bent on the GPU along the curve it jumps, between two nodes or
/// from a node to the crystal): a thin jagged thread of light, kinked at
/// uneven steps, pointed at both ends (part `.spark`: white-hot along its
/// core, violet at its edge, lighting the air round it)
pub const spark=struct{
  /// lays the spark up 0..1: kinked at uneven steps, a branch of its own
  /// forking off partway
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // how many kinks it runs through
    const n=13;
    // each kink's place, its place along the spark (0..1) and its radius
    var p:[n]V3=undefined;
    var ts:[n]f32=undefined;
    var rs:[n]f32=undefined;
    var rng=engine.core.rng.Rng.init(0x5A4C);
    for(&p,&ts,&rs,0..)|*q,*t,*r,i|{
      // how far along it this kink is: uneven steps, the ends fixed
      const f=if(i==0 or i==n-1)m.ratio(i,n-1)else m.ratio(i,n-1)+rng.range(-0.025,0.025);
      // how far off its line it kinks: none at its ends
      const off=if(i==0 or i==n-1)@as(f32,0)else 0.016;
      q.*=v3(rng.range(-1,1)*off,f,rng.range(-1,1)*off);
      t.*=f;
      r.*=@max(0.0032*@sin(m.pi*f),2e-4);
    }
    try b.tubeR(&p,&ts,&rs,kit.pearl,.spark,4);
    // a short fork off its middle, dying out
    var fp:[5]V3=undefined;
    var ft:[5]f32=undefined;
    var fr:[5]f32=undefined;
    for(&fp,&ft,&fr,0..)|*q,*t,*r,j|{
      // how far along the fork this point is
      const f=m.ratio(j,4);
      q.*=p[5]+v3(0.03*f+rng.range(-0.006,0.006)*f,0.09*f,-0.012*f);
      t.*=ts[5]+0.1*f;
      r.*=@max(0.002*(1-f),2e-4);
    }
    try b.tubeR(&fp,&ft,&fr,kit.pearl,.spark,4);
  }
};
