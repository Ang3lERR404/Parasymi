//! LUMENROOT: the first symbiote. Shares its mana with every non-parasitic
//! neighbour, and grows faster among kin. Its body is the symbiotic
//! lineage's (gfx/meshes/structure_kit.zig `plant`): a braided stem on a
//! mat of braided roots, a leaf rosette, a vine twining up it, its cyan
//! bloom opening out of a bead of resin sap.
const species = @import("../species.zig");
const color = @import("../../core/color.zig");

pub const def:species.Species = .{
  .lineage = .symbiotic, .seed = .seed_lumenroot,
  .mature_time = 12, .mana_cap = 10, .ley_draw = 0.6, .share = 0.8, .drain = 0, .yield = 0.12,
  .genome = .{
    .stem_h = 0.75, .stem_r = 0.045, .segments = 7, .curl = 0, .wobble = 0.1,
    .leaves = 6, .leaf_len = 0.28, .leaf_w = 0.1, .leaf_droop = 0.35,
    .petals = 6, .bloom_r = 0.14, .thorns = 0, .tendrils = 0, .rosette = 4, .vines = 1,
    // the lineage's vine and leaf greens (gfx/meshes/palette.zig; its stem richer,
    // for the plant material mutes it), its own cyan bloom
    .stem_col = color.rgb(0.34, 0.66, 0.2), .leaf_col = color.rgb(0.40, 0.80, 0.38), .bloom_col = color.rgb(0.55, 0.95, 1.0),
  },
};
