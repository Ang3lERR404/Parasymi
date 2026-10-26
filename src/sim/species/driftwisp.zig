//! DRIFTWISP: a floater that occupies no tile: a sap float holding up a
//! catcher dish, filaments trailing beneath. Drinks the night sky instead
//! of the ley and condenses it into starlight.
const species = @import("../species.zig");
const color = @import("engine").core.color;

pub const def:species.Species = .{
  .lineage = .symbiotic, .seed = .seed_driftwisp, .floating = true, .yields = .starlight,
  .mature_time = 20, .mana_cap = 8, .ley_draw = 0.5, .share = 0.4, .drain = 0, .yield = 0.06,
  // light and hanging in the air: the wind carries it furthest
  .sway = 1.8,
  .genome = .{
    .form = .drift,
    .stem_h = 0.1, .stem_r = 0.028, .segments = 4, .curl = 0.05, .wobble = 0.1,
    .leaves = 0, .leaf_len = 0.1, .leaf_w = 0.05, .leaf_droop = 0,
    .petals = 10, .bloom_r = 0.26, .thorns = 0, .tendrils = 11, .tendril_curl = 0.15, .tendril_wobble = 0.12,
    .stem_col = color.rgb(0.5, 0.6, 0.8), .leaf_col = color.rgb(0.6, 0.7, 1.0), .bloom_col = color.rgb(0.85, 0.9, 1.0),
  },
};
