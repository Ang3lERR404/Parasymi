//! play tested: turning, picking, opening, removing and putting down; the gamepad walking, stepping the hotbar and using.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the test helpers
const testing=std.testing;
/// the engine package
const engine=lib.engine;
/// all the maths: tiles, facings, projection
const m=engine.core.math;
/// the chunk layer: tile indices
const ck=lib.ck;
/// what can be held: item kinds
const items=lib.items;
/// the keys and buttons, set by hand here
const Input=engine.platform.input.Input;
/// the bindings: actions held and loaded
const ctl=lib.controls;
/// the test gardens' world seed
const defaultSeed=lib.play.defaultSeed;
/// the game under test
const Game=lib.play.game.Game;
/// what has the wolf's attention
const Mode=lib.play.Mode;
/// the screen size the tests draw for
const testScreen=lib.play.testsMenu.testScreen;
/// one simulation tick (s), each frame's step here
const tickTime=lib.play.tickTime;
/// headless: the mouse over the middle of tile `t`, as the camera sees it now
fn aim(g:*const Game,in:*Input,t:m.Vice(i32,2),sc:m.Vice(f32,2))void{
  // the tile's middle, projected to the screen (clip space)
  const q=m.mulV(g.cam.viewProj(),.{m.f(t[0])+0.5,g.heightAt(t[0],t[1]),m.f(t[1])+0.5,1});
  in.mouse=.{(q[0]/q[3]+1)/2*sc[0],(q[1]/q[3]+1)/2*sc[1]};
}
/// headless: one frame with `a` pressed (held down this frame only) over tile `t`
fn pressAt(g:*Game,in:*Input,t:m.Vice(i32,2),a:ctl.Action)!void{
  aim(g,in,t,testScreen);
  in.advance();
  ctl.hold(in,a,true);
  try g.update(in,tickTime,testScreen);
  in.advance();
  ctl.hold(in,a,false);
  try g.update(in,tickTime,testScreen);
}
test"R turns what is under the cursor (Shift back), Q picks its bulb, a click opens it, remove takes it up, held use puts one down"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,defaultSeed);
  defer g.deinit();
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  // the input, driven by hand (no window)
  var in:Input=.{.win=undefined};
  // the tile the wolf stands on
  const x,const z=m.tileAt(g.player.pos);
  for(0..4)|dx|{
    // the tile this many east of the wolf, its chunk and index
    const tx=x+1+@as(i32,@intCast(dx));
    const c=g.world.chunkOfTile(tx,z).?;
    const t=ck.localIndex(tx,z);
    c.kind[t]=.soil;
    c.res[t]=0;
    c.occ[t]=.none;
  }
  // the tile the sap cache stands on
  const at=m.Vice(i32,2){x+2,z};
  try testing.expect(try g.structs.place(gpa,&g.world,at[0],at[1],.sapCache,0,0));
  g.player.inv=.{};
  // R: a quarter clockwise, rooted, and not again until it has turned
  try pressAt(&g,&in,at,.rotate);
  // the cache just placed
  const id=g.structs.at(&g.world,at[0],at[1]).?;
  try testing.expectEqual(@as(m.Dir,1),g.structs.get(id).dir);
  try testing.expect(g.structs.get(id).turn.busy(g.time,true));
  try pressAt(&g,&in,at,.rotate);
  try testing.expectEqual(@as(m.Dir,1),g.structs.get(id).dir);
  // the next thing put down keeps its own facing
  try testing.expectEqual(@as(m.Dir,0),g.placeDir);
  // once turned, Shift+R turns it back
  g.time+=lib.turn.time;
  ctl.hold(&in,.counter,true);
  try pressAt(&g,&in,at,.rotate);
  ctl.hold(&in,.counter,false);
  try testing.expectEqual(@as(m.Dir,0),g.structs.get(id).dir);
  // Q: none in the belly, nothing to pick; with one, onto the hotbar
  try pressAt(&g,&in,at,.pick);
  try testing.expect(g.selected()==null);
  _=g.player.inv.add(.sapCache,1);
  g.hot=4;
  try pressAt(&g,&in,at,.pick);
  try testing.expectEqual(@as(?items.Item,.sapCache),g.selected());
  try testing.expectEqual(@as(usize,4),g.hot);
  // a click on it opens its panel, even with a bulb in hand
  try pressAt(&g,&in,at,.use);
  try testing.expectEqual(Mode.structure,g.mode);
  g.mode=.roam;
  // so does interact
  try pressAt(&g,&in,at,.interact);
  try testing.expectEqual(Mode.structure,g.mode);
  g.mode=.roam;
  // remove takes it up: its bulb comes back
  try pressAt(&g,&in,at,.remove);
  try testing.expect(g.structs.at(&g.world,at[0],at[1])==null);
  try testing.expectEqual(@as(u32,2),g.player.inv.count(.sapCache));
  // held, use puts the bulb in hand down where it fits, turned as R left it
  g.placeDir=3;
  aim(&g,&in,at,testScreen);
  in.advance();
  ctl.hold(&in,.use,true);
  for(0..3)|_|try g.update(&in,tickTime,testScreen);
  ctl.hold(&in,.use,false);
  // the cache put back down
  const put=g.structs.at(&g.world,at[0],at[1]) orelse return error.TestUnexpectedResult;
  try testing.expectEqual(@as(m.Dir,3),g.structs.get(put).dir);
  try testing.expectEqual(@as(u32,1),g.player.inv.count(.sapCache));
}
test"the left stick walks the wolf, the d-pad steps round the hotbar, the right trigger is use"{
  // the test allocator, which catches leaks
  const gpa=testing.allocator;
  // a fresh game on the test seed
  var g=try Game.init(gpa,defaultSeed);
  defer g.deinit();
  try ctl.fill(&.{@embedFile("controls.cfg")});
  defer ctl.unload();
  // the input, driven by hand (no window)
  var in:Input=.{.win=undefined};
  // where the wolf starts
  const from=g.player.pos;
  in.tilt(.left,.{0,1});
  for(0..30)|_|{
    in.advance();
    try g.update(&in,tickTime,testScreen);
  }
  in.tilt(.left,.{0,0});
  try testing.expect(m.dist(from,g.player.pos)>0.3);
  // from the first slot back round to the last, and on again to the first
  g.hot=0;
  in.advance();
  in.hold(.{.pad=.dpad_left},true);
  try g.update(&in,tickTime,testScreen);
  try testing.expectEqual(ctl.slots.len-1,g.hot);
  in.advance();
  in.hold(.{.pad=.dpad_left},false);
  in.hold(.{.pad=.dpad_right},true);
  try g.update(&in,tickTime,testScreen);
  try testing.expectEqual(@as(usize,0),g.hot);
  in.hold(.{.pad=.dpad_right},false);
  // the right trigger pulled is use held
  in.hold(.{.trigger=.right_trigger},true);
  try testing.expect(ctl.down(&in,.use));
}
