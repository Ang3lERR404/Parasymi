//! species registry. Each species is its own module under `species/`;
//! everything about a plant derives from its `def`: simulation stats, which
//! lineage it belongs to, how its mesh is grown (the genome), its seed and
//! which parents it was spliced from.
//!
//! A new species is one new file plus one line in `parts`.
const items = @import("items.zig");
const registry = @import("../core/registry.zig");

const parts = struct {
  pub const lumenroot = @import("species/lumenroot.zig");
  pub const thornleech = @import("species/thornleech.zig");
  pub const vesper = @import("species/vesper.zig");
  pub const driftwisp = @import("species/driftwisp.zig");
  pub const hollowheart = @import("species/hollowheart.zig");
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

/// procedural mesh parameters (see gfx/meshgen.zig).
pub const Genome = struct {
  /// the stem grows as a vine (gfx/meshgen.zig `Growth`): `segments`+1
  /// control points, `curl` spiral (0 none .. 0.5 tight), `wobble` noise.
  stem_h:f32, stem_r:f32, segments:u8, curl:f32, wobble:f32 = 0.1,
  leaves:u8, leaf_len:f32, leaf_w:f32, leaf_droop:f32,
  petals:u8, bloom_r:f32,
  thorns:u8, tendrils:u8,
  /// tendrils are grown vines too: they coil as they reach for the ground
  tendril_curl:f32 = 0.4, tendril_wobble:f32 = 0.2,
  stem_col:[3]f32, leaf_col:[3]f32, bloom_col:[3]f32,
};

pub const Species = struct {
  name:[]const u8,
  lineage:Lineage,
  /// the item that plants this species
  seed:items.Item,
  /// footprint: a size x size square of tiles, or none at all when floating
  /// (a floater hovers over any tile, even water or another plant).
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
  /// seconds for a mature plant to ripen one seed.
  seed_time:f32,
  genome:Genome,
  parents:?[2]Id = null,
};

pub const table = reg.table(Species, "def");

pub inline fn get(id:Id) *const Species { return table.getPtrConst(id); }

/// which species an item plants, if any.
pub fn fromSeed(item:items.Item) ?Id {
  inline for (ids) |id| if (table.get(id).seed == item) return id;
  return null;
}
