//! mesh: STARLIGHT CATCHER (drafts, side by side for the gardener). the
//! symbiotic lineage's rooted catcher, rooted beside a starlit patch, a
//! delicate harvester of the faintest starlight, in the reed's proportions
//! (the gardener's pick): a low rosette of natural leaves cupped upward
//! like open hands, a fine woven stalk rising 1.1 m, a thin vine winding a
//! little way up it, and on top a catcher turned to the sky, stamens in its
//! heart. The light it gathers shows: beads of it glow in the catcher's
//! heart and run down the vine to the roots (each draft's `glows`). Three
//! directions for the catcher on top (`Dish`): a deep sky dish of many fine
//! petals ringed with hair-fine light-catching filaments; feathery plumes
//! fanned up out of a small cup like antennae; a cup of broad petals
//! holding a lens of sap, its rims fringed with dew-tipped hairs. It grows
//! on a hidden stalk (gfx/growth.zig): roots spread with it, the hands
//! unfold one by one, the stalk rises, the vine winds up it as it passes,
//! the catcher opens last, its stamens and hairs after it.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, the mesh builder underneath
const engine=lib.engine;
/// all the maths: vectors, angles, splines
const m=engine.core.math;
/// the plant-piece mesher: braids, petals, stamens, leaves, the builder itself
const mg=lib.meshgen;
/// the garden's palette: vine, core
const pal=lib.palette;
/// colour conversions, for its own muted greens and star-blues
const color=engine.core.color;
/// the structure kit: root mats, resin pods
const kit=lib.structureKit;
/// the garden's growth timing: the hidden stalk everything grows along
const growth=lib.growth;
/// a sample's glowing pieces (`meshlib.Glow`)
const Glow=lib.meshlib.Glow;
/// a point or direction in space
const V3=m.V3;
/// makes a point in space from three numbers
const v3=m.v3;
/// its hands: a deep muted green at the stalk, a softer sage at the tips
const handDark=color.rgb(0.1,0.24,0.13).toRgba8(255);
/// (their tips)
const handLite=color.rgb(0.32,0.5,0.34).toRgba8(255);
/// the catcher's tissue: a dusk-grey sage at the base, a pale star-blue at the rim
const dishBase=color.rgb(0.42,0.5,0.45).toRgba8(255);
/// (its rim)
const dishTip=color.rgb(0.6,0.7,0.92).toRgba8(255);
/// its fine hairs and plumes: silver-sage
const hairCol=color.rgb(0.62,0.68,0.66).toRgba8(255);
/// the beads of gathered light: star-blue
const beadCol=color.rgb(0.6,0.75,1.0).toRgba8(255);
/// the light its beads throw (linear), and how far
const beadLight=m.V3{0.18,0.3,0.7};
/// (how far)
const beadReach:f32=1.6;
/// how much later each hand and petal opens than the one before (a share of the growth)
const stagger:f32=0.02;
/// the reed's proportions: how tall to the catcher, how thick at its foot
const tall:f32=1.1;
/// (how thick)
const girth:f32=0.018;
/// how many hands ring the foot, how long and wide each, how steeply it rises
const hands=7;
/// (how long)
const handLen:f32=0.24;
/// (how wide)
const handWide:f32=0.09;
/// (how steeply)
const handRise:f32=0.95;
/// how far up the stalk the vine winds (a share), how many times round
const vineTop:f32=0.62;
/// (how many turns)
const vineTurns:f32=2.4;
/// points the vine's spiral is laid through
const vinePts=16;
/// how many beads of light run down the vine to the roots
const beadsDown=5;
/// the vine's turn, from the side of the stalk it starts on
const vineStart:f32=0.7;
/// the catcher on top: which direction
pub const Dish=enum{
  /// a deep bowl of many fine petals ringed with light-catching hairs
  sky,
  /// feathery plumes fanned up out of a small cup, like antennae
  plume,
  /// broad cupped petals holding a lens of sap, fringed with dew-tipped hairs
  dew,
};
/// the catcher with dish `d`, as a library mesh, its beads glowing
pub fn Look(comptime d:Dish)type{
  return struct{
    /// builds it: roots, hands, stalk, vine and the catcher on one growth skeleton
    pub fn build(b:*mg.Builder)Allocator.Error!void{try catcher(b,d);}
    /// its beads of gathered light: in the catcher's heart and down the vine
    pub const glows:[]const Glow=&beadsOf(d);
  };
}
/// mesh: CATCHER BEAD. a bead of gathered starlight, a unit across, soft
/// star-blue; the catcher's drafts glow it in their hearts and down their vines
pub const bead=struct{
  /// builds the bead: a smooth ball
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(1,1,1),.col=beadCol,.part=.bloom,.rings=8,.segs=10,.t=1});
  }
};
/// where the stalk runs (its hidden spline's control points)
const stalkCtrl=[_]V3{v3(0,-0.03,0),v3(0.012,tall*0.35,-0.006),v3(-0.01,tall*0.7,0.008),v3(0,tall,0)};
/// a point of the vine's spiral, `u` of the way up it (0..1), off the stalk
fn vineAt(u:f32)V3{
  // how far round and up it is
  const a=u*vineTurns*m.tau+vineStart;
  const h=u*vineTop*tall+0.02;
  // the stalk there (a straight line through its ends is near enough for
  // the beads; the vine itself follows the real spline)
  const r=girth*1.6+0.01;
  return v3(@cos(a)*r,h,@sin(a)*r);
}
/// the beads of light for dish `d`: one in the catcher's heart, and
/// `beadsDown` down the vine to its foot
fn beadsOf(comptime d:Dish)[1+beadsDown]Glow{
  // the beads, filled in
  var gs:[1+beadsDown]Glow=undefined;
  // the heart: how high it sits in the catcher, and how big
  const heart:f32=switch(d){.sky=>0.04,.plume=>0.04,.dew=>0.07};
  const size:f32=switch(d){.sky=>0.03,.plume=>0.018,.dew=>0.04};
  gs[0]=.{.mesh="catcherBead",.at=v3(0,tall+heart,0),.scale=size,.glow=1.4,.light=beadLight*m.splat3(1.4),.reach=beadReach*1.5};
  for(0..beadsDown)|i|{
    // how far down the vine it is, smaller as it sinks
    const u=1-m.ratio(i+1,beadsDown+1);
    gs[1+i]=.{.mesh="catcherBead",.at=vineAt(u),.scale=0.008+0.006*u,.glow=0.9,.light=beadLight*m.splat3(0.35),.reach=beadReach*0.6};
  }
  return gs;
}
/// the catcher with dish `d`
fn catcher(b:*mg.Builder,d:Dish)Allocator.Error!void{
  // the growth skeleton everything below is hung on
  var k=growth.Skeleton.begin(b);
  // the catcher's heart, at the stalk's top
  const top=v3(0,tall,0);
  const stalk=k.trunk(&stalkCtrl,.{.pace=1.4});
  try kit.rootMat(b,7,0.3,0.02,0x5C10,.{.k=&k,.id=stalk});
  try rosette(b,&k,stalk);
  try k.braid(b,stalk,.{.girth=girth,.tip=0.6,.strands=4,.twist=3.2,.wobble=pal.strandWobble,.seed=0x5C11,.core=pal.core,.strand=pal.vine});
  try vine(b,&k,stalk);
  switch(d){
    .sky=>try skyDish(b,&k,stalk,top),
    .plume=>try plumes(b,&k,stalk,top),
    .dew=>try dewCup(b,&k,stalk,top),
  }
  k.finish(b);
}
/// the hands: natural leaves round the foot, each its own size, held up
/// and cupped like open hands, unfolding one by one; a few young ones
/// folded close to the stalk among them
fn rosette(b:*mg.Builder,k:*growth.Skeleton,stalk:growth.Id)Allocator.Error!void{
  for(0..hands)|i|{
    // its bearing round the foot, nudged a little off even, and its size
    const a=(m.f(i)+0.18*@sin(m.f(i)*2.7))/hands*m.tau;
    const big=0.75+0.35*@abs(@sin(m.f(i)*1.9+0.4));
    // the way it reaches: out and steeply up
    const dir=m.norm(v3(@cos(a)*@cos(handRise),@sin(handRise),@sin(a)*@cos(handRise)));
    const base=v3(@cos(a)*0.02,0.015,@sin(a)*0.02);
    // where its vertices begin, so it unfolds in its turn
    const s=b.mark();
    try mg.natural(b,base,dir,handLen*big,handWide*big,0.35,handDark,handLite,0.4,.stalked);
    try k.on(b,s,stalk,0.05,.{.from=base,.delay=stagger*m.f(i)});
  }
  for(0..3)|i|{
    // a young leaf, folded close to the stalk
    const a=m.ratio(i,3)*m.tau+0.5;
    const base=v3(0,0.03+0.02*m.f(i),0);
    const s=b.mark();
    try mg.natural(b,base,m.norm(v3(@cos(a)*0.3,1,@sin(a)*0.3)),handLen*0.4,handWide*0.35,0.05,handDark,handLite,0.5,.sessile);
    try k.on(b,s,stalk,0.08+0.04*m.f(i),.{.from=base});
  }
}
/// the vine: a thread-thin tendril winding up the stalk from its foot,
/// tapering to a point, tiny leaves along it (its beads glow over it)
fn vine(b:*mg.Builder,k:*growth.Skeleton,stalk:growth.Id)Allocator.Error!void{
  // its spiral round the stalk
  var c:[vinePts]V3=undefined;
  for(&c,0..)|*p,i|p.*=vineAt(m.ratio(i,vinePts-1));
  const id=k.branch(stalk,0.02,&c,.{.after=.passing,.pace=1.2});
  try k.tube(b,id,.{.r0=0.0035,.tip=0.25,.col=pal.vine,.part=.stem,.sides=5});
  for(0..4)|j|{
    // a tiny leaf along it, pointing out from the stalk
    const u=0.2+0.2*m.f(j);
    const at=k.point(id,u);
    const out=m.norm(v3(at[0],0.4,at[2])+v3(1e-4,0,0));
    const s=b.mark();
    try mg.natural(b,at,out,0.035,0.016,0.3,handDark,handLite,0.6,.stalked);
    try k.on(b,s,id,u,.{.from=at});
  }
}
/// hairs: `n` hair-fine filaments rising from `from` points, each tipped
/// with a tiny bead, grown on the stalk's end after the catcher opens
fn hair(b:*mg.Builder,k:*growth.Skeleton,stalk:growth.Id,from:V3,way:V3,len:f32,delay:f32)Allocator.Error!void{
  // the hair's points, bending a little outward as it rises, and their stamps and radii
  var p:[6]V3=undefined;
  var ts:[6]f32=undefined;
  var rs:[6]f32=undefined;
  for(&p,&ts,&rs,0..)|*q,*t,*r,i|{
    const u=m.ratio(i,5);
    q.*=from+way*m.splat3(len*u)+v3(way[0],0,way[2])*m.splat3(len*0.25*u*u);
    t.*=1;
    r.*=0.0016*(1-0.6*u)*m.smooth(m.clamp01(u*6));
  }
  const s=b.mark();
  try b.tubeR(&p,&ts,&rs,hairCol,.stem,4);
  try mg.ellipsoid(b,.{.center=p[5],.radii=v3(0.0035,0.0035,0.0035),.col=beadCol,.part=.bloom,.rings=4,.segs=6,.t=1});
  try k.on(b,s,stalk,1,.{.from=from,.delay=delay});
}
/// stamens in the catcher's heart, standing last of all
fn heartStamens(b:*mg.Builder,k:*growth.Skeleton,stalk:growth.Id,top:V3,len:f32,delay:f32)Allocator.Error!void{
  const s=b.mark();
  try mg.stamens(b,.{.heart=top+v3(0,0.008,0),.axis=v3(0,1,0),.n=11,.len=len,.r=0.0022,.anther=0.01,.lean=0.35,.arch=0.4,.col=handLite,.seed=0x5C12});
  try k.on(b,s,stalk,1,.{.from=top,.delay=delay});
}
/// the sky dish: a deep bowl of many fine petals turned to the sky, a ring
/// of hair-fine filaments round its rim reaching up to catch the light
fn skyDish(b:*mg.Builder,k:*growth.Skeleton,stalk:growth.Id,top:V3)Allocator.Error!void{
  // how many petals, and how long each
  const n=18;
  const len:f32=0.27;
  for(0..n)|i|{
    const a=(m.f(i)+0.5*m.f(i%2))/n*m.tau;
    const s=b.mark();
    try mg.petal(b,.{.base=top,.out=v3(@cos(a),0,@sin(a)),.len=len*(0.92+0.08*m.f(i%2)),.width=len*0.2,.rise=0.42,.flare=0.08,.cup=0.35,.col=dishBase,.tip=dishTip,.part=.bloom});
    try k.on(b,s,stalk,1,.{.from=top,.delay=0.02+stagger*0.5*m.f(i)});
  }
  for(0..24)|i|{
    // a hair rising from the rim, leaning outward
    const a=m.ratio(i,24)*m.tau+0.13;
    const rim=top+v3(@cos(a)*len*0.85,len*0.42,@sin(a)*len*0.85);
    try hair(b,k,stalk,rim,m.norm(v3(@cos(a)*0.35,1,@sin(a)*0.35)),0.09+0.035*@abs(@sin(m.f(i)*2.3)),0.1+0.006*m.f(i));
  }
  try heartStamens(b,k,stalk,top,0.05,0.12);
}
/// plumes: a small cup, and out of it feathery plumes fanned up like
/// antennae, each a fine rachis with tiny leaflets along both sides
fn plumes(b:*mg.Builder,k:*growth.Skeleton,stalk:growth.Id,top:V3)Allocator.Error!void{
  for(0..7)|i|{
    // the cup's petals
    const a=m.ratio(i,7)*m.tau;
    const s=b.mark();
    try mg.petal(b,.{.base=top,.out=v3(@cos(a),0,@sin(a)),.len=0.07,.width=0.03,.rise=0.8,.flare=0.3,.cup=0.6,.col=dishBase,.tip=dishTip,.part=.bloom});
    try k.on(b,s,stalk,1,.{.from=top,.delay=0.02+stagger*m.f(i)});
  }
  for(0..6)|i|{
    // a plume: its bearing, its lean out from upright, its length
    const a=m.ratio(i,6)*m.tau+0.3;
    const lean:f32=0.55+0.15*@sin(m.f(i)*1.7);
    const len:f32=0.26+0.05*@cos(m.f(i)*2.1);
    // its rachis, curving outward as it rises
    var p:[8]V3=undefined;
    var ts:[8]f32=undefined;
    var rs:[8]f32=undefined;
    for(&p,&ts,&rs,0..)|*q,*t,*r,j|{
      const u=m.ratio(j,7);
      const l=lean*u;
      q.*=top+v3(@cos(a)*@sin(l)*len*u,@cos(l)*len*u,@sin(a)*@sin(l)*len*u);
      t.*=1;
      r.*=0.0025*(1-0.7*u)*m.smooth(m.clamp01(u*5));
    }
    const s=b.mark();
    try b.tubeR(&p,&ts,&rs,hairCol,.stem,4);
    for(1..7)|j|{
      // a pair of leaflets either side of the rachis, shorter toward its tip
      const at=p[j];
      const side=m.norm(v3(-@sin(a),0,@cos(a)));
      for([_]f32{-1,1})|sd|{
        try mg.petal(b,.{.base=at,.out=side*m.splat3(sd),.len=0.04*(1-m.ratio(j,9)),.width=0.007,.rise=0.5,.flare=0.2,.cup=0.3,.col=hairCol,.tip=dishTip,.part=.leaf});
      }
    }
    try mg.ellipsoid(b,.{.center=p[7],.radii=v3(0.005,0.005,0.005),.col=beadCol,.part=.bloom,.rings=4,.segs=6,.t=1});
    try k.on(b,s,stalk,1,.{.from=top,.delay=0.08+0.02*m.f(i)});
  }
  try heartStamens(b,k,stalk,top,0.045,0.14);
}
/// the dew cup: broad petals cupped deep round a lens of sap, each rim
/// fringed with fine hairs tipped with beads of dew
fn dewCup(b:*mg.Builder,k:*growth.Skeleton,stalk:growth.Id,top:V3)Allocator.Error!void{
  // the lens of sap in its heart, swelling as it opens
  const pod=b.mark();
  try kit.resinPod(b,top+v3(0,0.05,0),v3(0.08,0.04,0.08),10,14);
  try k.on(b,pod,stalk,1,.{.from=top});
  // how many petals, and how long each
  const n=9;
  const len:f32=0.23;
  for(0..n)|i|{
    const a=(m.f(i)+0.5*m.f(i%2))/n*m.tau;
    const s=b.mark();
    try mg.petal(b,.{.base=top,.out=v3(@cos(a),0,@sin(a)),.len=len,.width=len*0.48,.rise=0.95,.flare=0.45,.cup=0.75,.col=dishBase,.tip=dishTip,.part=.bloom});
    try k.on(b,s,stalk,1,.{.from=top,.delay=0.03+stagger*m.f(i)});
    for(0..4)|j|{
      // a dew-tipped hair along its rim, leaning out
      const e=a+(m.ratio(j,3)-0.5)*0.5;
      const rim=top+v3(@cos(e)*len*0.55,len*0.78,@sin(e)*len*0.55);
      try hair(b,k,stalk,rim,m.norm(v3(@cos(e)*0.7,1,@sin(e)*0.7)),0.035+0.01*m.f(j%2),0.1+0.004*m.f(i*4+j));
    }
  }
  try heartStamens(b,k,stalk,top+v3(0,0.03,0),0.04,0.14);
}
