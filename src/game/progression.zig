//! research tree, discoveries and world events.
//!
//! research works like Factorio labs: a technology is chosen, then a research
//! structure in the world consumes its per-unit ingredients from its own
//! inventory, one unit at a time, until enough units are done. Nothing is
//! paid from a pool.
//!
//! Each technology is its own module under `research/` declaring:
//!   def:Research                  name, cost, prerequisites    (required)
//!   apply(*ecology.Mods)          what it changes in the living world
//!   unlocks:[_]species.Id         species it lets the gardener plant
//!   completed(*Progression)       anything said or done when it is learned
//!   veil:f32                      how far it pulls the world-event veil
//! A new technology is one new file plus one line in `techs`.
const std = @import("std");
const EnumArray = std.enums.EnumArray;
const bufPrint = std.fmt.bufPrint;
const copyBackwards = std.mem.copyBackwards;
const testing = std.testing;
const registry = @import("../core/registry.zig");
const species = @import("../sim/species.zig");
const ecology = @import("../sim/ecology.zig");
const items = @import("../sim/items.zig");

const techs = struct {
  pub const ley_sight = @import("research/ley_sight.zig");
  pub const drift_spores = @import("research/drift_spores.zig");
  pub const root_communion = @import("research/root_communion.zig");
  pub const canopy_weaving = @import("research/canopy_weaving.zig");
  pub const hungering_tendrils = @import("research/hungering_tendrils.zig");
  pub const seed_splicing = @import("research/seed_splicing.zig");
  pub const thinning_veil = @import("research/thinning_veil.zig");
};
const reg = registry.Registry(techs);

pub const Discovery = enum { convergence };

pub const Id = reg.Id;

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

pub const tree = reg.table(Research, "def");

/// for each species, the technology that must be known to plant it (null: always).
const plant_gate = blk: {
  var gate = EnumArray(species.Id, ?Id).initFill(null);
  for (reg.ids) |id| if (reg.has(id, "unlocks")) for (reg.module(id).unlocks) |sp| gate.set(sp, id);
  break :blk gate;
};

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
    copyBackwards(Message, g.log[1..], g.log[0 .. g.log.len - 1]);
    const m = &g.log[0];
    m.* = .{};
    m.len = if (bufPrint(&m.buf, fmt, args)) |s| s.len else |_| m.buf.len;
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
    switch (id) {
      inline else => |k| if (comptime reg.has(k, "completed")) reg.module(k).completed(g),
    }
  }

  pub fn canPlant(g:*const Progression, sp:species.Id) bool {
    const gate = plant_gate.get(sp) orelse return true;
    return g.done.contains(gate);
  }

  /// the living world as shaped by everything learned so far.
  pub fn mods(g:*const Progression) ecology.Mods {
    var m:ecology.Mods = .{};
    inline for (reg.ids) |id| {
      if (comptime reg.has(id, "apply")) if (g.done.contains(id)) reg.module(id).apply(&m);
    }
    return m;
  }

  /// where the world-event veil is heading, from what has been learned.
  fn veilTarget(g:*const Progression) f32 {
    var v:f32 = 0;
    inline for (reg.ids) |id| {
      if (comptime reg.has(id, "veil")) if (g.done.contains(id)) { v = @max(v, reg.module(id).veil); };
    }
    return v;
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
    g.veil += (g.veilTarget() - g.veil) * @min(1, dt * 0.3);
    for (&g.log) |*m| m.age += dt;
  }
};

test "labs consume ingredients unit by unit" {
  var g:Progression = .{};
  var lab:Lab = .{};
  var inv:items.Inventory(8) = .{};
  g.select(.seed_splicing);
  try testing.expect(g.current == null); // locked
  g.select(.ley_sight);
  try testing.expect(g.current == .ley_sight);
  // no ingredients: nothing happens
  g.labTick(&lab, &inv, 10);
  try testing.expect(!lab.busy);
  _ = inv.add(.starlight, 20);
  var t:f32 = 0;
  while (t < 60) : (t += 0.1) g.labTick(&lab, &inv, 0.1);
  try testing.expect(g.done.contains(.ley_sight));
  try testing.expectEqual(@as(u32, 10), inv.count(.starlight));
  try testing.expect(g.current == null);
  // convergence gates splicing even once prerequisites are done
  g.done.insert(.root_communion);
  g.done.insert(.hungering_tendrils);
  try testing.expect(g.status(.seed_splicing) == .locked);
  g.absorb(.{.convergence = true}, 0.016);
  try testing.expect(g.status(.seed_splicing) == .open);
}
