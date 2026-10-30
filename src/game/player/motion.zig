//! the wolf's motion each frame: gait stages, footsteps and the gathering pry.
const lib=@import("../../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const World=lib.world.World;
const skel=lib.skeleton;
const bellyMesh=lib.wolfBelly;
const V3=m.V3;
const v3=m.v3;
const Bone=skel.Bone;
const bellyItems=lib.player.tuning.bellyItems;
const breathRate=lib.player.tuning.breathRate;
const breathRateRun=lib.player.tuning.breathRateRun;
const cycle=lib.player.tuning.cycle;
const cyclePerSpeed=lib.player.tuning.cyclePerSpeed;
const dutyFast=lib.player.tuning.dutyFast;
const dutySlow=lib.player.tuning.dutySlow;
const fullnessResponse=lib.player.tuning.fullnessResponse;
const gaits=lib.player.tuning.gaits;
const gatherAt=lib.player.tuning.gatherAt;
const gripSide=lib.player.tuning.gripSide;
const gripUp=lib.player.tuning.gripUp;
const Gait=lib.player.tuning.Gait;
const handDamp=lib.player.tuning.handDamp;
const handFreq=lib.player.tuning.handFreq;
const liftAmount=lib.player.tuning.liftAmount;
const liftArc=lib.player.tuning.liftArc;
const liftStride=lib.player.tuning.liftStride;
const lost=lib.player.tuning.lost;
const minDt=lib.player.tuning.minDt;
const padFreq=lib.player.tuningLook.padFreq;
const pryBack=lib.player.tuning.pryBack;
const pryUp=lib.player.tuning.pryUp;
const Player=lib.player.player.Player;
const reachFreq=lib.player.tuning.reachFreq;
const restAfter=lib.player.tuning.restAfter;
const restFreq=lib.player.tuning.restFreq;
const restFull=lib.player.tuning.restFull;
const restFullIn=lib.player.tuning.restFullIn;
const settle=lib.player.tuning.settle;
const settleTime=lib.player.tuning.settleTime;
const sprintSpeed=lib.player.tuning.sprintSpeed;
const squatFreq=lib.player.tuning.squatFreq;
const stageAt=lib.player.tuning.stageAt;
const stageBlend=lib.player.tuning.stageBlend;
const standing=lib.player.tuning.standing;
const stowTime=lib.player.tuning.stowTime;
const strideResponse=lib.player.tuning.strideResponse;
const swingMax=lib.player.tuning.swingMax;
const swingMin=lib.player.tuning.swingMin;
const swingSpeedMin=lib.player.tuning.swingSpeedMin;
const trailMax=lib.player.tuning.trailMax;
const walkSpeed=lib.player.tuning.walkSpeed;
const pryPull=lib.player.ik.pryPull;
pub fn animate(p:*Player,ground:?*const World,dt:f32)void{
  p.t+=dt;
  const spd=p.groundSpeed();
  const g=p.gait();
  const walk=walkSpeed*g.walk;
  const sprint=sprintSpeed*g.sprint;
  p.stride+=(m.clamp01(spd/walk)-p.stride)*@min(1,dt*strideResponse);
  p.cycle=(cycle+cyclePerSpeed*spd)*g.stride;
  p.duty=m.lerp(dutySlow,dutyFast,m.clamp01((spd-1)/(sprint-1)));
  p.phase=@mod(p.phase+spd/p.cycle*dt,1);
  const effort=m.clamp01(spd/sprint);
  p.breath+=dt*m.lerp(breathRate,breathRateRun,effort);
  p.fullness+=(p.bellyFill()-p.fullness)*@min(1,dt*fullnessResponse);
  p.reach.to(if(p.work!=null)1 else 0,reachFreq,1,dt);
  p.pry(dt);
  p.still=if(p.stride<standing and p.work==null and p.gather==null)p.still+dt else 0;
  const heavy=m.smooth(m.clamp01((p.fullness-restFull)/(restFullIn-restFull)));
  p.restPose.to(if(p.still>restAfter)heavy else 0,restFreq,1,dt);
  // what the body feels: its acceleration, turned into its own frame
  const a=(p.vel-p.lastVel)/m.splat3(@max(dt,minDt));
  p.lastVel=p.vel;
  const al=m.mulV(m.rotY(-p.facing),.{a[0],a[1],a[2],0});
  p.accel=v3(al[0],al[1],al[2]);
  const fell=p.step(ground,spd,dt);
  p.slosh(fell,dt);
  p.springs(dt);
}
/// which of the belly's stages the wolf is in: 0 light .. 1 heavy .. 2
/// full, blending over `STAGE_BLEND` about each threshold
pub fn stage(p:*const Player)f32{
  var out:f32=0;
  for(stageAt)|at|out+=m.smooth(m.clamp01((p.fullness-at)/stageBlend+0.5));
  return out;
}
/// the gait for the belly's load (`GAITS` blended by `stage`)
pub fn gait(p:*const Player)Gait{
  const st=p.stage();
  const i:usize=if(st>=1)1 else 0;
  const k=st-m.f(i);
  const a=gaits[i];
  const b=gaits[i+1];
  var out:Gait=undefined;
  inline for(@typeInfo(Gait).@"struct".fields)|fl|@field(out,fl.name)=m.lerp(@field(a,fl.name),@field(b,fl.name),k);
  return out;
}
/// how full the belly is to look at (0..1) for what it holds
pub fn bellyFill(p:*const Player)f32{return 1-@exp(-m.f(p.inv.total())/bellyItems);}
/// the feet: plant, lift, swing to where they are wanted. Returns whether
/// one came down this frame.
pub fn step(p:*Player,ground:?*const World,spd:f32,dt:f32)bool{
  if(!p.placed){
    for(&p.feet,0..)|*f,s|f.at=p.rest(ground,s);
    p.placed=true;
  }
  const moving=p.stride>standing;
  // how far ahead of the hip a foot lands, so it passes under the hip
  // mid-stance
  const ahead=if(spd>0.1)p.vel/m.splat3(spd)*m.splat3(p.duty*p.cycle*0.5*m.clamp01(spd/1.5))else v3(0,0,0);
  var fell=false;
  for(&p.feet,0..)|*f,s|{
    const other=&p.feet[1-s];
    if(m.len(f.at-p.rest(ground,s))>lost){
      f.*=.{.at=p.rest(ground,s),.phase=f.phase};
      continue;
    }
    const ph=@mod(p.phase+0.5*m.f(s),1);
    if(f.planted()){
      const off=m.len(f.at-p.rest(ground,s));
      // a foot trailing too far always lifts (the other one is down by then)
      var lift=off>trailMax and other.planted();
      if(moving){
        // the gait lifts it as its stance ends
        lift=lift or (ph>=p.duty and f.phase<p.duty);
      }else{
        // standing, a foot left behind steps back under (one at a time)
        lift=lift or (other.planted() and off>settle and off>=m.len(other.at-p.rest(ground,1-s)));
      }
      if(lift){
        f.from=f.at;
        f.t=0;
        f.dur=if(moving)m.clamp((1-p.duty)*p.cycle/@max(spd,swingSpeedMin),swingMin,swingMax)else settleTime;
        f.lift=(liftAmount+liftStride*p.stride)*p.gait().lift;
      }
    }
    f.phase=ph;
    if(!f.planted()){
      f.t=@min(1,f.t+dt/f.dur);
      const left=(1-f.t)*f.dur;
      const to=p.onGround(ground,p.rest(ground,s)+p.vel*m.splat3(left)+ahead);
      const k=m.smooth(f.t);
      f.at=m.lerpV(f.from,to,k);
      f.at[1]=m.lerp(f.from[1],to[1],k)+f.lift*m.pow(f32,@sin(f.t*m.pi),liftArc);
      if(f.planted()){
        f.at[1]=to[1];
        fell=true;
        p.fell[s]=.{.weight=p.stage()/2,.pace=m.clamp01(spd/(sprintSpeed*p.gait().sprint))};
      }
    }
    m.spring(&f.pad,&f.padV,if(f.planted())1 else 0,padFreq,dt);
  }
  return fell;
}
/// gathering: the squat eases in and out, each unit come loose sends a
/// paw (one, then the other) to the belly, and the wrists chase where the
/// pry wants them
pub fn pry(p:*Player,dt:f32)void{
  p.squat.to(if(p.gather!=null)1 else 0,squatFreq,1,dt);
  for(&p.stow)|*t|t.*=@max(t.*-dt,0);
  const k=p.gather orelse {
    p.lastPry=0;
    return;
  };
  if(k<p.lastPry and p.squat.x>0.5){
    p.stow[p.nextStow]=stowTime;
    p.nextStow+%=1;
  }
  p.lastPry=k;
  const q=p.pose();
  for(&p.wrist,0..)|*w,s|{
    const want=p.wristWant(q,s,k);
    // just crouching, the wrists start where they are wanted
    if(p.squat.x<0.02)w.*=.{.pos=want};
    m.springDamper(&w.pos,&w.vel,want,handFreq*handFreq,2*handDamp*handFreq,1,v3(0,0,0),dt);
  }
}
/// where wrist `s` is wanted (wolf space) at unit share `k`: on the node,
/// pulled back and up through the pry, or at the belly while stowing
pub fn wristWant(p:*const Player,q:skel.Pose,s:usize,k:f32)V3{
  const node=p.workLocal();
  const x=skel.sign(s);
  const pull=pryPull(k);
  const grip=node+v3(x*gripSide,gripUp+pryUp*pull,-pryBack*pull);
  const stow=m.smooth(m.clamp01(@sin(p.stow[s]/stowTime*m.pi)*1.6));
  if(stow<=0)return grip;
  const w=skel.fk(q);
  const belly=m.mulPoint(w[@intFromEnum(Bone.gut)],v3(x*bellyMesh.rx*0.3,bellyMesh.down*0.15,bellyMesh.rz*1.15));
  return m.lerpV(grip,belly,stow);
}
/// the node worked on, in the wolf's own frame (a little ahead without one)
pub fn workLocal(p:*const Player)V3{
  const at=p.work orelse return v3(0,0,gatherAt);
  const l=m.mulV(m.inverseRigid(p.heading()),.{at[0],at[1],at[2],1});
  return v3(l[0],l[1],l[2]);
}
