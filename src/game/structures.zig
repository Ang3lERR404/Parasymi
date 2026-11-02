//! grown structures: the first steps from hand work toward automation.
//!
//! Each kind is its own module under `structures/` declaring:
//!   def:Def                     name, bulb item, footprint, mesh   (required)
//!   State                       per-kind data (optional, see `State` union)
//!   tick(ctx, id, dt) [!]bool   advance; returns whether it is active
//!                               (`Ctx`: the garden, and in the game the
//!                               wolf, the sky and this tick's events)
//!   link(ctx, id)               notice its neighbours, every tick, grown or not
//!   wants(s, g, item) u32       how many of `item` it will still take in
//!   output(s) ?Item             what may leave it first (pulled by conduits)
//!   gives(s, item) bool         whether `item` may leave it (default: it is
//!                               its `output`); a braided conduit's lanes
//!                               pull a different item each. `outputs` walks
//!                               all that may leave (`handOff` offers each)
//!   receive(s, g, item, edge) bool  a carrier taking an item handed in at
//!                               `edge` (counted from the way it faces)
//!   release(s) ?Item            hand back anything it holds outside `inv`
//!   sown(s, act)                the gardener has just put it down by hand,
//!                               in which act (the strange seed is planted
//!                               only in the hyena's)
//!   handOver(s) ?Item           what a click hands the wolf straight away,
//!                               taken out of it (a polyp's drifting flower)
//!   message(ctx, id, msg) Reply what it makes of a `Msg` another sends it
//!                               (`Structures.send`; `.ignored`: the
//!                               message's default)
//!   configure(ss, id, g)        the player's "C" interaction (it may reach
//!                               another structure: `Structures.pairing`)
//!   recipes(g) []const u8       what its panel offers to weave (indices into
//!                               `craft.hand`); `chosen(s)` is the one it
//!                               weaves, `choose(s, g, r)` sets it
//!   emit(s, out, ctr, tf)       extra visuals beyond its mesh (placed as it is:
//!                               `place(s, ctr)`)
//!   breath(s) ?Breath           what it breathes into the air: moisture
//!                               into the mist and the cloud round it
//!   describe(s, d, g, x, y)     one line of hover text
//!   ground(kind) bool           which tiles it may stand on (default: any tile)
//!   field(s) ?Field             a field of celestial energy it holds
//!   hold(s, x, y) ?Hold         how it draws the floater at a tile toward itself
//!   size(s) f32                 how much larger than its mesh it has grown
//!                               (by research), its growing in aside
//!   icon(ic, col)               its bulb in the HUD: the seed (`ic.coat`) and a
//!                               sprout or two showing what it does (`icon.zig`)
//!   meets:Meeting               another structure that, grown
//!                               beside it, is a discovery (`Structures.meetings`)
//!   adopts(s, kind, have) bool  whether it takes on one more child of `kind`
//!                               beyond the `have` it has (`dependOn`;
//!                               default: none). A child depends on its
//!                               parent: `getParent`, `getChildren`,
//!                               `getChild`; `spawnChild` puts one down
//!                               already its child (no `adopts` asked)
//!   pairs:Pairs                 how it pairs with partners (`.most` at once),
//!                               one way (it sends there) or both ways
//!                               (`pairWith`, `pairStep`, `getPartner`,
//!                               `getPartners`, `pairedTo`, `unpair`;
//!                               default: never)
//!   meshes                      the library meshes it draws beyond `mesh` and
//!                               `preview` (a tuple: `.{ .itemPod, ... }`);
//!                               `--structure` builds only these (tested)
//! Missing hooks fall back to doing nothing. A new structure is one new file
//! plus one line in `kinds`.
const lib=@import("../lib.zig");
/// the engine package: maths, the registry machinery
const engine=lib.engine;
/// all the maths: vectors, matrices, a structure's facing
const m=engine.core.math;
/// the comptime registry that turns `kinds` into an enum and dispatch
const registry=engine.core.registry;
/// the chunks: tile kinds, occupancy and the id types stored there
const ck=lib.ck;
/// what can be held: item kinds and stacks of them
const items=lib.items;
/// the plants' registry, for the lineage a structure belongs to
const species=lib.species;
/// the mesh library a structure's mesh is chosen from
const meshlib=lib.meshlib;
/// what the gardener has understood: research and discoveries
const prog=lib.progression;
/// what structures tell each other, and how a kind pairs
pub const messages=@import("structures/core/messages.zig");
/// one structure as stored, and the context its hooks run in
pub const structure=@import("structures/core/structure.zig");
/// the garden's list of every placed structure
pub const list=@import("structures/core/list.zig");
/// pairing structures with partners, one way or both
pub const partners=@import("structures/core/partners.zig");
/// parents and children: a structure that depends on another
pub const kin=@import("structures/core/kin.zig");
/// calling each kind's hooks: ticking, linking, wanting, giving
pub const dispatch=@import("structures/core/dispatch.zig");
/// handing items from one structure on to the next
pub const handoff=@import("structures/core/handoff.zig");
/// the optional hooks seen from outside, each with its quiet default
pub const hooks=@import("structures/core/hooks.zig");
/// tests of items flowing between structures
pub const testsFlow=@import("structures/core/tests_flow.zig");
/// tests of kin, pairing and messages
pub const testsKin=@import("structures/core/tests_kin.zig");
/// a shared test bench: a small garden to put structures down in
pub const bench=@import("structures/core/bench.zig");
/// what one structure tells another
pub const Msg=messages.Msg;
/// what a structure makes of a `Msg`
pub const Reply=messages.Reply;
/// how a kind pairs: with whom, which way, how many at once
pub const Pairs=messages.Pairs;
/// the most partners any structure keeps
pub const partnerSlots=messages.partnerSlots;
/// one way or both ways, for a pairing
pub const Way=messages.Way;
/// where configuring a pairing structure leaves it
pub const PairStep=messages.PairStep;
/// one placed structure: where, which way, what it holds, its state
pub const Structure=structure.Structure;
/// everything a structure's behaviour may touch
pub const Ctx=structure.Ctx;
/// a kind found by its name's hash, as saves store it
pub const kindByName=structure.kindByName;
/// a fresh structure of one kind, for a saved one to be read over
pub const blank=structure.blank;
/// the garden's list of structures
pub const Structures=list.Structures;
/// what a hand-off between structures did
pub const HandOff=handoff.HandOff;
/// the first ground tile a structure may stand on
pub const firstGround=handoff.firstGround;
/// hand what a structure gives on to the one it faces
pub const handOff=handoff.handOff;
/// hand off, choosing what goes by a given rule
pub const handOffWith=handoff.handOffWith;
/// how a structure draws a floater toward itself
pub const Hold=hooks.Hold;
/// every field of celestial energy the structures hold
pub const fields=hooks.fields;
/// how a structure draws the floater at a tile toward itself, if it does
pub const hold=hooks.hold;
/// hand back what a structure holds outside its slots
pub const release=hooks.release;
/// tell a structure the gardener has just put down by hand which act it is
pub const sown=hooks.sown;
/// what a click on it hands the wolf straight away (`handOver`)
pub const handOver=hooks.handOver;
/// whether a structure answers the player's configure
pub const configurable=hooks.configurable;
/// the player's configure on a structure
pub const configure=hooks.configure;
/// what a structure's panel offers to weave
pub const recipes=hooks.recipes;
/// the recipe a structure weaves now
pub const chosen=hooks.chosen;
/// set the recipe a structure weaves
pub const choose=hooks.choose;
/// a structure's extra visuals beyond its mesh
pub const emit=hooks.emit;
/// how much moisture a structure breathes into the air
pub const Breath=hooks.Breath;
/// what a structure breathes into the air, if anything
pub const breath=hooks.breath;
/// a structure's line of hover text
pub const describe=hooks.describe;
/// a kind's bulb in the HUD
pub const icon=hooks.icon;
/// take one thing out of a structure by hand
pub const harvestOne=hooks.harvestOne;
/// every kind of structure, one module each; the order is the enum's order
pub const kinds=struct{
  /// the root conduit: carries one item at a time, tile to tile
  pub const conduit=@import("structures/conduit.zig");
  /// plain storage in a gourd of resin
  pub const sapCache=@import("structures/sap_cache.zig");
  /// a small tree that weaves by itself from what it is fed
  pub const germinator=@import("structures/germinator.zig");
  /// the lab: a bloom that condenses research, unit by unit
  pub const arsthraxia=@import("structures/arsthraxia.zig");
  /// works the resource node beside it, one item at a time
  pub const rootDigger=@import("structures/root_digger.zig");
  /// woven of both lineages, feeding on blooms' light, letting flowers drift
  pub const polyp=@import("structures/polyp.zig");
  /// the cut crystal a halo's blooms become, floating high
  pub const diamond=@import("structures/diamond.zig");
  /// a fern that weaves fibre by itself, slowly
  pub const loomfern=@import("structures/loomfern.zig");
  /// a parasite that draws mineral nodes up into its crop
  pub const lithophage=@import("structures/lithophage.zig");
  /// a conduit of braided lanes, one item each
  pub const braidedConduit=@import("structures/braided_conduit.zig");
  /// a parasite's nerve knot that shares out what it is fed
  pub const ganglion=@import("structures/ganglion.zig");
  /// a symbiote that gathers what nearby plants ripen
  pub const gatheringCrown=@import("structures/gathering_crown.zig");
  /// a parasite that sends what it is fed by spore to its partner
  pub const sporecaster=@import("structures/sporecaster.zig");
  /// a loomfern and a lithophage grown into one floating body
  pub const weftstone=@import("structures/weftstone.zig");
  /// a braided conduit and a sporecaster grown into one, trading both ways
  pub const driftbraid=@import("structures/driftbraid.zig");
  /// a 2x2 tree that weaves what is of both lineages
  pub const monfris=@import("structures/monfris.zig");
  /// a floating body tethered to feed a monfris
  pub const vultrixi=@import("structures/vultrixi.zig");
  /// the seed the unforming let fall, lying where it landed
  pub const strangeSeed=@import("structures/strange_seed.zig");
  /// a constellate core with four petals snapped on, yielding fragments
  pub const yielder=@import("structures/yielder.zig");
  /// a polyp's stemless flower put down as a floating light
  pub const driftFlower=@import("structures/drift_flower.zig");
  /// the mist tree, breathing moisture into the air
  pub const nebularbor=@import("structures/nebularbor.zig");
  /// the root well: a basket storing the rain, pouring it out through dry spells
  pub const rootWell=@import("structures/root_well.zig");
  /// the tanglehold: storage of both lineages, twice a sap cache's
  pub const tanglehold=@import("structures/tanglehold.zig");
  /// the storm spire: charges under the rain and strikes the cloud into storms
  pub const stormSpire=@import("structures/storm_spire.zig");
};
/// the registry built from `kinds`: ids, tables, hook dispatch
pub const reg=registry.Registry(kinds);
/// what fills a tile: nothing, a plant or a structure
pub const Occ=ck.Occ;
/// a plant's id, as a tile stores it
pub const PlantId=ck.PlantId;
/// which kind of structure, one tag per module in `kinds`
pub const Kind=reg.Id;
/// a placed structure's slot in `Structures.list`.
pub const Id=ck.StructId;
/// what a kind of structure is: its bulb, footprint, mesh and how it
/// stands, sways, grows and behaves in the garden
pub const Def=struct{
  /// the bulb it is grown from (and dropped back as when uprooted)
  item:items.Item,
  /// how many tiles across its square footprint is
  size:u8,
  /// the library mesh it is drawn with
  mesh:meshlib.Id,
  /// how see-through its sap (resin pods, sap beads) is at its thinnest;
  /// like the wolf's, it has no light of its own
  sap:f32=sap,
  /// grown structures that stand up move like plants: how far they bend in
  /// the wind (0 rigid)
  sway:f32=0,
  /// the height (in tiles) that bending is spread over
  tall:f32=1,
  /// seconds it takes to grow from a sprout once the gardener puts it down
  /// (0: there at once); it does no work until grown. Its mesh is built
  /// along growth splines (gfx/growth.zig) and grows along them on the
  /// GPU, branch after branch (`PartInstance` `grown`)
  grow:f32=0,
  /// carries items tile to tile the way it faces (R turns it): carriers
  /// chain into one line, and producers leave them to pull through `output`
  carrier:bool=false,
  /// keeps items in its slots: a click on it opens its panel, where they
  /// are lifted and put down as in the belly (hud/structure.zig)
  store:bool=false,
  /// how many of its slots it keeps items in (at most `slots`; four
  /// rows of them in its panel)
  room:u8=16,
  /// floats over its tile instead of standing on it: it takes no room
  /// there, so it may float over a structure or a plant (never over
  /// another floating one)
  floating:bool=false,
  /// how high over the ground a floating one hangs
  hover:f32=0,
  /// its mesh is drawn by its own `emit` (a diamond: it forms on the GPU),
  /// not breathing and growing in as the others do; `mesh` is its preview
  bare:bool=false,
  /// does not breathe: what it emits hangs on its mesh and must stay put
  /// on it (a germinator's cups and core)
  still:bool=false,
  /// what the gardener sees before putting it down, if not `mesh` (a
  /// germinator's emitted pieces at rest with it)
  preview:?meshlib.Id=null,
  /// what it emits travels far from it (a sporecaster's spores): it is
  /// emitted however far it stands from the view
  far:bool=false,
  /// its `tick` runs while it grows too, not only once grown: a life that
  /// is all growing (the nebularbor's roots drink from the first day)
  worksGrowing:bool=false,
  /// the lineage it belongs to, the one place that says so: every kind
  /// names it (null only while it is not yet known, as the strange seed's);
  /// what the unforming does to it, whether a monfris or the hands weave
  /// it and how pale its roots are all follow from it
  lineage:?species.Lineage,
  /// the lineage the unforming evolves it into instead of taking it (the
  /// arsthraxia: symbiotic into convergent)
  evolves:?species.Lineage=null,
  /// whether the unforming takes it, grown back down to nothing and gone
  /// (game/unforming.zig): every kind of a lineage but the convergent one,
  /// unless it evolves
  pub fn unforms(d:Def)bool{
    const l=d.lineage orelse return false;
    return d.evolves==null and l!=.convergent;
  }
  /// a parasite's: the roots it turns on (R) are pale, not bark
  pub fn pale(d:Def)bool{return d.lineage==.parasitic;}
};
/// every kind's `def`, looked up by kind
pub const defs=reg.table(Def,"def");
/// another structure (`kind`, most often of the other lineage) that, both grown within
/// `meetCount` tiles of each other, is witnessed as the discovery `found`
pub const Meeting=struct{kind:Kind,found:prog.Discovery};
/// tiles apart (between footprints) that still count as side by side
pub const meetCount=3;
/// per-kind state; the active tag is the structure's kind.
pub const State=reg.Union("State");
/// every library mesh kind `k` draws: its mesh, its preview and what it
/// emits (its `meshes`), gathered at compile time into one list
pub fn meshes(k:Kind)[]const meshlib.Id{
  return switch(k){
    inline else=>|t|comptime blk:{
      // the kind's def, and the extra meshes it lists (if any)
      const d:Def=reg.module(t).def;
      const extra=if(reg.has(t,"meshes"))reg.module(t).meshes else.{};
      // how many leading entries are its own: its mesh, and its preview if set
      const own:usize=if(d.preview!=null)2 else 1;
      // the list being filled
      var out:[own+extra.len]meshlib.Id=undefined;
      out[0]=d.mesh;
      if(d.preview)|p|out[1]=p;
      for(extra,own..)|e,i|out[i]=e;
      // the filled list, frozen so a pointer to it may outlive the block
      const all=out;
      break:blk&all;
    },
  };
}
/// the kind of structure grown from bulb `item`, or null if it grows none
pub fn kindOf(item:items.Item)?Kind{
  inline for(reg.ids)|k|if(defs.get(k).item==item)return k;
  return null;
}
/// the most stacks a structure's inventory holds (each kind keeps items in
/// its `Def.room` of them)
pub const slots=32;
/// how quickly a structure's activity glow eases toward its target
pub const activityEase:f32=3;
/// how see-through structures' sap is at its thinnest, unless a def says otherwise
pub const sap:f32=0.78;
/// a structure as another holds on to it: by tile (an `Id` shifts when
/// another is uprooted) and whether it floats (a floater and what it
/// floats over share a tile)
pub const Ref=struct{
  /// the tile's column
  x:i32,
  /// the tile's row
  y:i32,
  /// whether it is the floating one on that tile
  floating:bool,
  /// whether two refs name the same structure
  pub fn eql(a:Ref,b:Ref)bool{return a.x==b.x and a.y==b.y and a.floating==b.floating;}
  /// the tile it stands on, as x and y
  pub fn tile(r:Ref)m.Vice(i32,2){return.{r.x,r.y};}
};
/// what `spawnChild` puts down: a structure of `kind` on tile `x`,`y`,
/// facing `dir`, with its own `seed` for how it sways and varies
pub const Spawn=struct{x:i32,y:i32,kind:Kind,dir:m.Dir=0,seed:f32=0};
/// a root's (or nerve's, or tendril's) reach `r` (0..1) one frame on: it
/// grows `grow` toward 1 while what it reaches for is `there`, and withers
/// `wither` back toward 0 once it is gone
pub fn reaching(r:f32,there:bool,grow:f32,wither:f32)f32{return if(there)@min(1,r+grow)else@max(0,r-wither);}
test"a reach grows while its plant is there and withers once it is gone"{
  // the test helpers
  const testing=lib.std.testing;
  try testing.expectEqual(@as(f32,0.75),reaching(0.5,true,0.25,0.1));
  try testing.expectEqual(@as(f32,1),reaching(0.9,true,0.25,0.1));
  try testing.expectEqual(@as(f32,0),reaching(0.05,false,0.25,0.1));
}
test{
  _=messages;
  _=structure;
  _=list;
  _=partners;
  _=kin;
  _=dispatch;
  _=handoff;
  _=hooks;
  _=testsFlow;
  _=testsKin;
}
