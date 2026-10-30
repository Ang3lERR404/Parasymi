//! SPORECASTER: a parasite that sends. Paired with another sporecaster (the
//! configure key on it, then on the one it should send to), it turns what
//! it is fed into spore carriers, a few of one kind to a spore, which rise
//! out of its pore and drift over everything, however far, straight down
//! into the pore of the one it is paired with. Spores cost nothing: a
//! fruiting body manifests them by the thousand. The caster they land in
//! hands what they bring to its neighbours, or conduits pull it away, or,
//! paired on itself, it sends it on again: the loop conduits cannot close.
//! A spore whose caster is gone turns home and gives back what it carried;
//! one whose caster is full hangs over it until there is room.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const testing=std.testing;
const m=lib.engine.core.math;
const color=lib.engine.core.color;
const ck=lib.ck;
const World=lib.world.World;
const gen=lib.gen;
const items=lib.items;
const Plants=lib.plants.Plants;
const st=lib.structures;
const iconKit=lib.icon;
const txt=lib.txt;
const prog=lib.progression;
const style=lib.style;
const Parts=lib.parts.Parts;
const Look=lib.parts.Look;
const Draw=lib.engine.ui.draw.Draw;
const Color=lib.engine.ui.draw.Color;
const mesh=lib.sporecaster;
const V3=m.V3;
const v3=m.v3;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.bellyLump,.sporeCarrier};
/// paired one way: its partner is the caster it sends to
pub const pairs:st.Pairs=.{};
pub const def:st.Def=.{.item=.sporecaster,.size=1,.mesh=.sporecaster,.store=true,.grow=5,.sway=0.45,.tall=0.65,.sap=0.3,.far=true,.pale=true};
/// most it holds, how many of one kind a spore carries, and seconds
/// between one spore and the next
pub const holdTime=40;
pub const load=5;
pub const launch:f32=0.25;
/// spores in the air at once from one caster
pub const airHeight=24;
/// tiles a second a spore drifts, and how high it rises over a crossing
/// (a share of how far it goes, at least `RISE_MIN`)
pub const speed:f32=2.5;
const riseHeight:f32=0.22;
const riseMin:f32=1.2;
/// it wanders off its line by this much, back and forth as it goes
const wanderAmount:f32=0.25;
const sporeFade:f32=0.35;
const sporeGlow:f32=0.6;
const sporeSize:f32=1.7;
/// a spore waiting over a full caster hangs this high over its pore, bobbing
const hangDepth:f32=0.35;
/// what it holds hangs in its sac, in a ring, bobbing
const ringRadius:f32=0.45;
const lumpR:f32=0.022;
const lumpGrow:f32=0.02;
const bobAmount:f32=0.01;
const turnRate:f32=0.25;
const glow:f32=0.2;
pub const Spore=struct{
  item:items.Item,
  n:u8,
  /// how far along it is (0 at the pore it left .. 1 at the one it seeks)
  t:f32=0,
  /// the caster it seeks (its tile and ground height), and whether it has
  /// turned home, carrying back what it could not deliver
  to:[2]i32,
  toH:f32,
  home:bool=false,
};
pub const State=struct{
  spores:[airHeight]?Spore=@splat(null),
  t:f32=0,
};
/// the sporecaster on tile `at`, if one stands there.
fn casterAt(ss:*st.Structures,w:*const World,at:[2]i32)?st.Id{
  const j=ss.at(w,at[0],at[1]) orelse return null;
  return if(ss.get(j).kind()==.sporecaster)j else null;
}
pub fn groundAt(w:*const World,at:[2]i32)f32{
  if(w.chunkOfTile(at[0],at[1]))|c|return c.height[ck.localIndex(at[0],at[1])];
  return gen.heightAt(w.seed,at[0],at[1]);
}
/// pair it (`pairStep`): the first configured waits, the next is where the
/// first sends. Configured twice over, it stops sending.
pub fn configure(ss:*st.Structures,id:st.Id,g:*prog.Progression)void{
  switch(ss.pairStep(id)){
    .waiting=>g.say(txt.s.msg.sporesChoose,.{}),
    .cut=>g.say(txt.s.msg.sporesStill,.{}),
    .paired=>g.say(txt.s.msg.sporesPaired,.{}),
  }
}
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  const self=ctx.ss.get(i);
  const sc=&self.state.sporecaster;
  // a caster that sends hands nothing to its neighbours: it sends it all
  if(self.partner()==null)_=st.handOff(ctx,i);
  var busy=false;
  for(&sc.spores)|*slot|{
    const sp=&(slot.* orelse continue);
    busy=true;
    const far=@max(m.len(m.v3(m.f(sp.to[0]-self.x),0,m.f(sp.to[1]-self.y))),1);
    if(sp.home){
      sp.t-=dt*speed/far;
      if(sp.t>0)continue;
      _=self.inv.add(sp.item,sp.n);
      slot.*=null;
      continue;
    }
    if(sp.t<1){
      sp.t=@min(1,sp.t+dt*speed/far);
      continue;
    }
    // over the caster it seeks: in, if it is still there and has room
    const j=casterAt(ctx.ss,ctx.w,sp.to)orelse{
      sp.home=true;
      continue;
    };
    const took=switch(ctx.ss.send(ctx,j,.{.arrived=.{.item=sp.item,.n=sp.n}})){
      .took=>|k|k,
      .ignored,.done=>0,
    };
    sp.n-=@intCast(took);
    if(sp.n==0)slot.*=null;
  }
  if(ctx.ss.getPartner(i)==null)return busy;
  const to=self.partner().?.tile();
  if(self.inv.total()==0)return busy;
  sc.t+=dt;
  if(sc.t<launch)return true;
  for(&sc.spores)|*slot|{
    if(slot.*!=null)continue;
    // the kind it holds most of, a load of it
    var best:?items.Stack=null;
    for(self.inv.slot)|s|if(s)|it|if(best==null or it.n>best.?.n){
      best=it;
    };
    const it=best orelse break;
    const n:u8=@intCast(@min(it.n,load));
    _=self.inv.take(it.item,n);
    slot.*=.{.item=it.item,.n=n,.to=to,.toH=groundAt(ctx.w,to)};
    sc.t=0;
    break;
  }
  return true;
}
/// uprooted: what its spores carry comes back into its slots with them.
pub fn release(s:*st.Structure)?items.Item{
  for(&s.state.sporecaster.spores)|*slot|if(slot.*)|sp|{
    _=s.inv.add(sp.item,sp.n);
    slot.*=null;
  };
  return null;
}
/// anything, while it has room.
pub fn wants(s:*const st.Structure,_:*const prog.Progression,_:items.Item)u32{return holdTime-|s.inv.total();}
/// the oldest thing it holds (what a caster that sends nowhere lets go).
pub fn output(s:*const st.Structure)?items.Item{
  if(s.partner()!=null)return null;
  for(s.inv.slot)|slot|if(slot)|it|return it.item;
  return null;
}
pub fn gives(s:*const st.Structure,item:items.Item)bool{return s.partner()==null and s.inv.count(item)>0;}
/// the spores it sent, drifting over to the caster they seek (or home),
/// each its tip leading and a bead of what it carries inside; and what it
/// holds hanging in its sac.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  const sc=&s.state.sporecaster;
  const base=s.place(ctr);
  const pore=m.mulPoint(base,mesh.poreAt);
  for(sc.spores,0..)|slot,k|{
    const sp=slot orelse continue;
    const dest=m.footprintCentre(sp.to[0],sp.to[1],1,sp.toH)+mesh.poreAt;
    const at=flight(pore,dest,sp.t,s.seed+m.f(k)*0.37,tf);
    const ahead=flight(pore,dest,if(sp.home)sp.t-0.02 else sp.t+0.02,s.seed+m.f(k)*0.37,tf);
    // a spore waiting over a full caster hangs there, bobbing
    const hang=if(!sp.home and sp.t>=1)v3(0,hangDepth+0.05*@sin(tf*2+m.f(k)),0)else v3(0,0,0);
    const dir=if(m.len(ahead-at)>m.eps)m.norm(ahead-at)else v3(0,1,0);
    const col=color.Rgba8.of(sp.item.info().col).toF4();
    try out.emit(.sporeCarrier,m.chain(&.{m.translate(at+hang),m.alignY(dir),m.scale3(m.splat3(sporeSize))}),.{
      .glow=sporeGlow,.phase=s.seed+m.f(k)*0.37,.fade=sporeFade,.tint=.{col[0],col[1],col[2],0},.flutter=0.5,
    });
  }
  if(s.grown<1)return;
  var n:usize=0;
  for(s.inv.slot)|slot|{if(slot!=null)n+=1;}
  var j:usize=0;
  for(s.inv.slot)|slot|{
    const it=slot orelse continue;
    const a=m.ratio(j,n)*m.tau+tf*turnRate+s.seed*6;
    const ring=if(n==1)0 else mesh.sacR[0]*ringRadius;
    const at=mesh.sacAt+v3(@cos(a)*ring,bobAmount*@sin(tf*1.2+m.f(j)*2),@sin(a)*ring);
    const r=lumpR+lumpGrow*m.ratio(it.n,holdTime);
    try out.emit(.bellyLump,m.mul(base,m.chain(&.{m.translate(at),m.scale3(m.splat3(r))})),Look{
      .glow=glow,.phase=s.seed,.tint=color.Rgba8.of(it.item.info().col).toF4(),
      .sway=def.sway,.tall=def.tall,.drop=at[1],
    });
    j+=1;
  }
}
/// where a spore is `t` along its drift from `from` to `to`: up out of the
/// pore, a long rise and fall over the ground, straight down into the
/// pore it seeks, wandering a little off its line as it goes
pub fn flight(from:V3,to:V3,t:f32,ph:f32,tf:f32)V3{
  const k=m.clamp01(t);
  const d=to-from;
  const flat=v3(d[0],0,d[2]);
  const far=m.len(flat);
  const side=if(far>m.eps)m.norm(m.cross(flat,v3(0,1,0)))else v3(1,0,0);
  const rise=@max(riseMin,riseHeight*far);
  // eased along, so it leaves and arrives slowly
  const e=m.smooth(k);
  const wander=wanderAmount*@sin(m.pi*k)*@sin(k*9+ph*7+tf*0.7);
  return from+flat*m.splat3(e)+v3(0,d[1]*e+rise*@sin(m.pi*k),0)+side*m.splat3(wander);
}
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  const sc=&s.state.sporecaster;
  var air:u32=0;
  for(sc.spores)|sp|{if(sp!=null)air+=1;}
  if(s.partner())|p|{
    const to=p.tile();
    _=try d.print(x,y,style.textBody,style.white,txt.s.describe.sends,.{to[0]-s.x,to[1]-s.y,air,s.inv.total(),holdTime});
  }else{
    _=try d.print(x,y,style.textBody,style.dim,txt.s.describe.unpaired,.{s.inv.total(),holdTime});
  }
}
/// its bulb: a tall pale stalk out of the seed holding a sac, spores rising
/// out of its pore and drifting off along an arc (it sends things far).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  try ic.stem(.{.{-0.1,iconKit.topAt},.{-0.05,0.3},.{-0.16,0.45},.{-0.1,0.58}},0.09,iconSkin);
  try ic.glow(.{-0.1,0.72},0.25,iconSacGlow);
  try ic.bud(.{-0.1,0.72},0.18,iconSac,0.3);
  for([_]f32{-1,1})|sx|try ic.stem(.{.{-0.1,0.86},.{-0.1+0.18*sx,0.98},.{-0.1+0.3*sx,0.9},.{-0.1+0.28*sx,0.78}},0.04,iconFrond);
  const arc=[4]iconKit.P{.{-0.1,0.9},.{0.2,1.1},.{0.6,0.9},.{0.75,0.3}};
  for(0..3)|k|{
    const t=@mod(ic.t*0.5+ic.phase+m.f(k)/3,1);
    try ic.bud(iconKit.curve(arc,t),0.06,iconSpore,@sin(t*m.pi));
  }
  try ic.coat(col);
}
const iconSkin:Color=.{190,182,205,255};
const iconFrond:Color=.{175,160,210,255};
const iconSac:Color=.{120,160,220,200};
const iconSacGlow:Color=.{120,160,220,70};
const iconSpore:Color=.{235,225,255,255};
// ---- tests ----
const testDt:f32=0.05;
/// soil along y = 0 and y = 1 from x = 0 to 29
fn fixture(w:*World)!void{
  try w.stream(.{.x=0,.y=0},1,100);
  const c=w.chunkOfTile(0,0).?;
  for(0..30)|x|for(0..2)|y|{
    const t=y*ck.sizeTiles+x;
    c.kind[t]=.soil;
    c.height[t]=1;
    c.res[t]=0;
  };
}
fn run(ss:*st.Structures,w:*World,plants:*Plants,g:*prog.Progression,seconds:f32)!void{
  var t:f32=0;
  while(t<seconds):(t+=testDt)try ss.tick(testing.allocator,w,plants,g,testDt);
}
test"sporecasters pair by configuring one, then the one it sends to"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,0,0,.sporecaster,0,0));
  try testing.expect(try ss.place(gpa,&w,25,1,.sporecaster,0,0));
  const a=ss.at(&w,0,0).?;
  const b=ss.at(&w,25,1).?;
  st.configure(&ss,a,&g);
  try testing.expect(ss.pairing!=null);
  st.configure(&ss,b,&g);
  try testing.expectEqual(b,ss.getPartner(a).?);
  try testing.expect(ss.get(b).partner()==null and ss.pairing==null);
  var toB=ss.pairedTo(b);
  try testing.expectEqual(a,toB.next().?);
  try testing.expect(toB.next()==null);
  // configured twice over, it stops sending
  st.configure(&ss,a,&g);
  st.configure(&ss,a,&g);
  try testing.expect(ss.get(a).partner()==null);
}
test"spores carry what a caster is fed to the one it is paired with, however far"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,0,0,.sporecaster,0,0));
  try testing.expect(try ss.place(gpa,&w,28,0,.sporecaster,0,0));
  const a=ss.at(&w,0,0).?;
  try testing.expect(ss.pairWith(a,ss.at(&w,28,0).?));
  try testing.expectEqual(@as(u16,12),ss.insert(&g,a,.essence,12));
  try testing.expectEqual(@as(u16,7),ss.insert(&g,a,.grit,7));
  // a caster that sends lets nothing go to conduits
  try testing.expect(ss.output(a)==null);
  try run(&ss,&w,&plants,&g,24);
  const b=ss.get(ss.at(&w,28,0).?);
  try testing.expectEqual(@as(u32,12),b.inv.count(.essence));
  try testing.expectEqual(@as(u32,7),b.inv.count(.grit));
  try testing.expectEqual(@as(u32,0),ss.get(a).inv.total());
  // the one it lands in, sending nowhere, lets it go
  try testing.expect(ss.output(ss.at(&w,28,0).?)!=null);
}
test"spores whose caster is uprooted turn home with what they carry"{
  const gpa=testing.allocator;
  var w=World.init(gpa,5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants=.{};
  defer plants.deinit(gpa);
  var ss:st.Structures=.{};
  defer ss.deinit(gpa);
  var g:prog.Progression=.{};
  try testing.expect(try ss.place(gpa,&w,0,0,.sporecaster,0,0));
  try testing.expect(try ss.place(gpa,&w,28,0,.sporecaster,0,0));
  const a=ss.at(&w,0,0).?;
  try testing.expect(ss.pairWith(a,ss.at(&w,28,0).?));
  _=ss.insert(&g,a,.fibre,10);
  try run(&ss,&w,&plants,&g,1);
  _=ss.remove(&w,ss.at(&w,28,0).?);
  // uprooting it cut the pairing
  try testing.expect(ss.get(ss.at(&w,0,0).?).partner()==null);
  try run(&ss,&w,&plants,&g,24);
  const back=ss.get(ss.at(&w,0,0).?);
  try testing.expectEqual(@as(u32,10),back.inv.count(.fibre));
  for(back.state.sporecaster.spores)|sp|try testing.expect(sp==null);
}
