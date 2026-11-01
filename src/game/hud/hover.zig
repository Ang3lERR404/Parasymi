//! what is under the cursor, on a trellis beside it: a structure (its name
//! and what it is doing), a plant (its name, how far grown and what it
//! gives or draws) or a resource node; bare ground by the top-left, its kind
//! and ley.
const lib=@import("../../lib.zig");
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=lib.engine.core.math;
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the chunk layer: tiles, occupancy, plant ids
const ck=lib.ck;
/// every plant kind's definition
const species=lib.species;
/// the game itself: what is hovered, the wolf's reach
const play=lib.play;
/// the structures registry: kinds and their descriptions
const st=lib.structures;
/// resource nodes and what they yield
const resources=lib.resources;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// every player-facing string
const txt=lib.txt;
/// bare ground's panel, by the top-left: its left edge (pixels)
const panelX=s.edge;
/// bare ground's panel: its top edge (pixels)
const panelY:f32=104;
/// where its text starts (pixels from the left)
const textX:f32=32;
/// where its text's top sits (pixels from the top)
const textTop:f32=116;
/// the card beside the cursor: how far off it (pixels, right and down)
const offset=m.Vice(f32,2){24,20};
/// the card's width for a structure, whose line of work is wider (pixels)
const cardW:f32=400;
/// the card's width for a plant (pixels)
const plantW:f32=360;
/// the card's width for a resource node (pixels)
const nodeW:f32=240;
/// the card's inner margin (pixels)
const margin:f32=14;
/// the height of one line (pixels)
const lineH:f32=24;
/// how close (pixels) the card may come to the screen's edges
const keep:f32=8;
/// where "too far" sits on the name's line, from the card's right
const farX:f32=96;
/// shown while something is hovered, but not over an open structure
/// panel (which shows all of this itself) nor a HUD panel (which has its own).
pub fn visible(g:*const play.Game)bool{return g.hover!=null and g.mode!=.structure and g.pointed==null;}
/// draws what is under the cursor: a structure's card, a plant's card, a
/// resource node's card, or, for bare ground, the top-left panel with its
/// kind and ley (and "too far" when out of reach).
pub fn draw(g:*play.Game,d:*Draw,screenW:f32,screenH:f32)Allocator.Error!void{
  // the hovered tile, its chunk, and whether the wolf can reach it
  const h=g.hover.?;
  const c=g.world.chunkOfTile(h[0],h[1]) orelse return;
  const near=g.player.inReach(h[0],h[1]);
  if(g.structs.at(&g.world,h[0],h[1]))|j|return structure(g,d,screenW,screenH,g.structs.get(j),near);
  if(g.plantAt(h))|i|return plant(g,d,screenW,screenH,i,near);
  // the tile's index within its chunk
  const t=ck.localIndex(h[0],h[1]);
  if(c.res[t]>0 and c.occ[t]==.none){
    // what the node yields
    const item=resources.of(c.kind[t]).?.item;
    // where the card's first line goes
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
fn card(g:*const play.Game,d:*Draw,screenW:f32,screenH:f32,w:f32,lines:f32,near:bool)Allocator.Error!m.Vice(f32,2){
  // the card's height, and its corner kept on screen
  const ch=lineH*lines+2*margin;
  const x=@max(@min(g.mouse[0]+offset[0],screenW-w-keep),keep);
  const y=@max(@min(g.mouse[1]+offset[1],screenH-ch-keep),keep);
  try d.trellis(x,y,w,ch,s.card,0.7);
  if(!near)_=try d.text(x+w-farX,y+margin+2,s.textNote,s.dim,txt.s.hud.tooFar);
  return.{x+margin,y+margin};
}
/// a structure's card: its name, what it is doing (its `describe` hook),
/// and for one that opens, a hint how to open it.
fn structure(g:*play.Game,d:*Draw,screenW:f32,screenH:f32,sp:*const st.Structure,near:bool)Allocator.Error!void{
  // whether it opens as a store, and where the card's first line goes
  const opens=sp.def().store;
  const at=try card(g,d,screenW,screenH,cardW,if(opens)3 else 2,near);
  _=try d.text(at[0],at[1],s.textLabel,s.gold,txt.structure(sp.kind()));
  try st.describe(sp,d,&g.prog,at[0],at[1]+lineH);
  if(opens)_=try d.text(at[0],at[1]+2*lineH,s.textNote,if(near)s.gold else s.dim,txt.s.hud.openHint);
}
/// a plant's card: its name, a tendril of how far grown (with its stage),
/// then what it yields and how healthy it is, or for a bloom whether it
/// radiates and over how many links; and whether it draws radiance.
fn plant(g:*play.Game,d:*Draw,screenW:f32,screenH:f32,i:ck.PlantId,near:bool)Allocator.Error!void{
  // the plant, its kind's definition, and the garden's radiance network
  const p=g.plants.list.get(i.idx());
  const def=species.get(p.sp);
  const rad=&g.eco.radiance;
  // whether the network has caught up to this plant yet
  const known=i.idx()<rad.powered.items.len;
  // a bloom waiting on its network, or a plant that draws radiance, says so
  const waits=(def.radiance>0 and !(known and rad.radiating.items[i.idx()])) or def.needsRadiance;
  // where the card's first line goes, and the current line's left and top
  const at=try card(g,d,screenW,screenH,plantW,if(waits)4 else 3,near);
  const x=at[0];
  var y=at[1];
  _=try d.text(x,y,s.textLabel,s.white,txt.plant(p.sp).name);
  y+=lineH;
  try d.tendril(x,y+4,140,s.barH,s.growth,p.growth,0.5);
  if(def.stages>0){
    // which stage it is in, and that stage's name
    const k=def.stage(p.growth);
    const name=txt.nth(txt.plant(p.sp).stages orelse "",k);
    _=try d.print(x+152,y,s.textNote,s.dim,txt.s.hud.stage,.{name,k+1,def.stages,p.growth*100});
  }else{
    _=try d.print(x+152,y,s.textNote,s.dim,txt.s.hud.growth,.{p.growth*100});
  }
  y+=lineH;
  if(def.radiance>0){
    // a bloom: it yields nothing; it radiates, or waits on its network
    // how many radiance links this bloom has
    var links:u32=0;
    for(rad.links.items)|l|{
      if(l.a==i or l.b==i)links+=1;
    }
    // whether this bloom radiates now
    const lit=known and rad.radiating.items[i.idx()];
    _=try d.print(x,y,s.textBody,if(lit)s.gold else s.dim,txt.s.hud.bloom,.{if(lit)txt.s.hud.radiating else txt.s.hud.dark,links,p.health*100});
    if(!lit)_=try d.text(x,y+lineH,s.textNote,s.dim,txt.s.hud.noMature);
    return;
  }
  // what it yields, or a question when the gardener has not learned it
  const yields=if(g.prog.yieldKnown(p.sp))txt.item(def.yields).short else txt.s.hud.unknownYield;
  _=try d.print(x,y,s.textBody,s.gold,txt.s.hud.plant,.{yields,p.essence,p.health*100});
  if(def.needsRadiance){
    // whether it is drawing radiance now
    const lit=known and rad.powered.items[i.idx()];
    _=try d.text(x,y+lineH,s.textNote,if(lit)s.gold else s.dim,if(lit)txt.s.hud.drawingRadiance else txt.s.hud.withering);
  }
}
