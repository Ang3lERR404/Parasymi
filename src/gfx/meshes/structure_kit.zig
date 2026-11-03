//! the symbiotic lineage's body: shared pieces for grown structures, in
//! the plants' language (a woven root mat they rise from, grown vines with
//! leaves along them, and pods of the wolf's resin sap, dense at the base,
//! see-through toward the top, with no light of its own), and its plants
//! built of the same (`plant`, the `herb` form). Not a mesh itself; the
//! structure meshes use it. Given an `On`, a piece grows on a structure's
//! growth splines (gfx/growth.zig) instead of with the structure as a
//! whole; a plant grows by tu.x (plant.vert).
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error the builder may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, splines, easing
const m=engine.core.math;
/// the mesh builder and its primitives
const mg=lib.meshgen;
/// the shared swatches: wood, vine, leaves, roots, sap
const pal=lib.palette;
/// colour conversions, for shading a genome's colours
const color=engine.core.color;
/// the engine's deterministic random stream
const Rng=engine.core.rng.Rng;
/// the garden's growth timing: skeletons, splines, branches
const growth=lib.growth;
/// the species registry, whose genomes shape a plant
const species=lib.species;
/// a point or direction in space
const V3=m.V3;
/// makes a vector from three numbers
const v3=m.v3;
/// where a piece grows: off spline `id` of skeleton `k`, `u` along it
pub const On=struct{
  /// the structure's skeleton the piece is timed along
  k:*growth.Skeleton,
  /// the spline on it the piece grows off
  id:growth.Id,
  /// how far along that spline, 0 its root .. 1 its tip
  u:f32=0,
};
/// `n` braided roots radiating from the centre out to `reach`, hugging the
/// ground and sinking into it at their ends, each `girth` thick at its root.
/// On a spline, each root is a branch off it growing with it.
pub fn rootMat(b:*mg.Builder,n:u32,reach:f32,girth:f32,seed:u64,on:?On)Allocator.Error!void{
  // the mat's own random stream
  var rng=Rng.init(seed);
  for(0..n)|i|{
    // this root's bearing, where it leaves the centre and where it sinks
    const a=(m.f(i)+rng.range(-0.25,0.25))/m.f(n)*m.tau;
    const from=v3(@cos(a)*0.08,0.06,@sin(a)*0.08);
    const to=v3(@cos(a)*reach*rng.range(0.8,1.05),-0.04,@sin(a)*reach*rng.range(0.8,1.05));
    // its control points
    var c:[6]V3=undefined;
    mg.growthPath(.{.start=from,.direction=m.norm(to-from),.length=m.dist(to,from),.wobble=0.25,.seed=seed+%i*41},&c);
    if(on)|o|{
      // its branch on the skeleton, growing with the spline it leaves
      const root=o.k.branch(o.id,o.u,&c,.{.after=.with});
      try o.k.braid(b,root,.{.girth=girth,.wobble=pal.strandWobble,.seed=seed+%i*7,.core=pal.core,.strand=pal.vine,.t0=0.05});
      continue;
    }
    // the root resampled smooth
    var p:[12]V3=undefined;
    m.splineResample(&c,&p);
    // each point's growth stamp and radius
    var ts:[12]f32=undefined;
    var rs:[12]f32=undefined;
    for(&ts,&rs,0..)|*t,*r,j|{
      // how far out along the root, 0..1
      const k=m.ratio(j,11);
      t.*=0.05*(1-k);
      r.*=girth*m.lerp(1,0.35,k);
    }
    try mg.braid(b,&p,&ts,&rs,3,2.2,pal.strandWobble,seed+%i*7,pal.core,pal.vine);
  }
}
/// a grown vine from `from` toward `to`, tapering from `r0`, curling by
/// `curl`, with `leaves` small leaves along it, growing over `t0`..`t1`.
/// On a spline, it is a branch off it (grown once that is done, `from`
/// moved onto it), its leaves opening as it passes them.
pub fn leafyVine(b:*mg.Builder,from:V3,to:V3,r0:f32,curl:f32,leaves:u32,t0:f32,t1:f32,seed:u64,on:?On)Allocator.Error!void{
  // how the vine grows: from `from` toward `to`, wavering and curling
  const g:mg.Growth=.{.start=from,.direction=m.norm(to-from),.length=m.dist(to,from),.wobble=0.18,.curl=curl,.seed=seed};
  if(on)|o|{
    // its branch on the skeleton
    const vine=o.k.vine(o.id,o.u,g,7,.{});
    try o.k.tube(b,vine,.{.r0=r0,.col=pal.vine,.sides=5,.t0=t0,.t1=t1});
    try o.k.leaves(b,vine,.{.n=leaves,.len=0.18,.width=0.06,.t0=t0,.t1=t1,.col=pal.leafDark,.tip=pal.leafLite,.seed=seed+%3});
    return;
  }
  // its control points, and the vine resampled smooth
  var c:[7]V3=undefined;
  mg.growthPath(g,&c);
  var p:[18]V3=undefined;
  m.splineResample(&c,&p);
  // each point's growth stamp and radius
  var ts:[18]f32=undefined;
  var rs:[18]f32=undefined;
  mg.taperRadii(r0,0.3,&rs);
  for(&ts,0..)|*t,j|t.*=m.lerp(t0,t1,m.ratio(j,17));
  try b.tubeR(&p,&ts,&rs,pal.vine,.stem,5);
  try mg.leavesAlong(b,&p,leaves,0.18,0.06,0.15,0.85,t0,t1,pal.leafDark,pal.leafLite,seed+%3);
}
/// how much later each foot leaf unfolds than the one before (a share of
/// the whole growth)
const footStagger:f32=0.025;
/// a pod of resin sap: tu.y runs from its dense base (0) to its thin
/// crown (1), which the resin shading reads.
pub fn resinPod(b:*mg.Builder,center:V3,radii:V3,rings:u32,segs:u32)Allocator.Error!void{
  // where the pod's vertices begin
  const start=b.mark();
  try mg.ellipsoid(b,.{.center=center,.radii=radii,.col=pal.sap,.part=.resin,.rings=rings,.segs=segs,.t=0.6});
  for(b.v.items[start..])|*vx|vx.tu[1]=m.clamp01((vx.pos[1]-(center[1]-radii[1]))/(2*radii[1]));
}
/// `n` broad leaves in a ring `r` out at the foot, all on one envelope.
/// On a spline, they unfold from their bases one after another as its
/// front passes.
pub fn footLeaves(b:*mg.Builder,n:u32,r:f32,len:f32,width:f32,seed:u64,on:?On)Allocator.Error!void{
  // the ring's own random stream
  var rng=Rng.init(seed);
  for(0..n)|i|{
    // this leaf's bearing, the way it lies (out, a little up), and its base
    const a=(m.f(i)+rng.range(-0.2,0.2))/m.f(n)*m.tau;
    const dir=m.norm(v3(@cos(a),0.25,@sin(a)));
    const base=v3(@cos(a)*r,0.08,@sin(a)*r);
    // where its vertices begin
    const s=b.mark();
    try mg.natural(b,base,dir,len*rng.range(0.85,1.1),width,0.7,pal.leafDark,pal.leafLite,0.4,.stalked);
    if(on)|o|try o.k.on(b,s,o.id,o.u,.{.from=base,.delay=footStagger*m.f(i)});
  }
}
/// a root grown from `from` along `dir` (heading down into the soil),
/// `len` long, tapering from `r0` to a hair, with two forks splitting off
/// its far half.
pub fn rootlet(b:*mg.Builder,from:V3,dir:V3,len:f32,r0:f32,seed:u64)Allocator.Error!void{
  // the rootlet's own random stream
  var rng=Rng.init(seed);
  // its control points, and the root resampled smooth
  var c:[6]V3=undefined;
  mg.growthPath(.{.start=from,.direction=dir,.length=len,.wobble=0.35,.seed=seed},&c);
  var p:[12]V3=undefined;
  m.splineResample(&c,&p);
  // each point's growth stamp and radius
  var ts:[12]f32=undefined;
  var rs:[12]f32=undefined;
  mg.taperRadii(r0,0.12,&rs);
  for(&ts,0..)|*t,j|t.*=m.ratio(j,11)*0.3;
  try b.tubeR(&p,&ts,&rs,pal.rootBark,.stem,5);
  for(0..2)|f|{
    // the point the fork leaves from, and the flat direction across the root
    const k:usize=4+f*3;
    const side=m.norm(m.cross(dir,v3(0,1,0)));
    // which side it forks to, and the way it heads (out and down)
    const sgn:f32=if(f==0)1 else-1;
    const fd=m.norm(dir+side*m.splat3(sgn*rng.range(0.5,0.9))+v3(0,-0.2,0));
    // the fork's control points, and the fork resampled smooth
    var fc:[4]V3=undefined;
    mg.growthPath(.{.start=p[k],.direction=fd,.length=len*rng.range(0.35,0.5),.wobble=0.4,.seed=seed+%f*13},&fc);
    var fp:[8]V3=undefined;
    m.splineResample(&fc,&fp);
    // each point's growth stamp and radius
    var ft:[8]f32=undefined;
    var fr:[8]f32=undefined;
    mg.taperRadii(rs[k]*0.75,0.15,&fr);
    for(&ft)|*t|t.*=ts[k];
    try b.tubeR(&fp,&ft,&fr,pal.rootBark,.stem,4);
  }
}
/// the lineage's braid: how far a strand turns round its stem per unit of
/// the stem's length per unit of its radius (a germinator trunk's pitch),
/// so thin stems and thick trunks wind alike
const pitch:f32=0.46;
/// a stem thicker than this braids six strands round its core, else four
const thick:f32=0.1;
/// braided roots a rooted symbiote spreads into the soil
const roots=5;
/// how many young leaves stand folded round a plant's crown
const crownLeaves=3;
/// the longest leaf (m) still cut with teeth: longer ones (a tree's) are smooth-edged
const toothedUpTo:f32=0.45;
/// a point `k` up a stem (`spine`, its `radii`), pushed out toward its skin
/// along bearing `a`: where a leaf's stalk leaves it
fn onStem(spine:[]const V3,radii:[]const f32,k:f32,a:f32)V3{
  // the stem's ring nearest that height, for its radius
  const ri:usize=@intFromFloat(m.clamp(k,0,1)*m.f(radii.len-1));
  return m.alongPath(spine,k)+v3(@cos(a),0,@sin(a))*m.splat3(radii[ri]*0.8);
}
/// a symbiote (the `herb` form) grown from its genome, in the lineage's
/// body: a braided stem, strands wound tight round a darker core, each a
/// little different, flaring into a mat of braided roots sinking into the
/// soil (`rooted`), a rosette of broad leaves at its foot, leafy vines
/// twining up it, leaves up it on one envelope, braided offshoots ending in
/// buds or small blooms, and its bloom opening out of a bead of resin sap
/// held in a cup of sepals. Grown by tu.x (plant.vert); deterministic per
/// `seed` and `variant`.
pub fn plant(b:*mg.Builder,g:species.Genome,seed:u64,variant:u32,rooted:bool)Allocator.Error!void{
  // the plant's own random stream
  var rng=Rng.init(seed);
  // the genome's strand colour, and the darker core they wind round
  const strand=g.stemCol.toRgba8(255);
  const core=color.shade(g.stemCol,0.55);
  // its leaves' shaded base, and their true colour at the tips
  const leaf=color.shade(g.leafCol,0.6);
  const leafTip=g.leafCol.toRgba8(255);
  // the leaves' stalks; the yellower green old leaves age to; a young
  // leaf's fresh tip
  const stalk=color.shade(g.stemCol,0.8);
  const aged=color.rgb(0.55,0.66,0.26);
  const youngTip=color.rgb(0.6,0.95,0.5).toRgba8(255);
  // a herb's leaves are toothed; a tree's broad ones smooth-edged (1, 0)
  const teeth:f32=if(g.leafLen>toothedUpTo)0 else 1;
  // the stem: a grown vine rising from the root, flaring where it meets
  // the ground so it grows out of the soil rather than standing on it
  const res=32;
  // how it leans off upright, and how it grows
  const lean=v3(rng.range(-0.08,0.08),1,rng.range(-0.08,0.08));
  const stem:mg.Growth=.{
    .start=v3(0,0,0),.direction=m.norm(lean),.length=g.stemH,
    .wobble=g.wobble,.curl=g.curl,.taper=0.35,.seed=seed^0x57E4,
  };
  // its control points (room for the most segments), and how many it uses
  var ctrl:[17]V3=undefined;
  const cn=@as(usize,@max(@min(g.segments,16),3))+1;
  mg.growthPath(stem,ctrl[0..cn]);
  // the stem resampled smooth
  var spine:[res]V3=undefined;
  m.splineResample(ctrl[0..cn],&spine);
  // each point's growth stamp and radius
  var ts:[res]f32=undefined;
  var radii:[res]f32=undefined;
  mg.taperRadii(g.stemR,stem.taper,&radii);
  for(&ts,&radii,0..)|*t,*r,i|{
    // how far up the stem, 0 foot .. 1 crown
    const k=m.ratio(i,res-1);
    t.*=k;
    if(rooted){
      // how near the foot, 1 at the ground: the flare swells sharply there
      const low=1-k;
      r.* *= 1+0.9*low*low*low*low*low*low;
    }
  }
  // how many strands its braid has
  const strands:u32=if(g.stemR>thick)6 else 4;
  try mg.braid(b,&spine,&ts,&radii,strands,pitch*g.stemH/g.stemR,pal.strandWobble,seed^0xB4A1,core,strand);
  if(rooted){
    // the root mat: braided roots leaving the flare, arching down to hug
    // the ground and sinking into it at their ends
    for(0..roots)|i|{
      // this root's bearing, the flat way out along it, and how far it reaches
      const a=(m.f(i)+rng.range(-0.25,0.25))/roots*m.tau+m.f(variant);
      const out=v3(@cos(a),0,@sin(a));
      const reach=g.stemR*rng.range(9,12);
      // its control points: an arch from the flare down into the ground
      var c:[6]V3=undefined;
      for(&c,0..)|*p,j|{
        // how far out along the root, 0..1
        const s=m.ratio(j,c.len-1);
        p.*=out*m.splat3(m.lerp(g.stemR*0.6,reach,s))+v3(0,g.stemR*(2*(1-s)*(1-s)+0.3*s*(1-s)-s*s),0);
      }
      mg.grow(&c,.{.start=c[0],.direction=m.norm(c[5]-c[0]),.length=m.dist(c[5],c[0]),.wobble=0.25,.seed=seed+%i*41});
      // the root resampled smooth
      var p:[12]V3=undefined;
      m.splineResample(&c,&p);
      // each point's growth stamp and radius
      var rt:[12]f32=undefined;
      var rr:[12]f32=undefined;
      for(&rt,&rr,0..)|*t,*r,j|{
        // how far out along the root, 0..1
        const k=m.ratio(j,11);
        t.*=0.04*(1-k);
        r.*=g.stemR*0.7*m.lerp(1,0.35,k);
      }
      try mg.braid(b,&p,&rt,&rr,3,2.2,pal.strandWobble,seed+%i*7,core,strand);
    }
    // the rosette: broad old leaves sprawling low round the foot on short
    // stalks, each its own size, toothed, twisted and rippled, yellower
    // than the young growth above; unfolding first
    for(0..g.rosette)|i|{
      // this leaf's bearing, and the stem's skin there
      const a=(m.f(i)+rng.range(-0.3,0.3))/m.f(g.rosette)*m.tau+m.f(variant)*0.7+0.5;
      const at=v3(@cos(a)*g.stemR*1.2,g.stemR*1.5,@sin(a)*g.stemR*1.2);
      try mg.leaf(b,.{
        .at=at,.dir=m.norm(v3(@cos(a),rng.range(-0.15,0.1),@sin(a))),
        .len=g.leafLen*rng.range(0.95,1.45),.width=g.leafW*rng.range(1.15,1.5),.droop=rng.range(0.45,0.7),.curl=rng.range(0,0.15),
        .twist=rng.range(-0.5,0.5),.wave=rng.range(0.12,0.25),.teeth=teeth*rng.range(5,7),.stalk=rng.range(0.2,0.35),
        .col=color.shade(aged,0.6),.tip=color.mix(aged.toRgba8(255),leafTip,rng.range(0,0.5)),.stalkCol=stalk,.t=0.02,
      });
    }
  }
  // leafy vines twining up the stem from its foot, rooted at it and
  // tapering to a point at both ends, small leaves along them
  for(0..g.vines)|vi|{
    // its control points, and the rings it is drawn with
    const steps=10;
    const veinRings=28;
    // where up the stem it starts and ends (0..1), and how many turns it makes
    const k0:f32=0.03;
    const k1=rng.range(0.55,0.7);
    const turns=rng.range(1.2,1.6);
    // its starting bearing, and its radius
    const a0=m.f(vi)/m.f(g.vines)*m.tau+rng.float()*m.tau;
    const vr=g.stemR*0.32;
    // its control points, wound round the stem just off its surface
    var c:[steps]V3=undefined;
    for(&c,0..)|*p,j|{
      // how far along the vine, how far up the stem, and its bearing there
      const s=m.ratio(j,steps-1);
      const k=m.lerp(k0,k1,s);
      const a=a0+s*turns*m.tau;
      // the stem's ring nearest that height, for its radius
      const ri:usize=@intFromFloat(k*(res-1));
      p.*=m.alongPath(&spine,k)+v3(@cos(a),0,@sin(a))*m.splat3(radii[ri]*1.05+vr);
    }
    mg.grow(&c,.{.start=c[0],.direction=m.norm(c[steps-1]-c[0]),.length=m.dist(c[steps-1],c[0]),.wobble=0.06,.seed=seed+%vi*83});
    // the vine resampled smooth
    var p:[veinRings]V3=undefined;
    m.splineResample(&c,&p);
    // each point's growth stamp and radius
    var vt:[veinRings]f32=undefined;
    var vs:[veinRings]f32=undefined;
    for(&vt,&vs,0..)|*t,*r,j|{
      // how far along the vine, 0..1
      const s=m.ratio(j,veinRings-1);
      t.*=m.lerp(k0,k1,s);
      r.*=@max(vr*@sqrt(@sin(m.pi*s)),2e-4);
    }
    try b.tubeR(&p,&vt,&vs,color.mix(strand,leafTip,0.25),.stem,5);
    try mg.leavesAlong(b,&p,4,g.leafLen*0.4,g.leafW*0.55,0.2,0.9,k0,k1,leaf,leafTip,seed+%vi*29);
  }
  // leaves up the stem on their own stalks, a golden angle round from the
  // last (strayed): biggest and drooping most low down, smaller toward the
  // crown, each its own size, droop, twist and ripple, toothed, the tips
  // curling; the low ones yellower with age
  const from=g.leafFrom;
  for(0..g.leaves)|i|{
    // how far up the leaves (0..1), and how far up the stem this one sits
    const up=m.ratio(i,@max(g.leaves,1)-1);
    const k=m.clamp(m.lerp(@max(from-0.08,0.1),0.88,up)+rng.range(-0.02,0.02),0.02,0.95);
    // its bearing
    const ang=m.f(i)*m.goldenAngle+m.f(variant)+rng.range(-0.35,0.35);
    try mg.leaf(b,.{
      .at=onStem(&spine,&radii,k,ang),.dir=m.norm(v3(@cos(ang),m.lerp(0.05,0.5,up)+rng.range(-0.1,0.1),@sin(ang))),
      .len=g.leafLen*m.lerp(1.35,0.5,up)*rng.range(0.75,1.3),.width=g.leafW*m.lerp(1.3,0.85,up)*rng.range(0.8,1.15),
      .droop=g.leafDroop*m.lerp(1.5,0.6,up)*rng.range(0.7,1.3),.curl=rng.range(0,0.25),.twist=rng.range(-0.7,0.7),
      .wave=rng.range(0.05,0.18),.teeth=teeth*rng.range(4,6),.stalk=rng.range(0.25,0.45),
      .col=leaf,.tip=color.mix(aged.toRgba8(255),leafTip,m.lerp(0.4,1,up)),.stalkCol=stalk,.t=k,
    });
  }
  // young leaves at the crown, still folded, standing up round the bloom
  for(0..crownLeaves)|i|{
    // its bearing
    const ang=m.f(i)/crownLeaves*m.tau+rng.range(-0.4,0.4);
    try mg.leaf(b,.{
      .at=onStem(&spine,&radii,0.93,ang),.dir=m.norm(v3(@cos(ang),1.6,@sin(ang))),
      .len=g.leafLen*rng.range(0.3,0.42),.width=g.leafW*0.7,.droop=0.05,.twist=rng.range(-0.4,0.4),.open=0.4,
      .col=color.shade(g.leafCol,0.7),.tip=color.mix(leafTip,youngTip,0.6),.stalkCol=stalk,.t=0.9,
    });
  }
  // thorns: small, short, pressed to the stem
  for(0..g.thorns)|i|{
    // how far up the stem, and the thorn's bearing
    const k=0.15+0.7*rng.float();
    const ang=m.f(i)*m.goldenAngle*1.3;
    try b.cone(m.alongPath(&spine,k),m.norm(v3(@cos(ang),0.4,@sin(ang))),0.045,0.01,color.shade(g.bloomCol,0.7),k,.thorn);
  }
  // prop roots: braided, from low on the stem down into the soil close
  // round the foot, small leaves along them
  const prop=m.alongPath(&spine,0.2);
  for(0..g.tendrils)|i|{
    // this root's bearing, how far out it lands, and the way down to there
    const ang=m.ratio(i,g.tendrils)*m.tau+0.4+0.3*m.f(variant);
    const spread=g.stemR*3+g.stemH*0.12;
    const reach=v3(@cos(ang)*spread,-prop[1]*0.98,@sin(ang)*spread);
    // its control points
    var tc:[7]V3=undefined;
    mg.growthPath(.{
      .start=prop,.direction=m.norm(reach),.length=m.len(reach),
      .wobble=g.tendrilWobble,.curl=g.tendrilCurl,.seed=seed+%i*31,
    },&tc);
    // the root resampled smooth
    var tp:[20]V3=undefined;
    m.splineResample(&tc,&tp);
    // each point's growth stamp and radius
    var tt:[20]f32=undefined;
    var tr:[20]f32=undefined;
    mg.taperRadii(g.stemR*0.4,0.3,&tr);
    for(&tt,0..)|*t,j|t.*=m.lerp(0.2,0.05,m.ratio(j,19));
    try mg.braid(b,&tp,&tt,&tr,3,2.4,pal.strandWobble,seed+%i*17,core,strand);
    try mg.leavesAlong(b,&tp,3,g.leafLen*0.4,g.leafW*0.55,0.12,0.6,0.2,0.05,leaf,leafTip,seed+%i*13);
  }
  // offshoots: braided side stems leaving the main one between the
  // leaves, each curving up to the light and ending in a bud or a small
  // bloom; they come up pressed to the stem (meshgen `shootFold`)
  const shootR=g.stemR*0.55;
  // (below a tree's crown too: they branch from the trunk)
  const shootFrom=@max(from*0.6,0.3);
  // the offshoots' own random stream, and how many there are
  var srng=Rng.init(seed^0x0FF5);
  const shoots=mg.shootCount(g,&srng);
  for(0..shoots)|i|{
    // how far up the stem it leaves, its bearing, and its length
    const k=m.lerp(shootFrom,0.85,(m.f(i)+srng.range(0.2,0.8))/m.f(shoots));
    const ang=m.f(i)*m.goldenAngle*1.7+1.1+m.f(variant)*0.9+srng.range(-0.3,0.3);
    const len=g.stemH*srng.range(0.32,0.46)*m.lerp(1.15,0.75,k);
    // its path, timing, and the tip and axis its bud or bloom sits on
    const sh=mg.shootPath(&spine,k,k,ang,len,srng.range(0.3,0.6),seed+%i*211);
    // each point's growth stamp and radius
    var st:[mg.shootRes]f32=undefined;
    var sr:[mg.shootRes]f32=undefined;
    for(&st,&sr,0..)|*t,*r,j|{
      // how far along the offshoot, 0..1
      const s=m.ratio(j,mg.shootRes-1);
      t.*=m.lerp(sh.t0,sh.t1,s);
      r.*=shootR*m.lerp(1,0.55,s)*mg.collar(s);
    }
    // where the offshoot's braid begins
    const s0=b.mark();
    try mg.braid(b,&sh.path,&st,&sr,3,pitch*len/shootR,pal.strandWobble,seed+%i*101,core,strand);
    mg.shootFoldNearest(b,s0,&sh.path);
    // where its leaves begin
    const lv=b.mark();
    try mg.leavesAlong(b,&sh.path,2,g.leafLen*0.45,g.leafW*0.6,0.25,0.7,sh.t0,sh.t1,leaf,leafTip,seed+%i*59);
    mg.shootFoldAlong(b,lv,&sh.path);
    // where its bud or bloom begins
    const s=b.mark();
    if(srng.float()<0.5)
      try mg.flower(b,g,sh.at,sh.axis,srng.range(0.55,0.7),m.f(variant)+m.f(i),sh.t1,.{.resin=pal.sap})
    else
      try mg.bud(b,g,sh.at,sh.axis,srng.range(0.65,0.85),m.f(i)*1.3,sh.t1);
    mg.shootFold(b,s,1);
  }
  // its yield: pods hanging from the stem where the paws pluck it, each
  // on a short stalk out of the braid, a golden angle round from the last
  for(0..g.pods)|k|{
    // how far up the stem it hangs (a little apart from its neighbour), its bearing and the way out
    const pk=g.podAt+0.04*(m.f(k%2)-0.5);
    const ang=mg.pods.bearing(k,variant);
    const out=v3(@cos(ang),0,@sin(ang));
    // the stem's ring nearest that height, for its radius
    const ri:usize=@intFromFloat(pk*(res-1));
    _=try mg.pods.hanging(b,g,k,m.alongPath(&spine,pk)+out*m.splat3(radii[ri]*0.85),out,g.podR*0.5,strand,pk);
  }
  // the bloom: its bead of resin in the cup of sepals, the petals rising
  // from its crown
  try mg.flower(b,g,spine[res-1],m.norm(spine[res-1]-spine[res-4]),1,m.f(variant),1,.{.resin=pal.sap});
}
