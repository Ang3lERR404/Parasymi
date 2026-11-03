//! ROOT-DIGGER: the first gathering automation. Its roots work the resource
//! node beside it, drawing out one item at a time (the same item the wolf
//! would gather there) into a small buffer. Conduits behind it pull from
//! that buffer; any other structure beside it that wants the item is fed
//! directly. When the node runs dry it idles, and it takes up any node that
//! appears beside it later by itself. Its digging root reaches out to the
//! node it works and withers back from one gone; what it draws out swells
//! up the root home into the gourd its knot of roots grips.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the test harness: allocator and expectations
const testing=std.testing;
/// all the maths: vectors, directions, easing
const m=lib.engine.core.math;
/// colour conversions, for tinting the root's swell by its item's colour
const color=lib.engine.core.color;
/// chunk layout: tiles, their kinds and what is left in them
const ck=lib.ck;
/// the garden's tile world, whose nodes it digs
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
/// which ground holds which resource node
const resources=lib.resources;
/// the HUD's shared sizes and colours
const style=lib.style;
/// the scene's list of moving parts this digger adds to each frame
const Parts=lib.parts.Parts;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the whole game, for the uprooting test
const play=lib.play;
/// the wolf's actions, for the uprooting test
const actions=lib.actions;
/// the digger's mesh: its root's reach and its gourd
const mesh=lib.rootDigger;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.bellyLump,.diggerClod,.diggerRoot};
/// what a digger is: grown from its seed, one tile across, a low store
/// swaying gently
pub const def:st.Def=.{.item=.rootDigger,.lineage=.symbiotic,.size=1,.mesh=.rootDigger,.store=true,.grow=4,.sway=0.5,.tall=0.6,.light=.boost,.draws=1};
/// seconds per item drawn from the node
pub const rate:f32=4;
/// items it holds before it stops digging
pub const buffer=8;
/// how fast its digging root reaches out to a node (its length a second)
const rootGrow:f32=0.6;
/// how fast it withers back from one gone (its length a second)
const rootWither:f32=0.9;
/// how much its roots flutter in the breeze
const rootFlutter:f32=0.3;
/// how brightly its root and what it holds glow at rest
const glow:f32=0.15;
/// how much brighter its root glows while it works
const glowActive:f32=0.5;
/// each item drawn: over the first `prise` of it the root prises it loose,
/// clods of the node flung up about its claw, then it swells up the root's
/// core in its own colour, home into the gourd
const prise:f32=0.3;
/// how many clods are flung up about the claw
const clods=4;
/// a clod's size
const clodSize:f32=0.034;
/// how high the clods are flung
const clodFling:f32=0.13;
/// how far out from the claw they fly
const clodOut:f32=0.11;
/// what it has dug hangs in its gourd in a ring this far out, as a share
/// of the gourd's radius
const ringRadius:f32=0.45;
/// the size of a held shape holding a single thing
const lumpR:f32=0.022;
/// how much larger a held shape grows as the gourd fills
const lumpGrow:f32=0.018;
/// how far each held shape bobs up and down
const bobAmount:f32=0.008;
/// how fast the ring of held shapes turns (radians a second)
const turnRate:f32=0.25;
/// its describe bar sits further right (a longer line), this far in
const barX:f32=300;
/// and is shorter, this wide
const barW:f32=60;
/// the node being worked: which side it lies on, what it yields, and how far
/// along the current item is.
pub const Dig=struct{
  /// the side the node lies on
  dir:m.Dir,
  /// what the node yields
  item:items.Item,
  /// seconds into drawing the current item (up to `rate`)
  t:f32=0,
};
/// what a digger remembers: the node it works and its roots' reach
pub const State=struct{
  /// null while there is no node beside it
  dig:?Dig=null,
  /// how far its digging root toward each side has reached (0..1)
  reach:m.Vice(f32,4)=@splat(0),
};
/// it roots in living ground only.
pub fn ground(k:ck.Kind)bool{return k==.soil or k==.moss;}
/// finds the node beside it (keeping the one it works), grows its root to
/// it, and every `rate` seconds draws one item out while its buffer has
/// room. Returns true while digging.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  // the digger itself
  const self=ctx.ss.get(i);
  _=st.handOff(ctx,i);
  // its remembered state, and the node beside it, if any
  const d=&self.state.rootDigger;
  const found=findNode(ctx.w,self.x,self.y,if(d.dig)|dg|dg.dir else 0);
  // its root reaches out to the node it works, and withers from any other
  for(&d.reach,0..)|*r,k|{
    // whether the node lies this way
    const there=if(found)|f|f.dir==k else false;
    r.*=st.reaching(r.*,there,dt*rootGrow/mesh.root.reachDistance,dt*rootWither);
  }
  if(found==null){
    d.dig=null;
    return false;
  }
  // the node found
  const f=found.?;
  if(d.dig==null or d.dig.?.dir!=f.dir)d.dig=.{.dir=f.dir,.item=f.item};
  // the dig under way
  const dg=&d.dig.?;
  if(self.inv.total()>=buffer)return false;
  dg.t+=dt;
  if(dg.t<rate)return true;
  dg.t-=rate;
  f.chunk.res[f.tile]-=1;
  _=self.inv.add(dg.item,1);
  return true;
}
/// a resource node found beside a digger
const Found=struct{
  /// the side it lies on
  dir:m.Dir,
  /// what it yields
  item:items.Item,
  /// the chunk it lies in
  chunk:*ck.Chunk,
  /// its tile's index in that chunk
  tile:usize,
};
/// an unoccupied resource node beside (x, y), trying `prefer` first so a
/// digger stays on the node it is working.
fn findNode(w:*const World,x:i32,y:i32,prefer:m.Dir)?Found{
  for(m.dirs)|k|{
    // the side tried, and the step toward it
    const dir=prefer+%k;
    const v=m.dirVec(dir);
    // the chunk of the tile that way, and its index there
    const c=w.chunkOfTile(x+v.x,y+v.z) orelse continue;
    const t=ck.localIndex(x+v.x,y+v.z);
    if(c.res[t]==0 or c.occ[t]!=.none)continue;
    // the node that ground holds
    const node=resources.of(c.kind[t]) orelse continue;
    return.{.dir=dir,.item=node.item,.chunk=c,.tile=t};
  }
  return null;
}
/// it takes nothing in: all it holds it digs itself.
pub fn wants(_:*const st.Structure,_:*const prog.Progression,_:items.Item)u32{return 0;}
/// the oldest buffered item.
pub fn output(s:*const st.Structure)?items.Item{
  for(s.inv.slot)|slot|if(slot)|it|return it.item;
  return null;
}
/// anything it has dug.
pub fn gives(s:*const st.Structure,item:items.Item)bool{return s.inv.count(item)>0;}
/// its digging root, reaching to the node (or withering from one gone);
/// while it works each item is prised loose, clods flung up about the
/// claw, and swells up the root's core home into the gourd, where what it
/// has dug hangs. All but the root sway with the knot.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // its remembered state, and the dig under way
  const d=&s.state.rootDigger;
  const dg=d.dig;
  // whether it is digging, and how far into the current item (0..1)
  const working=dg!=null and s.inv.total()<buffer;
  const k=if(dg)|g|g.t/rate else 0;
  for(d.reach,0..)|r,side|{
    if(r<=0)continue;
    // this root's side, whether it is the one digging, and the step that way
    const dir:m.Dir=@intCast(side);
    const on=working and dg.?.dir==dir and r>=1;
    const v=m.dirVec(dir);
    // the colour of what it draws, as bytes and as floats
    const col:m.Vice(u8,4)=if(dg)|g|g.item.info().col else.{0,0,0,255};
    const c=color.Rgba8.of(col).toF4();
    try out.emit(.diggerRoot,m.chain(&.{m.translate(ctr),m.rotY(m.atan2(-m.f(v.z),m.f(v.x)))}),.{
      .glow=glow+glowActive*s.activity,.flutter=rootFlutter,.phase=s.seed+m.f(side)*0.1,.grown=r*s.grown,
      .carry=if(on and k>prise)m.smooth((k-prise)/(1-prise))else-1,.carryCol=.{c[0],c[1],c[2]},
    });
    if(!on or k>prise)continue;
    // clods of the node flung up about the claw, falling back
    const node=ctr+m.v3(m.f(v.x),0,m.f(v.z))*m.splat3(mesh.root.reachDistance);
    // how far through the prising it is (0..1)
    const t=k/prise;
    for(0..clods)|j|{
      // this clod's heading, and how far out it flies
      const a=m.ratio(j,clods)*m.tau+s.seed*5+m.f(j)*0.7;
      const reach=clodOut*(0.7+0.3*m.f(j%2));
      // where it is on its arc, and its size (shrinking as it lands)
      const p=node+m.v3(@cos(a)*reach*t,clodFling*(0.8+0.2*m.f(j%3))*4*t*(1-t),@sin(a)*reach*t);
      const size=clodSize*(0.75+0.25*m.f(j%2))*(1-m.smooth(m.unlerp(0.85,1,t)));
      try out.emit(.diggerClod,m.chain(&.{m.translate(p),m.rotY(a+t*4),m.rotX(t*3+m.f(j)),m.scale3(m.splat3(size))}),.{.phase=s.seed});
    }
  }
  // what it has dug, hanging in its gourd
  if(s.grown<1)return;
  // its frame in the world
  const base=s.place(ctr);
  // how many stacks it holds, and which of them is being drawn
  const n=s.inv.used();
  var j:usize=0;
  for(s.inv.slot)|slot|{
    // the stack in this slot
    const it=slot orelse continue;
    // the stack's place on the ring: its angle, the ring's reach, where it hangs
    const a=m.ratio(j,n)*m.tau+tf*turnRate+s.seed*6;
    const ring=if(n==1)0 else mesh.podR[0]*ringRadius;
    const at=mesh.podAt+m.v3(@cos(a)*ring,bobAmount*@sin(tf*0.9+m.f(j)*2),@sin(a)*ring);
    // its size: larger the fuller the gourd
    const r=lumpR+lumpGrow*m.ratio(it.n,buffer);
    try s.emitLump(out,base,at,r,it.item,glow);
    j+=1;
  }
}
/// its line in the panel: no node (dim), or what it digs and how full it
/// is, with a tendril toward the next item.
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // how much it holds
  const n=s.inv.total();
  // the dig under way
  const dg=s.state.rootDigger.dig orelse {
    _=try d.print(x,y,style.textBody,style.dim,txt.s.describe.noNode,.{n,buffer});
    return;
  };
  // what to name: the item, or that it is full
  const what=if(n>=buffer)txt.s.describe.diggerFull else txt.item(dg.item).name;
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.digs,.{what,n,buffer});
  try d.tendril(x+barX,y+2,barW,style.barH,style.digger,dg.t/rate,0.4);
}
// ---- tests ----
/// a strip of soil at y = 0 (x = 0..5) with a moss node of `res` fibre at
/// (2, 0); the digger goes at (1, 0).
fn fixture(w:*World,res:ck.Res)!void{
  // the bare ground's chunk
  const c=try bench.ground(w,.{.width=6,.depth=2,.bare=true});
  c.kind[2]=.moss;
  c.res[2]=res;
}
test"a digger beside a node draws one item every 4 seconds"{
  // the allocator, and the world with its node
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w,5);
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,1,0,.rootDigger,0,0));
  // the digger
  const id=ss.at(&w,1,0).?;
  try bench.run(&ss,&w,&plants,&g,3.9);
  try testing.expectEqual(@as(u32,0),ss.get(id).inv.count(.fibre));
  try bench.run(&ss,&w,&plants,&g,8.2);
  try testing.expectEqual(@as(u32,3),ss.get(id).inv.count(.fibre));
  try testing.expectEqual(@as(ck.Res,2),w.chunkOfTile(2,0).?.res[2]);
}
test"a digger with no node beside it idles"{
  // the allocator, and the world with its node
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w,5);
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,4,1,.rootDigger,0,0));
  try bench.run(&ss,&w,&plants,&g,20);
  // the digger, far from the node
  const s=ss.get(ss.at(&w,4,1).?);
  try testing.expectEqual(@as(u32,0),s.inv.total());
  try testing.expect(s.state.rootDigger.dig==null);
  w.chunkOfTile(0,0).?.kind[ck.sizeTiles+3]=.stone;
  try testing.expect(!ss.canPlace(&w,3,1,.rootDigger));
}
test"a digger with nowhere to send buffers 8, then pauses"{
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
  try testing.expect(try ss.place(gpa,&w,1,0,.rootDigger,0,0));
  try bench.run(&ss,&w,&plants,&g,60);
  try testing.expectEqual(@as(u32,buffer),ss.get(ss.at(&w,1,0).?).inv.total());
  try testing.expectEqual(@as(ck.Res,20-buffer),w.chunkOfTile(2,0).?.res[2]);
}
test"a conduit behind the digger carries its items away"{
  // the allocator, and the world with its node
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w,6);
  // the chunk, its node moved to (1, 1) so the conduit's tile is clear
  const c=w.chunkOfTile(0,0).?;
  c.kind[2]=.soil;
  c.res[2]=0;
  c.kind[ck.sizeTiles+1]=.moss;
  c.res[ck.sizeTiles+1]=6;
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,1,0,.rootDigger,0,0));
  try testing.expect(try ss.place(gpa,&w,2,0,.conduit,0,0));
  try testing.expect(try ss.place(gpa,&w,3,0,.sapCache,0,0));
  // the conduit
  const conduit=ss.at(&w,2,0).?;
  // whether fibre was ever seen in the conduit, and the time run so far
  var carried=false;
  var t:f32=0;
  while(t<30):(t+=0.05){
    try ss.tick(testing.allocator,&w,&plants,&g,0.05);
    if(ss.get(conduit).state.conduit.held)|it|carried=carried or it==.fibre;
  }
  try testing.expect(carried);
  try testing.expect(ss.get(ss.at(&w,3,0).?).inv.count(.fibre)>=6);
}
test"uprooting a digger returns its bulb and what it holds"{
  // the allocator, and a whole game
  const gpa=testing.allocator;
  var g=try play.Game.init(gpa,play.defaultSeed);
  defer g.deinit();
  // the wolf's tile, and its chunk
  const at=m.tileAt(g.player.pos);
  const c=g.world.chunkOfTile(at[0],at[1]).?;
  c.kind[ck.localIndex(at[0],at[1])]=.soil;
  try testing.expect(try g.structs.place(gpa,&g.world,at[0],at[1],.rootDigger,0,0));
  // the digger
  const id=g.structs.at(&g.world,at[0],at[1]).?;
  _=g.structs.get(id).inv.add(.grit,3);
  // the grit the wolf carried before
  const grit=g.player.inv.count(.grit);
  actions.unbuild(&g,id);
  try testing.expectEqual(@as(u32,1),g.player.inv.count(.rootDigger));
  try testing.expectEqual(grit+3,g.player.inv.count(.grit));
  try testing.expect(g.structs.at(&g.world,at[0],at[1])==null);
}
/// its bulb: a small sprout above, roots reaching down from the seed to a
/// stone and a ley shard (it digs nodes).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  try ic.stem(.{.{-0.12,-0.62},.{-0.25,-0.62},.{-0.4,-0.55},.{-0.5,-0.66}},0.11,iconKit.rootCol);
  try ic.stem(.{.{0.12,-0.62},.{0.25,-0.66},.{0.38,-0.55},.{0.5,-0.62}},0.11,iconKit.rootCol);
  try ic.bud(.{-0.58,-0.7},0.19,iconStone,0.2);
  try ic.gem(.{0.6,-0.66},0.21,iconLey);
  try ic.stem(.{.{0,iconKit.topAt},.{0,0.25},.{0.06,0.35},.{0.02,0.45}},0.09,iconKit.stemCol);
  try ic.leaf(.{0.02,0.42},0.6,0.3,0.18,iconKit.sprout,0.9);
  try ic.leaf(.{0.02,0.4},m.pi-0.6,0.28,0.17,iconKit.sprout,0.9);
  try ic.coat(col);
}
/// the stony grey of the stone its root grips in its bulb
const iconStone:Color=.{150,140,130,255};
/// the violet of the ley shard its other root grips
const iconLey:Color=.{170,120,255,255};
