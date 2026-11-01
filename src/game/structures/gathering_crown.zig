//! GATHERING CROWN: a symbiote that gathers for the garden. It sends a
//! woven root out to every plant on the tiles within two of it and, once a
//! root has reached its plant, gathers what that plant has ripened, a unit
//! at a time and each plant in turn, into the pod at its heart: one crown
//! harvests a whole bed, where conduits need a root beside every plant.
//! What it gathers goes to a neighbour that wants it, or a conduit behind
//! it pulls it away; with nowhere to go it holds `buffer`, then rests.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the test harness: allocator and expectations
const testing=std.testing;
/// all the maths: vectors, matrices, easing
const m=lib.engine.core.math;
/// colour conversions, for tinting a carried mote by its item's colour
const color=lib.engine.core.color;
/// chunk layout and plant ids
const ck=lib.ck;
/// the garden's tile world
const World=lib.world.World;
/// what can be held: item kinds and stacks of them
const items=lib.items;
/// the garden's plants, which it roots out to and gathers from
const Plants=lib.plants.Plants;
/// the structures registry: `Def`, `Structure`, the hooks' context
const st=lib.structures;
/// the shared structure test bench: ground, running ticks
const bench=st.bench;
/// the tools a bulb icon is drawn with
const iconKit=lib.icon;
/// every player-facing string
const txt=lib.txt;
/// what the gardener has understood
const prog=lib.progression;
/// the HUD's shared sizes and colours
const style=lib.style;
/// the scene's list of moving parts this crown adds to each frame
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the mesh library, whose ids name its roots
const meshlib=lib.meshlib;
/// the crown's mesh: where its pod sits and how wide
const mesh=lib.gatheringCrown;
/// builds a three-float vector
const v3=m.v3;
/// a ganglion grown beside it: the study of shared nerves
pub const meets:st.Meeting=.{.kind=.ganglion,.found=.crownAndNerve};
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.bellyLump,.itemPod,.crownRoot1,.crownRoot2,.crownRoot3,.crownRoot4,.crownRoot5};
/// what a crown is: grown from its seed, one tile across, a low store
/// swaying freely in the breeze
pub const def:st.Def=.{.item=.gatheringCrown,.lineage=.symbiotic,.size=1,.mesh=.gatheringCrown,.store=true,.grow=5,.sway=0.6,.tall=0.45,.sap=0.35};
/// how far it reaches, in tiles, every way
pub const reachTiles=2;
/// the width of the square of tiles it reaches over
const side=2*reachTiles+1;
/// how many tiles that square holds (its own among them)
const tiles=side*side;
/// seconds between one gathering and the next
pub const gather:f32=1.5;
/// the most it holds before it rests
pub const buffer=12;
/// how fast a root grows out to a plant (its length a second at one tile
/// out; farther ones take longer)
const rootGrow:f32=0.5;
/// how fast a root withers once its plant is gone (lengths a second)
const rootWither:f32=1.2;
/// how much the roots flutter in the breeze
const rootFlutter:f32=0.3;
/// what it gathers travels up the root to the pod this fast (its length a
/// second)
const carryRate:f32=1.5;
/// how high that travelling mote arcs over the ground
const arc:f32=0.18;
/// the size of the travelling mote
const moteSize:f32=0.45;
/// how brightly the travelling mote glows
const moteGlow:f32=0.8;
/// what it holds hangs in the pod in a ring this far out, as a share of
/// the pod's radius
const ringRadius:f32=0.45;
/// the size of a held shape holding a single thing
const lumpR:f32=0.024;
/// how much larger a held shape grows as the pod fills
const lumpGrow:f32=0.02;
/// how far each held shape bobs up and down
const bobAmount:f32=0.01;
/// how fast the ring of held shapes turns (radians a second)
const turnRate:f32=0.2;
/// how brightly the roots and held shapes glow
const glow:f32=0.2;
/// what a crown remembers: its roots' reach, whose turn it is, and the
/// last thing gathered on its way up
pub const State=struct{
  /// how far its root toward each tile round it has grown (0..1), by
  /// `index` of the tile's offset
  reach:[tiles]f32=@splat(0),
  /// the tile it gathers from next (round them in turn)
  turn:u8=0,
  /// seconds since it last gathered
  t:f32=0,
  /// the tile the last thing gathered came from (null: nothing travelling)
  from:?u8=null,
  /// how far up its root that thing has travelled, 0..1
  carry:f32=0,
  /// what that travelling thing is
  carried:items.Item=.essence,
};
/// the offset (x, y), in tiles, of the `i`th tile of the square round it
fn offset(i:usize)[2]i32{return.{@as(i32,@intCast(i%side))-reachTiles,@as(i32,@intCast(i/side))-reachTiles};}
/// the plant whose own tile (its corner, for one larger than a tile) is
/// `i` round (x, y), if any: one root to each plant
fn plantAt(ctx:st.Ctx,x:i32,y:i32,i:usize)?ck.PlantId{
  // that tile's offset from the crown
  const o=offset(i);
  if(o[0]==0 and o[1]==0)return null;
  // the plant covering that tile, and the plant list to check its corner
  const p=ctx.plants.at(ctx.w,x+o[0],y+o[1]) orelse return null;
  const s=ctx.plants.list.slice();
  if(s.items(.x)[p.idx()]!=x+o[0] or s.items(.y)[p.idx()]!=y+o[1])return null;
  return p;
}
/// which root mesh reaches the tile at offset `o` (one per distance out)
fn rootFor(o:[2]i32)meshlib.Id{
  // the squared distance out to that tile
  const d2=o[0]*o[0]+o[1]*o[1];
  return switch(d2){
    1=>.crownRoot1,
    2=>.crownRoot2,
    4=>.crownRoot3,
    5=>.crownRoot4,
    else=>.crownRoot5,
  };
}
/// grows a root toward each plant round it (withering the rest), carries
/// the last gathered thing up its root, and every `gather` seconds takes one
/// ripe unit from the next reached plant round. Returns true while working.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  _=st.handOff(ctx,i);
  // the crown itself, and its remembered state
  const self=ctx.ss.get(i);
  const c=&self.state.gatheringCrown;
  // how many roots have reached their plants
  var roots:usize=0;
  for(&c.reach,0..)|*r,k|{
    // the tile's offset, how far out it is, and whether a plant stands there
    const o=offset(k);
    const len=@sqrt(m.f(o[0]*o[0]+o[1]*o[1]));
    const there=plantAt(ctx,self.x,self.y,k)!=null;
    r.*=if(there)@min(1,r.*+dt*rootGrow/@max(len,1))else@max(0,r.*-dt*rootWither);
    if(r.*>=1)roots+=1;
  }
  if(c.from)|_|{
    c.carry+=dt*carryRate;
    if(c.carry>=1)c.from=null;
  }
  if(roots==0 or self.inv.total()>=buffer)return false;
  c.t+=dt;
  if(c.t<gather)return true;
  // each plant its root has reached, in turn
  for(0..tiles)|k|{
    // the tile offered now, starting from whose turn it is
    const at:u8=@intCast((c.turn+k)%tiles);
    if(c.reach[at]<1)continue;
    // the plant there, and what it gives up
    const p=plantAt(ctx,self.x,self.y,at) orelse continue;
    const item=st.harvestOne(ctx.plants,p) orelse continue;
    _=self.inv.add(item,1);
    c.turn=@intCast((@as(usize,at)+1)%tiles);
    c.t=0;
    c.from=at;
    c.carry=0;
    c.carried=item;
    return true;
  }
  // nothing ripe: it waits, ready
  c.t=gather;
  return false;
}
/// it takes nothing in: all it holds it gathers itself.
pub fn wants(_:*const st.Structure,_:*const prog.Progression,_:items.Item)u32{return 0;}
/// the oldest thing it gathered.
pub fn output(s:*const st.Structure)?items.Item{return s.firstHeld(st.Structure.anything);}
/// it gives anything it holds.
pub fn gives(s:*const st.Structure,item:items.Item)bool{return s.inv.count(item)>0;}
/// its roots out to the plants round it, what it last gathered travelling
/// up one, and what it holds hanging in its pod.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // its remembered state
  const c=&s.state.gatheringCrown;
  for(c.reach,0..)|r,k|{
    if(r<=0)continue;
    // this root's tile offset
    const o=offset(k);
    try out.emit(rootFor(o),m.chain(&.{m.translate(ctr),m.rotY(m.atan2(-m.f(o[1]),m.f(o[0])))}),.{
      .flutter=rootFlutter,.phase=s.seed+m.f(k)*0.07,.grown=r*s.grown,.glow=glow,
    });
  }
  if(s.grown<1)return;
  // its frame in the world
  const base=s.place(ctr);
  if(c.from)|k|{
    // the tile it came from, where it set out, where the pod is, and where it is now
    const o=offset(k);
    const from=ctr+v3(m.f(o[0]),0.05,m.f(o[1]));
    const to=m.mulPoint(base,mesh.podAt);
    const p=m.lerpV(from,to,m.smooth(c.carry))+v3(0,arc*@sin(m.pi*c.carry),0);
    try out.emit(.itemPod,m.chain(&.{m.translate(p),m.scale3(m.splat3(moteSize*@sin(m.pi*m.clamp01(c.carry*1.1+0.05))))}),.{
      .glow=moteGlow,.tint=color.Rgba8.of(c.carried.info().col).toF4(),
    });
  }
  // how many stacks it holds, and which of them is being drawn
  const n=s.inv.used();
  var j:usize=0;
  for(s.inv.slot)|slot|{
    // the stack in this slot
    const it=slot orelse continue;
    // the stack's place on the ring: its angle, the ring's reach, where it hangs
    const a=m.ratio(j,n)*m.tau+tf*turnRate+s.seed*6;
    const ring=if(n==1)0 else mesh.podR[0]*ringRadius;
    const at=mesh.podAt+v3(@cos(a)*ring,bobAmount*@sin(tf*0.9+m.f(j)*2),@sin(a)*ring);
    // its size: larger the fuller the pod
    const r=lumpR+lumpGrow*m.ratio(it.n,buffer);
    try s.emitLump(out,base,at,r,it.item,glow);
    j+=1;
  }
}
/// its line in the panel: how many plants it reaches and how full it is,
/// with a tendril toward its next gathering (or a note that it is full).
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // its remembered state
  const c=&s.state.gatheringCrown;
  // how many roots have reached their plants
  var n:u32=0;
  for(c.reach)|r|{if(r>=1)n+=1;}
  // how much it holds
  const held=s.inv.total();
  if(held>=buffer){
    _=try d.print(x,y,style.textBody,style.dim,txt.s.describe.crownFull,.{held,buffer});
    return;
  }
  _=try d.print(x,y,style.textBody,if(n==0)style.dim else style.white,txt.s.describe.gathers,.{n,held,buffer});
  try d.tendril(x+style.descBarX,y+2,style.descBarW,style.barH,style.growth,c.t/gather,0.3);
}
/// its bulb: a cupped crown of petals on a sprout out of the seed, roots
/// reaching out either side to small buds (it gathers from the plants
/// round it).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  for([_]f32{-1,1})|sx|{
    try ic.stem(.{.{0.08*sx,-0.6},.{0.35*sx,-0.5},.{0.55*sx,-0.62},.{0.7*sx,-0.5}},0.07,iconKit.rootCol);
    try ic.bud(.{0.72*sx,-0.4},0.11,iconKit.sprout,0.5);
  }
  try ic.stem(.{.{0,iconKit.topAt},.{0.03,0.3},.{-0.03,0.45},.{0,0.55}},0.1,iconKit.stemCol);
  try ic.glow(.{0,0.7},0.25,iconGlow);
  try ic.bud(.{0,0.7},0.15,iconSap,0.7);
  for(0..5)|k|try ic.leaf(.{0,0.6},0.35+m.f(k)*0.6,0.32,0.12,if(k%2==0)iconPetal else iconKit.sprout,0.6);
  try ic.coat(col);
}
/// the amber of the sap bead at the crown's heart in its bulb
const iconSap:Color=.{255,190,90,255};
/// the soft amber glow behind that bead
const iconGlow:Color=.{255,190,90,80};
/// the warm gold of the crown's petals
const iconPetal:Color=.{245,190,100,255};
// ---- tests ----
/// plants a full-grown lumenroot at (x, y) holding `essence` ripe units
fn ripe(gpa:Allocator,w:*World,plants:*Plants,x:i32,y:i32,essence:f32)!void{
  try testing.expect(try plants.placeEx(gpa,w,x,y,.{.x=x,.y=y,.chunk=undefined,.tile=undefined,.sp=.lumenroot,.seed=0,.growth=1,.essence=essence}));
}
test"a gathering crown roots out to every plant within two tiles and gathers them"{
  // the allocator, the world and its ground
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=7,.depth=7});
  // the plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,3,3,.gatheringCrown,0,0));
  // beside, on a diagonal, two out, and the far corner; one too far
  try ripe(gpa,&w,&plants,4,3,2);
  try ripe(gpa,&w,&plants,2,2,2);
  try ripe(gpa,&w,&plants,3,5,2);
  try ripe(gpa,&w,&plants,1,1,2);
  try ripe(gpa,&w,&plants,6,3,2);
  try bench.run(&ss,&w,&plants,&g,30);
  // the crown
  const id=ss.at(&w,3,3).?;
  try testing.expectEqual(@as(u32,8),ss.get(id).inv.count(.essence));
  // the one three tiles out is left alone
  const far=plants.at(&w,6,3).?;
  try testing.expectEqual(@as(f32,2),plants.list.items(.essence)[far.idx()]);
}
test"a gathering crown hands what it gathers to a cache beside it"{
  // the allocator, the world and its ground
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=7,.depth=7});
  // the plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,3,3,.gatheringCrown,0,0));
  try testing.expect(try ss.place(gpa,&w,3,4,.sapCache,0,0));
  try ripe(gpa,&w,&plants,5,3,20);
  try bench.run(&ss,&w,&plants,&g,40);
  try testing.expect(ss.get(ss.at(&w,3,4).?).inv.count(.essence)>=15);
  try testing.expectEqual(@as(u32,0),ss.get(ss.at(&w,3,3).?).inv.total());
}
