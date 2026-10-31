//! the garden's meshes: every plant grown from its species genome out of the
//! engine's primitives (engine gfx/meshgen.zig: tubes, lofts, vines, braids)
//! and the garden's own (blades, laminae, petals, stamens, flowers).
const lib=@import("../lib.zig");
/// the engine package, reached through the hub
const engine=lib.engine;
/// all the maths: vectors, splines, easing
const m=engine.core.math;
/// the garden's vertex layouts and part roles
const vertex=lib.vertex;
/// the species registry, whose genome picks each plant's form
const species=lib.species;
/// blades: bent strips with a body, the vein on the cupped face
pub const blades=@import("meshgen/blades.zig");
/// laminae: leaves and petals with a body, folding to a midrib
pub const laminae=@import("meshgen/laminae.zig");
/// petals, pollen and stamens: what a flower is made of
pub const petals=@import("meshgen/petals.zig");
/// shoots: whole plants grown from their genome, stalk by stalk
pub const shoots=@import("meshgen/shoots.zig");
/// flowers: the bloom at a stalk's tip, its bud and calyx, and leaves along a stalk
pub const flowers=@import("meshgen/flowers.zig");
/// drifts: floaters held up by a sap lantern, filaments trailing below
pub const drifts=@import("meshgen/drifts.zig");
/// pods: a plant's yield ripening on it, beads of sap where it is plucked
pub const pods=@import("meshgen/pods.zig");
/// the meshgen tests: a blade's body and a confluence's growth keys
pub const tests=@import("meshgen/tests.zig");
/// a curved blade drooping out from its base (leaf or petal)
pub const blade=blades.blade;
/// a blade whose midrib follows a smooth spline through a path
pub const bladeAlong=blades.bladeAlong;
/// the midrib points of a drooping blade
pub const bladeSpine=blades.bladeSpine;
/// half a leaf's or petal's thickness, as a share of its broadest half-width
pub const laminaThick=laminae.laminaThick;
/// what a lamina is drawn from: its rows' spine, side, face, width and dish
pub const Lamina=laminae.Lamina;
/// builds a leaf or petal with a body, watertight, bevelled at its edges
pub const lamina=laminae.lamina;
/// what a petal is drawn from: where it rises, how it opens, its colours
pub const Petal=petals.Petal;
/// builds one petal
pub const petal=petals.petal;
/// pollen: the warm gold an anther is coloured
pub const pollen=petals.pollen;
/// what a flower's stamens are drawn from: how many, how long, their colour
pub const Stamens=petals.Stamens;
/// builds a ring of stamens (every flower has them; closed buds hide them)
pub const stamens=petals.stamens;
/// builds one whole plant of a species from its genome
pub const plant=shoots.plant;
/// how many offshoots a variant grows, between the genome's two counts
pub const shootCount=shoots.shootCount;
/// where an offshoot ends: its tip, heading, path and growth timing
pub const Shoot=shoots.Shoot;
/// how many points a shoot's path is resampled into
pub const shootRes=shoots.shootRes;
/// builds an offshoot: a side stem leaving the main stem, curving up to the light
pub const offshoot=shoots.offshoot;
/// where an offshoot runs, for a caller building its stem itself
pub const shootPath=shoots.shootPath;
/// folds a stem built along an offshoot's path by each vertex's nearest point
pub const shootFoldNearest=shoots.shootFoldNearest;
/// marks vertices to fold in against their stem until growth reaches them
pub const shootFold=shoots.shootFold;
/// folds what grows along an offshoot (its leaves) with the stem beneath it
pub const shootFoldAlong=shoots.shootFoldAlong;
/// what a bloom sits on: a calyx of skin, or a bead of resin in sepals
pub const Calyx=flowers.Calyx;
/// builds an open bloom: its calyx, two whorls of petals and stamens
pub const flower=flowers.flower;
/// builds a closed bud, its stamens hidden inside
pub const bud=flowers.bud;
/// grows small leaves along a vine, turning round it, smaller toward the tip
pub const leavesAlong=flowers.leavesAlong;
/// one leaf at a point along a path (the grower's leaf: `growth.Skeleton.leaves`)
pub const leafAt=flowers.leafAt;
/// how many segments a blade's midrib is cut into, base to tip
pub const bladeSegs=12;
/// mesh variants grown per species, so neighbouring plants differ in shape.
pub const variantCount=4;
/// the engine's builder and primitives, writing the garden's vertex roles
/// the engine's builder and primitives, writing the garden's vertex roles
pub const gen=engine.gfx.meshgen.Mesher(vertex.Part,.stem);
/// the mesh builder: vertices pour into it, part by part
pub const Builder=gen.Builder;
/// a vine: a tube along a smooth spline, tapering at both ends
pub const vine=gen.vine;
/// a braid: strands twisting round one another along a path
pub const braid=gen.braid;
/// a braid turned to lie along a given side
pub const braidTurned=gen.braidTurned;
/// a braid wound round a core
pub const braidAround=gen.braidAround;
/// a loft: rings swept along a path and joined into a skin
pub const loft=gen.loft;
/// a patch: a smooth surface over a grid of points
pub const patch=gen.patch;
/// bands: stripes of colour along a tube
pub const bands=gen.bands;
/// what an ellipsoid is drawn from: its centre, radii and colour
pub const Ellipsoid=gen.Ellipsoid;
/// builds a closed ellipsoid
pub const ellipsoid=gen.ellipsoid;
/// a bundle: many thin tubes gathered into one
pub const bundle=gen.bundle;
/// the engine's mesh builder module, for its plain numbers and helpers
const eg=engine.gfx.meshgen;
/// how many levels of detail each mesh is built at
pub const lods=eg.lods;
/// how far from the camera each level of detail begins
pub const lodDistances=eg.lodDistances;
/// the level of detail for a distance
pub const lodAt=eg.lodAt;
/// which rows of a grid are kept at a level of detail (every one, every other...)
pub const stride=eg.stride;
/// the core of a braid: the path its strands wind round
pub const braidCore=eg.braidCore;
/// one strand of a braid, off its core
pub const braidStrand=eg.braidStrand;
/// how far a braid's strands stand off its core
pub const braidOff=eg.braidOff;
/// salts a strand's random seed, so neighbouring strands differ
pub const strandSalt=eg.strandSalt;
/// how far a strand has turned round its core at a share of its length
pub const strandTurn=eg.strandTurn;
/// how much a strand swells at a share of its length
pub const strandSwell=eg.strandSwell;
/// carries a frame along a path without twisting it (parallel transport)
pub const transport=eg.transport;
/// what a grown vine is drawn from: when along its length it forms
pub const Growth=eg.Growth;
/// builds a grown vine: a Catmull-Rom spline from a fixed root, tapering to points
pub const grow=eg.grow;
/// the smooth path a grown vine follows, root to tip
pub const growthPath=eg.growthPath;
/// the radii of a tube tapering to a point at both ends
pub const taperRadii=eg.taperRadii;
/// how a branch flares into the stem it leaves (a factor on its radius)
pub const collar=eg.collar;
/// growth keys a confluence is built at, evenly from sprout (0) to bloom (1).
/// Every key has the same vertices in the same order, so the plant shader
/// blends between the two around a plant's growth: it grows, never jumps.
pub const keys=8;
/// how many meshes a species is built as: shapes picked by tile, or for a
/// confluence its growth keys.
pub fn variants(id:species.Id)u32{
  return switch(species.get(id).genome.form){
    .herb,.coil,.drift,.radiant,.star=>variantCount,
    .confluence=>keys,
  };
}
/// for a species grown through keys: where between two keys a growth lies
pub const Key=struct{
  /// the key just below the growth
  v:u32,
  /// how far toward the next key it is (0..1)
  f:f32,
};
/// the growth key a plant of species `id` sits at for `growth` (0..1);
/// null for a species of fixed shapes
pub fn growthKey(id:species.Id,growth:f32)?Key{
  switch(species.get(id).genome.form){
    .herb,.coil,.drift,.radiant,.star=>return null,
    .confluence=>{
      // how far through the keys the growth lies, and the key just below it
      const x=m.clamp01(growth)*(keys-1);
      const v=@min(m.floorTo(u32,x),keys-2);
      return.{.v=v,.f=x-m.f(v)};
    },
  }
}
/// slots per species in per-variant tables (the most any species uses).
pub const maxVariants=@max(variantCount,keys);
/// where a (species, variant, level of detail) mesh sits in per-variant tables.
/// where a (species, variant, level of detail) mesh sits in per-variant tables.
pub fn plantSlot(id:species.Id,variant:u32,lod:u32)usize{return(@as(usize,@intFromEnum(id))*maxVariants+variant)*lods+lod;}
test{
  _=blades;
  _=laminae;
  _=petals;
  _=shoots;
  _=flowers;
  _=drifts;
  _=pods;
  _=tests;
}
