//! the wolf's limbs by inverse kinematics: legs to feet, arms to wrists.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, matrices, angles, easing
const m=engine.core.math;
/// the engine's rig helpers: the two-bone solve
const rig=engine.anim.rig;
/// the wolf's skeleton: its bones, lengths and rest pose
const skel=lib.skeleton;
/// a point or direction in 3D
const V3=m.V3;
/// a 4x4 transform
const M4=m.M4;
/// one bone of the wolf's skeleton
const Bone=skel.Bone;
/// how far through a unit's pry the pull ends (0..1 of the unit)
const pullEnd=lib.player.tuning.pullEnd;
/// how far through a unit's pry the wrench ends (0..1 of the unit)
const wrenchEnd=lib.player.tuning.wrenchEnd;
/// where each foot's ball rests under the standing wolf (wolf space)
pub const restFoot=blk:{
  @setEvalBranchQuota(100000);
  // each foot's resting ball, filled in below
  var out:[2]V3=undefined;
  // the skeleton's bones in the world at its rest pose
  const w=skel.fk(.{});
  for(&out,skel.sides)|*o,sd|o.*=m.origin(w[@intFromEnum(sd.foot)]);
  break:blk out;
};
/// bone `b`'s bit in a mask of bones (`parts.Look.hide`)
pub fn bit(b:Bone)u64{return@as(u64,1)<<@intFromEnum(b);}
/// the skeleton's bind pose, inverted (what the skin matrices start from)
pub fn bindInv()[skel.count]M4{return skel.inverses(skel.bind());}
/// the leg reaching `d` (the ball, from the hip joint, in the pelvis's
/// frame). Digitigrade: the metatarsal keeps its angle to the thigh (`fold`
/// more mid-swing), so thigh and metatarsal act as one link and the shin as
/// the other, solved by the law of cosines; the knee always folds back.
/// The foot is kept level with the ground (the pelvis tilted by
/// `pelvisPitch`), its toes hanging by `hang`.
pub fn solveLeg(d:V3,fold:f32,pelvisPitch:f32,hang:f32)skel.Limb{
  // out to the side first (the hip's roll), then in its own plane
  const ab=m.atan2(d[0],-d[1]);
  // the reach turned into the leg's own plane, and its height and depth there
  const plane=m.mulV(m.rotZ(-ab),.{d[0],d[1],d[2],0});
  const dy=plane[1];
  const dz=plane[2];
  // how far the metatarsal is folded off the thigh's line
  const delta=skel.restKnee+skel.restHock-fold;
  // thigh and metatarsal as one link: its length and the angle it sits at
  // from the thigh's own
  const cy=skel.thighLength+skel.metaLength*@cos(delta);
  const cz=skel.metaLength*@sin(delta);
  const lv=@sqrt(cy*cy+cz*cz);
  const phi=m.atan2(cz,cy);
  // the two-link solve: the angles at the root and at the knee
  const ik=rig.twoBone(lv,skel.shinLength,@sqrt(dy*dy+dz*dz));
  // the direction toward the ball, as a limb's turn about X
  const beta=m.atan2(-dz,-dy);
  // the turns of thigh, shin and metatarsal, each from the pelvis's down
  const th=beta-ik.root-phi;
  const shin=beta+ik.end;
  const meta=th+delta;
  return.{
    .root=.{.x=th,.z=ab},
    .mid=shin-th,
    .low=.{.x=meta-shin},
    .foot=-meta-pelvisPitch+hang,
  };
}
/// the arm reaching its wrist to `d` (from the shoulder joint, in the
/// chest's frame): the elbow's bend from the law of cosines (always
/// forward), then the shoulder turned out (about Z) and forward (about X)
/// to carry the bent arm's wrist onto `d`.
pub fn solveArm(d:V3)skel.Limb{
  // the upper arm's and forearm's lengths
  const a=skel.upperArm;
  const b=skel.forearmLength;
  // the two-link solve, how far the wrist can reach, and the elbow's bend
  const ik=rig.twoBone(a,b,m.len(d));
  const l=ik.reach;
  const mid=ik.bend;
  // the bent arm's wrist in its own frame: down the upper arm, the forearm
  // bent forward from it
  const y0=-(a+b*@cos(mid));
  const z0=b*@sin(mid);
  // the target pulled in to the reach, and the shoulder's turn out about Z
  const dd=d*m.splat3(l/@max(m.len(d),1e-6));
  const zr=m.asin(m.clamp(dd[0]/-y0,-1,1));
  // the bent wrist's height once turned out
  const y1=y0*@cos(zr);
  // (wrapped to the nearest turn: the difference of two angles can come
  // out a whole turn round, and an arm blended toward it would spin)
  const xr=m.angleDiff(0,m.atan2(dd[2],dd[1])-m.atan2(z0,y1));
  return.{.root=.{.x=xr,.z=zr},.mid=mid};
}
/// `solveArm` with the shoulder first turned by `y` about the chest's
/// vertical: the wrist still reaches `d`, but the elbow swings round the
/// line from shoulder to wrist (out from the body, or in)
pub fn solveArmTurned(d:V3,y:f32)skel.Limb{
  // the arm solved in the shoulder's turned frame, then given that turn
  var ik=solveArm(m.mulPoint(m.rotY(-y),d));
  ik.root.y=y;
  return ik;
}
/// how far through its pull and wrench the pry is at unit share `k` (0 on
/// the grip .. 1 wrenched), easing back to the grip after
pub fn pryPull(k:f32)f32{
  if(k<pullEnd)return 0.75*m.smooth(k/pullEnd);
  if(k<wrenchEnd)return 0.75+0.25*m.smooth((k-pullEnd)/(wrenchEnd-pullEnd));
  return 1-m.smooth((k-wrenchEnd)/(1-wrenchEnd));
}
