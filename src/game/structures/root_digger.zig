//! ROOT-DIGGER: the first gathering automation. Its roots work the resource
//! node beside it, drawing out one item at a time (the same item the wolf
//! would gather there) into a small buffer. Conduits behind it pull from
//! that buffer; any other structure beside it that wants the item is fed
//! directly. When the node runs dry it idles, and it takes up any node that
//! appears beside it later by itself. Its digging root reaches out to the
//! node it works and withers back from one gone; what it draws out swells
//! up the root home into the gourd its knot of roots grips.
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
const iconKit=lib.icon;
const txt=lib.txt;
const prog=lib.progression;
const resources=lib.resources;
const style=lib.style;
const Parts=lib.parts.Parts;
const Draw=lib.engine.ui.draw.Draw;
const Color=lib.engine.ui.draw.Color;
const play=lib.play;
const actions=lib.actions;
const Look=lib.parts.Look;
const mesh=lib.rootDigger;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.bellyLump,.diggerClod,.diggerRoot};
pub const def:st.Def=.{.item=.rootDigger,.size=1,.mesh=.rootDigger,.store=true,.grow=4,.sway=0.5,.tall=0.6};
/// seconds per item drawn from the node
pub const rate:f32=4;
/// items it holds before it stops digging
pub const buffer=8;
/// how fast its digging root reaches out to a node (its length a second)
/// and withers back from one gone
const rootGrow:f32=0.6;
const rootWither:f32=0.9;
const rootFlutter:f32=0.3;
const glow:f32=0.15;
const glowActive:f32=0.5;
/// each item drawn: over the first `PRISE` of it the root prises it loose,
/// clods of the node flung up about its claw, then it swells up the root's
/// core in its own colour, home into the gourd
const prise:f32=0.3;
const clods=4;
const clodSize:f32=0.034;
const clodFling:f32=0.13;
const clodOut:f32=0.11;
/// what it has dug hangs in its gourd, in a ring, bobbing
const ringRadius:f32=0.45;
const lumpR:f32=0.022;
const lumpGrow:f32=0.018;
const bobAmount:f32=0.008;
const turnRate:f32=0.25;
/// its describe bar sits further right (a longer line) and is shorter
const barX:f32=300;
const barW:f32=60;
/// the node being worked: which side it lies on, what it yields, and how far
/// along the current item is.
pub const Dig=struct{
  dir:m.Dir,
  item:items.Item,
  t:f32=0,
};
pub const State=struct{
  /// null while there is no node beside it
  dig:?Dig=null,
  /// how far its digging root toward each side has reached (0..1)
  reach:[4]f32=@splat(0),
};
/// it roots in living ground only.
pub fn ground(k:ck.Kind)bool{return k==.soil or k==.moss;}
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  const self=ctx.ss.get(i);
  _=st.handOff(ctx,i);
  const d=&self.state.rootDigger;
  const found=findNode(ctx.w,self.x,self.y,if(d.dig)|dg|dg.dir else 0);
  // its root reaches out to the node it works, and withers from any other
  for(&d.reach,0..)|*r,k|{
    const there=if(found)|f|f.dir==k else false;
    r.*=if(there)@min(1,r.*+dt*rootGrow/mesh.root.reachDistance)else@max(0,r.*-dt*rootWither);
  }
  if(found==null){
    d.dig=null;
    return false;
  }
  const f=found.?;
  if(d.dig==null or d.dig.?.dir!=f.dir)d.dig=.{.dir=f.dir,.item=f.item};
  const dg=&d.dig.?;
  if(self.inv.total()>=buffer)return false;
  dg.t+=dt;
  if(dg.t<rate)return true;
  dg.t-=rate;
  f.chunk.res[f.tile]-=1;
  _=self.inv.add(dg.item,1);
  return true;
}
const Found=struct{
  dir:m.Dir,
  item:items.Item,
  chunk:*ck.Chunk,
  tile:usize,
};
/// an unoccupied resource node beside (x, y), trying `prefer` first so a
/// digger stays on the node it is working.
fn findNode(w:*const World,x:i32,y:i32,prefer:m.Dir)?Found{
  for(m.dirs)|k|{
    const dir=prefer+%k;
    const v=m.dirVec(dir);
    const c=w.chunkOfTile(x+v.x,y+v.z) orelse continue;
    const t=ck.localIndex(x+v.x,y+v.z);
    if(c.res[t]==0 or c.occ[t]!=.none)continue;
    const node=resources.of(c.kind[t]) orelse continue;
    return.{.dir=dir,.item=node.item,.chunk=c,.tile=t};
  }
  return null;
}
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
  const d=&s.state.rootDigger;
  const dg=d.dig;
  const working=dg!=null and s.inv.total()<buffer;
  const k=if(dg)|g|g.t/rate else 0;
  for(d.reach,0..)|r,side|{
    if(r<=0)continue;
    const dir:m.Dir=@intCast(side);
    const on=working and dg.?.dir==dir and r>=1;
    const v=m.dirVec(dir);
    const col:[4]u8=if(dg)|g|g.item.info().col else.{0,0,0,255};
    const c=color.Rgba8.of(col).toF4();
    try out.emit(.diggerRoot,m.chain(&.{m.translate(ctr),m.rotY(m.atan2(-m.f(v.z),m.f(v.x)))}),.{
      .glow=glow+glowActive*s.activity,.flutter=rootFlutter,.phase=s.seed+m.f(side)*0.1,.grown=r*s.grown,
      .carry=if(on and k>prise)m.smooth((k-prise)/(1-prise))else-1,.carryCol=.{c[0],c[1],c[2]},
    });
    if(!on or k>prise)continue;
    // clods of the node flung up about the claw, falling back
    const node=ctr+m.v3(m.f(v.x),0,m.f(v.z))*m.splat3(mesh.root.reachDistance);
    const t=k/prise;
    for(0..clods)|j|{
      const a=m.ratio(j,clods)*m.tau+s.seed*5+m.f(j)*0.7;
      const reach=clodOut*(0.7+0.3*m.f(j%2));
      const p=node+m.v3(@cos(a)*reach*t,clodFling*(0.8+0.2*m.f(j%3))*4*t*(1-t),@sin(a)*reach*t);
      const size=clodSize*(0.75+0.25*m.f(j%2))*(1-m.smooth(m.clamp01((t-0.85)/0.15)));
      try out.emit(.diggerClod,m.chain(&.{m.translate(p),m.rotY(a+t*4),m.rotX(t*3+m.f(j)),m.scale3(m.splat3(size))}),.{.phase=s.seed});
    }
  }
  // what it has dug, hanging in its gourd
  if(s.grown<1)return;
  const base=s.place(ctr);
  var n:usize=0;
  for(s.inv.slot)|slot|{if(slot!=null)n+=1;}
  var j:usize=0;
  for(s.inv.slot)|slot|{
    const it=slot orelse continue;
    const a=m.ratio(j,n)*m.tau+tf*turnRate+s.seed*6;
    const ring=if(n==1)0 else mesh.podR[0]*ringRadius;
    const at=mesh.podAt+m.v3(@cos(a)*ring,bobAmount*@sin(tf*0.9+m.f(j)*2),@sin(a)*ring);
    const r=lumpR+lumpGrow*m.ratio(it.n,buffer);
    try out.emit(.bellyLump,m.mul(base,m.chain(&.{m.translate(at),m.scale3(m.splat3(r))})),Look{
      .glow=glow,.phase=s.seed,.tint=color.Rgba8.of(it.item.info().col).toF4(),
      .sway=def.sway,.tall=def.tall,.drop=at[1],
    });
    j+=1;
  }
}
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  const n=s.inv.total();
  const dg=s.state.rootDigger.dig orelse {
    _=try d.print(x,y,style.textBody,style.dim,txt.s.describe.noNode,.{n,buffer});
    return;
  };
  const what=if(n>=buffer)txt.s.describe.diggerFull else txt.item(dg.item).name;
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.digs,.{what,n,buffer});
  try d.tendril(x+barX,y+2,barW,style.barH,style.digger,dg.t/rate,0.4);
}
// ---- tests ----
/// tests tick structures at 20 Hz
const testDt:f32=0.05;
/// a strip of soil at y = 0 (x = 0..5) with a moss node of `res` fibre at
/// (2, 0); the digger goes at (1, 0).
fn fixture(w:*World,res:ck.Res)!void{
  try w.stream(.{.x=0,.y=0},1,100);
  var it=w.map.valueIterator();
  while(it.next())|cp|@memset(&cp.*.res,0);
  const c=w.chunkOfTile(0,0).?;
  for(0..6)|x|for(0..2)|y|{
    const t=y*ck.sizeTiles+x;
    c.kind[t]=.soil;
    c.height[t]=1;
    c.res[t]=0;
  };
  c.kind[2]=.moss;
  c.res[2]=res;
}
fn run(ss:*st.Structures,w:*World,plants:*Plants,g:*prog.Progression,seconds:f32)!void{
  var t:f32=0;
  while(t<seconds):(t+=testDt)try ss.tick(testing.allocator,w,plants,g,testDt);
}
test"a digger beside a node draws one item every 4 seconds"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w,5);
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,1,0,.rootDigger,0,0));
  const id=ss.at(&w,1,0).?;
  try run(&ss,&w,&plants,&g,3.9);
  try testing.expectEqual(@as(u32,0),ss.get(id).inv.count(.fibre));
  try run(&ss,&w,&plants,&g,8.2);
  try testing.expectEqual(@as(u32,3),ss.get(id).inv.count(.fibre));
  try testing.expectEqual(@as(ck.Res,2),w.chunkOfTile(2,0).?.res[2]);
}
test"a digger with no node beside it idles"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w,5);
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,4,1,.rootDigger,0,0));
  try run(&ss,&w,&plants,&g,20);
  const s=ss.get(ss.at(&w,4,1).?);
  try testing.expectEqual(@as(u32,0),s.inv.total());
  try testing.expect(s.state.rootDigger.dig==null);
  w.chunkOfTile(0,0).?.kind[ck.sizeTiles+3]=.stone;
  try testing.expect(!ss.canPlace(&w,3,1,.rootDigger));
}
test"a digger with nowhere to send buffers 8, then pauses"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w,20);
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,1,0,.rootDigger,0,0));
  try run(&ss,&w,&plants,&g,60);
  try testing.expectEqual(@as(u32,buffer),ss.get(ss.at(&w,1,0).?).inv.total());
  try testing.expectEqual(@as(ck.Res,20-buffer),w.chunkOfTile(2,0).?.res[2]);
}
test"a conduit behind the digger carries its items away"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w,6);
  const c=w.chunkOfTile(0,0).?;
  c.kind[2]=.soil;
  c.res[2]=0;
  c.kind[ck.sizeTiles+1]=.moss;
  c.res[ck.sizeTiles+1]=6;
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,1,0,.rootDigger,0,0));
  try testing.expect(try ss.place(gpa,&w,2,0,.conduit,0,0));
  try testing.expect(try ss.place(gpa,&w,3,0,.sapCache,0,0));
  const conduit=ss.at(&w,2,0).?;
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
  const gpa=testing.allocator;
  var g=try play.Game.init(gpa,play.defaultSeed);
  defer g.deinit();
  const at=m.tileAt(g.player.pos);
  const c=g.world.chunkOfTile(at[0],at[1]).?;
  c.kind[ck.localIndex(at[0],at[1])]=.soil;
  try testing.expect(try g.structs.place(gpa,&g.world,at[0],at[1],.rootDigger,0,0));
  const id=g.structs.at(&g.world,at[0],at[1]).?;
  _=g.structs.get(id).inv.add(.grit,3);
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
const iconStone:Color=.{150,140,130,255};
const iconLey:Color=.{170,120,255,255};
