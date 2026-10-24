//! CELESTIAL BLOOM: the garden's power source. A floating symbiote that
//! yields nothing; it radiates. Mature, it holds a field of celestial
//! energy around it (`radiance`), and it links with every other bloom
//! within `link` tiles into one network: a growing bloom joined to a
//! network that holds a mature one radiates too, so uprooting the bloom
//! that joins them cuts off everything downstream. Plants that need
//! radiance (`needs_radiance`) halt and wither outside every field.
const species = @import("../species.zig");
const color = @import("../../core/color.zig");

pub const def:species.Species = .{
  .lineage = .symbiotic, .seed = .seed_bloom, .floating = true,
  // no item, no output: it radiates instead (the sky feeds it, as it does
  // every floater; it never condenses essence)
  .mature_time = 30, .mana_cap = 10, .ley_draw = 0.5, .share = 0, .drain = 0, .yield = 0,
  .radiance = 3.5, .link = 10,
  // the highest living thing in the garden, above the fallen starlight
  .hover = 3.2,
  // it drifts and bobs; it does not bend from a root
  .sway = 0.6,
  // pearl: plant.frag lays an iridescent film over it (it belongs to the sky)
  .genome = .{
    .form = .radiant,
    .stem_h = 0.12, .stem_r = 0.03, .segments = 4, .curl = 0.05, .wobble = 0.1,
    .leaves = 0, .leaf_len = 0.1, .leaf_w = 0.05, .leaf_droop = 0,
    .petals = 12, .bloom_r = 0.3, .thorns = 0, .tendrils = 5, .tendril_curl = 0.2, .tendril_wobble = 0.2,
    .stem_col = color.rgb(0.72, 0.76, 0.86), .leaf_col = color.rgb(0.85, 0.88, 0.95), .bloom_col = color.rgb(0.95, 0.95, 1.0),
  },
};
