//! mesh: STARLIGHT CATCHER (a draft for the gardener). the symbiotic
//! lineage's rooted catcher, rooted beside a starlit patch, a delicate
//! harvester of the faintest starlight, in the reed's proportions (the
//! gardener's pick): pseudo-rooted on its splayed little legs of root (the
//! gardener's favourite), only their tips touching the ground, its body
//! lifted over them by a hint of magic, bobbing softly (`hover`) on a faint
//! light under it; a low rosette of natural leaves cupped upward like open
//! hands, a fine woven stalk rising 1.1 m with two small pairs of leaves
//! along it, a thin vine winding a little way up it, and on top the
//! catcher (the sky dish and the dew cup in one, the gardener's blend): a
//! deep, smooth bowl of many fine petals turned to the sky, ringed with
//! hair-fine bead-tipped filaments reaching up to catch the light, a lens
//! of amber sap in its heart, dew-tipped hairs over its petals, stamens
//! round the lens. By night the light it gathers shows: a bead of it glows
//! in the lens and beads run down the vine to the roots (`glows`, by night
//! only). It grows on a hidden stalk (gfx/growth.zig): the legs spread with
//! it, the hands unfold one by one, the stalk rises, its leaf pairs open as
//! it passes, the vine winds up it, the bowl opens petal by petal, the lens
//! swells, the stamens and hairs last.
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
/// the structure kit: root mats (its legs), resin pods (its lens)
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
/// the bowl's tissue: a soft sage at the base, a pale star-blue at the rim
const dishBase=color.rgb(0.3,0.42,0.3).toRgba8(255);
/// (its rim)
const dishTip=color.rgb(0.52,0.63,0.86).toRgba8(255);
/// its fine hairs and filaments: silver-sage
const hairCol=color.rgb(0.62,0.68,0.66).toRgba8(255);
/// the beads of dew and gathered light: star-blue
const beadCol=color.rgb(0.6,0.75,1.0).toRgba8(255);
/// the light its beads throw by night (linear), and how far
const beadLight=m.V3{0.18,0.3,0.7};
/// (how far)
const beadReach:f32=1.6;
/// how much later each hand and petal opens than the one before (a share of the growth)
const stagger:f32=0.02;
/// the reed's proportions: how tall to the bowl, how thick at its foot
const tall:f32=1.1;
/// (how thick)
const girth:f32=0.018;
/// how many legs of root it stands on lightly, how far they splay, how thick
const legs=7;
/// (how far)
const legReach:f32=0.3;
/// (how thick)
const legGirth:f32=0.02;
/// how high its body floats over the ground, lifted by a hint of magic:
/// only its legs' tips touch down (pseudo-rooted)
const lift:f32=0.08;
/// how far it bobs up and down as it hovers (m; its legs' tips sink this
/// far into the ground at rest, so they never leave it)
const bob:f32=0.012;
/// how high a leg's knee arches over the body's foot (m)
const knee:f32=0.05;
/// the soft light of the magic lifting it, under its body (linear), and how far
const liftLight=m.V3{0.1,0.16,0.36};
/// (how far)
const liftReach:f32=0.7;
/// how many hands ring the foot, how long and wide each, how steeply it rises
const hands=7;
/// (how long)
const handLen:f32=0.24;
/// (how wide)
const handWide:f32=0.09;
/// (how steeply)
const handRise:f32=0.95;
/// where up the stalk its leaf pairs sit (shares of it), and how long the leaves are
const nodes=[_]f32{0.32,0.52};
/// (how long)
const nodeLeaf:f32=0.08;
/// how far up the stalk the vine winds (a share), how many times round
const vineTop:f32=0.62;
/// (how many turns)
const vineTurns:f32=2.4;
/// points the vine's spiral is laid through
const vinePts=16;
/// the vine's turn, from the side of the stalk it starts on
const vineStart:f32=0.7;
/// how many beads of light run down the vine to the roots by night
const beadsDown=5;
/// the bowl: how many petals, how long each, how wide (a share of its
/// length), how steeply they rise, how far they flare, how deeply each cups
/// and how many rows each is built in (smooth, never faceted)
const petals=18;
/// (how long)
const petalLen:f32=0.27;
/// (how wide)
const petalWide:f32=0.3;
/// (how steeply)
const petalRise:f32=0.42;
/// (how far they flare)
const petalFlare:f32=0.08;
/// (how deeply each cups)
const petalCup:f32=0.18;
/// (how many rows)
const petalRows=16;
/// its rim's filaments: how many, and how long (at the least, and how much more)
const filaments=24;
/// (how long)
const filamentLen=m.Vice(f32,2){0.09,0.035};
/// the dew-tipped hairs over each petal, and how long
const dewHairs=2;
/// (how long)
const dewLen:f32=0.035;
/// the lens of sap in its heart: how high its middle sits over the bowl's
/// heart and its half-sizes
const lensHigh:f32=0.05;
/// (its half-sizes)
const lensR=v3(0.075,0.035,0.075);
/// the catcher, as a library mesh, its beads glowing by night
pub const blend=struct{
  /// builds it: legs, hands, stalk, leaf pairs, vine and bowl on one growth skeleton
  pub fn build(b:*mg.Builder)Allocator.Error!void{try catcher(b);}
  /// its beads of gathered light: in the lens and down the vine, by night;
  /// and the soft light of the magic lifting it, always
  pub const glows:[]const Glow=&beadsOf();
  /// how far it bobs as it hovers on its hint of magic
  pub const hover:f32=bob;
};
/// the legs: splayed roots arching up out of the floating body's foot and
/// down to the ground, only their tips touching it (pseudo-rooted), braided
/// like the lineage's root mats and spreading with the stalk
fn legsOf(b:*mg.Builder,k:*growth.Skeleton,stalk:growth.Id)Allocator.Error!void{
  for(0..legs)|i|{
    // its bearing, nudged off even, and how far out its tip touches down
    const a=(m.f(i)+0.25*@sin(m.f(i)*3.1))/legs*m.tau;
    const r=legReach*(0.85+0.2*@abs(@sin(m.f(i)*1.7)));
    // out from the body, up over its knee, and down to its tip just in the ground
    const c=[_]V3{
      v3(@cos(a)*0.03,lift+0.02,@sin(a)*0.03),
      v3(@cos(a)*r*0.4,lift+knee,@sin(a)*r*0.4),
      v3(@cos(a)*r*0.78,lift*0.45,@sin(a)*r*0.78),
      v3(@cos(a)*r,-bob,@sin(a)*r),
    };
    const leg=k.branch(stalk,0,&c,.{.after=.with});
    try k.braid(b,leg,.{.girth=legGirth,.wobble=pal.strandWobble,.seed=0x5C10+%i*7,.core=pal.core,.strand=pal.vine,.t0=0.05});
  }
}
/// mesh: CATCHER BEAD. a bead of gathered starlight, a unit across, soft
/// star-blue; the catcher glows it in its lens and down its vine by night
pub const bead=struct{
  /// builds the bead: a smooth ball
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(1,1,1),.col=beadCol,.part=.bloom,.rings=8,.segs=10,.t=1});
  }
};
/// where the stalk runs (its hidden spline's control points)
const stalkCtrl=[_]V3{v3(0,lift-0.02,0),v3(0.012,lift+tall*0.35,-0.006),v3(-0.01,lift+tall*0.7,0.008),v3(0,lift+tall,0)};
/// a point of the vine's spiral, `u` of the way up it (0..1), off the stalk
fn vineAt(u:f32)V3{
  // how far round and up it is, and how far out from the stalk
  const a=u*vineTurns*m.tau+vineStart;
  const h=lift+u*vineTop*tall+0.02;
  const r=girth*1.6+0.01;
  return v3(@cos(a)*r,h,@sin(a)*r);
}
/// the beads of light by night: one in the lens, and `beadsDown` down the
/// vine to its foot; and the soft light of the magic under its body
fn beadsOf()[2+beadsDown]Glow{
  // the beads, filled in
  var gs:[2+beadsDown]Glow=undefined;
  gs[0]=.{.mesh="catcherBead",.at=v3(0,lift+tall+lensHigh,0),.scale=0.032,.glow=1.4,.light=beadLight*m.splat3(1.4),.reach=beadReach*1.5,.when=.night};
  for(0..beadsDown)|i|{
    // how far down the vine it is, smaller as it sinks
    const u=1-m.ratio(i+1,beadsDown+1);
    gs[1+i]=.{.mesh="catcherBead",.at=vineAt(u),.scale=0.008+0.006*u,.glow=0.9,.light=beadLight*m.splat3(0.35),.reach=beadReach*0.6,.when=.night};
  }
  // the magic lifting it: a soft light under its body, always
  gs[1+beadsDown]=.{.mesh="catcherBead",.at=v3(0,lift*0.5,0),.scale=0.001,.glow=0,.light=liftLight,.reach=liftReach};
  return gs;
}
/// the catcher
fn catcher(b:*mg.Builder)Allocator.Error!void{
  // the growth skeleton everything below is hung on
  var k=growth.Skeleton.begin(b);
  // the bowl's heart, at the stalk's top
  const top=v3(0,lift+tall,0);
  const stalk=k.trunk(&stalkCtrl,.{.pace=1.4});
  try legsOf(b,&k,stalk);
  try rosette(b,&k,stalk);
  try k.braid(b,stalk,.{.girth=girth,.tip=0.6,.strands=4,.twist=3.2,.wobble=pal.strandWobble,.seed=0x5C11,.core=pal.core,.strand=pal.vine});
  try leafPairs(b,&k,stalk);
  try vine(b,&k,stalk);
  try bowl(b,&k,stalk,top);
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
    const base=v3(@cos(a)*0.02,lift+0.015,@sin(a)*0.02);
    // where its vertices begin, so it unfolds in its turn
    const s=b.mark();
    try mg.natural(b,base,dir,handLen*big,handWide*big,0.35,handDark,handLite,0.4,.stalked);
    try k.on(b,s,stalk,0.05,.{.from=base,.delay=stagger*m.f(i)});
  }
  for(0..3)|i|{
    // a young leaf, folded close to the stalk
    const a=m.ratio(i,3)*m.tau+0.5;
    const base=v3(0,lift+0.03+0.02*m.f(i),0);
    const s=b.mark();
    try mg.natural(b,base,m.norm(v3(@cos(a)*0.3,1,@sin(a)*0.3)),handLen*0.4,handWide*0.35,0.05,handDark,handLite,0.5,.sessile);
    try k.on(b,s,stalk,0.08+0.04*m.f(i),.{.from=base});
  }
}
/// the stalk's leaf pairs: at each node two small natural leaves either
/// side of it, each pair turned a quarter round from the last, opening as
/// the stalk's front passes
fn leafPairs(b:*mg.Builder,k:*growth.Skeleton,stalk:growth.Id)Allocator.Error!void{
  for(nodes,0..)|u,n|{
    // the node, and the way the pair faces
    const at=k.point(stalk,u);
    const a=m.f(n)*m.pi*0.5+0.3;
    for([_]f32{0,m.pi})|turn|{
      // this leaf: out from the stalk and a little up
      const dir=m.norm(v3(@cos(a+turn),0.55,@sin(a+turn)));
      const s=b.mark();
      try mg.natural(b,at,dir,nodeLeaf*(1-0.2*m.f(n)),nodeLeaf*0.38,0.4,handDark,handLite,0.6,.stalked);
      try k.on(b,s,stalk,u,.{.from=at});
    }
  }
}
/// the vine: a thread-thin tendril winding up the stalk from its foot,
/// tapering to a point, tiny leaves along it (its beads glow over it by night)
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
/// a hair-fine filament rising from `from` along `way`, `len` long,
/// bending a little outward as it rises, tipped with a bead, grown on the
/// stalk's end `delay` after it is done
fn hair(b:*mg.Builder,k:*growth.Skeleton,stalk:growth.Id,from:V3,way:V3,len:f32,delay:f32)Allocator.Error!void{
  // the hair's points, their stamps and radii
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
/// the bowl: a deep, smooth dish of fine petals turned to the sky, opening
/// one by one, a ring of bead-tipped filaments round its rim reaching up,
/// dew-tipped hairs over its petals, a lens of amber sap swelling in its
/// heart, stamens round the lens last of all
fn bowl(b:*mg.Builder,k:*growth.Skeleton,stalk:growth.Id,top:V3)Allocator.Error!void{
  // the lens, swelling as the bowl opens
  const lens=b.mark();
  try kit.resinPod(b,top+v3(0,lensHigh,0),lensR,10,14);
  try k.on(b,lens,stalk,1,.{.from=top,.delay=0.04});
  for(0..petals)|i|{
    // its bearing round the bowl: the odd ones nudged half a step round, a little shorter
    const a=(m.f(i)+0.5*m.f(i%2))/petals*m.tau;
    const len=petalLen*(0.92+0.08*m.f(i%2));
    const s=b.mark();
    try mg.petal(b,.{.base=top,.out=v3(@cos(a),0,@sin(a)),.len=len,.width=len*petalWide,.rise=petalRise,.flare=petalFlare,.cup=petalCup,.col=dishBase,.tip=dishTip,.part=.bloom,.rows=petalRows});
    try k.on(b,s,stalk,1,.{.from=top,.delay=0.02+stagger*0.5*m.f(i)});
    for(0..dewHairs)|j|{
      // a dew-tipped hair standing off the petal's face, part way out
      const out=0.45+0.25*m.f(j);
      const e=a+(m.f(j)-0.5)*0.12;
      const at=top+v3(@cos(e)*len*out*@cos(petalRise),len*out*@sin(petalRise)+0.004,@sin(e)*len*out*@cos(petalRise));
      try hair(b,k,stalk,at,m.norm(v3(@cos(e)*0.2,1,@sin(e)*0.2)),dewLen*(0.8+0.4*m.f(j)),0.1+0.004*m.f(i*dewHairs+j));
    }
  }
  for(0..filaments)|i|{
    // a filament rising from the rim, leaning outward
    const a=m.ratio(i,filaments)*m.tau+0.13;
    const rim=top+v3(@cos(a)*petalLen*0.85,petalLen*petalRise,@sin(a)*petalLen*0.85);
    try hair(b,k,stalk,rim,m.norm(v3(@cos(a)*0.35,1,@sin(a)*0.35)),filamentLen[0]+filamentLen[1]*@abs(@sin(m.f(i)*2.3)),0.1+0.006*m.f(i));
  }
  // the stamens, standing round the lens last of all
  const s=b.mark();
  try mg.stamens(b,.{.heart=top+v3(0,lensHigh,0),.axis=v3(0,1,0),.n=11,.len=0.055,.r=0.0022,.anther=0.01,.lean=0.6,.arch=0.4,.col=handLite,.seed=0x5C12});
  try k.on(b,s,stalk,1,.{.from=top,.delay=0.14});
}
