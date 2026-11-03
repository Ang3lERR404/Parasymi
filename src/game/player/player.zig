//! the wolf: what it carries and where it is, moving over the tiles.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, matrices, springs, angles
const m=engine.core.math;
/// what can be carried: item kinds and the inventory
const items=lib.items;
/// the garden's world: which tiles are walkable and how high
const World=lib.world.World;
/// the wolf's skeleton: its bones, pose and finger and tail counts
const skel=lib.skeleton;
/// a point or direction in 3D
const V3=m.V3;
/// builds a 3D vector from its three parts
const v3=m.v3;
/// a 4x4 transform
const M4=m.M4;
/// a transform that moves by a vector
const translate=m.translate;
/// how quickly velocity matches the wish (per second)
const accelResponse=lib.player.tuning.accelResponse;
/// how far a full belly sets each foot out to the side (m)
const bellyStance=lib.player.tuning.bellyStance;
/// how high above its feet what the wolf works on sits (m)
const chestHeight=lib.player.tuning.chestHeight;
/// the fingers' loose curl at rest (radians)
const curlRest=lib.player.tuningLook.curlRest;
/// the gait cycle's length standing still (m)
const cycle=lib.player.tuning.cycle;
/// the share of the cycle a foot is planted, walking slowly
const dutySlow=lib.player.tuning.dutySlow;
/// slower than this (m/s), the wolf keeps the way it faces
const faceMinSpeed=lib.player.tuning.faceMinSpeed;
/// how stiffly it follows the terrain's height (spring frequency)
const groundFreq=lib.player.tuning.groundFreq;
/// how high a swinging foot lifts standing (m)
const liftAmount=lib.player.tuning.liftAmount;
/// the shortest frame time a rate is divided by (s)
const minDt=lib.player.tuning.minDt;
/// how far ahead of its centre the body is probed for walls (m)
const probeRadius=lib.player.tuning.probeRadius;
/// how far the wolf can reach to work or gather (m)
const reachDistance=lib.player.tuning.reachDistance;
/// how long a standing foot's settling step takes (s)
const settleTime=lib.player.tuning.settleTime;
/// how many slots the belly holds
const slots=lib.player.slots;
/// its top sprinting speed (m/s)
const sprintSpeed=lib.player.tuning.sprintSpeed;
/// how far the feet step out to each side in the squat (m)
const squatStance=lib.player.tuning.squatStance;
/// the highest terrace step it climbs in one go (m)
const stepUp=lib.player.tuning.stepUp;
/// how quickly its facing turns to the target (per second)
const turnResponse=lib.player.tuning.turnResponse;
/// its top walking speed (m/s)
const walkSpeed=lib.player.tuning.walkSpeed;
/// how much velocity is kept each frame while the paws work (0..1)
const workDrag=lib.player.tuning.workDrag;
/// the belly's lumps: their rest places, springs and weights
const lumps=lib.player.tuningLook.lumps;
/// where each foot's ball rests under the standing wolf (wolf space)
const restFoot=lib.player.ik.restFoot;
/// a point mass on a spring: offset from its rest place and velocity.
const Spring3=struct{
  /// how far it has strayed from its rest place
  pos:V3=v3(0,0,0),
  /// how fast it is moving
  vel:V3=v3(0,0,0),
};
/// a damped angular spring (critically damped is `damp` 1)
const Swing=struct{
  /// where the spring has swung to (radians, or a 0..1 blend)
  x:f32=0,
  /// how fast it is swinging
  v:f32=0,
  /// swing one step of `dt` toward `target`, `freq` setting how stiff
  /// (a quarter turn a second per unit) and `damp` how damped
  pub fn to(s:*Swing,target:f32,freq:f32,damp:f32,dt:f32)void{
    // the spring's angular frequency
    const w=freq*m.tau/4;
    s.v+=(w*w*(target-s.x)-2*damp*w*s.v)*dt;
    s.x+=s.v*dt;
  }
};
/// one foot: where its ball is in the world, and its swing (`t` 1 planted)
const Foot=struct{
  /// where its ball is in the world
  at:V3=v3(0,0,0),
  /// where its swing set off from
  from:V3=v3(0,0,0),
  /// how far through its swing it is, 0..1 (1: planted)
  t:f32=1,
  /// how long its swing lasts (s)
  dur:f32=settleTime,
  /// how high its swing lifts (m)
  lift:f32=liftAmount,
  /// where in the gait it was last frame
  phase:f32=0,
  /// 1 planted .. 0 lifted, eased (the central pad flattens with it)
  pad:f32=1,
  /// how fast the pad is easing
  padV:f32=0,
  /// which way the ground under it faces (the world's up on level
  /// ground), eased as it moves: its sole is laid along it
  nrm:V3=v3(0,1,0),
  /// whether it is down: its swing finished
  pub fn planted(f:*const Foot)bool{return f.t>=1;}
};
/// a paw coming down, for what hears it (game/sound.zig): how heavy the
/// wolf is (the belly's stage, 0 light .. 1 full) and how fast it goes
/// (0 standing .. 1 sprinting), and where it came down (heard from there)
/// (fields: `weight` 0 light .. 1 full, `pace` 0 standing .. 1 sprinting,
/// `at` the paw's place in the world)
pub const Footfall=struct{weight:f32,pace:f32,at:m.V3=@splat(0)};
/// what the paws gather from: a resource node, wrenched out of the ground
/// a unit at a time (each sent to the belly as the next is gripped), or a
/// plant's ripe yield, drawn off it by paw (each sent as it comes loose)
pub const Hold=enum{
  /// a resource node, pried
  node,
  /// a plant's ripe yield, plucked
  plant,
};
/// the wolf: where it stands and moves, what it carries in its belly, and
/// every spring and stage of its procedural motion
pub const Player=struct{
  /// feet position (y follows the terrain)
  pos:V3,
  /// its velocity (m/s); only x and z are walked, y is the ground's
  vel:V3=v3(0,0,0),
  /// how fast its height is springing after the ground
  yV:f32=0,
  /// the way it faces (radians about the vertical; 0 looks down +z)
  facing:f32=0,
  /// how fast it is turning (radians a second)
  turn:f32=0,
  /// what its sap belly carries
  inv:items.Inventory(slots)=.{},
  // animation state
  /// seconds of motion so far: every idle sway and flick keys off it
  t:f32=0,
  /// where in the gait cycle (0..1), and how far into stride (0 standing)
  phase:f32=0,
  /// how far into stride, 0 standing .. 1 full stride
  stride:f32=0,
  /// the cycle's length and stance share this frame
  cycle:f32=cycle,
  /// the share of the cycle a foot is planted this frame
  duty:f32=dutySlow,
  /// the breath's phase (radians), quickening with effort
  breath:f32=0,
  /// how full the belly looks, easing toward the inventory's fill
  fullness:f32=0,
  /// a fill held from outside (`--full=`, for shots of the belly at one
  /// size), whatever it holds; null: the inventory's own
  fullHeld:?f32=null,
  /// velocity last frame and the acceleration felt since, in the wolf's own
  /// frame (x right, z forward)
  lastVel:V3=v3(0,0,0),
  /// the acceleration felt, in its own frame (m/s^2)
  accel:V3=v3(0,0,0),
  /// its two feet, left and right
  feet:[2]Foot=@splat(.{}),
  /// whether the feet have been put under it yet
  placed:bool=false,
  /// paws come down since `footfalls` last took them
  fell:[2]?Footfall=@splat(null),
  /// what lags on springs: the lean and bank of the body, each arm's swing
  /// and elbow, the head's turn and nod, the ears
  lean:Swing=.{},
  /// the body's bank into turns
  bank:Swing=.{},
  /// each arm's swing
  arm:[2]Swing=@splat(.{}),
  /// each elbow's bend
  elbow:[2]Swing=@splat(.{}),
  /// the head's turn
  look:Swing=.{},
  /// the head's nod
  nod:Swing=.{},
  /// each ear's lie
  ear:[2]Swing=@splat(.{}),
  /// each finger's curl, each hand's spread
  curl:[2][skel.fingerCount]Swing=@splat(@splat(.{.x=curlRest})),
  /// each hand's spread
  spread:[2]Swing=@splat(.{}),
  /// what hangs in the belly (relative to its centre) and the resin's
  /// give (relative to its rest)
  lump:[lumps.len]Spring3=@splat(.{}),
  /// the pectorals' give (left, right)
  pec:[2]Spring3=@splat(.{}),
  /// the rear's give (left, right)
  rump:[2]Spring3=@splat(.{}),
  /// each tail joint's swing
  tail:[skel.tailCount]Swing=@splat(.{}),
  /// 0..1 blend toward the work gesture (gathering, planting, harvesting)
  reach:Swing=.{},
  /// where the hands are busy (gathering, weaving, ...); null while idle
  work:?V3=null,
  /// gathering from the node at `work`: how far through the unit being
  /// pried loose (0..1); null otherwise
  gather:?f32=null,
  /// what the paws work at `work` while gathering: a node pried out of the
  /// ground, or a plant's ripe yield plucked
  hold:Hold=.node,
  /// a plucked yield's kind, shown as a bead in each paw that stows one;
  /// null when nothing plucked is carried in
  bead:?items.Item=null,
  /// 0..1 blend into the gathering squat
  squat:Swing=.{},
  /// how deep that squat goes, 1 down in full (work on the ground) .. 0
  /// standing to work at the chest, eased after the work's height
  low:Swing=.{.x=1},
  /// how far it stretches up to work over its head, 0..1, eased the same
  rise:Swing=.{},
  /// where each wrist is wanted while gathering (wolf space), on a spring
  wrist:[2]Spring3=@splat(.{}),
  /// seconds left of each paw pressing a unit into the belly, which paw
  /// takes the next one, and the unit share last frame
  stow:m.Vice(f32,2)=@splat(0),
  /// which paw stows the next unit (0 left, 1 right)
  nextStow:u1=0,
  /// the unit share last frame: a drop means a unit came loose
  lastPry:f32=0,
  /// seconds stood still with idle hands, and the blend into the
  /// belly-rest idle
  still:f32=0,
  /// the blend into the belly-rest idle (0..1)
  restPose:Swing=.{},
  /// seen from its own eyes: the facing they want (the body turns to it,
  /// the head leads) and how far up (+) or down they look; null otherwise
  aim:?f32=null,
  /// how far up (+) or down its eyes look (radians); null otherwise
  gaze:?f32=null,
  /// a pose set from outside (the animation editor, tools/animedit.zig),
  /// shown in place of the procedural one; null in play
  posed:?skel.Pose=null,
  /// each joint of the tail and its tip in the world, trailing behind its
  /// swinging rest shape (null until first laid out)
  tailAt:?[skel.tailCount+1]V3=null,
  /// where each was a step before (its motion)
  tailWas:[skel.tailCount+1]V3=@splat(v3(0,0,0)),
  /// tile-aware: no wading, one terrace step at a time.
  /// Walks it toward `wish` (a direction on the ground, length up to 1) at walk or
  /// sprint speed, sliding along what it cannot climb, its height springing
  /// after the ground, and turns it toward its work, aim or way.
  pub fn move(p:*Player,wish:m.Vice(f32,2),sprint:bool,ground:*const World,dt:f32)void{
    // the gait the belly allows, its top speed, and the velocity wished for
    const g=p.gait();
    const speed:f32=if(sprint)sprintSpeed*g.sprint else walkSpeed*g.walk;
    const target=v3(wish[0]*speed,0,wish[1]*speed);
    // eased toward the wish velocity
    p.vel=m.dampV(p.vel,target,accelResponse,dt);
    if(p.work!=null)p.vel*=m.splat3(workDrag);
    // the height of the tile it stands on
    const here=ground.walkable(m.tileOf(p.pos[0]),m.tileOf(p.pos[2])) orelse p.pos[1];
    // resolve each axis separately so the wolf slides along cliffs
    inline for(.{0,2})|axis|{
      // where this axis would carry it
      var next=p.pos;
      next[axis]+=p.vel[axis]*dt;
      // probe a little ahead so the body does not clip into terrace walls
      var probe=next;
      probe[axis]+=if(p.vel[axis]>0)probeRadius else-probeRadius;
      // whether the probe lands on ground no more than a step above
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
    // how far it is from facing what it wants, and the share turned this frame
    const diff=m.angleDiff(p.facing,want);
    const turn=diff*m.dampBy(turnResponse,dt);
    p.facing+=turn;
    p.turn=turn/@max(dt,minDt);
  }
  /// the paws come down since last asked, once each
  pub fn footfalls(p:*Player)[2]?Footfall{
    defer p.fell=@splat(null);
    return p.fell;
  }
  /// how fast it moves over the ground (m/s), ignoring its rise and fall
  pub fn groundSpeed(p:*const Player)f32{return@sqrt(p.vel[0]*p.vel[0]+p.vel[2]*p.vel[2]);}
  /// wolf space to the world: where it stands, turned the way it faces
  pub fn heading(p:*const Player)M4{return m.chain(&.{translate(p.pos),m.rotY(p.facing)});}
  /// where a foot rests under the standing wolf, in the world
  pub fn rest(p:*const Player,ground:?*const World,s:usize)V3{
    // the foot's rest out to the side: wider for a full belly or a squat
    const x=restFoot[s][0]+skel.sign(s)*(bellyStance*p.fullness+squatStance*p.squat.x*p.low.x);
    // that rest in the world
    const r=m.mulV(p.heading(),.{x,0,restFoot[s][2],1});
    return p.onGround(ground,v3(r[0],0,r[2]));
  }
  /// which way the ground faces at `at` (up without a world): its slope
  /// felt `slopeSpan` either way across and along
  pub fn groundNormal(_:*const Player,ground:?*const World,at:V3)V3{
    // the world, or level ground
    const g=ground orelse return v3(0,1,0);
    // how far the ground is felt either way, and its rise across and along
    const e=lib.player.tuning.slopeSpan;
    const dx=g.surfaceAt(at[0]+e,at[2])-g.surfaceAt(at[0]-e,at[2]);
    const dz=g.surfaceAt(at[0],at[2]+e)-g.surfaceAt(at[0],at[2]-e);
    return m.norm(v3(-dx,2*e,-dz));
  }
  /// `at` set down on the ground as it is drawn (level with the body
  /// without a world), so a paw never sinks into a slope
  pub fn onGround(p:*const Player,ground:?*const World,at:V3)V3{
    // the ground's height there, or the body's
    const y=if(ground)|g|g.surfaceAt(at[0],at[2])else p.pos[1];
    return v3(at[0],y,at[2]);
  }
  /// where what it works on or carries is held: above its feet
  pub fn chest(p:*const Player)V3{return p.pos+v3(0,chestHeight,0);}
  /// whether tile (`wx`, `wz`)'s centre is within its reach
  pub fn inReach(p:*const Player,wx:i32,wz:i32)bool{
    // the tile's centre, and how far off it lies on the ground
    const c=m.tileCentre(wx,wz,0);
    const dx=c[0]-p.pos[0];
    const dz=c[2]-p.pos[2];
    return dx*dx+dz*dz<=reachDistance*reachDistance;
  }
  /// one frame of motion (motion.zig)
  pub const animate=lib.player.motion.animate;
  /// which of the belly's stages it is in: 0 light .. 2 full (motion.zig)
  pub const stage=lib.player.motion.stage;
  /// the gait for its belly's load (motion.zig)
  pub const gait=lib.player.motion.gait;
  /// how full its belly is to look at, 0..1 (motion.zig)
  pub const bellyFill=lib.player.motion.bellyFill;
  /// the feet's step; whether one came down (motion.zig)
  pub const step=lib.player.motion.step;
  /// the gathering pry: squat, stow and wrists (motion.zig)
  pub const pry=lib.player.motion.pry;
  /// where a gathering wrist is wanted (motion.zig)
  pub const wristWant=lib.player.motion.wristWant;
  /// how long a paw takes to carry a unit to the belly (motion.zig)
  pub const stowSpan=lib.player.motion.stowSpan;
  /// how much of a paw's carry to the belly is still to come (motion.zig)
  pub const stowLeft=lib.player.motion.stowLeft;
  /// a plucked unit come loose sent to the belly (motion.zig)
  pub const stowUnit=lib.player.motion.stowUnit;
  /// how deep the squat goes and how far it stretches up (motion.zig)
  pub const height=lib.player.motion.height;
  /// the node worked on, in its own frame (motion.zig)
  pub const workLocal=lib.player.motion.workLocal;
  /// every spring settled after the frame's motion (springs.zig)
  pub const springs=lib.player.springs.springs;
  /// what hangs in and on the body sloshing (springs.zig)
  pub const slosh=lib.player.springs.slosh;
  /// how far a belly lump may stray (springs.zig)
  pub const bellyRoom=lib.player.springs.bellyRoom;
  /// the skeleton's pose this frame (posing.zig)
  pub const pose=lib.player.posing.pose;
  /// the tail trailing behind its rest shape (posing.zig)
  pub const trailTail=lib.player.posing.trailTail;
  /// the belly-rest idle's arms (posing.zig)
  pub const restArms=lib.player.posing.restArms;
  /// the arms reached to the gathering wrists (posing.zig)
  pub const armsToWrists=lib.player.posing.armsToWrists;
  /// the legs reached to the feet (posing.zig)
  pub const legs=lib.player.posing.legs;
  /// how far the hips drop so the feet reach the ground (posing.zig)
  pub const hipDrop=lib.player.posing.hipDrop;
  /// where its eyes are in the world (posing.zig)
  pub const eyes=lib.player.posing.eyes;
  /// the posed, skinned wolf emitted into the scene (posing.zig)
  pub const rig=lib.player.posing.rig;
};
