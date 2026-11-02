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
/// builds a 3D vector from its three parts
const v3=m.v3;
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
/// the angle the metatarsal stands at, at rest, from the pelvis's down (about X)
const restMeta=skel.restThigh+skel.restKnee+skel.restHock;
/// the way from the hip to the resting ball, at rest, as a limb's turn about X
const restReach=blk:{
  // the resting ball from the left hip, in the pelvis's frame
  const d=restFoot[0]-v3(-skel.hipX,skel.hipY,0);
  break:blk m.atan2(-d[2],-d[1]);
};
/// how much of the leg's swing toward its foot the metatarsal follows
const metaFollow=lib.player.tuning.metaFollow;
/// what a leg reaches for: its foot and the ground under it
pub const Reach=struct{
  /// the ball, from the hip joint, in the pelvis's frame
  d:V3,
  /// how much more the metatarsal folds (mid-swing)
  fold:f32=0,
  /// the pelvis's turn, which the foot is kept level against
  pelvis:skel.Turn=.{},
  /// how far the toes hang (mid-swing)
  hang:f32=0,
  /// which way the ground under the foot faces, in wolf space
  ground:V3=v3(0,1,0),
};
/// where the hock is wanted, in the leg's own plane (height, depth), and
/// the hip's roll out to that plane: the metatarsal its own bone, standing
/// at its rest angle swung part way with the reach and folded by `fold`,
/// run back up from the ball
const Hock=struct{
  /// the hip's roll out to the side
  ab:f32,
  /// the metatarsal's angle from the pelvis's down
  mu:f32,
  /// the hock's height in the leg's plane
  y:f32,
  /// the hock's depth in the leg's plane
  z:f32,
};
/// the hock wanted for a foot at `d` (see `Hock`)
fn hockFor(d:V3,fold:f32)Hock{
  // out to the side first (the hip's roll), then in its own plane
  const ab=m.atan2(d[0],-d[1]);
  // the reach turned into the leg's own plane, and its height and depth there
  const plane=m.mulV(m.rotZ(-ab),.{d[0],d[1],d[2],0});
  // the way toward the ball, as a limb's turn about X
  const beta=m.atan2(-plane[2],-plane[1]);
  // the metatarsal: its rest angle, swung part way with the reach, folded
  const mu=restMeta+metaFollow*m.angleDiff(restReach,beta)-fold;
  return.{.ab=ab,.mu=mu,.y=plane[1]+skel.metaLength*@cos(mu),.z=plane[2]+skel.metaLength*@sin(mu)};
}
/// how much further than thigh and shin comfortably reach the hock lies
/// for a foot at `d` (0 within reach): how far the hips must drop
pub fn overreach(d:V3,fold:f32)f32{
  // the hock wanted, and the most thigh and shin are asked to span
  const h=hockFor(d,fold);
  const most=(skel.thighLength+skel.shinLength)*lib.player.tuning.reachShare;
  return@max(@sqrt(h.y*h.y+h.z*h.z)-most,0);
}
/// from what share of thigh and shin together the reach is softened
const softFrom:f32=0.983;
/// the hock's reach `d` softened as thigh and shin near straight: unchanged
/// below `softFrom` of their length, then easing toward full length and
/// never reaching it, so the knee straightens smoothly instead of snapping
/// (a straight two-bone chain's bend changes without bound at its end)
fn softReach(d:f32)f32{
  // the whole length, and where the softening starts
  const most=skel.thighLength+skel.shinLength;
  const from=most*softFrom;
  if(d<=from)return d;
  return from+(most-from)*(1-@exp(-(d-from)/(most-from)));
}
/// the leg reaching its foot, plantigrade, each bone its own: the
/// metatarsal stands back up from the ball at its own angle (`hockFor`),
/// thigh and shin reach the hock by the law of cosines with the knee
/// forward and the shin folding back, and the foot is laid along the
/// ground: level against the pelvis's pitch and roll, tipped and rolled
/// with the slope under it, its toes hanging by `hang`
pub fn solveLeg(r:Reach)skel.Limb{
  // the hock wanted, and thigh and shin reaching it
  const h=hockFor(r.d,r.fold);
  const ik=rig.twoBone(skel.thighLength,skel.shinLength,softReach(@sqrt(h.y*h.y+h.z*h.z)));
  // the way toward the hock, as a limb's turn about X
  const bh=m.atan2(-h.z,-h.y);
  // the turns of thigh and shin, each from the pelvis's down
  const th=bh-ik.root;
  const shin=bh+ik.end;
  // the ground's slope along the foot and across it
  const slopePitch=m.atan2(r.ground[2],r.ground[1]);
  const slopeRoll=m.atan2(-r.ground[0],r.ground[1]);
  return.{
    // rolled out to the leg's plane first, then swung in it: a turn (Y*X*Z)
    // swings first and rolls after, so the two are composed in the
    // solve's order and read back as one turn, and the foot lands exactly
    .root=rig.turnOf(m.mul(m.rotZ(h.ab),m.rotX(th))),
    .mid=shin-th,
    .low=.{.x=h.mu-shin},
    .foot=-h.mu-r.pelvis.x+r.hang+slopePitch,
    .roll=slopeRoll-h.ab-r.pelvis.z,
  };
}
/// which way an elbow points when nothing else asks (the right arm's;
/// the left's mirrored): back, a little out and down
const elbowBack=v3(0.35,-0.15,-1);
/// the arm reaching its wrist to `d` (from the shoulder joint, in the
/// chest's frame), its elbow pointing out toward `pole`: the elbow placed
/// by the law of cosines in the plane of the reach and the pole, the upper
/// arm's whole frame turned to run down to it with the forearm bending
/// forward onto the wrist (the shoulder's swing and its twist both, read
/// back as one turn), the elbow bent by what is left
pub fn solveArmPole(d:V3,pole:V3)skel.Limb{
  // the upper arm's and forearm's lengths, and the triangle they make
  const a=skel.upperArm;
  const b=skel.forearmLength;
  const tri=rig.twoBone(a,b,m.len(d));
  // the elbow, and the wrist where the arm can reach it
  const e=rig.middle(a,b,d,pole);
  const wrist=m.norm(d)*m.splat3(tri.reach);
  // the upper arm's +Y runs back up from the elbow; its +Z is the way the
  // forearm bends, square to it (away from the pole, held straight)
  const y=-m.norm(e);
  const fore=wrist-e;
  var z=fore-y*m.splat3(m.dot(fore,y));
  if(m.len(z)<1e-6)z=y*m.splat3(m.dot(pole,y))-pole;
  return.{.root=rig.turnOf(rig.frame(y,m.cross(y,m.norm(z)))),.mid=tri.bend};
}
/// the arm on side `s` reaching its wrist to `d` (from the shoulder, in the
/// chest's frame), the elbow back and a little out
pub fn solveArm(d:V3,s:usize)skel.Limb{return solveArmPole(d,elbowBack*v3(skel.sign(s),1,1));}
/// `solveArm` with the elbow swung by `y` about the chest's vertical (out
/// from the body, or in): the wrist still reaches `d`
pub fn solveArmTurned(d:V3,s:usize,y:f32)skel.Limb{return solveArmPole(d,m.mulDir(m.rotY(y),elbowBack*v3(skel.sign(s),1,1)));}
/// the wrist's turn that lays the hand of arm `l` (side `s`) with its
/// fingers along `fingers` and its palm facing `palm` (both in the chest's
/// frame; the palm faces the hand's -x on the right, +x on the left)
pub fn handTo(l:skel.Limb,s:usize,fingers:V3,palm:V3)skel.Turn{
  // the forearm's frame in the chest's, and the hand's wanted there
  const fore=m.chain(&.{l.root.m4(),m.rotX(-l.mid)});
  const want=rig.frame(-fingers,palm*m.splat3(-skel.sign(s)));
  return rig.turnOf(m.chain(&.{m.inverseRigid(fore),want}));
}
/// which way the forearm of arm `l` runs, elbow to wrist, in the chest's frame
pub fn forearmDir(l:skel.Limb)V3{return m.mulDir(m.chain(&.{l.root.m4(),m.rotX(-l.mid)}),v3(0,-1,0));}
/// how far through its pull and wrench the pry is at unit share `k` (0 on
/// the grip .. 1 wrenched), easing back to the grip after
pub fn pryPull(k:f32)f32{
  if(k<pullEnd)return 0.75*m.smooth(k/pullEnd);
  if(k<wrenchEnd)return 0.75+0.25*m.smooth((k-pullEnd)/(wrenchEnd-pullEnd));
  return 1-m.smooth((k-wrenchEnd)/(1-wrenchEnd));
}
test"the leg's reach softens only near straight, rising smoothly and never past full length"{
  // the leg's whole length, and the reach a step before it
  const most=skel.thighLength+skel.shinLength;
  var last=softReach(0);
  try lib.std.testing.expectEqual(@as(f32,0.5*most),softReach(0.5*most));
  for(1..400)|i|{
    // a reach from nothing to well past full length, and it softened
    const d=m.ratio(i,399)*most*1.5;
    const s=softReach(d);
    try lib.std.testing.expect(s>=last and s-last<=d-m.ratio(i-1,399)*most*1.5+1e-6 and s<=most);
    last=s;
  }
}
