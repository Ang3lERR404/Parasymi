//! species registry. Each species is its own module under `species/`;
//! everything about a plant derives from its `def`: simulation stats, which
//! lineage it belongs to, how its mesh is grown (the genome), its seed and
//! which parents it was spliced from.
//!
//! A new species is one new file plus one line in `parts`.
const lib=@import("../lib.zig");
/// what can be held: the seed that plants a species, what it yields
const items=lib.items;
/// the engine package, reached through the hub
const engine=lib.engine;
/// colour types, for each genome's stem, leaf and bloom
const color=engine.core.color;
/// all the maths: conversions
const m=engine.core.math;
/// the engine's registry: one module per thing, an enum over them
const registry=engine.core.registry;
/// every species, one module each
const parts=struct{
  /// the first symbiote, sharing its mana with its neighbours
  pub const lumenroot=@import("species/lumenroot.zig");
  /// the first parasite, draining its neighbours and the ley
  pub const thornleech=@import("species/thornleech.zig");
  /// the evening star's flower, the first convergent hybrid
  pub const vesper=@import("species/vesper.zig");
  /// a floater that drinks the night sky and condenses starlight
  pub const driftwisp=@import("species/driftwisp.zig");
  /// a 2x2 heart-tree, a deep mana reservoir
  pub const hollowheart=@import("species/hollowheart.zig");
  /// the convergence hybrid, rooting where the lineages meet
  pub const confluence=@import("species/confluence.zig");
  /// the celestial bloom, the garden's power source
  pub const bloom=@import("species/bloom.zig");
};
/// the registry over `parts`: their ids, count and definitions
const reg=registry.Registry(parts);
/// which species: one tag per member of `parts`
pub const Id=reg.Id;
/// how many species there are
pub const count=reg.count;
/// every species id, in declaration order
pub const ids=reg.ids;
/// which path a plant walks
pub const Lineage=enum(u8){
  /// the sharers: they feed their neighbours
  symbiotic,
  /// the takers: they drain their neighbours
  parasitic,
  /// both at once: the first step toward the eventual merge of the two paths.
  convergent,
  /// shader-side scalar: +1 symbiotic, -1 parasitic, 0 convergent.
  pub fn affinity(l:Lineage)f32{
    return switch(l){.symbiotic=>1,.parasitic=>-1,.convergent=>0};
  }
};
/// how a genome is grown into a mesh (see gfx/meshgen.zig).
pub const Form=enum(u8){
  /// a stem with leaves, thorns, tendrils and a bloom
  herb,
  /// the parasites' alien body: a twisted stalk on a bulbous foot with
  /// bladders (`thorns`) up it and a crown of curling fronds (`tendrils`)
  /// around a bulb (`bloomR`); no leaves or petals
  coil,
  /// a floater: a translucent float (sized by `bloomR`), a short neck
  /// (`stemH`) lifting a wide catcher dish (`petals`), and filaments
  /// (`tendrils`) trailing beneath; nothing reaches the ground
  drift,
  /// where the lineages first meet: two trunks, one of each, winding round
  /// each other and fusing into one entwined crown (gfx/meshes/
  /// convergence_kit.zig), grown through keys
  confluence,
  /// a structure of light: a luminous core with fragments orbiting it
  /// (`petals` lens plates, `bloomR` its size); it assembles rather than
  /// grows, and drifts rather than bends
  radiant,
  /// an evening star's flower: the radiant body brought down to hang over
  /// its tile (`stemH` up, nothing under it), a star of `petals` rays
  /// round its core (`bloomR`) and `leaves` floating free beneath, all
  /// gathered, falling in from the sky (radiant_kit `star`)
  star,
};
/// procedural mesh parameters (see gfx/meshgen.zig).
pub const Genome=struct{
  /// how the genome is grown into a mesh
  form:Form=.herb,
  /// the stem grows as a vine (gfx/meshgen.zig `Growth`): `segments`+1
  /// control points, `curl` spiral (0 none .. 0.5 tight), `wobble` noise.
  /// stemH: how tall the stem stands (m)
  stemH:f32,
  /// how thick the stem is at its foot (m, a radius)
  stemR:f32,
  /// how many segments the stem's vine is grown in
  segments:u8,
  /// how tightly the stem spirals (0 none .. 0.5 tight)
  curl:f32,
  /// how much noise bends the stem
  wobble:f32=0.1,
  /// how many leaves grow on it
  leaves:u8,
  /// each leaf's length (m)
  leafLen:f32,
  /// each leaf's width (m)
  leafW:f32,
  /// how far each leaf droops toward its tip
  leafDroop:f32,
  /// how far up the stem (0..1) the leaves begin: low for a leafy herb,
  /// high for a tree that carries its leaves as a crown
  leafFrom:f32=0.2,
  /// how many petals its bloom has (or plates, rays, dish petals by form)
  petals:u8,
  /// how big its bloom is (m, a radius)
  bloomR:f32,
  /// how many thorns (a coil's sacs) it grows
  thorns:u8,
  /// how many tendrils (a coil's fronds, a drift's filaments) it grows
  tendrils:u8,
  /// a symbiote's rosette of broad leaves round its foot, and leafy vines
  /// twining up its stem (gfx/meshes/structure_kit.zig `plant`):
  /// how many rosette leaves
  rosette:u8=0,
  /// how many vines twine up the stem
  vines:u8=0,
  /// offshoots: side stems off the main stem, each ending in a bud or a
  /// small bloom (looks only); each variant grows between the two
  shoots:[2]u8=.{1,3},
  /// tendrils are grown vines too: they coil as they reach for the ground;
  /// how tightly they coil
  tendrilCurl:f32=0.4,
  /// how much noise bends them
  tendrilWobble:f32=0.2,
  /// the stem's colour
  stemCol:color.Rgb,
  /// the leaves' colour
  leafCol:color.Rgb,
  /// the bloom's colour
  bloomCol:color.Rgb,
};
/// everything a species is: its lineage, seed, footprint, mana and yield,
/// how it grows and looks
pub const Species=struct{
  /// which path it walks
  lineage:Lineage,
  /// the item that plants this species; null when it cannot be sown and only
  /// grows where its parents meet. Plants never set seed: seeds are woven
  /// by a germinator, and an uprooted plant comes back as its seed.
  seed:?items.Item,
  /// footprint: a size x size square of tiles, or none at all when floating
  /// (a floater hovers over any tile, even another plant).
  size:u8=1,
  /// whether it floats, taking no tile
  floating:bool=false,
  /// what condenses inside the plant from its mana, harvested by hand or conduit.
  yields:items.Item=.essence,
  /// seconds to maturity at full mana.
  matureTime:f32,
  /// the most mana it holds
  manaCap:f32,
  /// mana drawn from the ley field under the plant per second.
  leyDraw:f32,
  /// mana shared to (symbiotic) neighbours per second
  share:f32,
  /// mana stolen from (parasitic) neighbours per second
  drain:f32,
  /// essence condensed per second from stored mana once mature.
  yield:f32,
  /// how its mesh is grown
  genome:Genome,
  /// the two species it was spliced from, if any
  parents:?[2]Id=null,
  /// parasites within this many tiles of the mature plant drain at
  /// `contained` of their rate (0: none).
  contain:u8=0,
  /// wind sway amplitude relative to other plants.
  sway:f32=1,
  /// a floater's height above the ground
  hover:f32=1.15,
  /// where its ripe yield is plucked by paw: how high over its foot (a
  /// floater's: over its own floating point), in metres at full size
  pluck:f32=0.5,
  /// celestial energy: the radius (tiles) of the field this plant holds
  /// once it radiates (0: none) (see ecology `Radiance`)
  radiance:f32=0,
  /// how far (tiles) it links with others of its kind into one network
  link:f32=0,
  /// it needs celestial energy: outside every field it halts and withers
  needsRadiance:bool=false,
  /// growth stages named on hover (0: unstaged; names in `game/text.zig`,
  /// the mesh itself grows continuously; see meshgen `keys`).
  stages:u8=0,
  /// which stage a plant at `growth` shows (0 when unstaged).
  pub fn stage(s:*const Species,growth:f32)u32{
    if(s.stages==0)return 0;
    return@min(s.stages-1,@as(u32,@intFromFloat(@max(growth,0)*m.f(s.stages))));
  }
};
/// drain rate of a parasite near a mature containing plant.
pub const contained:f32=0.5;
/// every species' definition, by id
pub const table=reg.table(Species,"def");
/// the definition of species `id`
pub inline fn get(id:Id)*const Species{return table.getPtrConst(id);}
/// which species an item plants, if any.
pub fn fromSeed(item:items.Item)?Id{
  inline for(ids)|id|if(table.get(id).seed)|s|if(s==item)return id;
  return null;
}
