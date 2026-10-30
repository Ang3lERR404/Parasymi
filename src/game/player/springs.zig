//! the wolf's springs: arms, lean, head, ears, tail and the sloshing belly.
const lib=@import("../../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const noise=engine.core.noise;
const skel=lib.skeleton;
const bellyMesh=lib.wolfBelly;
const v3=m.v3;
const armDamp=lib.player.tuning.armDamp;
const armFreq=lib.player.tuning.armFreq;
const armSwing=lib.player.tuning.armSwing;
const bank=lib.player.tuning.bank;
const bankDamp=lib.player.tuning.bankDamp;
const bankMax=lib.player.tuning.bankMax;
const bellyRoomSize=lib.player.tuningLook.bellyRoomSize;
const bellyRoomMin=lib.player.tuningLook.bellyRoomMin;
const curlFlex=lib.player.tuningLook.curlFlex;
const curlRest=lib.player.tuningLook.curlRest;
const curlSwing=lib.player.tuningLook.curlSwing;
const digAmount=lib.player.tuning.digAmount;
const digDepth=lib.player.tuning.digDepth;
const digRate=lib.player.tuning.digRate;
const earBack=lib.player.tuningLook.earBack;
const earDamp=lib.player.tuningLook.earDamp;
const earFlick=lib.player.tuningLook.earFlick;
const earFlickEvery=lib.player.tuningLook.earFlickEvery;
const earFreq=lib.player.tuningLook.earFreq;
const elbowRest=lib.player.tuning.elbowRest;
const elbowSwing=lib.player.tuning.elbowSwing;
const fingerDamp=lib.player.tuningLook.fingerDamp;
const fingerFreq=lib.player.tuningLook.fingerFreq;
const flexLag=lib.player.tuningLook.flexLag;
const flexRate=lib.player.tuningLook.flexRate;
const flexWave=lib.player.tuningLook.flexWave;
const gazeNod=lib.player.tuning.gazeNod;
const gazeNodDown=lib.player.tuning.gazeNodDown;
const gazeNodUp=lib.player.tuning.gazeNodUp;
const gripClose=lib.player.tuningLook.gripClose;
const gripLag=lib.player.tuningLook.gripLag;
const gripOpen=lib.player.tuningLook.gripOpen;
const headDamp=lib.player.tuning.headDamp;
const headFreq=lib.player.tuning.headFreq;
const leanAccel=lib.player.tuning.leanAccel;
const leanDamp=lib.player.tuning.leanDamp;
const leanFreq=lib.player.tuning.leanFreq;
const leanMax=lib.player.tuning.leanMax;
const leanStride=lib.player.tuning.leanStride;
const leanWork=lib.player.tuning.leanWork;
const lookIdle=lib.player.tuning.lookIdle;
const lookIdleRate=lib.player.tuning.lookIdleRate;
const lookMax=lib.player.tuning.lookMax;
const lookTurn=lib.player.tuning.lookTurn;
const lookWork=lib.player.tuning.lookWork;
const lumpR=lib.player.tuningLook.lumpR;
const pecC=lib.player.tuningLook.pecC;
const pecK=lib.player.tuningLook.pecK;
const pecMass=lib.player.tuningLook.pecMass;
const pecMax=lib.player.tuningLook.pecMax;
const pryGrip=lib.player.tuning.pryGrip;
const Player=lib.player.player.Player;
const restFist=lib.player.tuning.restFist;
const restFlat=lib.player.tuning.restFlat;
const rumpC=lib.player.tuningLook.rumpC;
const rumpK=lib.player.tuningLook.rumpK;
const rumpKick=lib.player.tuningLook.rumpKick;
const rumpMax=lib.player.tuningLook.rumpMax;
const sloshAmount=lib.player.tuningLook.sloshAmount;
const spreadDamp=lib.player.tuningLook.spreadDamp;
const spreadOpen=lib.player.tuningLook.spreadOpen;
const spreadShut=lib.player.tuningLook.spreadShut;
const stepKick=lib.player.tuningLook.stepKick;
const stowCup=lib.player.tuning.stowCup;
const stowTime=lib.player.tuning.stowTime;
const tailDamp=lib.player.tuningLook.tailDamp;
const tailFreq=lib.player.tuningLook.tailFreq;
const tailFreqStep=lib.player.tuningLook.tailFreqStep;
const tailGait=lib.player.tuningLook.tailGait;
const tailIdle=lib.player.tuningLook.tailIdle;
const tailIdleRate=lib.player.tuningLook.tailIdleRate;
const tailTurn=lib.player.tuningLook.tailTurn;
const tailTurnMax=lib.player.tuningLook.tailTurnMax;
const wrenchEnd=lib.player.tuning.wrenchEnd;
const lumps=lib.player.tuningLook.lumps;
/// what lags on springs: lean and bank, arms, head, ears, tail
pub fn springs(p:*Player,dt:f32)void{
  const st=p.stride;
  // the generic gesture gives way to the gathering pose
  const work=p.reach.x*(1-p.squat.x);
  p.lean.to(m.clamp(leanStride*st+p.accel[2]*leanAccel,-leanMax,leanMax)+leanWork*work,leanFreq,leanDamp,dt);
  p.bank.to(m.clamp(-p.turn*bank*st,-bankMax,bankMax),leanFreq,bankDamp,dt);
  for(0..2)|s|{
    // each arm swings with the opposite leg: back as its own leg comes forward
    const ph=@mod(p.phase+0.5*m.f(s),1);
    const swing=@sin(ph*m.tau+m.halfPi)*armSwing*st;
    const dig=digAmount+@sin(p.t*digRate+m.f(s)*1.7)*digDepth;
    p.arm[s].to(m.lerp(swing,dig,work),armFreq,armDamp,dt);
    p.elbow[s].to(elbowRest+elbowSwing*st*m.clamp01(-p.arm[s].x*2)+0.7*work,armFreq,armDamp,dt);
    // ears lie back with speed and flick now and then, one, then the other
    const due=@mod(p.t+m.f(s)*1.3,earFlickEvery)<dt and noise.grad(0xEA2+%s,p.t*0.7,0.5)>0;
    if(due)p.ear[s].v+=earFlick;
    p.ear[s].to(-earBack*st,earFreq,earDamp,dt);
  }
  const idle=(1-st)*(1-work);
  for(&p.curl,&p.spread,0..)|*hand,*spread,s|{
    const flex=m.clamp01(noise.grad(0xF1C+%s,p.t*flexRate,0.5)*2);
    const stroke=p.t*digRate+m.f(s)*1.7-0.6;
    var sum:f32=0;
    for(hand,0..)|*c,i|{
      const fi=m.f(i);
      var target=curlRest+curlSwing*st*m.clamp01(-p.arm[s].x*1.5);
      target+=curlFlex*idle*flex*m.clamp01(@sin(p.t*flexWave-fi*flexLag+m.f(s)*2.1));
      const rake=0.5+0.5*@sin(stroke-fi*gripLag);
      target=m.lerp(target,m.lerp(gripOpen,gripClose,rake),work);
      // gathering: shut on the node, opening as the paw comes back to it,
      // cupped round a unit on its way to the belly
      const k=p.gather orelse 0;
      const regrip=1-m.smooth(m.clamp01((k-wrenchEnd)/(1-wrenchEnd)*2))*m.smooth(m.clamp01((1-k)*8));
      const hold=m.lerp(gripOpen,pryGrip,regrip);
      const cup=m.clamp01(p.stow[s]/stowTime*4);
      target=m.lerp(target,m.lerp(hold,stowCup,cup),p.squat.x);
      // resting: the paw on the belly lies flat, the one on the hip curls
      target=m.lerp(target,if(s==1)restFlat else restFist,p.restPose.x*(1-p.squat.x));
      c.to(target,fingerFreq,fingerDamp,dt);
      sum+=c.x;
    }
    const shut=m.clamp01(sum/(skel.fingerCount*gripClose));
    spread.to(m.lerp(spreadOpen,spreadShut,shut),fingerFreq,spreadDamp,dt);
  }
  var look=m.clamp(p.turn*lookTurn,-lookMax,lookMax)+lookIdle*idle*noise.grad(0x100C,p.t*lookIdleRate,0.5);
  var nod=lookWork*(work+p.squat.x)+0.12*idle*noise.grad(0x40D,p.t*lookIdleRate,3.5);
  // seen from its own eyes, the head looks where they do, ahead of the
  // body still turning to them, and nods up and down with them
  if(p.aim)|a|look=m.clamp(m.angleDiff(p.facing,a),-lookMax,lookMax);
  if(p.gaze)|up|nod=m.clamp(-up*gazeNod,gazeNodUp,gazeNodDown)+lookWork*(work+p.squat.x);
  p.look.to(look,headFreq,headDamp,dt);
  p.nod.to(nod,headFreq,headDamp,dt);
  // tail: each joint chases the one before it, steered by turning and gait
  var target=m.clamp(-p.turn*tailTurn,-tailTurnMax,tailTurnMax)+@sin(p.t*tailIdleRate)*tailIdle*(1-st)+@sin(p.phase*m.tau)*tailGait*st;
  for(&p.tail,0..)|*j,i|{
    j.to(target,tailFreq-m.f(i)*tailFreqStep,tailDamp,dt);
    target=j.x;
  }
}
/// the belly's lumps and the resin lag behind the body's acceleration
/// (inertia), overshoot when it stops, and settle back on their springs;
/// a footfall drops them a little.
pub fn slosh(p:*Player,fell:bool,dt:f32)void{
  const room=p.bellyRoom();
  const force=-p.accel*m.splat3(sloshAmount);
  for(&p.lump,lumps)|*s,l|{
    if(fell)s.vel[1]-=stepKick*p.stride;
    m.springDamper(&s.pos,&s.vel,l.rest*m.splat3(room),l.k,l.c,l.mass,force*m.splat3(l.mass),dt);
    // stay inside the sac; hitting its wall stops the outward motion
    const d=m.len(s.pos);
    if(d>room){
      const n=s.pos/m.splat3(d);
      s.pos=n*m.splat3(room);
      s.vel-=n*m.splat3(@max(m.dot(s.vel,n),0));
    }
  }
  for(&p.pec,pecK)|*s,k|{
    if(fell)s.vel[1]-=rumpKick*0.6*p.stride;
    m.springDamper(&s.pos,&s.vel,v3(0,0,0),k,pecC,pecMass,force*m.splat3(pecMass),dt);
    const d=m.len(s.pos);
    if(d>pecMax)s.pos*=m.splat3(pecMax/d);
  }
  for(&p.rump)|*s|{
    if(fell)s.vel[1]-=rumpKick*p.stride;
    m.springDamper(&s.pos,&s.vel,v3(0,0,0),rumpK,rumpC,pecMass,force*m.splat3(pecMass),dt);
    const d=m.len(s.pos);
    if(d>rumpMax)s.pos*=m.splat3(rumpMax/d);
  }
}
/// how far a lump's centre may stray from the gut's centre (in the gut
/// bone's frame, which swells with it): within `BELLY_ROOM` of the sac,
/// and never poking through it
pub fn bellyRoom(_:*const Player)f32{
  return@max(@min(bellyMesh.down,@min(bellyMesh.rx,bellyMesh.rz))*bellyRoomSize-lumpR,bellyRoomMin);
}
