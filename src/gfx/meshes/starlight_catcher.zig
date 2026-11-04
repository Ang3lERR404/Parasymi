//! mesh: STARLIGHT CATCHER (drafts, side by side for the gardener). the
//! symbiotic lineage's rooted catcher, rooted beside a starlit patch and
//! reaching up for the light: a low rosette of broad leaves cupped upward
//! like open hands, a tall slender woven stalk rising from it to one
//! cupped bloom on top turned up to the sky like a dish, stamens in its
//! heart, and a thin vine spiralling a little way up the stalk with a few
//! small catching petals along it. Each draft is the same plant in its
//! own proportions (`Form`). It grows on a hidden stalk (gfx/growth.zig):
//! the roots spread with it, the hands unfold one by one, the stalk rises,
//! the vine winds up it as it passes, the dish opens petal by petal, the
//! stamens last.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, the mesh builder underneath
const engine=lib.engine;
/// all the maths: vectors, angles, splines
const m=engine.core.math;
/// the plant-piece mesher: braids, petals, stamens, the builder itself
const mg=lib.meshgen;
/// the garden's palette: leaves, vine, core
const pal=lib.palette;
/// colour conversions, for the dish's pale tips
const color=engine.core.color;
/// the structure kit: root mats
const kit=lib.structureKit;
/// the garden's growth timing: the hidden stalk everything grows along
const growth=lib.growth;
/// a point or direction in space
const V3=m.V3;
/// makes a point in space from three numbers
const v3=m.v3;
/// the dish's petals: pale cream at the claw, a soft star-blue at the tip
const dishBase=color.rgb(0.86,0.9,0.7).toRgba8(255);
/// (their tips)
const dishTip=color.rgb(0.62,0.74,0.98).toRgba8(255);
/// the vine's small catching petals: the same blue, paler
const catchTip=color.rgb(0.74,0.82,1.0).toRgba8(255);
/// how much later each hand and petal opens than the one before (a share of the growth)
const stagger:f32=0.025;
/// points the vine's spiral is laid through
const vinePts=14;
/// one draft's proportions
pub const Form=struct{
  /// how tall the stalk stands, to the dish (m)
  tall:f32,
  /// how thick the stalk is at its foot (m)
  girth:f32,
  /// how many hands ring the foot
  hands:u32,
  /// how long a hand is, and how wide (m)
  handLen:f32,
  /// (how wide)
  handWide:f32,
  /// how steeply a hand rises (radians above level) and how deeply it cups
  handRise:f32,
  /// (how deeply)
  handCup:f32,
  /// how many petals make the dish, how long each is (m)
  petals:u32,
  /// (how long)
  petalLen:f32,
  /// how steeply the dish's petals rise and how far they flare out
  dishRise:f32,
  /// (how far they flare)
  dishFlare:f32,
  /// how far up the stalk the vine winds (a share of it), how many times
  /// round, and how many small petals it carries
  vineTop:f32,
  /// (how many turns)
  vineTurns:f32,
  /// (how many petals)
  vinePetals:u32,
  /// its own random draws
  seed:u64,
};
/// the balanced blend: a stalk of middling height, six hands, an even dish
pub const balanced=Form{.tall=0.75,.girth=0.03,.hands=6,.handLen=0.26,.handWide=0.11,.handRise=0.75,.handCup=0.65,
  .petals=8,.petalLen=0.2,.dishRise=0.55,.dishFlare=0.35,.vineTop=0.45,.vineTurns=1.6,.vinePetals=3,.seed=0x5C01};
/// the reed: tall and slender, a small ring of hands, a wide shallow dish,
/// the vine winding higher
pub const reed=Form{.tall=1.1,.girth=0.024,.hands=5,.handLen=0.22,.handWide=0.09,.handRise=0.85,.handCup=0.6,
  .petals=9,.petalLen=0.24,.dishRise=0.4,.dishFlare=0.25,.vineTop=0.6,.vineTurns=2.2,.vinePetals=5,.seed=0x5C02};
/// the cup: short and stout, big hands held high, a deep cupped dish
pub const cup=Form{.tall=0.5,.girth=0.036,.hands=7,.handLen=0.3,.handWide=0.13,.handRise=0.95,.handCup=0.8,
  .petals=7,.petalLen=0.18,.dishRise=0.85,.dishFlare=0.15,.vineTop=0.35,.vineTurns=1.2,.vinePetals=2,.seed=0x5C03};
/// the catcher in proportions `f`, as a library mesh
pub fn Look(comptime f:Form)type{
  return struct{
    /// builds it: roots, hands, stalk, vine, dish and stamens, all hung on
    /// one growth skeleton in that order
    pub fn build(b:*mg.Builder)Allocator.Error!void{try catcher(b,f);}
  };
}
/// the catcher in proportions `f`
fn catcher(b:*mg.Builder,f:Form)Allocator.Error!void{
  // the growth skeleton everything below is hung on
  var k=growth.Skeleton.begin(b);
  // the dish's heart, at the stalk's top
  const top=v3(0,f.tall,0);
  // the hidden stalk: from just under the ground, leaning a breath, up to the dish
  const stalk=k.trunk(&.{v3(0,-0.03,0),v3(0.012,f.tall*0.35,-0.006),v3(-0.01,f.tall*0.7,0.008),top},.{.pace=1.4});
  try kit.rootMat(b,7,0.32,0.026,f.seed,.{.k=&k,.id=stalk});
  try hands(b,&k,stalk,f);
  try k.braid(b,stalk,.{.girth=f.girth,.tip=0.55,.strands=4,.twist=2.6,.wobble=pal.strandWobble,.seed=f.seed+%1,.core=pal.core,.strand=pal.vine});
  try vine(b,&k,stalk,f);
  try dish(b,&k,stalk,top,f);
  k.finish(b);
}
/// the hands: broad leaves round the foot, cupped and held up like open
/// hands, each unfolding in its turn
fn hands(b:*mg.Builder,k:*growth.Skeleton,stalk:growth.Id,f:Form)Allocator.Error!void{
  for(0..f.hands)|i|{
    // its bearing round the foot, nudged a little off even
    const a=(m.f(i)+0.15*@sin(m.f(i)*2.7+m.f(f.seed%7)))/m.f(f.hands)*m.tau;
    // where it rises from, just off the stalk's foot
    const base=v3(@cos(a)*0.035,0.02,@sin(a)*0.035);
    // where its vertices begin, so it unfolds in its turn
    const s=b.mark();
    try mg.petal(b,.{
      .base=base,.out=v3(@cos(a),0,@sin(a)),.len=f.handLen*(0.9+0.2*@abs(@sin(m.f(i)*1.9))),.width=f.handWide,
      .rise=f.handRise,.flare=0.45,.cup=f.handCup,.col=pal.leafDark,.tip=pal.leafLite,.part=.leaf,
    });
    try k.on(b,s,stalk,0.06,.{.from=base,.delay=stagger*m.f(i)});
  }
}
/// the vine: a thin tendril winding up the stalk from its foot, tapering
/// to a point, a few small catching petals along it
fn vine(b:*mg.Builder,k:*growth.Skeleton,stalk:growth.Id,f:Form)Allocator.Error!void{
  // its spiral round the stalk, a little out from it
  var c:[vinePts]V3=undefined;
  for(&c,0..)|*p,i|{
    // how far up it this point is, and how far round
    const u=m.ratio(i,vinePts-1);
    const a=u*f.vineTurns*m.tau+m.f(f.seed%5);
    const h=u*f.vineTop*f.tall+0.02;
    const r=f.girth*1.4+0.012;
    p.*=k.point(stalk,h/f.tall)+v3(@cos(a)*r,0,@sin(a)*r);
  }
  const id=k.branch(stalk,0.02,&c,.{.after=.passing,.pace=1.2});
  try k.tube(b,id,.{.r0=0.006,.tip=0.25,.col=pal.vine,.part=.stem,.sides=5});
  for(0..f.vinePetals)|j|{
    // where along the vine it sits, and the way out from the stalk there
    const u=0.3+0.6*m.ratio(j,@max(f.vinePetals,2)-1);
    const at=k.point(id,u);
    const out=m.norm(v3(at[0],0,at[2])+v3(1e-4,0,0));
    // where its vertices begin, so it opens as the vine reaches it
    const s=b.mark();
    try mg.petal(b,.{.base=at,.out=out,.len=0.07,.width=0.032,.rise=0.7,.flare=0.5,.cup=0.6,.col=pal.leafLite,.tip=catchTip,.part=.bloom});
    try k.on(b,s,id,u,.{.from=at});
  }
}
/// the dish: cupped petals round the stalk's top, turned up to the sky,
/// opening one by one, stamens standing in its heart last of all
fn dish(b:*mg.Builder,k:*growth.Skeleton,stalk:growth.Id,top:V3,f:Form)Allocator.Error!void{
  for(0..f.petals)|i|{
    // its bearing round the dish: the odd ones nudged half a step round
    const a=(m.f(i)+0.5*m.f(i%2))/m.f(f.petals)*m.tau;
    // where its vertices begin, so it opens in its turn
    const s=b.mark();
    try mg.petal(b,.{
      .base=top,.out=v3(@cos(a),0,@sin(a)),.len=f.petalLen,.width=f.petalLen*0.42,
      .rise=f.dishRise,.flare=f.dishFlare,.cup=0.55,.col=dishBase,.tip=dishTip,.part=.bloom,
    });
    try k.on(b,s,stalk,1,.{.from=top,.delay=0.03+stagger*m.f(i)});
  }
  // where the stamens' vertices begin, so they stand last of all
  const sta=b.mark();
  try mg.stamens(b,.{.heart=top+v3(0,0.01,0),.axis=v3(0,1,0),.n=9,.len=f.petalLen*0.55,.r=0.003,.anther=0.014,
    .lean=0.4,.arch=0.45,.col=pal.leafLite,.seed=f.seed+%2});
  try k.on(b,sta,stalk,1,.{.from=top,.delay=0.06+stagger*m.f(f.petals)});
}
