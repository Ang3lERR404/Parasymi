//! research tree, discoveries and world events.
//!
//! research works like Factorio labs: a technology is chosen, then a research
//! structure in the world consumes its per-unit ingredients from its own
//! inventory, one unit at a time, until enough units are done. Nothing is
//! paid from a pool. Entries reference each other (prerequisites),
//! discoveries and items, and what they unlock is expressed as ecology mods
//! or planting rights.
const std = @import("std");
const species = @import("../sim/species.zig");
const ecology = @import("../sim/ecology.zig");
const items = @import("../sim/items.zig");

pub const Discovery = enum { convergence };

pub const Id = enum { ley_sight, drift_spores, root_communion, canopy_weaving, hungering_tendrils, seed_splicing, thinning_veil };


pub const Research = struct {
  name:[]const u8,
  desc:[]const u8,
  /// ingredients consumed per unit, units needed, seconds per unit.
  per_unit:[]const items.Ingredient,
  units:u32,
  unit_time:f32,
  prereq:[]const Id = &.{},
  needs:?Discovery = null,
};

pub const tree = std.enums.EnumArray(Id, Research).init(.{
  .ley_sight = .{
    .name = "LEY SIGHT", .desc = "SEE THE LEY CURRENTS",
    .per_unit = &.{.{.item = .starlight, .n = 1}}, .units = 10, .unit_time = 3,
  },
  .drift_spores = .{
    .name = "DRIFT SPORES", .desc = "WEAVE DRIFTWISPS: FLOATERS THAT CONDENSE STARLIGHT",
    .per_unit = &.{.{.item = .starlight, .n = 2}, .{.item = .essence, .n = 1}}, .units = 15, .unit_time = 4,
    .prereq = &.{.ley_sight},
  },
  .canopy_weaving = .{
    .name = "CANOPY WEAVING", .desc = "WEAVE HOLLOWHEARTS: 2X2 MANA RESERVOIR TREES",
    .per_unit = &.{.{.item = .essence, .n = 3}, .{.item = .fibre, .n = 2}, .{.item = .grit, .n = 1}}, .units = 25, .unit_time = 6,
    .prereq = &.{.root_communion},
  },
  .root_communion = .{
    .name = "ROOT COMMUNION", .desc = "SYMBIOTIC LINKS REACH 2 TILES",
    .per_unit = &.{.{.item = .essence, .n = 2}, .{.item = .fibre, .n = 1}}, .units = 20, .unit_time = 5,
  },
  .hungering_tendrils = .{
    .name = "HUNGERING TENDRILS", .desc = "PARASITES DRAIN X2",
    .per_unit = &.{.{.item = .essence, .n = 2}, .{.item = .grit, .n = 1}}, .units = 20, .unit_time = 5,
  },
  .seed_splicing = .{
    .name = "SEED SPLICING", .desc = "HARVEST VESPER SEEDS WHERE LINEAGES TOUCH",
    .per_unit = &.{.{.item = .essence, .n = 3}, .{.item = .starlight, .n = 1}, .{.item = .ley_shard, .n = 1}},
    .units = 30, .unit_time = 8,
    .prereq = &.{.root_communion, .hungering_tendrils}, .needs = .convergence,
  },
  .thinning_veil = .{
    .name = "THE THINNING VEIL", .desc = "HYBRIDS YIELD X3. SOMETHING STIRS",
    .per_unit = &.{.{.item = .essence, .n = 5}, .{.item = .starlight, .n = 2}, .{.item = .ley_shard, .n = 2}},
    .units = 50, .unit_time = 12,
    .prereq = &.{.seed_splicing},
  },
});

/// working state of one research structure.
pub const Lab = struct {
  /// a unit's ingredients have been consumed and are being worked.
  busy:bool = false,
  t:f32 = 0,
  speed:f32 = 1,
};

pub const Message = struct { buf:[96]u8 = undefined, len:usize = 0, age:f32 = 0 };

pub const Progression = struct {
  done:std.EnumSet(Id) = .initEmpty(),
  found:std.EnumSet(Discovery) = .initEmpty(),
  /// world event blend 0..1 (sky/glow shift after the veil thins).
  veil:f32 = 0,
  log:[6]Message = @splat(.{}),
  /// the technology every lab works on, and units finished per technology.
  current:?Id = null,
  progress:std.EnumArray(Id, u32) = .initFill(0),
  /// withered plants are reported in batches, not every tick.
  died:u32 = 0,
  died_t:f32 = 0,

  pub fn say(g:*Progression, comptime fmt:[]const u8, args:anytype) void {
    std.mem.copyBackwards(Message, g.log[1..], g.log[0 .. g.log.len - 1]);
    const m = &g.log[0];
    m.* = .{};
    m.len = if (std.fmt.bufPrint(&m.buf, fmt, args)) |s| s.len else |_| m.buf.len;
  }

  pub fn status(g:*const Progression, id:Id) enum { done, open, locked } {
    if (g.done.contains(id)) return .done;
    const r = tree.get(id);
    for (r.prereq) |p| if (!g.done.contains(p)) return .locked;
    if (r.needs) |d| if (!g.found.contains(d)) return .locked;
    return .open;
  }

  pub fn select(g:*Progression, id:Id) void {
    const r = tree.get(id);
    switch (g.status(id)) {
      .open => { g.current = id; g.say("RESEARCHING {s}", .{r.name}); },
      .done => g.say("{s} IS ALREADY KNOWN", .{r.name}),
      .locked => g.say("{s} IS LOCKED", .{r.name}),
    }
  }

  /// advance one research structure. `inv` is the structure's own inventory
  /// (anything with count/take, see sim/items.zig).
  pub fn labTick(g:*Progression, lab:*Lab, inv:anytype, dt:f32) void {
    const id = g.current orelse return;
    const r = tree.get(id);
    if (!lab.busy) {
      for (r.per_unit) |ing| if (inv.count(ing.item) < ing.n) return;
      for (r.per_unit) |ing| _ = inv.take(ing.item, ing.n);
      lab.busy = true;
      lab.t = 0;
    }
    lab.t += dt * lab.speed;
    if (lab.t < r.unit_time) return;
    lab.busy = false;
    // another lab may have finished it while this unit was in progress
    if (g.done.contains(id)) return;
    const p = g.progress.getPtr(id);
    p.* += 1;
    if (p.* >= r.units) g.complete(id);
  }

  fn complete(g:*Progression, id:Id) void {
    g.done.insert(id);
    if (g.current == id) g.current = null;
    g.say("RESEARCHED {s}", .{tree.get(id).name});
    if (id == .thinning_veil) g.say("THE VEIL THINS. THE GARDEN DREAMS OF MORE", .{});
  }

  pub fn canPlant(g:*const Progression, sp:species.Id) bool {
    return switch (sp) {
      .lumenroot, .thornleech => true,
      .vesper => g.done.contains(.seed_splicing),
      .driftwisp => g.done.contains(.drift_spores),
      .hollowheart => g.done.contains(.canopy_weaving),
    };
  }

  pub fn mods(g:*const Progression) ecology.Mods {
    var m:ecology.Mods = .{};
    m.link2 = g.done.contains(.root_communion);
    if (g.done.contains(.hungering_tendrils)) m.drain_mult = 2;
    if (g.done.contains(.thinning_veil)) m.yield_mult[@intFromEnum(species.Id.vesper)] = 3;
    return m;
  }

  pub fn absorb(g:*Progression, ev:ecology.Events, dt:f32) void {
    g.died += ev.died;
    g.died_t += dt;
    if (g.died_t > 2) {
      if (g.died > 0) g.say("{d} PLANT(S) WITHERED", .{g.died});
      g.died = 0;
      g.died_t = 0;
    }
    if (ev.convergence and !g.found.contains(.convergence)) {
      g.found.insert(.convergence);
      g.say("DISCOVERY: SYMBIOTE AND PARASITE ENTWINE", .{});
      g.say("A HYBRID SEED STIRS. RESEARCH SEED SPLICING", .{});
    }
    const target:f32 = if (g.done.contains(.thinning_veil)) 1 else 0;
    g.veil += (target - g.veil) * @min(1, dt * 0.3);
    for (&g.log) |*m| m.age += dt;
  }
};

test "labs consume ingredients unit by unit" {
  var g:Progression = .{};
  var lab:Lab = .{};
  var inv:items.Inventory(8) = .{};
  g.select(.seed_splicing);
  try std.testing.expect(g.current == null); // locked
  g.select(.ley_sight);
  try std.testing.expect(g.current == .ley_sight);
  // no ingredients: nothing happens
  g.labTick(&lab, &inv, 10);
  try std.testing.expect(!lab.busy);
  _ = inv.add(.starlight, 20);
  var t:f32 = 0;
  while (t < 60) : (t += 0.1) g.labTick(&lab, &inv, 0.1);
  try std.testing.expect(g.done.contains(.ley_sight));
  try std.testing.expectEqual(@as(u32, 10), inv.count(.starlight));
  try std.testing.expect(g.current == null);
  // convergence gates splicing even once prerequisites are done
  g.done.insert(.root_communion);
  g.done.insert(.hungering_tendrils);
  try std.testing.expect(g.status(.seed_splicing) == .locked);
  g.absorb(.{.convergence = true}, 0.016);
  try std.testing.expect(g.status(.seed_splicing) == .open);
}
