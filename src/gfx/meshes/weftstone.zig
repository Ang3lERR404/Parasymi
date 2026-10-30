//! mesh: WEFTSTONE. a loomfern and a lithophage grown into one floating
//! body (convergence_kit), hanging `hover` over the tile it floats above:
//! at its bottom a bulb of both saps where what it draws from the nodes
//! gathers and is ionized into ley crystals (emitted), clasped by five pale
//! frondlets that run down its flank exactly alike and curl in beneath it,
//! where its tendrils leave (emitted, `tendril`, one to each node it
//! latches onto); above the bulb a short weave of green and pale strands
//! rising to a crown of five fronds arching out alike, their leaflets
//! every one their own, their tips rolled into croziers.
//! It grows on a hidden stalk (gfx/growth.zig): the bulb swells first,
//! the frondlets clasp it, the weave rises and the fronds arch out of its
//! top, their leaflets opening as each front passes.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error every building call may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, splines, easing
const m=engine.core.math;
/// the plant-piece mesh builder: tubes, leaves along a stem
const mg=lib.meshgen;
/// colour mixing, for the tendril greening toward its end
const color=engine.core.color;
/// the garden's growth skeleton, which times every piece's growing
const growth=lib.growth;
/// the parasites' kit: nodules, stalk shapes and woven sections
const pk=lib.parasiteKit;
/// the convergence kit: the sac, the weave, fronds and their colours
const kit=lib.convergenceKit;
/// a point or direction in 3D
const V3=m.V3;
/// makes a `V3` from three numbers
const v3=m.v3;
/// how high its bulb hangs over its tile (world units; its mesh carries
/// it: breathing lifts and lowers it, a slow bob)
pub const hover:f32=0.85;
/// the bulb's heart, hanging `hover` over the tile's centre
pub const bulbAt=v3(0,hover,0);
/// the bulb's radii across, up and deep (world units): a touch taller than wide
pub const bulbR=v3(0.12,0.13,0.12);
/// the point just under the bulb its tendrils leave from
pub const underAt=bulbAt-v3(0,bulbR[1]*1.05,0);
/// the weave's foot, on the bulb's top, where it rises to its crown
const base=bulbAt+v3(0,bulbR[1]*0.85,0);
/// the weave's top, where the five fronds arch out (0.2 over its foot)
const crown=base+v3(0,0.2,0);
/// how the weave is shaped round its stalk: its radius, how far its strands
/// part into a cage over 0.15..0.85 of it, and how hard it swells into its foot
const stalkShape:pk.Stalk=.{.girth=0.03,.part=2.1,.from=0.15,.to=0.85,.foot=0.3};
/// grows the whole Weftstone on a hidden stalk up its weave: the bulb
/// swells first, the five frondlets clasp it, the weave rises and the
/// five fronds arch out of its crown, their leaflets opening last
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the skeleton every piece is hung on and timed by
  var k=growth.Skeleton.begin(b);
  // the hidden stalk up the weave, wandering a little on its way to the crown
  const stalk=k.trunk(&.{base,base+v3(0.008,0.07,-0.006),base+v3(-0.006,0.14,0.004),crown},.{.pace=1.4});
  // the bulb first, out of the stalk's foot
  // where the bulb's vertices begin, so they can be hung on the stalk
  const bulb=b.mark();
  try kit.sac(b,.{.center=bulbAt,.radii=bulbR,.t=0.1,.arms=2,.swirl=1.1,.phase=1.3});
  try k.on(b,bulb,stalk,0,.{.from=base,.span=k.get(stalk).time*0.5});
  // pale frondlets clasping it, down its flank from its shoulder and
  // curling in under it, exactly alike
  for(0..kit.fold)|i|{
    // this frondlet's heading round the bulb
    const a=m.ratio(i,kit.fold)*m.tau;
    // the frondlet's seven guide points, from the bulb's shoulder down and in under it
    var c:[7]V3=undefined;
    for(&c,0..)|*q,j|{
      // how far round from the bulb's top this guide point lies (radians), and how
      // far out it hugs, easing in as it curls under
      const th=m.lerp(0.35,m.pi*0.93,m.ratio(j,6));
      const r=1.1-0.12*m.smooth(m.ratio(j,6));
      q.*=bulbAt+v3(@sin(th)*@cos(a)*bulbR[0]*r,@cos(th)*bulbR[1]*1.08,@sin(th)*@sin(a)*bulbR[2]*r);
    }
    // the frondlet as a branch off the stalk's foot, growing just after the bulb
    const id=k.branch(stalk,0,&c,.{.after=.with,.delay=0.05});
    try k.tube(b,id,.{.r0=0.011,.tip=0.3,.col=kit.pale,.part=.tendril,.sides=5,.t0=0.1,.t1=0.2});
    // where the frondlet's end bead begins, and the point it sits at
    const bead=b.mark();
    const end=k.point(id,1);
    try pk.nodule(b,end,m.splat3(0.012),0.2,kit.pearl,kit.pale,kit.pearl);
    try k.on(b,bead,id,1,.{.from=end});
  }
  // scratch for the weave: its points along the stalk, and its strands' sections
  var sp:[growth.res]V3=undefined;
  var sec:[growth.res]pk.Section=undefined;
  try kit.weaveOn(b,&k,stalk,stalkShape,.{.twist=0.9*m.pi,.seed=0x3EF1},0.2,0.4,&sp,&sec);
  // the crown: five fronds arching out of its top, alike
  for(0..kit.fold)|i|{
    // this frond's heading round the crown
    const a=0.4+m.ratio(i,kit.fold)*m.tau;
    _=try kit.frondOn(b,&k,stalk,1,.{
      .from=crown,.out=v3(@cos(a),0,@sin(a)),.len=0.55,.r=0.011,
      .rise=1.0,.curl=3.0,.pairs=8,.leafLen=0.1,.leafW=0.022,
      .t0=0.4,.t1=1,.seed=0x3EF2,.leafSeed=0x3EF3+%i*131,
    },.{.delay=0.04*m.f(i)});
  }
  k.finish(b);
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
      c.*=color.mix(kit.lilac,kit.leafLite,m.smooth(m.clamp01((f-0.3)/0.6)));
    }
    try b.tubeC(&p,&ts,&rs,&cs,null,.tendril,5);
    try mg.leavesAlong(b,&p,2,0.05,0.018,0.3,0.7,0,0.94,kit.leafDark,kit.leafLite,0x3E71);
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
