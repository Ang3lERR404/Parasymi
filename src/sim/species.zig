//! species registry. Each species is its own module under `species/`;
//! everything about a plant derives from its `def`: simulation stats, which
//! lineage it belongs to, how its mesh is grown (the genome), its seed and
//! which parents it was spliced from.
//!
//! A new species is one new file plus one line in `parts`.
const items = @import("items.zig");
const color = @import("engine").core.color;
const m = @import("engine").core.math;
const registry = @import("engine").core.registry;

const parts = struct {
  pub const lumenroot = @import("species/lumenroot.zig");
  pub const thornleech = @import("species/thornleech.zig");
  pub const vesper = @import("species/vesper.zig");
  pub const driftwisp = @import("species/driftwisp.zig");
  pub const hollowheart = @import("species/hollowheart.zig");
  pub const confluence = @import("species/confluence.zig");
  pub const bloom = @import("species/bloom.zig");
};
const reg = registry.Registry(parts);

pub const Id = reg.Id;
pub const count = reg.count;
pub const ids = reg.ids;

pub const Lineage = enum(u8) {
  symbiotic, parasitic,
  /// both at once: the first step toward the eventual merge of the two paths.
  convergent,

  /// shader-side scalar: +1 symbiotic, -1 parasitic, 0 convergent.
  pub fn affinity(l:Lineage) f32 {
    return switch (l) { .symbiotic => 1, .parasitic => -1, .convergent => 0 };
  }
};

/// how a genome is grown into a mesh (see gfx/meshgen.zig).
pub const Form = enum(u8) {
  /// a stem with leaves, thorns, tendrils and a bloom
  herb,
  /// the parasites' alien body: a twisted stalk on a bulbous foot with
  /// bladders (`thorns`) up it and a crown of curling fronds (`tendrils`)
  /// around a bulb (`bloom_r`); no leaves or petals
  coil,
  /// a floater: a translucent float (sized by `bloom_r`), a short neck
  /// (`stem_h`) lifting a wide catcher dish (`petals`), and filaments
  /// (`tendrils`) trailing beneath; nothing reaches the ground
  drift,
  /// where the lineages first meet: two trunks, one of each, winding round
  /// each other and fusing into one entwined crown (gfx/meshes/
  /// convergence_kit.zig), grown through keys
  confluence,
  /// a structure of light: a luminous core with fragments orbiting it
  /// (`petals` lens plates, `bloom_r` its size); it assembles rather than
  /// grows, and drifts rather than bends
  radiant,
  /// an evening star's flower: the radiant body brought down to hang over
  /// its tile (`stem_h` up, nothing under it), a star of `petals` rays
  /// round its core (`bloom_r`) and `leaves` floating free beneath, all
  /// gathered, falling in from the sky (radiant_kit `star`)
  star,
};

/// procedural mesh parameters (see gfx/meshgen.zig).
pub const Genome = struct {
  form:Form = .herb,
  /// the stem grows as a vine (gfx/meshgen.zig `Growth`): `segments`+1
  /// control points, `curl` spiral (0 none .. 0.5 tight), `wobble` noise.
  stem_h:f32, stem_r:f32, segments:u8, curl:f32, wobble:f32 = 0.1,
  leaves:u8, leaf_len:f32, leaf_w:f32, leaf_droop:f32,
  /// how far up the stem (0..1) the leaves begin: low for a leafy herb,
  /// high for a tree that carries its leaves as a crown
  leaf_from:f32 = 0.2,
  petals:u8, bloom_r:f32,
  thorns:u8, tendrils:u8,
  /// a symbiote's rosette of broad leaves round its foot, and leafy vines
  /// twining up its stem (gfx/meshes/structure_kit.zig `plant`)
  rosette:u8 = 0, vines:u8 = 0,
  /// offshoots: side stems off the main stem, each ending in a bud or a
  /// small bloom (looks only); each variant grows between the two
  shoots:[2]u8 = .{1, 3},
  /// tendrils are grown vines too: they coil as they reach for the ground
  tendril_curl:f32 = 0.4, tendril_wobble:f32 = 0.2,
  stem_col:color.Rgb, leaf_col:color.Rgb, bloom_col:color.Rgb,
};

pub const Species = struct {
  lineage:Lineage,
  /// the item that plants this species; null when it cannot be sown and only
  /// grows where its parents meet. Plants never set seed: seeds are woven
  /// by a germinator, and an uprooted plant comes back as its seed.
  seed:?items.Item,
  /// footprint: a size x size square of tiles, or none at all when floating
  /// (a floater hovers over any tile, even another plant).
  size:u8 = 1,
  floating:bool = false,
  /// what condenses inside the plant from its mana, harvested by hand or conduit.
  yields:items.Item = .essence,
  /// seconds to maturity at full mana.
  mature_time:f32,
  mana_cap:f32,
  /// mana drawn from the ley field under the plant per second.
  ley_draw:f32,
  /// mana shared to (symbiotic) or stolen from (parasitic) neighbours per second.
  share:f32,
  drain:f32,
  /// essence condensed per second from stored mana once mature.
  yield:f32,
  genome:Genome,
  parents:?[2]Id = null,
  /// parasites within this many tiles of the mature plant drain at
  /// `CONTAINED` of their rate (0: none).
  contain:u8 = 0,
  /// wind sway amplitude relative to other plants.
  sway:f32 = 1,
  /// a floater's height above the ground
  hover:f32 = 1.15,
  /// celestial energy: the radius (tiles) of the field this plant holds
  /// once it radiates (0: none), and how far (tiles) it links with others
  /// of its kind into one network (see ecology `Radiance`)
  radiance:f32 = 0,
  link:f32 = 0,
  /// it needs celestial energy: outside every field it halts and withers
  needs_radiance:bool = false,
  /// growth stages named on hover (0: unstaged; names in `game/text.zig`,
  /// the mesh itself grows continuously; see meshgen `KEYS`).
  stages:u8 = 0,

  /// which stage a plant at `growth` shows (0 when unstaged).
  pub fn stage(s:*const Species, growth:f32) u32 {
    if (s.stages == 0) return 0;
    return @min(s.stages - 1, @as(u32, @intFromFloat(@max(growth, 0) * m.f(s.stages))));
  }
};

/// drain rate of a parasite near a mature containing plant.
pub const CONTAINED:f32 = 0.5;

pub const table = reg.table(Species, "def");

pub inline fn get(id:Id) *const Species { return table.getPtrConst(id); }

/// which species an item plants, if any.
pub fn fromSeed(item:items.Item) ?Id {
  inline for (ids) |id| if (table.get(id).seed) |s| if (s == item) return id;
  return null;
}
