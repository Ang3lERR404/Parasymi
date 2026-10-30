//! catalogue of rigid procedural part meshes, one module (or a companion
//! struct inside its owner's module) each under
//! `meshes/` exposing `build(b)`. Each is built once at startup in its own
//! local space; anything "made of parts" (the player, resource nodes, motes,
//! structures) draws instances of these with a per-instance transform, so
//! procedural animation is just transform math.
//!
//! A new mesh is one new file (or struct) plus one line in `parts`.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// checks a finished skeleton left no piece past its growth
const assert=std.debug.assert;
/// the allocator type every building call may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// the garden's mesh builder and its levels of detail
const mg=lib.meshgen;
/// the engine's registry: one module per thing, an enum over them
const registry=engine.core.registry;
/// every library mesh, one member each, in draw order: translucent ones
/// after what they cover (the registry's order is the draw order)
const parts=struct{
  // drawn first: a flat soft patch on the ground under floaters
  /// a flat soft disc of shadow on the ground
  pub const shadow=@import("meshes/shadow.zig");
  // the vine-wolf: one skinned body, then what is see-through over it
  /// the vine-wolf's one skinned body
  pub const wolfBody=@import("meshes/wolf_body.zig");
  /// both its ears, skinned to their bones
  pub const wolfEars=@import("meshes/wolf_ears.zig");
  // drawn before the belly so the translucent sac blends over them
  /// a lump of something heavy the wolf carries, seen through its belly
  pub const bellyLump=@import("meshes/belly_lump.zig");
  /// the sac of sap on the wolf's gut, translucent over what it holds
  pub const wolfBelly=@import("meshes/wolf_belly.zig");
  /// the left lobe of solidified sap on the chest
  pub const wolfPecL=@import("meshes/wolf_pec.zig").left;
  /// the right lobe on the chest
  pub const wolfPecR=@import("meshes/wolf_pec.zig").right;
  /// the left lobe of sap over the rump
  pub const wolfRumpL=@import("meshes/wolf_rump.zig").left;
  /// the right lobe over the rump
  pub const wolfRumpR=@import("meshes/wolf_rump.zig").right;
  /// the central bean of sap under each foot
  pub const pawPad=@import("meshes/paw_pad.zig");
  /// a small oval of sap: the toe pads, and the nose pad
  pub const pawBean=@import("meshes/paw_pad.zig").bean;
  // the world
  /// mineral grit breaking out of the ground
  pub const nodeGrit=@import("meshes/node_grit.zig");
  /// a clump of fibre plant, long stalks rising
  pub const nodeFibre=@import("meshes/node_fibre.zig");
  /// ley shards: crystals grown out of a ley line
  pub const nodeLey=@import("meshes/node_ley.zig");
  /// a fallen fragment of starlight, a small faceted bipyramid
  pub const mote=@import("meshes/mote.zig");
  /// what bursts out where a plant's yield comes loose: motes and drops of it
  pub const pluckBurst=@import("meshes/pluck_burst.zig");
  // structures
  /// a living root conduit digging up out of the soil, running straight
  pub const conduit=@import("meshes/conduit.zig");
  /// the same root turning in from the tile's +Z edge
  pub const conduitLeft=@import("meshes/conduit.zig").left;
  /// the same root turning in from the other side
  pub const conduitRight=@import("meshes/conduit.zig").right;
  /// a conduit's tap: the root reaching down to what it draws from
  pub const conduitTap=@import("meshes/conduit.zig").tap;
  /// a braided conduit: a root conduit grown dense, four sapwood cores
  pub const braidedConduit=@import("meshes/braided_conduit.zig");
  /// the weave, leaves and soil of a straight braided conduit
  pub const braidWrap=@import("meshes/braided_conduit.zig").wrap;
  /// the weave of one turning in from the tile's +Z edge
  pub const braidWrapLeft=@import("meshes/braided_conduit.zig").wrapLeft;
  /// the weave of one turning in from the other side
  pub const braidWrapRight=@import("meshes/braided_conduit.zig").wrapRight;
  /// a straight braided conduit's first lane core
  pub const braidLane0=@import("meshes/braided_conduit.zig").Lane(0,0);
  /// its second lane core
  pub const braidLane1=@import("meshes/braided_conduit.zig").Lane(0,1);
  /// its third lane core
  pub const braidLane2=@import("meshes/braided_conduit.zig").Lane(0,2);
  /// its fourth lane core
  pub const braidLane3=@import("meshes/braided_conduit.zig").Lane(0,3);
  /// a left-turning braid's first lane core
  pub const braidLane0Left=@import("meshes/braided_conduit.zig").Lane(1,0);
  /// its second lane core
  pub const braidLane1Left=@import("meshes/braided_conduit.zig").Lane(1,1);
  /// its third lane core
  pub const braidLane2Left=@import("meshes/braided_conduit.zig").Lane(1,2);
  /// its fourth lane core
  pub const braidLane3Left=@import("meshes/braided_conduit.zig").Lane(1,3);
  /// a right-turning braid's first lane core
  pub const braidLane0Right=@import("meshes/braided_conduit.zig").Lane(-1,0);
  /// its second lane core
  pub const braidLane1Right=@import("meshes/braided_conduit.zig").Lane(-1,1);
  /// its third lane core
  pub const braidLane2Right=@import("meshes/braided_conduit.zig").Lane(-1,2);
  /// its fourth lane core
  pub const braidLane3Right=@import("meshes/braided_conduit.zig").Lane(-1,3);
  /// the sap cache's lid, opening at its mouth as things pass
  pub const sapCacheLid=@import("meshes/sap_cache.zig").lid;
  /// the sap cache: a store grown like the plants, a gourd of resin on a woven bole
  pub const sapCache=@import("meshes/sap_cache.zig");
  /// the germinator: a small tree that weaves essence into seeds
  pub const germinator=@import("meshes/germinator.zig");
  /// the germinator whole, at rest: what the gardener sees before placing it
  pub const germinatorWhole=@import("meshes/germinator.zig").whole;
  /// one of its cups, a spout petal reaching out to pour
  pub const germinatorCup=@import("meshes/germinator.zig").cup;
  /// the essence standing in a cup, a lens of it
  pub const germinatorPool=@import("meshes/germinator.zig").pool;
  /// the essence pouring from a cup's lip, placed along its fall
  pub const germinatorPour=@import("meshes/germinator.zig").pour;
  /// the whirlpool of essence spun in its core
  pub const germinatorVortex=@import("meshes/germinator.zig").vortex;
  /// a thread of essence wound in onto the seed
  pub const germinatorThread=@import("meshes/germinator.zig").thread;
  /// the seed being woven: an egg drawn to a point at its crown
  pub const germinatorSeed=@import("meshes/germinator.zig").seed;
  /// a winding of essence round the seed, as on a spindle
  pub const germinatorWinding=@import("meshes/germinator.zig").winding;
  // (see-through: blends over what spins inside it)
  /// the germinator's core of thin resin, what spins in it showing through
  pub const germinatorCore=@import("meshes/germinator.zig").core;
  /// the arsthraxia: a bloom that studies, three braided stems rising
  pub const arsthraxia=@import("meshes/arsthraxia.zig");
  /// the arsthraxia whole, at rest with its flower: what is placed
  pub const arsthraxiaWhole=@import("meshes/arsthraxia.zig").whole;
  /// the arsthraxia the unforming evolves: its stand woven of both lineages
  pub const arsthraxiaWoven=@import("meshes/arsthraxia_convergent.zig").stand;
  /// its outer whorl, in the convergence kit's living colours
  pub const arsthraxiaWovenWhorl=@import("meshes/arsthraxia_convergent.zig").whorl;
  /// its inner cup and stamens, in the convergence kit's living colours
  pub const arsthraxiaWovenCup=@import("meshes/arsthraxia_convergent.zig").cup;
  /// it whole, at rest with its flower
  pub const arsthraxiaWovenWhole=@import("meshes/arsthraxia_convergent.zig").whole;
  /// its flower's broad outer whorl, turning slowly as it studies
  pub const arsthraxiaWhorl=@import("meshes/arsthraxia.zig").whorl;
  /// its inner cup, turning against the outer whorl
  pub const arsthraxiaCup=@import("meshes/arsthraxia.zig").cup;
  /// the vines a finished study grows, curling in under the cage
  pub const arsthraxiaVines=@import("meshes/arsthraxia.zig").vines;
  /// a shoot grown along its own splines by research's progress
  pub const arsthraxiaShoot=@import("meshes/arsthraxia.zig").shoot;
  /// a small sap of resin held in two vine bands, spun round the core
  pub const arsthraxiaSatellite=@import("meshes/arsthraxia.zig").satellite;
  // (light: blends over the satellites spinning round it)
  /// the core of condensing light, a ball a unit across
  pub const arsthraxiaCore=@import("meshes/arsthraxia.zig").core;
  /// a wisp of light falling into the core
  pub const arsthraxiaWisp=@import("meshes/arsthraxia.zig").wisp;
  /// a generic carried item, tinted per item
  pub const itemPod=@import("meshes/item_pod.zig");
  /// the root-digger: a knot of braided roots that digs
  pub const rootDigger=@import("meshes/root_digger.zig");
  /// one of its roots, reaching out to a node, a claw at its end
  pub const diggerRoot=@import("meshes/root_digger.zig").root;
  /// a loose clod of earth flung up as it draws something out
  pub const diggerClod=@import("meshes/root_digger.zig").clod;
  /// the loomfern: a fern that weaves, a woven bole on a root mat
  pub const loomfern=@import("meshes/loomfern.zig");
  /// a sheaf it weaves on its spindle, laid at its foot
  pub const loomfernSheaf=@import("meshes/loomfern.zig").sheaf;
  /// a thread drawn from one end and wound in at the other
  pub const loomfernThread=@import("meshes/loomfern.zig").thread;
  /// the gathering crown's first root, out to a node
  pub const crownRoot1=@import("meshes/gathering_crown.zig").Root(0);
  /// its second root
  pub const crownRoot2=@import("meshes/gathering_crown.zig").Root(1);
  /// its third root
  pub const crownRoot3=@import("meshes/gathering_crown.zig").Root(2);
  /// its fourth root
  pub const crownRoot4=@import("meshes/gathering_crown.zig").Root(3);
  /// its fifth root
  pub const crownRoot5=@import("meshes/gathering_crown.zig").Root(4);
  /// the gathering crown: a symbiote rosette that gathers for the garden
  pub const gatheringCrown=@import("meshes/gathering_crown.zig");
  /// the lithophage: a parasite that eats stone, a bulbous foot half sunk
  pub const lithophage=@import("meshes/lithophage.zig");
  /// the crystal it grows with what it draws, and saps away
  pub const lithophageCrystal=@import("meshes/lithophage.zig").crystal;
  /// one of its roots, out to a node beside it
  pub const lithophageRoot=@import("meshes/lithophage.zig").root;
  /// the same root, out to a node on a diagonal
  pub const lithophageRootFar=@import("meshes/lithophage.zig").rootFar;
  // what a rooted thing walks on while it turns (R)
  /// a root a rooted thing walks on while it turns, symbiote green
  pub const turnRoot=@import("meshes/turn_root.zig");
  /// the same root in the parasites' pale colours
  pub const turnRootPale=@import("meshes/turn_root.zig").pale;
  /// a ganglion's nerve out to what it feeds, carrying a pulse
  pub const ganglionNerve=@import("meshes/ganglion.zig").nerve;
  /// the ganglion: a parasite's nerve knot, see-through over what hangs inside
  pub const ganglion=@import("meshes/ganglion.zig");
  /// the sporecaster: a parasite that sends, see-through over what hangs inside
  pub const sporecaster=@import("meshes/sporecaster.zig");
  /// a spore carrier it sends, holding what it carries, cilia trailing
  pub const sporeCarrier=@import("meshes/sporecaster.zig").carrier;
  // the convergent structures (see-through: blend over what hangs inside)
  /// a weftstone's tendril, three pale claws gripping a node
  pub const weftstoneTendril=@import("meshes/weftstone.zig").tendril;
  /// a monfris's tether, two strands twined, hanging between two
  pub const monfrisTether=@import("meshes/monfris.zig").tether;
  /// the driftbraid: a braided conduit and a sporecaster grown into one
  pub const driftbraid=@import("meshes/driftbraid.zig");
  /// the monfris: a weftstone and a driftbraid grown into one 2x2 tree
  pub const monfris=@import("meshes/monfris.zig");
  /// the vultrixi: a gathering crown and a ganglion grown into one, floating
  pub const vultrixi=@import("meshes/vultrixi.zig");
  /// the weftstone: a loomfern and a lithophage grown into one, floating
  pub const weftstone=@import("meshes/weftstone.zig");
  // the halo: its polyp and the diamond it forms
  /// the polyp: woven of both lineages, its stem caging a sac of both saps, fronds and plumed tentacles crowning it
  pub const polyp=@import("meshes/polyp_convergent.zig").woven;
  /// a flower of both lineages with no stem, drifting off a polyp
  pub const driftFlower=@import("meshes/drift_flower.zig");
  /// the seed the unforming gathers out of the shattered radiant light
  pub const strangeSeed=@import("meshes/strange_seed.zig");
  /// a shard of a shattering radiant plant, flying up to the seed
  pub const unformShard=@import("meshes/unform_shard.zig");
  /// an earlier look for the polyp, to compare: a slender hydra crowned with feathers and plumed tentacles, offshoots up its stem
  pub const polypHydra=@import("meshes/polyp_hydra.zig");
  /// an earlier look for the polyp, to compare: a colony of feathery polyps on one fleshy mound
  pub const polypColony=@import("meshes/polyp.zig");
  /// a mixed look for the polyp: the colony crowned with the hydra's hanging tentacles
  pub const polypHanging=@import("meshes/polyp.zig").hanging;
  /// a mixed look for the polyp: a colony of slender hydras on the fleshy mound
  pub const polypHydras=@import("meshes/polyp_hydra.zig").colony;
  /// a mixed look for the polyp: the hydra opening into its mouth disc, crowned with its feathery tentacles
  pub const polypHydraFeathered=@import("meshes/polyp_hydra.zig").feathered;
  /// a mixed look for the polyp: the hydra opening into its mouth disc, its long tentacles plumed at their tips
  pub const polypHydraPlumed=@import("meshes/polyp_hydra.zig").plumed;
  /// a convergent look for the polyp: its smooth flesh marbled with both saps, a sac at its gut
  pub const polypMarbled=@import("meshes/polyp_convergent.zig").marbled;
  /// the diamond a halo leaves, gathered in from its shards
  pub const haloDiamond=@import("meshes/halo.zig").diamond;
  // translucent, over everything
  /// the rays the diamond throws to make its ring
  pub const haloProjection=@import("meshes/halo.zig").projection;
  /// the ring of split light the diamond projects
  pub const haloRing=@import("meshes/halo.zig").ring;
  /// the flash of light where a halo's blooms meet
  pub const haloFlash=@import("meshes/halo.zig").flash;
  /// soft rays sent between two celestial blooms
  pub const bloomThread=@import("meshes/bloom_thread.zig");
};
/// the registry over `parts`: their ids, count and builders
const reg=registry.Registry(parts);
/// which library mesh: one tag per member of `parts`
pub const Id=reg.Id;
/// how many library meshes there are
pub const count=reg.count;
/// every library mesh id, in draw order
pub const ids=reg.ids;
/// every library mesh at each level of detail (one slot per mesh and level,
/// see `slot`).
pub const slots=count*mg.lods;
/// where a mesh at a level of detail sits in per-slot tables.
pub fn slot(id:Id,lod:u32)usize{return@as(usize,@intFromEnum(id))*mg.lods+lod;}
/// build one mesh at one level of detail into `b` (leaving `b.lod` there),
/// recording its (first vertex, count).
pub fn buildOne(b:*mg.Builder,id:Id,lod:u32,ranges:*[slots][2]u32)Allocator.Error!void{
  b.lod=lod;
  // where this mesh's vertices begin
  const first=b.mark();
  switch(id){
    inline else=>|k|try reg.module(k).build(b),
  }
  // a skeleton left unfinished leaves its times past one (never grown)
  if(b.grow.items.len>first)for(b.grow.items[first..])|g|assert(g.at[0]+g.at[1]<=1+1e-4);
  ranges[slot(id,lod)]=.{@intCast(first),@intCast(b.mark()-first)};
}
