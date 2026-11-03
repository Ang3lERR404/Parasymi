//! mesh: BIRD OF PARADISE. a wild flower of no lineage, sprung up where
//! rain has pooled (game/wild.zig): a clump of paddle leaves held high on
//! long stalks, and flower stalks as tall rising among them, each ending in
//! a beak, a green sheath turned sideways and flushed wine-red toward its
//! point, out of which a crest of flame-orange sepals rises one flower after
//! another, a blue tongue reaching forward under each, its stigma at its
//! tip. Real by day; the crest and tongues are drawn as light (`.bloom`), so
//! when the wild flowers glow by night they burn like a bird of fire. It
//! grows on a hidden skeleton (gfx/growth.zig): the leaves rise one after
//! another and unfurl, then the stalks climb, the beak forms and the crests
//! open from it in turn.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, rng
const engine=lib.engine;
/// all the maths: vectors, splines
const m=engine.core.math;
/// the plant-piece mesher: leaves, petals, stamens, laminae, the builder itself
const mg=lib.meshgen;
/// colour conversions
const color=engine.core.color;
/// the garden's growth timing: the hidden skeleton everything grows along
const growth=lib.growth;
/// the seeded random stream each leaf and stalk is bent and sized by
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a point in space from three numbers
const v3=m.v3;
/// straight up
const up=v3(0,1,0);
/// a leaf stalk's colour: a grey green
const stalkCol=color.rgb(0.34,0.44,0.3).toRgba8(255);
/// a leaf's colour at its base, a deep blue-green, and paler at its tip
const leafCol=color.rgb(0.22,0.4,0.33).toRgba8(255);
/// (at its tip)
const leafTip=color.rgb(0.36,0.52,0.4).toRgba8(255);
/// the flower stalk's colour: greener than the leaves', flushed toward its top
const scapeCol=color.rgb(0.36,0.48,0.3).toRgba8(255);
/// the beak's colours, foot to point: green, a wine flush, wine red
const beakCols=[3]color.Rgb{color.rgb(0.32,0.48,0.3),color.rgb(0.44,0.32,0.3),color.rgb(0.55,0.18,0.28)};
/// a sepal's colour at its foot, a deep orange, and its flame-gold tip
const sepalCol=color.rgb(0.98,0.42,0.06).toRgba8(255);
/// (its tip)
const sepalTip=color.rgb(1,0.76,0.3).toRgba8(255);
/// the tongue's colour at its foot, a deep blue, and its pale tip
const tongueCol=color.rgb(0.1,0.16,0.72).toRgba8(255);
/// (its tip)
const tongueTip=color.rgb(0.38,0.58,1).toRgba8(255);
/// the stigma: white, at the tongue's tip
const stigmaCol=color.rgb(0.95,0.95,0.9).toRgba8(255);
/// the hidden foot every leaf and stalk rises out of
const foot=[_]V3{v3(0,-0.04,0),v3(0,0.01,0),v3(0,0.05,0)};
/// a leaf stalk's girth at its foot
const stalkR:f32=0.008;
/// a flower stalk's girth at its foot
const scapeR:f32=0.009;
/// how much later each leaf rises than the one before (the skeleton's time)
const leafStagger:f32=0.05;
/// how long the beak is, heel to point, and how far its heel reaches back
const beakLen:f32=0.21;
/// (how far its heel reaches back past the stalk)
const beakHeel:f32=0.04;
/// the beak's broadest half-width
const beakW:f32=0.025;
/// how many rows the beak is built of, heel to point
const beakRows=12;
/// how far apart along the beak each flower rises out of it
const crestStep:f32=0.02;
/// how much later each flower opens than the one before (the skeleton's time)
const crestStagger:f32=0.25;
/// how a clump is grown: how many leaves and flower stalks, how tall, and
/// the seed it is varied by
const Clump=struct{
  /// how many leaves
  leaves:u32,
  /// how many flower stalks
  scapes:u32,
  /// how tall its leaves stand
  tall:f32,
  /// how many flowers each beak has opened
  crests:u32,
  /// the seed it is bent and sized by
  seed:u64,
};
/// builds the plain clump: six leaves and two flowers
pub fn build(b:*mg.Builder)Allocator.Error!void{try clump(b,.{.leaves=6,.scapes=2,.tall=0.62,.crests=2,.seed=0xB1D0});}
/// a young clump: four leaves and one flower, lower
pub const young=struct{
  /// builds it
  pub fn build(b:*mg.Builder)Allocator.Error!void{try clump(b,.{.leaves=4,.scapes=1,.tall=0.48,.crests=1,.seed=0xB1D1});}
};
/// an old clump: eight leaves and three flowers, the tallest
pub const old=struct{
  /// builds it
  pub fn build(b:*mg.Builder)Allocator.Error!void{try clump(b,.{.leaves=8,.scapes=3,.tall=0.72,.crests=3,.seed=0xB1D2});}
};
/// a clump: the hidden foot, its leaves round it one after another, then
/// its flower stalks climbing among them
fn clump(b:*mg.Builder,c:Clump)Allocator.Error!void{
  // the skeleton, its random stream, and the hidden foot
  var k=growth.Skeleton.begin(b);
  var rng=Rng.init(c.seed);
  const base=k.trunk(&foot,.{});
  for(0..c.leaves)|i|try leaf(b,&k,base,c,i,&rng);
  // the flower stalks, once the leaves are up
  const after=k.latest(b);
  for(0..c.scapes)|i|try scape(b,&k,base,c,i,after,&rng);
  k.finish(b);
}
/// leaf `i`: a long stalk leaning out of the foot, curving up, and its
/// paddle blade unfurling at its top once it is up
fn leaf(b:*mg.Builder,k:*growth.Skeleton,base:growth.Id,c:Clump,i:usize,rng:*Rng)Allocator.Error!void{
  // its heading round the clump (radians), how far it leans out and how tall it stands
  const a=(m.f(i)*m.goldenAngle)+rng.range(-0.2,0.2);
  const out=v3(@cos(a),0,@sin(a));
  const lean=rng.range(0.12,0.3);
  const h=c.tall*rng.range(0.7,1)*(1-0.25*m.ratio(i,c.leaves));
  // its stalk: out of the foot, leaning, its top bowing outward a little
  const ctrl=[_]V3{v3(0,0.02,0),out*m.splat3(lean*h*0.25)+up*m.splat3(h*0.35),out*m.splat3(lean*h*0.6)+up*m.splat3(h*0.72),out*m.splat3(lean*h)+up*m.splat3(h)};
  const s=k.branch(base,0.6,&ctrl,.{.after=.passing,.delay=m.f(i)*leafStagger});
  try k.tube(b,s,.{.r0=stalkR,.tip=0.55,.col=stalkCol,.sides=6});
  // the blade: on along the stalk's way, a long paddle, a little torn at its edge
  const top=k.point(s,1);
  const dir=m.norm(k.tangent(s,1)+out*m.splat3(0.35));
  const len=h*rng.range(0.45,0.55);
  const at=b.mark();
  try mg.leaf(b,.{
    .at=top,.dir=dir,.len=len,.width=len*0.24,.droop=rng.range(0.2,0.35),.curl=0.08,
    .twist=rng.range(-0.4,0.4),.wave=0.12,.col=leafCol,.tip=leafTip,.stalkCol=stalkCol,.t=1,
  });
  try k.on(b,at,s,1,.{});
}
/// flower stalk `i`: climbing straight among the leaves once they are up,
/// its beak turned sideways at its top, the flowers rising out of it in turn
fn scape(b:*mg.Builder,k:*growth.Skeleton,base:growth.Id,c:Clump,i:usize,after:f32,rng:*Rng)Allocator.Error!void{
  // its heading, how far it leans, how tall it stands and the way its beak points
  const a=m.f(i)*2.2+rng.range(0.3,0.9);
  const out=v3(@cos(a),0,@sin(a));
  const h=c.tall*rng.range(1.02,1.18);
  const lean=h*rng.range(0.06,0.14);
  const turnTo=a+rng.range(1.2,1.9);
  const fwd=m.norm(v3(@cos(turnTo),0.18,@sin(turnTo)));
  // its stalk, from the foot straight up, leaning a little
  const ctrl=[_]V3{v3(0,0.02,0),out*m.splat3(lean*0.3)+up*m.splat3(h*0.4),out*m.splat3(lean*0.75)+up*m.splat3(h*0.8),out*m.splat3(lean)+up*m.splat3(h)};
  const s=k.late(base,0.6,&ctrl,after+m.f(i)*0.15,h*1.3);
  try k.tube(b,s,.{.r0=scapeR,.tip=0.75,.col=scapeCol,.sides=6});
  // the beak, once the stalk is up
  const top=k.point(s,1);
  const mark=b.mark();
  try beak(b,top,fwd);
  try k.on(b,mark,s,1,.{.span=0.3});
  // its flowers, rising out of the beak one after another
  for(0..c.crests)|j|{
    // where it rises, a little further back each time
    const heart=top+fwd*m.splat3(0.034-m.f(j)*crestStep)+up*m.splat3(0.012);
    const at=b.mark();
    try crest(b,heart,fwd,c.seed+%j*31+%i*7);
    try k.on(b,at,s,1,.{.delay=0.25+m.f(j)*crestStagger,.span=0.35,.from=heart});
  }
}
/// the beak: a boat-shaped sheath, keeled under, turned sideways from the
/// stalk's top (heel just behind it), closing to a point at either end, its
/// point lifting a little
fn beak(b:*mg.Builder,top:V3,fwd:V3)Allocator.Error!void{
  // across it, level
  const side=m.norm(m.cross(fwd,up));
  // each row's midline point, the way its width lies, the side it cups
  // to, its half-width, how far its edges rise, and its colour
  var spine:[beakRows]V3=undefined;
  var sides:[beakRows]V3=undefined;
  var face:[beakRows]V3=undefined;
  var ws:[beakRows]f32=undefined;
  var dish:[beakRows]f32=undefined;
  var cols:[beakRows]color.Rgba8=undefined;
  for(0..beakRows)|r|{
    // how far along it, heel to point (0..1)
    const u=m.ratio(r,beakRows-1);
    // its midline: from the heel forward, the point lifting
    spine[r]=top+fwd*m.splat3(-beakHeel+(beakLen+beakHeel)*u)+up*m.splat3(0.03*u*u*u);
    sides[r]=side;
    face[r]=up;
    // broadest a third along, drawn to a long point
    ws[r]=beakW*@sin(m.pi*m.pow(f32,u,0.55))*(1-0.35*u);
    dish[r]=1.3*ws[r];
    // green at its heel, a wine flush, wine red at its point
    const c=if(u<0.5)beakCols[0].lerp(beakCols[1],u*2)else beakCols[1].lerp(beakCols[2],(u-0.5)*2);
    cols[r]=c.toRgba8(255);
  }
  try mg.lamina(b,.{.spine=&spine,.side=&sides,.face=&face,.width=&ws,.dish=&dish,.bow=1,.broad=beakW,.col=&cols,.t=1,.part=.leaf});
}
/// one flower out of the beak at `heart`: three flame sepals rising up and
/// back as a crest, fanned; a blue tongue reaching forward over the beak,
/// two small lobes at its foot, the stigma at its tip
fn crest(b:*mg.Builder,heart:V3,fwd:V3,seed:u64)Allocator.Error!void{
  // its own random stream, and the way back along the beak, level
  var rng=Rng.init(seed);
  const back=m.norm(v3(-fwd[0],0,-fwd[2]));
  const ahead=-back;
  for(0..3)|i|{
    // this sepal's fan across the crest (radians), and the way it heads
    const fan=(m.f(i)-1)*0.45+rng.range(-0.08,0.08);
    const out=turned(back,fan);
    try mg.petal(b,.{.base=heart,.out=out,.len=rng.range(0.14,0.16),.width=0.016,.rise=1.25+rng.range(-0.06,0.06),.flare=0.45,.cup=0.35,.col=sepalCol,.tip=sepalTip,.part=.bloom});
  }
  // the tongue: forward and up, its tip bending down over the beak
  // its length, the angle it rises at, and how far its tip bends
  const tLen:f32=0.105;
  const rise:f32=0.95;
  const flare:f32=0.75;
  try mg.petal(b,.{.base=heart,.out=ahead,.len=tLen,.width=0.013,.rise=rise,.flare=flare,.cup=0.6,.col=tongueCol,.tip=tongueTip,.part=.bloom});
  // its lobes, short and spread, as an arrow's barbs
  for([_]f32{-0.6,0.6})|fan|try mg.petal(b,.{.base=heart,.out=turned(ahead,fan),.len=0.04,.width=0.01,.rise=0.7,.flare=0.3,.cup=0.5,.col=tongueCol,.tip=tongueTip,.part=.bloom});
  // the stigma and its anthers, out of the tongue's tip along its way
  const tip=heart+(ahead*m.splat3(@cos(rise-flare*0.6))+up*m.splat3(@sin(rise-flare*0.6)))*m.splat3(tLen*0.9);
  const way=m.norm(ahead*m.splat3(@cos(rise-flare))+up*m.splat3(@sin(rise-flare)));
  try mg.stamens(b,.{.heart=tip,.axis=way,.n=2,.len=0.026,.r=0.0016,.lean=0.08,.arch=0.1,.anther=0.006,.col=stigmaCol,.tip=stigmaCol,.part=.bloom,.seed=seed});
}
/// a level way `v` turned `a` radians about straight up
fn turned(v:V3,a:f32)V3{return v3(v[0]*@cos(a)-v[2]*@sin(a),0,v[0]*@sin(a)+v[2]*@cos(a));}
