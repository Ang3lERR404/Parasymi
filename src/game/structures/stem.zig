//! CONSTELLATE STEM: a stem of light (rings wound up its length, a joint every third ring) the star hyena builds of fragments and puts
//! down on its own (act 2). It floats over its tile, bobbing, a web
//! holding its shape (game/structures/constellate_part.zig), until a combo
//! takes it in. It is what others fasten to: three joints up its length
//! (every third ring), leaves drifting over to its lowest and highest and
//! a bare stem put down after it to its middle as its branch (a sprig,
//! `constellateSprig`, showing only what is fastened); and, bare itself,
//! it drifts as a branch to a stem put down before it. Bare, it takes buds
//! instead: four drift over to its joints (two at its highest) and it
//! becomes the heart (game/structures/heart.zig).
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the test harness: expectations
const testing=std.testing;
/// the allocator the drawing calls may fail with
const Allocator=std.mem.Allocator;
/// all the maths: angles
const m=lib.engine.core.math;
/// the structures registry: `Def`, `Structure`
const st=lib.structures;
/// what the gardener has understood
const prog=lib.progression;
/// what every constellate part put down shares
const part=lib.constellatePart;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// the scene's list of moving parts it draws itself into
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the hover text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the library meshes it draws: its web, by its own `emit` (a sprig, or a
/// stem gathering buds as a garden's heart begins)
pub const meshes=.{.constellateStem,.constellateSprig,.constellateHeartDriven};
/// what a stem put down is: one tile, drawn by its own `emit`, still
pub const def:st.Def=.{.item=.constellateStem,.lineage=null,.size=1,.mesh=.constellateStem,.bare=true,.still=true};
/// how many buds on it begin the heart
pub const budsWhole:u8=4;
/// which joint each bud fastens at, in turn (two at its highest, either side)
const budJoints=[budsWhole]u8{0,1,2,2};
/// what a stem put down remembers: what is fastened at its joints (one
/// bit each: lowest, middle, highest), the buds on it, and, bare, its own
/// drift as a branch
pub const State=struct{
  /// what is fastened at its joints (bit 0 lowest, 1 middle, 2 highest)
  joints:u8=0,
  /// how many buds are fastened on it (a sprig's leaves and branch never
  /// share a stem with buds)
  buds:u8=0,
  /// its drift over to another stem's middle joint, as its branch
  drift:part.Drift=.{},
};
/// the joint free for `what` on a stem holding `joints` and `buds`, if
/// any: a leaf its lowest, else its highest, and a branch its middle, on a
/// stem with no buds; a bud the next of `budJoints`, on one with nothing
/// else
pub fn freeJoint(joints:u8,buds:u8,what:st.Fasten)?u8{
  // whether joint `j` is free
  const free=struct{
    /// whether bit `j` of `js` is clear
    fn f(js:u8,j:u3)bool{return js&(@as(u8,1)<<j)==0;}
  }.f;
  return switch(what){
    .leaf=>if(buds>0)null else if(free(joints,0))0 else if(free(joints,2))2 else null,
    .branch=>if(buds==0 and free(joints,1))1 else null,
    .bud=>if(joints==0 and buds<budsWhole)budJoints[buds]else null,
  };
}
/// bare, it drifts as a branch to a stem put down before it within reach
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // what it remembers
  const q=&ctx.ss.get(i).state.stem;
  if(q.joints!=0 or q.buds!=0)return false;
  return part.fasten(ctx,i,&q.drift,.branch,dt);
}
/// a part nearby may drift over to a free joint, and one drifted over
/// fastens there; never while it drifts away itself as a branch. Its last
/// bud fastened, it becomes the heart.
pub fn message(ctx:st.Ctx,i:st.Id,msg:st.Msg)st.Reply{
  // what it remembers
  const q=&ctx.ss.get(i).state.stem;
  if(q.drift.to!=null)return.ignored;
  switch(msg){
    .fastenComing=>|w|return if(freeJoint(q.joints,q.buds,w))|j|.{.joint=j}else.ignored,
    .fastened=>|w|{
      const j=freeJoint(q.joints,q.buds,w) orelse return.ignored;
      if(w==.bud)q.buds+=1 else q.joints|=@as(u8,1)<<@intCast(j);
      if(q.buds==budsWhole)ctx.ss.become(ctx.gpa,i,.heart);
      return.{.joint=j};
    },
    .lit,.unform,.graft,.arrived,.petalComing,.petalSnapped=>return.ignored,
  }
}
/// it, floating over its tile as a sprig showing what is fastened at its
/// joints, or as the heart's stem showing the buds fastened on it, or
/// drifting over to another stem as its branch
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // what it remembers, and where it floats
  const q=s.state.stem;
  if(q.drift.to!=null)return part.driftTo(s,out,ctr,tf,.constellateStem,q.drift);
  const at=m.chain(&.{m.translate(part.floatAt(s,ctr,tf)),m.rotY(s.seed*m.tau)});
  if(q.buds>0)return out.emit(.constellateHeartDriven,at,.{.phase=s.seed,.grown=0,.carry=0,.give=.{0,m.f(q.buds),0}});
  try out.emit(.constellateSprig,at,.{.phase=s.seed,.grown=m.f(q.joints)/7});
}
test"a stem's joints: leaves at its lowest then highest, a branch at its middle, buds only on a bare one"{
  try testing.expectEqual(@as(?u8,0),freeJoint(0,0,.leaf));
  try testing.expectEqual(@as(?u8,2),freeJoint(0b001,0,.leaf));
  try testing.expectEqual(@as(?u8,null),freeJoint(0b101,0,.leaf));
  try testing.expectEqual(@as(?u8,1),freeJoint(0b101,0,.branch));
  try testing.expectEqual(@as(?u8,null),freeJoint(0b111,0,.branch));
  try testing.expectEqual(@as(?u8,null),freeJoint(0b001,0,.bud));
  try testing.expectEqual(@as(?u8,2),freeJoint(0,3,.bud));
  try testing.expectEqual(@as(?u8,null),freeJoint(0,1,.leaf));
}
/// its line in the panel: floating, waiting to be joined
pub fn describe(_:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  try part.describe(d,x,y);
}
/// its bulb: one stem of light standing, glowing
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  try ic.glow(.{0,0.5},0.35,part.iconGlow);
  try ic.stem(.{.{0,iconKit.topAt},.{0.04,0.35},.{-0.03,0.65},.{0.01,0.9}},0.05,part.iconLight);
  try ic.coat(col);
}
test"two leaves and a later stem put down near a stem fasten at its joints: a whole sprig"{
  // a fresh game, its world streamed in round the gardener
  const gpa=testing.allocator;
  var g=try lib.play.Game.init(gpa,testing.io,lib.play.defaultSeed);
  defer g.deinit();
  try g.world.stream(g.focus(),2,1000);
  // the host stem first, then two leaves and a branch stem near it
  const c=m.tileAt(g.player.pos);
  try testing.expect(try g.structs.place(gpa,&g.world,c[0]+3,c[1],.stem,0,0.1));
  try testing.expect(try g.structs.place(gpa,&g.world,c[0]+5,c[1],.leaf,0,0.2));
  try testing.expect(try g.structs.place(gpa,&g.world,c[0]+3,c[1]+2,.leaf,0,0.3));
  try testing.expect(try g.structs.place(gpa,&g.world,c[0]+1,c[1],.stem,0,0.4));
  // the seconds run
  var t:f32=0;
  while(t<part.drifting+1):(t+=lib.play.tickTime)try g.step();
  // one stem left, all three joints held
  try testing.expectEqual(@as(usize,1),g.structs.list.items.len);
  try testing.expectEqual(@as(u8,0b111),g.structs.list.items[0].state.stem.joints);
}
