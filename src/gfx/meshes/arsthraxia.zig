//! mesh: ARSTHRAXIA. a bloom that studies: three braided stems rise out of
//! a root mat and twine round one another, part into an open cage round a
//! pod of resin threaded on a nerve, and gather again in a calyx under its
//! flower, over which its core of research energy condenses. Down the
//! middle of every stem runs a nerve (part `.nerve`) showing between its
//! strands: thought climbs it while it studies (part.vert).
//! The structure emits the rest, each built here in its own space: the
//! flower's two whorls (`whorl`, `cup`), turning while it studies; the
//! satellite saps (`satellite`), the core (`core`) and the wisps drawn
//! into it (`wisp`); and what research grows on it: the vines climbing its
//! stems (`vines`, Arsthraxia) and its offshoots (`shoot`, the minor
//! studies). `whole` is it at rest with its flower: the placement preview.
//! All grow on hidden growth splines (gfx/growth.zig): the stems with
//! their roots, leaves unfolding up them, the cage's tendrils and pod, the
//! calyx; then (`form`) the whorls open, petal after petal, and last
//! (`coreForm`) the core.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, the builder underneath
const engine=lib.engine;
/// all the maths: vectors, matrices, splines
const m=engine.core.math;
/// the plant-piece mesher: braids, petals, stamens, bands, the builder itself
const mg=lib.meshgen;
/// the garden's palette: vine, leaves, strand wobble
const pal=lib.palette;
/// colour conversions, for the petals' violets
const color=engine.core.color;
/// the structure kit: root mats, foot leaves and resin pods
const kit=lib.structureKit;
/// the garden's growth timing: the hidden splines it grows along
const growth=lib.growth;
/// a point or direction in space
const V3=m.V3;
/// makes a point in space from three numbers
const v3=m.v3;
/// how tall it stands to its flower's heart
pub const height:f32=1.55;
/// the flower's heart, where its whorls turn
pub const heartAt=v3(0,height-0.02,0);
/// how many braided stems rise and twine
pub const stemCount=3;
/// the petals' deep violet heart
const petalHeart=color.rgb(0.30,0.22,0.46);
/// the paler lilac their rims turn to
const petalRim=color.rgb(0.62,0.5,0.86);
/// the pale lilac of its stamens
pub const stamen=color.rgb(0.8,0.74,0.9);
/// a nerve at rest: dark wood with a violet cast
pub const nerve=color.rgb(0.2,0.15,0.24).toRgba8(255);
/// research energy is light: white under the shading's own colours
const energyWhite=color.rgb(1,1,1).toRgba8(255);
/// the last share of its growth, its stems grown, over which its whorls
/// open (they are emitted, so carry it in their vertices) ...
pub const form:f32=0.3;
/// ... and the end of it, over which the core and its satellites form
/// (placed by the structure: `growth.formed`)
pub const coreForm:f32=0.12;
/// how long a petal of the whorls takes to open (a share of the whole
/// growth)
pub const petalOpen:f32=0.1;
/// how much later each petal of the whorls opens than the one before
pub const whorlStagger:f32=0.005;
/// likewise an offshoot's satellite, over the last of the offshoot's growth
pub const shootForm:f32=0.3;
/// the stems grow this slowly per unit of their length
pub const stalkPace:f32=1.2;
/// how much later each sepal or petal opens than the one before (a share
/// of the skeleton's time)
pub const petalStagger:f32=0.025;
/// a stem's course, from the root mat's heart: (height, out from the axis,
/// how far it has wound round it) at each control point. It flares out of
/// the roots, twines tight with the others, parts into the cage and
/// gathers again under the flower.
pub const stemAt=[_][3]f32{
  .{0.0,0.0,0.0},.{0.12,0.13,0.15},.{0.35,0.085,0.95},.{0.6,0.075,1.95},
  .{0.84,0.09,2.9},.{1.02,0.21,3.45},.{1.17,0.26,3.75},.{1.32,0.2,4.0},
  .{1.44,0.08,4.15},.{height-0.04,0.02,4.2},
};
/// where the cage is widest: the resin pod's height
pub const cageY:f32=1.17;
/// the pod's half-sizes along x, y and z
const podR=v3(0.1,0.13,0.1);
/// where up the stems the foot leaves unfold (0..1)
const footAt:f32=0.06;
/// stem `k`'s starting heading round the axis (radians), evenly spread
pub fn stemAngle(k:usize)f32{return m.ratio(k,stemCount)*m.tau;}
/// its nerve's tu.x at a height: 0 at its roots .. 1 at its flower
pub fn nerveAt(y:f32)f32{return m.clamp01(y/height);}
/// builds it alone, as the structure grows it: its whorls and core are emitted
pub fn build(b:*mg.Builder)Allocator.Error!void{try stand(b);}
/// lays the whole stand on one growth skeleton: three stems, the root mat
/// and foot leaves, a tendril off each stem, the cage and the calyx,
/// leaving the last `form` of the growth for the emitted whorls
fn stand(b:*mg.Builder)Allocator.Error!void{
  // the growth skeleton the whole stand is hung on
  var sk=growth.Skeleton.begin(b);
  sk.tail=form;
  // the three stems' splines, the first the trunk the rest hang on
  var stems:[stemCount]growth.Id=undefined;
  for(&stems,0..)|*id,k|id.*=try stem(b,&sk,if(k==0)null else stems[0],k);
  try kit.rootMat(b,8,1.0,0.075,0x7B01,.{.k=&sk,.id=stems[0]});
  try kit.footLeaves(b,7,0.27,0.5,0.18,0x7B02,.{.k=&sk,.id=stems[0],.u=footAt});
  for(stems,0..)|id,k|try tendril(b,&sk,id,k);
  try cage(b,&sk,stems[0]);
  try calyx(b,&sk,stems[0]);
  sk.finish(b);
}
/// stem `k`: a braid of five strands round its nerve along its course
/// (the first is the trunk; the others grow with it from the same root),
/// a few leaves along its twined stretch
fn stem(b:*mg.Builder,sk:*growth.Skeleton,first:?growth.Id,k:usize)Allocator.Error!growth.Id{
  // this stem's starting heading (radians)
  const a0=stemAngle(k);
  // its control points, laid from `stemAt` round its heading
  var ctrl:[stemAt.len]V3=undefined;
  for(&ctrl,stemAt)|*c,p|c.*=v3(@cos(a0+p[2])*p[1],p[0],@sin(a0+p[2])*p[1]);
  // where it gathers under the flower, kept through the wobble
  const top=ctrl[ctrl.len-1];
  mg.grow(&ctrl,.{.start=ctrl[0],.direction=v3(0,1,0),.length=height,.wobble=0.05,.seed=0x7B10+%k*31});
  // it gathers with the others under the flower, where it was laid
  ctrl[ctrl.len-1]=top;
  // its spline: the trunk, or a branch growing with it from the root
  const id=if(first)|f|sk.branch(f,0,&ctrl,.{.after=.with,.pace=stalkPace})else sk.trunk(&ctrl,.{.pace=stalkPace});
  // how many rings run along the stem
  const steps=growth.res;
  // its resampled points
  const path=&sk.get(id).pts;
  // each ring's nerve tu, radius and how far its strands have turned
  var ts:[steps]f32=undefined;
  var rs:[steps]f32=undefined;
  var turn:[steps]f32=undefined;
  for(&ts,&rs,&turn,path,0..)|*t,*r,*a,p,i|{
    // how far along the stem this ring is (0..1)
    const u=m.ratio(i,steps-1);
    t.*=nerveAt(p[1]);
    r.*=0.06*(1+0.55*@exp(-u*12))*m.lerp(1,0.55,u);
    a.*=u*3.4+m.f(k);
  }
  // where the braid's vertices begin, so it rises along the stem
  const s=b.mark();
  try mg.braidAround(b,path,&ts,&rs,&turn,5,pal.strandWobble,0x7B20+%k*7,nerve,pal.vine,.nerve);
  try sk.along(b,s,id);
  try sk.leaves(b,id,.{.n=3,.len=0.3,.width=0.1,.from=0.15,.to=0.48,.t0=0.1,.t1=0.5,.col=pal.leafDark,.tip=pal.leafLite,.seed=0x7B30+%k*11});
  return id;
}
/// off stem `k` where the cage is widest, a tendril reaching out and up,
/// curling at its tip, two leaves along it
fn tendril(b:*mg.Builder,sk:*growth.Skeleton,id:growth.Id,k:usize)Allocator.Error!void{
  // this tendril's heading: the stem's own where the cage is widest
  const a=stemAngle(k)+stemAt[6][2];
  // how far along the stem that widest point is (0..1)
  const u=sk.nearest(id,v3(@cos(a)*stemAt[6][1],stemAt[6][0],@sin(a)*stemAt[6][1]));
  // the way out along that heading, flat
  const out=v3(@cos(a),0,@sin(a));
  // the way across the heading, flat
  const side=v3(-out[2],0,out[0]);
  // the tendril's own vine off the stem
  const t=sk.vine(id,u,.{.start=undefined,.direction=m.norm(out+side*m.splat3(0.4)+v3(0,0.55,0)),.length=0.42,.wobble=0.15,.curl=0.45,.seed=0x7B40+%k*13},7,.{.after=.passing});
  try sk.tube(b,t,.{.r0=0.016,.tip=0.05,.col=pal.vine,.sides=5,.t0=0.75,.t1=0.95});
  try sk.leaves(b,t,.{.n=2,.len=0.15,.width=0.055,.from=0.2,.to=0.6,.t0=0.75,.t1=0.95,.col=pal.leafDark,.tip=pal.leafLite,.seed=0x7B48+%k*5});
}
/// inside the cage: a nerve rising up its middle from the trunk to the
/// flower's heart, a pod of resin threaded on it where the cage is widest
fn cage(b:*mg.Builder,sk:*growth.Skeleton,trunk:growth.Id)Allocator.Error!void{
  // how many rings run along the nerve
  const steps=growth.res;
  // where up the trunk the nerve leaves it (0..1)
  const from=sk.nearest(trunk,v3(0,stemAt[4][0]-0.06,0));
  // the nerve's own spline, up the cage's middle to under the heart
  const id=sk.branch(trunk,from,&.{v3(0,0,0),v3(0,0.95,0),v3(0,cageY,0),v3(0,heartAt[1]-0.03,0)},.{.after=.passing});
  // its resampled points
  const path=&sk.get(id).pts;
  // each ring's nerve tu and radius, pointed at both ends
  var ts:[steps]f32=undefined;
  var rs:[steps]f32=undefined;
  for(&ts,&rs,path,0..)|*t,*r,p,i|{
    // how far along the nerve this ring is (0..1)
    const u=m.ratio(i,steps-1);
    t.*=nerveAt(p[1]);
    r.*=@max(0.017*m.pow(f32,@sin(m.pi*u),0.4),2e-4);
  }
  // where the nerve's vertices begin, so it rises along its spline
  const s=b.mark();
  try b.tubeR(path,&ts,&rs,nerve,.nerve,6);
  try sk.along(b,s,id);
  // where the pod sits, threaded on the nerve
  const at=v3(0,cageY,0);
  // where the pod's vertices begin, so it swells as the nerve passes
  const p=b.mark();
  try kit.resinPod(b,at,podR,10,14);
  try sk.on(b,p,id,sk.nearest(id,at),.{.from=at});
}
/// the calyx the stems gather into: sepals cupped up under the flower
fn calyx(b:*mg.Builder,sk:*growth.Skeleton,trunk:growth.Id)Allocator.Error!void{
  // where the sepals spring from, just under the flower's heart
  const heart=heartAt-v3(0,0.05,0);
  for(0..5)|i|{
    // this sepal's angle round the heart (radians)
    const a=(m.f(i)+0.5)/5*m.tau;
    // the way out along this sepal, flat
    const out=v3(@cos(a),0,@sin(a));
    // where its vertices begin, so it opens in its turn
    const s=b.mark();
    try mg.petal(b,.{
      .base=heart+out*m.splat3(0.03),.out=out,.len=0.26,.width=0.12,
      .rise=0.75,.flare=0.35,.cup=0.5,
      .col=pal.leafDark,.tip=pal.leafLite,.t=1,.part=.leaf,
    });
    try sk.on(b,s,trunk,1,.{.from=heart,.delay=petalStagger*m.f(i)});
  }
}
/// a whorl of `n` petals round the heart (the origin), opening one after
/// another from `first` on over the structure's last `form` of growth
pub fn petals(b:*mg.Builder,n:usize,turn:f32,first:usize,p:mg.Petal)Allocator.Error!void{
  for(0..n)|i|{
    // this petal's angle round the heart (radians)
    const a=(m.f(i)+turn)/m.f(n)*m.tau;
    // the petal, turned to its own heading
    var q=p;
    q.out=v3(@cos(a),0,@sin(a));
    // where its vertices begin, so it opens in its turn
    const s=b.mark();
    try mg.petal(b,q);
    try growth.tag(b,s,q.base,.{1-form+whorlStagger*m.f(first+i),petalOpen});
  }
}
/// mesh: ARSTHRAXIA WHORL. the flower's broad outer whorl, opening wide
/// round its heart (the origin); it turns slowly while it studies.
pub const whorl=struct{
  /// builds the outer whorl: nine broad violet petals opening wide
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try petals(b,9,0,0,.{
      .base=v3(0,0,0),.out=undefined,.len=0.62,.width=0.3,.rise=0.55,.flare=0.7,.cup=0.4,
      .col=petalHeart.toRgba8(255),.tip=petalRim.toRgba8(255),.t=1,.part=.leaf,
    });
  }
};
/// mesh: ARSTHRAXIA CUP. the inner whorl cupping the core that condenses
/// over it, stamens arching out of its heart (the origin) beneath it; it
/// turns against the outer whorl while it studies.
pub const cup=struct{
  /// builds the cup: five upright petals set between the whorl's, then nine
  /// stamens arching out, opening after them
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try petals(b,5,0.5,9,.{
      .base=v3(0,0,0),.out=undefined,.len=0.42,.width=0.22,.rise=1.15,.flare=0.4,.cup=0.4,
      .col=petalHeart.toRgba8(255),.tip=petalRim.toRgba8(255),.t=1,.part=.leaf,
    });
    // where the stamens' vertices begin, so they open last
    const s=b.mark();
    try mg.stamens(b,.{
      .heart=v3(0,0,0),.axis=v3(0,1,0),.n=9,.len=0.32,.r=0.009,.anther=0.055,
      .lean=0.4,.arch=0.6,.col=stamen.toRgba8(255),.t=1,.seed=0x7B05,
    });
    try growth.tag(b,s,v3(0,0,0),.{1-form+whorlStagger*14,petalOpen});
  }
};
/// mesh: ARSTHRAXIA WHOLE. it at rest with its flower, whorls set on its
/// heart: what the gardener sees before putting it down.
pub const whole=struct{
  /// builds it at rest, the whorls set on its heart
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try stand(b);
    // where the whorls' vertices begin, so only they are moved up to the heart
    const s=b.mark();
    try whorl.build(b);
    try cup.build(b);
    b.xform(s,m.translate(heartAt));
  }
};
/// mesh: ARSTHRAXIA VINES. what Arsthraxia's study grows on it: two vines
/// climbing its twined stems from the soil, winding round them, then
/// breaking away under the cage and curling in at their tips, leaves and
/// small tendrils along them. Grown by that study's progress.
pub const vines=struct{
  /// how many vines climb the stems
  const steps=2;
  /// how many control points climb round the stems before a vine breaks away
  const climb=11;
  /// how many control points run along a vine in all: the climb, the break, the crozier
  const ctrlCount=climb+6;
  /// how many turns they wind round the stems on their way up
  const turns:f32=1.6;
  /// how far up the stems a vine climbs before it breaks away (tiles)
  const topAt:f32=0.86;
  /// lays vine `v`'s control points into `out`: winding round the stems up
  /// to `topAt`, breaking away outward, then rolling into a crozier
  fn ctrl(v:usize,out:*[ctrlCount]V3)void{
    // the vine's starting heading round the stems (radians)
    const a0=m.ratio(v,steps)*m.tau+0.9;
    for(0..climb)|j|{
      // how far up its climb this point is (0..1)
      const k=m.ratio(j,climb-1);
      // its height up the stems
      const y=m.lerp(-0.02,topAt,k);
      // clear of the stems' flared foot, then close round their twine
      const r=0.175+0.13*@exp(-y*9);
      // its angle round the stems here, winding as it climbs
      const a=a0+k*turns*m.tau;
      out[j]=v3(@cos(a)*r,y,@sin(a)*r);
    }
    // the heading it breaks away along, once it has wound
    const a1=a0+turns*m.tau;
    // the way out along that heading, flat
    const outw=v3(@cos(a1),0,@sin(a1));
    // straight up
    const up=v3(0,1,0);
    // the climb's last point, where it breaks away
    const last=out[climb-1];
    out[climb]=last+outw*m.splat3(0.12)+up*m.splat3(0.08);
    out[climb+1]=last+outw*m.splat3(0.24)+up*m.splat3(0.2);
    // a crozier rolling in toward the stems
    const c=last+outw*m.splat3(0.3)+up*m.splat3(0.33);
    // the crozier's radii, closing in point by point
    const rho=[_]f32{0.1,0.075,0.052,0.034};
    for(rho,0..)|r,j|{
      // this crozier point's angle round its middle (radians)
      const th=-0.27+1.3*m.f(j);
      out[climb+2+j]=c+(outw*m.splat3(@cos(th))+up*m.splat3(@sin(th)))*m.splat3(r);
    }
    mg.grow(out,.{.start=out[0],.direction=up,.length=topAt,.wobble=0.04,.seed=0x7B50+%v*17});
  }
  /// builds the vines: two, each climbing, breaking away and curling, with
  /// leaves and two small tendrils, the second a little behind the first
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the growth skeleton the vines are hung on
    var sk=growth.Skeleton.begin(b);
    for(0..steps)|v|{
      // this vine's control points
      var c:[ctrlCount]V3=undefined;
      ctrl(v,&c);
      // the vine's own spline
      const id=sk.trunk(&c,.{.delay=0.15*m.f(v)});
      try sk.tube(b,id,.{.r0=0.016,.tip=0.05,.col=pal.vine,.sides=5,.t0=0,.t1=0.7});
      try sk.leaves(b,id,.{.n=8,.len=0.13,.width=0.045,.from=0.1,.to=0.78,.t0=0,.t1=0.7,.col=pal.leafDark,.tip=pal.leafLite,.seed=0x7B58+%v*7});
      // small tendrils off it, curling
      for([_]f32{0.32,0.58},0..)|u,j|{
        // the vine's direction there
        const tan=sk.tangent(id,u);
        // the way away from the stems, flat
        const away=m.norm(sk.point(id,u)*v3(1,0,1));
        // the tendril's own vine off it
        const t=sk.vine(id,u,.{.start=undefined,.direction=m.norm(away+tan*m.splat3(0.5)),.length=0.13,.wobble=0.1,.curl=0.5,.seed=0x7B60+%v*5+%j},5,.{.after=.passing});
        try sk.tube(b,t,.{.r0=0.005,.tip=0.1,.col=pal.vine,.sides=4,.t0=0.3,.t1=0.6});
      }
    }
    sk.finish(b);
  }
};
/// mesh: ARSTHRAXIA SATELLITE. a small sap of resin held in two grown vine
/// bands, one of those the old core split into; spun round the core.
pub const satellite=struct{
  /// how big the sap is: its radius
  pub const radius:f32=0.075;
  /// builds the satellite: a small resin pod wrapped by two crossing vine bands
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try kit.resinPod(b,v3(0,0,0),v3(radius,radius,radius),8,12);
    // two bands wrapping it, pole to pole, crossing
    const arcs=[_][4]f32{.{0.15,0.3,2.99,2.4},.{0.2,3.5,2.9,5.6}};
    try mg.bands(b,v3(0,0,0),v3(radius,radius,radius),&arcs,1,0.008,0.12,0x0B5,pal.vine);
  }
};
/// mesh: ARSTHRAXIA CORE. the research energy condensing where the old sap
/// core stood: a ball of light a unit across (tu.x < 0 marks it from a
/// wisp); the structure sizes it by how far the unit has condensed.
pub const core=struct{
  /// builds the core: a smooth white ball of energy, radius 1
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(1,1,1),.col=energyWhite,.part=.energy,.rings=12,.segs=18,.t=-1});
  }
};
/// mesh: ARSTHRAXIA WISP. a thread of energy a satellite sheds into the
/// core, running straight up +y over 0..1 (tu.x 0 at the satellite .. 1 at
/// the core); placed along its fall as a curve (part.vert). It closes to a
/// point at both ends.
pub const wisp=struct{
  /// builds the wisp: a tube up +y from 0 to 1, thinning toward the core,
  /// pointed at both ends, white energy
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // how many rings run along the wisp
    const steps=20;
    // the wisp's path, its flow (tu.x) and its radius, ring by ring
    var path:[steps]V3=undefined;
    var ts:[steps]f32=undefined;
    var rs:[steps]f32=undefined;
    for(&path,&ts,&rs,0..)|*p,*t,*r,i|{
      // how far along the wisp this ring is (0..1)
      const k=m.ratio(i,steps-1);
      p.*=v3(0,k,0);
      t.*=k;
      r.*=@max(0.024*m.pow(f32,@sin(m.pi*k),0.5)*(1-0.4*k),2e-4);
    }
    try b.tubeR(&path,&ts,&rs,energyWhite,.energy,6);
  }
};
/// where an offshoot leaves the stems, `y` up them: on their axis, inside
/// their twine, so it grows out of it
pub fn stalkAt(y:f32)V3{return v3(0,y,0);}
/// how many control points an offshoot's bough runs through
/// (laid by `shootCtrl`)
const shootCtrlCount=8;
/// how long an offshoot's bough is (tiles)
const shootLen:f32=0.8;
/// lays an offshoot's control points into `ctrl`, from where it leaves the
/// stems (the origin) out along +x, rising toward the light
fn shootCtrl(ctrl:*[shootCtrlCount]V3)void{
  // how many control points to lay
  const steps=shootCtrlCount;
  ctrl[0]=v3(0,0,0);
  for(1..steps)|j|{
    // how far along the bough this point is (0..1)
    const s=m.ratio(j,steps-1);
    // heading turns from a low rise toward upright, mostly in its outer half
    const h=m.lerp(0.22,1.25,s*s);
    ctrl[j]=ctrl[j-1]+v3(@cos(h),@sin(h),0)*m.splat3(shootLen/(steps-1));
  }
  mg.grow(ctrl,.{.start=ctrl[0],.direction=m.norm(ctrl[steps-1]),.length=shootLen,.wobble=0.12,.curl=0.03,.seed=0x7B21});
}
/// where an offshoot's flower opens, in its own space, and which way
pub fn shootTip()struct{at:V3,axis:V3}{
  // the bough's control points
  var c:[shootCtrlCount]V3=undefined;
  shootCtrl(&c);
  // the bough resampled, to find its tip and the way it points there
  var p:[growth.res]V3=undefined;
  m.splineResample(&c,&p);
  return.{.at=p[growth.res-1],.axis=m.norm(p[growth.res-1]-p[growth.res-5])};
}
/// mesh: ARSTHRAXIA SHOOT. an offshoot a minor study grows out of the
/// stems: a braided bough round a nerve of its own (thought runs out along
/// it to its flower), leaving along +x and rising, leaves along it, a
/// leafy twig off it and a vine winding round it that breaks away into a
/// curling tendril; it opens into a flower like the crown's, a calyx under
/// it (a satellite of its own hovers over it, emitted, `shootForm`). Its
/// root lies inside the stems. It grows along its own growth splines by
/// research's progress.
pub const shoot=struct{
  /// builds the offshoot: the braided bough, its leaves, a leafy twig, the
  /// winding vine and the flower, leaving the last `shootForm` for its satellite
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // the growth skeleton the offshoot is hung on
    var sk=growth.Skeleton.begin(b);
    sk.tail=shootForm;
    // the bough's control points
    var ctrl:[shootCtrlCount]V3=undefined;
    shootCtrl(&ctrl);
    // the bough's own spline
    const bough=sk.trunk(&ctrl,.{});
    try sk.braid(b,bough,.{.girth=0.045,.tip=0.5,.strands=4,.twist=3,.wobble=pal.strandWobble,.seed=0x7B70,.core=nerve,.strand=pal.vine,.t0=0,.t1=1,.corePart=.nerve});
    try sk.leaves(b,bough,.{.n=4,.len=0.2,.width=0.07,.from=0.25,.to=0.8,.t0=0,.t1=1,.col=pal.leafDark,.tip=pal.leafLite,.seed=0x7B22});
    // a leafy twig off its back, reaching out and curling
    // the twig's own vine off the bough
    const twig=sk.vine(bough,0.5,.{.start=undefined,.direction=m.norm(v3(0.5,0.6,0.7)),.length=0.3,.wobble=0.15,.curl=0.3,.seed=0x7B71},6,.{.after=.passing});
    try sk.tube(b,twig,.{.r0=0.014,.tip=0.05,.col=pal.vine,.sides=5,.t0=0.5,.t1=0.8});
    try sk.leaves(b,twig,.{.n=3,.len=0.12,.width=0.045,.from=0.25,.to=0.85,.t0=0.5,.t1=0.8,.col=pal.leafDark,.tip=pal.leafLite,.seed=0x7B72});
    try winding(b,&sk,bough);
    try flower(b,&sk,bough);
    sk.finish(b);
  }
  /// a vine winding round the bough as it grows, then breaking away up
  /// into a curling tendril, small leaves along it
  fn winding(b:*mg.Builder,sk:*growth.Skeleton,bough:growth.Id)Allocator.Error!void{
    // how many control points wind round the bough
    const w=10;
    // the bough's resampled points
    const pts=&sk.get(bough).pts;
    // a twist-free frame along the bough: its normal and its binormal
    var nrm:[growth.res]V3=undefined;
    var bin:[growth.res]V3=undefined;
    mg.transport(pts,&nrm,&bin);
    // the vine's control points: the winding, then three breaking away
    var c:[w+3]V3=undefined;
    for(0..w)|j|{
      // how far along its winding this point is (0..1)
      const k=m.ratio(j,w-1);
      // where on the bough this point winds (0..1)
      const u=m.lerp(0.06,0.66,k);
      // the bough's ring nearest there
      const i:usize=@intFromFloat(@round(u*(growth.res-1)));
      // its angle round the bough here, wound just over two turns (radians)
      const a=k*2.2*m.tau;
      // round the bough's strands, wound closer as it thins
      const r=0.045*m.lerp(1,0.5,u)*1.12+0.012;
      c[j]=pts[i]+(nrm[i]*m.splat3(@cos(a))+bin[i]*m.splat3(@sin(a)))*m.splat3(r);
    }
    // the winding's last point, where it breaks away
    const last=c[w-1];
    // the way out from the bough there
    const off=m.norm(last-m.alongPath(pts,0.66));
    c[w]=last+off*m.splat3(0.06)+v3(0,0.06,0);
    c[w+1]=last+off*m.splat3(0.1)+v3(0,0.15,0);
    c[w+2]=last+off*m.splat3(0.06)+v3(0,0.2,0);
    // the vine's own branch off the bough
    const id=sk.branch(bough,0.06,&c,.{.after=.passing});
    try sk.tube(b,id,.{.r0=0.009,.tip=0.08,.col=pal.vine,.sides=4,.t0=0.1,.t1=0.7});
    try sk.leaves(b,id,.{.n=4,.len=0.08,.width=0.03,.from=0.15,.to=0.7,.t0=0.1,.t1=0.7,.col=pal.leafDark,.tip=pal.leafLite,.seed=0x7B73});
  }
  /// its flower at the bough's tip: a calyx, a whorl of petals, stamens
  fn flower(b:*mg.Builder,sk:*growth.Skeleton,bough:growth.Id)Allocator.Error!void{
    // where the flower opens on the bough's tip, and which way it faces
    const tip=shootTip();
    for(0..5)|i|{
      // this sepal's angle round the tip (radians)
      const a=(m.f(i)+0.5)/5*m.tau;
      // where its vertices begin, so it opens in its turn
      const s=b.mark();
      try mg.petal(b,.{
        .base=tip.at-tip.axis*m.splat3(0.02),.out=v3(@cos(a),0,@sin(a)),
        .len=0.1,.width=0.05,.rise=0.6,.flare=0.3,.cup=0.5,
        .col=pal.leafDark,.tip=pal.leafLite,.t=1,.part=.leaf,
      });
      try sk.on(b,s,bough,1,.{.from=tip.at,.delay=petalStagger*0.5*m.f(i)});
    }
    for(0..7)|i|{
      // this petal's angle round the tip (radians)
      const a=m.ratio(i,7)*m.tau;
      // where its vertices begin, so it opens after the calyx
      const p=b.mark();
      try mg.petal(b,.{
        .base=tip.at,.out=v3(@cos(a),0,@sin(a)),
        .len=0.2,.width=0.1,.rise=0.9,.flare=0.6,.cup=0.4,
        .col=petalHeart.toRgba8(255),.tip=petalRim.toRgba8(255),.t=1,.part=.leaf,
      });
      try sk.on(b,p,bough,1,.{.from=tip.at,.delay=petalStagger*(2.5+0.5*m.f(i))});
    }
    // where the stamens' vertices begin, so they open last
    const st=b.mark();
    try mg.stamens(b,.{
      .heart=tip.at,.axis=tip.axis,.n=6,.len=0.11,.r=0.004,.anther=0.022,
      .lean=0.35,.arch=0.5,.col=stamen.toRgba8(255),.t=1,.seed=0x7B23,
    });
    try sk.on(b,st,bough,1,.{.from=tip.at,.delay=petalStagger*6.5});
  }
};
