//! the sap belly (Tab): the wolf's inventory, slots hanging in rows from
//! vines on a trellis whose main stem fills with sap as the belly does, and
//! the weave list below it.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// a check that holds at build time: the slots fill whole rows
const assert=std.debug.assert;
/// the game itself: the belly, what is held, the open structure
const play=lib.play;
/// the player, for how many slots the belly has
const playerMod=lib.player;
/// what the gardener has understood
const prog=lib.progression;
/// the weave recipes, some woven by hand
const craft=lib.craft;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// the HUD's panel component
const Panel=lib.hudPanel.Panel;
/// every player-facing string
const txt=lib.txt;
/// all the maths: conversions, easing, angles
const m=lib.engine.core.math;
/// the tools an item's icon is drawn with
const icon=lib.icon;
/// what can be held: item kinds and stacks
const items=lib.items;
/// the HUD: picks, presses, rows and bullets
const hud=lib.hud;
/// a husk slot, the HUD's shared component
const Slot=lib.hudSlot.Slot;
/// the bindings, to see whether take is held
const ctl=lib.controls;
/// the keys and buttons down this frame
const Input=lib.engine.platform.input.Input;
/// how many slots hang to a row
pub const cols=6;
/// how many rows of slots the belly has
const rows=playerMod.slots/cols;
comptime{assert(playerMod.slots%cols==0);}
/// how far apart (pixels) the slots hang
const gap=s.slotGap;
/// the panel's width (pixels)
const pw:f32=830;
/// room for the title, the hint and the first row's vine above its husks
const headerH:f32=88;
/// the height (pixels) of one row of the weave list
const weaveRowH:f32=52;
/// a held stack's icon radius (pixels)
const slotR:f32=24;
/// a husk's radius (pixels)
const huskR:f32=21;
/// how faint the trace a lifted stack leaves behind is, 0..255
const liftedAlpha:u8=50;
/// a recipe's output radius (pixels)
const recipeR:f32=15;
/// how faded a recipe is while it cannot be woven yet, 0..255
const unreadyAlpha:u8=150;
/// seconds a row's vine takes to grow across
const vineGrow:f32=0.7;
/// the main stem: how far in (pixels) from the panel's left
const stemX:f32=40;
/// how far (pixels) below the panel's top the main stem ends
const stemTop:f32=26;
/// shown while the belly is open.
pub fn visible(g:*const play.Game)bool{return g.mode==.belly;}
/// a belly slot, a slot of the open structure (its grid is drawn here
/// too), a recipe woven by hand
pub const Pick=union(enum){
  /// a belly slot, by its index
  slot:usize,
  /// a slot of the open structure, by its index
  store:usize,
  /// a recipe woven by hand, by its index in `craft.hand`
  weave:usize
};
/// a slot lifts or places as mouse1 goes down; a recipe weaves as it is
/// let go over it
pub fn fire(p:Pick)hud.Fire{return switch(p){.slot,.store=>.press,.weave=>.release};}
/// a slot lifts or puts down (with take held, a stack moves straight across
/// to the other side); discard throws a belly stack away; a recipe weaves
/// (or, carrying something, the click just puts it down).
pub fn click(g:*play.Game,p:Pick,press:hud.Press,in:*const Input)void{
  // with take held, nothing carried and a structure open, a stack moves across
  const across=ctl.down(in,.take) and g.held==null and g.mode==.structure;
  switch(press){
    .use=>switch(p){
      .slot=>|i|if(across)g.moveAcross(.{.slot=i})else g.clickSlot(i),
      .store=>|i|if(across)g.moveAcross(.{.store=i})else g.clickStore(i),
      .weave=>|i|if(g.held!=null)g.drop()else g.weaveByHand(i),
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
/// draws the panel: the title, fill and hint, the main stem filling with
/// sap, the belly's slot grid and the weave list below it.
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  // how many rows the weave list takes, and the grid's and the list's heights
  const weaveRows=(craft.handsOf(g.act).len+1)/2;
  const slotsH=gap*m.f(rows);
  const weaveH=42+weaveRowH*m.f(weaveRows);
  // the panel's height, and its top-left corner
  const ph=headerH+slotsH+weaveH+40;
  const px=(w-pw)/2;
  const py=(h-ph)/2-s.panelLift;
  try(Panel{.box=.{.x=px,.y=py,.w=pw,.h=ph},.col=s.panel,.seed=0.33}).draw(g,d,.{w,h});
  _=try d.text(px+72,py+s.titleY,s.textTitle,s.gold,txt.s.hud.bellyTitle);
  _=try d.print(px+pw-200,py+38,s.textSub,s.dim,txt.s.hud.bellyFill,.{g.player.inv.fill()*100});
  _=try d.text(px+72,py+58,s.textFine,s.dim,txt.s.hud.bellyHint);
  // the next block's top (pixels)
  var y=py+headerH;
  // the trellis's main stem up its left side, sap rising in it as the belly fills
  try d.stem(.{px+stemX,y+slotsH},-m.halfPi,slotsH+headerH-stemTop,s.barHBold,s.sap,g.player.inv.fill(),0.27);
  try grid(g,d,.slot,&g.player.inv.slot,cols,px+(pw-gap*cols)/2,y);
  y+=slotsH+6;
  try weaves(g,d,px,y);
}
/// the side of a slot grid: the belly's, or the open structure's
pub const Side=enum{
  /// the wolf's own belly
  slot,
  /// the open structure's store
  store
};
/// the belly's slot grid is this wide
pub const width=gap*cols;
/// the belly's slot grid is this tall
pub const height=gap*m.f(rows);
/// a vine slots hang from: it runs `y` above their centres, a little wavy,
/// from `x0` to `x1`, grown from its left end to `grow` of its length, a
/// pair of leaves unfurling between each two slots `step` apart once it has
/// passed. Returns how far grown it is at `x` (0 before the tip, 1 well past).
pub const Vine=struct{
  /// where it starts (pixels from the left)
  x0:f32,
  /// where it ends at full growth (pixels from the left)
  x1:f32,
  /// its height over the slots' centres (pixels from the top)
  y:f32,
  /// how far apart (pixels) the slots hanging from it are
  step:f32,
  /// how far along its length it has grown, 0..1
  grow:f32,
  /// its seed: the phase of its wave and sway
  seed:f32,
  /// the length (pixels) of one straight piece of the drawn vine
  const seg:f32=12;
  /// how far it runs past its first and last slots' outer edges
  const endPad:f32=8;
  /// how far (pixels) it waves up and down
  const wave:f32=2.5;
  /// its radius (pixels) at its left end
  const r0:f32=3.2;
  /// its radius (pixels) at its right end
  const r1:f32=2.4;
  /// px of vine behind its tip that tapers, and that a slot or leaf takes to
  /// grow once the tip has passed it
  const tip:f32=40;
  /// a leaf's length (pixels)
  const leafLen:f32=13;
  /// a leaf's width (pixels)
  const leafWid:f32=5;
  /// the slot's husk hangs this far below the vine (its stalk's reach)
  pub const drop:f32=34;
  /// the vine's height (pixels) at `x`, waving gently
  fn at(v:Vine,x:f32)f32{return v.y+wave*@sin(x*0.045+v.seed*7);}
  /// where its tip has grown to (pixels)
  fn tipX(v:Vine)f32{return m.lerp(v.x0,v.x1,v.grow);}
  /// how far grown the vine is at `x`
  pub fn reached(v:Vine,x:f32)f32{return m.clamp01((v.tipX()-x)/tip);}
  /// draws it as far as it has grown, tapering to its tip, then its leaves
  /// between the slots, unfurling once passed and swaying with time `t`.
  pub fn draw(v:Vine,d:*Draw,t:f32)Allocator.Error!void{
    // where its tip is
    const end=v.tipX();
    if(end<=v.x0)return;
    // how many pieces the grown part takes
    const n:usize=@intFromFloat(@ceil((end-v.x0)/seg));
    // the piece's start, and how far along the bark it has run (pixels)
    var a:m.Vice(f32,2)=.{v.x0,v.at(v.x0)};
    var arc:f32=0;
    for(0..n)|i|{
      // the piece's end, and how far along the whole vine it is (0..1)
      const x=@min(v.x0+seg*m.f(i+1),end);
      const b:m.Vice(f32,2)=.{x,v.at(x)};
      const k=(x-v.x0)/@max(v.x1-v.x0,1);
      // its radius at either end, thinning to the tip
      const ra=m.lerp(r0,r1,(a[0]-v.x0)/@max(v.x1-v.x0,1))*@sqrt(m.clamp01((end-a[0])/tip));
      const rb=m.lerp(r0,r1,k)*@sqrt(m.clamp01((end-x)/tip));
      try d.limb(a,b,@max(ra,0.6),@max(@min(rb,ra),0.4),s.barkYoung,arc);
      arc+=b[0]-a[0];
      a=b;
    }
    // leaves between the slots, one up one down, swaying
    // where the next pair of leaves grows, and which pair it is
    var x=v.x0+endPad+v.step;
    var i:usize=0;
    while(x<v.x1-endPad-1):({x+=v.step;i+=1;}){
      // how far this pair has unfurled
      const open=v.reached(x);
      if(open<=0)continue;
      // how far it sways now, and where the pair grows from
      const sway=0.12*@sin(t*1.6+m.f(i)*1.9+v.seed*5);
      const base:m.Vice(f32,2)=.{x,v.at(x)};
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
  // the clock, and how many rows the grid takes
  const t=g.uiT();
  const nRows=(stacks.len+columns-1)/columns;
  for(0..nRows)|row|{
    // this row's vine
    const vine=rowVine(d,gx,py+gap*(m.f(row)+0.5),columns,rowSeed(side,row));
    try vine.draw(d,t);
  }
  for(stacks,0..)|slot,i|{
    // this slot's centre
    const cx=gx+gap*(m.f(i%columns)+0.5);
    const cy=py+gap*(m.f(i/columns)+0.5);
    // its slot, grown as far as its row's vine has
    var sl=Slot.around(.{cx,cy},gap,gap,hud.row(.belly,@unionInit(Pick,@tagName(side),i)),huskR/gap);
    sl.grown=rowVine(d,gx,cy,columns,rowSeed(side,i/columns)).reached(cx);
    sl.phase=m.f(i)*0.13;
    if(!try sl.draw(g,d))continue;
    const it=slot orelse continue;
    // lifted onto the cursor: only a faint trace stays behind
    const lifted=g.holds(@unionInit(play.Held,@tagName(side),i));
    // how full its stack is, 0..1
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
  // the width (pixels) of one column of the list
  const colW=(pw-60)/2;
  for(craft.handsOf(g.act),0..)|i,k|{
    // the recipe, and its line's left and top
    const r=craft.hand[i];
    const colx=px+70+m.f(k%2)*colW;
    const y=wy+42+weaveRowH*m.f(k/2);
    try g.rows.add(.{.x=colx-10,.y=y-24,.w=colW-20,.h=weaveRowH},hud.row(.belly,.{.weave=i}));
    // whether it is understood, and whether the belly holds enough to weave it
    const open=r.unlocked(&g.prog);
    const ok=open and craft.Crafter.can(g.player.inv.bag(),r);
    if(open)try icon.draw(d,r.out,.{colx+16,y},recipeR,g.uiT(),m.f(i)*0.5,if(ok)0.9 else 0.1,if(ok)255 else unreadyAlpha)
    else try d.leaf(.{colx+16,y+recipeR*0.8},-m.halfPi,recipeR*1.6,recipeR*0.7,s.unknown,0,m.f(i)*0.5);
    if(!open){
      // what must be understood first, or a question
      const needName=if(r.needs)|n|txt.research(n).name else txt.s.hud.unknown;
      _=try d.print(colx+40,y-14,s.textBody,s.unknown,txt.s.hud.recipeNeeds,.{needName});
      continue;
    }
    _=try d.print(colx+40,y-14,s.textBody,if(ok)s.white else s.dim,if(r.n>1)txt.s.hud.recipeMany else txt.s.hud.recipe,.{txt.item(r.out).name,r.n});
    // where the next ingredient is written (pixels from the left)
    var x=colx+44;
    for(r.in,0..)|ing,j|{
      // whether the belly holds enough of this ingredient
      const have=g.player.inv.worth(ing.item)>=ing.n;
      try d.grain(x+6,y+10,9,13,ing.item.info().col,if(have)0.7 else 0,m.f(j)*0.3);
      x=try d.print(x+14,y+5,s.textFine,if(have)s.white else s.dim,txt.s.hud.ingredient,.{ing.n,txt.item(ing.item).short})+10;
    }
  }
}
