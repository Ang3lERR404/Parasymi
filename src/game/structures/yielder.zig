//! YIELDER: the constellate lineage's first build, made in act 2 by the
//! star hyena's hands. A constellate core (a flower head of light, built of
//! ten fragments) put down stands alone, a web; each constellate petal fed
//! to it snaps on round its rim, bonded to it, until four stand there. Then
//! it is whole: its petals turn slowly round the core and, every few
//! seconds, spring shut, their tips gathering the air's energy into one
//! point over the core, let go as a mote of light and one new fragment,
//! and spring open again (the constellate web, `constellateYield`, all on
//! the GPU). The fragments it yields it keeps; a click takes one.
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
/// what can be held: petals in, fragments out
const items=lib.items;
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
/// the library meshes it draws: its web, by its own `emit`
pub const meshes=.{.constellateYield};
/// what a yielder is: one tile, of a lineage not yet named, drawn by its
/// own `emit` (its petals show as they snap on), still
pub const def:st.Def=.{.item=.constellateCore,.lineage=null,.size=1,.mesh=.constellateYield,.bare=true,.still=true};
/// how many petals make it whole (part.vert `PLEXUS_YIELD_PETALS`)
pub const petalsWhole:u8=4;
/// how often, whole, it yields a fragment (s; part.vert `PLEXUS_YIELD_CYCLE`)
pub const cycle:f32=6;
/// the most fragments it keeps before it waits for some to be taken
pub const keeps:u32=20;
/// what a yielder remembers: how many petals are snapped on, and how far
/// into its gathering it is
pub const State=struct{
  /// petals snapped on (0 .. `petalsWhole`)
  petals:u8=0,
  /// seconds into its gathering, whole
  since:f32=0,
  /// whether all its petals are on
  pub fn whole(q:State)bool{return q.petals>=petalsWhole;}
};
/// it takes petals until it is whole, nothing else
pub fn wants(s:*const st.Structure,_:*const prog.Progression,item:items.Item)u32{
  if(item!=.constellatePetal)return 0;
  return (petalsWhole-|s.state.yielder.petals)-|s.inv.count(.constellatePetal);
}
/// one step of a yielder `q` holding `inv` (of `n` slots) over `dt` s: the petals fed to
/// it snap on, and, whole, it yields a fragment every `cycle` s while it
/// keeps fewer than `keeps`. Returns whether it worked.
pub fn step(comptime n:usize,q:*State,inv:*items.Inventory(n),dt:f32)bool{
  // snapping on what it was fed
  var snapped=false;
  while(!q.whole() and inv.take(.constellatePetal,1)){
    q.petals+=1;
    snapped=true;
  }
  if(!q.whole())return snapped;
  q.since+=dt;
  if(q.since<cycle)return true;
  q.since-=cycle;
  if(inv.count(.fragment)<keeps)_=inv.add(.fragment,1);
  return true;
}
/// its petals snap on; whole, it gathers and yields
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the yielder
  const s=ctx.ss.get(i);
  return step(st.slots,&s.state.yielder,&s.inv,dt);
}
/// whole, a click takes one fragment it has yielded
pub fn handOver(s:*st.Structure)?items.Item{
  if(!s.state.yielder.whole() or !s.inv.take(.fragment,1))return null;
  return .fragment;
}
/// its web, as many petals showing as are snapped on, and the light it holds
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // how many of its petals are on (a share of the four)
  const on=m.f(s.state.yielder.petals)/m.f(petalsWhole);
  try out.emit(.constellateYield,s.place(ctr),.{.phase=s.seed,.grown=on});
  try out.light(ctr+m.v3(0,1.2,0),m.v3(0.5,0.75,1)*m.splat3(0.5+0.5*on+0.15*@sin(tf*1.1)),4);
}
/// its line in the panel: how many petals are on, or, whole, how many
/// fragments it holds
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // what it remembers
  const q=s.state.yielder;
  if(q.whole())_=try d.print(x,y,style.textBody,style.white,txt.s.describe.yielderWhole,.{s.inv.count(.fragment)})
  else _=try d.print(x,y,style.textBody,style.white,txt.s.describe.yielderPetals,.{q.petals});
}
/// its bulb: a bright core and four petals of light round it
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // the core's middle
  const mid:iconKit.P=.{0,0.5};
  try ic.glow(mid,0.4,iconGlow);
  for(0..petalsWhole)|k|try ic.leaf(mid,m.f(k)*m.halfPi+0.4+ic.t*0.2,0.3,0.1,iconPetal,1);
  try ic.bud(mid,0.09,iconCore,1);
  try ic.coat(col);
}
/// the icon's glow: deep blue, soft
const iconGlow:Color=.{60,110,255,80};
/// the icon's petals: pale sea-glass blue
const iconPetal:Color=.{150,210,255,220};
/// the icon's core: near white
const iconCore:Color=.{220,240,255,255};
test"a yielder takes four petals, then yields a fragment each cycle, keeping at most its fill"{
  // a yielder, and what it holds
  var q=State{};
  var inv=items.Inventory(4){};
  _=inv.add(.constellatePetal,3);
  _=step(4,&q,&inv,1);
  try testing.expect(!q.whole() and q.petals==3);
  // a fourth: whole, and yielding
  _=inv.add(.constellatePetal,1);
  _=step(4,&q,&inv,1);
  try testing.expect(q.whole());
  _=step(4,&q,&inv,cycle);
  try testing.expectEqual(@as(u32,1),inv.count(.fragment));
  // never past what it keeps
  for(0..100)|_|_=step(4,&q,&inv,cycle);
  try testing.expectEqual(keeps,inv.count(.fragment));
}
