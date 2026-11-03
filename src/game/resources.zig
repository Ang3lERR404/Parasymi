//! what each kind of ground offers: the item gathered from its resource
//! nodes and how those nodes look. One table, keyed by tile kind.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// a table with one slot per tile kind
const EnumArray=std.enums.EnumArray;
/// the chunk grid: the tile kinds a node sits on
const ck=lib.ck;
/// what can be held: the item a node gives
const items=lib.items;
/// the library meshes a node is drawn with
const meshlib=lib.meshlib;
/// what one kind of ground offers: the item dug from its nodes and how
/// those nodes look and move
pub const Node=struct{
  /// the item a node gives when worked
  item:items.Item,
  /// the library mesh it is drawn as
  mesh:meshlib.Id,
  /// emission intensity for the node mesh (0 = none, 1 = full glow)
  glow:f32=0,
  /// how far it bends in the garden's wind (a plant-like node; 0: stands still)
  sway:f32=0,
  /// the height the wind bends it over, in tiles
  tall:f32=0.5,
};
/// every tile kind's node, or null where the ground offers none: soil and
/// stone give grit, moss gives fibre, the ley gives glowing shards
pub const nodes=EnumArray(ck.Kind,?Node).init(.{
  .soil=.{.item=.grit,.mesh=.nodeGrit},
  .stone=.{.item=.grit,.mesh=.nodeGrit},
  .moss=.{.item=.fibre,.mesh=.nodeFibre,.sway=1,.tall=0.5},
  .ley=.{.item=.leyShard,.mesh=.nodeLey,.glow=0.7},
});
/// the node a tile kind offers, if any
pub fn of(k:ck.Kind)?Node{return nodes.get(k);}
