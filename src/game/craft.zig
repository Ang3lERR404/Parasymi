//! weaving: turning gathered matter into seeds and structure bulbs. The wolf
//! weaves bulbs by hand; a germinator weaves everything, seeds and bulbs,
//! and only it weaves seeds (plants never set seed), so it is the
//! bootstrap: woven from gathered matter alone, it weaves the first
//! essence flowers, and fed by conduits it is what automates the garden. Ingredients
//! leave the inventory when a weave is queued (like Factorio hand crafting)
//! and the result appears when it finishes.
const std = @import("std");
const copyForwards = std.mem.copyForwards;
const testing = std.testing;
const items = @import("../sim/items.zig");
const prog = @import("progression.zig");

pub const Recipe = struct {
  out:items.Item,
  n:u16 = 1,
  in:[]const items.Ingredient,
  time:f32,
  /// research that must be known before this can be woven
  needs:?prog.Id = null,
  /// only a germinator weaves it (seeds always are; so are the convergent
  /// structures, the hands cannot bind two lineages into one)
  germinator:bool = false,
  /// the advanced tier: only a heartloom weaves it, never a germinator or
  /// the hands
  advanced:bool = false,

  pub fn unlocked(r:Recipe, g:*const prog.Progression) bool {
    return if (r.needs) |id| g.done.contains(id) else true;
  }
};

/// everything that can be woven, seeds among them (only a germinator weaves those;
/// it weaves the rest too).
pub const hand = [_]Recipe{
  .{ .out = .seed_lumenroot, .in = &.{ .{ .item = .fibre, .n = 2 }, .{ .item = .starlight, .n = 1 } }, .time = 1.5 },
  .{ .out = .seed_thornleech, .in = &.{ .{ .item = .grit, .n = 2 }, .{ .item = .ley_shard, .n = 1 }, .{ .item = .starlight, .n = 1 } }, .time = 1.5 },
  .{ .out = .seed_driftwisp, .in = &.{ .{ .item = .starlight, .n = 1 }, .{ .item = .ley_shard, .n = 1 }, .{ .item = .fibre, .n = 1 } }, .time = 2, .needs = .drift_spores },
  // decision: ungated, from starlight, ley and essence (the brief sets no cost)
  .{ .out = .seed_bloom, .in = &.{ .{ .item = .starlight, .n = 3 }, .{ .item = .ley_shard, .n = 1 }, .{ .item = .essence, .n = 2 } }, .time = 3 },
  .{ .out = .seed_hollowheart, .in = &.{ .{ .item = .essence, .n = 4 }, .{ .item = .fibre, .n = 3 }, .{ .item = .grit, .n = 2 } }, .time = 3, .needs = .canopy_weaving },
  // decision: the hybrid is spliced from both lineages' essence and what their meeting condenses
  .{ .out = .seed_vesper, .in = &.{ .{ .item = .essence, .n = 2 }, .{ .item = .convergence_essence, .n = 1 }, .{ .item = .fibre, .n = 1 } }, .time = 2.5, .needs = .seed_splicing },
  .{ .out = .conduit, .n = 2, .in = &.{ .{ .item = .fibre, .n = 2 }, .{ .item = .grit, .n = 1 } }, .time = 1 },
  .{ .out = .sap_cache, .in = &.{ .{ .item = .fibre, .n = 4 }, .{ .item = .grit, .n = 4 } }, .time = 2 },
  // no essence: nothing yields it until the germinator has woven a seed
  .{ .out = .germinator, .in = &.{ .{ .item = .fibre, .n = 6 }, .{ .item = .grit, .n = 4 }, .{ .item = .starlight, .n = 2 } }, .time = 3 },
  .{ .out = .arsthraxia, .in = &.{ .{ .item = .fibre, .n = 8 }, .{ .item = .grit, .n = 6 }, .{ .item = .essence, .n = 4 }, .{ .item = .starlight, .n = 4 }, .{ .item = .ley_shard, .n = 2 } }, .time = 4 },
  .{ .out = .root_digger, .in = &.{ .{ .item = .fibre, .n = 3 }, .{ .item = .grit, .n = 2 }, .{ .item = .ley_shard, .n = 1 } }, .time = 2, .needs = .deep_rooting },
  // decision: ungated, from what a bloom is grown from plus fibre (the brief sets no cost)
  .{ .out = .polyp, .in = &.{ .{ .item = .fibre, .n = 4 }, .{ .item = .essence, .n = 3 }, .{ .item = .starlight, .n = 2 }, .{ .item = .ley_shard, .n = 2 } }, .time = 3 },
  // decision: a diamond is woven from what a halo is grown from, condensed
  // (the brief sets no cost); the advanced tier's, from ley crystals
  .{ .out = .diamond, .in = &.{ .{ .item = .starlight, .n = 6 }, .{ .item = .ley_crystal, .n = 3 }, .{ .item = .convergence_essence, .n = 3 }, .{ .item = .fibre, .n = 2 } }, .time = 6, .needs = .celestial_defragmentation, .advanced = true },
  // decision: costs for the lineages' structures are set here (the brief sets none)
  .{ .out = .loomfern, .in = &.{ .{ .item = .fibre, .n = 5 }, .{ .item = .essence, .n = 2 }, .{ .item = .grit, .n = 2 } }, .time = 2.5, .needs = .living_looms },
  .{ .out = .lithophage, .in = &.{ .{ .item = .grit, .n = 6 }, .{ .item = .ley_shard, .n = 2 }, .{ .item = .essence, .n = 2 }, .{ .item = .fibre, .n = 2 } }, .time = 3, .needs = .lithophagy },
  // woven from conduits: four grown into one
  .{ .out = .braided_conduit, .in = &.{ .{ .item = .conduit, .n = 4 }, .{ .item = .fibre, .n = 2 }, .{ .item = .essence, .n = 1 } }, .time = 2, .needs = .braided_roots },
  .{ .out = .ganglion, .in = &.{ .{ .item = .fibre, .n = 3 }, .{ .item = .essence, .n = 3 }, .{ .item = .grit, .n = 2 }, .{ .item = .ley_shard, .n = 1 } }, .time = 2.5, .needs = .lithophagy },
  .{ .out = .gathering_crown, .in = &.{ .{ .item = .fibre, .n = 4 }, .{ .item = .essence, .n = 3 }, .{ .item = .starlight, .n = 2 }, .{ .item = .grit, .n = 1 } }, .time = 2.5, .needs = .living_looms },
  .{ .out = .sporecaster, .in = &.{ .{ .item = .fibre, .n = 3 }, .{ .item = .essence, .n = 3 }, .{ .item = .starlight, .n = 2 }, .{ .item = .ley_shard, .n = 1 } }, .time = 3, .needs = .spore_casting },
  // decision: the convergent structures are woven from the pair they grow
  // out of, bound by what the lineages' meeting condenses (the brief sets
  // no cost); last, so the weaves chosen in saved gardens keep their places
  .{ .out = .weftstone, .in = &.{ .{ .item = .loomfern, .n = 1 }, .{ .item = .lithophage, .n = 1 }, .{ .item = .convergence_essence, .n = 2 }, .{ .item = .starlight, .n = 2 } }, .time = 4, .needs = .woven_stone, .germinator = true },
  .{ .out = .driftbraid, .in = &.{ .{ .item = .braided_conduit, .n = 1 }, .{ .item = .sporecaster, .n = 1 }, .{ .item = .convergence_essence, .n = 2 }, .{ .item = .essence, .n = 2 } }, .time = 4, .needs = .braided_drift, .germinator = true },
  // decision: the heartloom from the two convergent structures it grows
  // out of, the Vultrixi from the pair it does, both bound by convergence
  // essence and ley crystals (the brief sets no cost)
  .{ .out = .heartloom, .in = &.{ .{ .item = .weftstone, .n = 1 }, .{ .item = .driftbraid, .n = 1 }, .{ .item = .convergence_essence, .n = 4 }, .{ .item = .ley_crystal, .n = 2 } }, .time = 6, .needs = .interweaving, .germinator = true },
  .{ .out = .vultrixi, .in = &.{ .{ .item = .gathering_crown, .n = 1 }, .{ .item = .ganglion, .n = 1 }, .{ .item = .convergence_essence, .n = 2 }, .{ .item = .ley_crystal, .n = 1 } }, .time = 4, .needs = .shared_nerves, .germinator = true },
};

pub fn isSeedRecipe(idx:usize) bool { return hand[idx].out.plants() != null; }
/// whether the hands cannot weave it: a seed, one marked for a germinator,
/// or the advanced tier
pub fn germinatorOnly(idx:usize) bool { return isSeedRecipe(idx) or hand[idx].germinator or hand[idx].advanced; }
pub fn isAdvanced(idx:usize) bool { return hand[idx].advanced; }

/// the recipes the wolf weaves by hand (indices into `hand`): all but what
/// only a germinator weaves.
pub const by_hand = recipesWhere(germinatorOnly, false);
/// the seed weaves (indices into `hand`).
pub const seeds = recipesWhere(isSeedRecipe, true);
/// every weave but the advanced tier: what a germinator may be set to
/// (indices into `hand`).
pub const all = recipesWhere(isAdvanced, false);
/// the advanced tier: what a heartloom may be set to (indices into `hand`).
pub const advanced = recipesWhere(isAdvanced, true);

/// whether some weave makes `item` (what a germinator lets go of).
pub fn woven(item:items.Item) bool {
  for (hand) |r| if (r.out == item) return true;
  return false;
}

fn countWhere(comptime pred:fn (usize) bool, comptime want:bool) usize {
  @setEvalBranchQuota(10_000);
  var n:usize = 0;
  for (0..hand.len) |i| if (pred(i) == want) { n += 1; };
  return n;
}

fn recipesWhere(comptime pred:fn (usize) bool, comptime want:bool) [countWhere(pred, want)]u8 {
  @setEvalBranchQuota(10_000);
  var out:[countWhere(pred, want)]u8 = undefined;
  var k:usize = 0;
  for (0..hand.len) |i| if (pred(i) == want) { out[k] = i; k += 1; };
  return out;
}

/// max weaves queued at once (the wolf's hands can only do so much)
const QUEUE_MAX = 8;

pub const Crafter = struct {
  queue:[QUEUE_MAX]u8 = undefined,
  len:usize = 0,
  t:f32 = 0,

  pub fn can(inv:items.Bag, r:Recipe) bool {
    for (r.in) |ing| if (inv.count(ing.item) < ing.n) return false;
    return true;
  }

  /// takes the ingredients now; false if missing or the queue is full.
  pub fn push(c:*Crafter, inv:items.Bag, idx:usize) bool {
    const r = hand[idx];
    if (c.len == QUEUE_MAX or !can(inv, r)) return false;
    for (r.in) |ing| _ = inv.take(ing.item, ing.n);
    c.queue[c.len] = @intCast(idx);
    c.len += 1;
    return true;
  }

  pub fn busy(c:*const Crafter) bool { return c.len > 0; }
  pub fn progress(c:*const Crafter) f32 { return if (c.len == 0) 0 else c.t / hand[c.queue[0]].time; }

  /// returns the item finished this step, if any. A result that does not fit
  /// waits in the weave until there is room.
  pub fn tick(c:*Crafter, inv:items.Bag, dt:f32) ?items.Item {
    if (c.len == 0) return null;
    const r = hand[c.queue[0]];
    c.t = @min(c.t + dt, r.time);
    if (c.t < r.time) return null;
    if (inv.add(r.out, r.n) < r.n) return null;
    copyForwards(u8, c.queue[0 .. c.len - 1], c.queue[1..c.len]);
    c.len -= 1;
    c.t = 0;
    return r.out;
  }
};

test "weaving takes ingredients up front and yields after its time" {
  var inv:items.Inventory(8) = .{};
  var c:Crafter = .{};
  try testing.expect(!c.push(inv.bag(), 0));
  _ = inv.add(.fibre, 4);
  _ = inv.add(.starlight, 1);
  try testing.expect(c.push(inv.bag(), 0));
  try testing.expect(!c.push(inv.bag(), 0)); // only one starlight
  try testing.expectEqual(@as(u32, 2), inv.count(.fibre));
  try testing.expect(c.tick(inv.bag(), 1.0) == null);
  try testing.expect(c.tick(inv.bag(), 1.0) == .seed_lumenroot);
  try testing.expectEqual(@as(u32, 1), inv.count(.seed_lumenroot));
  try testing.expect(!c.busy());
}