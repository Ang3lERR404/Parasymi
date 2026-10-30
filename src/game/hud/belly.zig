//! the sap belly (Tab): the wolf's inventory, slots hanging in rows from
//! vines on a trellis whose main stem fills with sap as the belly does, and
//! the weave list below it.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const assert=std.debug.assert;
const play=lib.play;
const playerMod=lib.player;
const prog=lib.progression;
const craft=lib.craft;
const Draw=lib.engine.ui.draw.Draw;
const s=lib.style;
const txt=lib.txt;
const m=lib.engine.core.math;
const icon=lib.icon;
const items=lib.items;
const hud=lib.hud;
const Slot=lib.hudSlot.Slot;
const ctl=lib.controls;
const actions=lib.actions;
const Input=lib.engine.platform.input.Input;
pub const cols=6;
const rows=playerMod.slots/cols;
comptime{assert(playerMod.slots%cols==0);}
const gap=s.slotGap;
const pw:f32=830;
/// room for the title, the hint and the first row's vine above its husks
const headerH:f32=88;
const weaveRowH:f32=52;
const slotR:f32=24;
const huskR:f32=21;
const liftedAlpha:u8=50;
/// a recipe's output, and how faded while it cannot be woven yet
const recipeR:f32=15;
const unreadyAlpha:u8=150;
/// seconds a row's vine takes to grow across
const vineGrow:f32=0.7;
/// the main stem: in from the panel's left, how far below its top it ends
const stemX:f32=40;
const stemTop:f32=26;
pub fn visible(g:*const play.Game)bool{return g.mode==.belly;}
/// a belly slot, a slot of the open structure (its grid is drawn here
/// too), a recipe woven by hand
pub const Pick=union(enum){slot:usize,store:usize,weave:usize};
/// a slot lifts or puts down (with take held, a stack moves straight across
/// to the other side); discard throws a belly stack away; a recipe weaves
/// (or, carrying something, the click just puts it down).
pub fn click(g:*play.Game,p:Pick,press:hud.Press,in:*const Input)void{
  const across=ctl.down(in,.take) and g.held==null and g.mode==.structure;
  switch(press){
    .use=>switch(p){
      .slot=>|i|if(across)g.moveAcross(.{.slot=i})else g.clickSlot(i),
      .store=>|i|if(across)g.moveAcross(.{.store=i})else g.clickStore(i),
      .weave=>|i|if(g.held!=null)g.drop()else actions.weaveByHand(g,i),
    },
    .discard=>switch(p){
      .slot=>|i|g.discard(i),
      .store,.weave=>{},
    },
    .remove=>{},
  }
}
/// the stack's item on a slot (not one lifted from it)
pub fn shows(g:*const play.Game,p:Pick)?items.Item{
  return switch(p){
    .slot=>|i|if(g.holds(.{.slot=i}))null else if(g.player.inv.slot[i])|it|it.item else null,
    .store=>|i|if(g.holds(.{.store=i}))null else if(g.storeSlot(i))|it|it.item else null,
    .weave=>null,
  };
}
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  const weaveRows=(craft.byHand.len+1)/2;
  const slotsH=gap*m.f(rows);
  const weaveH=42+weaveRowH*m.f(weaveRows);
  const ph=headerH+slotsH+weaveH+40;
  const px=(w-pw)/2;
  const py=(h-ph)/2-s.panelLift;
  try d.trellis(px,py,pw,ph,s.panel,0.33);
  g.rows.add(.{.x=px,.y=py,.w=pw,.h=ph},.panel);
  _=try d.text(px+72,py+s.titleY,s.textTitle,s.gold,txt.s.hud.bellyTitle);
  _=try d.print(px+pw-200,py+38,s.textSub,s.dim,txt.s.hud.bellyFill,.{g.player.inv.fill()*100});
  _=try d.text(px+72,py+58,s.textFine,s.dim,txt.s.hud.bellyHint);
  var y=py+headerH;
  // the trellis's main stem up its left side, sap rising in it as the belly fills
  try d.stem(.{px+stemX,y+slotsH},-m.halfPi,slotsH+headerH-stemTop,s.barHBold,s.sap,g.player.inv.fill(),0.27);
  try grid(g,d,.slot,&g.player.inv.slot,cols,px+(pw-gap*cols)/2,y);
  y+=slotsH+6;
  try weaves(g,d,px,y);
}
/// the side of a slot grid: the belly's, or the open structure's
pub const Side=enum{slot,store};
/// the belly's slot grid is this wide
pub const width=gap*cols;
pub const height=gap*m.f(rows);
/// a vine slots hang from: it runs `y` above their centres, a little wavy,
/// from `x0` to `x1`, grown from its left end to `grow` of its length, a
/// pair of leaves unfurling between each two slots `step` apart once it has
/// passed. Returns how far grown it is at `x` (0 before the tip, 1 well past).
pub const Vine=struct{
  x0:f32,x1:f32,y:f32,step:f32,grow:f32,seed:f32,
  const seg:f32=12;
  /// how far it runs past its first and last slots' outer edges
  const endPad:f32=8;
  const wave:f32=2.5;
  const r0:f32=3.2;
  const r1:f32=2.4;
  /// px of vine behind its tip that tapers, and that a slot or leaf takes to
  /// grow once the tip has passed it
  const tip:f32=40;
  const leafLen:f32=13;
  const leafWid:f32=5;
  /// the slot's husk hangs this far below the vine (its stalk's reach)
  pub const drop:f32=34;
  fn at(v:Vine,x:f32)f32{return v.y+wave*@sin(x*0.045+v.seed*7);}
  fn tipX(v:Vine)f32{return m.lerp(v.x0,v.x1,v.grow);}
  /// how far grown the vine is at `x`
  pub fn reached(v:Vine,x:f32)f32{return m.clamp01((v.tipX()-x)/tip);}
  pub fn draw(v:Vine,d:*Draw,t:f32)Allocator.Error!void{
    const end=v.tipX();
    if(end<=v.x0)return;
    const n:usize=@intFromFloat(@ceil((end-v.x0)/seg));
    var a:[2]f32=.{v.x0,v.at(v.x0)};
    var arc:f32=0;
    for(0..n)|i|{
      const x=@min(v.x0+seg*m.f(i+1),end);
      const b:[2]f32=.{x,v.at(x)};
      const k=(x-v.x0)/@max(v.x1-v.x0,1);
      const ra=m.lerp(r0,r1,(a[0]-v.x0)/@max(v.x1-v.x0,1))*@sqrt(m.clamp01((end-a[0])/tip));
      const rb=m.lerp(r0,r1,k)*@sqrt(m.clamp01((end-x)/tip));
      try d.limb(a,b,@max(ra,0.6),@max(@min(rb,ra),0.4),s.barkYoung,arc);
      arc+=b[0]-a[0];
      a=b;
    }
    // leaves between the slots, one up one down, swaying
    var x=v.x0+endPad+v.step;
    var i:usize=0;
    while(x<v.x1-endPad-1):({x+=v.step;i+=1;}){
      const open=v.reached(x);
      if(open<=0)continue;
      const sway=0.12*@sin(t*1.6+m.f(i)*1.9+v.seed*5);
      const base:[2]f32=.{x,v.at(x)};
      try d.leaf(base,-2.2+sway,leafLen*open,leafWid*open,s.leaf,open,v.seed+m.f(i));
      try d.leaf(base,-0.9-sway,leafLen*0.85*open,leafWid*open,s.leaf,open,v.seed+m.f(i)+0.5);
    }
  }
};
/// the slots of one side, `columns` across from `gx`, in the order the
/// gardener keeps them, each hanging from its row's vine: a click lifts a
/// stack onto the cursor, the next puts it down (play.Game.clickSlot /
/// clickStore).
pub fn grid(g:*play.Game,d:*Draw,comptime side:Side,stacks:[]const?items.Stack,columns:usize,gx:f32,py:f32)Allocator.Error!void{
  const t=g.uiT();
  const nRows=(stacks.len+columns-1)/columns;
  for(0..nRows)|row|{
    const vine=rowVine(d,gx,py+gap*(m.f(row)+0.5),columns,rowSeed(side,row));
    try vine.draw(d,t);
  }
  for(stacks,0..)|slot,i|{
    const cx=gx+gap*(m.f(i%columns)+0.5);
    const cy=py+gap*(m.f(i/columns)+0.5);
    var sl=Slot.around(.{cx,cy},gap,gap,hud.row(.belly,@unionInit(Pick,@tagName(side),i)),huskR/gap);
    sl.grown=rowVine(d,gx,cy,columns,rowSeed(side,i/columns)).reached(cx);
    sl.phase=m.f(i)*0.13;
    if(!try sl.draw(g,d))continue;
    const it=slot orelse continue;
    // lifted onto the cursor: only a faint trace stays behind
    const lifted=g.holds(@unionInit(play.Held,@tagName(side),i));
    const full=m.ratio(it.n,items.stack);
    try icon.draw(d,it.item,sl.center(),slotR,t,sl.phase,0.3+0.7*full,if(lifted)liftedAlpha else 255);
    if(!lifted)try icon.count(d,sl.center(),slotR,it.n);
  }
}
/// a row's vine's seed (and growth key): apart from every panel's
fn rowSeed(side:Side,row:usize)f32{return 7+m.f(@intFromEnum(side))*0.37+m.f(row)*0.11;}
/// the vine a row of `columns` slots centred at `cy` hangs from, grown as
/// far as its panel has (keyed by `seed`, as `Draw.grown`).
pub fn rowVine(d:*Draw,gx:f32,cy:f32,columns:usize,seed:f32)Vine{
  return.{
    .x0=gx-Vine.endPad,.x1=gx+gap*m.f(columns)+Vine.endPad,.y=cy-Vine.drop,
    .step=gap,.grow=d.grown(seed,vineGrow),.seed=seed,
  };
}
/// two columns of the recipes woven by hand (no seeds: a germinator weaves
/// those); locked ones shown as unknown. Clicking one weaves it.
fn weaves(g:*play.Game,d:*Draw,px:f32,wy:f32)Allocator.Error!void{
  _=try d.text(px+72,wy,s.textHeading,s.gold,txt.s.hud.weave);
  _=try d.text(px+pw-260,wy+6,s.textFine,s.dim,txt.s.hud.weaveHint);
  if(g.weave.busy()){
    try d.tendril(px+130,wy+6,200,s.barHBold,s.gold,g.weave.progress(),0.4);
    _=try d.print(px+346,wy+2,s.textNote,s.dim,txt.s.hud.queued,.{g.weave.len});
  }
  const colW=(pw-60)/2;
  for(craft.byHand,0..)|i,k|{
    const r=craft.hand[i];
    const colx=px+70+m.f(k%2)*colW;
    const y=wy+42+weaveRowH*m.f(k/2);
    g.rows.add(.{.x=colx-10,.y=y-24,.w=colW-20,.h=weaveRowH},hud.row(.belly,.{.weave=i}));
    const open=r.unlocked(&g.prog);
    const ok=open and craft.Crafter.can(g.player.inv.bag(),r);
    if(open)try icon.draw(d,r.out,.{colx+16,y},recipeR,g.uiT(),m.f(i)*0.5,if(ok)0.9 else 0.1,if(ok)255 else unreadyAlpha)
    else try d.leaf(.{colx+16,y+recipeR*0.8},-m.halfPi,recipeR*1.6,recipeR*0.7,s.unknown,0,m.f(i)*0.5);
    if(!open){
      const needName=if(r.needs)|n|txt.research(n).name else txt.s.hud.unknown;
      _=try d.print(colx+40,y-14,s.textBody,s.unknown,txt.s.hud.recipeNeeds,.{needName});
      continue;
    }
    _=try d.print(colx+40,y-14,s.textBody,if(ok)s.white else s.dim,if(r.n>1)txt.s.hud.recipeMany else txt.s.hud.recipe,.{txt.item(r.out).name,r.n});
    var x=colx+44;
    for(r.in,0..)|ing,j|{
      const have=g.player.inv.count(ing.item)>=ing.n;
      try d.grain(x+6,y+10,9,13,ing.item.info().col,if(have)0.7 else 0,m.f(j)*0.3);
      x=try d.print(x+14,y+5,s.textFine,if(have)s.white else s.dim,txt.s.hud.ingredient,.{ing.n,txt.item(ing.item).short})+10;
    }
  }
}
