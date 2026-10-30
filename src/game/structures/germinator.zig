//! GERMINATOR: a small tree that weaves by itself from what it is fed,
//! running the same recipes the wolf weaves by hand, and the seeds besides
//! (only it weaves those), at its own pace. The wolf bootstraps by hand;
//! fed and emptied by conduits, the germinator is what automates the garden.
//!
//! Each weave is seen through: its cups tip and pour the essences it weaves
//! from into its core of sap, which spins them into a whirl round its
//! spindle (centrifuging them) and winds a seed of them on it (spindling),
//! all of it following how far the weave has come.
const lib=@import("../../lib.zig");
const std=lib.std;
const m=lib.engine.core.math;
const indexOfScalar=std.mem.indexOfScalar;
const Allocator=std.mem.Allocator;
const items=lib.items;
const color=lib.engine.core.color;
const st=lib.structures;
const iconKit=lib.icon;
const txt=lib.txt;
const prog=lib.progression;
const craft=lib.craft;
const style=lib.style;
const Parts=lib.parts.Parts;
const Look=lib.parts.Look;
const mesh=lib.germinator;
const growth=lib.growth;
const Draw=lib.engine.ui.draw.Draw;
const Color=lib.engine.ui.draw.Color;
const V3=m.V3;
const v3=m.v3;
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes=.{.germinatorCore,.germinatorCup,.germinatorPool,.germinatorSeed,.germinatorThread,.germinatorVortex,.germinatorWinding,.germinatorPour};
pub const def:st.Def=.{
  .item=.germinator,.size=2,.mesh=.germinator,.preview=.germinatorWhole,.store=true,
  .sway=0.55,.tall=mesh.tall,.grow=6,.still=true,
};
/// weave speed multiplier relative to hand-weaving
const speed:f32=0.6;
/// most of one ingredient it will hold
const stock=20;
/// a weave's stages over its progress (0..1), each easing in over its
/// first two and out over its last two: the cups pour, the core spins
/// (centrifuging), the threads wind onto the seed (spindling)
const pourTimes=[4]f32{0,0.04,0.26,0.34};
const spinTimes=[4]f32{0.14,0.36,0.84,0.96};
const windTimes=[4]f32{0.36,0.5,0.92,0.98};
/// the seed grows on the spindle over this stretch of the weave
const seedFrom:f32=0.36;
const seedTo:f32=0.96;
/// a stream reaches the core this far into the weave (falling from the lip)
const pourFall:f32=0.06;
/// how fast the core's contents turn at full spin (rad/s); idle, they drift
const spinRate:f32=9;
const calm:f32=0.25;
/// the core swells out and flattens as it spins, by this at full spin
const bulgeAmount:f32=0.07;
/// how far a cup tips to pour (rad), and nods idle
const tiltAmount:f32=1.05;
const nod:f32=0.05;
const nodRate:f32=0.8;
/// the essence standing in a cup: its lens's radius and height empty ..
/// full (cup space)
const poolW=[2]f32{0.02,0.055};
const poolY=[2]f32{0.03,0.075};
/// where the streams land on the core's crown: this far out toward their cup
const landAmount:f32=0.07;
/// how far each essence's winding leans off the spindle, so they cross
const windingLean=[_]f32{0.0,0.32,-0.3,0.18,-0.2};
/// light of its own: essence standing, poured, spun, wound
const poolGlow:f32=0.25;
const pourGlow:f32=0.7;
const spinGlow:f32=0.6;
const seedGlow:f32=0.45;
/// how see-through the core's sap is at its thinnest
const coreSap:f32=0.22;
pub const State=struct{
  /// which recipe (index into craft.hand) it weaves
  recipe:u8=0,
  weave:craft.Crafter=.{},
};
pub fn tick(ctx:st.Ctx,i:st.Id,dt:f32)bool{
  const self=ctx.ss.get(i);
  const g=&self.state.germinator;
  const r=craft.hand[g.recipe];
  if(!g.weave.busy() and r.unlocked(ctx.g) and craft.Crafter.can(self.inv.bag(),r))_=g.weave.push(self.inv.bag(),g.recipe);
  _=g.weave.tick(self.inv.bag(),dt*speed);
  return g.weave.busy();
}
pub fn wants(s:*const st.Structure,_:*const prog.Progression,item:items.Item)u32{
  for(craft.hand[s.state.germinator.recipe].in)|ing|{
    if(ing.item==item)return stock-|s.inv.count(item);
  }
  return 0;
}
/// only finished weaves leave: anything woven, so one woven before the
/// recipe was changed still goes (what it weaves from never is).
pub fn output(s:*const st.Structure)?items.Item{
  for(s.inv.slot)|slot|if(slot)|it|if(craft.woven(it.item))return it.item;
  return null;
}
/// anything woven it holds.
pub fn gives(s:*const st.Structure,item:items.Item)bool{return craft.woven(item) and s.inv.count(item)>0;}
/// its panel offers every weave.
pub fn recipes()[]const u8{return&craft.all;}
pub fn chosen(s:*const st.Structure)?u8{return s.state.germinator.recipe;}
/// set what it weaves, if the gardener understands it. A weave under way
/// finishes first (its ingredients are already in it).
pub fn choose(s:*st.Structure,g:*prog.Progression,r:u8)void{
  const out=txt.item(craft.hand[r].out).name;
  if(!craft.hand[r].unlocked(g))return g.say(txt.s.msg.notUnderstood,.{out});
  if(s.state.germinator.recipe==r)return;
  s.state.germinator.recipe=r;
  g.say(txt.s.msg.germinatorWeaves,.{out});
}
/// cycle through the weaves the gardener understands.
pub fn configure(ss:*st.Structures,id:st.Id,g:*prog.Progression)void{
  const s=ss.get(id);
  const at=indexOfScalar(u8,&craft.all,s.state.germinator.recipe) orelse 0;
  for(1..craft.all.len+1)|k|{
    const r=craft.all[(at+k)%craft.all.len];
    if(craft.hand[r].unlocked(g))return choose(s,g,r);
  }
}
pub fn describe(s:*const st.Structure,d:*Draw,_:*const prog.Progression,x:f32,y:f32)Allocator.Error!void{
  const gs=&s.state.germinator;
  _=try d.print(x,y,style.textBody,style.white,txt.s.describe.weaves,.{txt.item(craft.hand[gs.recipe].out).name});
  try d.tendril(x+style.descBarX,y+2,style.descBarW,style.barH,style.gold,gs.weave.progress(),0.3);
}
// a fresh germinator starts on recipe 0
comptime{std.debug.assert(craft.all[0]==0);}
/// a stage's strength at progress `p`: 0 before `e[0]`, rising to 1 by
/// `e[1]`, held, falling to 0 from `e[2]` to `e[3]` (linear ramps)
fn stage(p:f32,e:[4]f32)f32{
  if(p<=e[0] or p>=e[3])return 0;
  if(p<e[1])return(p-e[0])/(e[1]-e[0]);
  if(p>e[2])return(e[3]-p)/(e[3]-e[2]);
  return 1;
}
/// the area under `stage` from 0 to `p`: how far something running at its
/// strength has gone
fn stageArea(p:f32,e:[4]f32)f32{
  const rise=e[1]-e[0];
  const fall=e[3]-e[2];
  if(p<=e[0])return 0;
  if(p<e[1])return(p-e[0])*(p-e[0])/(2*rise);
  if(p<e[2])return rise/2+(p-e[1]);
  if(p<e[3])return rise/2+(e[2]-e[1])+(p-e[2])-(p-e[2])*(p-e[2])/(2*fall);
  return rise/2+(e[2]-e[1])+fall/2;
}
/// how far round the core's contents have turned: a slow drift, and while
/// a weave spins them, as far as its spin has carried them by progress `p`.
/// Worked out from the progress alone (the spin speeds up and slows down
/// with the weave, never jumping), and a whole number of turns by the
/// weave's end, so the next one starts where it left off.
fn turned(p:f32,time:f32,tf:f32)f32{
  // progress runs this fast (per second)
  const rate=speed/time;
  const total=stageArea(1,spinTimes);
  const turns=@max(1,@round(spinRate*total/rate/m.tau));
  return tf*calm+stageArea(p,spinTimes)/total*turns*m.tau;
}
fn colOf(item:items.Item)[4]f32{return color.Rgba8.of(item.info().col).toF4();}
/// the tree's cups, core and what it weaves: placed on its mesh as it
/// stands (`place`), swaying with it from its root. The cups and core
/// form once the tree has grown (their meshes carry `mesh.FORM`, grown by
/// the structure's growth on the GPU).
pub fn emit(s:*const st.Structure,out:*Parts,ctr:m.V3,tf:f32)Allocator.Error!void{
  if(growth.formed(mesh.form,s.grown)<=0)return;
  const base=s.place(ctr);
  const lift=s.grownScale()[1];
  const g=&s.state.germinator;
  const busy=g.weave.busy();
  // the weave under way (its recipe may since have been changed), else
  // the one it waits to weave
  const r=craft.hand[if(busy)g.weave.queue[0]else g.recipe];
  const p=if(busy)g.weave.progress()else 0;
  const pour=stage(p,pourTimes);
  const spin=stage(p,spinTimes);
  const wind=stage(p,windTimes);
  const grownSeed=if(busy)m.smooth(m.clamp01((p-seedFrom)/(seedTo-seedFrom)))else 0;
  const turn=turned(p,r.time,tf);
  // it all sways with the tree, from its root (`drop`: how high over it)
  const sway:Look=.{.phase=s.seed,.sway=def.sway,.tall=def.tall,.grown=s.grown};
  // the cups: each holds one of what the weave is woven from, standing
  // in it as deep as the tree has it in store, and tips to pour it
  const top=m.mulPoint(base,mesh.coreTop);
  for(0..mesh.boughs)|k|{
    const tip=mesh.tip(k);
    const ing:?items.Ingredient=if(k<r.in.len)r.in[k]else null;
    const tilt=(if(ing!=null)pour*tiltAmount else 0)+nod*@sin(tf*nodRate+m.f(k)*1.3+s.seed*7);
    const cup=m.mul(base,m.chain(&.{m.translate(tip),m.rotY(mesh.cupFacing(k)),m.rotZ(-tilt)}));
    var look=sway;
    look.drop=tip[1]*lift;
    try out.emit(.germinatorCup,cup,look);
    const it=ing orelse continue;
    const col=colOf(it.item);
    const level=m.clamp01(m.f(s.inv.count(it.item))/stock);
    // the essence keeps level as the cup tips; a cup that has poured is dry
    if(level>0 or pour>0){
      const lv=@max(level,pour);
      const w=m.lerp(poolW[0],poolW[1],lv);
      look.tint=col;
      look.glow=poolGlow;
      try out.emit(.germinatorPool,m.mul(cup,m.chain(&.{m.translate(v3(0,m.lerp(poolY[0],poolY[1],lv),0)),m.rotZ(tilt),m.scale3(m.splat3(w))})),look);
    }
    if(pour<=0)continue;
    // the stream: off the lip, out over the core and down into its crown
    const lip=m.mulPoint(cup,mesh.cupLip);
    const land=top+m.norm(v3(lip[0]-top[0],0,lip[2]-top[2]))*m.splat3(landAmount);
    const d=land-lip;
    const across=v3(d[0],0,d[2]);
    const ctrl=[4]V3{lip,lip+across*m.splat3(0.35)+v3(0,0.01,0),lip+across*m.splat3(0.85)+v3(0,d[1]*0.55,0),land};
    try out.emitCurve(.germinatorPour,ctrl,m.norm(m.cross(d,v3(0,1,0))),1,m.smooth(m.clamp01(p/pourFall)),.{
      .glow=pourGlow,.phase=s.seed+m.f(k)*0.13,.fade=pour,.carryCol=.{col[0],col[1],col[2]},
      .sway=def.sway,.tall=def.tall,.drop=land[1]-ctr[1],
    });
  }
  // the core: its sap turns with what spins in it (its bubbles swirl
  // too), swelling out and flattening as it spins
  const heart=m.mul(base,m.translate(mesh.coreAt));
  var look=sway;
  look.drop=mesh.coreAt[1]*lift;
  const bulge=1+bulgeAmount*spin;
  var core=look;
  core.fade=coreSap;
  try out.emit(.germinatorCore,m.mul(heart,m.chain(&.{m.rotY(turn),m.scale3(v3(bulge,1/(bulge*bulge),bulge))})),core);
  if(!busy)return;
  const n=r.in.len;
  // centrifuging: an arm of the whirl for each essence, flung out toward
  // the core's wall as it spins up
  if(spin>0)for(r.in,0..)|ing,j|{
    look.tint=colOf(ing.item);
    look.glow=spinGlow*(0.4+0.6*spin);
    const wide=m.lerp(0.55,1,spin);
    try out.emit(.germinatorVortex,m.mul(heart,m.chain(&.{m.rotY(turn+m.ratio(j,n)*m.tau),m.scale3(v3(wide,spin,wide))})),look);
  };
  // spindling: threads drawn off the whirl wind onto the seed as it turns
  if(wind>0)for(r.in,0..)|ing,j|{
    look.tint=colOf(ing.item);
    look.glow=spinGlow;
    try out.emit(.germinatorThread,m.mul(heart,m.chain(&.{m.rotY(turn+(m.f(j)+0.5)/m.f(n)*m.tau),m.scale3(m.splat3(m.lerp(0.4,1,wind)))})),look);
  };
  // the seed on the spindle, the colour of what it becomes, wound round
  // with each essence it is spun from
  if(grownSeed<=0)return;
  const size=m.scale3(m.splat3(mesh.seedR*grownSeed));
  look.tint=colOf(r.out);
  look.glow=seedGlow;
  try out.emit(.germinatorSeed,m.mul(heart,m.chain(&.{m.rotY(turn),size})),look);
  for(r.in,0..)|ing,j|{
    look.tint=colOf(ing.item);
    try out.emit(.germinatorWinding,m.mul(heart,m.chain(&.{m.rotY(turn+m.f(j)*2.1),m.rotX(windingLean[j%windingLean.len]),size})),look);
  }
}
/// its bulb: a sprout whose two cupped leaves cradle a new seed (it weaves seeds).
pub fn icon(ic:iconKit.Icon,col:Color)Allocator.Error!void{
  try ic.stem(.{.{0,iconKit.topAt},.{0,0.3},.{0.06,0.4},.{0,0.5}},0.11,iconKit.stemCol);
  try ic.glow(.{0,0.72},0.28,iconGlow);
  try ic.kernel(.{0,0.74},0.42,iconSeed);
  try ic.leaf(.{0,0.48},0.4,0.46,0.3,iconKit.sprout,0.55);
  try ic.leaf(.{0,0.48},m.pi-0.4,0.46,0.3,iconKit.sprout,0.55);
  try ic.coat(col);
}
const iconSeed:Color=.{120,240,220,255};
const iconGlow:Color=.{150,255,200,70};
