//! what a solcyriphon's night beam does where it falls, beyond the light
//! grid's own work. On bare moss it has, now and then, a very small chance
//! to turn it into a ley line: about one in a hundred each whole night it
//! falls there (`chance`), kept as the garden's changed ground is
//! (game/moss.zig); on any other bare ground it does nothing. On a plant
//! it is witnessed: the first overdrive, and the first starglass or evening
//! silk steeped in one, are discoveries.
const lib=@import("../lib.zig");
/// the chunk: tile kinds
const ck=lib.ck;
/// the game: its world, the light grid's beams, its random stream
const Game=lib.play.Game;
/// the sky: how long a day and its night last
const sky=lib.sky;
/// the chance a whole night's beam on one moss tile turns it to a ley line
pub const chance:f32=0.01;
/// how long the beam falls in a night, as a share of a whole day (the
/// night's darkest third)
const nightShare:f32=1.0/3.0;
/// one tick (`dt` s): every beam on bare moss may turn it to a ley line,
/// at `chance` a night, by how strong the beam is
pub fn tick(g:*Game,dt:f32)void{
  witness(g);
  for(g.eco.light.beams.items)|b|{
    if(b.onto!=.ground)continue;
    // the tile under the beam
    const c=g.world.chunkOfTile(b.x,b.y) orelse continue;
    if(c.kind[ck.localIndex(b.x,b.y)]!=.moss)continue;
    if(g.rng.float()>=chance*b.k*dt/(sky.dayLen*nightShare))continue;
    g.moss.become(g.gpa,&g.world,b.x,b.y,.ley) catch continue;
  }
}
/// the discoveries a beam on a plant makes: the first overdrive, then the
/// first rare yield of starglass or evening silk steeped whole in one
fn witness(g:*Game)void{
  // the plants' columns, and how hard each is beamed
  const s=g.plants.list.slice();
  const beamed=g.eco.light.beamed.items;
  for(beamed,0..)|b,i|{
    if(b<=0 or i>=g.plants.len())continue;
    g.prog.discover(.overdrive);
    if(s.items(.rare)[i]<1)continue;
    // what steeps in it
    const rare=lib.species.get(s.items(.sp)[i]).rareYield();
    if(rare==.starglass)g.prog.discover(.starglass);
    if(rare==.eveningSilk)g.prog.discover(.eveningSilk);
  }
}
