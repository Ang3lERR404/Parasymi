//! the garden's two acts. In the first the gardener is the wolf; in the
//! second (once the wolf roots himself into the garden's tree, not yet in
//! the game: `--act2` begins there) it is the star hyena, a living
//! constellation who never walks but hovers over the ground, with only the
//! convergent lineage and the constellate one to work with. Which act a
//! garden is in says who the gardener is: the body drawn where the player
//! stands, the eyes the camera looks out of, whether its steps sound, and
//! what putting the strange seed down does (in the hyena's act alone it is
//! planted).
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the drawing calls may fail with
const Allocator=std.mem.Allocator;
/// the test harness: expectations
const testing=std.testing;
/// all the maths: vectors, matrices, turns
const m=lib.engine.core.math;
/// the gardener's place, heading and motion
const Player=lib.player.Player;
/// the scene's list of moving parts he goes into
const Parts=lib.parts.Parts;
/// the library meshes, his among them
const meshlib=lib.meshlib;
/// his mesh's home: his limbs, bones and pose
const hyena=lib.constellate;
/// which act a garden is in
pub const Act=enum(u8){
  /// the wolf's: from the garden's start, through the unforming
  wolf,
  /// the star hyena's, after the wolf roots: convergent and constellate alone
  hyena,
  /// the act a saved byte names (none: a corrupt save)
  pub fn of(b:u8)?Act{return std.enums.fromInt(Act,b);}
};
/// where his bones turn as he leans into his motion: about his hips
const leanAbout=m.v3(0,1,0);
/// how far he leans forward for each unit of speed (rad per m/s), and the most
const leanPer:f32=0.06;
/// the most he leans forward (rad)
const leanMost:f32=0.25;
/// where his eyes are in his bind pose, on his head's bone
const eyesAt=m.v3(0,1.79,0.13);
/// his head's bone, which his eyes ride
const headBone=3;
/// the bones not drawn when seen from his own eyes: his head, muzzle, ears
/// and mane (one bit each), though they still cast their shadows
const headBones:u64=0b1111_1000;
/// where his body's middle is above where he stands (culling and detail)
const bodyMid:f32=1.1;
/// his bones now, placed where the player stands and turned the way it
/// faces, leaning forward into its motion
fn bones(p:*const Player,t:f32,out:[]m.M4)usize{
  // how fast he moves over the ground, and so how far he leans
  const speed=m.len(m.v3(p.vel[0],0,p.vel[2]));
  const lean=@min(speed*leanPer,leanMost);
  const at=m.chain(&.{p.heading(),m.translate(leanAbout),m.rotX(lean),m.translate(-leanAbout)});
  return hyena.hyenaPose(t,at,out);
}
/// draw the star hyena where the player stands, `t` the game's clock (s).
/// Seen from his own eyes (`headless`) his head is not drawn.
pub fn draw(p:*const Player,out:*Parts,t:f32,headless:bool)Allocator.Error!void{
  // his bones now, and where they go in this frame's list
  var b:[meshlib.maxPoseBones]m.M4=undefined;
  const n=bones(p,t,&b);
  const base=try out.pose(b[0..n]);
  try out.emitSkinned(.constellateHyena,base,p.pos+m.v3(0,bodyMid,0),.{.phase=0.3,.hide=if(headless)headBones else 0});
}
/// where the eyes of act `a`'s gardener are this frame
pub fn eyes(a:Act,p:*const Player,t:f32)m.V3{
  return switch(a){
    .wolf=>p.eyes(),
    .hyena=>blk:{
      // his bones now
      var b:[meshlib.maxPoseBones]m.M4=undefined;
      _=bones(p,t,&b);
      break:blk m.mulPoint(b[headBone],eyesAt);
    },
  };
}
/// how long the unforming may take to run through before act 2 (s)
const unformingMost:f32=600;
/// begin the hyena's act, which comes only after the unforming: the event
/// run through to its end (the radiant plants shattered, the lineages
/// gone, the ley sealed, the seed fallen), then the seed it let fall taken
/// up into his keeping (`--act2`, until the wolf's rooting begins it in
/// play)
pub fn begin(g:*lib.play.Game)lib.play.Error!void{
  try g.world.stream(g.focus(),2,1000);
  g.prog.done.insert(.unforming);
  // the structures standing before it: the seed it lets fall comes after
  const before=g.structs.list.items.len;
  // the seconds run
  var t:f32=0;
  while(!(g.unforming.phase==.landed and g.unforming.sealed) and t<unformingMost):(t+=lib.play.tickTime)try g.step();
  g.act=.hyena;
  // the seed it let fall, taken up
  for(g.structs.list.items[@min(before,g.structs.list.items.len)..],before..)|s,i|if(s.kind()==.strangeSeed){
    var gone=g.structs.remove(&g.world,.of(i));
    gone.deinit(g.gpa);
    break;
  };
  _=g.player.inv.add(.strangeSeed,1);
  g.bar[0]=.strangeSeed;
}
/// whether act `a`'s gardener's steps sound (the hyena hovers)
pub fn steps(a:Act)bool{return a==.wolf;}
test"the hyena's eyes are at his head's height over where he stands, and an act survives a byte"{
  // a player standing at the origin, still
  const p=Player{.pos=m.v3(0,0,0)};
  const e=eyes(.hyena,&p,0);
  try testing.expect(e[1]>1.7 and e[1]<1.9);
  try testing.expectEqual(Act.hyena,Act.of(@intFromEnum(Act.hyena)).?);
  try testing.expectEqual(@as(?Act,null),Act.of(9));
  try testing.expect(!steps(.hyena) and steps(.wolf));
}
