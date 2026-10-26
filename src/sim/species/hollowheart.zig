//! HOLLOWHEART: a 2x2 heart-tree. A deep mana reservoir that feeds
//! everything around its footprint.
const lib = @import("../../lib.zig");
const species = lib.species;
const engine = lib.engine;
const color = engine.core.color;

pub const def:species.Species = .{
  .lineage = .symbiotic, .seed = .seed_hollowheart, .size = 2,
  .mature_time = 45, .mana_cap = 60, .ley_draw = 2.4, .share = 0.9, .drain = 0, .yield = 0.5,
  // a heavy tree: it leans, it does not wave
  .sway = 0.6,
  .genome = .{
    .stem_h = 2.1, .stem_r = 0.16, .segments = 12, .curl = 0.06, .wobble = 0.08,
    .leaves = 20, .leaf_len = 0.75, .leaf_w = 0.24, .leaf_droop = 0.45, .leaf_from = 0.55,
    .petals = 7, .bloom_r = 0.4, .thorns = 0, .tendrils = 6, .shoots = .{2, 5}, .vines = 2,
    .stem_col = color.rgb(0.3, 0.24, 0.18), .leaf_col = color.rgb(0.25, 0.65, 0.4), .bloom_col = color.rgb(1.0, 0.8, 0.5),
  },
};
