//! prepared worlds for showcasing and testing (`--demo`, `--stress`).
//! Not part of play: they place things on the gardener's behalf.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator placing plants and structures may need
const Allocator=std.mem.Allocator;
/// the chunk grid: tiles, their nodes and occupancy
const ck=lib.ck;
/// the species registry, for the plants put down
const species=lib.species;
/// the research tree, whose studies are marked known
const prog=lib.progression;
/// the game's state and its tick
const play=lib.play;
/// the engine package
const engine=lib.engine;
/// all the maths: tiles, rings, directions
const m=engine.core.math;
/// the halo structure: its reach and the points of its ring
const halo=lib.haloStructure;
/// the weaving recipes, for the germinator's chosen bulb
const craft=lib.craft;
/// the structures registry: placing, feeding, configuring
const st=lib.structures;
/// what can be held: items and stack sizes
const items=lib.items;
/// the whole running game the setups fill
const Game=play.Game;
/// a starter garden around the player plus the first automation, fast-forwarded.
pub fn demo(g:*Game,seconds:f32)Allocator.Error!void{
  // the wolf's tile, the garden's centre
  const cx,const cz=m.tileAt(g.player.pos);
  // the row being planted
  var dz:i32=-4;
  while(dz<=4):(dz+=1){
    // the column being planted
    var dx:i32=-6;
    while(dx<=6):(dx+=1){
      if(@abs(dx)<=1 and @abs(dz)<=1)continue;
      // lumenroots west and on even rows, thornleeches east, else bare
      const sp:species.Id=if(dx>2).thornleech else if(dx<-2 or @mod(dz,2)==0).lumenroot else continue;
      _=try g.plants.place(g.gpa,&g.world,cx+dx,cz+dz,sp,g.rng.float());
    }
  }
  // a lumenroot harvested by conduits into a cache, a germinator and research
  // bloom already fed, the new plant forms around
  for([_]prog.Id{.leySight,.driftSpores,.rootCommunion,.canopyWeaving,.arsthraxia,.sapSatellites,.condensingWhorl})|id|g.prog.done.insert(id);
  _=try g.structs.place(g.gpa,&g.world,cx-2,cz-3,.conduit,0,0.1);
  _=try g.structs.place(g.gpa,&g.world,cx-1,cz-3,.conduit,0,0.2);
  _=try g.structs.place(g.gpa,&g.world,cx,cz-3,.sapCache,0,0.3);
  if(try g.structs.place(g.gpa,&g.world,cx-2,cz+5,.germinator,0,0.4)){
    // the germinator just put down
    const j=g.structs.at(&g.world,cx-2,cz+5).?;
    _=g.structs.insert(&g.prog,j,.fibre,20);
    _=g.structs.insert(&g.prog,j,.starlight,20);
  }
  if(try g.structs.place(g.gpa,&g.world,cx+1,cz+5,.arsthraxia,0,0.5)){
    g.prog.select(.hungeringTendrils);
    // the arsthraxia just put down
    const j=g.structs.at(&g.world,cx+1,cz+5).?;
    _=g.structs.insert(&g.prog,j,.essence,20);
    _=g.structs.insert(&g.prog,j,.grit,20);
  }
  // the light grid over them: a solcyriphon between the germinator and the
  // arsthraxia (which studies only in its light), blooms carrying it on to
  // the two sporecasters (they cast and take in only lit)
  try grown(g,cx,cz+4,.solcyriphon,0.15);
  try grown(g,cx-3,cz+8,.bloom,0.25);
  try grown(g,cx+8,cz+3,.bloom,0.35);
  try radiantGarden(g,cx,cz-13);
  _=try g.plants.place(g.gpa,&g.world,cx-6,cz+6,.hollowheart,0.7);
  _=try g.plants.place(g.gpa,&g.world,cx-5,cz-1,.driftwisp,0.8);
  _=try g.plants.place(g.gpa,&g.world,cx-4,cz+2,.driftwisp,0.9);
  try digger(g,cx,cz);
  try lineages(g,cx,cz);
  try confluences(g,cx,cz);
  try convergent(g,cx,cz);
  // seconds fast-forwarded so far
  var t:f32=0;
  while(t<seconds):(t+=play.tickTime)try g.step();
  try haloGarden(g,cx,cz);
  try grove(g,cx,cz);
  // the germinator, its seeds woven, set to a bulb woven from five things,
  // fed for a while: all its cups pour
  if(g.structs.at(&g.world,cx-2,cz+5))|j|{
    // the arsthraxia's weave, among all a germinator may be set to
    const r=for(craft.all)|r|{
      if(craft.hand[r].out==.arsthraxia)break r;
    }else unreachable;
    st.choose(g.structs.get(j),&g.prog,r);
    for(craft.hand[r].in)|ing|_=g.structs.insert(&g.prog,j,ing.item,items.stack);
  }
  _=g.player.inv.add(.grit,34);
  _=g.player.inv.add(.fibre,21);
  _=g.player.inv.add(.starlight,7);
  _=g.player.inv.add(.seedLumenroot,5);
  _=g.player.inv.add(.conduit,6);
  _=g.player.inv.add(.rootDigger,2);
}
/// how many nebularbors the demo's grove holds, and how far into their
/// lives they are (real trees, a little aged)
const groveTrees=9;
/// trees along each row of the grove, 3 tiles apart
const groveRow=3;
/// (how far into their lives)
const groveGrown:f32=0.25;
/// a grove of nebularbors on the nearest moss east of the garden, side by
/// side, whose leaves together breathe a cloud heavy enough to rain (one
/// alone never does)
fn grove(g:*Game,cx:i32,cz:i32)Allocator.Error!void{
  // the first tree, on the nearest moss it fits on
  var first:?st.Id=null;
  var r:i32=0;
  outer:while(r<40):(r+=1){
    // the walk round that ring
    var it=m.ring(r);
    while(it.next())|o|{
      if(!g.structs.canPlace(&g.world,cx+14+o[0],cz+o[1],.nebularbor))continue;
      first=try nearest(g,cx+14+o[0],cz+o[1],.nebularbor,0.3);
      break:outer;
    }
  }
  const f=first orelse return;
  // where it stands; the rest crowd round it
  const at=m.Vice(i32,2){g.structs.get(f).x,g.structs.get(f).y};
  g.structs.get(f).grown=groveGrown;
  for(1..groveTrees)|k|{
    // the next tree, as near the first as it fits
    const j=try nearest(g,at[0]+@as(i32,@intCast(k%groveRow))*3,at[1]+@as(i32,@intCast(k/groveRow))*3,.nebularbor,0.3+0.2*m.f(k)) orelse continue;
    g.structs.get(j).grown=groveGrown;
  }
  // mire lilies grown along the grove's near edge, where its rain soaks
  // and pools, so they float on it
  for(0..groveLilies)|k|{
    // this lily's tile
    const x=at[0]+@as(i32,@intCast(k))*2;
    const z=at[1]-1;
    _=try g.plants.placeEx(g.gpa,&g.world,x,z,.{.x=x,.y=z,.chunk=undefined,.tile=undefined,.sp=.mireLily,.seed=0.2+0.15*m.f(k),.growth=1});
  }
  // a patch of bare soil beyond them, a grown moss creeper in its middle,
  // left to turn it to moss as the grove's rain soaks it
  var dz:i32=2;
  while(dz<=6):(dz+=1){
    var dx:i32=0;
    while(dx<=6):(dx+=1){
      // this tile of the patch
      const c=g.world.chunkOfTile(at[0]+dx,at[1]-dz) orelse continue;
      const t=ck.localIndex(at[0]+dx,at[1]-dz);
      if(c.occ[t]!=.none)continue;
      c.kind[t]=.soil;
      c.res[t]=0;
      c.dirty=true;
    }
  }
  _=try g.plants.placeEx(g.gpa,&g.world,at[0]+3,at[1]-4,.{.x=at[0]+3,.y=at[1]-4,.chunk=undefined,.tile=undefined,.sp=.mossCreeper,.seed=0.4,.growth=1});
  // a grown storm spire between the lilies, holding ley crystals, left to
  // charge in the grove's rain and strike its cloud into a storm
  if(try nearest(g,at[0]+1,at[1]-1,.stormSpire,0.6))|j|{
    g.structs.get(j).grown=1;
    _=g.structs.insert(&g.prog,j,.leyCrystal,5);
  }
}
/// how many mire lilies grow along the demo grove's edge
const groveLilies=4;
/// a symbiote and a parasite two tiles apart, left to converge (a
/// confluence's stages are viewed with `--plant=confluence`).
fn confluences(g:*Game,cx:i32,cz:i32)Allocator.Error!void{
  _=try g.plants.place(g.gpa,&g.world,cx+4,cz-7,.lumenroot,0.3);
  _=try g.plants.place(g.gpa,&g.world,cx+6,cz-7,.thornleech,0.6);
}
/// the convergent structures south of the confluences: a weftstone
/// floating among stone, and two driftbraids trading, one fed fibre, the
/// other grit
fn convergent(g:*Game,cx:i32,cz:i32)Allocator.Error!void{
  for([_]prog.Id{.wovenStone,.braidedDrift})|id|g.prog.done.insert(id);
  // the weftstone over the nearest stone it can reach
  // the ring being searched, outward from the centre
  var r:i32=3;
  outer:while(r<16):(r+=1){
    // the walk round that ring
    var it=m.ring(r);
    while(it.next())|o|{
      // the tile tried
      const x=cx+o[0];
      const z=cz+o[1];
      if(!mineralAround(g,x,z)or!g.structs.canPlace(&g.world,x,z,.weftstone))continue;
      _=try g.structs.place(g.gpa,&g.world,x,z,.weftstone,0,0.4);
      break:outer;
    }
  }
  // the two driftbraids, west and east, paired once both stand
  const a=try nearest(g,cx-5,cz+12,.driftbraid,0.2);
  const b=try nearest(g,cx+3,cz+12,.driftbraid,0.7);
  if(a!=null and b!=null){
    st.configure(&g.structs,a.?,&g.prog);
    st.configure(&g.structs,b.?,&g.prog);
    _=g.structs.insert(&g.prog,a.?,.fibre,20);
    _=g.structs.insert(&g.prog,b.?,.grit,20);
  }
  try loom(g,cx,cz+16);
}
/// a monfris weaving a weftstone, fed by four Vultrixi, each pulling one
/// of its kinds out of a sap cache beside it
fn loom(g:*Game,cx:i32,cz:i32)Allocator.Error!void{
  for([_]prog.Id{.interweaving,.sharedNerves,.wovenStone})|id|g.prog.done.insert(id);
  // the monfris, and where it stands
  const j=try nearest(g,cx,cz,.monfris,0.5) orelse return;
  const at=m.Vice(i32,2){g.structs.get(j).x,g.structs.get(j).y};
  // the weftstone's weave, among the monfris's
  const w=for(craft.loom)|w|{
    if(craft.hand[w].out==.weftstone)break w;
  }else unreachable;
  st.choose(g.structs.get(j),&g.prog,w);
  // the weave it is set to
  const r=craft.hand[w];
  for(r.in,0..)|ing,k|{
    // which side this ingredient's cache goes, and where
    const side:i32=if(k%2==0)-1 else 1;
    const x=at[0]+side*4;
    const z=at[1]-2+3*@as(i32,@intCast(k/2));
    // the cache, stocked with the ingredient
    const cache=try nearest(g,x,z,.sapCache,0.3+0.1*m.f(k)) orelse continue;
    _=g.structs.insert(&g.prog,cache,ing.item,40);
    // the cache, and the column west or east of it the vultrixi floats over
    const c=g.structs.get(cache);
    const vx=c.x-side;
    if(!try g.structs.place(g.gpa,&g.world,vx,c.y,.vultrixi,0,0.2+0.15*m.f(k)))continue;
    st.configure(&g.structs,g.structs.floaterAt(vx,c.y).?,&g.prog);
    st.configure(&g.structs,j,&g.prog);
  }
}
/// the last corner's bloom starts this far grown and, full of sky and
/// linked to no kin, grows 1/`lastSpan` a second: done ~20 s in
const lastFrom:f32=0.85;
/// the last corner's bloom's growing time (s)
const lastSpan:f32=133;
/// west of the garden, put down after the fast-forward so it plays out
/// live: three grown blooms on the points of a ring and a fourth
/// finishing (in ~20 s, time to walk over); as it does, the halo forms
/// and a diamond gathers at its heart. A polyp grows in beside the heart,
/// feeding on the blooms' light and letting its flowers drift. Two vespers draw on the east point's
/// bloom: one inside the ring, which it keeps once the bloom is drawn
/// away, one outside it, which only the diamond's wider field reaches.
fn haloGarden(g:*Game,cx:i32,cz:i32)Allocator.Error!void{
  // the halo's reach in tiles, and its heart's tile, west of the garden
  const r=halo.reachTiles;
  const x=cx-19;
  const z=cz+2;
  if(try g.structs.place(g.gpa,&g.world,x+2,z+1,.polyp,0,0.45))g.structs.sprout(g.structs.at(&g.world,x+2,z+1).?);
  for(halo.points,0..)|c,i|{
    // this bloom's tile, on a point of the ring
    const bx=x+c[0]*r;
    const bz=z+c[1]*r;
    _=try g.plants.placeEx(g.gpa,&g.world,bx,bz,.{
      .x=bx,.y=bz,.chunk=undefined,.tile=undefined,.sp=.bloom,
      .seed=0.31+0.17*m.f(i),.growth=if(i==3)lastFrom else 1,.span=if(i==3)lastSpan else 1e9,.mana=10,
    });
  }
  _=try g.plants.place(g.gpa,&g.world,x+3,z,.vesper,0.5);
  _=try g.plants.place(g.gpa,&g.world,x+5,z+3,.vesper,0.6);
  // the light the vespers live on, linked to the ring's blooms
  try grown(g,x+1,z-3,.solcyriphon,0.45);
}
/// a grown plant of `sp` at tile `x`,`z` (a floater at its centre), its own `seed`
fn grown(g:*Game,x:i32,z:i32,sp:species.Id,seed:f32)Allocator.Error!void{
  _=try g.plants.placeEx(g.gpa,&g.world,x,z,.{.x=x,.y=z,.chunk=undefined,.tile=undefined,.sp=sp,.seed=seed,.growth=1,.mana=10});
}
/// north of the garden, the light grid's own plants (docs/radiant-plants.md):
/// a solcyriphon pouring its night beam into a bloom below it, which
/// carries it on; an astrocyme filling beside them; a heliocyra casting a
/// strip east from the solcyriphon's field and a second one bending it
/// south; and a second solcyriphon over a lumenroot (overdriven at night)
/// with a halcyra beside it, guarding it
fn radiantGarden(g:*Game,cx:i32,cz:i32)Allocator.Error!void{
  for([_]prog.Id{.seedSplicing,.temperedLight,.bentLight,.halcyonVeil,.heldLight})|id|g.prog.done.insert(id);
  try grown(g,cx,cz,.solcyriphon,0.11);
  try grown(g,cx,cz,.bloom,0.21);
  try grown(g,cx-3,cz+1,.astrocyme,0.31);
  try grown(g,cx+1,cz+2,.heliocyra,0.41);
  try grown(g,cx+6,cz+2,.heliocyra,0.51);
  g.plants.list.items(.dir)[g.plants.len()-1]=1;
  try grown(g,cx+6,cz+5,.vesper,0.61);
  try grown(g,cx-6,cz-3,.solcyriphon,0.71);
  try grown(g,cx-6,cz-3,.lumenroot,0.81);
  try grown(g,cx-5,cz-3,.halcyra,0.91);
}
/// the nearest free spot beside a resource node gets a root-digger, with a
/// sap cache next to it to fill.
fn digger(g:*Game,cx:i32,cz:i32)Allocator.Error!void{
  g.prog.done.insert(.deepRooting);
  // the ring being searched, outward from the centre
  var r:i32=2;
  while(r<12):(r+=1){
    // the walk round that ring
    var it=m.ring(r);
    while(it.next())|o|{
      // the tile tried
      const x=cx+o[0];
      const z=cz+o[1];
      if(!nodeBeside(g,x,z)or!g.structs.canPlace(&g.world,x,z,.rootDigger))continue;
      _=try g.structs.place(g.gpa,&g.world,x,z,.rootDigger,0,0.6);
      for(m.dirs)|d|{
        // the way beside the digger being tried
        const v=m.dirVec(d);
        if(try g.structs.place(g.gpa,&g.world,x+v.x,z+v.z,.sapCache,0,0.7))return;
      }
      return;
    }
  }
}
/// the lineages' structures, south of the garden's conduit line: each put
/// down on the nearest spot it may stand to where it is shown, fed what
/// it works from.
fn lineages(g:*Game,cx:i32,cz:i32)Allocator.Error!void{
  g.prog.done.insert(.livingLooms);
  g.prog.done.insert(.lithophagy);
  g.prog.done.insert(.braidedRoots);
  // a sporecaster fed by a conduit line sends over the garden to one
  // emptying into a cache
  g.prog.done.insert(.sporeCasting);
  try layout(g,cx+8,cz+3,&.{
    .{.at=.{0,0},.k=.sapCache},.{.at=.{1,0},.k=.conduit},.{.at=.{2,0},.k=.sporecaster},
  },&.{.essence,.fibre,.leyShard,.grit});
  try layout(g,cx-3,cz+7,&.{.{.at=.{0,0},.k=.sporecaster},.{.at=.{1,0},.k=.sapCache}},&.{});
  // the two sporecasters, found once both stand, to pair
  var from:?st.Id=null;
  var to:?st.Id=null;
  for(g.structs.list.items,0..)|*s,i|if(s.kind()==.sporecaster){
    if(from==null)from=.of(i)else to=.of(i);
  };
  if(from!=null and to!=null)_=g.structs.pairWith(from.?,to.?);
  // a crown in the lumenroot bed, gathering it
  _=try nearest(g,cx-2,cz+1,.gatheringCrown,0.55);
  try braids(g,cx-10,cz-2);
  // a ganglion splitting a line three ways, each branch into a cache
  try layout(g,cx-10,cz+4,&.{
    .{.at=.{0,1},.k=.sapCache},.{.at=.{1,1},.k=.conduit},
    .{.at=.{2,1},.k=.ganglion},
    .{.at=.{2,0},.k=.conduit,.dir=3},.{.at=.{3,1},.k=.conduit},.{.at=.{2,2},.k=.conduit,.dir=1},
    .{.at=.{2,-1},.k=.sapCache},.{.at=.{4,1},.k=.sapCache},.{.at=.{2,3},.k=.sapCache},
  },&.{.essence,.fibre,.leyShard});
  // the nearest spot with stone round it to eat, its cup emptied into a cache
  // the ring being searched, outward from the centre
  var r:i32=3;
  outer:while(r<14):(r+=1){
    // the walk round that ring
    var it=m.ring(r);
    while(it.next())|o|{
      // the tile tried
      const x=cx+o[0];
      const z=cz+o[1];
      if(!mineralAround(g,x,z)or!g.structs.canPlace(&g.world,x,z,.lithophage))continue;
      _=try g.structs.place(g.gpa,&g.world,x,z,.lithophage,0,0.35);
      for(m.dirs)|d|{
        // the way beside it being tried
        const v=m.dirVec(d);
        // (never over the stone it eats)
        // the chunk beside it (none: not streamed in)
        const c=g.world.chunkOfTile(x+v.x,z+v.z) orelse continue;
        if(c.res[ck.localIndex(x+v.x,z+v.z)]>0)continue;
        if(try g.structs.place(g.gpa,&g.world,x+v.x,z+v.z,.sapCache,0,0.45))break;
      }
      break:outer;
    }
  }
  if(try nearest(g,cx+3,cz-4,.loomfern,0.15))|j|{
    _=g.structs.insert(&g.prog,j,.essence,3);
    // the loomfern
    const s=g.structs.get(j);
    // a cache beside it takes its fibre, so it is always weaving
    for(m.dirs)|d|{
      // the way beside it being tried
      const v=m.dirVec(d);
      if(try g.structs.place(g.gpa,&g.world,s.x+v.x,s.y+v.z,.sapCache,0,0.25))break;
    }
  }
}
/// a line of braided conduits carrying four kinds at once from one cache to
/// another, turning a corner, on the free ground nearest (x, z):
///   cache > braid > braid (turning)
///                   braid (fed from its side) > cache
fn braids(g:*Game,x:i32,z:i32)Allocator.Error!void{
  // each piece's place, kind and facing, from the first cache
  const at=[_]m.Vice(i32,2){.{0,0},.{1,0},.{2,0},.{2,1},.{3,1}};
  const kinds=[_]st.Kind{.sapCache,.braidedConduit,.braidedConduit,.braidedConduit,.sapCache};
  const dirs=[_]m.Dir{0,0,1,0,0};
  // the ring being searched, outward from (x, z)
  var r:i32=0;
  while(r<8):(r+=1){
    // the walk round that ring
    var it=m.ring(r);
    search:while(it.next())|o|{
      for(at,kinds)|a,k|if(!g.structs.canPlace(&g.world,x+o[0]+a[0],z+o[1]+a[1],k))continue:search;
      for(at,kinds,dirs,0..)|a,k,d,i|_=try g.structs.place(g.gpa,&g.world,x+o[0]+a[0],z+o[1]+a[1],k,d,0.1*m.f(i));
      // the first cache, stocked with all four kinds
      const src=g.structs.at(&g.world,x+o[0],z+o[1]).?;
      for([_]items.Item{.essence,.fibre,.leyShard,.grit})|item|_=g.structs.insert(&g.prog,src,item,items.stack);
      return;
    }
  }
}
/// one structure of a layout: where it stands from the first, its kind
/// and which way it faces
const Piece=struct{
  /// its tile, from the layout's first piece
  at:m.Vice(i32,2),
  /// what kind of structure it is
  k:st.Kind,
  /// which way it faces, 0..3
  dir:m.Dir=0
};
/// a set of structures put down together on the free ground nearest (x, z),
/// the first (a cache) stocked with `stock`
fn layout(g:*Game,x:i32,z:i32,pieces:[]const Piece,stock:[]const items.Item)Allocator.Error!void{
  // the ring being searched, outward from (x, z)
  var r:i32=0;
  while(r<8):(r+=1){
    // the walk round that ring
    var it=m.ring(r);
    search:while(it.next())|o|{
      for(pieces)|p|if(!g.structs.canPlace(&g.world,x+o[0]+p.at[0],z+o[1]+p.at[1],p.k))continue:search;
      for(pieces,0..)|p,i|_=try g.structs.place(g.gpa,&g.world,x+o[0]+p.at[0],z+o[1]+p.at[1],p.k,p.dir,0.1*m.f(i));
      // the first piece, stocked
      const src=g.structs.at(&g.world,x+o[0]+pieces[0].at[0],z+o[1]+pieces[0].at[1]).?;
      for(stock)|item|_=g.structs.insert(&g.prog,src,item,items.stack);
      return;
    }
  }
}
/// put a structure of kind `k` down on the free spot nearest (x, z) it may
/// stand on.
fn nearest(g:*Game,x:i32,z:i32,k:st.Kind,seed:f32)Allocator.Error!?st.Id{
  // the ring being searched, outward from (x, z)
  var r:i32=0;
  while(r<8):(r+=1){
    // the walk round that ring
    var it=m.ring(r);
    while(it.next())|o|{
      if(!g.structs.canPlace(&g.world,x+o[0],z+o[1],k))continue;
      _=try g.structs.place(g.gpa,&g.world,x+o[0],z+o[1],k,0,seed);
      return g.structs.at(&g.world,x+o[0],z+o[1]);
    }
  }
  return null;
}
/// a free grit or ley node on one of the eight tiles round (x, z)
fn mineralAround(g:*const Game,x:i32,z:i32)bool{
  // the walk round the eight tiles
  var it=m.ring(1);
  while(it.next())|o|{
    // the chunk holding that tile (none: not streamed in), and the tile in it
    const c=g.world.chunkOfTile(x+o[0],z+o[1]) orelse continue;
    const t=ck.localIndex(x+o[0],z+o[1]);
    if(c.res[t]>0 and c.occ[t]==.none and (c.kind[t]==.soil or c.kind[t]==.stone or c.kind[t]==.ley))return true;
  }
  return false;
}
/// whether a free node with something left lies on a tile beside (x, z)
fn nodeBeside(g:*const Game,x:i32,z:i32)bool{
  for(m.dirs)|d|{
    // the way being looked
    const v=m.dirVec(d);
    // the chunk holding that tile (none: not streamed in), and the tile in it
    const c=g.world.chunkOfTile(x+v.x,z+v.z) orelse continue;
    const t=ck.localIndex(x+v.x,z+v.z);
    if(c.res[t]>0 and c.occ[t]==.none)return true;
  }
  return false;
}
/// fill a side x side field with the three first species at random (perf testing).
pub fn stress(g:*Game,side:i32)Allocator.Error!void{
  // the wolf's tile, the field's centre
  const cx,const cz=m.tileAt(g.player.pos);
  // half the field's side
  const r=@divFloor(side,2);
  try g.world.stream(g.focus(),@divFloor(r,ck.sizeTiles)+2,1<<20);
  // the species planted
  const first=[_]species.Id{.lumenroot,.thornleech,.vesper};
  // the row being planted
  var dz:i32=-r;
  while(dz<r):(dz+=1){
    // the column being planted
    var dx:i32=-r;
    while(dx<r):(dx+=1){
      // pick one of the three species uniformly
      const sp=first[m.floorTo(usize,g.rng.float()*m.f(first.len))];
      _=try g.plants.place(g.gpa,&g.world,cx+dx,cz+dz,sp,g.rng.float());
    }
  }
}
/// act 2's garden (`--act2 --demo`), run on to show every constellate combo
/// at work: a planted strange seed with its fragments out; a core with four
/// petals put down round it (a yielder); a stem with four buds round it (a
/// heart), four petals put down by it once it has bloomed, run on until it
/// has settled into a builder and fed fragments; tendrils from the seed and
/// the yielder to the heart. Placed on the gardener's behalf, then the
/// garden runs on `seconds` (petals put down partway)
pub fn act2(g:*Game,seconds:f32)play.Error!void{
  // the tile the gardener stands on
  const c=m.tileAt(g.player.pos);
  // put kind `k` down at `dx`,`dz` from the gardener, as by hand
  const put=struct{
    /// put it down; whether it fit
    fn f(gg:*Game,cc:m.Vice(i32,2),dx:i32,dz:i32,k:st.Kind)Allocator.Error!bool{
      if(!try gg.structs.place(gg.gpa,&gg.world,cc[0]+dx,cc[1]+dz,k,0,gg.rng.float()))return false;
      st.sown(gg.structs.get(.of(gg.structs.list.items.len-1)),gg.act);
      return true;
    }
  }.f;
  _=try put(g,c,3,0,.strangeSeed);
  _=try put(g,c,3,6,.yielder);
  for([_]m.Vice(i32,2){.{5,6},.{1,6},.{3,8},.{3,4}})|o|_=try put(g,c,o[0],o[1],.petal);
  _=try put(g,c,12,3,.stem);
  for([_]m.Vice(i32,2){.{14,3},.{10,3},.{12,5},.{12,1}})|o|_=try put(g,c,o[0],o[1],.bud);
  // the garden runs on; once the heart has bloomed, petals by it
  var t:f32=0;
  var petals=false;
  while(t<seconds):(t+=play.tickTime){
    if(!petals and t>40){
      for([_]m.Vice(i32,2){.{14,5},.{10,5},.{14,1},.{10,1}})|o|_=try put(g,c,o[0],o[1],.petal);
      petals=true;
    }
    try g.step();
  }
  // the heart fed, and tendrils to it from the seed and the yielder
  const heart=g.structs.at(&g.world,c[0]+12,c[1]+3) orelse return;
  _=g.structs.insert(&g.prog,heart,.fragment,20);
  try tendril(g,.{c[0]+3,c[1]},.{c[0]+12,c[1]+3},lib.tendril.lift);
  try tendril(g,.{c[0]+3,c[1]+6},.{c[0]+12,c[1]+3},0);
  // (and the floating one rising over its middle and falling again, each
  // tile at its own height)
  if(g.tendrils.list.items.len>0){
    const rise=&g.tendrils.list.items[0];
    for(0..rise.n)|k|rise.highs[k]=0.6+1.6*@sin(m.pi*m.f(k)/m.f(rise.n-1));
  }
}
/// a tendril from what stands at `a` to what stands at `b`, its path along
/// x then z, every tile floating `high` over the ground (0 on it), braided whole
fn tendril(g:*Game,a:m.Vice(i32,2),b:m.Vice(i32,2),high:f32)Allocator.Error!void{
  const from=g.structs.at(&g.world,a[0],a[1]) orelse return;
  const to=g.structs.at(&g.world,b[0],b[1]) orelse return;
  var t=lib.tendril.Tendril{.from=g.structs.get(from).ref(),.to=g.structs.get(to).ref(),.n=0,.highs=@splat(high),.fill=1};
  // the walk from a to b
  var p=a;
  while(t.n<lib.tendril.most):(t.n+=1){
    t.path[t.n]=p;
    if(p[0]==b[0] and p[1]==b[1])break;
    if(p[0]!=b[0])p[0]+=if(b[0]>p[0])1 else -1 else p[1]+=if(b[1]>p[1])1 else -1;
  }
  t.n+=1;
  try g.tendrils.list.append(g.gpa,t);
}
