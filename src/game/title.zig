//! the main menu's stage: the wolf curled up asleep in a small patch of
//! flowers, centre stage on a dark ground under one warm light, petals,
//! motes, small flowers and seeds drifting down out of the dark above
//! him. No sky, ground or air is drawn round it (`Scene.stage`): the dark
//! is the backdrop. The menu itself is the HUD's (hud/title.zig), down the
//! right; the stage sits left of the middle. Drawn while the main menu, or
//! a panel opened from it, is open (`Game.atTitle`).
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type drawing may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, matrices, angles
const m=engine.core.math;
/// keyframed clips: the wolf's sleep
const clip=engine.anim.clip;
/// the wolf's skeleton and its pose
const skel=lib.skeleton;
/// every channel of the wolf's pose, by name, as a clip keys them
const PoseCh=clip.Channels(skel.Pose);
/// every plant kind
const species=lib.species;
/// the mound the wolf sleeps on, for how high its surface is under a plant
const mound=lib.stageMeshes.mound;
/// the garden's renderer: its scene
const renderer=lib.renderer;
/// what gets drawn: a plant on the stage, the lights ranked
const view=lib.view;
/// the HUD, built into the scene each frame
const hud=lib.hud;
/// the game whose menu this is
const Game=lib.play.Game;
/// the wolf's sleep, keyed in animedit (src/anim/sleep.anim)
const sleepText=@embedFile("sleep.anim");
/// shader time wraps this often (s) so f32 keeps its precision
const timeWrap:f64=3600;
/// the dark the stage sits in (linear): as black as the mound's far rim,
/// so no horizon is ever seen
const dark=m.v3(0.0015,0.0013,0.002);
/// how the camera looks at the stage: from this far, this steeply
/// (radians), turned this far round (radians)
const camDist:f32=3.9;
/// how steeply the camera looks down at the stage (radians)
const camPitch:f32=0.82;
/// how far round the stage the camera is turned (radians)
const camYaw:f32=0.35;
/// how far right of the wolf the camera aims (metres), so he lies left of
/// the middle and the menu has the right
const camAside:f32=0.8;
/// how high over the stage the camera aims (metres)
const camUp:f32=0.15;
/// the way the wolf faces on the stage (radians)
const wolfYaw:f32=-0.5;
/// the warm light over him: where (from the stage), its colour times its
/// strength, how far it reaches
const keyAt=m.v3(0.15,1.6,0.45);
/// the warm light's colour times its strength (linear)
const keyCol=m.v3(4.2,3.0,1.7);
/// how far the warm light reaches (metres)
const keyReach:f32=4.2;
/// a cool light behind him, rimming his back
const rimAt=m.v3(-1.1,0.9,-1.2);
/// the cool light's colour times its strength (linear)
const rimCol=m.v3(0.35,0.45,1.1);
/// how far the cool light reaches (metres)
const rimReach:f32=3.2;
/// the way toward the key light the stage is shaded by: a moon low behind
/// it, rimming the wolf and the patch rather than flooding the mound
const moon=m.v3(-0.35,0.45,-1);
/// how much daylight the stage is shaded with: night
const daylight:f32=0.0;
/// how far the stage is drawn round the camera's aim (tiles)
const reach:f32=12;
/// the patch round him: each plant's kind, where (from the stage), its own
/// seed. Moss under and round him, the evening star's flowers and the
/// first symbiote's in a ring past it
const Planted=struct{
  /// its kind
  sp:species.Id,
  /// where it stands, from the stage's middle (x, z metres)
  at:m.Vice(f32,2),
  /// its own seed, 0..1
  seed:f32,
};
/// the patch round the sleeping wolf
const patch=[_]Planted{
  .{.sp=.mossCreeper,.at=.{0,0},.seed=0.11},
  .{.sp=.mossCreeper,.at=.{-0.75,0.2},.seed=0.37},
  .{.sp=.mossCreeper,.at=.{0.7,-0.25},.seed=0.73},
  .{.sp=.mossCreeper,.at=.{0.1,0.8},.seed=0.29},
  .{.sp=.vesper,.at=.{-1.55,-0.75},.seed=0.21},
  .{.sp=.vesper,.at=.{1.45,-0.95},.seed=0.58},
  .{.sp=.vesper,.at=.{-0.2,-1.75},.seed=0.84},
  .{.sp=.lumenroot,.at=.{1.05,-1.65},.seed=0.46},
  .{.sp=.lumenroot,.at=.{-1.8,0.35},.seed=0.67},
  .{.sp=.lumenroot,.at=.{0.75,-1.6},.seed=0.92},
};
/// one kind of what drifts down over the stage: its mesh, how many, how
/// big (a scale on its true size), how brightly it glows
const Drift=struct{
  /// its mesh
  id:lib.meshlib.Id,
  /// how many drift down at once
  n:usize,
  /// its scale on its true size
  size:f32=1,
  /// how brightly it glows, 0..1
  glow:f32=0,
};
/// what drifts down over the sleeping wolf: petals, whole small flowers,
/// seeds on their fluff, glowing pollen
const drifts=[_]Drift{
  .{.id=.fallPetal,.n=56,.glow=0.08},
  .{.id=.fallFlower,.n=12,.size=1.2,.glow=0.12},
  .{.id=.fallSeed,.n=16,.glow=0.04},
  .{.id=.fallPollen,.n=44,.glow=1},
};
/// the most of one kind, so every piece's seed is its own
const drifted=64;
/// how high over the stage what drifts down falls from (metres)
const fallHigh:f32=3.4;
/// how far across the stage it spreads (metres either side)
const fallSpread:f32=2.4;
/// the scene for the main menu: the stage lit in the dark, the menu over it
pub fn scene(g:*Game,screen:m.Vice(f32,2))Allocator.Error!renderer.Scene{
  // the stage's middle (on the ground plane the stage hides), and the clock
  const at=m.v3(g.player.pos[0],0,g.player.pos[2]);
  const tf:f32=@floatCast(@mod(g.uiTime,timeWrap));
  // the stage's own camera (the gardener's is left as it is, to wake into
  // the garden with)
  var cam=g.cam;
  cam.view=.follow;
  cam.yaw=camYaw;
  cam.pitch=camPitch;
  cam.dist=camDist;
  cam.target=at+m.v3(@cos(camYaw)*camAside,camUp,-@sin(camYaw)*camAside);
  // gathered afresh: the patch, the sleeping wolf, the lights
  g.parts.clear();
  g.parts.look(cam.viewEye(),m.Frustum.of(cam.viewProj()),m.norm(moon));
  for(&g.inst)|*l|l.clearRetainingCapacity();
  try g.parts.emit(.stageMound,m.translate(at),.{});
  // each plant stands on the mound where it is
  for(patch)|p|try view.stagePlant(g,p.sp,at+m.v3(p.at[0],mound.height(m.len(m.v3(p.at[0],0,p.at[1])),m.atan2(p.at[1],p.at[0])),p.at[1]),1,p.seed,tf);
  // what drifts down out of the dark over him, each kind its own count,
  // size and glow, each piece its own seed
  for(drifts,0..)|d,k|for(0..d.n)|i|{
    try g.parts.emitFall(d.id,at,m.f(k*drifted+i)*m.goldenShare+m.f(k)*0.37,fallHigh,fallSpread,d.size,.{.glow=d.glow,.phase=m.ratio(i,d.n)});
  };
  // the wolf, posed by its sleep where it lies (a copy: the gardener's own
  // is left as it is, to wake into the garden)
  var sleeper=g.player;
  sleeper.pos=at;
  sleeper.facing=wolfYaw;
  sleeper.posed=try sleeping(g,tf);
  const feet=try sleeper.rig(&g.parts,false);
  try g.parts.light(at+keyAt,keyCol,keyReach);
  try g.parts.light(at+rimAt,rimCol,rimReach);
  view.rankLights(g);
  try hud.build(g,screen);
  // the eye, and the way toward the key light
  const eye=cam.viewEye();
  const ld=m.norm(moon);
  var out:renderer.Scene=.{
    .push=.{
      .vp=cam.viewProj(),
      .eyeTime=.{eye[0],eye[1],eye[2],tf},
      .fog=.{dark[0],dark[1],dark[2],0},
      .misc=.{0,0,1e9,1e9},
      .sun=.{ld[0],ld[1],ld[2],daylight},
      .view=.{cam.target[0],cam.target[2],reach,reach},
      .feet=.{
        .{feet[0][0],feet[0][1],feet[0][2],wolfYaw},
        .{feet[1][0],feet[1][1],feet[1][2],0},
      },
    },
    .clear=dark,
    .instances=undefined,
    .parts=g.parts.slices(),
    .bones=g.parts.bones.items,
    .lights=g.parts.lights.items,
    .ui=g.ui.v.items,
    .uiTime=tf,
    .stage=true,
  };
  for(&out.instances,g.inst)|*o,l|o.*=l.items;
  return out;
}
/// the wolf's pose `t` seconds into its sleep, looping (read from its
/// clip the first time)
fn sleeping(g:*Game,t:f32)Allocator.Error!skel.Pose{
  if(g.sleep==null)g.sleep=clip.Clip.parse(g.gpa,sleepText)catch|e|switch(e){
    error.OutOfMemory=>return error.OutOfMemory,
    // (the clip ships inside the game and a test reads it: never bad)
    else=>unreachable,
  };
  // the clip, and how far into its loop
  const c=&g.sleep.?;
  const k=@mod(t,@max(c.length,1e-3));
  // the pose, every keyed channel set from the clip
  var q=skel.Pose{};
  for(PoseCh.names,0..)|n,i|if(c.sample(n,k))|v|PoseCh.set(&q,i,v);
  return q;
}
test"the sleep reads and poses the wolf"{
  // the clip, read as the menu reads it
  var c=try clip.Clip.parse(std.testing.allocator,sleepText);
  defer c.deinit();
  try std.testing.expectEqualStrings("wolf",c.subject);
  // every channel it keys is one of the pose's
  for(c.tracks.items)|tr|try std.testing.expect(PoseCh.find(tr.name)!=null);
}
