//! the wolf posed: the skeleton from its state, and its parts for the renderer.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type emitting parts may fail with
const Allocator=std.mem.Allocator;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, matrices, turns, easing
const m=engine.core.math;
/// the wolf's skeleton: bones, pose, forward kinematics and skinning
const skel=lib.skeleton;
/// the wolf's body mesh: where its nose, pads and beans sit
const bodyMesh=lib.wolfBody;
/// the belly's mesh: its radii, its top, where its folds cross
const bellyMesh=lib.wolfBelly;
/// the library meshes: the pectorals' and rear's ids
const meshlib=lib.meshlib;
/// the scene's moving parts and how each looks
const parts=lib.parts;
/// the scene's list of moving parts the wolf adds to each frame
const Parts=parts.Parts;
/// a point or direction in 3D
const V3=m.V3;
/// builds a 3D vector from its three parts
const v3=m.v3;
/// a 4x4 transform
const M4=m.M4;
/// a transform that moves by a vector
const translate=m.translate;
/// a transform that scales by a vector
const scale=m.scale3;
/// one bone of the wolf's skeleton
const Bone=skel.Bone;
/// how far the arms hang out from the body (radians)
const armOut=lib.player.tuning.armOut;
/// the paw beans' glow
const beanGlow=lib.player.tuningLook.beanGlow;
/// how dense the beans' and nose's sap is (0..1)
const beanOpacity=lib.player.tuningLook.beanOpacity;
/// the paw beans' colour
const beanTint=lib.player.tuningLook.beanTint;
/// how far a full belly pushes the arms out (radians)
const bellyArms=lib.player.tuning.bellyArms;
/// the belly sap's glow when empty
const bellyGlow=lib.player.tuningLook.bellyGlow;
/// how much more the belly sap glows once full
const bellyGlowFull=lib.player.tuningLook.bellyGlowFull;
/// how far the pelvis bobs down at each footfall (m)
const bobAmount=lib.player.tuning.bobAmount;
/// how much its fur leaves stir
const bodyFlutter=lib.player.tuningLook.bodyFlutter;
/// the body's glow
const bodyGlow=lib.player.tuningLook.bodyGlow;
/// how high its middle sits, for culling and detail (m)
const bodyMid=lib.player.tuningLook.bodyMid;
/// how far the chest swells with each breath at rest
const breathAmount=lib.player.tuning.breathAmount;
/// how far it swells at a run
const breathRun=lib.player.tuning.breathRun;
/// how far the chest turns against the hips (a share)
const counter=lib.player.tuning.counter;
/// the inner ears' glow
const earGlow=lib.player.tuningLook.earGlow;
/// the inner ears' sap opacity
const earOpacity=lib.player.tuningLook.earOpacity;
/// where the eyes sit in the head's frame
const eyesAt=lib.player.tuningLook.eyesAt;
/// the head's bones, hidden from its own eyes
const headBones=lib.player.tuningLook.headBones;
/// how far the pelvis rolls with the stride (radians)
const hipRoll=lib.player.tuning.hipRoll;
/// how far the pelvis turns with the stride (radians)
const hipTurn=lib.player.tuning.hipTurn;
/// the nose's glow
const noseGlow=lib.player.tuningLook.noseGlow;
/// the nose's colour
const noseTint=lib.player.tuningLook.noseTint;
/// how far a planted foot's central pad flattens (a share)
const padFlatten=lib.player.tuningLook.padFlatten;
/// how far the jaw drops open, panting at a run (radians)
const pant=lib.player.tuning.pant;
/// the pectorals' opacity
const pecOpacity=lib.player.tuningLook.pecOpacity;
/// how far the body rocks back with the pull (radians)
const pryRock=lib.player.tuning.pryRock;
/// how far the wrists twist in the wrench (radians)
const pryTwist=lib.player.tuning.pryTwist;
/// where in a unit's pry the pull ends (0..1)
const pullEnd=lib.player.tuning.pullEnd;
/// the wolf being posed
const Player=lib.player.player.Player;
/// how far the hip-leaning elbow swings out (radians)
const restElbowOut=lib.player.tuning.restElbowOut;
/// where the left paw leans on the hip (pelvis frame)
const restHip=lib.player.tuning.restHip;
/// where on the sac the right palm lies (its angles up and round it)
const restOn=lib.player.tuning.restOn;
/// how far the resting palm's middle sits off the sac (m)
const restPalm=lib.player.tuning.restPalm;
/// how far down the hand from the wrist the palm's middle is (m)
const restHeel=lib.player.tuning.restHeel;
/// how far in toward the belly's middle the resting fingers point
const restInward=lib.player.tuning.restInward;
/// the share of the arm's length the resting wrist may be from the shoulder
const restReach=lib.player.tuning.restReach;
/// how high up the sac the resting paw may slide (radians from the bottom)
const restTop=lib.player.tuning.restTop;
/// how many halvings find where up the sac the paw is in reach
const restSteps=lib.player.tuning.restSteps;
/// the rear's opacity
const rumpOpacity=lib.player.tuningLook.rumpOpacity;
/// how much more a full, stretched sac lets show through
const sapStretch=lib.player.tuning.sapStretch;
/// how far the pelvis sinks at full stride (m)
const sinkAmount=lib.player.tuning.sinkAmount;
/// how far the hips drop in the gathering squat (m)
const squatDrop=lib.player.tuning.squatDrop;
/// how far the body leans in over the node (radians)
const squatLean=lib.player.tuning.squatLean;
/// how far it leans back, stretched up to work over its head (radians)
const riseLean=lib.player.tuning.riseLean;
/// how far its hips lift, stretched up (m)
const riseUp=lib.player.tuning.riseUp;
/// how far down the hand from the wrist a plucked bead is held (m)
const beadOut=lib.player.tuning.beadOut;
/// a plucked bead's radius (m)
const beadR=lib.player.tuning.beadR;
/// the item pod's own radius (gfx/meshes/item_pod.zig), sized to a bead
const podR:f32=0.09;
/// how brightly a plucked bead glows
const beadGlow=lib.player.tuning.beadGlow;
/// colour types, for a plucked bead's tint
const color=engine.core.color;
/// how far the pelvis sways over the planted foot (m)
const swayAmount=lib.player.tuning.swayAmount;
/// how much more the metatarsal folds mid-swing (radians)
const swingFold=lib.player.tuning.swingFold;
/// how far each tail joint past the root droops at rest (radians)
const tailDroop=lib.player.tuningLook.tailDroop;
/// how far the tail's root lifts at full stride (radians)
const tailLift=lib.player.tuningLook.tailLift;
/// how far a finger's tip joint is bent at rest (radians)
const tipRest=lib.player.tuningLook.tipRest;
/// how much of the knuckle's curl the tip joint follows
const tipShare=lib.player.tuningLook.tipShare;
/// how far the toes hang as a foot swings (radians)
const toeHang=lib.player.tuning.toeHang;
/// where in a unit's pry the wrench ends (0..1)
const wrenchEnd=lib.player.tuning.wrenchEnd;
/// how far a gripping paw's fingers cup in toward what it holds (a share of the forearm's line)
const gripCup:f32=0.45;
/// how far they tip down over it (a share of the forearm's line)
const gripDown:f32=0.2;
/// the engine's rig helpers: a turn read out of a frame, the trailing chain
const animRig=engine.anim.rig;
/// the share of the turn toward the gaze the neck takes
const neckShare=lib.player.tuningLook.neckShare;
/// how strongly the tail is drawn back to its rest shape (1/s at its root)
const tailStiff=lib.player.tuningLook.tailStiff;
/// how much of its own motion the tail keeps (a sixtieth of a second's)
const tailKeep=lib.player.tuningLook.tailKeep;
/// the bind pose, inverted, the skin matrices start from
const bindInv=lib.player.ik.bindInv;
/// how far through its pull and wrench a unit's pry is (0..1)
const pryPull=lib.player.ik.pryPull;
/// an arm reaching its wrist (inverse kinematics)
const solveArm=lib.player.ik.solveArm;
/// an arm reaching its wrist, the elbow swung round
const solveArmTurned=lib.player.ik.solveArmTurned;
/// a leg reaching its foot (inverse kinematics)
const solveLeg=lib.player.ik.solveLeg;
/// the skeleton's pose this frame, in wolf space (see wolf_skeleton);
/// a pose set from outside (`posed`) wins
pub fn pose(p:*const Player)skel.Pose{
  if(p.posed)|q|return q;
  // the pose, its tail laid along the trailing chain once there is one
  var q=restShape(p);
  if(p.tailAt)|pts|tailAlong(p,&q,pts);
  return q;
}
/// the pose before the tail trails: its tail in its swinging rest shape
fn restShape(p:*const Player)skel.Pose{
  // how far into stride, how far into the work gesture, how deep the squat
  const st=p.stride;
  const work=p.reach.x*(1-p.squat.x);
  const sq=p.squat.x;
  // the gait's phase as an angle
  const ph=p.phase*m.tau;
  // the pose, built up below
  var q:skel.Pose=.{};
  // the pelvis: lowest just after each footfall, over the planted foot;
  // gathering, down in a squat, the body leaning in and rocking back
  // with each pull
  // the gait, the bob, the pull's rock, and the body's lean
  const g=p.gait();
  const bob=bobAmount*g.bob*st*(0.5+0.5*@cos(2*ph-p.duty*m.tau));
  // (only as deep as the work is low; reaching up to it, stretched tall
  // and leaning back)
  const rock=pryRock*pryPull(p.gather orelse 0)*sq;
  const low=p.low.x;
  const rise=p.rise.x;
  const lean=p.lean.x-g.lean*(1-sq)+(squatLean*low-riseLean*rise-rock)*sq;
  q.hip=v3(swayAmount*g.sway*st*@sin(ph),skel.hipY-sinkAmount*g.sink*st-bob-0.07*work-(squatDrop*low-riseUp*rise)*sq,-0.04*sq*low);
  q.pelvis=.{.x=0.25*lean,.y=hipTurn*st*@sin(ph),.z=hipRoll*g.roll*st*@cos(ph)+p.bank.x};
  q.waist=.{.x=0.35*lean,.y=-0.5*counter*q.pelvis.y,.z=-0.4*q.pelvis.z};
  q.chest=.{.x=0.4*lean,.y=-0.5*counter*q.pelvis.y,.z=-0.4*q.pelvis.z};
  // where in its breath the wolf is, -1..1
  const breath=@sin(p.breath);
  q.breath=1+m.lerp(breathAmount,breathRun,st)*breath;
  // the head holds its gaze: neck and skull, as one chain, turn the head
  // to face just where it looks, whatever the body below does
  aimHead(&q,.{.x=p.nod.x+0.02*breath,.y=p.look.x,.z=-0.5*p.bank.x});
  q.jaw=pant*st*(0.6+0.4*breath);
  q.gut=p.fullness;
  for(0..2)|s|{
    // which side this is: -1 left, 1 right
    const x=skel.sign(s);
    q.arms[s]=.{
      .root=.{.x=p.arm[s].x,.z=x*(armOut+bellyArms*p.fullness+0.02*breath+0.1*work),.y=-x*0.15*work},
      .mid=p.elbow[s].x,
      .low=.{.x=0.2+0.3*work},
    };
    q.ears[s]=.{.x=p.ear[s].x,.z=0.15*x*p.ear[s].x};
    for(&q.hands[s].curl,&q.hands[s].tip,p.curl[s])|*c,*tp,sp|{
      c.*=sp.x;
      tp.*=tipRest+tipShare*sp.x;
    }
    q.hands[s].spread=p.spread[s].x;
  }
  // the tail lifts with the stride and droops at rest, each joint bending
  // a little further
  // (crouching, it lifts to balance the lean)
  for(&q.tail,p.tail,0..)|*j,sp,i|j.*=.{.x=(if(i==0)-tailLift*@max(st,sq*low)else tailDroop*(1-0.6*st)),.z=sp.x};
  q.hip[1]-=p.hipDrop(q);
  q.legs=p.legs(q);
  if(sq>0)p.armsToWrists(&q,sq);
  // how far into the belly-rest idle
  const resting=p.restPose.x*(1-sq);
  if(resting>0)restArms(&q,resting);
  return q;
}
/// the neck and skull turned, as one chain, so the head faces `gaze` (a
/// turn in wolf space: how far it looks round, nods and tilts): the neck
/// takes `neckShare` of the turn the chest leaves, the skull exactly the rest
fn aimHead(q:*skel.Pose,gaze:skel.Turn)void{
  // the chest's turn in wolf space, and the head's wanted from it
  const chest=m.chain(&.{q.pelvis.m4(),q.waist.m4(),q.chest.m4()});
  const want=gaze.m4();
  const rel=animRig.turnOf(m.chain(&.{m.inverseRigid(chest),want}));
  q.neck=.{.x=rel.x*neckShare,.y=rel.y*neckShare,.z=rel.z*neckShare};
  q.head=animRig.turnOf(m.chain(&.{m.inverseRigid(m.chain(&.{chest,q.neck.m4()})),want}));
}
/// each tail joint and its tip in wolf space, for pose `q`
fn tailJoints(q:skel.Pose)[skel.tailCount+1]V3{
  // the bones, and the joints filled in below
  const w=skel.fk(q);
  var out:[skel.tailCount+1]V3=undefined;
  inline for(.{Bone.tail0,Bone.tail1,Bone.tail2,Bone.tail3},0..)|b,i|out[i]=m.origin(w[@intFromEnum(b)]);
  out[skel.tailCount]=m.mulPoint(w[@intFromEnum(Bone.tail3)],v3(0,skel.tailSeg,0));
  return out;
}
/// one step of the tail trailing (motion.zig, after the springs): each
/// joint carries on with its own motion, is drawn back toward its place in
/// the tail's swinging rest shape and held at its length from the root, so
/// the tail swings through, lags a turn and settles as one chain
pub fn trailTail(p:*Player,dt:f32)void{
  // the rest shape this step, in the world
  var rest=tailJoints(restShape(p));
  const root=p.heading();
  for(&rest)|*r|r.*=m.mulPoint(root,r.*);
  // the chain, laid out on its rest shape the first time
  var pts=p.tailAt orelse blk:{
    p.tailWas=rest;
    break:blk rest;
  };
  animRig.trail(&pts,&p.tailWas,&rest,.{.stiff=tailStiff,.keep=tailKeep,.seg=skel.tailSeg},dt);
  p.tailAt=pts;
}
/// the tail's joints turned to lie along the trailing chain `pts` (in the
/// world): each segment turned in its parent's frame to run toward the next point
fn tailAlong(p:*const Player,q:*skel.Pose,pts:[skel.tailCount+1]V3)void{
  // the way into wolf space, and the tail's root frame
  const toWolf=m.inverseRigid(p.heading());
  const w=skel.fk(q.*);
  var frame=m.chain(&.{w[@intFromEnum(Bone.pelvis)],m.translate(skel.tailAt),m.rotX(skel.tailTilt)});
  for(0..skel.tailCount)|i|{
    if(i>0)frame=m.chain(&.{frame,m.translate(v3(0,skel.tailSeg,0))});
    // the way this segment runs, in its parent's frame
    const d=m.mulDir(m.inverseRigid(frame),m.mulDir(toWolf,pts[i+1]-pts[i]));
    const l=m.norm(d);
    // the turn that lays its +Y along it (no twist)
    q.tail[i]=.{.x=m.atan2(l[2],l[1]),.z=m.asin(-l[0])};
    frame=m.chain(&.{frame,q.tail[i].m4()});
  }
}
/// where the resting right paw lies on the belly in pose `q`: its wrist,
/// and (in the wolf's space) the way its fingers run and its palm faces
pub const BellyPaw=struct{
  /// where the wrist is wanted
  wrist:V3,
  /// the way the fingers run, along the sac
  fingers:V3,
  /// the way the palm faces, into the sac
  palm:V3,
  /// how far up the sac it lies (radians from the bottom)
  up:f32,
};
/// the right paw laid on the belly's skinned surface in pose `q`, its palm
/// flat on the sac, its fingers running down the curve and a little in
/// toward the middle: at `restOn`, or as a full belly swells out past the
/// arm's easy reach, slid up the sac just so far that the arm still
/// reaches it unstretched, so it lies on the belly at every fill
pub fn bellyPaw(q:skel.Pose)BellyPaw{
  // the bones, their skinning matrices as the GPU has them this frame, and the right shoulder
  const w=skel.fk(q);
  const skin=skel.skin(w,&bindInv(),q.breath);
  const shoulder=m.origin(w[@intFromEnum(skel.sides[1].arm)]);
  // how far from the shoulder the wrist may be
  const most=restReach*(skel.upperArm+skel.forearmLength);
  // where up the sac: `restOn`'s, or, out of reach there, found between it
  // and the top by halving (the wrist nears the shoulder going up)
  var lo=restOn[0];
  const rest=pawAt(&skin,lo);
  if(m.dist(rest.wrist,shoulder)<=most)return rest;
  var hi=restTop;
  for(0..restSteps)|_|{
    // halfway, and which half the reach falls in
    const mid=0.5*(lo+hi);
    if(m.dist(pawAt(&skin,mid).wrist,shoulder)>most)lo=mid else hi=mid;
  }
  return pawAt(&skin,hi);
}
/// the right paw laid on the sac `th` up it (and `restOn` round it), for
/// the bones' skinning matrices `skin`
fn pawAt(skin:*const[skel.count]M4,th:f32)BellyPaw{
  // where round the sac, a small step either way, and the sac's facing there
  const ph=restOn[1];
  const e:f32=0.02;
  const n=bellyMesh.posedNormal(skin,th,ph);
  // down the sac (toward its bottom) and round it toward its middle
  const down=bellyMesh.posed(skin,th-e,ph,1)-bellyMesh.posed(skin,th+e,ph,1);
  const inward=bellyMesh.posed(skin,th,ph+e,1)-bellyMesh.posed(skin,th,ph-e,1);
  // the fingers along the surface: down and in, nothing out of it
  const lay=m.norm(down)+m.norm(inward)*m.splat3(restInward);
  const fingers=m.norm(lay-n*m.splat3(m.dot(lay,n)));
  // the palm's middle just off the sac, the wrist up the hand from it
  const mid=bellyMesh.posed(skin,th,ph,1)+n*m.splat3(restPalm);
  return.{.wrist=mid-fingers*m.splat3(restHeel),.fingers=fingers,.palm=-n,.up=th};
}
/// the belly-rest idle, blended in by `r`: the right palm laid flat on the
/// belly's upper front (on its skinned surface, so at every fill); the left
/// on the hip, the wrist bent back and the elbow turned out
pub fn restArms(q:*skel.Pose,r:f32)void{
  // the bones in the wolf's space, and the way into the chest's frame
  const w=skel.fk(q.*);
  const into=m.inverseRigid(w[@intFromEnum(Bone.chest)]);
  // the right paw on the belly
  const paw=bellyPaw(q.*);
  // where each wrist is wanted: the left on the hip, the right on the belly
  const at=[2]V3{
    m.mulPoint(w[@intFromEnum(Bone.pelvis)],restHip*v3(-1,1,1)),
    paw.wrist,
  };
  for(0..2)|s|{
    // which side, how far the elbow swings out, and the arm reaching there
    const x=skel.sign(s);
    const out:f32=if(s==0)restElbowOut else 0;
    const ik=solveArmTurned(m.mulPoint(into,at[s])-skel.shoulder*v3(x,1,1),s,-x*out);
    // the arm being posed
    const a=&q.arms[s];
    a.root=skel.Turn.blend(a.root,ik.root,r);
    a.mid=m.lerp(a.mid,ik.mid,r);
    // (on the belly the paw lies flat along the sac; on the hip the wrist
    // cocks back)
    // the wrist's turn wanted
    const low:skel.Turn=if(s==0).{.x=-0.5,.z=x*0.3}else lib.player.ik.handTo(ik,s,m.mulDir(into,paw.fingers),m.mulDir(into,paw.palm));
    a.low=skel.Turn.blend(a.low,low,r);
  }
}
/// gathering: each arm blended (by `sq`) toward reaching its wrist's
/// target by inverse kinematics, the wrist twisting with the wrench
pub fn armsToWrists(p:*const Player,q:*skel.Pose,sq:f32)void{
  // the bones in the wolf's space, and the way into the chest's frame
  const w=skel.fk(q.*);
  const into=m.inverseRigid(w[@intFromEnum(Bone.chest)]);
  // the pry's unit share, and how far the wrists twist with the wrench
  const k=p.gather orelse 0;
  const twist=pryTwist*m.smooth(m.unlerp(pullEnd,wrenchEnd,k))*(1-m.smooth(m.unlerp(wrenchEnd,1,k)));
  // where each wrist is wanted, in the chest's frame
  const grip=[2]V3{m.mulPoint(into,p.wrist[0].pos),m.mulPoint(into,p.wrist[1].pos)};
  for(0..2)|s|{
    // which side, where the wrist is wanted from the shoulder, and the reach
    const x=skel.sign(s);
    const ik=solveArm(grip[s]-skel.shoulder*v3(x,1,1),s);
    // the paw turned to grip: its palm toward the other paw across what
    // they hold, its fingers on from the forearm, cupped over it and down
    const palm=m.norm(grip[1-s]-grip[s]);
    const fingers=m.norm(lib.player.ik.forearmDir(ik)+palm*m.splat3(gripCup)+v3(0,-gripDown,0));
    const hand=lib.player.ik.handTo(ik,s,fingers,palm);
    // the arm being posed
    const a=&q.arms[s];
    a.root=skel.Turn.blend(a.root,ik.root,sq);
    a.mid=m.lerp(a.mid,ik.mid,sq);
    // how far into stowing this paw is (0..1): it lets go its grip and
    // curls in toward the belly
    const stowing=m.clamp01(p.stowLeft(s)*3);
    const held=skel.Turn.blend(.{.x=hand.x,.y=hand.y-x*twist,.z=hand.z},.{.x=0.9},stowing);
    a.low=skel.Turn.blend(a.low,held,sq);
  }
}
/// what each leg reaches for in pose `q`: its foot from the hip joint in
/// the pelvis's frame, how folded and hanging it is mid-swing, and the
/// ground under it in wolf space
fn reaches(p:*const Player,q:skel.Pose)[2]lib.player.ik.Reach{
  // the two legs' reaches, filled in below
  var out:[2]lib.player.ik.Reach=undefined;
  // the way from the world into wolf space, and into the pelvis's frame
  const toWolf=m.inverseRigid(p.heading());
  const pelvis=m.chain(&.{translate(q.hip),q.pelvis.m4()});
  const into=m.inverseRigid(pelvis);
  for(&out,0..)|*r,s|{
    // the foot, in wolf space, then in the pelvis's frame
    const f=p.feet[s];
    const fw=m.mulV(toWolf,.{f.at[0],f.at[1],f.at[2],1});
    const fp=m.mulV(into,fw);
    // how far through its swing the foot is lifted (0 planted)
    const swing=if(f.planted())@as(f32,0)else@sin(f.t*m.pi);
    r.*=.{
      .d=v3(fp[0],fp[1],fp[2])-v3(skel.sign(s)*skel.hipX,0,0),
      .fold=swingFold*swing,.pelvis=q.pelvis,.hang=toeHang*swing,
      .ground=m.mulDir(toWolf,f.nrm),
    };
  }
  return out;
}
/// how far the hips drop so both feet reach the ground under them (a foot
/// down a slope or off a step pulls them down, never up)
pub fn hipDrop(p:*const Player,q:skel.Pose)f32{
  // the further of the two legs' overreach
  var drop:f32=0;
  for(reaches(p,q))|r|drop=@max(drop,lib.player.ik.overreach(r.d,r.fold));
  return@min(drop,lib.player.tuning.dropMax);
}
/// each leg reaching its foot, by inverse kinematics in the pelvis's frame
pub fn legs(p:*const Player,q:skel.Pose)[2]skel.Limb{
  // the two legs' turns, filled in below
  var out:[2]skel.Limb=undefined;
  for(&out,reaches(p,q))|*l,r|l.*=solveLeg(r);
  return out;
}
/// where its eyes are in the world this frame
pub fn eyes(p:*const Player)V3{
  // the bones in the wolf's space
  const w=skel.fk(p.pose());
  return m.mulPoint(m.mul(p.heading(),w[@intFromEnum(Bone.head)]),eyesAt);
}
/// emit every part; returns where each paw (left, right) touches down.
/// Seen from its own eyes (`headless`) its head is not drawn, though it
/// still casts its shadow.
pub fn rig(p:*const Player,out:*Parts,headless:bool)Allocator.Error![2]V3{
  // the pose, the wolf's place in the world, and the bones there
  const q=p.pose();
  const root=p.heading();
  var w=skel.fk(q);
  for(&w)|*b|b.*=m.mul(root,b.*);
  // the skin matrices, and where they go in the scene
  const skin=skel.skin(w,&bindInv(),q.breath);
  const base=try out.pose(&skin);
  // the body's middle, where it is culled and detailed about
  const mid=p.pos+v3(0,bodyMid,0);
  // a bone's transform, by name
  const at=struct{
    /// bone `b`'s transform out of the bones `ws`
    fn f(ws:*const[skel.count]M4,b:Bone)M4{return ws[@intFromEnum(b)];}
  }.f;
  // the bones hidden from its own eyes
  const hide:u64=if(headless)headBones else 0;
  try out.emitSkinned(.wolfBody,base,mid,.{.glow=bodyGlow,.flutter=bodyFlutter,.phase=0.1,.hide=hide});
  try out.emitSkinned(.wolfEars,base,mid,.{.glow=earGlow,.phase=0.5,.fade=earOpacity,.hide=hide});
  // the sheet of sap down its front, under the belly's sac
  try out.emitSkinned(.wolfPanel,base,mid,.{.phase=0.3,.fade=pecOpacity});
  if(!headless)try out.emit(.pawBean,m.chain(&.{at(&w,.head),translate(bodyMesh.nose),m.rotX(-bodyMesh.noseTilt),scale(v3(0.015,0.0105,0.011))}),.{.glow=noseGlow,.fade=beanOpacity,.tint=noseTint});
  // the plump lower lip, riding the jaw: amber sap, dense like the chest's
  if(!headless)try out.emit(.pawBean,m.chain(&.{at(&w,.jaw),translate(bodyMesh.lowerLip),scale(bodyMesh.lowerLipSize)}),.{.glow=beanGlow,.fade=pecOpacity});
  // the belly: the wolf's own amber belly, swelling with the inventory,
  // dropping and sagging as it fills; dense sap like the chest, so what it
  // holds no longer shows through (as the gardener drew it)
  // how full the belly is
  const b=p.fullness;
  // a plucked bead, its yield's colour, cupped in each paw that carries
  // one in from the plant, until the paw presses it into the belly
  if(p.bead)|it|for(0..2)|s|if(p.stowLeft(s)>0.5){
    // the paw's wrist, the bead held down the hand at its knuckles, where
    // the fingers close round it
    const hand=at(&w,skel.sides[s].hand);
    try out.emit(.itemPod,m.chain(&.{hand,translate(v3(0,-beadOut,0)),scale(m.splat3(beadR/podR))}),.{.glow=beadGlow,.phase=0.3,.tint=color.Rgba8.of(it.info().col).toF4()});
  };
  // (the shader creases it as it fills, the folds crossing at its button)
  // where the belly's folds cross
  const cross=bellyMesh.crossing();
  try out.emitSkinned(.wolfBelly,base,mid,.{
    .glow=bellyGlow+bellyGlowFull*b,.phase=0.3,.fade=pecOpacity-sapStretch*b,.give=.{b,cross[1],cross[2]},
  });
  // the pectorals and the rear: resin, its surface given by its spring
  // (and, on the chest, a slow idle) while its base holds
  for([_]meshlib.Id{.wolfPecL,.wolfPecR},[_]f32{-1,1},0..)|id,side,i|{
    // this pectoral's give: its spring and a slow idle breath
    const give=p.pec[i].pos+v3(0,0.003*@sin(p.t*m.tau/3+side*1.3),0);
    try out.emitSkinned(id,base,mid,.{.phase=0.6,.fade=pecOpacity,.give=.{give[0],give[1],give[2]}});
  }
  for([_]meshlib.Id{.wolfRumpL,.wolfRumpR},0..)|id,i|{
    // this cheek of the rear's give
    const give=p.rump[i].pos;
    try out.emitSkinned(id,base,mid,.{.phase=0.15,.fade=rumpOpacity,.give=.{give[0],give[1],give[2]}});
  }
  // where each paw touches down, filled in below
  var feet:[2]V3=undefined;
  for(skel.sides,0..)|sd,s|{
    // which side: -1 left, 1 right
    const x=skel.sign(s);
    // the beans: a palm pad and one under each fingertip; one
    // central pad on each foot that flattens while planted, four toe pads
    const bean:parts.Look=.{.glow=beanGlow,.fade=beanOpacity,.tint=beanTint};
    // the hand bone
    const hand=at(&w,sd.hand);
    try out.emit(.pawPad,m.chain(&.{hand,translate(bodyMesh.palmAt*v3(x,1,1)),m.rotZ(x*m.pi/2.0),scale(v3(0.018,0.005,0.016))}),bean);
    for(sd.tips)|tb|{
      try out.emit(.pawBean,m.chain(&.{at(&w,tb),translate(bodyMesh.tipPad*v3(x,1,1)),scale(v3(0.0042,0.0085,0.0075))}),bean);
    }
    // the foot bone
    const foot=at(&w,sd.foot);
    try out.emit(.pawPad,m.chain(&.{foot,translate(bodyMesh.padAt),scale(v3(0.021,0.006*(1-padFlatten*p.feet[s].pad),0.02))}),bean);
    for(bodyMesh.toes)|tp|{
      try out.emit(.pawBean,m.chain(&.{foot,translate(v3(tp[0],bodyMesh.soleY+0.002,tp[1])),scale(v3(0.0065,0.004,0.008))}),bean);
    }
    feet[s]=m.mulPoint(foot,v3(0,0,0.04));
  }
  return feet;
}
