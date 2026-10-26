//! what each kind of ground offers: the item gathered from its resource
//! nodes and how those nodes look. One table, keyed by tile kind.
const lib = @import("../lib.zig");
const std = lib.std;
const EnumArray = std.enums.EnumArray;
const ck = lib.ck;
const items = lib.items;
const meshlib = lib.meshlib;

pub const Node = struct {
  item:items.Item,
  mesh:meshlib.Id,
  /// emission intensity for the node mesh (0 = none, 1 = full glow)
  glow:f32 = 0,
  /// how far it bends in the garden's wind (a plant-like node), over what height
  sway:f32 = 0,
  tall:f32 = 0.5,
};

pub const nodes = EnumArray(ck.Kind, ?Node).init(.{
  .soil = .{ .item = .grit, .mesh = .node_grit },
  .stone = .{ .item = .grit, .mesh = .node_grit },
  .moss = .{ .item = .fibre, .mesh = .node_fibre, .sway = 1, .tall = 0.45 },
  .ley = .{ .item = .ley_shard, .mesh = .node_ley, .glow = 0.7 },
});

pub fn of(k:ck.Kind) ?Node { return nodes.get(k); }