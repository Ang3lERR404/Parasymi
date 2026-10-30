//! a structure's panel (a click on one that keeps items): its slots beside
//! the belly's, lifted and put down between them as in the belly, and the
//! weaves it may be set to (a germinator's `recipes`).
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const assert=std.debug.assert;
const m=lib.engine.core.math;
const play=lib.play;
const st=lib.structures;
const craft=lib.craft;
const Draw=lib.engine.ui.draw.Draw;
const s=lib.style;
const hud=lib.hud;
const txt=lib.txt;
const icon=lib.icon;
const belly=lib.hudBelly;
const Slot=lib.hudSlot.Slot;
const items=lib.items;
const Input=lib.engine.platform.input.Input;
/// its slots, this many across (the belly's grid sits to their right)
const cols=4;
const gap=s.slotGap;
const storeW=gap*cols;
const storeH=gap*m.f((st.slots+cols-1)/cols);
comptime{assert(storeH<=belly.height);}
const margin:f32=76;
const between:f32=72;
const pw=margin+storeW+between+belly.width+margin;
const headerH:f32=116;
const labelH:f32=34;
const hintH:f32=76;
/// the weave choices: rows of seed pods, the shown one's ingredients beside
/// them, one to a line
const recipeCols=7;
const recipeGap:f32=58;
const recipeLine:f32=18;
fn recipesH(n:usize)f32{return 104+recipeGap*m.f((n+recipeCols-1)/recipeCols-1);}
const recipeR:f32=19;
const unreadyAlpha:u8=120;
pub fn visible(g:*const play.Game)bool{return g.opened()!=null;}
/// a weave the structure may be set to (its slots are the belly's grid's)
pub const Pick=union(enum){recipe:u8};
/// a click chooses the weave (carrying something, it just puts it down)
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  if(press!=.use)return;
  if(g.held!=null)return g.drop();
  const r=switch(p){.recipe=>|r|r};
  if(g.opened())|j|st.choose(g.structs.get(j),&g.prog,r);
}
/// what a recipe weaves, once it is understood
pub fn shows(g:*const play.Game,p:Pick)?items.Item{
  const r=switch(p){.recipe=>|r|r};
  return if(craft.hand[r].unlocked(&g.prog))craft.hand[r].out else null;
}
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  const sp=g.structs.get(g.opened().?);
  const choices=st.recipes(sp.kind());
  const ph=headerH+(if(choices.len>0)recipesH(choices.len)else 0)+labelH+belly.height+hintH;
  const px=(w-pw)/2;
  const py=(h-ph)/2-s.panelLift;
  try d.trellis(px,py,pw,ph,s.panel,0.41);
  g.rows.add(.{.x=px,.y=py,.w=pw,.h=ph},.panel);
  _=try d.text(px+margin,py+40,s.textTitle,s.gold,txt.structure(sp.kind()));
  try st.describe(sp,d,&g.prog,px+margin,py+80);
  var y=py+headerH;
  if(choices.len>0){
    try recipes(g,d,sp,choices,px+margin,y);
    y+=recipesH(choices.len);
  }
  const bx=px+margin+storeW+between;
  _=try d.text(px+margin,y,s.textHeading,s.gold,txt.s.hud.holds);
  _=try d.text(bx,y,s.textHeading,s.gold,txt.s.hud.bellyTitle);
  _=try d.print(bx+belly.width-100,y+6,s.textNote,s.dim,txt.s.hud.bellyFill,.{g.player.inv.fill()*100});
  y+=labelH;
  try belly.grid(g,d,.store,&sp.inv.slot,cols,px+margin,y);
  try belly.grid(g,d,.slot,&g.player.inv.slot,belly.cols,bx,y);
  _=try d.text(px+margin,y+belly.height+18,s.textFine,s.dim,txt.s.hud.storeHint);
}
/// the recipes it may be set to weave, the chosen one lit; beside them, what
/// the one under the mouse (else the chosen one) is woven from, against
/// what the structure holds. A click chooses.
fn recipes(g:*play.Game,d:*Draw,sp:*const st.Structure,choices:[]const u8,x:f32,y:f32)Allocator.Error!void{
  _=try d.text(x,y,s.textHeading,s.gold,txt.s.hud.weaveChoose);
  const t=g.uiT();
  const chosen=st.chosen(sp);
  var shown=chosen;
  const row0=y+58;
  for(choices,0..)|r,k|{
    const cx=x+recipeGap*(m.f(k%recipeCols)+0.5);
    const cy=row0+recipeGap*m.f(k/recipeCols);
    const on=chosen==r;
    var sl=Slot.around(.{cx,cy},recipeGap,recipeGap,hud.row(.structure,.{.recipe=r}),(recipeR+3)/recipeGap);
    sl.lit=if(on)1 else 0;
    sl.halo=if(on)s.researchActive else null;
    sl.takes=false;
    sl.phase=m.f(k)*0.29;
    if(g.points(sl.pick))shown=r;
    _=try sl.draw(g,d);
    if(craft.hand[r].unlocked(&g.prog)){
      try icon.draw(d,craft.hand[r].out,sl.center(),recipeR,t,sl.phase,if(on)1 else 0.3,if(on)255 else unreadyAlpha);
    }else try hud.bullet(d,cx,cy-recipeR*0.3,recipeR*0.6,s.unknown,0,sl.phase);
  }
  const r=craft.hand[shown orelse return];
  const ix=x+recipeGap*m.f(@min(choices.len,recipeCols))+24;
  const cy=row0;
  if(!r.unlocked(&g.prog)){
    const need=if(r.needs)|n|txt.research(n).name else txt.s.hud.unknown;
    _=try d.print(ix,cy-10,s.textBody,s.unknown,txt.s.hud.recipeNeeds,.{need});
    return;
  }
  _=try d.print(ix,cy-24,s.textBody,if(shown==chosen)s.gold else s.white,if(r.n>1)txt.s.hud.recipeMany else txt.s.hud.recipe,.{txt.item(r.out).name,r.n});
  for(r.in,0..)|ing,j|{
    const have=sp.inv.count(ing.item);
    const enough=have>=ing.n;
    const ly=cy+4+recipeLine*m.f(j);
    try d.grain(ix+10,ly+5,9,13,ing.item.info().col,if(enough)0.7 else 0,m.f(j)*0.3);
    _=try d.print(ix+22,ly,s.textFine,if(enough)s.white else s.dim,txt.s.hud.stock,.{have,ing.n,txt.item(ing.item).short});
  }
}
