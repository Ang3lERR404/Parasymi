//! CONFLUENCE: the convergence hybrid. Never sown: it takes root on its own
//! where a mature symbiote and a mature parasite meet (game/convergence.zig),
//! grows for half again as long as the slower parent, and once mature
//! contains the parasites around it rather than killing them. Condenses
//! convergence essence. Its body tells the meeting (gfx/meshes/
//! convergence_kit.zig `confluence`): a trunk of each lineage winding up
//! round the other and fusing into one weave of both, crowned by flowers.
const species = @import("../species.zig");
const color = @import("../../core/color.zig");

pub const def:species.Species = .{
  .lineage = .convergent, .seed = null, .size = 2, .yields = .convergence_essence,
  // decision: mature_time is the fallback for a confluence without parents
  // (1.5x the slower first pair); a spawned one carries its own span.
  .mature_time = 18, .mana_cap = 40, .ley_draw = 1.6, .share = 0.5, .drain = 0, .yield = 0.12,
  .contain = 3, .sway = 1.5,
  .stages = 4,
  .genome = .{
    .form = .confluence,
    // its height and the girth of its trunks, its flowers' petals and
    // size (the rest of its body is the kit's; colours too)
    .stem_h = 2.8, .stem_r = 0.2, .segments = 0, .curl = 0, .wobble = 0.08,
    .leaves = 0, .leaf_len = 0, .leaf_w = 0, .leaf_droop = 0,
    .petals = 8, .bloom_r = 0.55, .thorns = 0, .tendrils = 0, .shoots = .{0, 0},
    .stem_col = color.rgb(0.36, 0.58, 0.24), .leaf_col = color.rgb(0.68, 0.62, 0.82), .bloom_col = color.rgb(0.58, 0.36, 0.9),
  },
  .parents = .{.lumenroot, .thornleech},
};
