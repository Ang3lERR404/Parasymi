//! research tree, discoveries and world events.
//!
//! research works like Factorio labs: a technology is chosen, then a research
//! structure in the world consumes its per-unit ingredients from its own
//! inventory, one unit at a time, until enough units are done. Nothing is
//! paid from a pool.
//!
//! Each technology is its own module under `research/` declaring:
//!   def:Research                  cost, prerequisites, branch  (required)
//!   apply(*ecology.Mods)          what it changes in the living world
//!   unlocks:[_]species.Id         species it lets the gardener plant
//!   completed(*Progression)       anything said or done when it is learned
//!   veil:f32                      how far it pulls the world-event veil
//!   reveals:[_]species.Id         species whose yield it makes visible
//! A new technology is one new file plus one line in `techs`.
const std = @import("std");
const EnumArray = std.enums.EnumArray;
const copyBackwards = std.mem.copyBackwards;
const testing = std.testing;
const registry = @import("../core/registry.zig");
const species = @import("../sim/species.zig");
const ecology = @import("../sim/ecology.zig");
const items = @import("../sim/items.zig");
const txt = @import("text.zig");
const ctext = @import("../core/text.zig");

const techs = struct {
  pub const ley_sight = @import("research/ley_sight.zig");
  pub const deep_rooting = @import("research/deep_rooting.zig");
  pub const drift_spores = @import("research/drift_spores.zig");
  pub const root_communion = @import("research/root_communion.zig");
  pub const canopy_weaving = @import("research/canopy_weaving.zig");
  pub const hungering_tendrils = @import("research/hungering_tendrils.zig");
  pub const seed_splicing = @import("research/seed_splicing.zig");
  pub const thinning_veil = @import("research/thinning_veil.zig");
  pub const convergence_theory = @import("research/convergence_theory.zig");
  pub const celestial_defragmentation = @import("research/celestial_defragmentation.zig");
};
const reg = registry.Registry(techs);

pub const Discovery = enum { convergence, diamond };

pub const Id = reg.Id;

pub const Research = struct {
  /// ingredients consumed per unit, units needed, seconds per unit.
  per_unit:[]const items.Ingredient,
  units:u32,
  unit_time:f32,
  prereq:[]const Id = &.{},
  needs:?Discovery = null,
  /// a big step (new structures, species, a world event): grows as a branch
  /// of the research sapling; anything else is a leaf (hud/research.zig).
  branch:bool = false,
};

pub const tree = reg.table(Research, "def");

pub const Status = enum { done, open, locked };

/// for each species, the technology that must be known to plant it (null: always).
const plant_gate = blk: {
  var gate = EnumArray(species.Id, ?Id).initFill(null);
  for (reg.ids) |id| if (reg.has(id, "unlocks")) for (reg.module(id).unlocks) |sp| gate.set(sp, id);
  break :blk gate;
};

/// for each species, the technology that must be known to see its yield (null: always).
const yield_gate = blk: {
  var gate = EnumArray(species.Id, ?Id).initFill(null);
  for (reg.ids) |id| if (reg.has(id, "reveals")) for (reg.module(id).reveals) |sp| gate.set(sp, id);
  break :blk gate;
};

/// working state of one research structure.
pub const Lab = struct {
  /// a unit's ingredients have been consumed and are being worked.
  busy:bool = false,
  t:f32 = 0,
  speed:f32 = 1,
};

const LOG_LEN = 6;
const MSG_BUF:usize = 96;

pub const Message = struct {
  buf:[MSG_BUF]u8 = undefined,
  len:usize = 0,
  age:f32 = 0,
};

/// seconds before a batch of withered plants is reported (avoids log spam)
const WITHER_BATCH:f32 = 2;
/// how quickly the veil eases toward its target (per second)
const VEIL_EASE:f32 = 0.3;

pub const Progression = struct {
  done:std.EnumSet(Id) = .initEmpty(),
  found:std.EnumSet(Discovery) = .initEmpty(),
  /// world event blend 0..1 (sky/glow shift after the veil thins).
  veil:f32 = 0,
  log:[LOG_LEN]Message = @splat(.{}),
  /// the technology every lab works on, and units finished per technology.
  current:?Id = null,
  progress:std.EnumArray(Id, u32) = .initFill(0),
  /// withered plants are reported in batches, not every tick.
  died:u32 = 0,
  died_t:f32 = 0,

  /// `tpl` is a runtime template (`core/text.zig`), usually `txt.s.msg.*`.
  pub fn say(g:*Progression, tpl:[]const u8, args:anytype) void {
    copyBackwards(Message, g.log[1..], g.log[0 .. g.log.len - 1]);
    const m = &g.log[0];
    m.* = .{};
    // if the message is too long it silently truncates to the buffer size
    m.len = ctext.bufRender(&m.buf, tpl, args).len;
  }

  pub fn status(g:*const Progression, id:Id) Status {
    if (g.done.contains(id)) return .done;
    const r = tree.get(id);
    for (r.prereq) |p| if (!g.done.contains(p)) return .locked;
    if (r.needs) |d| if (!g.found.contains(d)) return .locked;
    return .open;
  }

  pub fn select(g:*Progression, id:Id) void {
    const name = txt.research(id).name;
    switch (g.status(id)) {
      .open => { g.current = id; g.say(txt.s.msg.researching, .{name}); },
      .done => g.say(txt.s.msg.already_known, .{name}),
      .locked => g.say(txt.s.msg.locked, .{name}),
    }
  }

  /// advance one research structure. `inv` is the structure's own inventory.
  pub fn labTick(g:*Progression, lab:*Lab, inv:items.Bag, dt:f32) void {
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
    g.say(txt.s.msg.researched, .{txt.research(id).name});
    switch (id) {
      inline else => |k| if (comptime reg.has(k, "completed")) reg.module(k).completed(g),
    }
  }

  pub fn canPlant(g:*const Progression, sp:species.Id) bool {
    const gate = plant_gate.get(sp) orelse return true;
    return g.done.contains(gate);
  }

  /// does the gardener know what this species condenses?
  pub fn yieldKnown(g:*const Progression, sp:species.Id) bool {
    const gate = yield_gate.get(sp) orelse return true;
    return g.done.contains(gate);
  }

  /// something witnessed in the garden, said once.
  pub fn discover(g:*Progression, d:Discovery) void {
    if (g.found.contains(d)) return;
    g.found.insert(d);
    switch (d) {
      .convergence => {
        g.say(txt.s.msg.entwine, .{});
        g.say(txt.s.msg.hybrid_stirs, .{});
      },
      .diamond => {
        g.say(txt.s.msg.lattice_stirs, .{});
      },
    }
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
    if (g.died_t > WITHER_BATCH) {
      if (g.died > 0) g.say(txt.s.msg.withered, .{g.died});
      g.died = 0;
      g.died_t = 0;
    }
    g.veil += (g.veilTarget() - g.veil) * @min(1, dt * VEIL_EASE);
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
  g.labTick(&lab, inv.bag(), 10);
  try testing.expect(!lab.busy);
  _ = inv.add(.starlight, 20);
  var t:f32 = 0;
  while (t < 60) : (t += 0.1) g.labTick(&lab, inv.bag(), 0.1);
  try testing.expect(g.done.contains(.ley_sight));
  try testing.expectEqual(@as(u32, 10), inv.count(.starlight));
  try testing.expect(g.current == null);
  // convergence gates splicing even once prerequisites are done
  g.done.insert(.root_communion);
  g.done.insert(.hungering_tendrils);
  try testing.expect(g.status(.seed_splicing) == .locked);
  try testing.expect(g.status(.convergence_theory) == .locked);
  try testing.expect(!g.yieldKnown(.confluence) and g.yieldKnown(.lumenroot));
  g.discover(.convergence);
  try testing.expect(g.status(.seed_splicing) == .open);
  try testing.expect(g.status(.convergence_theory) == .open);
  g.done.insert(.convergence_theory);
  try testing.expect(g.yieldKnown(.confluence));
}