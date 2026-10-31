//! mesh: LOOMFERN. a fern that weaves: a short woven bole on a root mat,
//! opening into a crown of fronds arching out, their leaflets in pairs
//! along them, two young fronds still rolled tight in croziers at the
//! heart. Up through the middle rises a slender spindle out of a calyx
//! (essence it is fed stands in the calyx, `germinatorPool`); the sheaf
//! of fibre it weaves forms on the spindle (`sheaf`), drawn from the
//! fronds by threads (`thread`), and finished sheaves are laid at its foot.
//! It grows on a hidden bole (gfx/growth.zig): the roots spread with it,
//! then the fronds rise out of the crown one after another, their leaflets
//! unfolding as each front passes, the croziers last, then the calyx opens
//! and the spindle rises.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, rng, the builder underneath
const engine=lib.engine;
/// all the maths: vectors, matrices, splines
const m=engine.core.math;
/// the plant-piece mesher: braids, blades, petals, stamens, the builder itself
const mg=lib.meshgen;
/// the garden's palette: vine, core, leaves, root bark
const pal=lib.palette;
/// colour conversions, for the fibre's greens
const color=engine.core.color;
/// the structure kit: the root mat under the bole
const kit=lib.structureKit;
/// the garden's growth timing: the hidden bole everything grows along
const growth=lib.growth;
/// the seeded random stream each frond is bent and sized by
const Rng=engine.core.rng.Rng;
/// a point or direction in space
const V3=m.V3;
/// makes a point in space from three numbers
const v3=m.v3;
/// the bole's top, where the fronds arch out of its crown
pub const crown=v3(0,0.15,0);
/// the bole's girth at its foot, before it flares
const boleR:f32=0.06;
/// how fast the bole rises against the rest of its growth
const bolePace:f32=1.6;
/// how many fronds ring the crown
/// (the two croziers at its heart are extra)
pub const fronds=7;
/// how many control points run along each frond
const frondCtrlCount=7;
/// how much later each frond rises than the one before (the skeleton's time)
const frondStagger:f32=0.06;
/// the girth of a frond's rachis, its green midstem
const rachisR:f32=0.014;
/// how many pairs of leaflets run along each frond, from `pinnaFrom` to
/// its tip, longest near its foot
const pinnae=20;
/// where along a frond its leaflets begin (0..1)
const pinnaFrom:f32=0.22;
/// a leaflet's length at its longest
const pinnaLen:f32=0.115;
/// a leaflet's width at its widest
const pinnaW:f32=0.019;
/// the spindle's tip, the crown its foot
pub const spindleTop=v3(0,0.46,0);
/// where on the spindle the sheaf forms
pub const sheafAt=v3(0,0.33,0);
/// the spindle's girth at its foot
const spindleR:f32=0.011;
/// how many sepals make the calyx round the spindle's foot
const sepals=5;
/// where its pool of essence stands, cupped in the calyx
pub const poolAt=crown+v3(0,0.035,0);
/// a sheaf's height, its unit size
pub const sheafH:f32=0.17;
/// a sheaf's girth at its waist, where the root binds it
const sheafWaist:f32=0.018;
/// a sheaf's girth at its flaring ends
const sheafEnd:f32=0.045;
/// how many strands make up a sheaf
const sheafStrands=16;
/// fibre: the colour of the item it weaves, younger toward the tips
const fibre=color.rgb(0.47,0.66,0.35).toRgba8(255);
/// the fibre's darkest, at a sheaf's waist
const fibreDark=color.rgb(0.33,0.48,0.24).toRgba8(255);
/// the fibre's palest, toward a sheaf's ends and young strands
const fibreLite=color.rgb(0.62,0.78,0.45).toRgba8(255);
/// a frond's control points (deterministic per frond), from the crown
/// arching out and over, its tip curling back under as a crozier unrolled
pub fn frondCtrl(i:usize)[frondCtrlCount]V3{
  // this frond's own seeded rng, so it bends the same every time
  var rng=Rng.init(0x10F+i*97);
  // its heading round the crown: evenly spread, jittered a little (radians)
  const a=(m.f(i)+rng.range(-0.18,0.18))/fronds*m.tau;
  // the way out along that heading, flat, and straight up
  const out=v3(@cos(a),0,@sin(a));
  const up=v3(0,1,0);
  // how far it reaches out and how high it lifts, each its own
  const reach=rng.range(0.9,1.1);
  const lift=rng.range(0.85,1.12);
  // the arch's shape: (out, up) at each control point, before reach and lift
  const ks=[frondCtrlCount][2]f32{.{0.02,0},.{0.07,0.17},.{0.19,0.31},.{0.33,0.36},.{0.45,0.3},.{0.52,0.2},.{0.5,0.15}};
  // the control points, laid along out and up from the crown
  var c:[frondCtrlCount]V3=undefined;
  for(&c,ks)|*p,k|p.*=crown+out*m.splat3(k[0]*reach)+up*m.splat3(k[1]*lift);
  return c;
}
/// the point `u` along frond `i` (0 its foot .. 1 its tip)
pub fn frondAt(i:usize,u:f32)V3{
  // the frond's control points
  const c=frondCtrl(i);
  // the frond's spline resampled, to walk along by length
  var p:[growth.res]V3=undefined;
  m.splineResample(&c,&p);
  return m.alongPath(&p,u);
}
/// builds the loomfern: the bole and its roots, seven fronds and two
/// croziers, then the calyx, the spindle and the bud closing its tip;
/// all hung on one growth skeleton in that order
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the growth skeleton everything below is hung on
  var k=growth.Skeleton.begin(b);
  // the hidden bole: from just under the ground up to the crown
  const bole=k.trunk(&.{v3(0,-0.04,0),v3(0.008,crown[1]*0.5,-0.006),crown},.{.pace=bolePace});
  try kit.rootMat(b,8,0.5,0.036,0x10F1,.{.k=&k,.id=bole});
  {
    // the bole's path, its growth timing and its radius along it
    var sp:[growth.res]V3=undefined;
    var ts:[growth.res]f32=undefined;
    var rs:[growth.res]f32=undefined;
    k.path(bole,0,1,&sp);
    for(&ts,&rs,0..)|*t,*r,i|{
      // how far up the bole this point is (0..1)
      const u=m.ratio(i,growth.res-1);
      t.*=u*0.3;
      // flared at its foot, swelling again under the crown
      r.*=boleR*(0.75+0.5*@exp(-u*6)+0.25*@exp(-(1-u)*7));
    }
    // where the braid's vertices begin, so it rises along the bole
    const s=b.mark();
    try mg.braid(b,&sp,&ts,&rs,5,2.4,pal.strandWobble,0x10F2,pal.core,pal.vine);
    try k.along(b,s,bole);
  }
  for(0..fronds)|i|try frond(b,&k,bole,i);
  for(0..2)|i|try crozier(b,&k,bole,i);
  // the calyx: sepals cupped round the spindle's foot, opening once the
  // fronds are out
  // the spindle's own branch, rising once the fronds are out
  const spindle=k.branch(bole,1,&.{crown,crown+v3(0.006,0.12,0.004),sheafAt,spindleTop},.{.delay=0.1});
  for(0..sepals)|i|{
    // this sepal's angle round the spindle's foot (radians)
    const a=(m.f(i)+0.3)/sepals*m.tau;
    // where its vertices begin, so it opens in its turn
    const s=b.mark();
    try mg.petal(b,.{
      .base=crown,.out=v3(@cos(a),0,@sin(a)),.len=0.085,.width=0.042,
      .rise=1.0,.flare=0.6,.cup=0.55,.col=pal.core,.tip=pal.leafLite,.t=0.35,.part=.leaf,
    });
    try k.on(b,s,spindle,0,.{.from=crown,.delay=0.02*m.f(i)});
  }
  try k.tube(b,spindle,.{.r0=spindleR,.tip=0.25,.col=pal.rootLite,.sides=5,.t0=0.35,.t1=1});
  // a bud closing the spindle's tip, stamens peeping out of it
  // where the bud's vertices begin, so it closes the tip last
  const bud=b.mark();
  try mg.ellipsoid(b,.{.center=spindleTop,.radii=v3(0.016,0.022,0.016),.col=pal.leafDark,.part=.leaf,.rings=5,.segs=7,.t=1});
  try mg.stamens(b,.{.heart=spindleTop+v3(0,0.014,0),.axis=v3(0,1,0),.n=5,.len=0.04,.r=0.0025,.anther=0.01,.lean=0.4,.arch=0.5,.col=pal.leafLite,.seed=0x10F9});
  try k.on(b,bud,spindle,1,.{});
  k.finish(b);
}
/// one frond: a green rachis arching out of the crown, a pair of leaflets
/// at each step along it, each pair unfolding as the front passes
fn frond(b:*mg.Builder,k:*growth.Skeleton,bole:growth.Id,i:usize)Allocator.Error!void{
  // the frond's control points
  const c=frondCtrl(i);
  // the frond's own branch, rising in its turn
  const id=k.branch(bole,1,&c,.{.delay=frondStagger*m.f(i)});
  try k.tube(b,id,.{.r0=rachisR,.tip=0.2,.col=pal.vine,.sides=5,.t0=0.3,.t1=1});
  // this frond's own seeded rng, so its leaflets are its own
  var rng=Rng.init(0x10FA+i*31);
  for(0..pinnae)|j|{
    // how far along the frond this pair sits (0..1)
    const u=m.lerp(pinnaFrom,0.95,m.ratio(j,pinnae-1));
    // the frond's point there
    const at=k.point(id,u);
    // the frond's direction there
    const tan=k.tangent(id,u);
    // the way out to the frond's side, flat-ish
    const side=m.norm(m.cross(tan,v3(0,1,0)));
    // shortest toward the tip, swept on along the frond
    const len=pinnaLen*(1-0.72*m.smooth(m.ratio(j,pinnae-1)))*rng.range(0.9,1.08);
    // where the pair's vertices begin, so it unfolds as the front passes
    const s=b.mark();
    for([_]f32{1,-1})|sgn|{
      // which way this leaflet points: out to its side, swept on, a little up
      const dir=m.norm(side*m.splat3(sgn)+tan*m.splat3(0.55)+v3(0,0.12,0));
      try mg.natural(b,at,dir,len,pinnaW*(1-0.5*m.ratio(j,pinnae-1)),0.45,pal.leafDark,pal.leafLite,m.lerp(0.3,1,u),.sessile);
    }
    try k.on(b,s,id,u,.{});
  }
}
/// a young frond still rolled up: rising from the crown, its tip coiled
/// into a tight spiral (a crozier), its leaflets furled to nubs along it
fn crozier(b:*mg.Builder,k:*growth.Skeleton,bole:growth.Id,i:usize)Allocator.Error!void{
  // this crozier's heading round the crown (radians), set apart from the other
  const a=(m.f(i)*3.4+1.1);
  // the way out along that heading, flat
  const out=v3(@cos(a),0,@sin(a));
  // the way across, square to it
  const side=m.norm(m.cross(out,v3(0,1,0)));
  // where the coil sits: out a little and up over the crown
  const rise=crown+out*m.splat3(0.035)+v3(0,0.16+0.04*m.f(i),0);
  // the coil: a spiral in the plane of `out` and up, closing as it turns
  const n=10;
  // the control points: two rising out of the crown, then the coil
  var c:[n+2]V3=undefined;
  c[0]=crown+out*m.splat3(0.015);
  c[1]=crown+out*m.splat3(0.03)+v3(0,0.08,0);
  for(0..n)|j|{
    // how far round the coil this point is (0..1)
    const f=m.ratio(j,n-1);
    // its angle round the coil (radians)
    const th=f*1.6*m.tau;
    // its distance from the coil's middle, closing in
    const r=0.04*(1-0.8*f);
    c[j+2]=rise+out*m.splat3(r*@sin(th))+v3(0,r*@cos(th),0)+side*m.splat3(0.004*f);
  }
  // the crozier's own branch, after the fronds
  const id=k.branch(bole,1,&c,.{.delay=frondStagger*fronds+0.04*m.f(i),.pace=1.4});
  // its path, its growth timing and its radius along it
  var sp:[growth.res]V3=undefined;
  var ts:[growth.res]f32=undefined;
  var rs:[growth.res]f32=undefined;
  k.path(id,0,1,&sp);
  for(&ts,&rs,0..)|*t,*r,j|{
    // how far along it this point is (0..1)
    const u=m.ratio(j,growth.res-1);
    t.*=m.lerp(0.3,0.8,u);
    r.*=rachisR*1.1*(1-0.75*u);
  }
  // furled young green, paler at the coil where it is newest
  var cols:[growth.res]color.Rgba8=undefined;
  for(&cols,0..)|*cl,j|cl.*=color.mix(pal.vine,pal.leafLite,m.ratio(j,growth.res-1));
  // where its vertices begin, so stem and nubs grow along it together
  const s=b.mark();
  try b.tubeC(&sp,&ts,&rs,&cols,null,.stem,6);
  // furled leaflets: small nubs along the coil's outside
  for(0..6)|j|{
    // how far along the coil this nub sits (0..1)
    const u=m.lerp(0.35,0.9,m.ratio(j,5));
    // the coil's point there
    const at=k.point(id,u);
    // the coil's girth there, which the nub is sized by
    const r=rachisR*1.1*(1-0.75*u);
    for([_]f32{1,-1})|sgn|{
      try mg.ellipsoid(b,.{.center=at+side*m.splat3(sgn*r*1.3),.radii=m.splat3(r*0.9),.col=pal.leafLite,.part=.leaf,.rings=3,.segs=5,.t=0.8});
    }
  }
  try k.along(b,s,id);
}
/// mesh: LOOMFERN SHEAF. a bundle of fibre a unit `sheafH` tall standing
/// on its middle: strands gathered at the waist by a twist of root, flaring
/// at both ends, each drawn to a point; it forms on the spindle as the fern
/// weaves (the structure grows it by the weave) and is laid at its foot.
pub const sheaf=struct{
  /// builds the sheaf: sixteen strands, each jittered, twisting, gathered at
  /// the waist and flaring to both ends, then a root binding wound round it
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the sheaf's own seeded rng, so every sheaf is bundled alike
    var rng=pal.rngFor("loomfern_sheaf");
    // how many rings run along each strand
    const n=14;
    for(0..sheafStrands)|i|{
      // this strand's angle round the sheaf (radians), jittered
      const a0=(m.f(i)+rng.range(-0.3,0.3))/sheafStrands*m.tau;
      // how far out it flares, as a share of the sheaf's girth
      const ring=rng.range(0.55,1.0);
      // how much it twists from end to end
      const twist=rng.range(0.35,0.55);
      // how far down and up it reaches, each a little short of the full height
      const lo=rng.range(0.85,1.0);
      const hi=rng.range(0.85,1.0);
      // the strand's path, flow, radius and colour, ring by ring
      var path:[n]V3=undefined;
      var ts:[n]f32=undefined;
      var rs:[n]f32=undefined;
      var cols:[n]color.Rgba8=undefined;
      for(&path,&ts,&rs,&cols,0..)|*p,*t,*r,*cl,j|{
        // how far along the strand this ring is (0..1)
        const f=m.ratio(j,n-1);
        // its height on the sheaf, from its lower end to its upper
        const y=m.lerp(-0.5*lo,0.5*hi,f);
        // its distance from the axis: thin at the waist, flaring to the ends
        const flare=m.lerp(sheafWaist,sheafEnd,m.pow(f32,@abs(y)*2,1.6))*ring;
        // its angle round the axis, twisting with height
        const a=a0+twist*y*2;
        p.*=v3(@cos(a)*flare,y*sheafH,@sin(a)*flare);
        t.*=f;
        // drawn to a point at both ends
        r.*=0.0042*@max(@sqrt(@sin(m.pi*f)),0.08);
        cl.*=color.mix(fibreDark,fibreLite,m.clamp01(0.3+0.7*@abs(y)*2*rng.range(0.6,1.0)));
      }
      try b.tubeC(&path,&ts,&rs,&cols,null,.stem,4);
    }
    // the twist of root binding its waist, wound twice round, its ends
    // tucked in under it
    // how many rings run along the binding
    const weftCount=28;
    // the binding's path, flow and radius, ring by ring
    var path:[weftCount]V3=undefined;
    var ts:[weftCount]f32=undefined;
    var rs:[weftCount]f32=undefined;
    for(&path,&ts,&rs,0..)|*p,*t,*r,j|{
      // how far along the binding this ring is (0..1)
      const f=m.ratio(j,weftCount-1);
      // its angle round the waist: just over two turns (radians)
      const a=f*2.1*m.tau;
      // its distance from the axis: just outside the waist
      const rr=sheafWaist*1.25+0.002*@sin(f*m.pi);
      p.*=v3(@cos(a)*rr,(f-0.5)*0.022,@sin(a)*rr);
      t.*=0.5;
      r.*=0.0045*@max(@sqrt(@sin(m.pi*f)),0.15);
    }
    try b.tubeR(&path,&ts,&rs,pal.rootLite,.stem,5);
  }
};
/// mesh: LOOMFERN THREAD. a fibre drawn from a frond's leaflet to the sheaf:
/// built straight up +Y over 0..1 (bent on the GPU along its curve), a
/// strand twisting as it is drawn, as thick at either end (it is drawn
/// from one end and wound in at the other).
pub const thread=struct{
  /// builds the thread: a fine tube up +Y from 0 to 1, spiralling five times
  /// round its line, thinned to a point at both ends, its green banded
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // how many rings run along the thread
    const n=24;
    // the thread's path, flow, radius and colour, ring by ring
    var path:[n]V3=undefined;
    var ts:[n]f32=undefined;
    var rs:[n]f32=undefined;
    var cols:[n]color.Rgba8=undefined;
    for(&path,&ts,&rs,&cols,0..)|*p,*t,*r,*cl,i|{
      // how far along the thread this ring is (0..1)
      const f=m.ratio(i,n-1);
      // how far it spirals off its line: none at the ends, most at the middle
      const w=0.004*@sin(m.pi*f);
      p.*=v3(w*@cos(f*5*m.tau),f,w*@sin(f*5*m.tau));
      t.*=f;
      r.*=@max(0.0032*@sqrt(@sin(m.pi*m.lerp(0.03,0.97,f))),2e-4);
      cl.*=color.mix(fibre,fibreLite,0.5+0.5*@sin(f*9));
    }
    try b.tubeC(&path,&ts,&rs,&cols,null,.stem,4);
  }
};
