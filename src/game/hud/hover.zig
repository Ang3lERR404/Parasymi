//! what is under the cursor, on a trellis beside it: a structure (its name
//! and what it is doing), a plant (its name, how far grown and what it
//! gives or draws) or a resource node; bare ground by the top-left, its kind
//! and ley.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const ck=lib.ck;
const species=lib.species;
const play=lib.play;
const st=lib.structures;
const resources=lib.resources;
const Draw=lib.engine.ui.draw.Draw;
const s=lib.style;
const txt=lib.txt;
/// bare ground's panel, by the top-left
const panelX=s.edge;
const panelY:f32=104;
const textX:f32=32;
const textTop:f32=116;
/// the card beside the cursor: how far off it, its widths (a structure's
/// line of work is wider), margin, line height, and how far it keeps from
/// the screen's edges
const offset=[2]f32{24,20};
const cardW:f32=400;
const plantW:f32=360;
const nodeW:f32=240;
const margin:f32=14;
const lineH:f32=24;
const keep:f32=8;
/// where "too far" sits on the name's line, from the card's right
const farX:f32=96;
/// (a structure's open panel shows all of this itself; a HUD panel under
/// the cursor has its own)
pub fn visible(g:*const play.Game)bool{return g.hover!=null and g.mode!=.structure and g.pointed==null;}
pub fn draw(g:*play.Game,d:*Draw,screenW:f32,screenH:f32)Allocator.Error!void{
  const h=g.hover.?;
  const c=g.world.chunkOfTile(h[0],h[1]) orelse return;
  const near=g.player.inReach(h[0],h[1]);
  if(g.structs.at(&g.world,h[0],h[1]))|j|return structure(g,d,screenW,screenH,g.structs.get(j),near);
  if(g.plants.at(&g.world,h[0],h[1]))|i|return plant(g,d,screenW,screenH,i,near);
  const t=ck.localIndex(h[0],h[1]);
  if(c.res[t]>0 and c.occ[t]==.none){
    const item=resources.of(c.kind[t]).?.item;
    const at=try card(g,d,screenW,screenH,nodeW,1,near);
    _=try d.print(at[0],at[1],s.textLabel,item.info().col,txt.s.hud.node,.{txt.item(item).name,c.res[t]});
    return;
  }
  try d.trellis(panelX,panelY,360,60,s.card,0.6);
  _=try d.print(textX,textTop,s.textLabel,s.white,txt.s.hud.tile,.{txt.tile(c.kind[t]),c.leyCap[t]});
  if(!near)_=try d.text(textX+248,textTop+2,s.textNote,s.dim,txt.s.hud.tooFar);
}
/// a card `w` wide and `lines` lines high beside the cursor, kept on
/// screen; returns where its first line goes. Out of reach, it says so.
fn card(g:*const play.Game,d:*Draw,screenW:f32,screenH:f32,w:f32,lines:f32,near:bool)Allocator.Error![2]f32{
  const ch=lineH*lines+2*margin;
  const x=@max(@min(g.mouse[0]+offset[0],screenW-w-keep),keep);
  const y=@max(@min(g.mouse[1]+offset[1],screenH-ch-keep),keep);
  try d.trellis(x,y,w,ch,s.card,0.7);
  if(!near)_=try d.text(x+w-farX,y+margin+2,s.textNote,s.dim,txt.s.hud.tooFar);
  return.{x+margin,y+margin};
}
fn structure(g:*play.Game,d:*Draw,screenW:f32,screenH:f32,sp:*const st.Structure,near:bool)Allocator.Error!void{
  const opens=sp.def().store;
  const at=try card(g,d,screenW,screenH,cardW,if(opens)3 else 2,near);
  _=try d.text(at[0],at[1],s.textLabel,s.gold,txt.structure(sp.kind()));
  try st.describe(sp,d,&g.prog,at[0],at[1]+lineH);
  if(opens)_=try d.text(at[0],at[1]+2*lineH,s.textNote,if(near)s.gold else s.dim,txt.s.hud.openHint);
}
fn plant(g:*play.Game,d:*Draw,screenW:f32,screenH:f32,i:ck.PlantId,near:bool)Allocator.Error!void{
  const p=g.plants.list.get(i.idx());
  const def=species.get(p.sp);
  const rad=&g.eco.radiance;
  const known=i.idx()<rad.powered.items.len;
  // a bloom waiting on its network, or a plant that draws radiance, says so
  const waits=(def.radiance>0 and !(known and rad.radiating.items[i.idx()])) or def.needsRadiance;
  const at=try card(g,d,screenW,screenH,plantW,if(waits)4 else 3,near);
  const x=at[0];
  var y=at[1];
  _=try d.text(x,y,s.textLabel,s.white,txt.plant(p.sp).name);
  y+=lineH;
  try d.tendril(x,y+4,140,s.barH,s.growth,p.growth,0.5);
  if(def.stages>0){
    const k=def.stage(p.growth);
    const name=txt.nth(txt.plant(p.sp).stages orelse "",k);
    _=try d.print(x+152,y,s.textNote,s.dim,txt.s.hud.stage,.{name,k+1,def.stages,p.growth*100});
  }else{
    _=try d.print(x+152,y,s.textNote,s.dim,txt.s.hud.growth,.{p.growth*100});
  }
  y+=lineH;
  if(def.radiance>0){
    // a bloom: it yields nothing; it radiates, or waits on its network
    var links:u32=0;
    for(rad.links.items)|l|{
      if(l.a==i or l.b==i)links+=1;
    }
    const lit=known and rad.radiating.items[i.idx()];
    _=try d.print(x,y,s.textBody,if(lit)s.gold else s.dim,txt.s.hud.bloom,.{if(lit)txt.s.hud.radiating else txt.s.hud.dark,links,p.health*100});
    if(!lit)_=try d.text(x,y+lineH,s.textNote,s.dim,txt.s.hud.noMature);
    return;
  }
  const yields=if(g.prog.yieldKnown(p.sp))txt.item(def.yields).short else txt.s.hud.unknownYield;
  _=try d.print(x,y,s.textBody,s.gold,txt.s.hud.plant,.{yields,p.essence,p.health*100});
  if(def.needsRadiance){
    const lit=known and rad.powered.items[i.idx()];
    _=try d.text(x,y+lineH,s.textNote,if(lit)s.gold else s.dim,if(lit)txt.s.hud.drawingRadiance else txt.s.hud.withering);
  }
}
