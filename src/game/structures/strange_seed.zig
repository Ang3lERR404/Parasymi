//! STRANGE SEED: the seed the unforming gathered out of the shattered
//! radiant light and let fall, the constellate lineage's first. It lies
//! where it landed and never plants itself; the wolf may pick it up and put
//! it down again, nothing more. In the star hyena's act, put down by his
//! hand, it is planted: it conjures loose constellate fragments out of
//! itself one at a time, each rising slowly out of it to drift loose round
//! and over it, lines and panes forming between those that come near (the
//! constellate web, `strangeSeedWeb`, placed on the GPU), until `most`
//! drift there.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator the drawing calls may fail with
const Allocator=std.mem.Allocator;
/// the test harness: expectations
const testing=std.testing;
/// all the maths: vectors, angles
const m=lib.engine.core.math;
/// the structures registry: `Def`, `Structure`
const st=lib.structures;
/// every player-facing string
const txt=lib.txt;
/// what the gardener has understood
const prog=lib.progression;
/// the HUD's shared sizes and colours
const style=lib.style;
/// which act the garden is in: who put it down
const Act=lib.act.Act;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// the scene's list of moving parts its light goes into
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the hover text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the library meshes it draws beyond its own: the web of its fragments
pub const meshes=.{.strangeSeedWeb};
/// what it is: lying on one tile, there at once, still
pub const def:st.Def=.{.item=.strangeSeed,.lineage=null,.size=1,.mesh=.strangeSeed,.still=true};
/// the most loose fragments it conjures (the web's points, part.vert
/// `PLEXUS_POINTS`)
pub const most:f32=30;
/// how long it takes to conjure one (s): all of them in ten minutes
pub const every:f32=20;
/// what a strange seed remembers: whether it is planted, and how many
/// fragments it has conjured
pub const State=struct{
  /// planted by the star hyena's hand (else it only lies there)
  planted:bool=false,
  /// how many loose fragments it has conjured (0 .. `most`; the one
  /// rising now in part)
  fragments:f32=0,
};
/// put down by the gardener's hand in act `a`: planted in the hyena's,
/// beginning again from no fragments; in the wolf's it only lies there
pub fn sown(s:*st.Structure,a:Act)void{
  s.state.strangeSeed=.{.planted=a==.hyena};
}
/// how many fragments it has after `dt` s, having `had`: planted, one more
/// every `every` s up to `most`; else none come
pub fn conjure(had:f32,planted:bool,dt:f32)f32{
  if(!planted)return had;
  return @min(had+dt/every,most);
}
/// planted, it conjures its fragments; busy while it does
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // what it remembers, and how many it had
  const s=&ctx.ss.get(i).state.strangeSeed;
  const had=s.fragments;
  s.fragments=conjure(had,s.planted,dt);
  return s.fragments>had;
}
/// the soft light it holds, pulsing slowly, and, planted, the web of the
/// fragments it has conjured, each rising out of it in turn
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  try out.light(ctr+m.v3(0,0.1,0),m.v3(0.85,0.8,1)*m.splat3(0.6+0.2*@sin(tf*0.8)),3);
  // what it remembers
  const q=s.state.strangeSeed;
  if(!q.planted or q.fragments<=0)return;
  try out.emit(.strangeSeedWeb,s.place(ctr),.{.phase=s.seed,.grown=q.fragments/most});
}
/// its line in the panel: planted, how many fragments it has conjured;
/// else that it lies where it fell
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // what it remembers
  const q=s.state.strangeSeed;
  if(q.planted)_=try d.print(x,y,style.textBody,style.white,txt.s.describe.seedFragments,.{m.floorTo(u32,q.fragments),m.floorTo(u32,most)})
  else _=try d.print(x,y,style.textBody,style.white,txt.s.describe.seedLies,.{});
}
/// its icon: the cut seed, faceted, glowing from inside
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  try ic.glow(.{0,0.5},0.35,iconGlow);
  try ic.gem(.{0,0.5},0.28,iconGem);
  try ic.coat(col);
}
/// the near-white of the cut seed
const iconGem:Color=.{235,235,255,255};
/// the violet glow inside it
const iconGlow:Color=.{180,150,255,90};
test"a strange seed conjures fragments only once the hyena plants it, up to the most"{
  // lying where it fell: none come
  try testing.expectEqual(@as(f32,0),conjure(0,false,1000));
  // planted: one every `every` s
  try testing.expectApproxEqAbs(@as(f32,1),conjure(0,true,every),1e-4);
  // never past the most
  try testing.expectEqual(most,conjure(most-0.5,true,1000));
  // put down in the wolf's act it only lies there; in the hyena's it is planted afresh
  var s=st.Structure{.x=0,.y=0,.seed=0,.state=.{.strangeSeed=.{.planted=true,.fragments=5}}};
  sown(&s,.wolf);
  try testing.expect(!s.state.strangeSeed.planted);
  sown(&s,.hyena);
  try testing.expect(s.state.strangeSeed.planted and s.state.strangeSeed.fragments==0);
}
