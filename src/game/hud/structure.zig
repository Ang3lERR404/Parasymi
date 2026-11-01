//! a structure's panel (a click on one that keeps items): its slots beside
//! the belly's, lifted and put down between them as in the belly, and the
//! weaves it may be set to (a germinator's `recipes`).
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// a check that holds at build time: the store fits beside the belly
const assert=std.debug.assert;
/// all the maths: conversions
const m=lib.engine.core.math;
/// the game itself: the opened structure, what is held and pointed at
const play=lib.play;
/// the structures registry: slots, recipes, descriptions, choosing
const st=lib.structures;
/// the weave recipes, which a structure may be set to
const craft=lib.craft;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// the HUD's panel component
const Panel=lib.hudPanel.Panel;
/// the HUD: picks, presses, rows and bullets
const hud=lib.hud;
/// every player-facing string
const txt=lib.txt;
/// the tools an item's icon is drawn with
const icon=lib.icon;
/// the belly panel, whose slot grid sits beside the store's
const belly=lib.hudBelly;
/// a husk slot, the HUD's shared component
const Slot=lib.hudSlot.Slot;
/// what can be held: item kinds
const items=lib.items;
/// the keys and buttons down this frame
const Input=lib.engine.platform.input.Input;
/// its slots, this many across (the belly's grid sits to their right)
const cols=4;
/// how far apart (pixels) its slots hang, as the belly's do
const gap=s.slotGap;
/// the width (pixels) of its slot grid
const storeW=gap*cols;
/// the height (pixels) of its slot grid, rows enough for every slot
const storeH=gap*m.f((st.slots+cols-1)/cols);
comptime{assert(storeH<=belly.height);}
/// the panel's margin either side (pixels)
const margin:f32=76;
/// the gap (pixels) between its grid and the belly's
const between:f32=72;
/// the panel's width (pixels): both grids, the gap and the margins
const pw=margin+storeW+between+belly.width+margin;
/// the height (pixels) of its name and what it is doing, at the top
const headerH:f32=116;
/// the height (pixels) of the grids' labels
const labelH:f32=34;
/// the height (pixels) of the hint along the bottom
const hintH:f32=76;
/// the weave choices: this many seed pods to a row, the shown one's
/// ingredients beside them
const recipeCols=7;
/// how far apart (pixels) the choices' pods sit, across and down
const recipeGap:f32=58;
/// the height (pixels) of one ingredient's line
const recipeLine:f32=18;
/// the height (pixels) of the weave choices' block for `n` choices
fn recipesH(n:usize)f32{return 104+recipeGap*m.f((n+recipeCols-1)/recipeCols-1);}
/// a choice's pod radius (pixels)
const recipeR:f32=19;
/// how solid a choice not yet understood is, 0..255
const unreadyAlpha:u8=120;
/// shown while a structure's panel is open.
pub fn visible(g:*const play.Game)bool{return g.opened()!=null;}
/// a weave the structure may be set to (its slots are the belly's grid's)
pub const Pick=union(enum){
  /// the weave, by its index in `craft.hand`
  recipe:u8
};
/// a recipe clicks as mouse1 is let go over it
pub fn fire(_:Pick)hud.Fire{return.release;}
/// a click chooses the weave (carrying something, it just puts it down)
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  if(press!=.use)return;
  if(g.held!=null)return g.drop();
  // which recipe was clicked
  const r=switch(p){.recipe=>|r|r};
  if(g.opened())|j|st.choose(g.structs.get(j),&g.prog,r);
}
/// what a recipe weaves, once it is understood
pub fn shows(g:*const play.Game,p:Pick)?items.Item{
  // which recipe the row is
  const r=switch(p){.recipe=>|r|r};
  return if(craft.hand[r].unlocked(&g.prog))craft.hand[r].out else null;
}
/// draws the panel: the structure's name and what it is doing, its weave
/// choices when it has any, then its slots beside the belly's under their
/// labels, and the hint along the bottom.
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  // the opened structure, and the weaves it may be set to
  const sp=g.structs.get(g.opened().?);
  const choices=st.recipes(sp.kind(),&g.prog);
  // the panel's height, and its top-left corner
  const ph=headerH+(if(choices.len>0)recipesH(choices.len)else 0)+labelH+belly.height+hintH;
  const px=(w-pw)/2;
  const py=(h-ph)/2-s.panelLift;
  try(Panel{.box=.{.x=px,.y=py,.w=pw,.h=ph},.col=s.panel,.seed=0.41}).draw(g,d,.{w,h});
  _=try d.text(px+margin,py+40,s.textTitle,s.gold,txt.structure(sp.kind()));
  try st.describe(sp,d,&g.prog,px+margin,py+80);
  // the next block's top (pixels), moving down as each is drawn
  var y=py+headerH;
  if(choices.len>0){
    try recipes(g,d,sp,choices,px+margin,y);
    y+=recipesH(choices.len);
  }
  // the belly grid's left edge
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
  // the clock for sway, the chosen weave, and the one whose ingredients show
  const t=g.uiT();
  const chosen=st.chosen(sp);
  var shown=chosen;
  // the top of the first row of pods
  const row0=y+58;
  for(choices,0..)|r,k|{
    // this pod's centre, and whether it is the chosen weave
    const cx=x+recipeGap*(m.f(k%recipeCols)+0.5);
    const cy=row0+recipeGap*m.f(k/recipeCols);
    const on=chosen==r;
    // its slot, haloed when chosen; no carried thing is put down here
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
  // the shown recipe, and where its ingredients start
  const r=craft.hand[shown orelse return];
  const ix=x+recipeGap*m.f(@min(choices.len,recipeCols))+24;
  // the ingredients' top line, level with the first row
  const cy=row0;
  if(!r.unlocked(&g.prog)){
    // what must be understood first, or a question
    const need=if(r.needs)|n|txt.research(n).name else txt.s.hud.unknown;
    _=try d.print(ix,cy-10,s.textBody,s.unknown,txt.s.hud.recipeNeeds,.{need});
    return;
  }
  _=try d.print(ix,cy-24,s.textBody,if(shown==chosen)s.gold else s.white,if(r.n>1)txt.s.hud.recipeMany else txt.s.hud.recipe,.{txt.item(r.out).name,r.n});
  for(r.in,0..)|ing,j|{
    // how many the structure holds of it, whether that is enough, and its line
    const have=sp.inv.count(ing.item);
    const enough=have>=ing.n;
    const ly=cy+4+recipeLine*m.f(j);
    try d.grain(ix+10,ly+5,9,13,ing.item.info().col,if(enough)0.7 else 0,m.f(j)*0.3);
    _=try d.print(ix+22,ly,s.textFine,if(enough)s.white else s.dim,txt.s.hud.stock,.{have,ing.n,txt.item(ing.item).short});
  }
}
