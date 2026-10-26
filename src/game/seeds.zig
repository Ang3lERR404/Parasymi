//! plant seeds in the HUD. Each sown species has its own module under
//! `seeds/` declaring:
//!   item:Item        the seed it draws                       (required)
//!   icon(ic, col)    the seed (`ic.coat`) and a sprout or two showing
//!                    what it grows into and does (`icon.zig`)
//! A new species with a seed is one new file plus one line in `kinds`
//! (the test fails on a seed without one).
// decision: the icons live here, not in sim/species, since sim may not
// import the HUD's icon kit (layers import only downward)
const lib = @import("../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const engine = lib.engine;
const registry = engine.core.registry;
const items = lib.items;
const species = lib.species;
const Color = engine.ui.draw.Color;
const icon_kit = lib.icon;

const kinds = struct {
  pub const lumenroot = @import("seeds/lumenroot.zig");
  pub const thornleech = @import("seeds/thornleech.zig");
  pub const vesper = @import("seeds/vesper.zig");
  pub const driftwisp = @import("seeds/driftwisp.zig");
  pub const hollowheart = @import("seeds/hollowheart.zig");
  pub const bloom = @import("seeds/bloom.zig");
};
const reg = registry.Registry(kinds);

/// draws `item` as a seed with its sprouts; false when it is no plant's seed.
pub fn icon(item:items.Item, ic:icon_kit.Icon, col:Color) Allocator.Error!bool {
  inline for (reg.ids) |k| if (reg.module(k).item == item) {
    try reg.module(k).icon(ic, col);
    return true;
  };
  return false;
}

fn drawn(item:items.Item) bool {
  inline for (reg.ids) |k| if (reg.module(k).item == item) return true;
  return false;
}

test "every sown species' seed has an icon" {
  for (species.ids) |id| if (species.get(id).seed) |s| try testing.expect(drawn(s));
}
