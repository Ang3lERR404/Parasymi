//! THORNLEECH: the first parasite, alien rather than hostile (a coil: twisted
//! stalk, bladders, curling fronds). Drains every non-parasitic neighbour and
//! the ley beneath it; yields more, at their expense.
const species = @import("../species.zig");
const color = @import("../../core/color.zig");

pub const def:species.Species = .{
  .name = "THORNLEECH", .lineage = .parasitic, .seed = .seed_thornleech,
  .mature_time = 8, .mana_cap = 14, .ley_draw = 1.0, .share = 0, .drain = 1.2, .yield = 0.22, .seed_time = 20,
  .genome = .{
    .form = .coil,
    .stem_h = 0.6, .stem_r = 0.045, .segments = 6, .curl = 0.15, .wobble = 0.15,
    .leaves = 3, .leaf_len = 0.22, .leaf_w = 0.06, .leaf_droop = 0.8,
    .petals = 0, .bloom_r = 0.06, .thorns = 5, .tendrils = 6, .tendril_curl = 0.4, .tendril_wobble = 0.2,
    .stem_col = color.rgb(0.56, 0.54, 0.62), .leaf_col = color.rgb(0.70, 0.70, 0.80), .bloom_col = color.rgb(0.46, 0.62, 0.86),
  },
};
