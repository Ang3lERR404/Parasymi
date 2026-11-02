//! mesh: WOLF EARS. both ears, skinned to their bones (wolf_skeleton) above
//! their roots and to the skull below (so the root never leaves it), each
//! built at its root rising along the bone's +Y, its inner face toward +Z.
//! A thick ear with weight: its base flares wide and sinks into the skull
//! (below the origin) so it grows out of the head rather than sitting on
//! it, narrowing to a softly rounded tip. The inner face is sap
//! (translucent through the instance's fade), cupped, with its outer rim
//! rolled forward (the helix) and a fold running up inside it; the back is
//! a dense shell of vine, the two joined by the rolled rim.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error every building call may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, easing
const m=engine.core.math;
/// the mesh builder: patches and tubes
const mg=lib.meshgen;
/// the garden's shared colours (the wolf's core and vine)
const pal=lib.palette;
/// colour mixing, for the ear greening toward its tip
const color=engine.core.color;
/// the wolf's bones: each side's ear bone and the head
const skel=lib.skeleton;
/// the sculpt kit, whose `pack` turns bone weights into a vertex's skin
const Sculpt=engine.gfx.sculpt.Sculpt;
/// a point or direction in 3D
const V3=m.V3;
/// makes a `V3` from three numbers
const v3=m.v3;
/// how tall an ear stands from its root to its tip (world units)
pub const height:f32=0.12;
/// half the ear's width at its root, before the flare into the skull
const halfBase:f32=0.032;
/// how far below the origin the base runs into the skull (a share of `height`)
const sinkAmount:f32=0.3;
/// how deep the inner face cups at its middle
const cupDepth:f32=0.014;
/// the grid each face is laid on: rows up the ear
const rowCount=16;
/// the grid each face is laid on: columns across it
const colCount=11;
/// a soft bump: 1 at `mu`, falling away over about `sigma` either side
fn gauss(x:f32,mu:f32,sigma:f32)f32{
  // how far from the bump's middle, in its own widths
  const d=(x-mu)/sigma;
  return@exp(-d*d);
}
/// half the ear's width at `k` up it (negative k: sunk in the skull)
fn half(k:f32)f32{
  // how far up the ear, held to 0..1
  const up=m.clamp01(k);
  // a wide root flaring into the skull, a rounded tip
  const flare=0.016*m.pow(f32,m.clamp01(1-(k+sinkAmount)/(sinkAmount+0.25)),2);
  return halfBase*m.pow(f32,@cos(up*m.pi/2.0),0.75)+flare;
}
/// how thick the ear is at `k`: heavy at the root, thin toward the tip
fn thick(k:f32)f32{return m.lerp(0.012,0.0025,m.clamp01(k));}
/// a point on the inner face: `k` up the ear (a share of `height`; below 0
/// sunk in the skull), `u` across it (-1..1)
fn inner(k:f32,u:f32)V3{
  // how strongly the face's shaping shows at this height: soft at root and tip
  const rise=@sin(m.clamp01(k)*m.pi*0.9+0.15);
  // cupped, the rim rolling forward toward the inner side, a fold inside
  const cup=-cupDepth*(1-u*u)*rise;
  // the rim rolling forward at either edge
  const rim=0.009*m.smooth(m.unlerp(0.6,1,@abs(u)))*rise;
  // and the fold: a groove beside a ridge running up inside
  const fold=-0.004*gauss(u,-0.3,0.16)*rise+0.0025*gauss(u,0.12,0.12)*rise;
  return v3(-u*half(k),k*height,cup+rim+fold);
}
/// a point on the back of the ear: `k` up it, `u` across it (-1..1), the
/// inner face's point pushed back by the ear's thickness
fn outer(k:f32,u:f32)V3{
  // the inner face's point it lies behind
  const p=inner(k,u);
  // the back is rounder than the face: thickest down the middle
  return p-v3(0,0,thick(k)*(0.35+0.65*(1-u*u)));
}
/// the facing (unit) of the surface `f` at `k`, `u`, found from small steps
/// either way, turned so its z leans the way `toward` says (+1 or -1)
fn gridNormal(comptime f:fn(f32,f32)V3,k:f32,u:f32,toward:f32)V3{
  // how far each small step goes
  const e:f32=0.01;
  // the facing from the steps up and across
  const n=m.norm(m.cross(f(k+e,u)-f(k-e,u),f(k,u+e)-f(k,u-e)));
  return if(n[2]*toward<0)-n else n;
}
/// how far up the ear row `r` lies: from sunk in the skull to just short of the tip
fn kAt(r:usize)f32{return m.lerp(-sinkAmount,0.985,m.ratio(r,rowCount-1));}
/// lays both ears: each built at its root, skinned to the skull below and its
/// own bone above, then moved onto that bone in the bind pose
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // the bones' bind-pose transforms
  const w=skel.bind();
  for(skel.sides)|sd|{
    // where this ear's vertices begin
    const start=b.mark();
    try ear(b);
    // its root holds with the skull it is sunk in (rising from the root
    // mound sculpted there), and only above that does it turn with its
    // own bone, bending smoothly between
    for(b.v.items[start..],try b.skinOf(start))|vx,*k|{
      // how much of this vertex its own bone moves, 0 at the root .. 1 above
      const own=m.smooth(m.clamp01((vx.pos[1]-rootHold)/rootBend));
      // its weight for every bone, all but the ear's and the head's left at 0
      var wt:[skel.count]f32=@splat(0);
      wt[@intFromEnum(sd.ear)]=own;
      wt[@intFromEnum(skel.Bone.head)]=1-own;
      k.*=Sculpt.pack(&wt);
    }
    b.xform(start,w[@intFromEnum(sd.ear)]);
  }
}
/// how high up the ear (its own frame) the skull still holds it fully
const rootHold:f32=0.004;
/// over how much more height the hold passes to the ear's bone
const rootBend:f32=0.04;
/// lays one ear at its root: the sap-lined inner face, the vine back and the
/// rolled rim joining them up one edge, over the tip and down the other
fn ear(b:*mg.Builder)Allocator.Error!void{
  // the grid's points, normals, colours and heights (tu.y), reused for both faces
  var pts:[rowCount*colCount]V3=undefined;
  var nrms:[rowCount*colCount]V3=undefined;
  var cols:[rowCount*colCount]color.Rgba8=undefined;
  var us:[rowCount*colCount]f32=undefined;
  // the inner face (sap; its normal points back, so the face seen from in
  // front is the sap-lined one)
  for(0..rowCount)|r|for(0..colCount)|c|{
    // how far up this row is, how far across this column (-1..1), and its place in the grid
    const k=kAt(r);
    const u=m.ratio(c,colCount-1)*2-1;
    const i=r*colCount+c;
    pts[i]=inner(k,u);
    nrms[i]=gridNormal(inner,k,u,-1);
    cols[i]=color.mix(pal.wolfCore,pal.wolfBark,m.clamp01(k));
    us[i]=m.clamp01(k);
  };
  try mg.patch(b,rowCount,colCount,&pts,&nrms,&cols,&us,1,.ear);
  // the back: a dense shell of vine
  for(0..rowCount)|r|for(0..colCount)|c|{
    // how far up this row is, how far across this column (-1..1), and its place in the grid
    const k=kAt(r);
    const u=m.ratio(c,colCount-1)*2-1;
    const i=r*colCount+c;
    pts[i]=outer(k,u);
    nrms[i]=gridNormal(outer,k,u,-1);
    cols[i]=color.mix(pal.wolfBark,pal.wolfBarkLite,m.clamp01(k));
  };
  try mg.patch(b,rowCount,colCount,&pts,&nrms,&cols,&us,1,.stem);
  // the rolled rim joining face and back, up one edge, over the tip and
  // down the other
  // how many points the rim runs through: up one edge and down the other
  const ringRows=2*rowCount-1;
  // the rim's points, their heights along the ear and their radii
  var rim:[ringRows]V3=undefined;
  var ts:[ringRows]f32=undefined;
  var rs:[ringRows]f32=undefined;
  for(0..ringRows)|j|{
    // whether this point is on the way up (the left edge) or down (the right)
    const up=j<rowCount;
    // the row it sits at, the edge it runs along (-1 or 1) and how far up that is
    const r=if(up)j else ringRows-1-j;
    const u:f32=if(up)-1 else 1;
    const k=kAt(r);
    rim[j]=(inner(k,u)+outer(k,u))*m.splat3(0.5);
    ts[j]=m.clamp01(k);
    rs[j]=thick(k)*0.3+0.0012;
  }
  // over the tip the two edges meet: pull them together there
  try b.tubeR(&rim,&ts,&rs,pal.wolfBark,.stem,5);
}
