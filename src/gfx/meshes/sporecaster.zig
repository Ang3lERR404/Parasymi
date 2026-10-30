//! mesh: SPORECASTER. a parasite that sends: a bulbous foot half sunk in
//! the soil, a tall stalk of the lineage's lattice parting into a cage
//! round the sacs on its core, and on it a great translucent spore sac where what it
//! holds hangs (emitted, `bellyLump`s), pursed at its crown into a pore
//! its spore carriers rise out of and drift down into (`carrier`), a crown
//! of five lilac fronds flaring out round the pore and curling down and
//! back, each ending in a small cage of its own crowned in turn (a pod).
//! It grows on a hidden stalk (gfx/growth.zig): the foot swells and its
//! roots spread with it, the stalk rises, its sacs swell as it passes,
//! the sac swells out of its top, the pore purses and the fronds flare
//! last, all at once, their pods after them.
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
/// the garden's growth timing: the skeleton the caster grows along
const growth=lib.growth;
/// the parasite kit: foot, roots, lattice stalk, bladder, fronds, pods
const pk=lib.parasiteKit;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// the stalk's top, where the sac swells out of it
const neck=v3(0,0.36,0);
/// the lattice stalk: its girth, how far it parts into a cage, and the
/// stretch of it (0 foot .. 1 neck) the cage spans
const stalkShape:pk.Stalk=.{.girth=0.03,.part=2.6,.from=0.15,.to=0.85};
/// the sac's centre at the stalk's top, where the seeds it holds hang
pub const sacAt=v3(0,0.49,0);
/// the sac's radii: a little taller than wide
pub const sacR=v3(0.12,0.14,0.12);
/// the pore at its crown it casts from
pub const poreAt=sacAt+v3(0,sacR[1]*1.05,0);
/// how many fronds flare round the pore: the lineage's fivefold
const fronds=pk.fold;
/// the length of the pods the fronds end in
const pod:f32=0.075;
/// builds the caster: foot, roots, lattice stalk and its sacs, the spore
/// sac on top, the pursed pore at its crown, then the fronds and their pods,
/// all timed along one hidden stalk.
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the skeleton every part is timed along
  var k=growth.Skeleton.begin(b);
  // the hidden stalk, wavering up from under the soil to the neck
  const stalk=k.trunk(&.{v3(0,-0.03,0),v3(0.014,0.12,-0.01),v3(-0.012,0.25,0.008),neck},.{.pace=1.8});
  try pk.foot(b,&k,stalk,v3(0,-0.012,0),v3(0.12,0.08,0.12));
  try pk.roots(b,&k,stalk,pk.fold,0.24,0.015,0x5C01);
  try pk.stalk(b,&k,stalk,stalkShape);
  try pk.organs(b,&k,stalk,stalkShape,3,0.6);
  try pk.bladder(b,&k,stalk,1,sacAt,sacR,1,.{.from=neck});
  // the pore: a pursed pearl lip at the sac's crown
  const pore=b.mark();
  // the lip's points, growth stamps and radii
  var ring:[9]V3=undefined;
  var ts:[9]f32=undefined;
  var rs:[9]f32=undefined;
  for(&ring,&ts,&rs,0..)|*p,*t,*r,j|{
    // how far up the lip, 0..1
    const f=m.ratio(j,8);
    p.*=poreAt+v3(0,-0.02+0.035*f,0);
    t.*=1;
    // a lip swelling out and closing in round the opening
    r.*=0.022+0.014*@sin(m.pi*f)-0.008*f;
  }
  try b.tubeR(&ring,&ts,&rs,pk.pearl,.stem,10);
  try k.on(b,pore,stalk,1,.{.from=sacAt,.delay=0.05});
  // fronds flaring out round the pore and curling down and back, alike,
  // each ending in a pod
  for(0..fronds)|i|{
    // this frond's bearing round the sac
    const a=(m.f(i)+0.5)/fronds*m.tau;
    // its control points
    var c:[9]V3=undefined;
    // up the sac's flank from its foot pole, held just off its skin...
    for(c[0..4],0..)|*p,j|{
      // the angle down from the sac's crown, from its foot pole up
      const th=m.lerp(m.pi,0.55,m.ratio(j,3));
      p.*=sacAt+v3(@sin(th)*@cos(a)*sacR[0]*1.08,@cos(th)*sacR[1]*1.08,@sin(th)*@sin(a)*sacR[2]*1.08);
    }
    // ...then flaring out over the pore and curling down and back
    pk.frondPath(c[3],v3(@cos(a),0,@sin(a)),0.3,0.9,3.4,0x5C10,c[3..]);
    // its branch on the skeleton, growing a little after the sac
    const id=k.branch(stalk,1,&c,.{.delay=0.08});
    try k.tube(b,id,.{.r0=0.012,.tip=pk.podFoot(pk.podGirth(pod))/0.012,.col=pk.lilac,.part=.tendril,.sides=5,.t0=0.75,.t1=1});
    _=try pk.pod(b,&k,id,.{.len=pod,.girth=pk.podGirth(pod),.seed=0x5C20});
  }
  k.finish(b);
}
/// mesh: SPORE CARRIER. one spore drifting from caster to caster, about
/// its own origin, its tip (+Y) leading: a clear sac of thin-film sap (part `.bloom`, the instance's `fade`) round a bead
/// of what it carries (part `.essence`, its colour the instance tint),
/// fine lilac cilia trailing from its foot, waving (part `.tendril`).
pub const carrier=struct{
  /// the carrier's sac radius; the bead, tip and cilia are sized from it
  pub const radius:f32=0.04;
  /// builds the carrier: the tinted bead, the clear sac round it, a pearl
  /// tip on top and `cilia` fine strands trailing below, swaying as they go.
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(radius*0.45,radius*0.5,radius*0.45),.col=pk.pearl,.part=.essence,.rings=6,.segs=8,.t=-1});
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(radius,radius*1.12,radius),.col=pk.sac,.part=.bloom,.rings=8,.segs=10,.t=1});
    // a pursed pearl tip, the way it rises
    try mg.ellipsoid(b,.{.center=v3(0,radius*1.05,0),.radii=v3(radius*0.22,radius*0.18,radius*0.22),.col=pk.pearl,.rings=4,.segs=6,.t=1});
    for(0..cilia)|i|{
      // this strand's bearing, and the flat direction out along it
      const a=m.ratio(i,cilia)*m.tau;
      const out=v3(@cos(a),0,@sin(a));
      // its points, growth stamps and radii
      var p:[8]V3=undefined;
      var ts:[8]f32=undefined;
      var rs:[8]f32=undefined;
      for(&p,&ts,&rs,0..)|*q,*t,*r,j|{
        // how far down the strand, 0 root .. 1 tip
        const f=m.ratio(j,7);
        q.*=out*m.splat3(radius*(0.75+0.35*f))+v3(0,-radius*(0.6+2.6*f),0)+out*m.splat3(0.012*@sin(f*m.pi*1.5+m.f(i)));
        t.*=f;
        r.*=0.0035*(1-0.85*f);
      }
      try b.tubeR(&p,&ts,&rs,pk.lilac,.tendril,4);
    }
  }
  /// how many cilia trail from the carrier's foot
  const cilia=7;
};
