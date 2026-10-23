//! the fixed-tick ecology: mana from the ley field, symbiotic sharing,
//! parasitic draining, growth, essence and death. Two-phase (accumulate
//! deltas, then apply) so the result never depends on plant order.
const std = @import("std");
const m = @import("../core/math.zig");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const species = @import("species.zig");
const plants_mod = @import("plants.zig");
const ck = @import("../world/chunk.zig");
const World = @import("../world/world.zig").World;

const Plants = plants_mod.Plants;
const Id = plants_mod.Id;

/// knobs that progression turns. The sim never imports game code.
pub const Mods = struct {
  /// symbiotic links reach the second ring.
  link2:bool = false,
  drain_mult:f32 = 1,
  yield_mult:[species.count]f32 = @splat(1),
  /// how dark it is (0 day .. 1 night); floating plants drink starlight.
  night:f32 = 0,
};

pub const Events = struct {
  died:u32 = 0,
};

pub const MAX_SEEDS = 3;
/// health lost per second by a plant that needs radiance and has none
const UNPOWERED_WITHER:f32 = 0.06;
/// floaters drink this share of their draw by day, all of it at full night
const DAY_DRINK:f32 = 0.1;
/// a drawn ley tile refills this share of its deficit per second
const LEY_REFILL:f32 = 0.15;
/// symbiotes pass on this share of their fill difference (times share and
/// cap) per second; the receiver heals a little for it
const SHARE_RATE:f32 = 0.5;
const SHARE_HEAL:f32 = 0.02;
/// a parasite keeps this share of what it drains; prey below `STARVED` of
/// its cap loses health
const DRAIN_KEEP:f32 = 0.85;
const STARVED:f32 = 0.1;
const STARVE_HURT:f32 = 0.08;
/// growth: a starved plant still grows at `GROW_MIN` of its pace; each kin
/// linked speeds it (and its yield) up
const GROW_MIN:f32 = 0.3;
const KIN_GROW:f32 = 0.15;
const KIN_YIELD:f32 = 0.1;
/// a mature plant sets seed while healthier than this
const SEED_HEALTH:f32 = 0.5;
/// health per second: a mature plant nearly out of mana fades, others heal
const EMPTY:f32 = 0.05;
const FADE:f32 = 0.05;
const HEAL:f32 = 0.02;
/// the drawn sap flow: mana moved per cap, scaled, and eased per tick
const FLOW_GAIN:f32 = 4;
const FLOW_EASE:f32 = 0.05;

/// celestial energy (the blooms'). Blooms link with every bloom of their
/// kind within `link` tiles into networks; a network radiates when it holds
/// at least one mature bloom, and then every bloom in it, growing or not,
/// holds its field. A plant needs only one radiating bloom within range.
/// Worked out each tick from the blooms alone: their links pairwise (they
/// are few), then each radiating bloom's field by the tiles under it, the
/// same way containment is; plants are never scanned against blooms.
pub const Radiance = struct {
  /// per plant: whether it stands in a radiating bloom's field
  powered:std.ArrayList(bool) = .empty,
  /// per plant: whether it is a bloom that radiates
  radiating:std.ArrayList(bool) = .empty,
  /// linked pairs of blooms (drawn as threads of light); `live` when their
  /// network radiates
  links:std.ArrayList(Link) = .empty,
  /// scratch: the blooms' plant indices, their networks (union-find roots)
  /// and which networks hold a mature bloom
  blooms:std.ArrayList(u32) = .empty,
  root:std.ArrayList(u32) = .empty,
  live:std.ArrayList(bool) = .empty,

  pub const Link = struct { a:Id, b:Id, live:bool };

  pub fn deinit(r:*Radiance, gpa:Allocator) void {
    r.powered.deinit(gpa); r.radiating.deinit(gpa); r.links.deinit(gpa); r.blooms.deinit(gpa); r.root.deinit(gpa); r.live.deinit(gpa);
  }

  fn find(r:*Radiance, i:u32) u32 {
    var k = i;
    while (r.root.items[k] != k) k = r.root.items[k];
    return k;
  }

  pub fn update(r:*Radiance, gpa:Allocator, p:*const Plants, w:*const World) Allocator.Error!void {
    const n = p.len();
    try r.powered.resize(gpa, n);
    @memset(r.powered.items, false);
    try r.radiating.resize(gpa, n);
    @memset(r.radiating.items, false);
    r.links.clearRetainingCapacity();
    r.blooms.clearRetainingCapacity();
    const s = p.list.slice();
    for (s.items(.sp), 0..) |sp, i| {
      if (species.get(sp).radiance > 0) try r.blooms.append(gpa, @intCast(i));
    }
    const bn = r.blooms.items.len;
    if (bn == 0) return;
    // networks: every pair within linking range joins
    try r.root.resize(gpa, bn);
    for (r.root.items, 0..) |*x, k| x.* = @intCast(k);
    const xs = s.items(.x);
    const ys = s.items(.y);
    for (0..bn) |a| for (a + 1..bn) |b| {
      const ia = r.blooms.items[a];
      const ib = r.blooms.items[b];
      const reach = @min(species.get(s.items(.sp)[ia]).link, species.get(s.items(.sp)[ib]).link);
      const dx = m.f(xs[ia] - xs[ib]);
      const dy = m.f(ys[ia] - ys[ib]);
      if (dx * dx + dy * dy > reach * reach) continue;
      try r.links.append(gpa, .{.a = .of(ia), .b = .of(ib), .live = false});
      const ra = r.find(@intCast(a));
      const rb = r.find(@intCast(b));
      if (ra != rb) r.root.items[ra] = rb;
    };
    // a network radiates when it holds a mature bloom
    try r.live.resize(gpa, bn);
    @memset(r.live.items, false);
    for (r.blooms.items, 0..) |i, k| {
      if (s.items(.growth)[i] >= 1) r.live.items[r.find(@intCast(k))] = true;
    }
    for (r.blooms.items, 0..) |i, k| {
      if (r.live.items[r.find(@intCast(k))]) r.radiating.items[i] = true;
    }
    for (r.links.items) |*l| l.live = r.radiating.items[l.a.idx()];
    // each radiating bloom powers the plants on the tiles in its field
    for (r.blooms.items) |i| {
      if (!r.radiating.items[i]) continue;
      const rad = species.get(s.items(.sp)[i]).radiance;
      const reach:i32 = @intFromFloat(@ceil(rad));
      var dy:i32 = -reach;
      while (dy <= reach) : (dy += 1) {
        var dx:i32 = -reach;
        while (dx <= reach) : (dx += 1) {
          if (m.f(dx * dx + dy * dy) > rad * rad) continue;
          const j = p.at(w, xs[i] + dx, ys[i] + dy) orelse continue;
          r.powered.items[j.idx()] = true;
        }
      }
    }
  }
};

pub const Ecology = struct {
  dm:std.ArrayList(f32) = .empty,
  dh:std.ArrayList(f32) = .empty,
  df:std.ArrayList(f32) = .empty,
  /// per plant: its drain rate after containment (1, or `species.CONTAINED`).
  calm:std.ArrayList(f32) = .empty,
  radiance:Radiance = .{},
  dead:std.ArrayList(Id) = .empty,

  pub fn deinit(e:*Ecology, gpa:Allocator) void {
    e.dm.deinit(gpa); e.dh.deinit(gpa); e.df.deinit(gpa); e.calm.deinit(gpa); e.dead.deinit(gpa);
    e.radiance.deinit(gpa);
  }

  /// mature containing plants (the confluence) calm every parasite within
  /// their reach: they keep draining, at a fraction of the rate.
  fn contain(e:*Ecology, gpa:Allocator, p:*const Plants, w:*const World) Allocator.Error!void {
    try e.calm.resize(gpa, p.len());
    @memset(e.calm.items, 1);
    const s = p.list.slice();
    for (s.items(.sp), s.items(.growth), 0..) |sp, growth, i| {
      const r:i32 = species.get(sp).contain;
      if (r == 0 or growth < 1) continue;
      const f = p.extent(i);
      var y = f.y - r;
      while (y < f.y + f.size + r) : (y += 1) {
        var x = f.x - r;
        while (x < f.x + f.size + r) : (x += 1) {
          const j = p.at(w, x, y) orelse continue;
          if (species.get(s.items(.sp)[j.idx()]).lineage == .parasitic) e.calm.items[j.idx()] = species.CONTAINED;
        }
      }
    }
  }

  pub fn tick(e:*Ecology, gpa:Allocator, p:*Plants, w:*World, mods:Mods, dt:f32) Allocator.Error!Events {
    var ev:Events = .{};
    if (p.topology_dirty) p.rebuildLinks(w);
    const n = p.len();
    if (n == 0) return ev;
    try e.dm.resize(gpa, n); @memset(e.dm.items, 0);
    try e.dh.resize(gpa, n); @memset(e.dh.items, 0);
    try e.df.resize(gpa, n); @memset(e.df.items, 0);
    try e.contain(gpa, p, w);
    try e.radiance.update(gpa, p, w);
    const calm = e.calm.items;
    const powered = e.radiance.powered.items;
    const dm = e.dm.items;
    const dh = e.dh.items;
    const df = e.df.items;

    const s = p.list.slice();
    const sps = s.items(.sp);
    const mana = s.items(.mana);
    const growth = s.items(.growth);
    const span = s.items(.span);
    const health = s.items(.health);
    const chunks = s.items(.chunk);
    const tiles = s.items(.tile);
    const essence = s.items(.essence);
    const seeds = s.items(.seeds);
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
      if (sp.floating) {
        // floaters never touch the ley: they drink the night sky
        dm[i] += sp.ley_draw * (DAY_DRINK + (1 - DAY_DRINK) * mods.night) * dt;
      } else {
        const got = @min(c.ley[t], sp.ley_draw * dt);
        c.ley[t] += (c.ley_cap[t] - c.ley[t]) * LEY_REFILL * dt - got;
        dm[i] += got;
      }

      var kin:f32 = 0;
      if (sp.share > 0) {
        const rings = if (mods.link2) @as(usize, 2) else 1;
        for (0..rings) |ring| {
          const ns:[]const Id = if (ring == 0) &n1[i] else &n2[i];
          for (ns) |id| {
            if (id == .none) break;
            const j = id.idx();
            const sj = species.get(sps[j]);
            if (sj.lineage == .parasitic) continue;
            kin += 1;
            const diff = fill - mana[j] / sj.mana_cap;
            if (diff <= 0) continue;
            const f = diff * sp.share * cap * SHARE_RATE * dt;
            dm[i] -= f; dm[j] += f;
            df[i] += f; df[j] += f;
            dh[j] += SHARE_HEAL * dt;
          }
        }
      }
      if (sp.drain > 0) {
        for (n1[i]) |id| {
          if (id == .none) break;
          const j = id.idx();
          const lj = species.get(sps[j]).lineage;
          const prey = switch (lin) {
            .parasitic => lj != .parasitic,
            .convergent => lj == .parasitic,
            .symbiotic => false,
          };
          if (!prey) continue;
          const take = @min(mana[j], sp.drain * mods.drain_mult * calm[i] * dt);
          dm[j] -= take; dm[i] += take * DRAIN_KEEP;
          df[i] += take; df[j] += take;
          if (mana[j] < STARVED * species.get(sps[j]).mana_cap) dh[j] -= STARVE_HURT * dt;
        }
      }

      // without celestial energy a plant that needs it halts and withers
      if (sp.needs_radiance and !powered[i]) {
        dh[i] -= UNPOWERED_WITHER * dt;
        continue;
      }
      if (growth[i] < 1) {
        const mature = if (span[i] > 0) span[i] else sp.mature_time;
        growth[i] = @min(1, growth[i] + dt / mature * (GROW_MIN + (1 - GROW_MIN) * fill) * health[i] * (1 + KIN_GROW * kin));
      } else {
        // mana condenses into essence held by the plant until harvested.
        const room = cap - essence[i];
        const conv = @min(@min(mana[i], sp.yield * fill * dt), room);
        dm[i] -= conv;
        essence[i] = @min(cap, essence[i] + conv * mods.yield_mult[@intFromEnum(sps[i])] * (1 + KIN_YIELD * kin));
        if (health[i] > SEED_HEALTH) seeds[i] = @min(MAX_SEEDS, seeds[i] + dt / sp.seed_time);
      }
      dh[i] += if (fill < EMPTY and growth[i] >= 1) -FADE * dt else HEAL * dt;
    }

    const flow = s.items(.flow);
    e.dead.clearRetainingCapacity();
    for (0..n) |i| {
      const cap = species.get(sps[i]).mana_cap;
      mana[i] = m.clamp(mana[i] + dm[i], 0, cap);
      health[i] = m.clamp(health[i] + dh[i], 0, 1);
      flow[i] += (df[i] / dt / cap * FLOW_GAIN - flow[i]) * FLOW_EASE;
      if (health[i] <= 0) try e.dead.append(gpa, .of(i));
    }
    var k = e.dead.items.len;
    while (k > 0) { k -= 1; p.remove(w, e.dead.items[k]); }
    ev.died = @intCast(e.dead.items.len);
    return ev;
  }
};

/// tests run the sim at 60 Hz (the sim never imports game's `play.TICK`)
const TEST_HZ = 60;
const TEST_DT:f32 = 1.0 / m.f(TEST_HZ);

test "symbiotes share, parasites drain" {
  const gpa = testing.allocator;
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
  try testing.expect(try p.place(gpa, &w, 0, 0, .lumenroot, 0.1));
  try testing.expect(try p.place(gpa, &w, 1, 0, .thornleech, 0.2));
  for (0..TEST_HZ * 30) |_| _ = try eco.tick(gpa, &p, &w, .{}, TEST_DT);
  const es = p.list.items(.essence);
  try testing.expect(p.len() < 2 or es[0] + es[1] > 0);
  try testing.expect(p.list.items(.flow)[0] > 0 or p.len() < 2);
}

test "a mature confluence halves parasite drain within 3 tiles" {
  const gpa = testing.allocator;
  var loss:[3]f32 = undefined;
  // no confluence; a mature one 2 tiles from the leech; one 4 tiles away
  for ([_]?i32{null, 3, 5}, 0..) |at, k| {
    var w = World.init(gpa, 5);
    defer w.deinit();
    try w.stream(.{.x = 0, .y = 0}, 1, 100);
    const c = w.chunkOfTile(0, 0).?;
    for (0..2) |y| for (0..8) |x| { c.kind[y * ck.SIZE + x] = .soil; c.height[y * ck.SIZE + x] = 1; };
    var p:Plants = .{};
    defer p.deinit(gpa);
    var eco:Ecology = .{};
    defer eco.deinit(gpa);
    try testing.expect(try p.placeEx(gpa, &w, 0, 0, .{.x = 0, .y = 0, .chunk = undefined, .tile = undefined, .sp = .lumenroot, .seed = 0, .mana = 5}));
    try testing.expect(try p.place(gpa, &w, 1, 0, .thornleech, 0));
    if (at) |x| try testing.expect(try p.placeEx(gpa, &w, x, 0, .{.x = x, .y = 0, .chunk = undefined, .tile = undefined, .sp = .confluence, .seed = 0, .growth = 1}));
    // the leech's 2-tile neighbourhood keeps the root's ley draw identical in every case
    _ = try eco.tick(gpa, &p, &w, .{}, 0.1);
    loss[k] = 5 - p.list.items(.mana)[0];
  }
  const full = species.get(.thornleech).drain * 0.1;
  try testing.expectApproxEqAbs(full * (1 - species.CONTAINED), loss[0] - loss[1], 1e-4);
  try testing.expectApproxEqAbs(loss[0], loss[2], 1e-4);
}

test "blooms power plants in range, link into networks, and uprooting cuts them off" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{.x = 0, .y = 0}, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..3) |y| for (0..20) |x| { c.kind[y * ck.SIZE + x] = .soil; };
  var p:Plants = .{};
  defer p.deinit(gpa);
  var eco:Ecology = .{};
  defer eco.deinit(gpa);
  // a mature bloom over (2,0), a vesper (which needs radiance) beside it
  try testing.expect(try p.placeEx(gpa, &w, 2, 0, .{.x = 2, .y = 0, .chunk = undefined, .tile = undefined, .sp = .bloom, .seed = 0.1, .growth = 1}));
  try testing.expect(try p.place(gpa, &w, 0, 0, .vesper, 0.2));
  // a young bloom 7 tiles on (within linking range, out of the first's
  // field) and a second vesper inside only its field
  try testing.expect(try p.placeEx(gpa, &w, 9, 0, .{.x = 9, .y = 0, .chunk = undefined, .tile = undefined, .sp = .bloom, .seed = 0.3}));
  try testing.expect(try p.place(gpa, &w, 11, 0, .vesper, 0.4));
  const near = p.at(&w, 0, 0).?;
  const far = p.at(&w, 11, 0).?;
  for (0..TEST_HZ) |_| _ = try eco.tick(gpa, &p, &w, .{}, TEST_DT);
  // the first draws from the mature bloom; the second from the young one,
  // which radiates because it is linked to a network with a mature bloom
  try testing.expect(eco.radiance.powered.items[near.idx()]);
  try testing.expect(eco.radiance.powered.items[far.idx()]);
  try testing.expectEqual(@as(usize, 1), eco.radiance.links.items.len);
  try testing.expect(eco.radiance.links.items[0].live);
  try testing.expect(p.list.items(.growth)[near.idx()] > 0);

  // uproot the mature bloom: the young one's network holds no mature bloom
  // now, so nothing radiates, and both vespers halt and wither
  try testing.expect(p.removeAt(&w, 2, 0));
  const growth_before = p.list.items(.growth)[p.at(&w, 0, 0).?.idx()];
  for (0..TEST_HZ * 5) |_| _ = try eco.tick(gpa, &p, &w, .{}, TEST_DT);
  const a = p.at(&w, 0, 0).?.idx();
  const b = p.at(&w, 11, 0).?.idx();
  try testing.expect(!eco.radiance.powered.items[a] and !eco.radiance.powered.items[b]);
  try testing.expectEqual(growth_before, p.list.items(.growth)[a]);
  try testing.expect(p.list.items(.health)[a] < 0.8 and p.list.items(.health)[b] < 0.8);
  // one bloom left: nothing to link to
  try testing.expectEqual(@as(usize, 0), eco.radiance.links.items.len);
}
