//! DRIFTBRAID: the braided conduit's lanes and the sporecaster's spores in
//! one sown body. Lanes of sapwood wind up its stalk through a cage of the
//! parasites' lattice to a marbled spore sac, and a crown of five fronds
//! flares round its pore, each ending in a small flower of both lineages.
//! It draws hard on the ley and condenses ley shards.
const species = @import("../species.zig");
const color = @import("../../core/color.zig");

pub const def:species.Species = .{
  .lineage = .convergent, .seed = .seed_driftbraid, .yields = .ley_shard,
  .mature_time = 20, .mana_cap = 18, .ley_draw = 1.4, .share = 0.5, .drain = 0.8, .yield = 0.1,
  .sway = 0.9,
  .genome = .{
    .form = .entwined, .body = .drift,
    // the stalk, the crown's fronds (`tendrils` long, `petals` per flower
    // at their tips) and the spore sac
    .stem_h = 0.95, .stem_r = 0.05, .segments = 0, .curl = 0, .wobble = 0.06,
    .leaves = 6, .leaf_len = 0.09, .leaf_w = 0.03, .leaf_droop = 0.3,
    .petals = 6, .bloom_r = 0.11, .thorns = 3, .tendrils = 0, .shoots = .{0, 0},
    .stem_col = color.rgb(0.32, 0.5, 0.36), .leaf_col = color.rgb(0.68, 0.62, 0.84), .bloom_col = color.rgb(0.55, 0.62, 0.95),
  },
};
