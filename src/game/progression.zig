//! essence economy, research tree, discoveries and world events. Research
//! entries reference each other (prerequisites), discoveries and species, and
//! everything they unlock is expressed as ecology mods or planting rights.
const std = @import("std");
const species = @import("../sim/species.zig");
const ecology = @import("../sim/ecology.zig");

pub const Discovery = enum { convergence };

pub const Id = enum { ley_sight, root_communion, hungering_tendrils, seed_splicing, thinning_veil };

pub const Research = struct {
  name:[]const u8,
  desc:[]const u8,
  cost:f64,
  prereq:[]const Id = &.{},
  needs:?Discovery = null,
};

pub const tree = std.enums.EnumArray(Id, Research).init(.{
  .ley_sight = .{.name = "LEY SIGHT", .desc = "SEE THE LEY CURRENTS", .cost = 15},
  .root_communion = .{.name = "ROOT COMMUNION", .desc = "SYMBIOTIC LINKS REACH 2 TILES", .cost = 40},
  .hungering_tendrils = .{.name = "HUNGERING TENDRILS", .desc = "PARASITES DRAIN X2", .cost = 40},
  .seed_splicing = .{
    .name = "SEED SPLICING", .desc = "PLANT VESPER BLOOM", .cost = 120,
    .prereq = &.{.root_communion, .hungering_tendrils}, .needs = .convergence,
  },
  .thinning_veil = .{
    .name = "THE THINNING VEIL", .desc = "HYBRIDS YIELD X3. SOMETHING STIRS", .cost = 400,
    .prereq = &.{.seed_splicing},
  },
});

pub const Message = struct { buf:[96]u8 = undefined, len:usize = 0, age:f32 = 0 };

pub const Progression = struct {
  essence:f64 = 0,
  lifetime:f64 = 0,
  done:std.EnumSet(Id) = .initEmpty(),
  found:std.EnumSet(Discovery) = .initEmpty(),
  /// world event blend 0..1 (sky/glow shift after the veil thins).
  veil:f32 = 0,
  log:[6]Message = @splat(.{}),
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

  pub fn buy(g:*Progression, id:Id) bool {
    const r = tree.get(id);
    if (g.status(id) != .open) { g.say("{s} IS LOCKED", .{r.name}); return false; }
    if (g.essence < r.cost) { g.say("NEED {d:.0} ESSENCE FOR {s}", .{r.cost, r.name}); return false; }
    g.essence -= r.cost;
    g.done.insert(id);
    g.say("RESEARCHED {s}", .{r.name});
    if (id == .thinning_veil) g.say("THE VEIL THINS. THE GARDEN DREAMS OF MORE", .{});
    return true;
  }

  pub fn canPlant(g:*const Progression, sp:species.Id) bool {
    return switch (sp) {
      .lumenroot, .thornleech => true,
      .vesper => g.done.contains(.seed_splicing),
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
    g.essence += ev.essence;
    g.lifetime += ev.essence;
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

test "research gating" {
  var g:Progression = .{};
  g.essence = 1000;
  try std.testing.expect(!g.buy(.seed_splicing));
  try std.testing.expect(g.buy(.root_communion));
  try std.testing.expect(g.buy(.hungering_tendrils));
  try std.testing.expect(!g.buy(.seed_splicing));
  g.absorb(.{.convergence = true}, 0.016);
  try std.testing.expect(g.buy(.seed_splicing));
  try std.testing.expect(g.canPlant(.vesper));
}
