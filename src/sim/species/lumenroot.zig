//! LUMENROOT: the first symbiote. Shares its mana with every non-parasitic
//! neighbour, and grows faster among kin.
const species = @import("../species.zig");
const color = @import("../../core/color.zig");

pub const def:species.Species = .{
  .lineage = .symbiotic, .seed = .seed_lumenroot,
  .mature_time = 12, .mana_cap = 10, .ley_draw = 0.6, .share = 0.8, .drain = 0, .yield = 0.12, .seed_time = 25,
  .genome = .{
    .stem_h = 0.75, .stem_r = 0.035, .segments = 7, .curl = 0, .wobble = 0.1,
    .leaves = 7, .leaf_len = 0.32, .leaf_w = 0.11, .leaf_droop = 0.35,
    .petals = 6, .bloom_r = 0.14, .thorns = 0, .tendrils = 0,
    .stem_col = color.rgb(0.25, 0.55, 0.35), .leaf_col = color.rgb(0.30, 0.85, 0.55), .bloom_col = color.rgb(0.55, 0.95, 1.0),
  },
};
