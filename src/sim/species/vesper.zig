//! VESPER BLOOM: the first convergent hybrid, spliced where symbiote and
//! parasite touch. Shares with symbiotes and drains parasites. The evening
//! star's flower, of the radiant lineage's body (radiant_kit `star`): it
//! is gathered, never grown, falling in from the sky piece by piece, and
//! it needs celestial energy: outside a bloom's field it withers, its
//! pieces loosening and sinking as its light dims.
const species = @import("../species.zig");
const color = @import("engine").core.color;

pub const def:species.Species = .{
  .lineage = .convergent, .seed = .seed_vesper,
  .mature_time = 16, .mana_cap = 24, .ley_draw = 0.8, .share = 0.6, .drain = 0.8, .yield = 0.4,
  // decision: the first plant that needs radiance (the brief names none)
  .needs_radiance = true,
  // it hangs over its tile on light; it does not bend from a root
  .sway = 0.5,
  .genome = .{
    .form = .star,
    // stem_h: how high its core hangs over its tile (it has no stem)
    .stem_h = 0.62, .stem_r = 0.03, .segments = 4, .curl = 0.05, .wobble = 0.1,
    // its leaves float free beneath it, one of each lineage's in turn
    .leaves = 5, .leaf_len = 0.28, .leaf_w = 0.07, .leaf_droop = 0.5,
    // a five-rayed star
    .petals = 5, .bloom_r = 0.17, .thorns = 0, .tendrils = 0,
    .shoots = .{0, 0},
    // dusk: a deep violet body, dusky leaves, a pale gold evening light
    .stem_col = color.rgb(0.42, 0.3, 0.78), .leaf_col = color.rgb(0.36, 0.5, 0.62), .bloom_col = color.rgb(1.0, 0.86, 0.6),
  },
  .parents = .{.lumenroot, .thornleech},
};
