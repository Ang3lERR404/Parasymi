//! the wolf posed: the skeleton from its state, and its parts for the renderer.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const engine=lib.engine;
const m=engine.core.math;
const skel=lib.skeleton;
const bodyMesh=lib.wolfBody;
const bellyMesh=lib.wolfBelly;
const meshlib=lib.meshlib;
const parts=lib.parts;
const Parts=parts.Parts;
const V3=m.V3;
const v3=m.v3;
const M4=m.M4;
const translate=m.translate;
const scale=m.scale3;
const Bone=skel.Bone;
const armOut=lib.player.tuning.armOut;
const beanGlow=lib.player.tuningLook.beanGlow;
const beanOpacity=lib.player.tuningLook.beanOpacity;
const beanTint=lib.player.tuningLook.beanTint;
const bellyArms=lib.player.tuning.bellyArms;
const bellyGlow=lib.player.tuningLook.bellyGlow;
const bellyGlowFull=lib.player.tuningLook.bellyGlowFull;
const bobAmount=lib.player.tuning.bobAmount;
const bodyFlutter=lib.player.tuningLook.bodyFlutter;
const bodyGlow=lib.player.tuningLook.bodyGlow;
const bodyMid=lib.player.tuningLook.bodyMid;
const breathAmount=lib.player.tuning.breathAmount;
const breathRun=lib.player.tuning.breathRun;
const counter=lib.player.tuning.counter;
const earGlow=lib.player.tuningLook.earGlow;
const earOpacity=lib.player.tuningLook.earOpacity;
const eyesAt=lib.player.tuningLook.eyesAt;
const headBones=lib.player.tuningLook.headBones;
const hipRoll=lib.player.tuning.hipRoll;
const hipTurn=lib.player.tuning.hipTurn;
const lumpGlow=lib.player.tuningLook.lumpGlow;
const lumpR=lib.player.tuningLook.lumpR;
const noseGlow=lib.player.tuningLook.noseGlow;
const noseTint=lib.player.tuningLook.noseTint;
const padFlatten=lib.player.tuningLook.padFlatten;
const pant=lib.player.tuning.pant;
const pecOpacity=lib.player.tuningLook.pecOpacity;
const pryRock=lib.player.tuning.pryRock;
const pryTwist=lib.player.tuning.pryTwist;
const pullEnd=lib.player.tuning.pullEnd;
const Player=lib.player.player.Player;
const restDrape=lib.player.tuning.restDrape;
const restElbowOut=lib.player.tuning.restElbowOut;
const restHip=lib.player.tuning.restHip;
const restLift=lib.player.tuning.restLift;
const restOn=lib.player.tuning.restOn;
const restPronate=lib.player.tuning.restPronate;
const rumpOpacity=lib.player.tuningLook.rumpOpacity;
const sapOpacity=lib.player.tuningLook.sapOpacity;
const sapStretch=lib.player.tuning.sapStretch;
const sinkAmount=lib.player.tuning.sinkAmount;
const squatDrop=lib.player.tuning.squatDrop;
const squatLean=lib.player.tuning.squatLean;
const stowTime=lib.player.tuning.stowTime;
const swayAmount=lib.player.tuning.swayAmount;
const swingFold=lib.player.tuning.swingFold;
const tailDroop=lib.player.tuningLook.tailDroop;
const tailLift=lib.player.tuningLook.tailLift;
const tipRest=lib.player.tuningLook.tipRest;
const tipShare=lib.player.tuningLook.tipShare;
const toeHang=lib.player.tuning.toeHang;
const wrenchEnd=lib.player.tuning.wrenchEnd;
const bindInv=lib.player.ik.bindInv;
const lumps=lib.player.tuningLook.lumps;
const pryPull=lib.player.ik.pryPull;
const solveArm=lib.player.ik.solveArm;
const solveArmTurned=lib.player.ik.solveArmTurned;
const solveLeg=lib.player.ik.solveLeg;
/// the skeleton's pose this frame, in wolf space (see wolf_skeleton)
pub fn pose(p:*const Player)skel.Pose{
  if(p.posed)|q|return q;
  const st=p.stride;
  const work=p.reach.x*(1-p.squat.x);
  const sq=p.squat.x;
  const ph=p.phase*m.tau;
  var q:skel.Pose=.{};
  // the pelvis: lowest just after each footfall, over the planted foot;
  // gathering, down in a squat, the body leaning in and rocking back
  // with each pull
  const g=p.gait();
  const bob=bobAmount*g.bob*st*(0.5+0.5*@cos(2*ph-p.duty*m.tau));
  const rock=pryRock*pryPull(p.gather orelse 0)*sq;
  const lean=p.lean.x-g.lean*(1-sq)+(squatLean-rock)*sq;
  q.hip=v3(swayAmount*g.sway*st*@sin(ph),skel.hipY-sinkAmount*g.sink*st-bob-0.07*work-squatDrop*sq,-0.04*sq);
  q.pelvis=.{.x=0.25*lean,.y=hipTurn*st*@sin(ph),.z=hipRoll*g.roll*st*@cos(ph)+p.bank.x};
  q.waist=.{.x=0.35*lean,.y=-0.5*counter*q.pelvis.y,.z=-0.4*q.pelvis.z};
  q.chest=.{.x=0.4*lean,.y=-0.5*counter*q.pelvis.y,.z=-0.4*q.pelvis.z};
  const breath=@sin(p.breath);
  q.breath=1+m.lerp(breathAmount,breathRun,st)*breath;
  // the head holds its gaze: it takes back the body's lean and bob
  const bodyPitch=q.pelvis.x+q.waist.x+q.chest.x;
  q.neck=.{.x=-0.4*bodyPitch+0.5*p.nod.x,.y=0.4*p.look.x-0.3*q.chest.y};
  q.head=.{.x=-0.6*bodyPitch+0.5*p.nod.x-bob*1.5+0.02*breath,.y=0.6*p.look.x-0.3*q.chest.y,.z=-0.5*p.bank.x};
  q.jaw=pant*st*(0.6+0.4*breath);
  q.gut=p.fullness;
  for(0..2)|s|{
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
  for(&q.tail,p.tail,0..)|*j,sp,i|j.*=.{.x=(if(i==0)-tailLift*@max(st,sq)else tailDroop*(1-0.6*st)),.z=sp.x};
  q.legs=p.legs(q);
  if(sq>0)p.armsToWrists(&q,sq);
  const resting=p.restPose.x*(1-sq);
  if(resting>0)restArms(&q,resting);
  return q;
}
/// the belly-rest idle, blended in by `r`: the right wrist onto the top
/// of the belly, the palm laid on it; the left on the hip, the wrist
/// bent back and the elbow turned out
pub fn restArms(q:*skel.Pose,r:f32)void{
  const w=skel.fk(q.*);
  const into=m.inverseRigid(w[@intFromEnum(Bone.chest)]);
  const on=restOn*v3(bellyMesh.rx,bellyMesh.upAxis,bellyMesh.rz);
  const at=[2]V3{
    m.mulPoint(w[@intFromEnum(Bone.pelvis)],restHip*v3(-1,1,1)),
    m.mulPoint(w[@intFromEnum(Bone.gutTop)],on)+v3(0,restLift,0),
  };
  for(0..2)|s|{
    const x=skel.sign(s);
    const out:f32=if(s==0)restElbowOut else 0;
    const ik=solveArmTurned(m.mulPoint(into,at[s])-skel.shoulder*v3(x,1,1),-x*out);
    const a=&q.arms[s];
    a.root=skel.Turn.blend(a.root,ik.root,r);
    a.mid=m.lerp(a.mid,ik.mid,r);
    // (on the belly the paw turns palm down and bends onto the sac; on
    // the hip the wrist cocks back)
    const low:skel.Turn=if(s==0).{.x=-0.5,.z=x*0.3}else.{.y=-x*restPronate,.z=-x*restDrape};
    a.low=.{.x=m.lerp(a.low.x,low.x,r),.y=m.lerp(a.low.y,low.y,r),.z=m.lerp(a.low.z,low.z,r)};
  }
}
/// gathering: each arm blended (by `sq`) toward reaching its wrist's
/// target by inverse kinematics, the wrist twisting with the wrench
pub fn armsToWrists(p:*const Player,q:*skel.Pose,sq:f32)void{
  const w=skel.fk(q.*);
  const into=m.inverseRigid(w[@intFromEnum(Bone.chest)]);
  const k=p.gather orelse 0;
  const twist=pryTwist*m.smooth(m.clamp01((k-pullEnd)/(wrenchEnd-pullEnd)))*(1-m.smooth(m.clamp01((k-wrenchEnd)/(1-wrenchEnd))));
  for(0..2)|s|{
    const x=skel.sign(s);
    const at=m.mulPoint(into,p.wrist[s].pos)-skel.shoulder*v3(x,1,1);
    const ik=solveArm(at);
    const a=&q.arms[s];
    a.root=skel.Turn.blend(a.root,ik.root,sq);
    a.mid=m.lerp(a.mid,ik.mid,sq);
    const stowing=m.clamp01(p.stow[s]/stowTime*3);
    a.low=.{.x=m.lerp(a.low.x,0.35*(1-stowing)+0.9*stowing,sq),.y=m.lerp(a.low.y,-x*twist*(1-stowing),sq),.z=a.low.z};
  }
}
/// each leg reaching its foot, by inverse kinematics in the pelvis's frame
pub fn legs(p:*const Player,q:skel.Pose)[2]skel.Limb{
  var out:[2]skel.Limb=undefined;
  const toWolf=m.inverseRigid(p.heading());
  const pelvis=m.chain(&.{translate(q.hip),q.pelvis.m4()});
  const into=m.inverseRigid(pelvis);
  const pelvisPitch=q.pelvis.x;
  for(&out,0..)|*l,s|{
    const f=p.feet[s];
    const fw=m.mulV(toWolf,.{f.at[0],f.at[1],f.at[2],1});
    const fp=m.mulV(into,fw);
    const swing=if(f.planted())@as(f32,0)else@sin(f.t*m.pi);
    l.*=solveLeg(v3(fp[0],fp[1],fp[2])-v3(skel.sign(s)*skel.hipX,0,0),swingFold*swing,pelvisPitch,toeHang*swing);
  }
  return out;
}
/// where its eyes are in the world this frame
pub fn eyes(p:*const Player)V3{
  const w=skel.fk(p.pose());
  return m.mulPoint(m.mul(p.heading(),w[@intFromEnum(Bone.head)]),eyesAt);
}
/// emit every part; returns where each paw (left, right) touches down.
/// Seen from its own eyes (`headless`) its head is not drawn, though it
/// still casts its shadow.
pub fn rig(p:*const Player,out:*Parts,headless:bool)Allocator.Error![2]V3{
  const q=p.pose();
  const root=p.heading();
  var w=skel.fk(q);
  for(&w)|*b|b.*=m.mul(root,b.*);
  const skin=skel.skin(w,&bindInv(),q.breath);
  const base=try out.pose(&skin);
  const mid=p.pos+v3(0,bodyMid,0);
  const at=struct{
    fn f(ws:*const[skel.count]M4,b:Bone)M4{return ws[@intFromEnum(b)];}
  }.f;
  const hide:u64=if(headless)headBones else 0;
  try out.emitSkinned(.wolfBody,base,mid,.{.glow=bodyGlow,.flutter=bodyFlutter,.phase=0.1,.hide=hide});
  try out.emitSkinned(.wolfEars,base,mid,.{.glow=earGlow,.phase=0.5,.fade=earOpacity,.hide=hide});
  if(!headless)try out.emit(.pawBean,m.chain(&.{at(&w,.head),translate(bodyMesh.nose),m.rotX(-bodyMesh.noseTilt),scale(v3(0.015,0.0105,0.011))}),.{.glow=noseGlow,.fade=beanOpacity,.tint=noseTint});
  // the belly: a sap sac that inflates with the inventory, drops and sags
  // as it fills, with the heavier things inside showing through as shadows
  const b=p.fullness;
  const gut=at(&w,.gut);
  var held:usize=0;
  for(p.inv.slot)|slot|if(slot!=null){
    held+=1;
  };
  for(p.lump[0..@min(held,lumps.len)])|l|{
    try out.emit(.bellyLump,m.chain(&.{gut,translate(l.pos),scale(m.splat3(lumpR))}),.{.glow=lumpGlow,.phase=0.3});
  }
  // (the shader creases it as it fills, the folds crossing at its button)
  const cross=bellyMesh.crossing();
  try out.emitSkinned(.wolfBelly,base,mid,.{
    .glow=bellyGlow+bellyGlowFull*b,.phase=0.3,.fade=sapOpacity-sapStretch*b,.give=.{b,cross[1],cross[2]},
  });
  // the pectorals and the rear: resin, its surface given by its spring
  // (and, on the chest, a slow idle) while its base holds
  for([_]meshlib.Id{.wolfPecL,.wolfPecR},[_]f32{-1,1},0..)|id,side,i|{
    const give=p.pec[i].pos+v3(0,0.003*@sin(p.t*m.tau/3+side*1.3),0);
    try out.emitSkinned(id,base,mid,.{.phase=0.6,.fade=pecOpacity,.give=.{give[0],give[1],give[2]}});
  }
  for([_]meshlib.Id{.wolfRumpL,.wolfRumpR},0..)|id,i|{
    const give=p.rump[i].pos;
    try out.emitSkinned(id,base,mid,.{.phase=0.15,.fade=rumpOpacity,.give=.{give[0],give[1],give[2]}});
  }
  var feet:[2]V3=undefined;
  for(skel.sides,0..)|sd,s|{
    const x=skel.sign(s);
    // the beans: a palm pad and one under each fingertip; one
    // central pad on each foot that flattens while planted, four toe pads
    const bean:parts.Look=.{.glow=beanGlow,.fade=beanOpacity,.tint=beanTint};
    const hand=at(&w,sd.hand);
    try out.emit(.pawPad,m.chain(&.{hand,translate(bodyMesh.palmAt*v3(x,1,1)),m.rotZ(x*m.pi/2.0),scale(v3(0.018,0.005,0.016))}),bean);
    for(sd.tips)|tb|{
      try out.emit(.pawBean,m.chain(&.{at(&w,tb),translate(bodyMesh.tipPad*v3(x,1,1)),scale(v3(0.0042,0.0085,0.0075))}),bean);
    }
    const foot=at(&w,sd.foot);
    try out.emit(.pawPad,m.chain(&.{foot,translate(bodyMesh.padAt),scale(v3(0.021,0.006*(1-padFlatten*p.feet[s].pad),0.02))}),bean);
    for(bodyMesh.toes)|tp|{
      try out.emit(.pawBean,m.chain(&.{foot,translate(v3(tp[0],bodyMesh.soleY+0.002,tp[1])),scale(v3(0.0065,0.004,0.008))}),bean);
    }
    feet[s]=m.mulPoint(foot,v3(0,0,0.04));
  }
  return feet;
}
