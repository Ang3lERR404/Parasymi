//! LITHOPHAGE: a parasite that eats stone. Its roots reach into the
//! mineral nodes on the eight tiles round it (grit on soil and stone,
//! shards on ley lines) and draw them up, one at a time, into its crop,
//! where they condense into a crystal; ley shards fed to it go the same
//! way. Once the crystal is whole it is sapped away: it runs out of the
//! crop's lip as a stream of mineral grit, item by item, into the cup on
//! its foot, where conduits pull it or neighbours that want it take it.
//! It gathers from every node round it at once, and a ley shard it eats
//! comes out as three grit.
// decision: it is fed ley shards only: grit it holds is always grit it
// has sapped (what leaves it), never grit it would eat again
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the test harness: allocator and expectations
const testing=std.testing;
/// all the maths: vectors, matrices, easing
const m=lib.engine.core.math;
/// colour conversions, for tinting motes, stream and cup by grit's colour
const color=lib.engine.core.color;
/// chunk layout: tiles, their kinds and the minerals left in them
const ck=lib.ck;
/// the garden's tile world, whose nodes it drains
const World=lib.world.World;
/// what can be held: item kinds and stacks of them
const items=lib.items;
/// the garden's plants (the tests' bench needs a list of them)
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
/// which ground holds which mineral node
const resources=lib.resources;
/// the HUD's shared sizes and colours
const style=lib.style;
/// the scene's list of moving parts this parasite adds to each frame
const Parts=lib.parts.Parts;
/// how one part looks: its glow, tint, sway and growth
const Look=lib.parts.Look;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the lithophage's mesh: where its crop, lip and cup are
const mesh=lib.lithophage;
/// the mesh library, whose ids name its roots
const meshlib=lib.meshlib;
/// a three-float vector
const V3=m.V3;
/// builds a three-float vector
const v3=m.v3;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.lithophageRoot,.lithophageRootFar,.lithophageCrystal,.germinatorPool,.germinatorPour,.itemPod};
/// what a lithophage is: grown from its seed, one tile across, a pale
/// store that swaps sap, swaying a little
pub const def:st.Def=.{.item=.lithophage,.lineage=.parasitic,.size=1,.mesh=.lithophage,.store=true,.grow=6,.sway=0.35,.tall=0.7,.sap=0.32};
/// seconds it takes to draw one mineral up out of the ground (or eat one
/// it was fed)
pub const draw:f32=3;
/// how much a crystal takes: grit counts one, a ley shard `leyWorth`
pub const crystal:u32=6;
/// what one ley shard counts toward a crystal
pub const leyWorth:u32=3;
/// grit a crystal saps into
// decision: as much as went in, so grit drawn from the ground is never lost
pub const yield=crystal;
/// seconds between one grit sapped and the next
pub const sap:f32=2;
/// grit it holds in its cup before it stops sapping
pub const buffer=8;
/// the most ley shards it takes in
const stock=10;
/// the eight tiles round it its roots reach into, a turn at a time
const around=[8]m.Vice(i32,2){.{1,0},.{1,1},.{0,1},.{-1,1},.{-1,0},.{-1,-1},.{0,-1},.{1,-1}};
/// how fast a root grows out to a node (share a second)
const rootGrow:f32=0.35;
/// how fast a root withers once its node is gone (share a second)
const rootWither:f32=0.8;
/// the crystal's size when whole (of its mesh)
const crystalSize:f32=1.5;
/// how fast it turns slowly in the crop (radians a second)
const crystalTurn:f32=0.25;
/// the size of the mote a drawn-up mineral shows as, rising from root to crop
const moteSize:f32=0.35;
/// how brightly that mote glows
const moteGlow:f32=0.7;
/// the grit in its cup: a lens this wide empty .. full
const poolW=m.Vice(f32,2){0.012,0.032};
/// how brightly the grit in its cup glows
const poolGlow:f32=0.35;
/// how brightly the stream of sapped grit glows
const streamGlow:f32=0.75;
/// how much the roots flutter in the breeze
const rootFlutter:f32=0.2;
/// how brightly the roots glow
const glow:f32=0.15;
/// what a lithophage remembers: its crystal, the mineral being drawn up,
/// the grit still to sap, and its roots
pub const State=struct{
  /// how much of a crystal has condensed (of `crystal`)
  fill:u32=0,
  /// how far the mineral being drawn up is (0..1)
  t:f32=0,
  /// where it is drawn from (an index into `around`, or none: one it was fed)
  from:?u8=null,
  /// what is being drawn (null: nothing)
  drawing:?items.Item=null,
  /// grit still to sap from the crystal
  sap:u8=0,
  /// how far along the next grit sapped is (0..1)
  sapT:f32=0,
  /// which tile round it its roots try next
  turn:u8=0,
  /// how far its root toward each tile round it has grown (0..1)
  reach:[8]f32=@splat(0),
};
/// what a mineral counts toward a crystal: a ley shard `leyWorth`, grit one
fn worth(item:items.Item)u32{return if(item==.leyShard)leyWorth else 1;}
/// whether an item is a mineral it eats (grit or ley shard)
fn mineral(item:items.Item)bool{return item==.grit or item==.leyShard;}
/// a mineral node on tile `i` round (x, y), if any: its chunk, tile and
/// what it gives (null when spent, built over, or not a mineral)
fn nodeAt(w:*World,x:i32,y:i32,i:usize)?struct{c:*ck.Chunk,t:usize,item:items.Item}{
  // the tile looked at, its chunk and its index there
  const tx=x+around[i][0];
  const ty=y+around[i][1];
  const c=w.chunkOfTile(tx,ty) orelse return null;
  const t=ck.localIndex(tx,ty);
  if(c.res[t]==0 or c.occ[t]!=.none)return null;
  // the node that ground holds
  const node=resources.of(c.kind[t]) orelse return null;
  if(!mineral(node.item))return null;
  return.{.c=c,.t=t,.item=node.item};
}
/// grow roots toward the mineral nodes round it, wither those with none.
fn growRoots(w:*World,self:*st.Structure,dt:f32)void{
  // its remembered state
  const l=&self.state.lithophage;
  for(&l.reach,0..)|*r,k|{
    // whether a node lies on that tile
    const there=nodeAt(w,self.x,self.y,k)!=null;
    r.*=st.reaching(r.*,there,dt*rootGrow,dt*rootWither);
  }
}
/// grows its roots, then either saps its whole crystal into its cup a grit
/// at a time, or draws up a mineral (fed shards first, else a reached node)
/// and condenses it into the crystal. Returns true while working.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  _=st.handOff(ctx,i);
  // the lithophage itself
  const self=ctx.ss.get(i);
  growRoots(ctx.w,self,dt);
  // its remembered state
  const l=&self.state.lithophage;
  // sapping the whole crystal away into its cup, as grit
  if(l.sap>0){
    if(self.inv.count(.grit)>=buffer)return false;
    l.sapT+=dt/sap;
    if(l.sapT<1)return true;
    if(self.inv.add(.grit,1)<1)return false;
    l.sapT=0;
    l.sap-=1;
    return true;
  }
  // drawing a mineral up: from what it was fed first, else a node round it
  // its root has reached
  if(l.drawing==null){
    if(self.inv.take(.leyShard,1)){
      l.drawing=.leyShard;
      l.from=null;
    }else for(0..around.len)|k|{
      // the tile tried now, starting from whose turn it is
      const at:u8=@intCast((l.turn+k)%around.len);
      if(l.reach[at]<1)continue;
      // the node there
      const n=nodeAt(ctx.w,self.x,self.y,at) orelse continue;
      n.c.res[n.t]-=1;
      l.drawing=n.item;
      l.from=at;
      l.turn=@intCast((at+1)%around.len);
      break;
    }
    if(l.drawing==null)return false;
    l.t=0;
  }
  l.t+=dt/draw;
  if(l.t<1)return true;
  l.fill+=worth(l.drawing.?);
  l.drawing=null;
  l.t=0;
  if(l.fill>=crystal){
    l.fill=0;
    l.sap=yield;
  }
  return true;
}
/// it wants ley shards only, up to `stock`, less what it holds.
pub fn wants(s:*const st.Structure,_:*const prog.Progression,item:items.Item)u32{
  return if(item==.leyShard)stock-|s.inv.count(item)else 0;
}
/// only the grit it has sapped leaves it.
pub fn output(s:*const st.Structure)?items.Item{return if(s.inv.count(.grit)>0).grit else null;}
/// it gives grit only, while it holds some.
pub fn gives(s:*const st.Structure,item:items.Item)bool{return item==.grit and s.inv.count(.grit)>0;}
/// its roots out to the nodes round it, a mote of each mineral drawn up
/// one, the crystal condensing in its crop, the stream of grit it saps
/// into its cup and the grit standing there.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // its remembered state, and its frame in the world
  const l=&s.state.lithophage;
  const base=s.place(ctr);
  for(l.reach,0..)|r,k|{
    if(r<=0)continue;
    // this root's tile offset, and its mesh (the longer one for a diagonal)
    const o=around[k];
    const id:meshlib.Id=if(o[0]!=0 and o[1]!=0).lithophageRootFar else.lithophageRoot;
    try out.emit(id,m.chain(&.{m.translate(ctr),m.rotY(m.atan2(-m.f(o[1]),m.f(o[0])))}),.{.flutter=rootFlutter,.phase=s.seed+m.f(k)*0.1,.grown=r*s.grown,.glow=glow});
  }
  if(s.grown<1)return;
  // the look every part of it shares: swaying with the stalk
  const sway:Look=.{.phase=s.seed,.sway=def.sway,.tall=def.tall};
  // a mineral being drawn: up its root from the node, then up the stalk
  if(l.drawing)|it|{
    // where the crop is in the world
    const crop=m.mulPoint(base,mesh.cropAt);
    // where the mote is now
    const p=if(l.from)|k|blk:{
      // the node it left, and the stalk's foot it passes
      const node=ctr+v3(m.f(around[k][0])*0.8,0.02,m.f(around[k][1])*0.8);
      const foot=ctr+v3(0,0.05,0);
      break:blk if(l.t<0.5)m.lerpV(node,foot,m.smooth(l.t*2))else m.lerpV(foot,crop,m.smooth(l.t*2-1));
    }else m.lerpV(ctr+v3(0,0.05,0),crop,m.smooth(l.t));
    // the mote's look: brighter, its mineral's colour
    var look=sway;
    look.glow=moteGlow;
    look.tint=color.Rgba8.of(it.info().col).toF4();
    look.drop=p[1]-ctr[1];
    try out.emit(.itemPod,m.chain(&.{m.translate(p),m.scale3(m.splat3(moteSize*@sin(m.pi*m.clamp01(l.t*1.2))))}),look);
  }
  // the crystal: grown by what has condensed, shrinking as it is sapped
  const whole=if(l.sap>0)(m.f(l.sap)-l.sapT)/yield else(m.f(l.fill)+(if(l.drawing)|it|m.f(worth(it))*m.smooth(m.clamp01(l.t*2-1))else 0))/m.f(crystal);
  if(whole>0){
    // the crystal's look: swaying from the crop's height
    var look=sway;
    look.drop=mesh.cropAt[1];
    try out.emit(.lithophageCrystal,m.mul(base,m.chain(&.{m.translate(mesh.cropAt),m.rotY(tf*crystalTurn+s.seed*4),m.rotX(0.3),m.scale3(m.splat3(crystalSize*@sqrt(m.clamp01(whole))))})),look);
  }
  // sapping: a stream out of the crop's lip down into the cup
  const ess=color.Rgba8.of(items.Item.grit.info().col).toF4();
  if(l.sap>0 and s.inv.count(.grit)<buffer){
    // the lip and cup in the world, and the fall between them
    const lip=m.mulPoint(base,mesh.lipAt);
    const cup=m.mulPoint(base,mesh.cupAt+v3(0,0.02,0));
    const d=cup-lip;
    // the stream's curve: out level from the lip, then down into the cup
    const ctrl=[4]V3{lip,lip+v3(d[0]*0.5,0.01,d[2]*0.5),lip+v3(d[0]*0.95,d[1]*0.5,d[2]*0.95),cup};
    try out.emitCurve(.germinatorPour,ctrl,m.norm(m.cross(d,v3(0,1,0))),1,1,.{
      .glow=streamGlow,.phase=s.seed,.fade=1,.carryCol=.{ess[0],ess[1],ess[2]},
      .sway=def.sway,.tall=def.tall,.drop=cup[1]-ctr[1],
    });
  }
  // the grit standing in its cup
  const held=s.inv.count(.grit);
  if(held>0){
    // the pool's look: grit-coloured, glowing softly
    var look=sway;
    look.tint=ess;
    look.glow=poolGlow;
    look.drop=mesh.cupAt[1];
    try out.emit(.germinatorPool,m.mul(base,m.chain(&.{m.translate(mesh.cupAt+v3(0,0.01,0)),m.scale3(m.splat3(m.lerp(poolW[0],poolW[1],m.ratio(held,buffer))))})),look);
  }
}
/// its line in the panel: sapping (with a tendril of the crystal left),
/// starved (no node reached, nothing fed), or drawing toward a crystal.
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // its remembered state, and the grit in its cup
  const l=&s.state.lithophage;
  const held=s.inv.count(.grit);
  if(l.sap>0){
    _=try d.print(x,y,style.textBody,style.white,txt.s.describe.lithSaps,.{held,buffer});
    try d.tendril(x+style.descBarX,y+2,style.descBarW,style.barH,style.gold,1-(m.f(l.sap)-l.sapT)/yield,0.3);
    return;
  }
  // how many roots have reached their nodes
  var roots:u32=0;
  for(l.reach)|r|{if(r>=1)roots+=1;}
  if(l.drawing==null and roots==0){
    _=try d.print(x,y,style.textBody,style.dim,txt.s.describe.lithStarved,.{held,buffer});
    return;
  }
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.lithDraws,.{l.fill,crystal,held,buffer});
  try d.tendril(x+style.descBarX,y+2,style.descBarW,style.barH,style.lith,(m.f(l.fill)+l.t)/m.f(crystal),0.3);
}
/// its bulb: a pale stalk out of the seed swelling into a crop with a gem
/// condensing in it, a bead of grit running from its lip (it draws stone
/// out of the ground round it).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  try ic.stem(.{.{0,iconKit.topAt},.{0.05,0.25},.{-0.04,0.38},.{0,0.5}},0.11,iconSkin);
  try ic.glow(.{0,0.72},0.3,iconSacGlow);
  try ic.bud(.{0,0.72},0.28,iconSac,0.3);
  try ic.gem(.{0,0.72},0.15,iconGem);
  for([_]f32{-1,1})|sx|try ic.stem(.{.{0.05*sx,0.5},.{0.32*sx,0.55},.{0.34*sx,0.95},.{0.1*sx,1.02}},0.05,iconFrond);
  // how far down the grit bead has run (0..1)
  const k=@mod(ic.t*0.7+ic.phase,1);
  try ic.bud(.{0.3,m.lerp(0.55,iconKit.topAt,k)},0.07,iconEss,1-k);
  try ic.coat(col);
}
/// the grey-lilac of its stalk in its bulb
const iconSkin:Color=.{150,145,165,255};
/// the violet of the fronds round its crop
const iconFrond:Color=.{175,160,210,255};
/// the translucent blue of its crop
const iconSac:Color=.{120,160,220,200};
/// the soft blue glow behind that crop
const iconSacGlow:Color=.{120,160,220,70};
/// the lilac of the gem condensing in the crop
const iconGem:Color=.{200,170,255,255};
/// the stony grey of the grit bead running from its lip
const iconEss:Color=.{150,140,130,255};
// ---- tests ----
/// soil round (2, 2), a grit node at (3, 2) holding `res`
fn fixture(w:*World,res:ck.Res)!void{
  // the bare ground's chunk
  const c=try bench.ground(w,.{.width=6,.depth=5,.bare=true});
  c.res[2*ck.sizeTiles+3]=res;
}
test"a lithophage drains the node beside it into a crystal, then saps it into grit"{
  // the allocator, and the world with its node
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w,20);
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,2,2,.lithophage,0,0));
  // the lithophage
  const id=ss.at(&w,2,2).?;
  // its root reaches the node, then six grit make a crystal, sapped back out
  const secs=1/rootGrow+draw*crystal+sap*yield+1;
  try bench.run(&ss,&w,&plants,&g,secs);
  try testing.expectEqual(@as(u32,yield),ss.get(id).inv.count(.grit));
  // (the next is already being drawn up)
  const left=w.chunkOfTile(3,2).?.res[2*ck.sizeTiles+3];
  try testing.expect(left==20-crystal or left==20-crystal-1);
  try testing.expect(ss.output(id)==.grit);
  try testing.expect(!ss.gives(id,.leyShard));
}
test"a lithophage eats the ley shards it is fed, each worth three grit"{
  // the allocator, and the world with a spent node
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w,0);
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,2,2,.lithophage,0,0));
  // the lithophage
  const id=ss.at(&w,2,2).?;
  try testing.expectEqual(@as(u16,2),ss.insert(&g,id,.leyShard,2));
  try testing.expectEqual(@as(u16,0),ss.insert(&g,id,.fibre,2));
  // grit it never takes: what it holds is what it sapped
  try testing.expectEqual(@as(u16,0),ss.insert(&g,id,.grit,2));
  try bench.run(&ss,&w,&plants,&g,draw*2+sap*yield+1);
  try testing.expectEqual(@as(u32,yield),ss.get(id).inv.count(.grit));
  // nothing round it, nothing fed: it rests
  try bench.run(&ss,&w,&plants,&g,30);
  try testing.expectEqual(@as(u32,yield),ss.get(id).inv.count(.grit));
  try testing.expect(ss.get(id).activity<0.01);
}
test"a lithophage's grit is carried off by a conduit behind it"{
  // the allocator, and the world with its node
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w,30);
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,2,2,.lithophage,0,0));
  try testing.expect(try ss.place(gpa,&w,2,3,.conduit,1,0));
  try testing.expect(try ss.place(gpa,&w,2,4,.sapCache,0,0));
  try bench.run(&ss,&w,&plants,&g,80);
  try testing.expect(ss.get(ss.at(&w,2,4).?).inv.count(.grit)>=yield*2);
}
