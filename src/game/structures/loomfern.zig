//! LOOMFERN: a fern that weaves fibre by itself, so the wolf need not pull
//! it from moss. Grown, it draws threads from its fronds and winds them
//! into a sheaf on its spindle, one fibre a sheaf, slowly from nothing;
//! fed essence (into its calyx), it weaves several sheaves from each at a
//! far quicker pace. Finished fibre goes to a neighbour that wants it, or
//! a conduit behind it pulls it away; with nowhere to go it lays its
//! sheaves at its foot until it holds `BUFFER`, then rests.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const testing=std.testing;
const m=lib.engine.core.math;
const ck=lib.ck;
const World=lib.world.World;
const items=lib.items;
const Plants=lib.plants.Plants;
const st=lib.structures;
const iconKit=lib.icon;
const txt=lib.txt;
const prog=lib.progression;
const style=lib.style;
const color=lib.engine.core.color;
const Parts=lib.parts.Parts;
const Look=lib.parts.Look;
const Draw=lib.engine.ui.draw.Draw;
const Color=lib.engine.ui.draw.Color;
const mesh=lib.loomfern;
const V3=m.V3;
const v3=m.v3;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.germinatorPool,.loomfernSheaf,.loomfernThread};
pub const def:st.Def=.{.item=.loomfern,.size=1,.mesh=.loomfern,.store=true,.grow=5,.sway=0.7,.tall=0.5};
/// a lithophage grown beside it: the study of woven stone
pub const meets:st.Meeting=.{.kind=.lithophage,.found=.loomAndStone};
/// seconds a fibre takes unfed, and fed
pub const slow:f32=12;
pub const fast:f32=3;
/// fibre woven from each essence it is fed
pub const perEssence=4;
/// fibre it holds before it rests, and most essence it takes in
pub const buffer=12;
const essenceStock=6;
/// threads drawn to the sheaf at once, each over its own stretch of the
/// weave (from, until it is wound in), the fronds they come from taking
/// turns weave by weave
const threads=3;
const threadAt=[threads]f32{0.0,0.2,0.4};
const threadDraw:f32=0.3;
const threadWind:f32=0.82;
/// where along a frond a thread is drawn from
const threadFrom:f32=0.72;
/// the sheaf turns this many times a weave (whole turns, so the next one
/// starts where it left off), and grows on the spindle from `SHEAF_FROM`
const sheafTurns:f32=2;
const sheafFrom:f32=0.08;
/// finished sheaves laid at its foot: one per this many fibre held, at most
/// `LAID`, this far out, leaning in against the bole
const perLaid=3;
const laid=4;
const laidOut:f32=0.17;
const laidLean:f32=1.15;
const laidSize:f32=0.85;
/// the essence in its calyx: a lens this wide empty .. full
const poolW=[2]f32{0.012,0.03};
const glow:f32=0.15;
const threadGlow=[2]f32{0.1,0.45};
const poolGlow:f32=0.3;
pub const State=struct{
  /// how far along the fibre being woven is (0..1)
  t:f32=0,
  /// fibre still to weave from the essence last taken in
  fed:u8=0,
  /// fibre woven so far (which fronds give the threads)
  woven:u32=0,
};
/// it roots in living ground only.
pub fn ground(k:ck.Kind)bool{return k==.soil or k==.moss;}
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  _=st.handOff(ctx,i);
  const self=ctx.ss.get(i);
  const f=&self.state.loomfern;
  if(self.inv.count(.fibre)>=buffer)return false;
  if(f.fed==0 and self.inv.take(.essence,1))f.fed=perEssence;
  f.t+=dt/(if(f.fed>0)fast else slow);
  if(f.t<1)return true;
  if(self.inv.add(.fibre,1)<1)return false;
  f.t=0;
  f.woven+%=1;
  if(f.fed>0)f.fed-=1;
  return true;
}
pub fn wants(s:*const st.Structure,_:*const prog.Progression,item:items.Item)u32{
  return if(item==.essence)essenceStock-|s.inv.count(.essence)else 0;
}
/// only the fibre it has woven leaves it.
pub fn output(s:*const st.Structure)?items.Item{return if(s.inv.count(.fibre)>0).fibre else null;}
pub fn gives(s:*const st.Structure,item:items.Item)bool{return item==.fibre and s.inv.count(.fibre)>0;}
/// the sheaf forming on its spindle and the threads drawn into it from the
/// fronds, the essence standing in its calyx, finished sheaves at its foot;
/// all of it sways with the fern.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,_:f32)Allocator.Error!void{
  if(s.grown<1)return;
  const f=&s.state.loomfern;
  const base=s.place(ctr);
  const sway:Look=.{.phase=s.seed,.sway=def.sway,.tall=def.tall,.glow=glow};
  const weaving=s.inv.count(.fibre)<buffer;
  const p=if(weaving)f.t else 0;
  const fed=f.fed>0 or s.inv.count(.essence)>0;
  // the sheaf: growing on the spindle as the weave goes, turning as it
  // winds the threads in
  const sheaf=m.smooth(m.clamp01((p-sheafFrom)/(1-sheafFrom)));
  if(sheaf>0){
    var look=sway;
    look.drop=mesh.sheafAt[1];
    try out.emit(.loomfernSheaf,m.mul(base,m.chain(&.{m.translate(mesh.sheafAt),m.rotY(p*sheafTurns*m.tau+s.seed*5),m.scale3(m.splat3(sheaf))})),look);
  }
  // the threads: each drawn out of a leaflet to the sheaf, then wound in,
  // its far end pulled off the frond and into the sheaf
  if(weaving)for(0..threads)|j|{
    const k0=threadAt[j];
    if(p<=k0)continue;
    const frond=(@as(usize,f.woven)*2+j*3+m.floorTo(usize,s.seed*7))%mesh.fronds;
    const from=m.mulPoint(base,mesh.frondAt(frond,threadFrom));
    const to=m.mulPoint(base,mesh.sheafAt);
    const d=to-from;
    const sag=v3(0,-0.04*m.len(d),0);
    const ctrl=[4]V3{from,from+d*m.splat3(0.33)+sag,from+d*m.splat3(0.7)+sag*m.splat3(0.5),to};
    const side=m.norm(m.cross(d,v3(0,1,0)));
    var look=sway;
    look.glow=if(fed)threadGlow[1]else threadGlow[0];
    look.drop=from[1]-ctr[1];
    if(p<threadWind){
      try out.emitCurve(.loomfernThread,ctrl,side,1,m.smooth(m.clamp01((p-k0)/threadDraw)),look);
    }else{
      // the same curve from the sheaf's end, shortening: wound in
      const back=[4]V3{ctrl[3],ctrl[2],ctrl[1],ctrl[0]};
      try out.emitCurve(.loomfernThread,back,-side,1,1-m.smooth((p-threadWind)/(1-threadWind)),look);
    }
  };
  // essence it was fed, standing in the calyx
  const ess=s.inv.count(.essence);
  if(ess>0 or f.fed>0){
    const lv=m.clamp01((m.f(ess)+m.f(f.fed)/perEssence)/essenceStock);
    var look=sway;
    look.tint=color.Rgba8.of(items.Item.essence.info().col).toF4();
    look.glow=poolGlow;
    look.drop=mesh.poolAt[1];
    try out.emit(.germinatorPool,m.mul(base,m.chain(&.{m.translate(mesh.poolAt),m.scale3(m.splat3(m.lerp(poolW[0],poolW[1],lv)))})),look);
  }
  // finished sheaves laid at its foot, leaning in against the bole, each
  // filling out as the fibre held grows toward it
  const held=s.inv.count(.fibre);
  for(0..laid)|k|{
    const fill=m.clamp01((m.f(held)-m.f(k*perLaid))/perLaid);
    if(fill<=0)break;
    const a=(m.f(k)+0.5)/laid*m.tau+s.seed*3;
    const at=v3(@cos(a)*laidOut,mesh.sheafH*0.42,@sin(a)*laidOut);
    var look=sway;
    look.drop=at[1];
    try out.emit(.loomfernSheaf,m.mul(base,m.chain(&.{m.translate(at),m.rotY(-a),m.rotZ(laidLean),m.scale3(m.splat3(laidSize*m.smooth(fill)))})),look);
  }
}
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  const f=&s.state.loomfern;
  const held=s.inv.count(.fibre);
  if(held>=buffer){
    _=try d.print(x,y,style.textBody,style.dim,txt.s.describe.loomFull,.{held,buffer});
    return;
  }
  const tpl=if(f.fed>0 or s.inv.count(.essence)>0)txt.s.describe.loomFed else txt.s.describe.loom;
  _=try d.print(x,y,style.textBody,style.white,tpl,.{held,buffer});
  try d.tendril(x+style.descBarX,y+2,style.descBarW,style.barH,style.growth,f.t,0.3);
}
/// its bulb: a fern unrolling out of the seed, a crozier at its heart and
/// a sheaf of fibre bound beside it (it weaves fibre).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  for([_]f32{-1,1})|sx|{
    const fr=[4]iconKit.P{.{0,iconKit.topAt},.{0.12*sx,0.5},.{0.5*sx,0.75},.{0.72*sx,0.5}};
    try ic.stem(fr,0.07,iconKit.stemCol);
    for(0..3)|k|{
      const at=iconKit.curve(fr,0.4+0.2*m.f(k));
      try ic.leaf(at,if(sx<0)2.2-0.3*m.f(k)else 0.9+0.3*m.f(k),0.2,0.1,iconKit.sprout,0.9);
    }
  }
  try ic.stem(.{.{0,iconKit.topAt},.{0,0.4},.{0.16,0.62},.{0.02,0.6}},0.075,iconKit.sprout);
  try ic.bud(.{0.06,0.56},0.07,iconKit.sprout,0.4);
  try ic.kernel(.{0.0,0.92},0.32,iconFibre);
  try ic.coat(col);
}
const iconFibre:Color=.{120,170,90,255};
// ---- tests ----
const testDt:f32=0.05;
fn fixture(w:*World)!void{
  try w.stream(.{.x=0,.y=0},1,100);
  var it=w.map.valueIterator();
  while(it.next())|cp|@memset(&cp.*.res,0);
  const c=w.chunkOfTile(0,0).?;
  for(0..4)|x|for(0..2)|y|{
    const t=y*ck.sizeTiles+x;
    c.kind[t]=.moss;
    c.height[t]=1;
  };
}
fn run(ss:*st.Structures,w:*World,plants:*Plants,g:*prog.Progression,seconds:f32)!void{
  var t:f32=0;
  while(t<seconds):(t+=testDt)try ss.tick(testing.allocator,w,plants,g,testDt);
}
test"a loomfern weaves fibre slowly unfed, and fast from essence"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,0,0,.loomfern,0,0));
  const id=ss.at(&w,0,0).?;
  try run(&ss,&w,&plants,&g,slow*2+0.2);
  try testing.expectEqual(@as(u32,2),ss.get(id).inv.count(.fibre));
  // fed one essence: four fibre at the fast pace
  try testing.expectEqual(@as(u16,1),ss.insert(&g,id,.essence,1));
  try testing.expectEqual(@as(u16,0),ss.insert(&g,id,.grit,1));
  try run(&ss,&w,&plants,&g,fast*perEssence+0.2);
  try testing.expectEqual(@as(u32,2+perEssence),ss.get(id).inv.count(.fibre));
  try testing.expectEqual(@as(u32,0),ss.get(id).inv.count(.essence));
  // only fibre leaves it
  try testing.expect(ss.output(id)==.fibre);
  try testing.expect(!ss.gives(id,.essence));
}
test"a loomfern hands its fibre to a neighbour, and rests when full"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,0,0,.loomfern,0,0));
  try testing.expect(try ss.place(gpa,&w,1,0,.sapCache,0,0));
  try testing.expect(try ss.place(gpa,&w,3,1,.loomfern,0,0));
  _=ss.insert(&g,ss.at(&w,0,0).?,.essence,essenceStock);
  try run(&ss,&w,&plants,&g,30);
  try testing.expect(ss.get(ss.at(&w,1,0).?).inv.count(.fibre)>=9);
  try run(&ss,&w,&plants,&g,slow*(buffer+2));
  const lone=ss.get(ss.at(&w,3,1).?);
  try testing.expectEqual(@as(u32,buffer),lone.inv.count(.fibre));
  try testing.expect(lone.activity<0.01);
}
