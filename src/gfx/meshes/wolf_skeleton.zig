//! the vine-wolf's skeleton: its bones, how they hang together and the pose
//! they take. The wolf is one skinned surface (`wolf_body`) built around
//! this skeleton in its bind pose (`bind`); the rig (game/player.zig) poses
//! it every frame and the GPU carries each vertex with its bones. Wolf
//! space: the ground under the hips at the origin, +Y up, +Z forward.
//!
//! Every limb bone runs down its local -Y from the joint it turns at to the
//! next; the spine, neck and tail run up +Y.
const lib=@import("../../lib.zig");
const std=lib.std;
const testing=std.testing;
const engine=lib.engine;
const m=engine.core.math;
const rig=engine.anim.rig;
const V3=m.V3;
const v3=m.v3;
const M4=m.M4;
const t=m.translate;
pub const Bone=enum(u8){
  pelvis,waist,chest,neck,head,jaw,gut,
  tail0,tail1,tail2,tail3,
  armL,forearmL,handL,thighL,shinL,metaL,footL,earL,
  armR,forearmR,handR,thighR,shinR,metaR,footR,earR,
  // each hand's four fingers: the knuckle's segment, then the tip's
  finger0L,finger1L,finger2L,finger3L,tip0L,tip1L,tip2L,tip3L,
  finger0R,finger1R,finger2R,finger3R,tip0R,tip1R,tip2R,tip3R,
  // the gut's upper half (see `GUT_GROW_TOP`)
  gutTop,
};
pub const count=@typeInfo(Bone).@"enum".fields.len;
pub const tailCount=4;
pub const fingerCount=4;
/// a side's bones: left (-X) and right (+X)
pub const Side=struct{arm:Bone,forearm:Bone,hand:Bone,thigh:Bone,shin:Bone,meta:Bone,foot:Bone,ear:Bone,fingers:[fingerCount]Bone,tips:[fingerCount]Bone};
pub const sides=[2]Side{
  .{.arm=.armL,.forearm=.forearmL,.hand=.handL,.thigh=.thighL,.shin=.shinL,.meta=.metaL,.foot=.footL,.ear=.earL,
     .fingers=.{.finger0L,.finger1L,.finger2L,.finger3L},.tips=.{.tip0L,.tip1L,.tip2L,.tip3L}},
  .{.arm=.armR,.forearm=.forearmR,.hand=.handR,.thigh=.thighR,.shin=.shinR,.meta=.metaR,.foot=.footR,.ear=.earR,
     .fingers=.{.finger0R,.finger1R,.finger2R,.finger3R},.tips=.{.tip0R,.tip1R,.tip2R,.tip3R}},
};
/// -1 left, 1 right
pub fn sign(s:usize)f32{return if(s==0)-1 else 1;}
pub fn parent(b:Bone)?Bone{
  return switch(b){
    .pelvis=>null,
    .waist,.tail0,.thighL,.thighR=>.pelvis,
    .chest,.gut,.gutTop=>.waist,
    .neck,.armL,.armR=>.chest,
    .head=>.neck,
    .jaw,.earL,.earR=>.head,
    .tail1=>.tail0,
    .tail2=>.tail1,
    .tail3=>.tail2,
    .forearmL=>.armL,
    .forearmR=>.armR,
    .handL=>.forearmL,
    .handR=>.forearmR,
    .shinL=>.thighL,
    .shinR=>.thighR,
    .metaL=>.shinL,
    .metaR=>.shinR,
    .footL=>.metaL,
    .footR=>.metaR,
    .finger0L,.finger1L,.finger2L,.finger3L=>.handL,
    .finger0R,.finger1R,.finger2R,.finger3R=>.handR,
    .tip0L=>.finger0L,
    .tip1L=>.finger1L,
    .tip2L=>.finger2L,
    .tip3L=>.finger3L,
    .tip0R=>.finger0R,
    .tip1R=>.finger1R,
    .tip2R=>.finger2R,
    .tip3R=>.finger3R,
  };
}
/// lengths and joint places (metres)
pub const hipY:f32=0.7;
pub const waistAt=v3(0,0.1,0);
pub const chestAt=v3(0,0.16,0);
pub const neckAt=v3(0,0.21,0.02);
pub const headAt=v3(0,0.09,0.025);
pub const jawAt=v3(0,-0.012,0.012);
/// the belly's gut, in the waist's frame, and the sac's radii about it
/// (across, down, forward). As it fills it rounds out toward a ball
/// `GUT_FULL` across (far past anything a body would hold), its back held
/// to the body so it swells forward, and drops (per unit of fill)
pub const gutAt=v3(0,-0.035,0.058);
pub const gutR=v3(0.11,0.095,0.086);
pub const gutFull:f32=0.3;
pub const gutDrop:f32=0.11;
pub const gutGrow=m.splat3(gutFull)/gutR-m.splat3(1);
pub const gutShift=v3(0,-gutDrop,gutFull-gutR[2]);
/// how far the sac reaches up from the gut's centre toward the ribs
pub const gutUp:f32=0.21;
/// the sac's upper half swells on its own bone (`gut_top`): as wide as the
/// gut, but its height grows only by the drop, so its top stays where it
/// hangs from the ribs while the half below rounds out, and nothing above
/// is lifted past where the waist holds it (so blending the two never
/// folds the sac over)
pub const gutGrowTop=v3(gutGrow[0],gutDrop/gutUp,gutGrow[2]);
pub const shoulder=v3(0.185,0.17,-0.01);
pub const upperArm:f32=0.25;
pub const forearmLength:f32=0.24;
/// the fingers: knuckles this far down the hand, spread across it (z);
/// each fans out from the middle by `SPLAY` at its edge; the segments'
/// lengths (the middle two longer)
pub const knuckleY:f32=0.08;
pub const knuckles=[fingerCount]f32{-0.0465,-0.0155,0.0155,0.0465};
pub const splay:f32=0.16;
pub const proximal=[fingerCount]f32{0.03,0.036,0.036,0.03};
pub const distal=[fingerCount]f32{0.026,0.03,0.03,0.026};
pub const hipX:f32=0.105;
pub const thighLength:f32=0.22;
pub const shinLength:f32=0.26;
pub const metaLength:f32=0.335;
pub const tailAt=v3(0,0.12,-0.13);
pub const tailSeg:f32=0.12;
/// the tail leaves the rear up and back, this far (radians) from straight up
pub const tailTilt:f32=-(m.halfPi-m.pi/6.0);
/// where an ear roots on the skull (x for the right one)
pub const earAt=v3(0.05,0.092,-0.012);
/// ears lean forward and out by this much at rest
pub const earTilt:f32=m.rad(12);
/// a joint's turn (engine anim/rig.zig): about X (pitch: + tips a limb's
/// -Y backward, a spine's +Y forward), then Y (twist), then Z (roll)
pub const Turn=rig.Turn;
pub const Limb=struct{
  /// the arm's shoulder or the leg's hip
  root:Turn=.{},
  /// elbow (+ bends the forearm forward) or knee (+ folds the shin back)
  mid:f32=0,
  /// wrist, or the hock (- swings the metatarsal forward)
  low:Turn=.{},
  /// the foot's turn at the ball (legs only)
  foot:f32=0,
};
/// a hand's fingers: how far each curls in toward the palm at its knuckle
/// and at its tip joint (radians), and how far they fan apart beyond
/// their rest (0 rest, 1 twice as wide, -1 together)
pub const Hand=struct{
  curl:[fingerCount]f32=@splat(0),
  tip:[fingerCount]f32=@splat(0),
  spread:f32=0,
};
/// everything the rig decides about the body's shape this frame
pub const Pose=struct{
  /// the pelvis's place in wolf space and its turn
  hip:V3=v3(0,hipY,0),
  pelvis:Turn=.{},
  waist:Turn=.{},
  chest:Turn=.{},
  neck:Turn=.{},
  head:Turn=.{},
  jaw:f32=0,
  /// how full the belly is (0..1)
  gut:f32=0,
  arms:[2]Limb=.{restArm(0),restArm(1)},
  legs:[2]Limb=.{restLeg(0),restLeg(1)},
  hands:[2]Hand=@splat(.{}),
  tail:[tailCount]Turn=@splat(.{}),
  ears:[2]Turn=@splat(.{}),
  /// the chest's breath (x and z swell)
  breath:f32=1,
};
/// the arms of the bind pose hang out from the body, clear of it
pub const bindArmOut:f32=0.42;
fn restArm(s:usize)Limb{return.{.root=.{.z=sign(s)*bindArmOut},.mid=0.25,.low=.{}};}
/// a digitigrade leg at rest: the thigh a little forward, the shin folded
/// back to a high hock, the metatarsal forward to the ball, the foot level
pub const restThigh:f32=-0.25;
pub const restKnee:f32=0.87;
pub const restHock:f32=-1.23;
/// the legs stand a little apart
pub const legOut:f32=0.05;
fn restLeg(s:usize)Limb{return.{.root=.{.x=restThigh,.z=sign(s)*legOut},.mid=restKnee,.low=.{.x=restHock},.foot=-(restThigh+restKnee+restHock)};}
/// each bone's frame in wolf space for `p` (its joint at the origin)
pub fn fk(p:Pose)[count]M4{
  var w:[count]M4=undefined;
  const set=struct{
    fn f(out:*[count]M4,b:Bone,mat:M4)void{out[@intFromEnum(b)]=mat;}
  }.f;
  const at=struct{
    fn f(out:*const[count]M4,b:Bone)M4{return out[@intFromEnum(b)];}
  }.f;
  set(&w,.pelvis,m.chain(&.{t(p.hip),p.pelvis.m4()}));
  set(&w,.waist,m.chain(&.{at(&w,.pelvis),t(waistAt),p.waist.m4()}));
  set(&w,.chest,m.chain(&.{at(&w,.waist),t(chestAt),p.chest.m4()}));
  set(&w,.neck,m.chain(&.{at(&w,.chest),t(neckAt),p.neck.m4()}));
  set(&w,.head,m.chain(&.{at(&w,.neck),t(headAt),p.head.m4()}));
  set(&w,.jaw,m.chain(&.{at(&w,.head),t(jawAt),m.rotX(p.jaw)}));
  set(&w,.gut,m.chain(&.{at(&w,.waist),t(gutAt+gutShift*m.splat3(p.gut)),m.scale3(m.splat3(1)+gutGrow*m.splat3(p.gut))}));
  set(&w,.gutTop,m.chain(&.{at(&w,.waist),t(gutAt+gutShift*m.splat3(p.gut)),m.scale3(m.splat3(1)+gutGrowTop*m.splat3(p.gut))}));
  var tail=m.chain(&.{at(&w,.pelvis),t(tailAt),m.rotX(tailTilt)});
  inline for(.{Bone.tail0,Bone.tail1,Bone.tail2,Bone.tail3},0..)|b,i|{
    if(i>0)tail=m.chain(&.{tail,t(v3(0,tailSeg,0))});
    tail=m.chain(&.{tail,p.tail[i].m4()});
    set(&w,b,tail);
  }
  for(sides,0..)|sd,s|{
    const x=sign(s);
    const arm=p.arms[s];
    set(&w,sd.arm,m.chain(&.{at(&w,.chest),t(shoulder*v3(x,1,1)),arm.root.m4()}));
    set(&w,sd.forearm,m.chain(&.{at(&w,sd.arm),t(v3(0,-upperArm,0)),m.rotX(-arm.mid)}));
    set(&w,sd.hand,m.chain(&.{at(&w,sd.forearm),t(v3(0,-forearmLength,0)),arm.low.m4()}));
    // fingers hang down the hand, fanned across it, and curl in toward the
    // palm, which faces the body (-x on the right hand)
    const hd=p.hands[s];
    for(sd.fingers,sd.tips,0..)|fb,tb,i|{
      const fan=-splay*(knuckles[i]/knuckles[fingerCount-1])*(1+hd.spread);
      set(&w,fb,m.chain(&.{at(&w,sd.hand),t(v3(0,-knuckleY,knuckles[i])),m.rotX(fan),m.rotZ(-x*hd.curl[i])}));
      set(&w,tb,m.chain(&.{at(&w,fb),t(v3(0,-proximal[i],0)),m.rotZ(-x*hd.tip[i])}));
    }
    const leg=p.legs[s];
    set(&w,sd.thigh,m.chain(&.{at(&w,.pelvis),t(v3(x*hipX,0,0)),leg.root.m4()}));
    set(&w,sd.shin,m.chain(&.{at(&w,sd.thigh),t(v3(0,-thighLength,0)),m.rotX(leg.mid)}));
    set(&w,sd.meta,m.chain(&.{at(&w,sd.shin),t(v3(0,-shinLength,0)),leg.low.m4()}));
    set(&w,sd.foot,m.chain(&.{at(&w,sd.meta),t(v3(0,-metaLength,0)),m.rotX(leg.foot)}));
    set(&w,sd.ear,m.chain(&.{at(&w,.head),t(earAt*v3(x,1,1)),m.rotZ(-x*earTilt),m.rotX(earTilt),p.ears[s].m4()}));
  }
  return w;
}
/// the pose the wolf's meshes are built in
pub fn bind()[count]M4{return fk(.{});}
/// the matrices the GPU skins with: each carries a vertex from the bind
/// pose to `world` (`bind_inv` from `inverses(bind())`); the chest's
/// breath swells it about its own axis
pub fn skin(world:[count]M4,bindInv:*const[count]M4,breath:f32)[count]M4{
  var out:[count]M4=undefined;
  for(&out,world,bindInv,0..)|*o,wm,inv,i|{
    const swell=if(i==@intFromEnum(Bone.chest))m.scale3(v3(breath,1,breath))else m.identity;
    o.*=m.chain(&.{wm,swell,inv});
  }
  return out;
}
pub fn inverses(mats:[count]M4)[count]M4{return rig.inverses(count,mats);}
test"the bind pose stands on the ground, the arms clear of the body"{
  const w=bind();
  for(sides)|sd|{
    const foot=m.origin(w[@intFromEnum(sd.foot)]);
    try testing.expectApproxEqAbs(@as(f32,0),foot[1],0.02);
    const hand=m.origin(w[@intFromEnum(sd.hand)]);
    try testing.expect(@abs(hand[0])>0.3);
  }
  // the skin of the bind pose is the identity
  const s=skin(w,&inverses(w),1);
  for(s)|mat|inline for(0..4)|c|inline for(0..4)|r|{
    try testing.expectApproxEqAbs(m.identity[c][r],mat[c][r],1e-5);
  };
}
