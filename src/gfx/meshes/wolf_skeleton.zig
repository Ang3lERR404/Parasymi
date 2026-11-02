//! the vine-wolf's skeleton: its bones, how they hang together and the pose
//! they take. The wolf is one skinned surface (`wolf_body`) built around
//! this skeleton in its bind pose (`bind`); the rig (game/player.zig) poses
//! it every frame and the GPU carries each vertex with its bones. Wolf
//! space: the ground under the hips at the origin, +Y up, +Z forward.
//!
//! Every limb bone runs down its local -Y from the joint it turns at to the
//! next; the spine, neck and tail run up +Y.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the test helpers, for the bind pose's checks
const testing=std.testing;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, matrices, angles
const m=engine.core.math;
/// the engine's rig: joint turns and matrix inverses
const rig=engine.anim.rig;
/// a point or direction in 3D
const V3=m.V3;
/// makes a `V3` from three numbers
const v3=m.v3;
/// a 4x4 transform: one bone's frame
const M4=m.M4;
/// a move by an offset, short for the long chains in `fk`
const t=m.translate;
/// every bone of the wolf, its index the slot its matrix fills in the
/// skinning array (parents before children)
pub const Bone=enum(u8){
  /// the hips: the root every other bone hangs from
  pelvis,
  /// the lower back, rising off the pelvis
  waist,
  /// the ribcage, which breathes
  chest,
  /// the neck, rising off the chest
  neck,
  /// the skull
  head,
  /// the lower jaw, hinged under the skull
  jaw,
  /// the belly's sac, which swells as it fills
  gut,
  /// the tail's first segment, at the rear
  tail0,
  /// the tail's second segment
  tail1,
  /// the tail's third segment
  tail2,
  /// the tail's last segment, its tip
  tail3,
  /// the left upper arm, from the shoulder
  armL,
  /// the left forearm, from the elbow
  forearmL,
  /// the left hand, from the wrist
  handL,
  /// the left thigh, from the hip
  thighL,
  /// the left shin, from the knee
  shinL,
  /// the left metatarsal, the long bone from the hock to the ball
  metaL,
  /// the left foot, from the ball
  footL,
  /// the left ear, from its root on the skull
  earL,
  /// the right upper arm, from the shoulder
  armR,
  /// the right forearm, from the elbow
  forearmR,
  /// the right hand, from the wrist
  handR,
  /// the right thigh, from the hip
  thighR,
  /// the right shin, from the knee
  shinR,
  /// the right metatarsal, the long bone from the hock to the ball
  metaR,
  /// the right foot, from the ball
  footR,
  /// the right ear, from its root on the skull
  earR,
  // each hand's four fingers: the knuckle's segment, then the tip's
  /// the left hand's first finger, its knuckle segment
  finger0L,
  /// the left hand's second finger, its knuckle segment
  finger1L,
  /// the left hand's third finger, its knuckle segment
  finger2L,
  /// the left hand's fourth finger, its knuckle segment
  finger3L,
  /// the left hand's first fingertip
  tip0L,
  /// the left hand's second fingertip
  tip1L,
  /// the left hand's third fingertip
  tip2L,
  /// the left hand's fourth fingertip
  tip3L,
  /// the right hand's first finger, its knuckle segment
  finger0R,
  /// the right hand's second finger, its knuckle segment
  finger1R,
  /// the right hand's third finger, its knuckle segment
  finger2R,
  /// the right hand's fourth finger, its knuckle segment
  finger3R,
  /// the right hand's first fingertip
  tip0R,
  /// the right hand's second fingertip
  tip1R,
  /// the right hand's third fingertip
  tip2R,
  /// the right hand's fourth fingertip
  tip3R,
  /// the gut's upper half, which swells on its own (see `gutGrowTop`)
  gutTop,
};
/// how many bones the wolf has
pub const count=@typeInfo(Bone).@"enum".fields.len;
/// how many segments its tail has
pub const tailCount=4;
/// how many fingers each hand has
pub const fingerCount=4;
/// one side's bones (left -X or right +X): arm, forearm, hand, thigh, shin,
/// metatarsal, foot, ear, and the hand's fingers and their tips
pub const Side=struct{arm:Bone,forearm:Bone,hand:Bone,thigh:Bone,shin:Bone,meta:Bone,foot:Bone,ear:Bone,fingers:[fingerCount]Bone,tips:[fingerCount]Bone};
/// both sides' bones: left first, then right
pub const sides=[2]Side{
  .{.arm=.armL,.forearm=.forearmL,.hand=.handL,.thigh=.thighL,.shin=.shinL,.meta=.metaL,.foot=.footL,.ear=.earL,
     .fingers=.{.finger0L,.finger1L,.finger2L,.finger3L},.tips=.{.tip0L,.tip1L,.tip2L,.tip3L}},
  .{.arm=.armR,.forearm=.forearmR,.hand=.handR,.thigh=.thighR,.shin=.shinR,.meta=.metaR,.foot=.footR,.ear=.earR,
     .fingers=.{.finger0R,.finger1R,.finger2R,.finger3R},.tips=.{.tip0R,.tip1R,.tip2R,.tip3R}},
};
/// which way out side `s` lies: -1 left, 1 right
pub fn sign(s:usize)f32{return if(s==0)-1 else 1;}
/// the bone `b` hangs from, or null for the pelvis, the root
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
/// lengths and joint places (metres); the hips stand this high off the ground
pub const hipY:f32=0.7;
/// where the waist joins, up from the pelvis
pub const waistAt=v3(0,0.1,0);
/// where the chest joins, up from the waist
pub const chestAt=v3(0,0.16,0);
/// where the neck joins, up and a little forward from the chest
pub const neckAt=v3(0,0.21,0.02);
/// where the skull sits, atop the neck
pub const headAt=v3(0,0.09,0.025);
/// where the jaw hinges, under and forward of the skull's joint
pub const jawAt=v3(0,-0.012,0.012);
/// where the belly's gut sits, in the waist's frame. As the sac fills it
/// rounds out toward a ball `gutFull` across (far past anything a body
/// would hold), its back held to the body so it swells forward, and drops
pub const gutAt=v3(0,-0.035,0.058);
/// the empty sac's radii: across, down and forward
pub const gutR=v3(0.13,0.115,0.1);
/// how wide the sac grows when full, a ball this far across
pub const gutFull:f32=0.3;
/// how far the sac drops per unit of fill
pub const gutDrop:f32=0.11;
/// how much the sac's scale grows per unit of fill, each way, to round out to `gutFull`
pub const gutGrow=m.splat3(gutFull)/gutR-m.splat3(1);
/// how far the sac's centre moves per unit of fill: down, and forward so its back stays put
pub const gutShift=v3(0,-gutDrop,gutFull-gutR[2]);
/// how far the sac reaches up from the gut's centre toward the ribs
pub const gutUp:f32=0.21;
/// the sac's upper half swells on its own bone (`gutTop`): as wide as the
/// gut, but its height grows only by the drop, so its top stays where it
/// hangs from the ribs while the half below rounds out, and nothing above
/// is lifted past where the waist holds it (so blending the two never
/// folds the sac over)
pub const gutGrowTop=v3(gutGrow[0],gutDrop/gutUp,gutGrow[2]);
/// where the shoulder joins the chest (x for the right one)
pub const shoulder=v3(0.185,0.17,-0.01);
/// the upper arm's length, shoulder to elbow
pub const upperArm:f32=0.25;
/// the forearm's length, elbow to wrist
pub const forearmLength:f32=0.24;
/// the fingers: knuckles this far down the hand, spread across it (z);
/// each fans out from the middle by `splay` at its edge; the segments'
/// lengths (the middle two longer). How far down the hand the knuckles sit
pub const knuckleY:f32=0.08;
/// where each finger roots across the hand (z)
pub const knuckles=[fingerCount]f32{-0.051,-0.017,0.017,0.051};
/// how far the outer fingers fan from the middle at rest (radians)
pub const splay:f32=0.16;
/// each finger's knuckle segment's length
pub const proximal=[fingerCount]f32{0.036,0.043,0.043,0.036};
/// each fingertip segment's length
pub const distal=[fingerCount]f32{0.032,0.036,0.036,0.032};
/// how far out from the middle each hip joint sits
pub const hipX:f32=0.12;
/// the thigh's length, hip to knee
pub const thighLength:f32=0.22;
/// the shin's length, knee to hock
pub const shinLength:f32=0.26;
/// the metatarsal's length, hock to ball
pub const metaLength:f32=0.335;
/// where the tail leaves the pelvis, up and back
pub const tailAt=v3(0,0.12,-0.13);
/// each tail segment's length
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
/// how one limb is turned: at its root, middle and low joint, and the foot
pub const Limb=struct{
  /// the arm's shoulder or the leg's hip
  root:Turn=.{},
  /// elbow (+ bends the forearm forward) or knee (+ folds the shin back)
  mid:f32=0,
  /// wrist, or the hock (- swings the metatarsal forward)
  low:Turn=.{},
  /// the foot's turn at the ball (legs only)
  foot:f32=0,
  /// the foot's roll about its own length, laying its sole flat across a
  /// slope (legs only)
  roll:f32=0,
};
/// a hand's fingers: how each curls in toward the palm, and how they fan
pub const Hand=struct{
  /// how far each finger curls in toward the palm at its knuckle (radians)
  curl:[fingerCount]f32=@splat(0),
  /// how far each fingertip curls in at its joint (radians)
  tip:[fingerCount]f32=@splat(0),
  /// how far the fingers fan beyond their rest (0 rest, 1 twice as wide, -1 together)
  spread:f32=0,
};
/// everything the rig decides about the body's shape this frame
pub const Pose=struct{
  /// the pelvis's place in wolf space
  hip:V3=v3(0,hipY,0),
  /// the pelvis's turn
  pelvis:Turn=.{},
  /// the waist's turn
  waist:Turn=.{},
  /// the chest's turn
  chest:Turn=.{},
  /// the neck's turn
  neck:Turn=.{},
  /// the skull's turn
  head:Turn=.{},
  /// how far the jaw hangs open (radians)
  jaw:f32=0,
  /// how full the belly is (0..1)
  gut:f32=0,
  /// each arm's turns, left then right (at rest, hanging out)
  arms:[2]Limb=.{restArm(0),restArm(1)},
  /// each leg's turns, left then right (at rest, standing)
  legs:[2]Limb=.{restLeg(0),restLeg(1)},
  /// each hand's fingers, left then right
  hands:[2]Hand=@splat(.{}),
  /// each tail segment's turn, root to tip
  tail:[tailCount]Turn=@splat(.{}),
  /// each ear's turn beyond its rest lean, left then right
  ears:[2]Turn=@splat(.{}),
  /// the chest's breath (x and z swell)
  breath:f32=1,
};
/// the arms of the bind pose hang out from the body, clear of it
pub const bindArmOut:f32=0.42;
/// an arm at rest on side `s`: swung out clear of the body, the elbow a little bent
fn restArm(s:usize)Limb{return.{.root=.{.z=sign(s)*bindArmOut},.mid=0.25,.low=.{}};}
/// a digitigrade leg at rest: the thigh a little forward, the shin folded
/// back to a high hock, the metatarsal forward to the ball, the foot level.
/// The thigh's rest swing (radians)
pub const restThigh:f32=-0.25;
/// the knee's rest fold (radians)
pub const restKnee:f32=0.87;
/// the hock's rest turn, the metatarsal swung forward (radians)
pub const restHock:f32=-1.23;
/// the legs stand a little apart
pub const legOut:f32=0.05;
/// a leg at rest on side `s`: digitigrade, set a little apart, the foot
/// turned back level and its sole rolled flat. The hip rolls out first and
/// then swings, as the leg's solve (player/ik.zig `solveLeg`) composes it,
/// so the solve reaching the resting foot finds this very pose
fn restLeg(s:usize)Limb{
  // the hip's roll out to the side
  const out=sign(s)*legOut;
  return.{.root=rig.turnOf(m.mul(m.rotZ(out),m.rotX(restThigh))),.mid=restKnee,.low=.{.x=restHock},.foot=-(restThigh+restKnee+restHock),.roll=-out};
}
/// each bone's frame in wolf space for `p` (its joint at the origin)
pub fn fk(p:Pose)[count]M4{
  // each bone's frame, filled parent first
  var w:[count]M4=undefined;
  // stores bone `b`'s frame in the array
  const set=struct{
    /// writes `mat` as bone `b`'s frame
    fn f(out:*[count]M4,b:Bone,mat:M4)void{out[@intFromEnum(b)]=mat;}
  }.f;
  // reads bone `b`'s frame back out of the array
  const at=struct{
    /// bone `b`'s frame, already set
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
  // the tail's frame so far, walked down it segment by segment
  var tail=m.chain(&.{at(&w,.pelvis),t(tailAt),m.rotX(tailTilt)});
  inline for(.{Bone.tail0,Bone.tail1,Bone.tail2,Bone.tail3},0..)|b,i|{
    if(i>0)tail=m.chain(&.{tail,t(v3(0,tailSeg,0))});
    tail=m.chain(&.{tail,p.tail[i].m4()});
    set(&w,b,tail);
  }
  for(sides,0..)|sd,s|{
    // which way out this side is (-1 left, 1 right), and its arm's turns
    const x=sign(s);
    const arm=p.arms[s];
    set(&w,sd.arm,m.chain(&.{at(&w,.chest),t(shoulder*v3(x,1,1)),arm.root.m4()}));
    set(&w,sd.forearm,m.chain(&.{at(&w,sd.arm),t(v3(0,-upperArm,0)),m.rotX(-arm.mid)}));
    set(&w,sd.hand,m.chain(&.{at(&w,sd.forearm),t(v3(0,-forearmLength,0)),arm.low.m4()}));
    // fingers hang down the hand, fanned across it, and curl in toward the
    // palm, which faces the body (-x on the right hand)
    const hd=p.hands[s];
    for(sd.fingers,sd.tips,0..)|fb,tb,i|{
      // how far this finger fans from the middle: more toward the edges, more as it spreads
      const fan=-splay*(knuckles[i]/knuckles[fingerCount-1])*(1+hd.spread);
      set(&w,fb,m.chain(&.{at(&w,sd.hand),t(v3(0,-knuckleY,knuckles[i])),m.rotX(fan),m.rotZ(-x*hd.curl[i])}));
      set(&w,tb,m.chain(&.{at(&w,fb),t(v3(0,-proximal[i],0)),m.rotZ(-x*hd.tip[i])}));
    }
    // this side's leg turns
    const leg=p.legs[s];
    set(&w,sd.thigh,m.chain(&.{at(&w,.pelvis),t(v3(x*hipX,0,0)),leg.root.m4()}));
    set(&w,sd.shin,m.chain(&.{at(&w,sd.thigh),t(v3(0,-thighLength,0)),m.rotX(leg.mid)}));
    set(&w,sd.meta,m.chain(&.{at(&w,sd.shin),t(v3(0,-shinLength,0)),leg.low.m4()}));
    set(&w,sd.foot,m.chain(&.{at(&w,sd.meta),t(v3(0,-metaLength,0)),m.rotX(leg.foot),m.rotZ(leg.roll)}));
    set(&w,sd.ear,m.chain(&.{at(&w,.head),t(earAt*v3(x,1,1)),m.rotZ(-x*earTilt),m.rotX(earTilt),p.ears[s].m4()}));
  }
  return w;
}
/// the pose the wolf's meshes are built in
pub fn bind()[count]M4{return fk(.{});}
/// the matrices the GPU skins with: each carries a vertex from the bind
/// pose to `world` (`bindInv` from `inverses(bind())`); the chest's
/// breath swells it about its own axis
pub fn skin(world:[count]M4,bindInv:*const[count]M4,breath:f32)[count]M4{
  // each bone's skinning matrix
  var out:[count]M4=undefined;
  for(&out,world,bindInv,0..)|*o,wm,inv,i|{
    // the chest's breathing swell, nothing for any other bone
    const swell=if(i==@intFromEnum(Bone.chest))m.scale3(v3(breath,1,breath))else m.identity;
    o.*=m.chain(&.{wm,swell,inv});
  }
  return out;
}
/// every bone's frame inverted, for carrying vertices back out of the bind pose
pub fn inverses(mats:[count]M4)[count]M4{return rig.inverses(count,mats);}
test"the bind pose stands on the ground, the arms clear of the body"{
  // the bind pose's frames
  const w=bind();
  for(sides)|sd|{
    // where this side's foot stands
    const foot=m.origin(w[@intFromEnum(sd.foot)]);
    try testing.expectApproxEqAbs(@as(f32,0),foot[1],0.02);
    // where this side's hand hangs
    const hand=m.origin(w[@intFromEnum(sd.hand)]);
    try testing.expect(@abs(hand[0])>0.3);
  }
  // the skin of the bind pose is the identity
  // the skinning matrices for the bind pose itself, unbreathing
  const s=skin(w,&inverses(w),1);
  for(s)|mat|inline for(0..4)|c|inline for(0..4)|r|{
    try testing.expectApproxEqAbs(m.identity[c][r],mat[c][r],1e-5);
  };
}
