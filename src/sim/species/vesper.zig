//! VESPER BLOOM: the first convergent hybrid, spliced where symbiote and
//! parasite touch. Shares with symbiotes and drains parasites. The evening
//! star's flower: it needs celestial energy, and withers outside a bloom's
//! field.
const species = @import("../species.zig");
const color = @import("../../core/color.zig");

pub const def:species.Species = .{
  .name = "VESPER BLOOM", .lineage = .convergent, .seed = .seed_vesper,
  .mature_time = 16, .mana_cap = 24, .ley_draw = 0.8, .share = 0.6, .drain = 0.8, .yield = 0.4, .seed_time = 45,
  // decision: the first plant that needs radiance (the brief names none)
  .needs_radiance = true,
  .genome = .{
    .stem_h = 0.95, .stem_r = 0.04, .segments = 9, .curl = 0.12, .wobble = 0.12,
    .leaves = 9, .leaf_len = 0.30, .leaf_w = 0.09, .leaf_droop = 0.55,
    .petals = 9, .bloom_r = 0.2, .thorns = 4, .tendrils = 2,
    .stem_col = color.rgb(0.25, 0.2, 0.45), .leaf_col = color.rgb(0.45, 0.4, 0.95), .bloom_col = color.rgb(0.95, 0.75, 1.0),
  },
  .parents = .{.lumenroot, .thornleech},
};
