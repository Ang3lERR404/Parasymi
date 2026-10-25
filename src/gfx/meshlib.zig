//! catalogue of rigid procedural part meshes, one module (or a companion
//! struct inside its owner's module) each under
//! `meshes/` exposing `build(b)`. Each is built once at startup in its own
//! local space; anything "made of parts" (the player, resource nodes, motes,
//! structures) draws instances of these with a per-instance transform, so
//! procedural animation is just transform math.
//!
//! A new mesh is one new file (or struct) plus one line in `parts`.
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const mg = @import("meshgen.zig");
const registry = @import("../core/registry.zig");

const parts = struct {
  // drawn first: a flat soft patch on the ground under floaters
  pub const shadow = @import("meshes/shadow.zig");
  // the vine-wolf: one skinned body, then what is see-through over it
  pub const wolf_body = @import("meshes/wolf_body.zig");
  pub const wolf_ears = @import("meshes/wolf_ears.zig");
  // drawn before the belly so the translucent sac blends over them
  pub const belly_lump = @import("meshes/belly_lump.zig");
  pub const wolf_belly = @import("meshes/wolf_belly.zig");
  pub const wolf_pec_l = @import("meshes/wolf_pec.zig").left;
  pub const wolf_pec_r = @import("meshes/wolf_pec.zig").right;
  pub const wolf_rump_l = @import("meshes/wolf_rump.zig").left;
  pub const wolf_rump_r = @import("meshes/wolf_rump.zig").right;
  pub const paw_pad = @import("meshes/paw_pad.zig");
  pub const paw_bean = @import("meshes/paw_pad.zig").bean;
  // the world
  pub const node_grit = @import("meshes/node_grit.zig");
  pub const node_fibre = @import("meshes/node_fibre.zig");
  pub const node_ley = @import("meshes/node_ley.zig");
  pub const mote = @import("meshes/mote.zig");
  // structures
  pub const conduit = @import("meshes/conduit.zig");
  pub const conduit_left = @import("meshes/conduit.zig").left;
  pub const conduit_right = @import("meshes/conduit.zig").right;
  pub const conduit_tap = @import("meshes/conduit.zig").tap;
  pub const braided_conduit = @import("meshes/braided_conduit.zig");
  pub const braid_wrap = @import("meshes/braided_conduit.zig").wrap;
  pub const braid_wrap_left = @import("meshes/braided_conduit.zig").wrap_left;
  pub const braid_wrap_right = @import("meshes/braided_conduit.zig").wrap_right;
  pub const braid_lane0 = @import("meshes/braided_conduit.zig").Lane(0, 0);
  pub const braid_lane1 = @import("meshes/braided_conduit.zig").Lane(0, 1);
  pub const braid_lane2 = @import("meshes/braided_conduit.zig").Lane(0, 2);
  pub const braid_lane3 = @import("meshes/braided_conduit.zig").Lane(0, 3);
  pub const braid_lane0_left = @import("meshes/braided_conduit.zig").Lane(1, 0);
  pub const braid_lane1_left = @import("meshes/braided_conduit.zig").Lane(1, 1);
  pub const braid_lane2_left = @import("meshes/braided_conduit.zig").Lane(1, 2);
  pub const braid_lane3_left = @import("meshes/braided_conduit.zig").Lane(1, 3);
  pub const braid_lane0_right = @import("meshes/braided_conduit.zig").Lane(-1, 0);
  pub const braid_lane1_right = @import("meshes/braided_conduit.zig").Lane(-1, 1);
  pub const braid_lane2_right = @import("meshes/braided_conduit.zig").Lane(-1, 2);
  pub const braid_lane3_right = @import("meshes/braided_conduit.zig").Lane(-1, 3);
  pub const sap_cache_lid = @import("meshes/sap_cache.zig").lid;
  pub const sap_cache = @import("meshes/sap_cache.zig");
  pub const germinator = @import("meshes/germinator.zig");
  pub const germinator_whole = @import("meshes/germinator.zig").whole;
  pub const germinator_cup = @import("meshes/germinator.zig").cup;
  pub const germinator_pool = @import("meshes/germinator.zig").pool;
  pub const germinator_pour = @import("meshes/germinator.zig").pour;
  pub const germinator_vortex = @import("meshes/germinator.zig").vortex;
  pub const germinator_thread = @import("meshes/germinator.zig").thread;
  pub const germinator_seed = @import("meshes/germinator.zig").seed;
  pub const germinator_winding = @import("meshes/germinator.zig").winding;
  // (see-through: blends over what spins inside it)
  pub const germinator_core = @import("meshes/germinator.zig").core;
  pub const arsthraxia = @import("meshes/arsthraxia.zig");
  pub const arsthraxia_whole = @import("meshes/arsthraxia.zig").whole;
  pub const arsthraxia_whorl = @import("meshes/arsthraxia.zig").whorl;
  pub const arsthraxia_cup = @import("meshes/arsthraxia.zig").cup;
  pub const arsthraxia_vines = @import("meshes/arsthraxia.zig").vines;
  pub const arsthraxia_shoot = @import("meshes/arsthraxia.zig").shoot;
  pub const arsthraxia_satellite = @import("meshes/arsthraxia.zig").satellite;
  // (light: blends over the satellites spinning round it)
  pub const arsthraxia_core = @import("meshes/arsthraxia.zig").core;
  pub const arsthraxia_wisp = @import("meshes/arsthraxia.zig").wisp;
  pub const item_pod = @import("meshes/item_pod.zig");
  pub const root_digger = @import("meshes/root_digger.zig");
  pub const digger_root = @import("meshes/root_digger.zig").root;
  pub const digger_clod = @import("meshes/root_digger.zig").clod;
  pub const loomfern = @import("meshes/loomfern.zig");
  pub const loomfern_sheaf = @import("meshes/loomfern.zig").sheaf;
  pub const loomfern_thread = @import("meshes/loomfern.zig").thread;
  pub const crown_root1 = @import("meshes/gathering_crown.zig").Root(0);
  pub const crown_root2 = @import("meshes/gathering_crown.zig").Root(1);
  pub const crown_root3 = @import("meshes/gathering_crown.zig").Root(2);
  pub const crown_root4 = @import("meshes/gathering_crown.zig").Root(3);
  pub const crown_root5 = @import("meshes/gathering_crown.zig").Root(4);
  pub const gathering_crown = @import("meshes/gathering_crown.zig");
  pub const lithophage = @import("meshes/lithophage.zig");
  pub const lithophage_crystal = @import("meshes/lithophage.zig").crystal;
  pub const lithophage_root = @import("meshes/lithophage.zig").root;
  pub const lithophage_root_far = @import("meshes/lithophage.zig").root_far;
  pub const ganglion_nerve = @import("meshes/ganglion.zig").nerve;
  // (see-through: blends over what hangs inside it)
  pub const ganglion = @import("meshes/ganglion.zig");
  // (see-through: blends over what hangs inside it)
  pub const sporecaster = @import("meshes/sporecaster.zig");
  pub const spore_carrier = @import("meshes/sporecaster.zig").carrier;
  // the convergent structures (see-through: blend over what hangs inside)
  pub const weftstone_tendril = @import("meshes/weftstone.zig").tendril;
  pub const monfris_tether = @import("meshes/monfris.zig").tether;
  pub const driftbraid = @import("meshes/driftbraid.zig");
  pub const monfris = @import("meshes/monfris.zig");
  pub const vultrixi = @import("meshes/vultrixi.zig");
  pub const weftstone = @import("meshes/weftstone.zig");
  // the halo: its polyp and the diamond it forms
  pub const polyp = @import("meshes/polyp.zig");
  pub const halo_diamond = @import("meshes/halo.zig").diamond;
  // translucent, over everything
  pub const halo_projection = @import("meshes/halo.zig").projection;
  pub const halo_ring = @import("meshes/halo.zig").ring;
  pub const halo_flash = @import("meshes/halo.zig").flash;
  pub const bloom_thread = @import("meshes/bloom_thread.zig");
};
const reg = registry.Registry(parts);

pub const Id = reg.Id;
pub const count = reg.count;

/// every library mesh at each level of detail (one slot per mesh and level,
/// see `slot`).
pub const SLOTS = count * mg.LODS;

/// where a mesh at a level of detail sits in per-slot tables.
pub fn slot(id:Id, lod:u32) usize { return @as(usize, @intFromEnum(id)) * mg.LODS + lod; }

/// build one mesh at one level of detail into `b` (leaving `b.lod` there),
/// recording its (first vertex, count).
pub fn buildOne(b:*mg.Builder, id:Id, lod:u32, ranges:*[SLOTS][2]u32) Allocator.Error!void {
  b.lod = lod;
  const first = b.mark();
  switch (id) {
    inline else => |k| try reg.module(k).build(b),
  }
  // a skeleton left unfinished leaves its times past one (never grown)
  if (b.grow.items.len > first) for (b.grow.items[first..]) |g| assert(g.at[0] + g.at[1] <= 1 + 1e-4);
  ranges[slot(id, lod)] = .{@intCast(first), @intCast(b.mark() - first)};
}
