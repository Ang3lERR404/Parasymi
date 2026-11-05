//! STARLIGHT CATCHER: the symbiotic lineage's rooted catcher, the garden's
//! first starlight. Woven by hand from cheap matter (fibre and grit, never
//! starlight), it is put down on or beside a starlit patch and, by night,
//! gathers what light the patch holds into starlight, slowly: far less well
//! than a halyriphon floating over the patch, so the radiant one is worth
//! reaching for. It keeps what it gathers; a click takes one. Pseudo-rooted
//! on its little legs, its body lifted by a hint of magic and bobbing softly
//! (`Def.bob`); by night, over a shining patch, beads of gathered light glow
//! in its lens and run down its vine. Once the unforming has darkened the
//! patches it gathers nothing.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the drawing calls may fail with
const Allocator=std.mem.Allocator;
/// the test harness: expectations
const testing=std.testing;
/// all the maths: vectors, conversions
const m=lib.engine.core.math;
/// the structures registry: `Def`, `Structure`, the hooks' context
const st=lib.structures;
/// what can be held: the starlight it gathers
const items=lib.items;
/// the chunk layer: each tile's starlit patch
const ck=lib.ck;
/// the world its tiles lie in
const World=lib.world.World;
/// every player-facing string
const txt=lib.txt;
/// what the gardener has understood
const prog=lib.progression;
/// the HUD's shared sizes and colours
const style=lib.style;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// the scene's list of moving parts it draws itself into
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the hover text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// its mesh's beads of light, where they hang
const look=lib.starlightCatcher;
/// the library meshes it draws by itself: its beads of gathered light
pub const meshes=.{.catcherBead};
/// what a catcher is: one tile of the symbiotic lineage, grown in 30 s,
/// swaying a little, its body lifted and bobbing on a hint of magic
pub const def:st.Def=.{.item=.starCatcher,.lineage=.symbiotic,.size=1,.mesh=.starCatcher,.grow=30,.sway=0.5,.tall=1.2,.bob=look.bob};
/// how long it takes to gather one starlight (s) at full night over a
/// patch of plain yield (1): a richer patch quickens it, a poorer slows it
pub const cycle:f32=40;
/// how far round its tile it reaches for a patch's light (tiles)
pub const reach:i32=1;
/// the most starlight it keeps before it waits for some to be taken
pub const keeps:u32=20;
/// what a catcher remembers: how far into gathering its next starlight it is
pub const State=struct{
  /// how much of its next starlight is gathered (0..1)
  gathered:f32=0,
};
/// the yield of the richest patch tile within `reach` of tile (x, y) (0: none near)
pub fn patchNear(w:*const World,x:i32,y:i32)f32{
  // the richest so far
  var best:f32=0;
  var dy:i32=-reach;
  while(dy<=reach):(dy+=1){
    var dx:i32=-reach;
    while(dx<=reach):(dx+=1){
      // the tile's chunk, if streamed in
      const c=w.chunkOfTile(x+dx,y+dy) orelse continue;
      best=@max(best,c.starYield[ck.localIndex(x+dx,y+dy)]);
    }
  }
  return best;
}
/// one step of a catcher `q` holding `inv` (of `n` slots) over `dt` s, a
/// patch of `yield` near it, `night` deep (0 day .. 1 night): it gathers
/// while it keeps fewer than `keeps`. Returns whether it worked.
pub fn step(comptime n:usize,q:*State,inv:*items.Inventory(n),yield:f32,night:f32,dt:f32)bool{
  if(yield<=0 or night<=0 or inv.count(.starlight)>=keeps)return false;
  q.gathered+=dt/cycle*yield*night;
  while(q.gathered>=1 and inv.count(.starlight)<keeps){
    q.gathered-=1;
    _=inv.add(.starlight,1);
  }
  q.gathered=@min(q.gathered,1);
  return true;
}
/// by night, beside a shining patch, it gathers starlight
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the catcher, the sky over it and how deep the night is
  const s=ctx.ss.get(i);
  const sky=ctx.sky orelse return false;
  if(sky.shift>0)return false;
  return step(st.slots,&s.state.starCatcher,&s.inv,patchNear(ctx.w,s.x,s.y),1-sky.daylight(),dt);
}
/// what a conduit's root may draw out of it: a starlight it has gathered
pub fn output(s:*const st.Structure)?items.Item{return if(s.inv.count(.starlight)>0).starlight else null;}
/// a click takes one starlight it has gathered
pub fn handOver(s:*st.Structure)?items.Item{
  if(!s.inv.take(.starlight,1))return null;
  return .starlight;
}
/// by night, gathering, its beads of light glow in its lens and down its vine
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // how much it glows: only while it gathers, by its activity
  const on=s.activity*s.grown;
  if(on<=0)return;
  // its kind, and where it hangs now, bobbing
  const d=s.def();
  const at=ctr+m.v3(0,st.bobAt(d,s.seed,tf),0);
  for(look.blend.glows)|gl|{
    if(gl.when!=.night)continue;
    // each bead rides the vine's sway at its own height up it (rooted
    // where the catcher is), so the fruit moves with the stem it hangs on
    try out.emit(.catcherBead,m.chain(&.{m.translate(at+gl.at),m.scale3(m.splat3(gl.scale))}),.{.phase=s.seed,.glow=gl.glow*on,.sway=d.sway,.tall=d.tall,.drop=at[1]+gl.at[1]-ctr[1]});
    try out.light(at+gl.at,gl.light*m.splat3(on),gl.reach);
  }
}
/// its line in the panel: how much starlight it holds
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.starCatcher,.{s.inv.count(.starlight)});
}
/// its bulb: a slender stalk, a bowl turned to the sky, a bead of light in it
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // the bowl's middle
  const mid:iconKit.P=.{0,0.62};
  try ic.glow(mid,0.3,iconGlow);
  for(0..5)|k|try ic.leaf(mid,m.pi+m.f(k)*m.pi/4+ic.t*0.1,0.3,0.08,iconBowl,1);
  try ic.leaf(.{0,0.1},m.halfPi*3,0.5,0.03,iconStalk,1);
  try ic.bud(mid,0.07,iconBead,1);
  try ic.coat(col);
}
/// the icon's glow: soft star-blue
const iconGlow:Color=.{90,140,255,70};
/// the icon's bowl: sage turning star-blue
const iconBowl:Color=.{150,180,210,230};
/// the icon's stalk: green
const iconStalk:Color=.{90,150,90,255};
/// the icon's bead: pale star-blue
const iconBead:Color=.{190,215,255,255};
test"a catcher gathers only by night beside a patch, richer faster, keeping at most its fill"{
  // a catcher and what it holds
  var q=State{};
  var inv=items.Inventory(4){};
  // by day, or with no patch near, nothing
  try testing.expect(!step(4,&q,&inv,1,0,cycle*3));
  try testing.expect(!step(4,&q,&inv,0,1,cycle*3));
  try testing.expectEqual(@as(u32,0),inv.count(.starlight));
  // a night over a plain patch: one each cycle; a rich one, three
  _=step(4,&q,&inv,1,1,cycle);
  try testing.expectEqual(@as(u32,1),inv.count(.starlight));
  _=step(4,&q,&inv,3,1,cycle);
  try testing.expectEqual(@as(u32,4),inv.count(.starlight));
  // never past what it keeps
  for(0..100)|_|_=step(4,&q,&inv,3,1,cycle);
  try testing.expectEqual(keeps,inv.count(.starlight));
}
test"a fresh garden's first starlight: a catcher put down at a patch gathers it by night"{
  // a fresh game at midnight, and the nearest starlit patch to it
  const gpa=testing.allocator;
  var g=try lib.play.Game.init(gpa,testing.io,lib.play.defaultSeed);
  defer g.deinit();
  g.sky.tod=0;
  const nr=lib.starlit.Near.of(g.world.seed,-120,-120,120,120);
  try testing.expect(nr.n>0);
  const p=nr.list[0];
  const x=m.tileOf(p.at[0]);
  const y=m.tileOf(p.at[1]);
  // the ground there streamed in, and a catcher put down grown on the patch
  try g.world.stream(lib.ck.Coord.ofTile(x,y),1,1000);
  try testing.expect(try g.structs.place(gpa,&g.world,x,y,.starCatcher,0,0.1));
  const s=&g.structs.list.items[g.structs.list.items.len-1];
  s.grown=1;
  // two cycles of the night
  var t:f32=0;
  while(t<cycle*2/yieldPoorest):(t+=lib.play.tickTime)try g.step();
  try testing.expect(s.inv.count(.starlight)>0);
}
/// the poorest patch's yield, for how long a test waits at the least
const yieldPoorest=lib.starlit.yieldPoor;
