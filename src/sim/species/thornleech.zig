//! THORNLEECH: the first parasite. Drains every non-parasitic neighbour and
//! the ley beneath it; yields more, at their expense.
const species = @import("../species.zig");
const color = @import("../../core/color.zig");

pub const def:species.Species = .{
  .name = "THORNLEECH", .lineage = .parasitic, .seed = .seed_thornleech,
  .mature_time = 8, .mana_cap = 14, .ley_draw = 1.0, .share = 0, .drain = 1.2, .yield = 0.22, .seed_time = 20,
  .genome = .{
    .stem_h = 0.55, .stem_r = 0.05, .segments = 6, .curl = 0.2, .wobble = 0.15,
    .leaves = 3, .leaf_len = 0.22, .leaf_w = 0.06, .leaf_droop = 0.8,
    .petals = 4, .bloom_r = 0.09, .thorns = 10, .tendrils = 4, .tendril_curl = 0.4, .tendril_wobble = 0.2,
    .stem_col = color.rgb(0.35, 0.12, 0.22), .leaf_col = color.rgb(0.55, 0.15, 0.35), .bloom_col = color.rgb(1.0, 0.25, 0.45),
  },
};
