//! CONFLUENCE: the convergence hybrid. Never sown: it takes root on its own
//! where a mature symbiote and a mature parasite meet (game/convergence.zig),
//! grows for half again as long as the slower parent, and once mature
//! contains the parasites around it rather than killing them. Condenses
//! convergence essence and ripens its parents' seeds.
const species = @import("../species.zig");
const color = @import("../../core/color.zig");

pub const def:species.Species = .{
  .name = "CONFLUENCE", .lineage = .convergent, .seed = null, .size = 2, .yields = .convergence_essence,
  // decision: mature_time is the fallback for a confluence without parents
  // (1.5x the slower first pair); a spawned one carries its own span.
  .mature_time = 18, .mana_cap = 40, .ley_draw = 1.6, .share = 0.5, .drain = 0, .yield = 0.12, .seed_time = 50,
  .contain = 3, .sway = 1.5,
  .stages = .{"ROOTING", "ENTWINING", "REACHING", "BLOOMING"},
  .genome = .{
    .form = .confluence,
    .stem_h = 2.8, .stem_r = 0.34, .segments = 10, .curl = 0.04, .wobble = 0.08,
    .leaves = 0, .leaf_len = 0, .leaf_w = 0, .leaf_droop = 0,
    .petals = 11, .bloom_r = 0.55, .thorns = 0, .tendrils = 7,
    .tendril_curl = 0.15, .tendril_wobble = 0.2,
    // stem: the symbiotic weave; leaf: where it frays into the parasitic
    // reach; bloom: violet sap at the heart of a petal, amber at its rim
    .stem_col = color.rgb(0.2, 0.48, 0.38), .leaf_col = color.rgb(0.52, 0.2, 0.18), .bloom_col = color.rgb(0.55, 0.3, 0.95),
  },
  .parents = .{.lumenroot, .thornleech},
};
