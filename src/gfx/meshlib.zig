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
  // drawn first: a flat soft patch on the ground under floaters
  pub const shadow = @import("meshes/shadow.zig");
  // the vine-wolf
  pub const wolf_torso = @import("meshes/wolf_torso.zig");
  // drawn before the belly so the translucent sac blends over them
  pub const belly_lump = @import("meshes/belly_lump.zig");
  pub const wolf_belly = @import("meshes/wolf_belly.zig");
  pub const wolf_pec_l = @import("meshes/wolf_pec_l.zig");
  pub const wolf_pec_r = @import("meshes/wolf_pec_r.zig");
  pub const wolf_head = @import("meshes/wolf_head.zig");
  pub const wolf_ear = @import("meshes/wolf_ear.zig");
  pub const wolf_limb = @import("meshes/wolf_limb.zig");
  pub const wolf_upper_arm = @import("meshes/wolf_upper_arm.zig");
  pub const wolf_forearm = @import("meshes/wolf_forearm.zig");
  pub const wolf_deltoid = @import("meshes/wolf_deltoid.zig");
  pub const wolf_thigh = @import("meshes/wolf_thigh.zig");
  pub const wolf_calf = @import("meshes/wolf_calf.zig");
  pub const wolf_rump_l = @import("meshes/wolf_rump_l.zig");
  pub const wolf_rump_r = @import("meshes/wolf_rump_r.zig");
  pub const wolf_tailbone = @import("meshes/wolf_tailbone.zig");
  pub const wolf_joint = @import("meshes/wolf_joint.zig");
  pub const wolf_paw = @import("meshes/wolf_paw.zig");
  pub const wolf_foot = @import("meshes/wolf_foot.zig");
  // after the foot, so the translucent pads blend over its sole
  pub const paw_pad = @import("meshes/paw_pad.zig");
  pub const paw_bean = @import("meshes/paw_bean.zig");
  pub const leaf_tuft = @import("meshes/leaf_tuft.zig");
  // the world
  pub const node_grit = @import("meshes/node_grit.zig");
  pub const node_fibre = @import("meshes/node_fibre.zig");
  pub const node_ley = @import("meshes/node_ley.zig");
  pub const mote = @import("meshes/mote.zig");
  // structures
  pub const conduit = @import("meshes/conduit.zig");
  pub const conduit_tap = @import("meshes/conduit_tap.zig");
  pub const sap_cache = @import("meshes/sap_cache.zig");
  pub const germinator = @import("meshes/germinator.zig");
  pub const research_bloom = @import("meshes/research_bloom.zig");
  pub const research_orb = @import("meshes/research_orb.zig");
  pub const item_pod = @import("meshes/item_pod.zig");
  pub const root_digger = @import("meshes/root_digger.zig");
  pub const digger_root = @import("meshes/digger_root.zig");
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
