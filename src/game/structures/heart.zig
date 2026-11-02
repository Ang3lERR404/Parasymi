//! HEART: what a bare constellate stem becomes once four buds have
//! fastened on it (act 2; game/structures/stem.zig). It plays the heart's
//! story (the constellate sketch, `constellateHeartDriven`, its clock the
//! game's): bound, it rises a little, shrinking, filaments dripping from its
//! foot; its buds bloom one after another and its stem becomes a layered
//! rose. Then it waits for four petals put down nearby, which drift over to
//! its first bloom; with them its chain reaction runs, each bloom built
//! fragment by fragment, the heart growing past its first size, grand
//! petals opening; then its blooms burst free and fall, and it settles low
//! over the ground, currents of energy rising into its base. Settled it is
//! a builder: fed ten fragments (by hand, or by a tendril), it gathers
//! energy into a glowing spot on top of its rose and forms a whole part
//! there, point by point (a petal, leaf, bud, core and stem in turn), which
//! hangs there until taken.
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
/// what can be held: its fragments, the parts it makes
const items=lib.items;
/// every player-facing string
const txt=lib.txt;
/// what the gardener has understood
const prog=lib.progression;
/// the HUD's shared sizes and colours
const style=lib.style;
/// what every constellate part shares: its bulb's colours
const part=lib.constellatePart;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// the scene's list of moving parts it draws itself into
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the hover text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the library meshes it draws: its whole story, by its own `emit`
pub const meshes=.{.constellateHeartDriven};
/// what a heart is: one tile (it towers over it), drawn by its own `emit`,
/// still; taken up it is kept as a heart, put down again it plays its
/// story afresh
pub const def:st.Def=.{.item=.constellateHeart,.lineage=null,.size=1,.mesh=.constellateHeartDriven,.bare=true,.still=true};
/// when in its story (s) its buds have bloomed, and it waits for petals
/// (part.vert `PLEXUS_STORY`: bound, rising, blooming)
pub const bloomed:f32=6+8+14;
/// when in its story it has begun settling (its chain reaction run)
pub const settling:f32=bloomed+96;
/// how far into settling it has settled enough to build (currents flowing)
pub const builds:f32=settling+30;
/// how many petals on its first bloom begin its chain reaction
pub const petalsWhole:u8=4;
/// how many fragments a part costs it
pub const cost:u32=10;
/// the most fragments it keeps to build with
pub const keeps:u32=50;
/// on the settling's scale (s), where making a part begins (the spot
/// gathering) and where it is whole (part.vert `PLEXUS_MADE_GATHER`, then
/// `PLEXUS_MADE_FORM` + `PLEXUS_MADE_FORMING`, and a little to rest)
pub const madeFrom:f32=24;
/// where on that scale a part is whole, resting on top of its rose
pub const madeWhole:f32=44;
/// the parts it makes, in turn (part.vert `plexusMadeKind`'s order)
pub const makes=[_]items.Item{.constellatePetal,.constellateLeaf,.constellateBud,.constellateCore,.constellateStem};
/// what a heart remembers: how far into its story it is, the petals on its
/// first bloom, and the part it is making
pub const State=struct{
  /// how far into its story (s)
  clock:f32=0,
  /// petals drifted over to its first bloom (0 .. `petalsWhole`)
  petals:u8=0,
  /// how far into making a part, on the settling's scale (0 none)
  madeAt:f32=0,
  /// which of `makes` it makes next
  next:u8=0,
  /// whether a part is whole on top of its rose, waiting to be taken
  pub fn ready(q:State)bool{return q.madeAt>=madeWhole;}
  /// whether it has settled into a builder
  pub fn building(q:State)bool{return q.clock>=builds;}
};
/// one step of a heart `q` holding `inv` (of `n` slots) over `dt` s: its
/// story runs on, held where its buds have bloomed until four petals are
/// on; settled, it takes `cost` fragments to make a part, forms it, and
/// rests it whole until taken. Returns whether it worked.
pub fn step(comptime n:usize,q:*State,inv:*items.Inventory(n),dt:f32)bool{
  if(q.clock>=bloomed and q.petals<petalsWhole){
    q.clock=bloomed;
    return false;
  }
  q.clock+=dt;
  if(!q.building())return true;
  if(q.madeAt==0){
    if(!inv.take(.fragment,cost))return false;
    q.madeAt=madeFrom;
  }
  if(q.ready())return false;
  q.madeAt=@min(q.madeAt+dt,madeWhole);
  return true;
}
/// its story runs on; settled, it builds
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the heart
  const s=ctx.ss.get(i);
  return step(st.slots,&s.state.heart,&s.inv,dt);
}
/// settled, it takes fragments to build with, up to what it keeps
pub fn wants(s:*const st.Structure,_:*const prog.Progression,item:items.Item)u32{
  if(item!=.fragment)return 0;
  return keeps-|s.inv.count(.fragment);
}
/// a part whole on top of its rose: a click takes it
pub fn handOver(s:*st.Structure)?items.Item{
  // what it remembers
  const q=&s.state.heart;
  if(!q.ready())return null;
  const it=makes[q.next];
  q.next=@intCast((q.next+1)%makes.len);
  q.madeAt=0;
  return it;
}
/// bloomed and waiting, petals nearby may drift over to its first bloom
pub fn message(ctx:st.Ctx,i:st.Id,msg:st.Msg)st.Reply{
  // what it remembers
  const q=&ctx.ss.get(i).state.heart;
  // whether it waits for petals
  const waits=q.clock>=bloomed-8 and q.petals<petalsWhole;
  switch(msg){
    .petalComing=>return if(waits).done else.ignored,
    .petalSnapped=>{
      if(!waits)return.ignored;
      q.petals+=1;
      return.done;
    },
    .lit,.unform,.graft,.arrived,.fastenComing,.fastened=>return.ignored,
  }
}
/// its story as far as it has come, the part it makes, and its light
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // what it remembers
  const q=s.state.heart;
  try out.emit(.constellateHeartDriven,s.place(ctr),.{.phase=s.seed,.grown=q.clock,.carry=q.madeAt,.give=.{m.f(q.next),m.f(petalsWhole),0}});
  try out.light(ctr+m.v3(0,1.4,0),m.v3(0.45,0.7,1)*m.splat3(0.9+0.2*@sin(tf*1.6)),5);
}
/// its line in the panel: what it waits for, or what it builds
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // what it remembers
  const q=s.state.heart;
  if(q.clock>=bloomed and q.petals<petalsWhole)_=try d.print(x,y,style.textBody,style.white,txt.s.describe.heartPetals,.{q.petals})
  else if(!q.building())_=try d.print(x,y,style.textBody,style.white,txt.s.describe.heartForming,.{})
  else if(q.ready())_=try d.print(x,y,style.textBody,style.white,txt.s.describe.heartReady,.{txt.item(makes[q.next]).name})
  else _=try d.print(x,y,style.textBody,style.white,txt.s.describe.heartBuilds,.{s.inv.count(.fragment),txt.item(makes[q.next]).name});
}
/// its bulb: a rose of light, four blooms round it
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // the rose's middle
  const mid:iconKit.P=.{0,0.55};
  try ic.glow(mid,0.42,part.iconGlow);
  for(0..5)|k|try ic.leaf(mid,m.f(k)/5*m.tau+ic.t*0.1,0.22,0.12,part.iconLight,1);
  for(0..4)|k|try ic.bud(.{0.32*@cos(m.f(k)*m.halfPi+0.6),0.55+0.32*@sin(m.f(k)*m.halfPi+0.6)},0.06,part.iconLight,0.8);
  try ic.coat(col);
}
test"a heart waits bloomed for four petals, then settles and builds a part of ten fragments"{
  // a heart and what it holds
  var q=State{};
  var inv=items.Inventory(4){};
  for(0..100)|_|_=step(4,&q,&inv,1);
  try testing.expectEqual(bloomed,q.clock);
  q.petals=petalsWhole;
  for(0..200)|_|_=step(4,&q,&inv,1);
  try testing.expect(q.building() and q.madeAt==0);
  // fed: it makes its first part, whole after a while
  _=inv.add(.fragment,cost);
  for(0..30)|_|_=step(4,&q,&inv,1);
  try testing.expect(q.ready() and inv.count(.fragment)==0);
}
test"four buds put down near a bare stem fasten on it, and it becomes the heart"{
  // a fresh game, its world streamed in round the gardener
  const gpa=testing.allocator;
  var g=try lib.play.Game.init(gpa,lib.play.defaultSeed);
  defer g.deinit();
  try g.world.stream(g.focus(),2,1000);
  // a stem, and four buds round it
  const c=m.tileAt(g.player.pos);
  try testing.expect(try g.structs.place(gpa,&g.world,c[0]+3,c[1],.stem,0,0.1));
  for([_]m.Vice(i32,2){.{5,0},.{1,0},.{3,2},.{3,-2}},0..)|o,k|try testing.expect(try g.structs.place(gpa,&g.world,c[0]+o[0],c[1]+o[1],.bud,0,0.2+m.f(k)*0.1));
  // the seconds run: the buds drift over and fasten
  var t:f32=0;
  while(t<part.drifting+1):(t+=lib.play.tickTime)try g.step();
  // one heart left, forming
  try testing.expectEqual(@as(usize,1),g.structs.list.items.len);
  try testing.expectEqual(st.Kind.heart,g.structs.list.items[0].kind());
}
