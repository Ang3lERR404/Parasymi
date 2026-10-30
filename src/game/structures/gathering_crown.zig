//! GATHERING CROWN: a symbiote that gathers for the garden. It sends a
//! woven root out to every plant on the tiles within two of it and, once a
//! root has reached its plant, gathers what that plant has ripened, a unit
//! at a time and each plant in turn, into the pod at its heart: one crown
//! harvests a whole bed, where conduits need a root beside every plant.
//! What it gathers goes to a neighbour that wants it, or a conduit behind
//! it pulls it away; with nowhere to go it holds `BUFFER`, then rests.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const testing=std.testing;
const m=lib.engine.core.math;
const color=lib.engine.core.color;
const ck=lib.ck;
const World=lib.world.World;
const items=lib.items;
const Plants=lib.plants.Plants;
const st=lib.structures;
const bench=st.bench;
const iconKit=lib.icon;
const txt=lib.txt;
const prog=lib.progression;
const style=lib.style;
const Parts=lib.parts.Parts;
const Draw=lib.engine.ui.draw.Draw;
const Color=lib.engine.ui.draw.Color;
const meshlib=lib.meshlib;
const mesh=lib.gatheringCrown;
const v3=m.v3;
/// a ganglion grown beside it: the study of shared nerves
pub const meets:st.Meeting=.{.kind=.ganglion,.found=.crownAndNerve};
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.bellyLump,.itemPod,.crownRoot1,.crownRoot2,.crownRoot3,.crownRoot4,.crownRoot5};
pub const def:st.Def=.{.item=.gatheringCrown,.size=1,.mesh=.gatheringCrown,.store=true,.grow=5,.sway=0.6,.tall=0.45,.sap=0.35};
/// how far it reaches (tiles, every way), and the tiles that makes
pub const reachTiles=2;
const side=2*reachTiles+1;
const tiles=side*side;
/// seconds between one gathering and the next, and most it holds
pub const gather:f32=1.5;
pub const buffer=12;
/// how fast a root grows out to a plant (its length a second at one tile
/// out; farther ones take longer) and withers when the plant is gone
const rootGrow:f32=0.5;
const rootWither:f32=1.2;
const rootFlutter:f32=0.3;
/// what it gathers travels up the root to the pod this fast (its length a
/// second), arcing this high
const carryRate:f32=1.5;
const arc:f32=0.18;
const moteSize:f32=0.45;
const moteGlow:f32=0.8;
/// what it holds hangs in the pod, in a ring, bobbing
const ringRadius:f32=0.45;
const lumpR:f32=0.024;
const lumpGrow:f32=0.02;
const bobAmount:f32=0.01;
const turnRate:f32=0.2;
const glow:f32=0.2;
pub const State=struct{
  /// how far its root toward each tile round it has grown (0..1), by
  /// `index` of the tile's offset
  reach:[tiles]f32=@splat(0),
  /// the tile it gathers from next, and time since it last gathered
  turn:u8=0,
  t:f32=0,
  /// the last thing gathered, travelling up its root (from which tile,
  /// how far along, what)
  from:?u8=null,
  carry:f32=0,
  carried:items.Item=.essence,
};
fn offset(i:usize)[2]i32{return.{@as(i32,@intCast(i%side))-reachTiles,@as(i32,@intCast(i/side))-reachTiles};}
/// the plant whose own tile (its corner, for one larger than a tile) is
/// `i` round (x, y), if any: one root to each plant
fn plantAt(ctx:st.Ctx,x:i32,y:i32,i:usize)?ck.PlantId{
  const o=offset(i);
  if(o[0]==0 and o[1]==0)return null;
  const p=ctx.plants.at(ctx.w,x+o[0],y+o[1]) orelse return null;
  const s=ctx.plants.list.slice();
  if(s.items(.x)[p.idx()]!=x+o[0] or s.items(.y)[p.idx()]!=y+o[1])return null;
  return p;
}
/// which root mesh reaches the tile at offset `o`
fn rootFor(o:[2]i32)meshlib.Id{
  const d2=o[0]*o[0]+o[1]*o[1];
  return switch(d2){
    1=>.crownRoot1,
    2=>.crownRoot2,
    4=>.crownRoot3,
    5=>.crownRoot4,
    else=>.crownRoot5,
  };
}
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  _=st.handOff(ctx,i);
  const self=ctx.ss.get(i);
  const c=&self.state.gatheringCrown;
  var roots:usize=0;
  for(&c.reach,0..)|*r,k|{
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
    const at:u8=@intCast((c.turn+k)%tiles);
    if(c.reach[at]<1)continue;
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
pub fn wants(_:*const st.Structure,_:*const prog.Progression,_:items.Item)u32{return 0;}
/// the oldest thing it gathered.
pub fn output(s:*const st.Structure)?items.Item{return s.firstHeld(st.Structure.anything);}
pub fn gives(s:*const st.Structure,item:items.Item)bool{return s.inv.count(item)>0;}
/// its roots out to the plants round it, what it last gathered travelling
/// up one, and what it holds hanging in its pod.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  const c=&s.state.gatheringCrown;
  for(c.reach,0..)|r,k|{
    if(r<=0)continue;
    const o=offset(k);
    try out.emit(rootFor(o),m.chain(&.{m.translate(ctr),m.rotY(m.atan2(-m.f(o[1]),m.f(o[0])))}),.{
      .flutter=rootFlutter,.phase=s.seed+m.f(k)*0.07,.grown=r*s.grown,.glow=glow,
    });
  }
  if(s.grown<1)return;
  const base=s.place(ctr);
  if(c.from)|k|{
    const o=offset(k);
    const from=ctr+v3(m.f(o[0]),0.05,m.f(o[1]));
    const to=m.mulPoint(base,mesh.podAt);
    const p=m.lerpV(from,to,m.smooth(c.carry))+v3(0,arc*@sin(m.pi*c.carry),0);
    try out.emit(.itemPod,m.chain(&.{m.translate(p),m.scale3(m.splat3(moteSize*@sin(m.pi*m.clamp01(c.carry*1.1+0.05))))}),.{
      .glow=moteGlow,.tint=color.Rgba8.of(c.carried.info().col).toF4(),
    });
  }
  const n=s.inv.used();
  var j:usize=0;
  for(s.inv.slot)|slot|{
    const it=slot orelse continue;
    const a=m.ratio(j,n)*m.tau+tf*turnRate+s.seed*6;
    const ring=if(n==1)0 else mesh.podR[0]*ringRadius;
    const at=mesh.podAt+v3(@cos(a)*ring,bobAmount*@sin(tf*0.9+m.f(j)*2),@sin(a)*ring);
    const r=lumpR+lumpGrow*m.ratio(it.n,buffer);
    try s.emitLump(out,base,at,r,it.item,glow);
    j+=1;
  }
}
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  const c=&s.state.gatheringCrown;
  var n:u32=0;
  for(c.reach)|r|{if(r>=1)n+=1;}
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
const iconSap:Color=.{255,190,90,255};
const iconGlow:Color=.{255,190,90,80};
const iconPetal:Color=.{245,190,100,255};
// ---- tests ----
const testDt=bench.testDt;
fn ripe(gpa:Allocator,w:*World,plants:*Plants,x:i32,y:i32,essence:f32)!void{
  try testing.expect(try plants.placeEx(gpa,w,x,y,.{.x=x,.y=y,.chunk=undefined,.tile=undefined,.sp=.lumenroot,.seed=0,.growth=1,.essence=essence}));
}
test"a gathering crown roots out to every plant within two tiles and gathers them"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=7,.depth=7});
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
  const id=ss.at(&w,3,3).?;
  try testing.expectEqual(@as(u32,8),ss.get(id).inv.count(.essence));
  // the one three tiles out is left alone
  const far=plants.at(&w,6,3).?;
  try testing.expectEqual(@as(f32,2),plants.list.items(.essence)[far.idx()]);
}
test"a gathering crown hands what it gathers to a cache beside it"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  _=try bench.ground(&w,.{.width=7,.depth=7});
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
