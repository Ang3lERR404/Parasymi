//! LITHOPHAGE: the root-digger's upgrade, a parasite that eats stone. It
//! grows as a stone coral, half plant, half mineral, and sends its tendrils
//! out over a radius round it: each runs under the ground near it (a line
//! of glowing cracks), surfaces further out as a pale coral runner creeping
//! over the ground, and digs into a mineral node (grit, or a ley shard on
//! a ley line). It draws from its nodes a unit at a time, in turn, and
//! refines what comes up its roots: each unit becomes two grit (a
//! root-digger's gives one), a ley shard three. What it draws condenses
//! into a crystal budding on its coral; once whole it is sapped away, a
//! stream of grit running down into the cup on its foot, where conduits
//! pull it or neighbours that want it take it.
//! It grows forever: grown, it reaches 2 tiles, and one tile further each
//! time its age triples (3 after five of the garden's days, 4 after 15, 5
//! after 45 ...). Its coral grows on as it does, a tier of new growth for
//! each tile it reaches further (gfx/meshes/lithophage.zig), its last tier
//! creeping on ever more slowly.
// decision: it is fed ley shards only: grit it holds is always grit it
// has sapped (what leaves it), never grit it would eat again
// decision: a ley shard is worth three grit whether a tendril draws it
// from a ley line or it is fed one; a grit unit refines to two
// decision: its reach is a disc: a tile is in reach when its centre lies
// within half a tile past the reach (so 2 takes in a knight's move, not
// the 5x5 square's corners)
// decision: its age counts from when it is grown; its tendrils number at
// most `most`, the nearest nodes first
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
/// the seeded hashes each tendril's wander comes from
const rng=lib.engine.core.rng;
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
/// named-field records, how its state is saved
const record=lib.record;
/// the scene's list of moving parts this parasite adds to each frame
const Parts=lib.parts.Parts;
/// how one part looks: its glow, tint, sway and growth
const Look=lib.parts.Look;
/// the UI's draw batch, which the panel text goes into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the lithophage's mesh: its tiers, tendrils, crystal bud and cup
const mesh=lib.lithophage;
/// the mesh library, whose ids name its tiers and tendrils
const meshlib=lib.meshlib;
/// a three-float vector
const V3=m.V3;
/// builds a three-float vector
const v3=m.v3;
/// a tile offset from its own tile (x, y)
const Off=m.Vice(i16,2);
/// its coral's tiers of later growth, the first grown on as it first
/// reaches a third tile
const tierIds=[mesh.tiers]meshlib.Id{.lithophageTier1,.lithophageTier2,.lithophageTier3,.lithophageTier4};
/// its tendrils, one mesh for each length (`mesh.tendrilLens`)
const tendrilIds=[mesh.tendrilLens.len]meshlib.Id{
  .lithophageTendril1,.lithophageTendril2,.lithophageTendril3,.lithophageTendril4,.lithophageTendril5,.lithophageTendril6,
  .lithophageTendril7,.lithophageTendril8,.lithophageTendril9,.lithophageTendril10,.lithophageTendril11,.lithophageTendril12,
};
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=tierIds++tendrilIds++[_]meshlib.Id{.lithophageCrystal,.germinatorPool,.germinatorPour,.itemPod};
/// what a lithophage is: grown from its seed, one tile across, a pale
/// store that swaps sap, drawn by itself (its coral grows on with its age),
/// stony and swaying only a little
pub const def:st.Def=.{.item=.lithophage,.lineage=.parasitic,.size=1,.mesh=.lithophage,.store=true,.grow=6,.bare=true,.sway=0.2,.tall=0.6,.sap=0.32,
  // it draws faster in light (docs/radiant-plants.md), more the further it reaches (`draws`)
  .light=.boost,.draws=3};
/// how far it reaches once grown (tiles)
pub const grownReach:i32=2;
/// the light it draws: `Def.draws`, and one more for each tile it reaches
/// past the first two (it does more the further it reaches)
pub fn draws(s:*const st.Structure)f32{return def.draws+m.f(reachAt(s.state.lithophage.age)-grownReach);}
/// how old it is (s, from when it is grown) when it first reaches a tile
/// further: five of the garden's days (a day 600 s); each tile after
/// comes when its age has tripled again
pub const firstStep:f32=3000;
/// how many times older it must grow for each tile further it reaches
const tripling:f32=3;
/// how fast its last tier creeps on, past its start (it never ends: half
/// grown on a step of its life after it begins, two thirds after two)
const lastPace:f32=1;
/// the most tendrils it sends out at once (the nearest nodes first)
pub const most=12;
/// how far it ever looks for nodes, however old (tiles)
const farthest:i32=40;
/// seconds it takes to draw one unit up a tendril (or eat a shard it was fed)
pub const draw:f32=3;
/// how much grit a crystal holds before it is sapped
pub const crystal:u32=12;
/// the grit a unit of grit drawn refines into (a root-digger's gives one)
pub const refined:u32=2;
/// the grit a ley shard refines into
pub const leyWorth:u32=3;
/// seconds between one grit sapped and the next
pub const sap:f32=1;
/// grit it holds in its cup before it stops sapping
pub const buffer=16;
/// the most ley shards it takes in
const stock=10;
/// how fast a tendril creeps out to its node (tiles a second)
const creep:f32=0.4;
/// how fast a tendril withers once its node is gone (tiles a second)
const wither:f32=0.8;
/// the crystal's size when whole (of its mesh)
const crystalSize:f32=0.75;
/// how fast it turns slowly on its bud (radians a second)
const crystalTurn:f32=0.25;
/// the size of the mote a drawn-up mineral shows as, running up a tendril
const moteSize:f32=0.3;
/// how brightly that mote glows
const moteGlow:f32=0.7;
/// the grit in its cup: a lens this wide empty .. full
const poolW=m.Vice(f32,2){0.012,0.03};
/// how brightly the grit in its cup glows
const poolGlow:f32=0.35;
/// how brightly the stream of sapped grit glows
const streamGlow:f32=0.75;
/// how brightly its coral glows at rest, and how much more at work
const glow:f32=0.12;
/// (how much more at work)
const glowActive:f32=0.25;
/// how its crystals are drawn: whole, as the ground's are, the light
/// glinting off them and shining back through (its coral is stone, untouched)
const crystalFade:f32=1;
/// how brightly its tendrils glow: the cracks they run under shining
const tendrilGlow:f32=0.22;
/// how much of its mesh's reach the culling sphere takes: its widest tier
const meshReach:f32=1.8;
/// how far its tendrils wander off the straight line to their nodes, as a
/// share of how far they run (at most `wanderMost` tiles)
const wanderShare:f32=0.12;
/// (at most this many tiles)
const wanderMost:f32=0.35;
/// one tendril: the node it digs into and how far it has crept there
pub const Tendril=struct{
  /// the node's tile, off its own
  at:Off=.{0,0},
  /// how far it has crept out to it (0..1)
  r:f32=0,
};
/// what a lithophage remembers: its age, its tendrils, the crystal
/// budding on it, the mineral being drawn up and the grit still to sap
pub const State=struct{
  /// how long it has lived since it was grown (s)
  age:f32=0,
  /// its tendrils, the first `count` in use
  tendrils:[most]Tendril=@splat(.{}),
  /// how many tendrils it has out
  count:u8=0,
  /// how much grit the crystal has condensed (of `crystal`)
  fill:u32=0,
  /// how far the mineral being drawn up is (0..1)
  t:f32=0,
  /// where it is drawn from (its node's tile off its own; none: one it was fed)
  from:?Off=null,
  /// what is being drawn (null: nothing)
  drawing:?items.Item=null,
  /// grit still to sap from the crystal
  sap:u8=0,
  /// how far along the next grit sapped is (0..1)
  sapT:f32=0,
  /// which tendril draws next
  turn:u8=0,
};
/// how far along its life it is, `age` seconds after it was grown: from
/// 0 to 1 over its first step, then one more each time its age triples
pub fn level(age:f32)f32{
  if(age<firstStep)return@max(age,0)/firstStep;
  return 1+@log(age/firstStep)/@log(tripling);
}
/// how far it reaches (tiles), `age` seconds after it was grown: 2, then
/// one more each time its age triples past its first step
pub fn reachAt(age:f32)i32{return grownReach+m.floorTo(i32,level(age)+1e-4);}
/// how far its coral's tier `n` (1..`mesh.tiers`) has grown at `lv` along
/// its life: each over the step before the tile it reaches with; the last
/// creeping on forever, ever more slowly
pub fn tierGrown(n:usize,lv:f32)f32{
  // how far past this tier's start it is
  const past=lv-m.f(n-1);
  if(n<mesh.tiers)return m.clamp01(past);
  return if(past<=0)0 else 1-1/(1+lastPace*past);
}
/// what a mineral refines into: a ley shard `leyWorth` grit, grit `refined`
fn worth(item:items.Item)u32{return if(item==.leyShard)leyWorth else refined;}
/// whether an item is a mineral it eats (grit or ley shard)
fn mineral(item:items.Item)bool{return item==.grit or item==.leyShard;}
/// how far a tile offset lies (tiles)
fn far(o:Off)f32{return@sqrt(m.f(o[0])*m.f(o[0])+m.f(o[1])*m.f(o[1]));}
/// whether a tile offset lies within `reach`: its centre within half a
/// tile past it
fn within(o:Off,reach:i32)bool{
  // the offset's squared length, and the reach's
  const d=@as(i32,o[0])*o[0]+@as(i32,o[1])*o[1];
  return d>0 and d<=reach*reach+reach;
}
/// a mineral node on the tile `o` off (x, y), if any: its chunk, tile and
/// what it gives (null when spent, built over, or not a mineral)
fn nodeAt(w:*World,x:i32,y:i32,o:Off)?struct{c:*ck.Chunk,t:usize,item:items.Item}{
  // the tile looked at, its chunk and its index there
  const tx=x+o[0];
  const ty=y+o[1];
  const c=w.chunkOfTile(tx,ty) orelse return null;
  const t=ck.localIndex(tx,ty);
  if(c.res[t]==0 or c.occ[t]!=.none)return null;
  // the node that ground holds
  const node=resources.of(c.kind[t]) orelse return null;
  if(!mineral(node.item))return null;
  return.{.c=c,.t=t,.item=node.item};
}
/// whether one of its tendrils already digs (or creeps toward) tile `o`
fn hasTendril(l:*const State,o:Off)bool{
  for(l.tendrils[0..l.count])|t|if(t.at[0]==o[0] and t.at[1]==o[1])return true;
  return false;
}
/// its tendrils creep out to the nodes in its reach and wither from those
/// gone (a withered one lets go); then one more sets out for the nearest
/// node in reach none digs yet, while it has room for one.
fn tend(w:*World,self:*st.Structure,dt:f32)void{
  // its remembered state, and how far it reaches now
  const l=&self.state.lithophage;
  const reach=@min(reachAt(l.age),farthest);
  // how many tendrils it keeps
  var kept:u8=0;
  for(0..l.count)|k|{
    // this tendril, whether its node is still there to dig, and how far it runs
    var t=l.tendrils[k];
    const there=within(t.at,reach) and nodeAt(w,self.x,self.y,t.at)!=null;
    const d=far(t.at);
    t.r=st.reaching(t.r,there,dt*creep/d,dt*wither/d);
    if(t.r<=0 and !there)continue;
    l.tendrils[kept]=t;
    kept+=1;
  }
  l.count=kept;
  if(l.count>=most)return;
  // the nearest node in reach no tendril digs yet, and how far it is (squared)
  var best:?Off=null;
  var bestD:i32=m.maxInt(i32);
  var dy:i32=-reach;
  while(dy<=reach):(dy+=1){
    // the column looked along
    var dx:i32=-reach;
    while(dx<=reach):(dx+=1){
      // the offset, and its squared length
      const o=Off{@intCast(dx),@intCast(dy)};
      const d=dx*dx+dy*dy;
      if(d>=bestD or !within(o,reach) or hasTendril(l,o))continue;
      if(nodeAt(w,self.x,self.y,o)==null)continue;
      best=o;
      bestD=d;
    }
  }
  if(best)|o|{
    l.tendrils[l.count]=.{.at=o};
    l.count+=1;
  }
}
/// ages, tends its tendrils, then either saps its whole crystal into its
/// cup a grit at a time, or draws a unit up a tendril that has reached its
/// node (fed shards first) and refines it into the crystal. Returns true
/// while working.
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  _=st.handOff(ctx,i);
  // the lithophage itself, and its remembered state
  const self=ctx.ss.get(i);
  const l=&self.state.lithophage;
  l.age+=dt;
  tend(ctx.w,self,dt);
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
  // drawing a unit up: from what it was fed first, else a node a tendril
  // has reached, in turn
  if(l.drawing==null){
    if(self.inv.take(.leyShard,1)){
      l.drawing=.leyShard;
      l.from=null;
    }else for(0..l.count)|k|{
      // the tendril tried now, starting from whose turn it is
      const at=(l.turn+k)%l.count;
      const t=l.tendrils[at];
      if(t.r<1)continue;
      // the node it digs
      const n=nodeAt(ctx.w,self.x,self.y,t.at) orelse continue;
      n.c.res[n.t]-=1;
      l.drawing=n.item;
      l.from=t.at;
      l.turn=@intCast((at+1)%l.count);
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
    l.sap=@intCast(l.fill);
    l.fill=0;
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
/// the four control points of the curve tendril `t` creeps along from its
/// coral at `ctr` out to its node, wandering its own way off the straight
/// line, and which way is across it
fn tendrilCurve(s:*const st.Structure,t:Tendril,ctr:V3)struct{ctrl:[4]V3,side:V3,len:f32}{
  // where its node is, how far, which way, and which way is across
  const node=ctr+v3(m.f(t.at[0]),0,m.f(t.at[1]));
  const d=far(t.at);
  const dir=m.norm(node-ctr);
  const side=m.norm(m.cross(dir,v3(0,1,0)));
  // how far it wanders, each of its two middle points its own way
  const spread=@min(d*wanderShare,wanderMost);
  const h=rng.hash2(m.floorTo(u64,s.seed*1e4),t.at[0],t.at[1]);
  const w1=(rng.unit(h)-0.5)*2*spread;
  const w2=(rng.unit(h^0x5eed)-0.5)*2*spread;
  // lifted a hair off the ground, so its cracks lie on it
  const lift=v3(0,0.004,0);
  return.{.ctrl=.{ctr+lift,ctr+lift+dir*m.splat3(d/3)+side*m.splat3(w1),ctr+lift+dir*m.splat3(d*2/3)+side*m.splat3(w2),node+lift},.side=side,.len=d};
}
/// where along a tendril's curve (0 its coral .. 1 its node) a point lies:
/// the same Catmull-Rom part.vert bends its mesh along, its ends extended in line
fn curveAt(c:[4]V3,u:f32)V3{
  // which of its three stretches, and how far along that one
  const s=m.clamp01(u)*3;
  const i=@min(m.floorTo(usize,s),2);
  const f=s-m.f(i);
  // the stretch's ends, and the points either side of them
  const b=c[i];
  const e=c[i+1];
  const a=if(i==0)b*m.splat3(2)-e else c[i-1];
  const d=if(i==2)e*m.splat3(2)-b else c[i+2];
  return m.catmullRom(a,b,e,d,f);
}
/// which of its tendril meshes is nearest `len` tiles long
fn tendrilMesh(len:f32)usize{
  // the nearest found yet, and how far off its length it is (as a ratio)
  var best:usize=0;
  var off:f32=m.inf(f32);
  for(mesh.tendrilLens,0..)|l,k|{
    // how far apart the two lengths are, as a ratio
    const r=@max(len/l,l/len);
    if(r<off){
      best=k;
      off=r;
    }
  }
  return best;
}
/// its coral (the young body and every tier grown on as far as its age),
/// its tendrils out to their nodes, a mote of each unit drawn up one, the
/// crystal budding on its coral, the stream of grit it saps into its cup
/// and the grit standing there.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  // its remembered state, its frame in the world, and how far along its life
  const l=&s.state.lithophage;
  const base=s.place(ctr);
  const lv=level(l.age);
  // the look its coral shares: stony, swaying a little, its crystals see-through
  const body:Look=.{.glow=glow+glowActive*s.activity,.phase=s.seed,.fade=crystalFade,.sway=def.sway,.tall=def.tall,.grown=s.grown};
  try out.emitReaching(def.mesh,base,body,meshReach);
  for(tierIds,1..)|id,n|{
    // how far this tier has grown on (never past the coral it grows from)
    const g=@min(tierGrown(n,lv),s.grown);
    if(g<=0)continue;
    var look=body;
    look.grown=g;
    try out.emitReaching(id,base,look,meshReach);
  }
  for(l.tendrils[0..l.count],0..)|t,k|{
    if(t.r<=0)continue;
    // its curve, and the mesh nearest its length
    const c=tendrilCurve(s,t,ctr);
    const id=tendrilMesh(c.len);
    try out.emitCurve(tendrilIds[id],c.ctrl,c.side,mesh.tendrilLens[id],1,.{.glow=tendrilGlow,.phase=s.seed+m.f(k)*0.1,.fade=crystalFade,.grown=t.r});
  }
  if(s.grown<1)return;
  // the look every part of it shares: swaying with the coral
  const sway:Look=.{.phase=s.seed,.sway=def.sway,.tall=def.tall};
  // where the crystal buds, in the world
  const bud=m.mulPoint(base,mesh.budAt);
  // a unit being drawn: down its tendril from the node, then up the coral
  if(l.drawing)|it|{
    // where the mote is now
    const p=if(l.from)|o|blk:{
      // the tendril it runs along (back from its node)
      const c=tendrilCurve(s,.{.at=o,.r=1},ctr).ctrl;
      break:blk if(l.t<0.7)curveAt(c,1-l.t/0.7)else m.lerpV(ctr+v3(0,0.05,0),bud,m.smooth((l.t-0.7)/0.3));
    }else m.lerpV(ctr+v3(0,0.05,0),bud,m.smooth(l.t));
    // the mote's look: brighter, its mineral's colour
    var look=sway;
    look.glow=moteGlow;
    look.tint=color.Rgba8.of(it.info().col).toF4();
    look.drop=p[1]-ctr[1];
    try out.emit(.itemPod,m.chain(&.{m.translate(p+v3(0,0.03,0)),m.scale3(m.splat3(moteSize*@sin(m.pi*m.clamp01(l.t*1.1))))}),look);
  }
  // the crystal: grown by what has condensed, shrinking as it is sapped
  const whole=if(l.sap>0)(m.f(l.sap)-l.sapT)/m.f(crystal)else(m.f(l.fill)+(if(l.drawing)|it|m.f(worth(it))*m.smooth(m.clamp01(l.t*2-1))else 0))/m.f(crystal);
  if(whole>0){
    // the crystal's look: swaying from the bud's height
    var look=sway;
    look.drop=mesh.budAt[1];
    try out.emit(.lithophageCrystal,m.mul(base,m.chain(&.{m.translate(mesh.budAt),m.rotY(tf*crystalTurn+s.seed*4),m.rotZ(-0.5),m.scale3(m.splat3(crystalSize*@sqrt(m.clamp01(whole))))})),look);
  }
  // sapping: a stream off the crystal's foot down into the cup
  const ess=color.Rgba8.of(items.Item.grit.info().col).toF4();
  if(l.sap>0 and s.inv.count(.grit)<buffer){
    // the crystal's foot and the cup in the world, and the fall between them
    const lip=m.mulPoint(base,mesh.budAt-v3(0.02,0.03,0));
    const cup=m.mulPoint(base,mesh.cupAt+v3(0,0.02,0));
    const d=cup-lip;
    // the stream's curve: out level from the crystal, then down into the cup
    const ctrl=[4]V3{lip,lip+v3(d[0]*0.4,0.01,d[2]*0.4),lip+v3(d[0]*0.9,d[1]*0.5,d[2]*0.9),cup};
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
/// starved (no node reached, nothing fed), or drawing toward a crystal,
/// with how far it reaches.
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  // its remembered state, and the grit in its cup
  const l=&s.state.lithophage;
  const held=s.inv.count(.grit);
  if(l.sap>0){
    _=try d.print(x,y,style.textBody,style.white,txt.s.describe.lithSaps,.{held,buffer});
    try d.tendril(x+style.descBarX,y+2,style.descBarW,style.barH,style.gold,1-(m.f(l.sap)-l.sapT)/m.f(crystal),0.3);
    return;
  }
  // how many tendrils have reached their nodes
  var dug:u32=0;
  for(l.tendrils[0..l.count])|t|{if(t.r>=1)dug+=1;}
  if(l.drawing==null and dug==0){
    _=try d.print(x,y,style.textBody,style.dim,txt.s.describe.lithStarved,.{reachAt(l.age),held,buffer});
    return;
  }
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.lithDraws,.{dug,reachAt(l.age),l.fill,crystal,held,buffer});
  try d.tendril(x+style.descBarX,y+2,style.descBarW,style.barH,style.lith,(m.f(l.fill)+l.t)/m.f(crystal),0.3);
}
/// its bulb: a pale stone coral out of the seed, forking, crystals budding
/// at its tips, a bead of grit running down it (it draws stone out of the
/// ground round it).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  try ic.stem(.{.{0,iconKit.topAt},.{0.02,0.25},.{-0.02,0.4},.{0,0.52}},0.12,iconCoral);
  for([_]f32{-1,1})|sx|{
    try ic.stem(.{.{0.01*sx,0.4},.{0.16*sx,0.48},.{0.26*sx,0.62},.{0.3*sx,0.8}},0.08,iconCoral);
    try ic.glow(.{0.3*sx,0.86},0.14,iconGemGlow);
    try ic.gem(.{0.3*sx,0.86},0.1,iconGem);
  }
  try ic.stem(.{.{0,0.5},.{0.01,0.62},.{-0.01,0.75},.{0,0.88}},0.08,iconCoral);
  try ic.gem(.{0,0.95},0.12,iconGem);
  // how far down the grit bead has run (0..1)
  const k=@mod(ic.t*0.7+ic.phase,1);
  try ic.bud(.{0.06,m.lerp(0.45,iconKit.topAt,k)},0.06,iconEss,1-k);
  try ic.coat(col);
}
/// the bone pale of its coral in its bulb
const iconCoral:Color=.{215,208,218,255};
/// the clear lilac of the crystals budding on it
const iconGem:Color=.{215,200,255,255};
/// the soft glow behind those crystals
const iconGemGlow:Color=.{200,185,255,70};
/// the stony grey of the grit bead running down it
const iconEss:Color=.{150,140,130,255};
// ---- tests ----
/// bare soil round (2, 2), grit nodes holding `res` at each of `at`
fn fixture(w:*World,res:ck.Res,at:[]const Off)!void{
  // the bare ground's chunk
  const c=try bench.ground(w,.{.width=10,.depth=9,.bare=true});
  for(at)|o|c.res[@as(usize,@intCast(2+o[1]))*ck.sizeTiles+@as(usize,@intCast(2+o[0]))]=res;
}
/// how much is left in the node on the tile `o` off (2, 2)
fn left(w:*World,o:Off)ck.Res{return w.chunkOfTile(2+o[0],2+o[1]).?.res[@as(usize,@intCast(2+o[1]))*ck.sizeTiles+@as(usize,@intCast(2+o[0]))];}
/// all the grit a lithophage has made of what it drew, wherever it is
/// now: in its cup, still to sap, or condensed in its crystal
fn made(s:*const st.Structure)u32{
  // its remembered state
  const l=&s.state.lithophage;
  return s.inv.count(.grit)+l.sap+l.fill;
}
test"it reaches 2 tiles grown, one further each time its age triples"{
  try testing.expectEqual(@as(i32,2),reachAt(0));
  try testing.expectEqual(@as(i32,2),reachAt(firstStep-1));
  try testing.expectEqual(@as(i32,3),reachAt(firstStep));
  try testing.expectEqual(@as(i32,3),reachAt(firstStep*3-1));
  try testing.expectEqual(@as(i32,4),reachAt(firstStep*3));
  try testing.expectEqual(@as(i32,5),reachAt(firstStep*9));
  try testing.expectEqual(@as(i32,6),reachAt(firstStep*27));
  // its coral: each tier grows over the step before it, the last never quite done
  try testing.expectEqual(@as(f32,0),tierGrown(1,0));
  try testing.expectEqual(@as(f32,1),tierGrown(1,level(firstStep)));
  try testing.expectEqual(@as(f32,0),tierGrown(2,level(firstStep)));
  try testing.expect(tierGrown(mesh.tiers,12)<1 and tierGrown(mesh.tiers,12)>tierGrown(mesh.tiers,4));
}
test"its reach is a disc: a knight's move in at 2, the corner out"{
  try testing.expect(within(.{2,1},2));
  try testing.expect(!within(.{2,2},2));
  try testing.expect(!within(.{3,0},2));
  try testing.expect(within(.{3,0},3));
  try testing.expect(!within(.{0,0},2));
}
test"a lithophage refines what its tendrils draw: each grit unit into two"{
  // the allocator, and the world with a node beside it and one two tiles off
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w,20,&.{.{1,0},.{0,2}});
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,2,2,.lithophage,0,0));
  // the lithophage
  const id=ss.at(&w,2,2).?;
  try bench.run(&ss,&w,&plants,&g,def.grow+60);
  // both nodes drawn from, every unit refined into two grit (the one
  // being drawn up now aside)
  const drawn:u32=(20-left(&w,.{1,0}))+(20-left(&w,.{0,2}));
  try testing.expect(left(&w,.{1,0})<20 and left(&w,.{0,2})<20);
  const s=ss.get(id);
  const pending:u32=if(s.state.lithophage.drawing!=null)1 else 0;
  try testing.expectEqual(refined*(drawn-pending),made(s));
  try testing.expect(s.inv.count(.grit)>0);
  try testing.expect(ss.output(id)==.grit);
  try testing.expect(!ss.gives(id,.leyShard));
}
test"a lithophage reaches a node three tiles off only once five days old"{
  // the allocator, and the world with a node three tiles off
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w,20,&.{.{3,0}});
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,2,2,.lithophage,0,0));
  // the lithophage
  const id=ss.at(&w,2,2).?;
  try bench.run(&ss,&w,&plants,&g,def.grow+30);
  try testing.expectEqual(@as(u8,0),ss.get(id).state.lithophage.count);
  try testing.expectEqual(@as(ck.Res,20),left(&w,.{3,0}));
  // five days on, it reaches it
  ss.get(id).state.lithophage.age=firstStep;
  try bench.run(&ss,&w,&plants,&g,30);
  try testing.expectEqual(@as(u8,1),ss.get(id).state.lithophage.count);
  try testing.expect(left(&w,.{3,0})<20);
}
test"a lithophage eats the ley shards it is fed, each worth three grit"{
  // the allocator, and the world with no node
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w,0,&.{});
  // no plants, the structures, and what the gardener understands
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,2,2,.lithophage,0,0));
  // the lithophage
  const id=ss.at(&w,2,2).?;
  try testing.expectEqual(@as(u16,4),ss.insert(&g,id,.leyShard,4));
  try testing.expectEqual(@as(u16,0),ss.insert(&g,id,.fibre,2));
  // grit it never takes: what it holds is what it sapped
  try testing.expectEqual(@as(u16,0),ss.insert(&g,id,.grit,2));
  try bench.run(&ss,&w,&plants,&g,def.grow+draw*4+sap*crystal+2);
  try testing.expectEqual(@as(u32,leyWorth*4),ss.get(id).inv.count(.grit));
  // nothing round it, nothing fed: it rests
  try bench.run(&ss,&w,&plants,&g,30);
  try testing.expectEqual(@as(u32,leyWorth*4),ss.get(id).inv.count(.grit));
  try testing.expect(ss.get(id).activity<0.01);
}
test"a lithophage's grit is carried off by a conduit behind it"{
  // the allocator, and the world with its node
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w,30,&.{.{1,0}});
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
  try testing.expect(ss.get(ss.at(&w,2,4).?).inv.count(.grit)>=crystal);
}
test"its state is saved and read back whole"{
  // a lithophage's state well on in its life
  const gpa=testing.allocator;
  var a:State=.{.age=firstStep*4,.count=2,.fill=5,.t=0.4,.from=.{-2,1},.drawing=.grit,.sap=3,.sapT=0.25,.turn=1};
  a.tendrils[0]=.{.at=.{-2,1},.r=1};
  a.tendrils[1]=.{.at=.{0,3},.r=0.5};
  // written as a record, and read back into a fresh one
  var buf:std.ArrayList(u8)=.empty;
  defer buf.deinit(gpa);
  try record.write(State,gpa,&buf,&a);
  var b:State=.{};
  try record.read(State,gpa,buf.items,&b);
  try testing.expectEqualDeep(a,b);
}
