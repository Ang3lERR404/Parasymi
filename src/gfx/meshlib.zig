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
/// all the maths: the points a sample's glows sit at
const m=engine.core.math;
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
  // the gardener's sculpts, one slot each (sculpts.slots of them)
  /// the first sculpt on the shelf
  pub const sculpt0=@import("meshes/sculpt.zig").Slot(0);
  /// the second
  pub const sculpt1=@import("meshes/sculpt.zig").Slot(1);
  /// the third
  pub const sculpt2=@import("meshes/sculpt.zig").Slot(2);
  /// the fourth
  pub const sculpt3=@import("meshes/sculpt.zig").Slot(3);
  /// the fifth
  pub const sculpt4=@import("meshes/sculpt.zig").Slot(4);
  /// the sixth
  pub const sculpt5=@import("meshes/sculpt.zig").Slot(5);
  /// the seventh
  pub const sculpt6=@import("meshes/sculpt.zig").Slot(6);
  /// the eighth
  pub const sculpt7=@import("meshes/sculpt.zig").Slot(7);
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
  /// a satellite: a thought-bud furled shut, blending open into the next
  pub const arsthraxiaBud0=@import("meshes/arsthraxia.zig").budKey(0);
  /// a thought-bud a third open
  pub const arsthraxiaBud1=@import("meshes/arsthraxia.zig").budKey(1);
  /// a thought-bud two thirds open
  pub const arsthraxiaBud2=@import("meshes/arsthraxia.zig").budKey(2);
  /// a thought-bud open
  pub const arsthraxiaBud3=@import("meshes/arsthraxia.zig").budKey(3);
  /// the warm heart glowing in a thought-bud
  pub const arsthraxiaBudHeart=@import("meshes/arsthraxia.zig").budHeart;
  /// a sample: the satellites' thought-bud, closed, half open, open
  pub const arsthraxiaBudSpiral=@import("meshes/arsthraxia.zig").budSpiral;
  /// a sketch: the constellate lineage's fragments, few of them joined
  pub const constellateLoose=@import("meshes/constellate.zig").loose;
  /// a sketch: more joined, the first panes filling in
  pub const constellateForming=@import("meshes/constellate.zig").forming;
  /// a sketch: joined through, panes across most of it
  pub const constellateCrystalline=@import("meshes/constellate.zig").crystalline;
  /// a sketch: a constellate petal, a part to build with
  pub const constellatePetal=@import("meshes/constellate.zig").petal;
  /// a sketch: a constellate leaf, a part to build with
  pub const constellateLeaf=@import("meshes/constellate.zig").leaf;
  /// a sketch: a constellate bud, a part to build with
  pub const constellateBud=@import("meshes/constellate.zig").bud;
  /// a sketch: a constellate flower head, a part to build with
  pub const constellateFlower=@import("meshes/constellate.zig").flower;
  /// a sketch: a constellate yielder, petals snapped to a flower head
  pub const constellateYield=@import("meshes/constellate.zig").yield;
  /// a sketch: a constellate stem, the part others fasten to
  pub const constellateStem=@import("meshes/constellate.zig").stem;
  /// a sketch: a constellate sprig, a branch and two leaves on a stem
  pub const constellateSprig=@import("meshes/constellate.zig").sprigMesh;
  /// a sketch: the constellate heart, four buds fastened to a stem
  pub const constellateHeartBound=@import("meshes/constellate.zig").heartBound;
  /// a sketch: the constellate heart rising, filaments dripping from it
  pub const constellateHeartRising=@import("meshes/constellate.zig").heartRising;
  /// a sketch: the constellate heart blooming into its grand flower
  pub const constellateHeartBlooming=@import("meshes/constellate.zig").heartBlooming;
  /// a sketch: the constellate heart's chain reaction
  pub const constellateHeartChain=@import("meshes/constellate.zig").heartChain;
  /// a sketch: the constellate heart settling into a builder
  pub const constellateHeartBuilder=@import("meshes/constellate.zig").heartBuilder;
  /// a sketch: the constellate heart's whole story, every stage in turn
  pub const constellateHeart=@import("meshes/constellate.zig").heartWhole;
  /// a sketch: a constellate tendril the gardener draws, floating
  pub const constellateTendril=@import("meshes/constellate.zig").tendril;
  /// a sketch: a constellate tendril along the ground
  pub const constellateTendrilGround=@import("meshes/constellate.zig").tendrilGround;
  /// a sketch: a constellate tendril arcing over
  pub const constellateTendrilArc=@import("meshes/constellate.zig").tendrilArc;
  /// a sketch: act 2's gardener, a hyena of stars hovering
  pub const constellateHyena=@import("meshes/constellate.zig").hyenaMesh;
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
  /// the nebularbor: a mist tree of both lineages, an umbrella crown with curtains of strands at its rim
  pub const nebularbor=@import("meshes/nebularbor.zig");
  /// a look it was blended from, to compare: the dew-bearer, curtains of strands hanging from its arching boughs
  pub const nebularborWeeping=@import("meshes/nebularbor.zig").weeping;
  /// a look it was blended from, to compare: the cloud-bearer, forking limbs crowned flat as an umbrella
  pub const nebularborCloud=@import("meshes/nebularbor.zig").cloud;
  /// the root well: a woven basket of both lineages on a rooted foot, leaves round its rim
  pub const rootWell=@import("meshes/root_well.zig");
  /// the water a root well holds, see-through, drawn after the basket round it
  pub const rootWellWater=@import("meshes/root_well.zig").water;
  /// the tanglehold: a sac of both saps caged in woven staves on a rooted foot
  pub const tanglehold=@import("meshes/tanglehold.zig");
  /// the storm spire: a woven spire, vane rings, a caged chamber, lanterns flown into the cloud
  pub const stormSpire=@import("meshes/storm_spire.zig");
  /// a bolt of lightning a storm spire strikes, bent along its curve on the GPU
  pub const stormBolt=@import("meshes/storm_spire.zig").bolt;
  /// one of a storm spire's lanterns, flown free on its thread
  pub const stormLantern=@import("meshes/storm_spire.zig").lantern;
  /// a storm spire's lantern thread, bent along the curve it hangs in on the GPU
  pub const stormThread=@import("meshes/storm_spire.zig").thread;
  // the halo: its polyp and the diamond it forms
  /// the polyp: woven of both lineages, its stem caging a sac of both saps, fronds and plumed tentacles crowning it
  pub const polyp=@import("meshes/polyp_convergent.zig").woven;
  /// a flower of both lineages with no stem, drifting off a polyp
  pub const driftFlower=@import("meshes/drift_flower.zig");
  /// the seed the unforming gathers out of the shattered radiant light
  pub const strangeSeed=@import("meshes/strange_seed.zig");
  /// the loose fragments a planted strange seed conjures, rising out of it
  pub const strangeSeedWeb=@import("meshes/constellate.zig").seedWeb;
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
  /// a spark of lightning jumping in a weftstone's chamber as it ionizes
  pub const weftstoneSpark=@import("meshes/weftstone.zig").spark;
};
/// the registry over `parts`: their ids, count and builders
const reg=registry.Registry(parts);
/// which library mesh: one tag per member of `parts`
pub const Id=reg.Id;
/// something glowing a sample is drawn with (`--samples=`): a library mesh
/// lit from within, and the light it throws into the air. A sample mesh
/// lists its own as `glows`.
pub const Glow=struct{
  /// the glowing library mesh, by name
  mesh:[]const u8,
  /// where it sits, in the sample's own space
  at:m.V3,
  /// how big it is drawn
  scale:f32,
  /// how bright it glows
  glow:f32,
  /// the colour and strength of the light it throws
  light:m.V3,
  /// how far that light reaches
  reach:f32,
};
/// the key mesh `id` blends into (its `next`, by name; none: null): a bud's
/// next shape as it opens, built after it, vertex for vertex alike
pub fn next(id:Id)?Id{
  return switch(id){
    inline else=>|k|if(@hasDecl(reg.module(k),"next"))comptime(std.meta.stringToEnum(Id,reg.module(k).next).?)else null,
  };
}
/// a skinned sample's bones at time `t` (s), placed by `at`, written to
/// `out`; returns how many
pub const Pose=*const fn(t:f32,at:m.M4,out:[]m.M4)usize;
/// the most bones a skinned sample poses
pub const maxPoseBones=32;
/// how sample `id` is posed (its `pose`; none: it is drawn rigid)
pub fn poser(id:Id)?Pose{
  return switch(id){
    inline else=>|k|if(@hasDecl(reg.module(k),"pose"))reg.module(k).pose else null,
  };
}
/// what glows with sample `id` (its `glows`; none: nothing)
pub fn glows(id:Id)[]const Glow{
  return switch(id){
    inline else=>|k|if(@hasDecl(reg.module(k),"glows"))reg.module(k).glows else &.{},
  };
}
/// how many library meshes there are
pub const count=reg.count;
/// every library mesh id, in draw order
pub const ids=reg.ids;
/// every library mesh at each level of detail (one slot per mesh and level,
/// see `slot`).
pub const slots=count*mg.lods;
/// where a mesh at a level of detail sits in per-slot tables.
pub fn slot(id:Id,lod:u32)usize{return@as(usize,@intFromEnum(id))*mg.lods+lod;}
/// the sculpt slots, in order: the shelf's `i`th sculpt is drawn from the `i`th
pub const sculptSlots=[_]Id{.sculpt0,.sculpt1,.sculpt2,.sculpt3,.sculpt4,.sculpt5,.sculpt6,.sculpt7};
/// build one mesh at one level of detail into `b` (leaving `b.lod` there),
/// recording its (first vertex, count).
pub fn buildOne(b:*mg.Builder,id:Id,lod:u32,ranges:*[slots]m.Vice(u32,2))Allocator.Error!void{
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
