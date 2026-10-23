//! what each kind of ground offers: the item gathered from its resource
//! nodes and how those nodes look. One table, keyed by tile kind.
const std = @import("std");
const EnumArray = std.enums.EnumArray;
const ck = @import("../world/chunk.zig");
const items = @import("../sim/items.zig");
const meshlib = @import("../gfx/meshlib.zig");

pub const Node = struct {
  item:items.Item,
  mesh:meshlib.Id,
  /// emission intensity for the node mesh (0 = none, 1 = full glow)
  glow:f32 = 0,
};

pub const nodes = EnumArray(ck.Kind, ?Node).init(.{
  .water = null,
  .soil = .{ .item = .grit, .mesh = .node_grit },
  .stone = .{ .item = .grit, .mesh = .node_grit },
  .moss = .{ .item = .fibre, .mesh = .node_fibre },
  .ley = .{ .item = .ley_shard, .mesh = .node_ley, .glow = 0.7 },
});

pub fn of(k:ck.Kind) ?Node { return nodes.get(k); }