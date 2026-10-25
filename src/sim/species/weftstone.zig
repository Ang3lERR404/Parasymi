//! WEFTSTONE: the loomfern's weaving and the lithophage's hunger in one
//! sown body. A fern of five exact fronds whose leaflets are a symbiote's,
//! round a crop of marbled sap where stone it draws up from the ley is
//! woven into grit. Shares with its kin, drains parasites beside it.
const species = @import("../species.zig");
const color = @import("../../core/color.zig");

pub const def:species.Species = .{
  // decision: grit, the pair's scarcer make (a loomfern weaves fibre unfed)
  .lineage = .convergent, .seed = .seed_weftstone, .yields = .grit,
  .mature_time = 14, .mana_cap = 16, .ley_draw = 1.0, .share = 0.4, .drain = 0.6, .yield = 0.18,
  .genome = .{
    .form = .entwined, .body = .weft,
    // the bole's height and girth, leaflet pairs per frond and their size,
    // the crop (`bloom_r`) and the sacs on its core (`thorns`)
    .stem_h = 0.3, .stem_r = 0.038, .segments = 0, .curl = 0, .wobble = 0.06,
    .leaves = 9, .leaf_len = 0.12, .leaf_w = 0.024, .leaf_droop = 0.3,
    .petals = 0, .bloom_r = 0.085, .thorns = 0, .tendrils = 0, .shoots = .{0, 0},
    .stem_col = color.rgb(0.3, 0.55, 0.34), .leaf_col = color.rgb(0.66, 0.62, 0.78), .bloom_col = color.rgb(0.62, 0.42, 0.9),
  },
};
