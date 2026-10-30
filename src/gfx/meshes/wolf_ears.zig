//! mesh: WOLF EARS. both ears, skinned to their bones (wolf_skeleton) above
//! their roots and to the skull below (so the root never leaves it), each
//! built at its root rising along the bone's +Y, its inner face toward +Z. A thick ear with weight: its base flares wide and sinks into the
//! skull (below the origin) so it grows out of the head rather than sitting
//! on it, narrowing to a softly rounded tip. The inner face is sap
//! (translucent through the instance's fade), cupped, with its outer rim
//! rolled forward (the helix) and a fold running up inside it; the back is
//! a dense shell of vine, the two joined by the rolled rim.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const mg=lib.meshgen;
const pal=lib.palette;
const color=engine.core.color;
const skel=lib.skeleton;
const Sculpt=engine.gfx.sculpt.Sculpt;
const V3=m.V3;
const v3=m.v3;
pub const height:f32=0.12;
const halfBase:f32=0.032;
/// how far below the origin the base runs into the skull (fraction of HEIGHT)
const sinkAmount:f32=0.3;
const cupDepth:f32=0.014;
const rowCount=16;
const colCount=11;
fn gauss(x:f32,mu:f32,sigma:f32)f32{
  const d=(x-mu)/sigma;
  return@exp(-d*d);
}
/// half the ear's width at `k` up it (negative k: sunk in the skull)
fn half(k:f32)f32{
  const up=m.clamp01(k);
  // a wide root flaring into the skull, a rounded tip
  const flare=0.016*m.pow(f32,m.clamp01(1-(k+sinkAmount)/(sinkAmount+0.25)),2);
  return halfBase*m.pow(f32,@cos(up*m.pi/2.0),0.75)+flare;
}
/// how thick the ear is at `k`: heavy at the root, thin toward the tip
fn thick(k:f32)f32{return m.lerp(0.012,0.0025,m.clamp01(k));}
/// a point on the inner face: k up the ear, u across it (-1..1)
fn inner(k:f32,u:f32)V3{
  const rise=@sin(m.clamp01(k)*m.pi*0.9+0.15);
  // cupped, the rim rolling forward toward the inner side, a fold inside
  const cup=-cupDepth*(1-u*u)*rise;
  const rim=0.009*m.smooth(m.clamp01((@abs(u)-0.6)/0.4))*rise;
  const fold=-0.004*gauss(u,-0.3,0.16)*rise+0.0025*gauss(u,0.12,0.12)*rise;
  return v3(-u*half(k),k*height,cup+rim+fold);
}
fn outer(k:f32,u:f32)V3{
  const p=inner(k,u);
  // the back is rounder than the face: thickest down the middle
  return p-v3(0,0,thick(k)*(0.35+0.65*(1-u*u)));
}
fn gridNormal(comptime f:fn(f32,f32)V3,k:f32,u:f32,toward:f32)V3{
  const e:f32=0.01;
  const n=m.norm(m.cross(f(k+e,u)-f(k-e,u),f(k,u+e)-f(k,u-e)));
  return if(n[2]*toward<0)-n else n;
}
fn kAt(r:usize)f32{return m.lerp(-sinkAmount,0.985,m.ratio(r,rowCount-1));}
pub fn build(b:*mg.Builder)Allocator.Error!void{
  const w=skel.bind();
  for(skel.sides)|sd|{
    const start=b.mark();
    try ear(b);
    // its root holds with the skull it is sunk in (rising from the root
    // mound sculpted there), and only above that does it turn with its
    // own bone, bending smoothly between
    for(b.v.items[start..],try b.skinOf(start))|vx,*k|{
      const own=m.smooth(m.clamp01((vx.pos[1]-rootHold)/rootBend));
      var wt:[skel.count]f32=@splat(0);
      wt[@intFromEnum(sd.ear)]=own;
      wt[@intFromEnum(skel.Bone.head)]=1-own;
      k.*=Sculpt.pack(&wt);
    }
    b.xform(start,w[@intFromEnum(sd.ear)]);
  }
}
/// how high up the ear (its own frame) the skull still holds it, and over
/// how much more it passes to the ear's bone
const rootHold:f32=0.004;
const rootBend:f32=0.04;
fn ear(b:*mg.Builder)Allocator.Error!void{
  var pts:[rowCount*colCount]V3=undefined;
  var nrms:[rowCount*colCount]V3=undefined;
  var cols:[rowCount*colCount]color.Rgba8=undefined;
  var us:[rowCount*colCount]f32=undefined;
  // the inner face (sap; its normal points back, so the face seen from in
  // front is the sap-lined one)
  for(0..rowCount)|r|for(0..colCount)|c|{
    const k=kAt(r);
    const u=m.ratio(c,colCount-1)*2-1;
    const i=r*colCount+c;
    pts[i]=inner(k,u);
    nrms[i]=gridNormal(inner,k,u,-1);
    cols[i]=color.mix(pal.wolfCore,pal.wolfVine,m.clamp01(k));
    us[i]=m.clamp01(k);
  };
  try mg.patch(b,rowCount,colCount,&pts,&nrms,&cols,&us,1,.ear);
  // the back: a dense shell of vine
  for(0..rowCount)|r|for(0..colCount)|c|{
    const k=kAt(r);
    const u=m.ratio(c,colCount-1)*2-1;
    const i=r*colCount+c;
    pts[i]=outer(k,u);
    nrms[i]=gridNormal(outer,k,u,-1);
    cols[i]=color.mix(pal.wolfCore,pal.wolfVine,0.4*m.clamp01(k));
  };
  try mg.patch(b,rowCount,colCount,&pts,&nrms,&cols,&us,1,.stem);
  // the rolled rim joining face and back, up one edge, over the tip and
  // down the other
  const ringRows=2*rowCount-1;
  var rim:[ringRows]V3=undefined;
  var ts:[ringRows]f32=undefined;
  var rs:[ringRows]f32=undefined;
  for(0..ringRows)|j|{
    const up=j<rowCount;
    const r=if(up)j else ringRows-1-j;
    const u:f32=if(up)-1 else 1;
    const k=kAt(r);
    rim[j]=(inner(k,u)+outer(k,u))*m.splat3(0.5);
    ts[j]=m.clamp01(k);
    rs[j]=thick(k)*0.3+0.0012;
  }
  // over the tip the two edges meet: pull them together there
  try b.tubeR(&rim,&ts,&rs,pal.wolfVine,.stem,5);
}
