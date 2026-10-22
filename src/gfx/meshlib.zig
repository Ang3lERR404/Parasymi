//! catalogue of rigid procedural part meshes, one module each under
//! `meshes/` exposing `build(b)`. Each is built once at startup in its own
//! local space; anything "made of parts" (the player, resource nodes, motes,
//! structures) draws instances of these with a per-instance transform, so
//! procedural animation is just transform math.
//!
//! A new mesh is one new file plus one line in `parts`.
const std = @import("std");
const Allocator = std.mem.Allocator;
const mg = @import("meshgen.zig");
const registry = @import("../core/registry.zig");

const parts = struct {
  // the vine-wolf
  pub const wolf_torso = @import("meshes/wolf_torso.zig");
  pub const wolf_belly = @import("meshes/wolf_belly.zig");
  pub const wolf_head = @import("meshes/wolf_head.zig");
  pub const wolf_limb = @import("meshes/wolf_limb.zig");
  pub const wolf_joint = @import("meshes/wolf_joint.zig");
  pub const wolf_paw = @import("meshes/wolf_paw.zig");
  pub const leaf_tuft = @import("meshes/leaf_tuft.zig");
  // the world
  pub const node_grit = @import("meshes/node_grit.zig");
  pub const node_fibre = @import("meshes/node_fibre.zig");
  pub const node_ley = @import("meshes/node_ley.zig");
  pub const mote = @import("meshes/mote.zig");
  // structures
  pub const conduit = @import("meshes/conduit.zig");
  pub const sap_cache = @import("meshes/sap_cache.zig");
  pub const germinator = @import("meshes/germinator.zig");
  pub const research_bloom = @import("meshes/research_bloom.zig");
  pub const research_orb = @import("meshes/research_orb.zig");
  pub const item_pod = @import("meshes/item_pod.zig");
};
const reg = registry.Registry(parts);

pub const Id = reg.Id;
pub const count = reg.count;

/// build every mesh into `b`, recording each one's (first vertex, count).
pub fn build(b:*mg.Builder, ranges:*[count][2]u32) Allocator.Error!void {
  inline for (reg.ids) |id| {
    const first = b.mark();
    try reg.module(id).build(b);
    ranges[@intFromEnum(id)] = .{@intCast(first), @intCast(b.mark() - first)};
  }
}
