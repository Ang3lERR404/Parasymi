//! petals and stamens: a flower's pieces.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every building call may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, splines, rotations
const m=engine.core.math;
/// a seeded random stream, so each stamen strays a little its own way
const Rng=engine.core.rng.Rng;
/// the garden's part roles
const vertex=lib.vertex;
/// colour types and mixing, for the claw-to-tip fade
const color=engine.core.color;
/// a point or direction in 3D
const V3=m.V3;
/// the mesh builder petals are poured into
const Builder=lib.meshgen.Builder;
/// builds a closed ellipsoid, for each anther's lobes
const ellipsoid=lib.meshgen.ellipsoid;
/// bends a filament's control points the way a vine grows
const grow=lib.meshgen.grow;
/// builds a leaf or petal with a body (laminae.zig)
const lamina=lib.meshgen.laminae.lamina;
/// what one petal is drawn from: where it rises, which way it opens, its
/// size, rise, flare, cup and colours
pub const Petal=struct{
  /// where its claw sits, at the bloom's heart
  base:V3,
  /// horizontal direction the petal faces out along (unit)
  out:V3,
  /// how long it is, claw to tip
  len:f32,
  /// widest half-width
  width:f32,
  /// a petal rises from the bloom's heart and flares open:
  /// these two set how steeply and how widely
  /// rise: the angle above horizontal at its base
  rise:f32,
  /// flare: how much it bends outward by the tip (radians)
  flare:f32,
  /// how far its edges lift toward the bloom's heart (a cupped petal)
  cup:f32=0.4,
  /// its colour at the claw
  col:color.Rgba8,
  /// its colour at the tip
  tip:color.Rgba8,
  /// how far along its plant's growth it forms (tu.x)
  t:f32=1,
  /// the shading role it is drawn with
  part:vertex.Part=.bloom,
};
/// a flower petal: narrow at its claw, broadest past the middle and closing
/// in a rounded tip, cupped across its width, curving from upright at the
/// base to open at the tip. A `lamina` (thin, bevelled at its edges); tu.y
/// runs base to tip.
pub fn petal(b:*Builder,p:Petal)Allocator.Error!void{
  // how many rows the petal has, claw to tip
  const ringCount=10;
  // straight up, which the petal rises from
  const up=m.v3(0,1,0);
  // the way its width lies, across its facing
  const side=m.norm(m.cross(up,p.out));
  // each row's point along the midline, and the face it cups to
  var spine:[ringCount]V3=undefined;
  var nrm:[ringCount]V3=undefined;
  spine[0]=p.base;
  for(0..ringCount)|i|{
    // how far along the petal this row is (0 claw .. 1 tip)
    const k=m.ratio(i,ringCount-1);
    // the angle this row climbs at: rising, then flaring open
    const h=p.rise-p.flare*k*k;
    // the way the midline runs here
    const dir=p.out*m.splat3(@cos(h))+up*m.splat3(@sin(h));
    if(i>0)spine[i]=spine[i-1]+dir*m.splat3(p.len/(ringCount-1));
    // the face toward the bloom's heart and the sky
    nrm[i]=m.norm(m.cross(side,dir));
  }
  // each row's side, half-width, how far its edges lift, and colour
  var sides:[ringCount]V3=undefined;
  var ws:[ringCount]f32=undefined;
  var dish:[ringCount]f32=undefined;
  var cs:[ringCount]color.Rgba8=undefined;
  for(0..ringCount)|i|{
    // how far along the petal this row is (0..1)
    const k=m.ratio(i,ringCount-1);
    // obovate: zero at the claw, widest near two thirds, a rounded tip
    ws[i]=p.width*@sqrt(@max(@sin(m.pi*m.pow(f32,k,1.6)),0));
    sides[i]=side;
    dish[i]=p.cup*ws[i];
    cs[i]=color.mix(p.col,p.tip,k);
  }
  try lamina(b,.{.spine=&spine,.side=&sides,.face=&nrm,.width=&ws,.dish=&dish,.broad=p.width,.col=&cs,.t=p.t,.part=p.part});
}
/// pollen: the warm gold of an anther
pub const pollen=color.rgb(0.92,0.72,0.3);
/// what a flower's stamens are drawn from: where they sit, how many, how
/// long and thick, how they lean and arch, and their colours
pub const Stamens=struct{
  /// the bloom's heart, where the filaments root
  heart:V3,
  /// the way the bloom faces (unit)
  axis:V3,
  /// how many stamens go round the ring
  n:u32,
  /// each filament's length, heart to anther
  len:f32,
  /// a filament's thickest radius
  r:f32,
  /// lean: the angle the filaments leave the axis at
  lean:f32=0.35,
  /// arch: how much further out they arch by the tip
  arch:f32=0.55,
  /// each anther's length
  anther:f32,
  /// the filaments' colour at the heart
  col:color.Rgba8,
  /// the anthers' colour: pollen gold unless told otherwise
  tip:color.Rgba8=pollen.toRgba8(255),
  /// turns the ring of them about the axis
  spin:f32=0,
  /// how far along its plant's growth they form (tu.x)
  t:f32=1,
  /// the shading role they are drawn with
  part:vertex.Part=.leaf,
  /// the seed their small strays are drawn from
  seed:u64=0,
};
/// the stamens at a flower's heart: a ring of slender filaments grown out
/// of it (Catmull-Rom, tapering to a point at both ends), leaving the
/// bloom's axis at `lean` and arching further out toward the tip, each
/// carrying a plump two-lobed anther heading on along it. tu.y runs from 0
/// at the heart to 1 at the anther, so they fold into the bud with the
/// petals and open with them. The vertex layout never depends on the sizes
/// (a confluence's growth keys pass smaller ones).
pub fn stamens(b:*Builder,s:Stamens)Allocator.Error!void{
  // control points per filament, and points each is resampled into
  const n=6;
  const res=10;
  // any direction not along the axis, to build a frame round it
  const ref=if(@abs(s.axis[1])<m.nearParallel)m.v3(0,1,0)else m.v3(1,0,0);
  // two directions across the axis, square to it and each other
  const e1=m.norm(m.cross(s.axis,ref));
  const e2=m.cross(s.axis,e1);
  // the stream each stamen's strays are drawn from
  var rng=Rng.init(s.seed^0x57A3);
  for(0..s.n)|i|{
    // this stamen's angle round the ring, a little astray
    const a=m.ratio(i,s.n)*m.tau+s.spin+rng.range(-0.15,0.15);
    // the way out from the axis it leans toward
    const out=e1*m.splat3(@cos(a))+e2*m.splat3(@sin(a));
    // its length and lean, each a little its own
    const len=s.len*rng.range(0.85,1.1);
    const lean=s.lean+rng.range(-0.08,0.08);
    // its control points, heart to anther
    var ctrl:[n]V3=undefined;
    ctrl[0]=s.heart+out*m.splat3(s.r);
    for(1..n)|j|{
      // how far along it this point is (0..1)
      const k=m.ratio(j,n-1);
      // the angle it climbs at here: leaning, then arching out
      const h=lean+s.arch*k*k;
      ctrl[j]=ctrl[j-1]+(s.axis*m.splat3(@cos(h))+out*m.splat3(@sin(h)))*m.splat3(len/(n-1));
    }
    grow(&ctrl,.{.start=ctrl[0],.direction=m.norm(ctrl[n-1]-ctrl[0]),.length=len,.wobble=0.1,.seed=s.seed+%i*29});
    // its smooth path, resampled evenly
    var path:[res]V3=undefined;
    m.splineResample(&ctrl,&path);
    // per point: when it forms, its radius, how far along it is, its colour
    var ts:[res]f32=undefined;
    var rs:[res]f32=undefined;
    var us:[res]f32=undefined;
    var cs:[res]color.Rgba8=undefined;
    for(&ts,&rs,&us,&cs,0..)|*t,*r,*u,*c,j|{
      // how far along the filament this point is (0..1)
      const k=m.ratio(j,res-1);
      t.*=s.t;
      u.*=k;
      // (never below the cap threshold, so every size keeps one layout)
      r.*=@max(s.r*@sqrt(@sin(m.pi*k)),2e-4);
      c.*=color.mix(s.col,s.tip,k*k*0.35);
    }
    try b.tubeC(&path,&ts,&rs,&cs,&us,s.part,4);
    // the anther: two lobes side by side, sitting on the tip and heading on
    // the way the filament heads at its tip
    const dir=m.norm(path[res-1]-path[res-3]);
    // the size of each anther lobe
    const lobe=s.anther*0.2;
    // where the anther's vertices begin, so they can be placed together
    const st=b.mark();
    for([_]f32{-1,1})|side|{
      try ellipsoid(b,.{
        .center=m.v3(side*lobe*0.8,s.anther*0.25,0),.radii=m.v3(lobe,s.anther*0.5,lobe*0.9),
        .col=s.tip,.part=s.part,.rings=5,.segs=6,.t=s.t,
      });
    }
    b.xform(st,m.chain(&.{m.translate(path[res-1]),m.alignY(dir),m.rotY(a)}));
    for(b.v.items[st..])|*v|v.tu[1]=1;
  }
}
