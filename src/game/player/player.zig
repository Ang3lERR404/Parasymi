//! the wolf: what it carries and where it is, moving over the tiles.
const lib=@import("../../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const items=lib.items;
const World=lib.world.World;
const skel=lib.skeleton;
const V3=m.V3;
const v3=m.v3;
const M4=m.M4;
const translate=m.translate;
const accelResponse=lib.player.tuning.accelResponse;
const bellyStance=lib.player.tuning.bellyStance;
const chestHeight=lib.player.tuning.chestHeight;
const curlRest=lib.player.tuningLook.curlRest;
const cycle=lib.player.tuning.cycle;
const dutySlow=lib.player.tuning.dutySlow;
const faceMinSpeed=lib.player.tuning.faceMinSpeed;
const groundFreq=lib.player.tuning.groundFreq;
const liftAmount=lib.player.tuning.liftAmount;
const minDt=lib.player.tuning.minDt;
const probeRadius=lib.player.tuning.probeRadius;
const reachDistance=lib.player.tuning.reachDistance;
const settleTime=lib.player.tuning.settleTime;
const slots=lib.player.slots;
const sprintSpeed=lib.player.tuning.sprintSpeed;
const squatStance=lib.player.tuning.squatStance;
const stepUp=lib.player.tuning.stepUp;
const turnResponse=lib.player.tuning.turnResponse;
const walkSpeed=lib.player.tuning.walkSpeed;
const workDrag=lib.player.tuning.workDrag;
const lumps=lib.player.tuningLook.lumps;
const restFoot=lib.player.ik.restFoot;
/// a point mass on a spring: offset from its rest place and velocity.
const Spring3=struct{
  pos:V3=v3(0,0,0),
  vel:V3=v3(0,0,0),
};
/// a damped angular spring (critically damped is `damp` 1)
const Swing=struct{
  x:f32=0,
  v:f32=0,
  pub fn to(s:*Swing,target:f32,freq:f32,damp:f32,dt:f32)void{
    const w=freq*m.tau/4;
    s.v+=(w*w*(target-s.x)-2*damp*w*s.v)*dt;
    s.x+=s.v*dt;
  }
};
/// one foot: where its ball is in the world, and its swing (`t` 1 planted)
const Foot=struct{
  at:V3=v3(0,0,0),
  from:V3=v3(0,0,0),
  t:f32=1,
  dur:f32=settleTime,
  lift:f32=liftAmount,
  /// where in the gait it was last frame
  phase:f32=0,
  /// 1 planted .. 0 lifted, eased (the central pad flattens with it)
  pad:f32=1,
  padV:f32=0,
  pub fn planted(f:*const Foot)bool{return f.t>=1;}
};
/// a paw coming down, for what hears it (game/sound.zig): how heavy the
/// wolf is (the belly's stage, 0 light .. 1 full) and how fast it goes
/// (0 standing .. 1 sprinting)
pub const Footfall=struct{weight:f32,pace:f32};
pub const Player=struct{
  /// feet position (y follows the terrain)
  pos:V3,
  vel:V3=v3(0,0,0),
  yV:f32=0,
  facing:f32=0,
  turn:f32=0,
  inv:items.Inventory(slots)=.{},
  // animation state
  t:f32=0,
  /// where in the gait cycle (0..1), and how far into stride (0 standing)
  phase:f32=0,
  stride:f32=0,
  /// the cycle's length and stance share this frame
  cycle:f32=cycle,
  duty:f32=dutySlow,
  breath:f32=0,
  /// how full the belly looks, easing toward the inventory's fill
  fullness:f32=0,
  /// velocity last frame and the acceleration felt since, in the wolf's own
  /// frame (x right, z forward)
  lastVel:V3=v3(0,0,0),
  accel:V3=v3(0,0,0),
  feet:[2]Foot=@splat(.{}),
  placed:bool=false,
  /// paws come down since `footfalls` last took them
  fell:[2]?Footfall=@splat(null),
  /// what lags on springs: the lean and bank of the body, each arm's swing
  /// and elbow, the head's turn and nod, the ears
  lean:Swing=.{},
  bank:Swing=.{},
  arm:[2]Swing=@splat(.{}),
  elbow:[2]Swing=@splat(.{}),
  look:Swing=.{},
  nod:Swing=.{},
  ear:[2]Swing=@splat(.{}),
  /// each finger's curl, each hand's spread
  curl:[2][skel.fingerCount]Swing=@splat(@splat(.{.x=curlRest})),
  spread:[2]Swing=@splat(.{}),
  /// what hangs in the belly (relative to its centre) and the resin's
  /// give (relative to its rest)
  lump:[lumps.len]Spring3=@splat(.{}),
  pec:[2]Spring3=@splat(.{}),
  rump:[2]Spring3=@splat(.{}),
  tail:[skel.tailCount]Swing=@splat(.{}),
  /// 0..1 blend toward the work gesture (gathering, planting, harvesting)
  reach:Swing=.{},
  /// where the hands are busy (gathering, weaving, ...); null while idle
  work:?V3=null,
  /// gathering from the node at `work`: how far through the unit being
  /// pried loose (0..1); null otherwise
  gather:?f32=null,
  /// 0..1 blend into the gathering squat
  squat:Swing=.{},
  /// where each wrist is wanted while gathering (wolf space), on a spring
  wrist:[2]Spring3=@splat(.{}),
  /// seconds left of each paw pressing a unit into the belly, which paw
  /// takes the next one, and the unit share last frame
  stow:[2]f32=@splat(0),
  nextStow:u1=0,
  lastPry:f32=0,
  /// seconds stood still with idle hands, and the blend into the
  /// belly-rest idle
  still:f32=0,
  restPose:Swing=.{},
  /// seen from its own eyes: the facing they want (the body turns to it,
  /// the head leads) and how far up (+) or down they look; null otherwise
  aim:?f32=null,
  gaze:?f32=null,
  /// a pose set from outside (the animation editor, tools/animedit.zig),
  /// shown in place of the procedural one; null in play
  posed:?skel.Pose=null,
  /// tile-aware: no wading, one terrace step at a time.
  pub fn move(p:*Player,wish:[2]f32,sprint:bool,ground:*const World,dt:f32)void{
    const g=p.gait();
    const speed:f32=if(sprint)sprintSpeed*g.sprint else walkSpeed*g.walk;
    const target=v3(wish[0]*speed,0,wish[1]*speed);
    const k=@min(1,dt*accelResponse);
    p.vel+=(target-p.vel)*m.splat3(k);
    if(p.work!=null)p.vel*=m.splat3(workDrag);
    const here=ground.walkable(m.tileOf(p.pos[0]),m.tileOf(p.pos[2])) orelse p.pos[1];
    // resolve each axis separately so the wolf slides along cliffs
    inline for(.{0,2})|axis|{
      var next=p.pos;
      next[axis]+=p.vel[axis]*dt;
      // probe a little ahead so the body does not clip into terrace walls
      var probe=next;
      probe[axis]+=if(p.vel[axis]>0)probeRadius else-probeRadius;
      const ok=if(ground.walkable(m.tileOf(probe[0]),m.tileOf(probe[2])))|h|h-here<=stepUp else false;
      if(ok)p.pos[axis]=next[axis]else p.vel[axis]=0;
    }
    // the body follows the ground as it is drawn, so its paws meet it
    const h=if(ground.walkable(m.tileOf(p.pos[0]),m.tileOf(p.pos[2]))!=null)ground.surfaceAt(p.pos[0],p.pos[2])else here;
    m.spring(&p.pos[1],&p.yV,h,groundFreq,dt);
    // face what we work on, where the eyes look, or where we move
    var want=p.facing;
    if(p.work)|w|{
      want=m.atan2(w[0]-p.pos[0],w[2]-p.pos[2]);
    }else if(p.aim)|a|{
      want=a;
    }else if(@abs(p.vel[0])+@abs(p.vel[2])>faceMinSpeed){
      want=m.atan2(p.vel[0],p.vel[2]);
    }
    const diff=m.angleDiff(p.facing,want);
    const turn=diff*@min(1,dt*turnResponse);
    p.facing+=turn;
    p.turn=turn/@max(dt,minDt);
  }
  /// the paws come down since last asked, once each
  pub fn footfalls(p:*Player)[2]?Footfall{
    defer p.fell=@splat(null);
    return p.fell;
  }
  pub fn groundSpeed(p:*const Player)f32{return@sqrt(p.vel[0]*p.vel[0]+p.vel[2]*p.vel[2]);}
  /// wolf space to the world: where it stands, turned the way it faces
  pub fn heading(p:*const Player)M4{return m.chain(&.{translate(p.pos),m.rotY(p.facing)});}
  /// where a foot rests under the standing wolf, in the world
  pub fn rest(p:*const Player,ground:?*const World,s:usize)V3{
    const x=restFoot[s][0]+skel.sign(s)*(bellyStance*p.fullness+squatStance*p.squat.x);
    const r=m.mulV(p.heading(),.{x,0,restFoot[s][2],1});
    return p.onGround(ground,v3(r[0],0,r[2]));
  }
  /// `at` set down on the ground as it is drawn (level with the body
  /// without a world), so a paw never sinks into a slope
  pub fn onGround(p:*const Player,ground:?*const World,at:V3)V3{
    const y=if(ground)|g|g.surfaceAt(at[0],at[2])else p.pos[1];
    return v3(at[0],y,at[2]);
  }
  pub fn chest(p:*const Player)V3{return p.pos+v3(0,chestHeight,0);}
  pub fn inReach(p:*const Player,wx:i32,wz:i32)bool{
    const c=m.tileCentre(wx,wz,0);
    const dx=c[0]-p.pos[0];
    const dz=c[2]-p.pos[2];
    return dx*dx+dz*dz<=reachDistance*reachDistance;
  }
  pub const animate=lib.player.motion.animate;
  pub const stage=lib.player.motion.stage;
  pub const gait=lib.player.motion.gait;
  pub const bellyFill=lib.player.motion.bellyFill;
  pub const step=lib.player.motion.step;
  pub const pry=lib.player.motion.pry;
  pub const wristWant=lib.player.motion.wristWant;
  pub const workLocal=lib.player.motion.workLocal;
  pub const springs=lib.player.springs.springs;
  pub const slosh=lib.player.springs.slosh;
  pub const bellyRoom=lib.player.springs.bellyRoom;
  pub const pose=lib.player.posing.pose;
  pub const restArms=lib.player.posing.restArms;
  pub const armsToWrists=lib.player.posing.armsToWrists;
  pub const legs=lib.player.posing.legs;
  pub const eyes=lib.player.posing.eyes;
  pub const rig=lib.player.posing.rig;
};
