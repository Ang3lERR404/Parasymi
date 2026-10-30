//! mesh: SAP CACHE. a store grown like the plants: a short woven bole on a
//! root mat, broad leaves at its foot, opening into a calyx that cups a
//! gourd of resin sap from below. Up over the gourd a basket is woven of
//! living vines winding one way from the calyx to its neck and pale roots
//! the other, passing over and under each other where they cross (wicker),
//! a leaf off a vine here and there; at the neck they gather into a collar bound by a twist of root,
//! a leafy vine or two curling up out of it. The neck is its mouth, closed
//! by a bud of sepals (`lid`, emitted: the structure opens it as something
//! goes in or comes out); what it holds hangs inside the resin (emitted by
//! the structure, `belly_lump`s tinted per item).
//! It grows on hidden growth splines (gfx/growth.zig): the bole rises with
//! its roots spreading and the foot leaves unfolding as it passes, the
//! calyx opens round its top, then the gourd fills from the bottom up as
//! the stem climbs through it while the basket's vines wind up round it,
//! the collar binds at the neck and the vines sprout from it; last (`FORM`)
//! the lid closes over the mouth.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const mg=lib.meshgen;
const pal=lib.palette;
const color=engine.core.color;
const kit=lib.structureKit;
const growth=lib.growth;
const Rng=engine.core.rng.Rng;
const V3=m.V3;
const v3=m.v3;
/// the bole: up to the calyx, its girth at the foot
const calyx=v3(0,0.13,0);
const boleR:f32=0.055;
const bolePace:f32=1.6;
/// the resin gourd's centre and radii, where stored items hang
pub const podAt=v3(0,0.42,0);
pub const podR=v3(0.27,0.29,0.27);
/// the neck where the basket's vines gather, at the gourd's crown, and the
/// mouth over it the lid closes (`lid` sits there)
pub const neck=podAt+v3(0,podR[1]*0.96,0);
pub const mouth=neck+v3(0,0.035,0);
/// the stem climbs through the gourd this slowly, so it fills unhurried
const stemPace:f32=1.8;
/// where along the bole the foot leaves unfold
const footAt:f32=0.15;
/// the calyx: sepals cupping the gourd's foot, each opening a little after
/// the one before
const sepals=6;
const sepalStagger:f32=0.02;
/// the basket: vines each way round the gourd, the turns each makes from
/// the calyx to the neck, where on the gourd (0 its foot .. 1 its crown)
/// they run, their girth, how far over and under they pass each other
pub const ribs=6;
const ribTurns:f32=0.7;
const ribFrom:f32=0.13;
const ribTo:f32=0.92;
const ribR:f32=0.011;
const ribSink:f32=1.0;
const ribOver:f32=0.75;
const ribPace:f32=1.5;
const ribRes=48;
/// a leaf off a vine of the first set, where along it
const ribLeaf=[_]f32{0.32,0.58};
/// the collar binding the neck
const collarR:f32=0.068;
/// the share of its growth, once all else is grown, over which the lid forms
pub const form:f32=0.12;
/// the lid: sepals round the mouth, each this long and wide
pub const lidSepals=5;
const lidLen:f32=0.085;
const lidW:f32=0.034;
const sepalTip=color.rgb(0.62,0.7,0.36).toRgba8(255);
/// the point `v` up the gourd (0 its foot .. 1 its crown) at bearing `a`,
/// `out` off its surface along its normal, and that normal
fn onPod(v:f32,a:f32,out:f32)[2]V3{
  const th=m.pi*(1-v);
  const u=v3(@sin(th)*@cos(a),@cos(th),@sin(th)*@sin(a));
  const n=m.norm(u/podR);
  return.{podAt+u*podR+n*m.splat3(out),n};
}
pub fn build(b:*mg.Builder)Allocator.Error!void{
  var k=growth.Skeleton.begin(b);
  k.tail=form;
  const bole=k.trunk(&.{v3(0,-0.04,0),v3(0.008,calyx[1]*0.5,-0.006),calyx},.{.pace=bolePace});
  try kit.rootMat(b,6,0.5,0.05,0x5AC1,.{.k=&k,.id=bole});
  try kit.footLeaves(b,6,0.2,0.36,0.15,0x5AC2,.{.k=&k,.id=bole,.u=footAt});
  {
    var sp:[growth.res]V3=undefined;
    var ts:[growth.res]f32=undefined;
    var rs:[growth.res]f32=undefined;
    k.path(bole,0,1,&sp);
    for(&ts,&rs,0..)|*t,*r,i|{
      const u=m.ratio(i,growth.res-1);
      t.*=u*0.25;
      // flared at its foot, swelling again into the calyx
      r.*=boleR*(0.8+0.55*@exp(-u*6)+0.35*@exp(-(1-u)*6));
    }
    const s=b.mark();
    try mg.braid(b,&sp,&ts,&rs,5,2.4,pal.strandWobble,0x5AC5,pal.core,pal.vine);
    try k.along(b,s,bole);
  }
  // the calyx: sepals curving up round the gourd's foot, holding it
  for(0..sepals)|i|{
    const a=(m.f(i)+0.5)/sepals*m.tau;
    const out=v3(@cos(a),0,@sin(a));
    const s=b.mark();
    try mg.petal(b,.{
      .base=calyx+out*m.splat3(0.06),.out=out,.len=0.19,.width=0.075,
      .rise=0.42,.flare=-0.75,.cup=0.45,.col=pal.leafDark,.tip=sepalTip,.t=0.3,.part=.leaf,
    });
    try k.on(b,s,bole,1,.{.from=calyx,.delay=sepalStagger*m.f(i)});
  }
  // the stem: on up through the gourd's heart to its mouth; the gourd fills
  // round it from the bottom up as its front climbs
  const stem=k.branch(bole,1,&.{calyx,v3(0.01,podAt[1],-0.01),neck,mouth},.{.pace=stemPace});
  {
    const s=b.mark();
    try kit.resinPod(b,podAt,podR,12,16);
    try k.along(b,s,stem);
  }
  for(0..2)|set|for(0..ribs)|i|try rib(b,&k,bole,set,i);
  try collar(b,&k,stem);
  // leafy vines curling up and out of the collar
  try kit.leafyVine(b,neck,neck+v3(0.16,0.3,0.06),0.022,0.4,3,0.75,1,0x5AC4,.{.k=&k,.id=stem,.u=0.86});
  try kit.leafyVine(b,neck,neck+v3(-0.1,0.17,-0.12),0.016,-0.35,2,0.75,0.95,0x5AC6,.{.k=&k,.id=stem,.u=0.86});
  k.finish(b);
}
/// vine `i` of set `set` of the basket: out of the calyx, winding up over
/// the gourd one way (the second set the other, halfway between the first)
/// to the neck. A strand of one set passes outside one of the other where
/// they cross when its index and theirs sum even, inside when odd: plain
/// weave, as a conduit's (conduit.zig `weave`). It grows on a spline of
/// its own lying on the gourd, after the bole.
fn rib(b:*mg.Builder,k:*growth.Skeleton,bole:growth.Id,set:usize,i:usize)Allocator.Error!void{
  const n=m.f(ribs);
  const sgn:f32=if(set==0)1 else-1;
  const shift=if(set==0)m.pi/n else 0;
  const start=(m.f(i)+0.5*m.f(set))*m.tau/n+0.3;
  const parity:f32=if(i%2==0)1 else-1;
  // the spline: on the gourd, clear of the weave's over and under
  var ctrl:[9]V3=undefined;
  for(&ctrl,0..)|*c,j|{
    const f=m.ratio(j,ctrl.len-1);
    const v=m.lerp(ribFrom,ribTo,f);
    c.*=onPod(v,start+sgn*ribTurns*m.tau*f,ribR*ribSink)[0];
  }
  const id=k.branch(bole,1,&ctrl,.{.pace=ribPace,.delay=0.04*m.f(i)+0.02*m.f(set)});
  var path:[ribRes]V3=undefined;
  var ts:[ribRes]f32=undefined;
  var rs:[ribRes]f32=undefined;
  var cols:[ribRes]color.Rgba8=undefined;
  for(&path,&ts,&rs,&cols,0..)|*p,*t,*r,*cl,j|{
    const f=m.ratio(j,ribRes-1);
    const v=m.lerp(ribFrom,ribTo,f);
    const wind=ribTurns*m.tau*f;
    const th=start+sgn*wind;
    const other=th+sgn*wind-shift;
    const off=ribR*(ribSink+sgn*parity*ribOver*@cos(n*other/2));
    p.*=if(j==0)k.point(id,0)else onPod(v,th,off)[0];
    t.*=m.lerp(0.3,0.75,f);
    // drawn to a point at both ends, gathered under the calyx and the collar
    r.*=ribR*(0.25+0.75*m.smooth(m.clamp01(@min(f,1-f)/0.12)));
    cl.*=if(set==0)
      color.mix(pal.vine,pal.leafLite,0.1+0.15*m.f(i%2)+0.25*f)
    else
      color.mix(pal.rootLite,pal.sapwood,0.2+0.25*m.f(i%2)+0.3*f);
  }
  const s=b.mark();
  try b.tubeC(&path,&ts,&rs,&cols,null,.stem,5);
  try k.along(b,s,id);
  if(set!=0)return;
  // a leaf off it, lifting away from the gourd and swept on up it
  var rng=Rng.init(0x5AC7+%i*13);
  for(ribLeaf,0..)|u,l|{
    if((i+l)%2==1)continue;
    const f=u+rng.range(-0.04,0.04);
    const v=m.lerp(ribFrom,ribTo,f);
    const th=start+sgn*ribTurns*m.tau*f;
    const at=onPod(v,th,ribR*(ribSink+1));
    const up=onPod(v+0.03,th+sgn*0.08,ribR*(ribSink+1))[0]-at[0];
    const dir=m.norm(at[1]*m.splat3(0.75)+m.norm(up)*m.splat3(0.8));
    const ls=b.mark();
    try mg.blade(b,at[0],dir,0.12*rng.range(0.85,1.1),0.042,0.45,pal.leafDark,pal.leafLite,m.lerp(0.3,0.75,f),.leaf);
    try k.on(b,ls,id,f,.{.from=at[0]});
  }
}
/// the collar at the gourd's neck where the basket's vines gather: a swell
/// of dark wood, bound by a twist of root wound twice round, its ends
/// tucked under, and a short sapwood lip up to the mouth
fn collar(b:*mg.Builder,k:*growth.Skeleton,stem:growth.Id)Allocator.Error!void{
  const u=k.nearest(stem,neck);
  const s=b.mark();
  try mg.ellipsoid(b,.{.center=neck+v3(0,0.004,0),.radii=v3(collarR,0.036,collarR),.col=pal.core,.rings=6,.segs=12,.t=0.75});
  try b.tube(&.{neck,mouth+v3(0,0.004,0)},&.{0.76,0.8},collarR*0.62,collarR*0.5,pal.sapwood,.stem,10);
  try k.on(b,s,stem,u,.{.from=neck});
  const w=30;
  var path:[w]V3=undefined;
  var ts:[w]f32=undefined;
  var rs:[w]f32=undefined;
  for(&path,&ts,&rs,0..)|*p,*t,*r,j|{
    const f=m.ratio(j,w-1);
    const a=f*2.1*m.tau;
    const rr=collarR*1.02+0.003*@sin(f*m.pi);
    p.*=neck+v3(@cos(a)*rr,(f-0.5)*0.03,@sin(a)*rr);
    t.*=0.76;
    r.*=0.0075*@max(@sqrt(@sin(m.pi*f)),0.15);
  }
  const t=b.mark();
  try b.tubeR(&path,&ts,&rs,pal.rootLite,.stem,5);
  try k.on(b,t,stem,u,.{.from=neck,.delay=0.03});
}
/// mesh: SAP CACHE LID. one sepal of the bud closing the gourd's mouth, in
/// its own space: its base at the origin facing out along +X, rising and
/// curling in over the mouth, so `LID_SEPALS` of them turned round it close
/// into a pointed bud. The structure turns each open about its base (about
/// -Z here) as something goes in or comes out. It forms over the last
/// `FORM` of the cache's growth.
pub const lid=struct{
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    const s=b.mark();
    try mg.petal(b,.{
      .base=v3(0,0,0),.out=v3(1,0,0),.len=lidLen,.width=lidW,
      .rise=1.05,.flare=-1.15,.cup=0.6,.col=pal.leafDark,.tip=sepalTip,.t=0.85,.part=.leaf,
    });
    try growth.tag(b,s,v3(0,0,0),growth.tailWindow(form));
  }
};
