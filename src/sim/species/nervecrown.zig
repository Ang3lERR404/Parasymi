//! NERVECROWN: the gathering crown's reach and the ganglion's sharing in
//! one sown body. A rosette of broad leaves with pale nerves running down
//! their midribs, out of a knot of five nodules round a marbled sac,
//! crowned by petals and fronds in turn. It shares its mana far and wide
//! and calms the parasites round it once grown.
const species = @import("../species.zig");
const color = @import("../../core/color.zig");

pub const def:species.Species = .{
  .lineage = .convergent, .seed = .seed_nervecrown, .yields = .essence,
  .mature_time = 18, .mana_cap = 22, .ley_draw = 0.9, .share = 1.0, .drain = 0.3, .yield = 0.15,
  .contain = 2, .sway = 0.8,
  .genome = .{
    .form = .entwined, .body = .nerve,
    // the stalk, the rosette's leaves, the crown's petals and its sac
    .stem_h = 0.3, .stem_r = 0.04, .segments = 0, .curl = 0, .wobble = 0.06,
    .leaves = 7, .leaf_len = 0.34, .leaf_w = 0.13, .leaf_droop = 0.4,
    .petals = 5, .bloom_r = 0.21, .thorns = 0, .tendrils = 0, .shoots = .{0, 0},
    .stem_col = color.rgb(0.3, 0.54, 0.32), .leaf_col = color.rgb(0.7, 0.64, 0.84), .bloom_col = color.rgb(0.95, 0.66, 0.4),
  },
};
