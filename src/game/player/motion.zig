//! the wolf's motion each frame: gait stages, footsteps and the gathering pry.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, springs, easing
const m=engine.core.math;
/// the garden's world, whose ground the feet are planted on
const World=lib.world.World;
/// the wolf's skeleton: its bones, pose and forward kinematics
const skel=lib.skeleton;
/// the belly's mesh: its radii and depth, where a stowing paw presses
const bellyMesh=lib.wolfBelly;
/// a point or direction in 3D
const V3=m.V3;
/// builds a 3D vector from its three parts
const v3=m.v3;
/// one bone of the wolf's skeleton
const Bone=skel.Bone;
/// how many items carried bring the belly most of the way to full
const bellyItems=lib.player.tuning.bellyItems;
/// the breath's tempo at rest (radians a second)
const breathRate=lib.player.tuning.breathRate;
/// the breath's tempo at a full sprint (radians a second)
const breathRateRun=lib.player.tuning.breathRateRun;
/// the gait cycle's length standing still (m)
const cycle=lib.player.tuning.cycle;
/// how much longer the cycle grows per m/s of speed (m)
const cyclePerSpeed=lib.player.tuning.cyclePerSpeed;
/// the share of the cycle a foot is planted, at a sprint
const dutyFast=lib.player.tuning.dutyFast;
/// the share of the cycle a foot is planted, walking slowly
const dutySlow=lib.player.tuning.dutySlow;
/// how quickly the belly's look follows its fill (per second)
const fullnessResponse=lib.player.tuning.fullnessResponse;
/// the light, heavy and full gaits
const gaits=lib.player.tuning.gaits;
/// how far ahead of its feet the wolf gathers from a node (m)
const gatherAt=lib.player.tuning.gatherAt;
/// how far either side of the node each paw grips (m)
const gripSide=lib.player.tuning.gripSide;
/// how high above the node's ground the paws grip (m)
const gripUp=lib.player.tuning.gripUp;
/// one stage's gait: speeds, stride, lift, sway, roll, sink, bob, lean
const Gait=lib.player.tuning.Gait;
/// how damped the gripping wrists' spring is
const handDamp=lib.player.tuning.handDamp;
/// how stiffly the gripping wrists chase their want (spring frequency)
const handFreq=lib.player.tuning.handFreq;
/// how high a swinging foot lifts standing (m)
const liftAmount=lib.player.tuning.liftAmount;
/// the lift's arc over the swing (sin to this power)
const liftArc=lib.player.tuning.liftArc;
/// how much higher a foot lifts at full stride (m)
const liftStride=lib.player.tuning.liftStride;
/// a foot this far from the body is put straight back (m)
const lost=lib.player.tuning.lost;
/// the shortest frame time a rate is divided by (s)
const minDt=lib.player.tuning.minDt;
/// how stiffly a foot's pad squashes and springs back (spring frequency)
const padFreq=lib.player.tuningLook.padFreq;
/// how far back the pull draws the paws (m)
const pryBack=lib.player.tuning.pryBack;
/// how far up the pull lifts the paws (m)
const pryUp=lib.player.tuning.pryUp;
/// the wolf whose motion this is
const Player=lib.player.player.Player;
/// how stiffly the paws move into and out of the work gesture
const reachFreq=lib.player.tuning.reachFreq;
/// how long it stands still before the belly rest begins (s)
const restAfter=lib.player.tuning.restAfter;
/// how stiffly the rest pose eases in (spring frequency)
const restFreq=lib.player.tuning.restFreq;
/// how full the belly must be before the rest begins (0..1)
const restFull=lib.player.tuning.restFull;
/// how full it is when the rest is fully in (0..1)
const restFullIn=lib.player.tuning.restFullIn;
/// a standing foot further than this from rest steps back under (m)
const settle=lib.player.tuning.settle;
/// how long that settling step takes (s)
const settleTime=lib.player.tuning.settleTime;
/// its top sprinting speed (m/s)
const sprintSpeed=lib.player.tuning.sprintSpeed;
/// how stiffly the squat eases in and out (spring frequency)
const squatFreq=lib.player.tuning.squatFreq;
/// where the heavy and full stages begin (shares of fullness)
const stageAt=lib.player.tuning.stageAt;
/// how much fullness each stage blends over
const stageBlend=lib.player.tuning.stageBlend;
/// below this stride the wolf counts as standing
const standing=lib.player.tuning.standing;
/// how long a paw takes to press a loose unit into the belly (s)
const stowTime=lib.player.tuning.stowTime;
/// how quickly the stride eases in and out (per second)
const strideResponse=lib.player.tuning.strideResponse;
/// the longest a striding swing lasts (s)
const swingMax=lib.player.tuning.swingMax;
/// the shortest a striding swing lasts (s)
const swingMin=lib.player.tuning.swingMin;
/// the fastest a swinging paw moves over the ground (m/s)
const swingSpeedMax=lib.player.tuning.swingSpeedMax;
/// the slowest speed a swing is timed for (m/s)
const swingSpeedMin=lib.player.tuning.swingSpeedMin;
/// a planted foot never trails the hip further than this (m)
const trailMax=lib.player.tuning.trailMax;
/// a planted foot this far behind lifts whatever the other does (m)
const trailHard=lib.player.tuning.trailHard;
/// its top walking speed (m/s)
const walkSpeed=lib.player.tuning.walkSpeed;
/// how far through its pull and wrench a unit's pry is (0..1)
const pryPull=lib.player.ik.pryPull;
/// how long a paw takes to carry a plucked unit to the belly (s)
const pluckStow=lib.player.tuning.pluckStow;
/// how far either side of a plucked yield each paw closes (m)
const pluckSide=lib.player.tuning.pluckSide;
/// how far the pull draws a plucked yield back toward the wolf (m)
const pluckBack=lib.player.tuning.pluckBack;
/// the squat is at its full depth for work this high over the feet (m)
const lowFrom=lib.player.tuning.lowFrom;
/// and gone this much higher (m)
const lowSpan=lib.player.tuning.lowSpan;
/// past this height over the feet the wolf stretches up to its work (m)
const riseFrom=lib.player.tuning.riseFrom;
/// and is stretched in full this much higher (m)
const riseSpan=lib.player.tuning.riseSpan;
/// one frame of motion: the gait's stride, cycle and phase follow the
/// speed, breath quickens with effort, the belly's look follows its fill,
/// the work, pry and rest poses ease, then the feet step, what hangs
/// sloshes, and every spring settles
pub fn animate(p:*Player,ground:?*const World,dt:f32)void{
  p.t+=dt;
  // how fast it moves over the ground, and the gait its belly allows
  const spd=p.groundSpeed();
  const g=p.gait();
  // the top walk and sprint speeds for that gait
  const walk=walkSpeed*g.walk;
  const sprint=sprintSpeed*g.sprint;
  p.stride+=(m.clamp01(spd/walk)-p.stride)*@min(1,dt*strideResponse);
  p.cycle=(cycle+cyclePerSpeed*spd)*g.stride;
  p.duty=m.lerp(dutySlow,dutyFast,m.clamp01((spd-1)/(sprint-1)));
  p.phase=@mod(p.phase+spd/p.cycle*dt,1);
  // how hard it is working: 0 at rest .. 1 at a full sprint
  const effort=m.clamp01(spd/sprint);
  p.breath+=dt*m.lerp(breathRate,breathRateRun,effort);
  p.fullness+=(p.bellyFill()-p.fullness)*@min(1,dt*fullnessResponse);
  p.reach.to(if(p.work!=null)1 else 0,reachFreq,1,dt);
  p.pry(dt);
  p.still=if(p.stride<standing and p.work==null and p.gather==null)p.still+dt else 0;
  // how heavy the belly is for the rest pose: 0 .. 1 once full enough
  const heavy=m.smooth(m.clamp01((p.fullness-restFull)/(restFullIn-restFull)));
  p.restPose.to(if(p.still>restAfter)heavy else 0,restFreq,1,dt);
  // what the body feels: its acceleration, turned into its own frame
  const a=(p.vel-p.lastVel)/m.splat3(@max(dt,minDt));
  p.lastVel=p.vel;
  // that acceleration turned into the wolf's own frame
  const al=m.mulV(m.rotY(-p.facing),.{a[0],a[1],a[2],0});
  p.accel=v3(al[0],al[1],al[2]);
  // whether a foot came down this frame
  const fell=p.step(ground,spd,dt);
  p.slosh(fell,dt);
  p.springs(dt);
  p.trailTail(dt);
}
/// which of the belly's stages the wolf is in: 0 light .. 1 heavy .. 2
/// full, blending over `stageBlend` about each threshold
pub fn stage(p:*const Player)f32{
  // the stages passed so far, each blended in about its threshold
  var out:f32=0;
  for(stageAt)|at|out+=m.smooth(m.clamp01((p.fullness-at)/stageBlend+0.5));
  return out;
}
/// the gait for the belly's load (`gaits` blended by `stage`)
pub fn gait(p:*const Player)Gait{
  // the stage, the pair of gaits it lies between, and how far along
  const st=p.stage();
  const i:usize=if(st>=1)1 else 0;
  const k=st-m.f(i);
  // the two gaits blended between
  const a=gaits[i];
  const b=gaits[i+1];
  // the gait blended field by field
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
  // whether it is striding, or only standing
  const moving=p.stride>standing;
  // how far ahead of the hip a foot lands, so it passes under the hip
  // mid-stance
  const ahead=if(spd>0.1)p.vel/m.splat3(spd)*m.splat3(p.duty*p.cycle*0.5*m.clamp01(spd/1.5))else v3(0,0,0);
  // whether any foot came down this frame
  var fell=false;
  for(&p.feet,0..)|*f,s|{
    // the other foot
    const other=&p.feet[1-s];
    if(m.len(f.at-p.rest(ground,s))>lost){
      f.*=.{.at=p.rest(ground,s),.phase=f.phase};
      continue;
    }
    // where this foot is in the gait's cycle (the two half a cycle apart)
    const ph=@mod(p.phase+0.5*m.f(s),1);
    if(f.planted()){
      // how far it is from where it rests
      const off=m.len(f.at-p.rest(ground,s));
      // a foot trailing too far always lifts (the other one is down by then)
      var lift=(off>trailMax and other.planted()) or off>trailHard;
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
      // the swing's ease and lift before this frame, and the foot under its lift
      const k0=m.smooth(f.t);
      var base=f.at;
      base[1]-=f.lift*m.pow(f32,@sin(f.t*m.pi),liftArc);
      f.t=@min(1,f.t+dt/f.dur);
      // the swing's time left, where it will land, and how far along it is
      const left=(1-f.t)*f.dur;
      const to=p.onGround(ground,p.rest(ground,s)+p.vel*m.splat3(left)+ahead);
      const k=m.smooth(f.t);
      // decision: the foot closes this frame's share of what is left to its
      // landing, never re-lerped from where it set off, so a landing that
      // moves (a turn, a stop, a wall, a step) bends the swing, never jumps it
      const share=if(k0<1)(k-k0)/(1-k0)else 1;
      // that share over the ground, never faster than a paw can swing (a
      // landing flung far by a sudden reversal is stepped toward, not leapt to)
      var by=(to-base)*m.splat3(share);
      const over=@sqrt(by[0]*by[0]+by[2]*by[2]);
      const most=swingSpeedMax*dt;
      if(over>most){
        by[0]*=most/over;
        by[2]*=most/over;
      }
      f.at=base+by;
      f.at[1]+=f.lift*m.pow(f32,@sin(f.t*m.pi),liftArc);
      if(f.planted()){
        f.at[1]=to[1];
        fell=true;
        p.fell[s]=.{.weight=p.stage()/2,.pace=m.clamp01(spd/(sprintSpeed*p.gait().sprint))};
      }
    }
    // its pad squashes as it plants, springing back as it lifts
    m.spring(&f.pad,&f.padV,if(f.planted())1 else 0,padFreq,dt);
    // it feels the slope of the ground under it, settling to it
    f.nrm=m.norm(m.lerpV(f.nrm,p.groundNormal(ground,f.at),m.clamp01(dt*lib.player.tuning.slopeRate)));
  }
  return fell;
}
/// gathering: the squat eases in and out, each unit come loose sends a
/// paw (one, then the other) to the belly, and the wrists chase where the
/// pry wants them
pub fn pry(p:*Player,dt:f32)void{
  p.squat.to(if(p.gather!=null)1 else 0,squatFreq,1,dt);
  // the squat's depth and the stretch follow the work's height (held as
  // they were once the work is done, while the squat eases out)
  if(p.work!=null){
    // how low and how high the work is
    const h=p.height();
    p.low.to(h.low,squatFreq,1,dt);
    p.rise.to(h.rise,squatFreq,1,dt);
  }
  for(&p.stow)|*t|t.*=@max(t.*-dt,0);
  // the unit's share of the pry, or nothing if not gathering
  const k=p.gather orelse {
    p.lastPry=0;
    return;
  };
  // (a node's unit is sent once the next is gripped; a plucked one as it
  // comes loose, by `stowUnit`)
  if(p.hold==.node and k<p.lastPry and p.squat.x>0.5)p.stowUnit();
  p.lastPry=k;
  // the skeleton's pose, which the wrists' wants are taken from
  const q=p.pose();
  for(&p.wrist,0..)|*w,s|{
    // where this wrist is wanted
    const want=p.wristWant(q,s,k);
    // just crouching, the wrists start where they are wanted
    if(p.squat.x<0.02)w.*=.{.pos=want};
    m.springDamper(&w.pos,&w.vel,want,handFreq*handFreq,2*handDamp*handFreq,1,v3(0,0,0),dt);
  }
}
/// how long a paw takes to carry a unit to the belly: a plucked one slower,
/// so it is seen leaving the plant
pub fn stowSpan(p:*const Player)f32{
  return switch(p.hold){
    .node=>stowTime,
    .plant=>pluckStow,
  };
}
/// how much of paw `s`'s carry to the belly is still to come (1 setting
/// off .. 0 done)
pub fn stowLeft(p:*const Player,s:usize)f32{return p.stow[s]/p.stowSpan();}
/// a unit come loose sent to the belly: the next paw, in turn, presses it in
pub fn stowUnit(p:*Player)void{
  p.stow[p.nextStow]=p.stowSpan();
  p.nextStow+%=1;
}
/// how high the work is, as the body answers it: `low` 1 down in the full
/// squat (a node, or a yield near the ground) .. 0 standing to it, and
/// `rise` 0 .. 1 stretched up to one over its head
pub fn height(p:*const Player)struct{low:f32,rise:f32}{
  // how high the work is over the feet
  const y=p.workLocal()[1];
  return.{.low=1-m.smooth(m.clamp01((y-lowFrom)/lowSpan)),.rise=m.smooth(m.clamp01((y-riseFrom)/riseSpan))};
}
/// where wrist `s` is wanted (wolf space) at unit share `k`: on the node,
/// pulled back and up through the pry (or either side of a plucked yield,
/// drawn back toward the wolf), or at the belly while stowing
pub fn wristWant(p:*const Player,q:skel.Pose,s:usize,k:f32)V3{
  // the node, which side this wrist is on, and how far the pull has drawn
  const node=p.workLocal();
  const x=skel.sign(s);
  const pull=pryPull(k);
  // the grip on the node, drawn back and up by the pull (a plucked
  // yield's, toward the wolf)
  const grip=switch(p.hold){
    .node=>node+v3(x*gripSide,gripUp+pryUp*pull,-pryBack*pull),
    .plant=>node+v3(x*pluckSide,0,-pluckBack*pull),
  };
  // how far toward the belly a stowing paw is: up, then back again
  // (a plucked one carried in steadily, a pried one pressed in at once)
  const press:f32=switch(p.hold){
    .node=>1.6,
    .plant=>1.1,
  };
  const stow=m.smooth(m.clamp01(@sin(p.stowLeft(s)*m.pi)*press));
  if(stow<=0)return grip;
  // the bones in the wolf's space, and the belly's front where the paw presses
  const w=skel.fk(q);
  const belly=m.mulPoint(w[@intFromEnum(Bone.gut)],v3(x*bellyMesh.rx*0.3,bellyMesh.down*0.15,bellyMesh.rz*1.15));
  return m.lerpV(grip,belly,stow);
}
/// the node worked on, in the wolf's own frame (a little ahead without one)
pub fn workLocal(p:*const Player)V3{
  // the node in the world, or a spot just ahead when there is none
  const at=p.work orelse return v3(0,0,gatherAt);
  // the node in the wolf's own frame
  const l=m.mulV(m.inverseRigid(p.heading()),.{at[0],at[1],at[2],1});
  return v3(l[0],l[1],l[2]);
}
