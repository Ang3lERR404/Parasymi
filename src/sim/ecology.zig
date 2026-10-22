//! the fixed-tick ecology: mana from the ley field, symbiotic sharing,
//! parasitic draining, growth, essence and death. Two-phase (accumulate
//! deltas, then apply) so the result never depends on plant order.
const std = @import("std");
const species = @import("species.zig");
const plants_mod = @import("plants.zig");
const World = @import("../world/world.zig").World;

const Plants = plants_mod.Plants;
const NONE = plants_mod.NONE;

/// knobs that progression turns. The sim never imports game code.
pub const Mods = struct {
  /// symbiotic links reach the second ring.
  link2:bool = false,
  drain_mult:f32 = 1,
  yield_mult:[species.count]f32 = @splat(1),
};

pub const Events = struct {
  essence:f64 = 0,
  died:u32 = 0,
  /// a mature symbiote touched a mature parasite this tick.
  convergence:bool = false,
};

pub const Ecology = struct {
  dm:std.ArrayList(f32) = .empty,
  dh:std.ArrayList(f32) = .empty,
  df:std.ArrayList(f32) = .empty,
  dead:std.ArrayList(u32) = .empty,

  pub fn deinit(e:*Ecology, gpa:std.mem.Allocator) void {
    e.dm.deinit(gpa); e.dh.deinit(gpa); e.df.deinit(gpa); e.dead.deinit(gpa);
  }

  pub fn tick(e:*Ecology, gpa:std.mem.Allocator, p:*Plants, w:*World, mods:Mods, dt:f32) !Events {
    var ev:Events = .{};
    if (p.topology_dirty) p.rebuildLinks(w);
    const n = p.len();
    if (n == 0) return ev;
    try e.dm.resize(gpa, n); @memset(e.dm.items, 0);
    try e.dh.resize(gpa, n); @memset(e.dh.items, 0);
    try e.df.resize(gpa, n); @memset(e.df.items, 0);
    const dm = e.dm.items;
    const dh = e.dh.items;
    const df = e.df.items;

    const s = p.list.slice();
    const sps = s.items(.sp);
    const mana = s.items(.mana);
    const growth = s.items(.growth);
    const health = s.items(.health);
    const chunks = s.items(.chunk);
    const tiles = s.items(.tile);
    const n1 = s.items(.n1);
    const n2 = s.items(.n2);

    for (0..n) |i| {
      const sp = species.get(sps[i]);
      const lin = sp.lineage;
      const cap = sp.mana_cap;
      const fill = mana[i] / cap;

      // ley field under the plant: draw, then let it slowly refill.
      const c = chunks[i];
      const t = tiles[i];
      const got = @min(c.ley[t], sp.ley_draw * dt);
      c.ley[t] += (c.ley_cap[t] - c.ley[t]) * 0.15 * dt - got;
      dm[i] += got;

      var kin:f32 = 0;
      if (sp.share > 0) {
        const rings = if (mods.link2) @as(usize, 2) else 1;
        for (0..rings) |ring| {
          const ns:[]const u32 = if (ring == 0) &n1[i] else &n2[i];
          for (ns) |j| {
            if (j == NONE) break;
            const sj = species.get(sps[j]);
            if (sj.lineage == .parasitic) continue;
            kin += 1;
            const diff = fill - mana[j] / sj.mana_cap;
            if (diff <= 0) continue;
            const f = diff * sp.share * cap * 0.5 * dt;
            dm[i] -= f; dm[j] += f;
            df[i] += f; df[j] += f;
            dh[j] += 0.02 * dt;
          }
        }
      }
      if (sp.drain > 0) {
        for (n1[i]) |j| {
          if (j == NONE) break;
          const lj = species.get(sps[j]).lineage;
          const prey = switch (lin) {
            .parasitic => lj != .parasitic,
            .convergent => lj == .parasitic,
            .symbiotic => false,
          };
          if (!prey) continue;
          const take = @min(mana[j], sp.drain * mods.drain_mult * dt);
          dm[j] -= take; dm[i] += take * 0.85;
          df[i] += take; df[j] += take;
          if (mana[j] < 0.1 * species.get(sps[j]).mana_cap) dh[j] -= 0.08 * dt;
        }
      }

      if (growth[i] < 1) {
        growth[i] = @min(1, growth[i] + dt / sp.mature_time * (0.3 + 0.7 * fill) * health[i] * (1 + 0.15 * kin));
      } else {
        const conv = @min(mana[i], sp.yield * fill * dt);
        dm[i] -= conv;
        ev.essence += conv * mods.yield_mult[@intFromEnum(sps[i])] * (1 + 0.1 * kin);
        if (lin == .symbiotic) for (n1[i]) |j| {
          if (j == NONE) break;
          if (species.get(sps[j]).lineage == .parasitic and growth[j] >= 1) ev.convergence = true;
        };
      }
      dh[i] += if (fill < 0.05 and growth[i] >= 1) -0.05 * dt else 0.02 * dt;
    }

    const flow = s.items(.flow);
    e.dead.clearRetainingCapacity();
    for (0..n) |i| {
      const cap = species.get(sps[i]).mana_cap;
      mana[i] = std.math.clamp(mana[i] + dm[i], 0, cap);
      health[i] = std.math.clamp(health[i] + dh[i], 0, 1);
      flow[i] += (df[i] / dt / cap * 4 - flow[i]) * 0.05;
      if (health[i] <= 0) try e.dead.append(gpa, @intCast(i));
    }
    var k = e.dead.items.len;
    while (k > 0) { k -= 1; p.remove(e.dead.items[k]); }
    ev.died = @intCast(e.dead.items.len);
    return ev;
  }
};

test "symbiotes share, parasites drain" {
  const gpa = std.testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{.x = 0, .y = 0}, 1, 100);
  // force a fertile strip for a deterministic test
  const c = w.chunkOfTile(0, 0).?;
  for (0..4) |x| c.kind[x] = .soil;
  var p:Plants = .{};
  defer p.deinit(gpa);
  var eco:Ecology = .{};
  defer eco.deinit(gpa);
  try std.testing.expect(try p.place(gpa, &w, 0, 0, .lumenroot, 0.1));
  try std.testing.expect(try p.place(gpa, &w, 1, 0, .thornleech, 0.2));
  var essence:f64 = 0;
  for (0..60 * 30) |_| essence += (try eco.tick(gpa, &p, &w, .{}, 1.0 / 60.0)).essence;
  try std.testing.expect(essence > 0);
  try std.testing.expect(p.list.items(.flow)[0] > 0 or p.len() < 2);
}
