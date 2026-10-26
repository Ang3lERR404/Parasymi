//! THORNLEECH: the first parasite, alien rather than hostile (a coil, built
//! by gfx/meshes/parasite_kit.zig: a lattice cage of a stalk with its sacs
//! hanging inside, a crown of five fronds each ending in a small cage of
//! its own). Drains every non-parasitic neighbour and the ley beneath it;
//! yields more, at their expense.
const species = @import("../species.zig");
const color = @import("engine").core.color;

pub const def:species.Species = .{
  .lineage = .parasitic, .seed = .seed_thornleech,
  .mature_time = 8, .mana_cap = 14, .ley_draw = 1.0, .share = 0, .drain = 1.2, .yield = 0.22,
  .genome = .{
    .form = .coil,
    // a coil: its stalk's height and girth, the sacs in its cage (`thorns`)
    // and the fronds of its crown (`tendrils`), its skin, fronds and sap
    // (it grows no leaves, petals or offshoots, and stands dead upright)
    .stem_h = 0.6, .stem_r = 0.045, .segments = 0, .curl = 0, .wobble = 0,
    .leaves = 0, .leaf_len = 0, .leaf_w = 0, .leaf_droop = 0,
    .petals = 0, .bloom_r = 0.06, .thorns = 3, .tendrils = 5, .shoots = .{0, 0},
    .stem_col = color.rgb(0.56, 0.54, 0.62), .leaf_col = color.rgb(0.68, 0.62, 0.82), .bloom_col = color.rgb(0.46, 0.62, 0.86),
  },
};
