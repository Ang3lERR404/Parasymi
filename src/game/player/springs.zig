//! the wolf's springs: arms, lean, head, ears, tail and the sloshing belly.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, springs, angles
const m=engine.core.math;
/// smooth noise, for idle flicks, flexes and glances
const noise=engine.core.noise;
/// the wolf's skeleton: how many fingers a hand has
const skel=lib.skeleton;
/// the belly's mesh: its radii and depth, the room inside it
const bellyMesh=lib.wolfBelly;
/// builds a 3D vector from its three parts
const v3=m.v3;
/// how damped the arms' springs are
const armDamp=lib.player.tuning.armDamp;
/// how stiffly the arms follow (spring frequency)
const armFreq=lib.player.tuning.armFreq;
/// how far the arms swing against the legs (radians)
const armSwing=lib.player.tuning.armSwing;
/// how far the body banks into turns (radians per rad/s)
const bank=lib.player.tuning.bank;
/// how damped the bank's spring is
const bankDamp=lib.player.tuning.bankDamp;
/// the most the body ever banks (radians)
const bankMax=lib.player.tuning.bankMax;
/// the share of the sac a lump keeps within
const bellyRoomSize=lib.player.tuningLook.bellyRoomSize;
/// the least room a lump always has (m)
const bellyRoomMin=lib.player.tuningLook.bellyRoomMin;
/// how far an idle flex curls the fingers (radians)
const curlFlex=lib.player.tuningLook.curlFlex;
/// the fingers' loose curl at rest (radians)
const curlRest=lib.player.tuningLook.curlRest;
/// how much more they curl as the arm swings forward (radians)
const curlSwing=lib.player.tuningLook.curlSwing;
/// how far the arms swing down into the dig (radians)
const digAmount=lib.player.tuning.digAmount;
/// how deep the paws dig into the work
const digDepth=lib.player.tuning.digDepth;
/// how fast the dig strikes (radians a second)
const digRate=lib.player.tuning.digRate;
/// how far the ears lie back at full speed (radians)
const earBack=lib.player.tuningLook.earBack;
/// how damped the ears' springs are
const earDamp=lib.player.tuningLook.earDamp;
/// how hard a flick kicks an ear
const earFlick=lib.player.tuningLook.earFlick;
/// how often an ear may flick (s between chances)
const earFlickEvery=lib.player.tuningLook.earFlickEvery;
/// how stiffly the ears follow (spring frequency)
const earFreq=lib.player.tuningLook.earFreq;
/// how far the elbows bend at rest (radians)
const elbowRest=lib.player.tuning.elbowRest;
/// how much more they bend swinging forward (radians)
const elbowSwing=lib.player.tuning.elbowSwing;
/// how damped the fingers' springs are
const fingerDamp=lib.player.tuningLook.fingerDamp;
/// how stiffly the fingers follow (spring frequency)
const fingerFreq=lib.player.tuningLook.fingerFreq;
/// how far behind its neighbour each finger flexes
const flexLag=lib.player.tuningLook.flexLag;
/// how fast the noise wanders that decides when the fingers flex
const flexRate=lib.player.tuningLook.flexRate;
/// how fast the flexing ripple runs (radians a second)
const flexWave=lib.player.tuningLook.flexWave;
/// the share of the eyes' look up or down the head nods
const gazeNod=lib.player.tuning.gazeNod;
/// the furthest the head nods down (radians)
const gazeNodDown=lib.player.tuning.gazeNodDown;
/// the furthest the head nods up (radians)
const gazeNodUp=lib.player.tuning.gazeNodUp;
/// how far the fingers rake shut with each dig stroke (radians)
const gripClose=lib.player.tuningLook.gripClose;
/// how far behind its neighbour each finger rakes
const gripLag=lib.player.tuningLook.gripLag;
/// how far the fingers open between dig strokes (radians)
const gripOpen=lib.player.tuningLook.gripOpen;
/// how damped the head's spring is
const headDamp=lib.player.tuning.headDamp;
/// how stiffly the head follows (spring frequency)
const headFreq=lib.player.tuning.headFreq;
/// how far the body leans into acceleration (radians per m/s^2)
const leanAccel=lib.player.tuning.leanAccel;
/// how damped the lean's spring is
const leanDamp=lib.player.tuning.leanDamp;
/// how stiffly the lean follows (spring frequency)
const leanFreq=lib.player.tuning.leanFreq;
/// the most the body ever leans (radians)
const leanMax=lib.player.tuning.leanMax;
/// the forward lean at full stride (radians)
const leanStride=lib.player.tuning.leanStride;
/// how far it leans down into the work (radians)
const leanWork=lib.player.tuning.leanWork;
/// how far the head looks about when idle (radians)
const lookIdle=lib.player.tuning.lookIdle;
/// how fast its idle look wanders
const lookIdleRate=lib.player.tuning.lookIdleRate;
/// the most the head turns to look (radians)
const lookMax=lib.player.tuning.lookMax;
/// how far the head turns into turns (radians per rad/s)
const lookTurn=lib.player.tuning.lookTurn;
/// how far the head looks down into the work (radians)
const lookWork=lib.player.tuning.lookWork;
/// how large each belly lump is (m)
const lumpR=lib.player.tuningLook.lumpR;
/// how damped the pectorals' springs are
const pecC=lib.player.tuningLook.pecC;
/// each pectoral's spring stiffness (left, right)
const pecK=lib.player.tuningLook.pecK;
/// how heavy each pectoral is
const pecMass=lib.player.tuningLook.pecMass;
/// the furthest a pectoral strays from rest (m)
const pecMax=lib.player.tuningLook.pecMax;
/// how far the gripping fingers close
const pryGrip=lib.player.tuning.pryGrip;
/// the wolf whose springs these are
const Player=lib.player.player.Player;
/// how tight the hip-leaning paw curls its knuckles
const restFist=lib.player.tuning.restFist;
/// how flat the belly-resting paw lays its fingers
const restFlat=lib.player.tuning.restFlat;
/// how damped the rear's springs are
const rumpC=lib.player.tuningLook.rumpC;
/// the rear's spring stiffness
const rumpK=lib.player.tuningLook.rumpK;
/// how hard each footfall bounces the rear
const rumpKick=lib.player.tuningLook.rumpKick;
/// the furthest the rear strays from rest (m)
const rumpMax=lib.player.tuningLook.rumpMax;
/// how strongly acceleration is felt by what hangs in the body
const sloshAmount=lib.player.tuningLook.sloshAmount;
/// how damped the hands' spread springs are
const spreadDamp=lib.player.tuningLook.spreadDamp;
/// how far open fingers fan apart (radians)
const spreadOpen=lib.player.tuningLook.spreadOpen;
/// how far closed fingers draw together (radians)
const spreadShut=lib.player.tuningLook.spreadShut;
/// how hard a footfall drops the belly's lumps
const stepKick=lib.player.tuningLook.stepKick;
/// how far a stowing paw cups round its unit
const stowCup=lib.player.tuning.stowCup;
/// how damped the tail's springs are
const tailDamp=lib.player.tuningLook.tailDamp;
/// how stiff the tail root's spring is (spring frequency)
const tailFreq=lib.player.tuningLook.tailFreq;
/// how much softer each tail joint's spring is than the one before
const tailFreqStep=lib.player.tuningLook.tailFreqStep;
/// how far the tail swings with the gait (radians)
const tailGait=lib.player.tuningLook.tailGait;
/// how far the tail's idle sway swings (radians)
const tailIdle=lib.player.tuningLook.tailIdle;
/// how fast the tail's idle sway swings (radians a second)
const tailIdleRate=lib.player.tuningLook.tailIdleRate;
/// how far a turn swings the tail (radians per rad/s)
const tailTurn=lib.player.tuningLook.tailTurn;
/// the furthest a turn swings the tail (radians)
const tailTurnMax=lib.player.tuningLook.tailTurnMax;
/// where in a unit's pry the wrench ends (0..1)
const wrenchEnd=lib.player.tuning.wrenchEnd;
/// the belly's lumps: their rest places, springs and weights
const lumps=lib.player.tuningLook.lumps;
/// what lags on springs, one step of `dt`: lean and bank, arms and
/// elbows, ears, fingers and spread, head, and tail
pub fn springs(p:*Player,dt:f32)void{
  // how far into stride
  const st=p.stride;
  // the generic gesture gives way to the gathering pose
  const work=p.reach.x*(1-p.squat.x);
  p.lean.to(m.clamp(leanStride*st+p.accel[2]*leanAccel,-leanMax,leanMax)+leanWork*work,leanFreq,leanDamp,dt);
  p.bank.to(m.clamp(-p.turn*bank*st,-bankMax,bankMax),leanFreq,bankDamp,dt);
  for(0..2)|s|{
    // each arm swings with the opposite leg: back as its own leg comes forward
    // where this arm's leg is in the cycle, its swing, and the dig it reaches for
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
  // how idle the wolf is: standing, its paws not at work
  const idle=(1-st)*(1-work);
  for(&p.curl,&p.spread,0..)|*hand,*spread,s|{
    // this hand's idle flex (when it ripples), and its dig stroke's phase
    const flex=m.clamp01(noise.grad(0xF1C+%s,p.t*flexRate,0.5)*2);
    const stroke=p.t*digRate+m.f(s)*1.7-0.6;
    // the hand's fingers' curl summed, to see how shut it is
    var sum:f32=0;
    for(hand,0..)|*c,i|{
      // which finger this is, as a number
      const fi=m.f(i);
      // the finger's curl wanted: resting, curling with the swing, flexing idle
      var target=curlRest+curlSwing*st*m.clamp01(-p.arm[s].x*1.5);
      target+=curlFlex*idle*flex*m.clamp01(@sin(p.t*flexWave-fi*flexLag+m.f(s)*2.1));
      // where in its rake this finger is (0 open .. 1 shut)
      const rake=0.5+0.5*@sin(stroke-fi*gripLag);
      target=m.lerp(target,m.lerp(gripOpen,gripClose,rake),work);
      // gathering: shut on the node, opening as the paw comes back to it,
      // cupped round a unit on its way to the belly
      // the pry's unit share, how shut the paw grips, and how cupped it stows
      const k=p.gather orelse 0;
      const regrip=1-m.smooth(m.clamp01((k-wrenchEnd)/(1-wrenchEnd)*2))*m.smooth(m.clamp01((1-k)*8));
      const hold=m.lerp(gripOpen,pryGrip,regrip);
      const cup=m.clamp01(p.stowLeft(s)*4);
      target=m.lerp(target,m.lerp(hold,stowCup,cup),p.squat.x);
      // resting: the paw on the belly lies flat, the one on the hip curls
      target=m.lerp(target,if(s==1)restFlat else restFist,p.restPose.x*(1-p.squat.x));
      c.to(target,fingerFreq,fingerDamp,dt);
      sum+=c.x;
    }
    // how shut the hand is, 0..1, which draws its fingers together
    const shut=m.clamp01(sum/(skel.fingerCount*gripClose));
    spread.to(m.lerp(spreadOpen,spreadShut,shut),fingerFreq,spreadDamp,dt);
  }
  // where the head wants to turn and nod
  var look=m.clamp(p.turn*lookTurn,-lookMax,lookMax)+lookIdle*idle*noise.grad(0x100C,p.t*lookIdleRate,0.5);
  var nod=lookWork*(work+p.squat.x)+0.12*idle*noise.grad(0x40D,p.t*lookIdleRate,3.5);
  // seen from its own eyes, the head looks where they do, ahead of the
  // body still turning to them, and nods up and down with them
  if(p.aim)|a|look=m.clamp(m.angleDiff(p.facing,a),-lookMax,lookMax);
  if(p.gaze)|up|nod=m.clamp(-up*gazeNod,gazeNodUp,gazeNodDown)+lookWork*(work+p.squat.x);
  p.look.to(look,headFreq,headDamp,dt);
  p.nod.to(nod,headFreq,headDamp,dt);
  // tail: each joint chases the one before it, steered by turning and gait
  // what the root wants: swung out by turns, swaying idle, swinging in stride
  var target=m.clamp(-p.turn*tailTurn,-tailTurnMax,tailTurnMax)+@sin(p.t*tailIdleRate)*tailIdle*(1-st)+@sin(p.phase*m.tau)*tailGait*st;
  for(&p.tail,0..)|*j,i|{
    j.to(target,tailFreq-m.f(i)*tailFreqStep,tailDamp,dt);
    target=j.x;
  }
}
/// the belly's lumps and the resin lag behind the body's acceleration
/// (inertia), overshoot when it stops, and settle back on their springs;
/// a footfall drops them a little.
/// One step of `dt`: lumps, pectorals and rear on their springs, each kept
/// within its room; `fell` is whether a foot came down this frame.
pub fn slosh(p:*Player,fell:bool,dt:f32)void{
  // how far a lump may stray, and the inertial push on everything hung
  const room=p.bellyRoom();
  const force=-p.accel*m.splat3(sloshAmount);
  for(&p.lump,lumps)|*s,l|{
    if(fell)s.vel[1]-=stepKick*p.stride;
    m.springDamper(&s.pos,&s.vel,l.rest*m.splat3(room),l.k,l.c,l.mass,force*m.splat3(l.mass),dt);
    // stay inside the sac; hitting its wall stops the outward motion
    // how far the lump has strayed, and the wall's outward direction
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
    // how far the pectoral has strayed, kept within its reach
    const d=m.len(s.pos);
    if(d>pecMax)s.pos*=m.splat3(pecMax/d);
  }
  for(&p.rump)|*s|{
    if(fell)s.vel[1]-=rumpKick*p.stride;
    m.springDamper(&s.pos,&s.vel,v3(0,0,0),rumpK,rumpC,pecMass,force*m.splat3(pecMass),dt);
    // how far the rear has strayed, kept within its reach
    const d=m.len(s.pos);
    if(d>rumpMax)s.pos*=m.splat3(rumpMax/d);
  }
}
/// how far a lump's centre may stray from the gut's centre (in the gut
/// bone's frame, which swells with it): within `bellyRoomSize` of the sac,
/// and never poking through it
pub fn bellyRoom(_:*const Player)f32{
  return@max(@min(bellyMesh.down,@min(bellyMesh.rx,bellyMesh.rz))*bellyRoomSize-lumpR,bellyRoomMin);
}
