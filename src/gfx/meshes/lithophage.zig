//! mesh: LITHOPHAGE. a parasite that eats stone: a bulbous foot half sunk
//! in the soil, pale roots gripping the ground round it, a stalk of three
//! strands wound tight rising into a great translucent bladder (its crop),
//! clasped by five lilac fronds curling up its flank and in over its crown.
//! What it draws from the ground condenses into a crystal inside the crop
//! (`crystal`, emitted); sapped away, the crystal runs down out of the
//! crop's lip as a stream of grit (`germinatorPour`, emitted) into a
//! cup on its foot (`germinatorPool`). Its roots out to the nodes it
//! drains are its own (`root`, `rootFar`).
//! Its stalk is the lineage's lattice (parasite_kit): woven at the foot,
//! parting into a cage round two sacs on its core, gathering at the neck.
//! It grows on a hidden stalk (gfx/growth.zig): the foot swells and its
//! roots spread with it, the stalk rises, its sacs swell as it passes, the
//! crop swells out of its top and the fronds clasp it last, all at once.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, rng, the mesh builder underneath
const engine=lib.engine;
/// all the maths: vectors, matrices, easing
const m=engine.core.math;
/// the plant-piece mesher: petals, tubes, grown paths, the builder itself
const mg=lib.meshgen;
/// colour conversions, for the crystal's violet and amber
const color=engine.core.color;
/// the garden's growth timing: the hidden stalk everything grows along
const growth=lib.growth;
/// the parasite kit: feet, roots, lattice stalks and bladders
const pk=lib.parasiteKit;
/// the mineral kit: faceted crystals
const mineral=lib.mineralKit;
/// the seeded random stream the crystal's points are sized by
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a point in space from three numbers
const v3=m.v3;
/// the stalk's top, where the crop sits on it
const neck=v3(0,0.34,0);
/// how the lattice stalk is shaped: its girth, how far its strands part and
/// over which stretch of it (0..1) they open round the sacs
const stalkShape:pk.Stalk=.{.girth=0.032,.part=2.4,.from=0.2,.to=0.85};
/// how fast the stalk rises against the rest of its growth
const stalkPace:f32=1.8;
/// the crop's centre: what condenses hangs at its heart
pub const cropAt=v3(0,0.5,0);
/// the crop's half-sizes along x, y and z
pub const cropR=v3(0.15,0.17,0.15);
/// how many fronds clasp the crop: the lineage's fivefold
const clasp=pk.fold;
/// how many control points run along one frond
const claspCtrl=9;
/// how far off the crop's skin a frond is held, as a share of its radius
const claspOff:f32=0.07;
/// where grit leaves the crop: its lip, low on its +X flank, from which it
/// runs down into the cup on the foot
pub const lipAt=cropAt+v3(cropR[0]*0.8,-cropR[1]*0.55,0);
/// where the cup on the foot sits, which the grit runs down into
pub const cupAt=v3(0.15,0.065,0.0);
/// how many lobes the cup opens into
const cupPetals=pk.fold;
/// where the foot sits, half sunk in the soil
const footAt=v3(0,-0.015,0);
/// the foot's half-sizes along x, y and z
const footR=v3(0.13,0.085,0.13);
/// builds the lithophage: the foot and roots, the lattice stalk and its sacs,
/// the cup on the foot, the crop and its lip, the clasping fronds and the
/// pearl nub at the crown; all hung on one growth skeleton in that order
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the growth skeleton everything below is hung on
  var k=growth.Skeleton.begin(b);
  // the hidden stalk: from just under the ground up to the neck
  const stalk=k.trunk(&.{v3(0,-0.03,0),v3(0.015,0.12,-0.01),v3(-0.012,0.24,0.008),neck},.{.pace=stalkPace});
  try pk.foot(b,&k,stalk,footAt,footR);
  try pk.roots(b,&k,stalk,pk.fold,0.26,0.016,0x1170);
  try pk.stalk(b,&k,stalk,stalkShape);
  try pk.organs(b,&k,stalk,stalkShape,2,0.6);
  // the cup on the foot, opening as the foot swells: a whorl of short pale
  // lobes cupped round where the grit pools
  for(0..cupPetals)|i|{
    // this lobe's angle round the cup (radians)
    const a=m.ratio(i,cupPetals)*m.tau;
    // where this lobe's vertices begin, so it opens with the foot
    const s=b.mark();
    try mg.petal(b,.{
      .base=cupAt-v3(0,0.012,0),.out=v3(@cos(a),0,@sin(a)),.len=0.05,.width=0.028,
      .rise=0.75,.flare=0.35,.cup=0.6,.col=pk.skin,.tip=pk.pearl,.t=0.1,.part=.leaf,
    });
    try k.on(b,s,stalk,0.2,.{.from=cupAt});
  }
  // the crop, swelling out of the stalk's top
  try pk.bladder(b,&k,stalk,1,cropAt,cropR,1,.{.from=neck});
  // its lip: a short pale spout pursed on its flank
  // where the lip's vertices begin, so it purses just after the crop
  const lip=b.mark();
  try b.tube(&.{lipAt-v3(0.03,-0.012,0),lipAt,lipAt+v3(0.012,-0.012,0)},&.{0.9,0.9,0.9},0.018,0.012,pk.pearl,.stem,7);
  try k.on(b,lip,stalk,1,.{.from=neck,.delay=0.05});
  // fronds out of its foot pole, up its flank over the outside and curling
  // in over its crown, alike
  for(0..clasp)|i|{
    // this frond's angle round the crop, set between the others
    const a=(m.f(i)+0.5)/clasp*m.tau;
    // the frond's control points, from the crop's foot up and over its crown
    var c:[claspCtrl]V3=undefined;
    for(&c,0..)|*p,j|{
      // how far along the frond this point is (0..1)
      const f=m.ratio(j,claspCtrl-1);
      // its polar angle from the crop's foot round to past its crown, held
      // just off its skin, the tip curling in and down toward the crown
      const th=m.lerp(m.pi,-0.15,f);
      // how far off the skin it is held, lifting toward the tip
      const lift=1+claspOff+0.25*f*f*f;
      // its angle round the crop, twisting a little as it climbs
      const tw=a+0.35*f;
      p.*=cropAt+v3(@sin(th)*@cos(tw)*cropR[0]*lift,@cos(th)*cropR[1]*(1+claspOff)-0.05*f*f*f*f,@sin(th)*@sin(tw)*cropR[2]*lift);
    }
    mg.grow(c[1..],.{.start=c[1],.direction=v3(0,1,0),.length=0.5,.wobble=0.12,.seed=0x1180});
    // the frond's own branch of the skeleton, grown just after the crop
    const id=k.branch(stalk,1,&c,.{.delay=0.05});
    try k.tube(b,id,.{.r0=0.013,.tip=0.15,.col=pk.lilac,.part=.tendril,.sides=5,.t0=0.75,.t1=1});
  }
  // a pearl nub at the crop's crown the fronds curl over
  // where the nub's vertices begin, so it forms last
  const nub=b.mark();
  try mg.ellipsoid(b,.{.center=cropAt+v3(0,cropR[1]*0.98,0),.radii=v3(0.028,0.02,0.028),.col=pk.pearl,.rings=5,.segs=8,.t=1});
  try k.on(b,nub,stalk,1,.{.from=neck,.delay=0.08});
  k.finish(b);
}
/// mesh: LITHOPHAGE CRYSTAL. what the crop condenses from the ground: a
/// cluster of faceted crystals (part `.prism`, no light of their own) about
/// its own origin, a unit `radius` across; the structure grows it with
/// what it has drawn and shrinks it as it saps it away.
pub const crystal=struct{
  /// how far the cluster reaches from its heart, before the structure scales it
  pub const radius:f32=0.09;
  /// builds the cluster: nine crystals pointing out every way from the heart,
  /// spread evenly on a golden spiral, each sized a little differently
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the cluster's own seeded rng, so every crop's crystal is alike
    var rng=Rng.init(0x117C);
    // the crystals' violet body and their amber tips
    const body=color.rgb(0.62,0.5,0.86).toRgba8(255);
    const tip=color.rgb(1.0,0.86,0.6).toRgba8(255);
    // points out every way from the heart, as it grows in sap
    for(0..9)|i|{
      // this crystal's angle round the heart (the golden angle per step)
      const th=m.f(i)*2.39996;
      // its height on the unit sphere, from near the top down to near the bottom
      const y=m.lerp(0.85,-0.85,m.ratio(i,8));
      // the sphere's radius at that height
      const rr=@sqrt(1-y*y);
      // which way this crystal points
      const dir=m.norm(v3(@cos(th)*rr,y,@sin(th)*rr));
      try mineral.crystal(b,.{
        .base=dir*m.splat3(-radius*0.25),.dir=dir,.len=radius*rng.range(0.85,1.15),.r=radius*rng.range(0.22,0.3),
        .col=body,.tip=tip,.part=.prism,
      },&rng);
    }
  }
};
/// mesh: LITHOPHAGE ROOT. a pale root from the foot out along +X to the
/// node on the next tile, arching low and digging into it, splitting into
/// gripping rootlets there; `rootFar` the same to a node on a diagonal.
/// It grows out along its own spline as it reaches (emitted with that as
/// `grown`), the rootlets last, and withers back down it.
pub const root=struct{
  /// builds the root to the node on the next tile
  pub fn build(b:*mg.Builder)Allocator.Error!void{try reaching(b,0.86,0x11A0);}
};
/// mesh: LITHOPHAGE ROOT FAR. the same root, out to a node on a diagonal
pub const rootFar=struct{
  /// builds the root to the node on the diagonal, √2 as far
  pub fn build(b:*mg.Builder)Allocator.Error!void{try reaching(b,0.86*m.sqrt2,0x11A1);}
};
/// builds one root `reach` tiles out along +X: a pale arch, grown first,
/// then five lilac rootlets clawing down round its end
fn reaching(b:*mg.Builder,reach:f32,seed:u64)Allocator.Error!void{
  // the growth skeleton the root is hung on
  var k=growth.Skeleton.begin(b);
  // the arch's control points, from the foot out to the node
  var c:[7]V3=undefined;
  for(&c,0..)|*p,j|{
    // how far along the arch this point is (0..1)
    const f=m.ratio(j,6);
    p.*=v3(0.07+(reach-0.07)*f,0.02+0.07*@sin(m.pi*f)*(1-0.4*f)-0.06*f*f*f,0);
  }
  mg.grow(&c,.{.start=c[0],.direction=v3(1,0,0),.length=reach,.wobble=0.25,.seed=seed});
  // the root's own spline
  const r=k.trunk(&c,.{});
  try k.tube(b,r,.{.r0=0.02,.tip=0.35,.col=pk.pearl,.part=.tendril,.sides=6,.t0=0,.t1=0.2});
  // gripping the node: rootlets clawing down round it
  // the root's end, where it grips the node
  const end=k.point(r,1);
  for(0..pk.fold)|i|{
    // this rootlet's angle round the end, and the way it reaches out
    const a=m.ratio(i,pk.fold)*m.tau;
    const out=v3(@cos(a),0,@sin(a));
    // the rootlet's control points, reaching out and clawing down
    var g:[5]V3=undefined;
    for(&g,0..)|*p,j|{
      // how far along the rootlet this point is (0..1)
      const f=m.ratio(j,4);
      p.*=end+out*m.splat3(0.08*@sin(f*1.4))+v3(0,-0.07*f*f,0);
    }
    // the rootlet's own branch, off the root's end
    const id=k.branch(r,1,&g,.{});
    try k.tube(b,id,.{.r0=0.009,.tip=0.1,.col=pk.lilac,.part=.tendril,.sides=4,.t0=0.2,.t1=0.25});
  }
  k.finish(b);
}
