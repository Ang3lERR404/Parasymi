//! MONFRIS: a weftstone and a driftbraid grown into one 2x2 tree that
//! weaves the advanced tier (`craft.advanced`), which nothing else can:
//! its panel picks the weave, as a germinator's does. It is fed by the
//! Vultrixi tethered to it, at most `TETHERS`, each bringing it one kind of
//! what that weave needs (so an advanced weave has at most six kinds), or
//! by hand from its panel; what it weaves it hands to the structures
//! beside it, or keeps for the gardener.
// decision: what it is fed by conduits it takes too (a conduit hands in
// through `wants` like anything else); only Vultrixi reach out for it
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const indexOfScalar=std.mem.indexOfScalar;
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
const craft=lib.craft;
const style=lib.style;
const Parts=lib.parts.Parts;
const Look=lib.parts.Look;
const Draw=lib.engine.ui.draw.Draw;
const Color=lib.engine.ui.draw.Color;
const mesh=lib.monfris;
const V3=m.V3;
const v3=m.v3;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.bellyLump,.itemPod};
pub const def:st.Def=.{.item=.monfris,.size=2,.mesh=.monfris,.store=true,.grow=10,.sway=0.2,.tall=1.7,.sap=0.3};
/// most Vultrixi tethered to one monfris (an advanced weave needs at
/// most this many kinds)
pub const tethers=6;
/// how many weaves' worth of each ingredient it stocks
const stock=2;
/// it weaves this much faster than a germinator weaves its own
const speed:f32=1;
/// what it holds hangs in its sac, in a ring, bobbing; what it weaves forms
/// at the sac's heart
const ringRadius:f32=0.5;
const lumpR:f32=0.026;
const lumpGrow:f32=0.02;
const bobAmount:f32=0.012;
const turnRate:f32=0.2;
const glow:f32=0.2;
const formingSize:f32=0.55;
const formingGlow:f32=0.8;
comptime{
  // every advanced weave fits the tethers it may have
  for(craft.advanced)|r|std.debug.assert(craft.hand[r].in.len<=tethers);
}
pub const State=struct{
  /// which advanced weave (index into craft.hand) it weaves
  recipe:u8=craft.advanced[0],
  weave:craft.Crafter=.{},
  /// how many Vultrixi are tethered to it (counted each tick)
  tethered:u8=0,
};
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  _=st.handOff(ctx,i);
  const self=ctx.ss.get(i);
  const h=&self.state.monfris;
  h.tethered=@intCast(ctx.ss.childCount(i));
  const r=craft.hand[h.recipe];
  if(!h.weave.busy() and r.unlocked(ctx.g) and craft.Crafter.can(self.inv.bag(),r))_=h.weave.push(self.inv.bag(),h.recipe);
  _=h.weave.tick(self.inv.bag(),dt*speed);
  return h.weave.busy();
}
/// what its weave needs, `STOCK` weaves' worth.
pub fn wants(s:*const st.Structure,_:*const prog.Progression,item:items.Item)u32{
  for(craft.hand[s.state.monfris.recipe].in)|ing|{
    if(ing.item==item)return@as(u32,ing.n)*stock-|s.inv.count(item);
  }
  return 0;
}
/// whether an advanced weave makes `item` (what it lets go of).
fn made(item:items.Item)bool{
  for(craft.advanced)|r|if(craft.hand[r].out==item)return true;
  return false;
}
pub fn output(s:*const st.Structure)?items.Item{return s.firstHeld(made);}
pub fn gives(s:*const st.Structure,item:items.Item)bool{return made(item) and s.inv.count(item)>0;}
/// its panel offers the advanced tier.
pub fn recipes()[]const u8{return&craft.advanced;}
pub fn chosen(s:*const st.Structure)?u8{return s.state.monfris.recipe;}
/// set what it weaves, if the gardener understands it (a weave under way
/// finishes first).
pub fn choose(s:*st.Structure,g:*prog.Progression,r:u8)void{
  const out=txt.item(craft.hand[r].out).name;
  if(!craft.hand[r].unlocked(g))return g.say(txt.s.msg.notUnderstood,.{out});
  if(indexOfScalar(u8,&craft.advanced,r)==null or s.state.monfris.recipe==r)return;
  s.state.monfris.recipe=r;
  g.say(txt.s.msg.monfrisWeaves,.{out});
}
/// a Vultrixi waiting to be tethered is tethered here (`ss.pairing`, set by
/// configuring it): it becomes its child (`dependOn`), while it has room
/// for one more.
pub fn configure(ss:*st.Structures,id:st.Id,g:*prog.Progression)void{
  const p=ss.pairing orelse return;
  const v=ss.find(p) orelse return;
  if(ss.get(v).kind()!=.vultrixi)return;
  ss.pairing=null;
  if(!ss.dependOn(v,id))return g.say(txt.s.msg.tetherFull,.{});
  g.say(txt.s.msg.tethered,.{});
}
/// its children are the Vultrixi tethered to it, `TETHERS` at most.
pub fn adopts(_:*const st.Structure,k:st.Kind,have:u32)bool{return k==.vultrixi and have<tethers;}
/// what it holds hanging in its sac, and what it weaves forming at its heart.
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  if(s.grown<1)return;
  const base=s.place(ctr);
  const h=&s.state.monfris;
  const n=s.inv.used();
  var j:usize=0;
  for(s.inv.slot)|slot|{
    const it=slot orelse continue;
    const a=m.ratio(j,n)*m.tau+tf*turnRate+s.seed*6;
    const ring=if(n==1)0 else mesh.sacR[0]*ringRadius;
    const at=mesh.sacAt+v3(@cos(a)*ring,-mesh.sacR[1]*0.3+bobAmount*@sin(tf*1.2+m.f(j)*2),@sin(a)*ring);
    const r=lumpR+lumpGrow*m.ratio(it.n,items.stack);
    try s.emitLump(out,base,at,r,it.item,glow);
    j+=1;
  }
  if(h.weave.busy()){
    const r=craft.hand[h.weave.queue[0]];
    const at=mesh.sacAt+v3(0,mesh.sacR[1]*0.15,0);
    try out.emit(.itemPod,m.mul(base,m.chain(&.{m.translate(at),m.rotY(tf),m.scale3(m.splat3(formingSize*(0.3+0.7*h.weave.progress())))})),Look{
      .glow=formingGlow,.phase=s.seed,.tint=color.Rgba8.of(r.out.info().col).toF4(),
      .sway=def.sway,.tall=def.tall,.drop=at[1],
    });
  }
}
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  const h=&s.state.monfris;
  const name=txt.item(craft.hand[h.recipe].out).name;
  if(h.weave.busy()){
    _=try d.print(x,y,style.textBody,style.white,txt.s.describe.loomWeaves,.{name,h.tethered});
    try d.tendril(x+style.descBarX,y+2,style.descBarW,style.barH,style.gold,h.weave.progress(),0.3);
  }else{
    _=try d.print(x,y,style.textBody,style.dim,txt.s.describe.loomWaits,.{name,h.tethered});
  }
}
/// its bulb: four strands out of the seed twining into one trunk under a
/// sac, a woven seed forming in it, tethers running in to it from either
/// side with motes along them (it is fed from round it).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  const sac:iconKit.P=.{0,0.7};
  for(0..4)|i|{
    const sx=m.lerp(-0.3,0.3,m.ratio(i,3));
    try ic.stem(.{.{sx,iconKit.topAt},.{sx*0.6,0.28},.{-sx*0.3,0.42},.{0,0.55}},0.06,if(i%2==0)iconGreen else iconPale);
  }
  for([_]f32{-1,1},0..)|sx,i|{
    const run=[4]iconKit.P{.{0.85*sx,0.95},.{0.6*sx,1.0},.{0.3*sx,0.85},sac};
    try ic.stem(run,0.02,iconTether);
    try ic.bud(.{0.85*sx,0.95},0.06,iconVult,0.6);
    const k=@mod(ic.t*0.6+ic.phase+m.f(i)*0.5,1);
    try ic.bud(iconKit.curve(run,k),0.04,iconMote,@sin(k*m.pi));
  }
  try ic.glow(sac,0.26,iconSacGlow);
  try ic.bud(sac,0.18,iconSac,0.4);
  try ic.kernel(sac,0.13,iconSeed);
  try ic.coat(col);
}
const iconGreen:Color=.{80,150,95,255};
const iconPale:Color=.{185,180,205,255};
const iconTether:Color=.{200,195,220,255};
const iconVult:Color=.{225,205,230,255};
const iconMote:Color=.{245,210,150,255};
const iconSac:Color=.{215,150,125,210};
const iconSacGlow:Color=.{170,140,230,70};
const iconSeed:Color=.{200,160,255,255};
