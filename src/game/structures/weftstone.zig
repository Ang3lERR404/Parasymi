//! WEFTSTONE: a loomfern and a lithophage grown into one floating body. It
//! hangs over any dry tile (over nodes, plants or structures alike) and
//! sends tendrils down to the mineral nodes round it, as many as
//! `latchCount`, nearest first, out to `reachTiles` tiles every way;
//! latched, each draws what its node holds up into the bulb at its bottom,
//! one unit at a time in turn. Grit and ley shards gathered there are
//! ionized, electrostatically, a measure of each at a time, into a ley
//! crystal, which it holds for the gardener or hands to the structures
//! beside it.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the test harness: allocator and expectations
const testing=std.testing;
/// all the maths: vectors, matrices, curves
const m=lib.engine.core.math;
/// colour conversions, for tinting motes and sparks by their item's colour
const color=lib.engine.core.color;
/// chunk layout: tiles, their kinds, heights and what is left in them
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
/// the scene's list of moving parts it adds to each frame
const Parts=lib.parts.Parts;
/// how one part looks: its glow, tint, sway and growth
const Look=lib.parts.Look;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the weftstone's mesh: its bulb and the point under it
const mesh=lib.weftstone;
/// a three-float vector
const V3=m.V3;
/// builds a three-float vector
const v3=m.v3;
// decision: its hover is carried by its mesh (`mesh.hover`), so `hover`
// stays 0 (the preview would lift it twice); breathing bobs it
/// a driftbraid grown beside it: the study of interweaving
pub const meets:st.Meeting=.{.kind=.driftbraid,.found=.weftAndDrift};
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.itemPod,.lithophageCrystal,.weftstoneTendril};
/// what a weftstone is: grown from its seed, one tile across, a floating
/// store, tall, swaying a little
pub const def:st.Def=.{.item=.weftstone,.size=1,.mesh=.weftstone,.store=true,.grow=7,.sway=0.3,.tall=1.2,.sap=0.3,.floating=true};
/// how far its tendrils reach, in tiles, every way
pub const reachTiles=2;
/// how many nodes it latches onto at once
pub const latchCount=6;
/// seconds a tendril takes to draw one unit from its node
pub const draw:f32=2;
/// the most grit its bulb holds
pub const bulbGrit=12;
/// the most ley shards its bulb holds
pub const bulbLey=4;
/// grit taken into one ley crystal
pub const ionGrit=4;
/// ley shards taken into one ley crystal
pub const ionLey=1;
/// seconds one crystal takes to ionize
pub const ionize:f32=6;
/// most ley crystals it holds
pub const crystalCount=8;
/// how fast a tendril reaches out (shares a second)
const reachDistance:f32=0.5;
/// how fast one withers back (shares a second)
const wither:f32=0.8;
/// how much its tendrils flutter in the breeze
const tendrilFlutter:f32=0.25;
/// the size of the mote rising up a tendril
const moteSize:f32=0.3;
/// how brightly that mote glows
const moteGlow:f32=0.7;
/// the ionizing crystal's size when whole (of its mesh)
const crystalSize:f32=1.05;
/// how fast it turns in the bulb (radians a second)
const crystalTurn:f32=0.4;
/// the size of a finished crystal held in the bulb
const heldSize:f32=0.32;
/// sparks crackling round the crystal while it ionizes: how many,
const sparks=5;
/// how often they jump (jumps a second),
const sparkRate:f32=14;
/// how large each spark is,
const sparkSize:f32=0.12;
/// and how brightly they flare
const sparkGlow:f32=1.4;
/// how brightly its tendrils glow
const glow:f32=0.18;
/// the tiles its tendrils may reach, as offsets, nearest first
const tiles=blk:{
  // how many tiles the square holds, the list, and how many laid so far
  const n=(2*reachTiles+1)*(2*reachTiles+1);
  var t:[n][2]i32=undefined;
  var k:usize=0;
  // the row being laid
  var y:i32=-reachTiles;
  while(y<=reachTiles):(y+=1){
    // the column being laid
    var x:i32=-reachTiles;
    while(x<=reachTiles):(x+=1){
      t[k]=.{x,y};
      k+=1;
    }
  }
  // by distance, then as laid out (stable)
  for(1..n)|i|{
    // the place the tile being sorted has sunk to
    var j=i;
    while(j>0 and dist2(t[j])<dist2(t[j-1])):(j-=1){
      // the tile set aside while two swap
      const tmp=t[j];
      t[j]=t[j-1];
      t[j-1]=tmp;
    }
  }
  break:blk t;
};
/// the squared distance of an offset from its centre
fn dist2(o:[2]i32)i32{return o[0]*o[0]+o[1]*o[1];}
/// what a weftstone remembers: its tendrils, the unit being drawn up, and
/// the crystal ionizing
pub const State=struct{
  /// how far each tendril has reached, 0..1 (one per tile in `tiles`)
  reach:[tiles.len]f32=@splat(0),
  /// the ground under the node each tendril reaches (for drawing it)
  ground:[tiles.len]f32=@splat(0),
  /// the tendril drawing now (null: none)
  from:?u8=null,
  /// the unit it draws
  drawing:?items.Item=null,
  /// how far up the tendril that unit has come (0..1)
  t:f32=0,
  /// the next tendril in turn
  turn:u8=0,
  /// whether a crystal is ionizing (its measure taken)
  ionizing:bool=false,
  /// how far along that crystal is (0..1)
  ion:f32=0,
};
/// whether an item is a mineral it draws (grit or ley shard)
fn mineral(item:items.Item)bool{return item==.grit or item==.leyShard;}
/// whether its bulb has room for one more of `item`
fn room(s:*const st.Structure,item:items.Item)bool{
  return switch(item){
    .grit=>s.inv.count(.grit)<bulbGrit,
    .leyShard=>s.inv.count(.leyShard)<bulbLey,
    else=>false,
  };
}
/// a mineral node on tile `k` of `tiles` round (x, y), if any: its chunk,
/// tile and what it gives (built over or not, floating as it does)
fn nodeAt(w:*World,x:i32,y:i32,k:usize)?struct{c:*ck.Chunk,t:usize,item:items.Item}{
  // the tile looked at, its chunk and its index there
  const tx=x+tiles[k][0];
  const ty=y+tiles[k][1];
  const c=w.chunkOfTile(tx,ty) orelse return null;
  const t=ck.localIndex(tx,ty);
  if(c.res[t]==0)return null;
  // the node that ground holds
  const node=resources.of(c.kind[t]) orelse return null;
  if(!mineral(node.item))return null;
  return.{.c=c,.t=t,.item=node.item};
}
/// latch onto the nearest `latchCount` nodes: their tendrils reach out, the
/// rest wither back
fn latch(w:*World,self:*st.Structure,dt:f32)void{
  // its remembered state, and how many nodes are latched so far
  const ws=&self.state.weftstone;
  var n:usize=0;
  for(&ws.reach,&ws.ground,0..)|*r,*gnd,k|{
    // the node on this tile, while it may latch more
    const node=if(n<latchCount)nodeAt(w,self.x,self.y,k)else null;
    if(node)|nd|{
      n+=1;
      gnd.*=nd.c.height[nd.t];
      r.*=@min(1,r.*+dt*reachDistance);
    }else r.*=@max(0,r.*-dt*wither);
  }
}
/// latches its tendrils, draws a unit up the next latched one in turn
/// while its bulb has room, and ionizes a measure of grit and ley into a
/// crystal while it has them. Returns true while drawing or ionizing.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  _=st.handOff(ctx,i);
  // the weftstone itself
  const self=ctx.ss.get(i);
  latch(ctx.w,self,dt);
  // its remembered state, and whether it did anything
  const ws=&self.state.weftstone;
  var busy=false;
  // drawing: one unit at a time, the latched tendrils in turn
  if(ws.drawing==null){
    for(0..tiles.len)|j|{
      // the tendril tried now, starting from whose turn it is
      const at:u8=@intCast((ws.turn+j)%tiles.len);
      if(ws.reach[at]<1)continue;
      // the node it reaches
      const nd=nodeAt(ctx.w,self.x,self.y,at) orelse continue;
      if(!room(self,nd.item))continue;
      nd.c.res[nd.t]-=1;
      ws.drawing=nd.item;
      ws.from=at;
      ws.turn=@intCast((at+1)%tiles.len);
      ws.t=0;
      break;
    }
  }
  if(ws.drawing)|it|{
    busy=true;
    ws.t+=dt/draw;
    if(ws.t>=1 and self.inv.add(it,1)==1){
      ws.drawing=null;
      ws.from=null;
      ws.t=0;
    }
  }
  // ionizing: a measure of grit and ley into a crystal
  if(!ws.ionizing and self.inv.count(.leyCrystal)<crystalCount and self.inv.count(.grit)>=ionGrit and self.inv.count(.leyShard)>=ionLey){
    _=self.inv.take(.grit,ionGrit);
    _=self.inv.take(.leyShard,ionLey);
    ws.ionizing=true;
    ws.ion=0;
  }
  if(ws.ionizing){
    busy=true;
    ws.ion=@min(1,ws.ion+dt/ionize);
    if(ws.ion>=1 and self.inv.add(.leyCrystal,1)==1){
      ws.ionizing=false;
      ws.ion=0;
    }
  }
  return busy;
}
/// grit and ley shards, while its bulb has room for them.
pub fn wants(s:*const st.Structure,_:*const prog.Progression,item:items.Item)u32{
  return switch(item){
    .grit=>bulbGrit-|s.inv.count(.grit),
    .leyShard=>bulbLey-|s.inv.count(.leyShard),
    else=>0,
  };
}
/// uprooted mid-ionization: the measure it took comes back.
pub fn release(s:*st.Structure)?items.Item{
  // its remembered state
  const ws=&s.state.weftstone;
  if(ws.ionizing){
    _=s.inv.add(.grit,ionGrit);
    _=s.inv.add(.leyShard,ionLey);
    ws.ionizing=false;
  }
  return null;
}
/// what it gives first: a ley crystal, while it holds one.
pub fn output(s:*const st.Structure)?items.Item{return if(s.inv.count(.leyCrystal)>0).leyCrystal else null;}
/// it gives ley crystals only, while it holds some.
pub fn gives(s:*const st.Structure,item:items.Item)bool{return item==.leyCrystal and s.inv.count(.leyCrystal)>0;}
/// the end of tendril `k` on its node, and its four control points from
/// under the bulb (`under`): down out of it, out over the ground, and down
/// onto the node
fn tendrilCtrl(s:*const st.Structure,under:V3,k:usize)[4]V3{
  // the node's offset, its top in the world, and the way to it
  const o=tiles[k];
  const node=m.footprintCentre(s.x+o[0],s.y+o[1],1,s.state.weftstone.ground[k])+v3(0,0.06,0);
  const d=node-under;
  return.{under,under+v3(d[0]*0.25,-0.18,d[2]*0.25),node+v3(-d[0]*0.15,0.3+0.05*m.len(v3(d[0],0,d[2])),-d[2]*0.15),node};
}
/// a point `t` along the curve through `c` (as the GPU bends it, closely enough)
fn along(c:[4]V3,t:f32)V3{
  // what is left of the way
  const u=1-t;
  return c[0]*m.splat3(u*u*u)+c[1]*m.splat3(3*u*u*t)+c[2]*m.splat3(3*u*t*t)+c[3]*m.splat3(t*t*t);
}
/// its tendrils down to the nodes it latches, a mote of what each draws
/// rising up it, the crystal ionizing in its bulb with sparks crackling
/// round it, and what its bulb holds.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // its remembered state, its frame in the world, and the point under its bulb
  const ws=&s.state.weftstone;
  const base=s.place(ctr);
  const under=m.mulPoint(base,mesh.underAt);
  for(ws.reach,0..)|r,k|{
    if(r<=0)continue;
    // this tendril's curve, its run laid level, and its flat side across that
    const c=tendrilCtrl(s,under,k);
    const flat=v3(c[3][0]-c[0][0],0,c[3][2]-c[0][2]);
    const side=if(m.len(flat)>m.eps)m.norm(m.cross(flat,v3(0,1,0)))else v3(1,0,0);
    try out.emitCurve(.weftstoneTendril,c,side,1,r*s.grown,.{.flutter=tendrilFlutter,.phase=s.seed+m.f(k)*0.13,.glow=glow});
  }
  if(s.grown<1)return;
  // the look every part of it shares: swaying with the body
  const sway:Look=.{.phase=s.seed,.sway=def.sway,.tall=def.tall};
  if(ws.drawing)|it|if(ws.from)|k|{
    // the tendril it rises up, and where along it the mote is
    const c=tendrilCtrl(s,under,k);
    const p=along(c,1-m.smooth(ws.t));
    // the mote's look: brighter, its mineral's colour
    var look=sway;
    look.glow=moteGlow;
    look.tint=color.Rgba8.of(it.info().col).toF4();
    try out.emit(.itemPod,m.chain(&.{m.translate(p),m.scale3(m.splat3(moteSize*@sin(m.pi*m.clamp01(ws.t*1.1))))}),look);
  };
  // the ley crystal's colour, for the sparks
  const ley=color.Rgba8.of(items.Item.leyCrystal.info().col).toF4();
  if(ws.ionizing){
    // the crystal's look: swaying from the bulb's height, brighter as it forms
    var look=sway;
    look.drop=mesh.bulbAt[1];
    look.glow=0.3+0.5*ws.ion;
    try out.emit(.lithophageCrystal,m.mul(base,m.chain(&.{m.translate(mesh.bulbAt),m.rotY(tf*crystalTurn+s.seed*4),m.scale3(m.splat3(crystalSize*@sqrt(ws.ion)))})),look);
    // sparks: each jumps to a new place round the crystal many times a
    // second, flickering
    const step=@floor(tf*sparkRate);
    for(0..sparks)|j|{
      // a hash of this jump, and from it the spark's angle and height (-0.7..0.7)
      const h=@sin((step+m.f(j)*17.3)*12.9898+s.seed*78.233)*43758.5453;
      const a=(h-@floor(h))*m.tau;
      const y=@sin(h*1.7)*0.7;
      // how far out from the crystal, and where it flares
      const rr=mesh.bulbR[0]*(0.45+0.4*ws.ion);
      const at=mesh.bulbAt+v3(@cos(a)*rr*@sqrt(1-y*y),y*mesh.bulbR[1]*0.6,@sin(a)*rr*@sqrt(1-y*y));
      // the spark's look: blazing, the ley crystal's colour
      var lookS=sway;
      lookS.glow=sparkGlow;
      lookS.tint=ley;
      lookS.drop=at[1];
      try out.emit(.itemPod,m.mul(base,m.chain(&.{m.translate(at),m.scale3(m.splat3(sparkSize*(0.6+0.4*@abs(@sin(h)))))})),lookS);
    }
  }
  // the crystals it holds, nestled in the bottom of its bulb
  const held=s.inv.count(.leyCrystal);
  for(0..held)|j|{
    // this crystal's angle round the bulb, and where it rests
    const a=m.ratio(j,crystalCount)*m.tau+s.seed*5;
    const at=mesh.bulbAt+v3(@cos(a)*mesh.bulbR[0]*0.5,-mesh.bulbR[1]*0.55,@sin(a)*mesh.bulbR[0]*0.5);
    // its look: swaying from as high as it rests
    var look=sway;
    look.drop=at[1];
    try out.emit(.lithophageCrystal,m.mul(base,m.chain(&.{m.translate(at),m.rotY(a),m.scale3(m.splat3(heldSize))})),look);
  }
}
/// its line in the panel: ionizing (with a tendril of progress), starved
/// (no node latched), or drawing: latched nodes, bulb and crystals held.
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // its remembered state
  const ws=&s.state.weftstone;
  // how many tendrils have latched
  var latched:u32=0;
  for(ws.reach)|r|{if(r>=1)latched+=1;}
  // how many crystals it holds
  const crystals=s.inv.count(.leyCrystal);
  if(ws.ionizing){
    _=try d.print(x,y,style.textBody,style.white,txt.s.describe.weftIonizes,.{crystals,crystalCount});
    try d.tendril(x+style.descBarX,y+2,style.descBarW,style.barH,style.lith,ws.ion,0.3);
    return;
  }
  if(latched==0 and ws.drawing==null){
    _=try d.print(x,y,style.textBody,style.dim,txt.s.describe.weftStarved,.{crystals,crystalCount});
    return;
  }
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.weftDraws,.{latched,s.inv.count(.grit),bulbGrit,s.inv.count(.leyShard),bulbLey,crystals,crystalCount});
}
/// its bulb: a twined stalk rising out of the seed to a crown of two
/// fronds, a bulb under them with a crystal sparking in it, tendrils
/// reaching down to stones either side.
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  // where its bulb hangs
  const bulb:iconKit.P=.{0,0.55};
  for([_]f32{-1,1})|sx|{
    // the stone this side's tendril reaches
    const stone:iconKit.P=.{0.7*sx,-0.25};
    try ic.stem(.{bulb,.{0.3*sx,0.35},.{0.6*sx,0.1},stone},0.035,iconTendril);
    try ic.gem(stone,0.09,if(sx<0)iconGrit else iconLey);
    try ic.stem(.{.{0,0.72},.{0.25*sx,0.98},.{0.5*sx,0.95},.{0.6*sx,0.78}},0.04,iconFrond);
    for(0..3)|j|try ic.leaf(iconKit.curve(.{.{0,0.72},.{0.25*sx,0.98},.{0.5*sx,0.95},.{0.6*sx,0.78}},0.3+0.2*m.f(j)),if(sx>0)1.9 else m.pi-1.9,0.12,0.05,iconKit.sprout,0.9);
  }
  try ic.stem(.{bulb,.{0.04,0.6},.{-0.04,0.66},.{0,0.72}},0.05,iconPale);
  try ic.bud(bulb,0.16,iconSac,0.5);
  // the spark's flicker (0..1), quick
  const k=@mod(ic.t*3+ic.phase,1);
  try ic.glow(bulb,0.12+0.06*k,iconSpark);
  try ic.gem(bulb,0.07,iconLey);
  try ic.coat(col);
}
/// the violet of its tendrils in its bulb
const iconTendril:Color=.{175,160,210,255};
/// the violet of its crown's fronds
const iconFrond:Color=.{175,160,210,255};
/// the pale lilac of its twined stalk
const iconPale:Color=.{185,180,205,255};
/// the rosy, half-clear bulb
const iconSac:Color=.{210,150,120,210};
/// the violet flicker of the spark in the bulb
const iconSpark:Color=.{210,170,255,120};
/// the stony grey of the grit node
const iconGrit:Color=.{150,140,130,255};
/// the lilac of the ley node and the crystal
const iconLey:Color=.{200,160,255,255};
// ---- tests ----
/// the bench's tick length, seconds
const testDt=bench.testDt;
/// turns tile (x, y) of the first chunk into a node of `item` holding `n`
/// (whichever ground kind yields it)
fn putNode(w:*World,x:usize,y:usize,item:items.Item,n:ck.Res)void{
  // the first chunk, and the tile's index in it
  const c=w.chunkOfTile(0,0).?;
  const t=y*ck.sizeTiles+x;
  inline for(std.meta.fields(ck.Kind))|f|{
    // this ground kind
    const kd:ck.Kind=@enumFromInt(f.value);
    if(resources.of(kd))|r|if(r.item==item){c.kind[t]=kd;};
  }
  c.res[t]=n;
}
test"a weftstone floats over the nodes, draws them up and ionizes them into ley crystals"{
  // the allocator, the world, its bare ground and two nodes
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=6,.depth=6,.bare=true});
  putNode(&w,2,2,.grit,30);
  putNode(&w,4,3,.leyShard,10);
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  // right over the grit node: floating, it takes no room there
  try testing.expect(try ss.place(gpa,&w,2,2,.weftstone,0,0));
  // the weftstone
  const id=ss.floaterAt(2,2).?;
  try bench.run(&ss,&w,&plants,&g,1/reachDistance+0.2);
  // how many tendrils have latched
  var latched:u32=0;
  for(ss.get(id).state.weftstone.reach)|r|{if(r>=1)latched+=1;}
  try testing.expectEqual(@as(u32,2),latched);
  try bench.run(&ss,&w,&plants,&g,draw*(ionGrit+ionLey)*2+ionize*2);
  // the weftstone, after its work
  const s=ss.get(id);
  try testing.expect(s.inv.count(.leyCrystal)>=1);
  try testing.expect(ss.output(id)==.leyCrystal and !ss.gives(id,.grit));
  try testing.expect(w.chunkOfTile(2,2).?.res[2*ck.sizeTiles+2]<30);
  // its bulb never overfills
  try testing.expect(s.inv.count(.grit)<=bulbGrit and s.inv.count(.leyShard)<=bulbLey);
}
test"a weftstone's tendrils reach no further than R and latch no more than LATCH"{
  // the allocator, the world, and its ground all grit nodes
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=6,.depth=6,.bare=true});
  for(0..6)|x|for(0..6)|y|putNode(&w,x,y,.grit,5);
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,2,2,.weftstone,0,0));
  try bench.run(&ss,&w,&plants,&g,1/reachDistance+0.2);
  // how many tendrils reach at all (each checked to be within reach)
  var latched:u32=0;
  for(ss.get(ss.floaterAt(2,2).?).state.weftstone.reach,tiles)|r,o|if(r>0){
    latched+=1;
    try testing.expect(@abs(o[0])<=reachTiles and @abs(o[1])<=reachTiles);
  };
  try testing.expectEqual(@as(u32,latchCount),latched);
}
