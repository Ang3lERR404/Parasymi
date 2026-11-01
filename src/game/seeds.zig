//! plant seeds in the HUD. Each sown species has its own module under
//! `seeds/` declaring:
//!   item:Item        the seed it draws                       (required)
//!   icon(ic, col)    the seed (`ic.coat`) and a sprout or two showing
//!                    what it grows into and does (`icon.zig`)
//! A new species with a seed is one new file plus one line in `kinds`
//! (the test fails on a seed without one).
// decision: the icons live here, not in sim/species, since sim may not
// import the HUD's icon kit (layers import only downward)
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// the test helpers, for the check that every seed is drawn
const testing=std.testing;
/// the engine package: core, gfx, ui
const engine=lib.engine;
/// the engine's registry builder, which turns `kinds` into ids and dispatch
const registry=engine.core.registry;
/// what can be held: item kinds, seeds among them
const items=lib.items;
/// every plant kind, to find which ones are sown from a seed
const species=lib.species;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=engine.ui.draw.Color;
/// the tools a seed icon is drawn with
const iconKit=lib.icon;
/// every seed that has its own picture: one module per sown species
const kinds=struct{
  /// the luminous sharer's seed
  pub const lumenroot=@import("seeds/lumenroot.zig");
  /// the pale drainer's seed
  pub const thornleech=@import("seeds/thornleech.zig");
  /// the evening star's seed
  pub const vesper=@import("seeds/vesper.zig");
  /// the floating lantern's spore
  pub const driftwisp=@import("seeds/driftwisp.zig");
  /// the deep reservoir's seed
  pub const hollowheart=@import("seeds/hollowheart.zig");
  /// the celestial bloom's seed
  pub const bloom=@import("seeds/bloom.zig");
  /// the mire lily's seed
  pub const mireLily=@import("seeds/mire_lily.zig");
};
/// the seed registry built from `kinds`: its ids and its modules
const reg=registry.Registry(kinds);
/// draws `item` as a seed with its sprouts; false when it is no plant's seed.
pub fn icon(item:items.Item,ic:iconKit.Icon,col:Color)Allocator.Error!bool{
  inline for(reg.ids)|k|if(reg.module(k).item==item){
    try reg.module(k).icon(ic,col);
    return true;
  };
  return false;
}
/// whether some module in `kinds` draws `item`; true when it has a picture.
fn drawn(item:items.Item)bool{
  inline for(reg.ids)|k|if(reg.module(k).item==item)return true;
  // the seed's module, when it is this item
  return false;
}
test"every sown species' seed has an icon"{
  for(species.ids)|id|if(species.get(id).seed)|s|try testing.expect(drawn(s));
}
