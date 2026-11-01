//! weaving: turning gathered matter into seeds and structure bulbs. The wolf
//! weaves bulbs by hand; a germinator weaves everything, seeds and bulbs,
//! and only it weaves seeds (plants never set seed), so it is the
//! bootstrap: woven from gathered matter alone, it weaves the first
//! essence flowers, and fed by conduits it is what automates the garden. Ingredients
//! leave the inventory when a weave is queued (like Factorio hand crafting)
//! and the result appears when it finishes.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// shifts the weave queue forward a place when the first weave is done
const copyForwards=std.mem.copyForwards;
/// the test harness
const testing=std.testing;
/// what can be held: items, ingredients, bags
const items=lib.items;
/// the research tree, which gates some weaves
const prog=lib.progression;
/// one weave: what comes out, how many, what goes in and how long it takes
pub const Recipe=struct{
  /// the item woven
  out:items.Item,
  /// how many come out of one weave
  n:u16=1,
  /// what it eats, taken when it is queued
  in:[]const items.Ingredient,
  /// seconds the weave takes
  time:f32,
  /// research that must be known before this can be woven
  needs:?prog.Id=null,
  /// only a germinator weaves it (seeds always are; so are the convergent
  /// structures, the hands cannot bind two lineages into one)
  germinator:bool=false,
  /// the advanced tier: only a monfris weaves it, never a germinator or
  /// the hands
  advanced:bool=false,
  /// of both lineages: a monfris weaves it too (a germinator still does,
  /// so the first monfris can be woven)
  convergent:bool=false,
  /// of one lineage until the unforming, which evolves it into both (the
  /// arsthraxia): a monfris weaves it too from then on
  evolves:bool=false,
  /// whether the research it needs (if any) is known
  pub fn unlocked(r:Recipe,g:*const prog.Progression)bool{
    return if(r.needs)|id|g.done.contains(id)else true;
  }
};
/// everything that can be woven, seeds among them (only a germinator weaves those;
/// it weaves the rest too).
pub const hand=[_]Recipe{
  .{.out=.seedLumenroot,.in=&.{.{.item=.fibre,.n=2},.{.item=.starlight,.n=1}},.time=1.5},
  .{.out=.seedThornleech,.in=&.{.{.item=.grit,.n=2},.{.item=.leyShard,.n=1},.{.item=.starlight,.n=1}},.time=1.5},
  .{.out=.seedDriftwisp,.in=&.{.{.item=.starlight,.n=1},.{.item=.leyShard,.n=1},.{.item=.fibre,.n=1}},.time=2,.needs=.driftSpores},
  // decision: ungated, from starlight, ley and essence (the brief sets no cost)
  .{.out=.seedBloom,.in=&.{.{.item=.starlight,.n=3},.{.item=.leyShard,.n=1},.{.item=.essence,.n=2}},.time=3},
  .{.out=.seedHollowheart,.in=&.{.{.item=.essence,.n=4},.{.item=.fibre,.n=3},.{.item=.grit,.n=2}},.time=3,.needs=.canopyWeaving},
  // decision: the hybrid is spliced from both lineages' essence and what their meeting condenses
  .{.out=.seedVesper,.in=&.{.{.item=.essence,.n=2},.{.item=.convergenceEssence,.n=1},.{.item=.fibre,.n=1}},.time=2.5,.needs=.seedSplicing},
  .{.out=.conduit,.n=2,.in=&.{.{.item=.fibre,.n=2},.{.item=.grit,.n=1}},.time=1},
  .{.out=.sapCache,.in=&.{.{.item=.fibre,.n=4},.{.item=.grit,.n=4}},.time=2},
  // no essence: nothing yields it until the germinator has woven a seed
  .{.out=.germinator,.in=&.{.{.item=.fibre,.n=6},.{.item=.grit,.n=4},.{.item=.starlight,.n=2}},.time=3},
  .{.out=.arsthraxia,.in=&.{.{.item=.fibre,.n=8},.{.item=.grit,.n=6},.{.item=.essence,.n=4},.{.item=.starlight,.n=4},.{.item=.leyShard,.n=2}},.time=4,.evolves=true},
  .{.out=.rootDigger,.in=&.{.{.item=.fibre,.n=3},.{.item=.grit,.n=2},.{.item=.leyShard,.n=1}},.time=2,.needs=.deepRooting},
  // decision: ungated, from what a bloom is grown from plus fibre (the brief sets no cost)
  .{.out=.polyp,.in=&.{.{.item=.fibre,.n=4},.{.item=.essence,.n=3},.{.item=.starlight,.n=2},.{.item=.leyShard,.n=2}},.time=3},
  // decision: a diamond is woven from what a halo is grown from, condensed
  // (the brief sets no cost); a germinator's alone, never a monfris's or
  // the hands' (the gardener's word)
  .{.out=.diamond,.in=&.{.{.item=.starlight,.n=6},.{.item=.leyShard,.n=4},.{.item=.convergenceEssence,.n=3},.{.item=.fibre,.n=2}},.time=6,.needs=.celestialDefragmentation,.germinator=true},
  // decision: costs for the lineages' structures are set here (the brief sets none)
  .{.out=.loomfern,.in=&.{.{.item=.fibre,.n=5},.{.item=.essence,.n=2},.{.item=.grit,.n=2}},.time=2.5,.needs=.livingLooms},
  .{.out=.lithophage,.in=&.{.{.item=.grit,.n=6},.{.item=.leyShard,.n=2},.{.item=.essence,.n=2},.{.item=.fibre,.n=2}},.time=3,.needs=.lithophagy},
  // woven from conduits: four grown into one
  .{.out=.braidedConduit,.in=&.{.{.item=.conduit,.n=4},.{.item=.fibre,.n=2},.{.item=.essence,.n=1}},.time=2,.needs=.braidedRoots},
  .{.out=.ganglion,.in=&.{.{.item=.fibre,.n=3},.{.item=.essence,.n=3},.{.item=.grit,.n=2},.{.item=.leyShard,.n=1}},.time=2.5,.needs=.lithophagy},
  .{.out=.gatheringCrown,.in=&.{.{.item=.fibre,.n=4},.{.item=.essence,.n=3},.{.item=.starlight,.n=2},.{.item=.grit,.n=1}},.time=2.5,.needs=.livingLooms},
  .{.out=.sporecaster,.in=&.{.{.item=.fibre,.n=3},.{.item=.essence,.n=3},.{.item=.starlight,.n=2},.{.item=.leyShard,.n=1}},.time=3,.needs=.sporeCasting},
  // decision: the convergent structures are woven from the pair they grow
  // out of, bound by what the lineages' meeting condenses (the brief sets
  // no cost); last, so the weaves chosen in saved gardens keep their places
  .{.out=.weftstone,.in=&.{.{.item=.loomfern,.n=1},.{.item=.lithophage,.n=1},.{.item=.convergenceEssence,.n=2},.{.item=.starlight,.n=2}},.time=4,.needs=.wovenStone,.germinator=true,.convergent=true},
  .{.out=.driftbraid,.in=&.{.{.item=.braidedConduit,.n=1},.{.item=.sporecaster,.n=1},.{.item=.convergenceEssence,.n=2},.{.item=.essence,.n=2}},.time=4,.needs=.braidedDrift,.germinator=true,.convergent=true},
  // decision: the monfris from the two convergent structures it grows
  // out of, the Vultrixi from the pair it does, both bound by convergence
  // essence and ley crystals (the brief sets no cost)
  .{.out=.monfris,.in=&.{.{.item=.weftstone,.n=1},.{.item=.driftbraid,.n=1},.{.item=.convergenceEssence,.n=4},.{.item=.leyCrystal,.n=2}},.time=6,.needs=.interweaving,.germinator=true,.convergent=true},
  .{.out=.vultrixi,.in=&.{.{.item=.gatheringCrown,.n=1},.{.item=.ganglion,.n=1},.{.item=.convergenceEssence,.n=2},.{.item=.leyCrystal,.n=1}},.time=4,.needs=.sharedNerves,.germinator=true,.convergent=true},
};
/// whether the weave at `idx` in `hand` makes a seed (an item that plants)
pub fn isSeedRecipe(idx:usize)bool{return hand[idx].out.plants()!=null;}
/// whether the hands cannot weave it: a seed, one marked for a germinator,
/// or the advanced tier
pub fn germinatorOnly(idx:usize)bool{return isSeedRecipe(idx) or hand[idx].germinator or hand[idx].advanced;}
/// whether the weave at `idx` in `hand` is the advanced tier
pub fn isAdvanced(idx:usize)bool{return hand[idx].advanced;}
/// the recipes the wolf weaves by hand (indices into `hand`): all but what
/// only a germinator weaves.
pub const byHand=recipesWhere(germinatorOnly,false);
/// the seed weaves (indices into `hand`).
pub const seeds=recipesWhere(isSeedRecipe,true);
/// every weave but the advanced tier: what a germinator may be set to
/// (indices into `hand`).
pub const all=recipesWhere(isAdvanced,false);
/// the advanced tier: what only a monfris weaves (indices into `hand`).
pub const advanced=recipesWhere(isAdvanced,true);
/// whether a monfris weaves the weave at `idx` in `hand`: the advanced
/// tier, or anything of both lineages
pub fn isLoom(idx:usize)bool{return hand[idx].advanced or hand[idx].convergent;}
/// what a monfris may be set to before the unforming: the advanced tier
/// and every convergent seed and bulb (indices into `hand`).
pub const loom=recipesWhere(isLoom,true);
/// whether a monfris weaves the weave at `idx` once the unforming has
/// evolved what it evolves
pub fn isLoomEvolved(idx:usize)bool{return isLoom(idx) or hand[idx].evolves;}
/// what a monfris may be set to after the unforming: its weaves and what
/// the unforming made convergent (indices into `hand`).
pub const loomEvolved=recipesWhere(isLoomEvolved,true);
/// what a monfris may be set to as far as the garden has come: more once
/// the unforming has been.
pub fn loomFor(g:*const prog.Progression)[]const u8{return if(g.done.contains(.unforming))&loomEvolved else&loom;}
/// whether some weave makes `item` (what a germinator lets go of).
pub fn woven(item:items.Item)bool{
  for(hand)|r|if(r.out==item)return true;
  return false;
}
/// how many weaves the predicate answers `want` for (comptime)
fn countWhere(comptime pred:fn(usize)bool,comptime want:bool)usize{
  @setEvalBranchQuota(10_000);
  // the count so far
  var n:usize=0;
  for(0..hand.len)|i|if(pred(i)==want){n+=1;};
  return n;
}
/// the indices into `hand` of every weave the predicate answers `want`
/// for, in table order (comptime)
fn recipesWhere(comptime pred:fn(usize)bool,comptime want:bool)[countWhere(pred,want)]u8{
  @setEvalBranchQuota(10_000);
  // the gathered indices, and how many are in so far
  var out:[countWhere(pred,want)]u8=undefined;
  var k:usize=0;
  for(0..hand.len)|i|if(pred(i)==want){out[k]=i;k+=1;};
  return out;
}
/// max weaves queued at once (the wolf's hands can only do so much)
const queueMax=8;
/// the wolf's weaving hands: a queue of weaves, the first one in progress
pub const Crafter=struct{
  /// the queued weaves, indices into `hand`; only the first `len` are real
  queue:[queueMax]u8=undefined,
  /// how many weaves are queued
  len:usize=0,
  /// seconds the first weave has been worked
  t:f32=0,
  /// whether `inv` holds everything the recipe eats
  pub fn can(inv:items.Bag,r:Recipe)bool{
    for(r.in)|ing|if(inv.count(ing.item)<ing.n)return false;
    return true;
  }
  /// takes the ingredients now; false if missing or the queue is full.
  pub fn push(c:*Crafter,inv:items.Bag,idx:usize)bool{
    // the recipe asked for
    const r=hand[idx];
    if(c.len==queueMax or !can(inv,r))return false;
    for(r.in)|ing|_=inv.take(ing.item,ing.n);
    c.queue[c.len]=@intCast(idx);
    c.len+=1;
    return true;
  }
  /// whether a weave is underway
  pub fn busy(c:*const Crafter)bool{return c.len>0;}
  /// how far the first weave is, 0..1 (0 when idle)
  pub fn progress(c:*const Crafter)f32{return if(c.len==0)0 else c.t/hand[c.queue[0]].time;}
  /// returns the item finished this step, if any. A result that does not fit
  /// waits in the weave until there is room.
  pub fn tick(c:*Crafter,inv:items.Bag,dt:f32)?items.Item{
    if(c.len==0)return null;
    // the weave at the front of the queue
    const r=hand[c.queue[0]];
    c.t=@min(c.t+dt,r.time);
    if(c.t<r.time)return null;
    if(inv.add(r.out,r.n)<r.n)return null;
    copyForwards(u8,c.queue[0..c.len-1],c.queue[1..c.len]);
    c.len-=1;
    c.t=0;
    return r.out;
  }
};
test"weaving takes ingredients up front and yields after its time"{
  // a bag of eight slots and idle hands
  var inv:items.Inventory(8)=.{};
  var c:Crafter=.{};
  try testing.expect(!c.push(inv.bag(),0));
  _=inv.add(.fibre,4);
  _=inv.add(.starlight,1);
  try testing.expect(c.push(inv.bag(),0));
  try testing.expect(!c.push(inv.bag(),0)); // only one starlight
  try testing.expectEqual(@as(u32,2),inv.count(.fibre));
  try testing.expect(c.tick(inv.bag(),1.0)==null);
  try testing.expect(c.tick(inv.bag(),1.0)==.seedLumenroot);
  try testing.expectEqual(@as(u32,1),inv.count(.seedLumenroot));
  try testing.expect(!c.busy());
}
