//! petals and stamens: a flower's pieces.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const Rng=engine.core.rng.Rng;
const vertex=lib.vertex;
const color=engine.core.color;
const V3=m.V3;
const Builder=lib.meshgen.Builder;
const ellipsoid=lib.meshgen.ellipsoid;
const grow=lib.meshgen.grow;
const lamina=lib.meshgen.laminae.lamina;
pub const Petal=struct{
  base:V3,
  /// horizontal direction the petal faces out along (unit)
  out:V3,
  len:f32,
  /// widest half-width
  width:f32,
  /// angle above horizontal at the base, and how much it bends outward by
  /// the tip (a petal rises from the bloom's heart and flares open)
  rise:f32,
  flare:f32,
  /// how far its edges lift toward the bloom's heart (a cupped petal)
  cup:f32=0.4,
  col:color.Rgba8,
  tip:color.Rgba8,
  t:f32=1,
  part:vertex.Part=.bloom,
};
/// a flower petal: narrow at its claw, broadest past the middle and closing
/// in a rounded tip, cupped across its width, curving from upright at the
/// base to open at the tip. A `lamina` (thin, bevelled at its edges); tu.y
/// runs base to tip.
pub fn petal(b:*Builder,p:Petal)Allocator.Error!void{
  const ringCount=7;
  const up=m.v3(0,1,0);
  const side=m.norm(m.cross(up,p.out));
  var spine:[ringCount]V3=undefined;
  var nrm:[ringCount]V3=undefined;
  spine[0]=p.base;
  for(0..ringCount)|i|{
    const k=m.ratio(i,ringCount-1);
    const h=p.rise-p.flare*k*k;
    const dir=p.out*m.splat3(@cos(h))+up*m.splat3(@sin(h));
    if(i>0)spine[i]=spine[i-1]+dir*m.splat3(p.len/(ringCount-1));
    // the face toward the bloom's heart and the sky
    nrm[i]=m.norm(m.cross(side,dir));
  }
  var sides:[ringCount]V3=undefined;
  var ws:[ringCount]f32=undefined;
  var dish:[ringCount]f32=undefined;
  var cs:[ringCount]color.Rgba8=undefined;
  for(0..ringCount)|i|{
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
pub const Stamens=struct{
  /// the bloom's heart and the way it faces (unit)
  heart:V3,
  axis:V3,
  n:u32,
  /// filament length and its thickest radius
  len:f32,
  r:f32,
  /// angle the filaments leave the axis at, and how much further out they
  /// arch by the tip
  lean:f32=0.35,
  arch:f32=0.55,
  /// each anther's length
  anther:f32,
  col:color.Rgba8,
  tip:color.Rgba8=pollen.toRgba8(255),
  /// turns the ring of them about the axis
  spin:f32=0,
  t:f32=1,
  part:vertex.Part=.leaf,
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
  const n=6;
  const res=10;
  const ref=if(@abs(s.axis[1])<m.nearParallel)m.v3(0,1,0)else m.v3(1,0,0);
  const e1=m.norm(m.cross(s.axis,ref));
  const e2=m.cross(s.axis,e1);
  var rng=Rng.init(s.seed^0x57A3);
  for(0..s.n)|i|{
    const a=m.ratio(i,s.n)*m.tau+s.spin+rng.range(-0.15,0.15);
    const out=e1*m.splat3(@cos(a))+e2*m.splat3(@sin(a));
    const len=s.len*rng.range(0.85,1.1);
    const lean=s.lean+rng.range(-0.08,0.08);
    var ctrl:[n]V3=undefined;
    ctrl[0]=s.heart+out*m.splat3(s.r);
    for(1..n)|j|{
      const k=m.ratio(j,n-1);
      const h=lean+s.arch*k*k;
      ctrl[j]=ctrl[j-1]+(s.axis*m.splat3(@cos(h))+out*m.splat3(@sin(h)))*m.splat3(len/(n-1));
    }
    grow(&ctrl,.{.start=ctrl[0],.direction=m.norm(ctrl[n-1]-ctrl[0]),.length=len,.wobble=0.1,.seed=s.seed+%i*29});
    var path:[res]V3=undefined;
    m.splineResample(&ctrl,&path);
    var ts:[res]f32=undefined;
    var rs:[res]f32=undefined;
    var us:[res]f32=undefined;
    var cs:[res]color.Rgba8=undefined;
    for(&ts,&rs,&us,&cs,0..)|*t,*r,*u,*c,j|{
      const k=m.ratio(j,res-1);
      t.*=s.t;
      u.*=k;
      // (never below the cap threshold, so every size keeps one layout)
      r.*=@max(s.r*@sqrt(@sin(m.pi*k)),2e-4);
      c.*=color.mix(s.col,s.tip,k*k*0.35);
    }
    try b.tubeC(&path,&ts,&rs,&cs,&us,s.part,4);
    // the anther: two lobes side by side, sitting on the tip and heading on
    const dir=m.norm(path[res-1]-path[res-3]);
    const lobe=s.anther*0.2;
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
