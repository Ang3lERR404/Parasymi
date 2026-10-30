//! structures tested: harvesting, handing off, the tile index, records.
const lib = @import("../../../lib.zig");
const std = lib.std;
const testing = std.testing;
const engine = lib.engine;
const m = engine.core.math;
const ck = lib.ck;
const World = lib.world.World;
const Plants = lib.plants.Plants;
const prog = lib.progression;
const Ctx = lib.structures.structure.Ctx;
const Id = lib.structures.Id;
const Kind = lib.structures.Kind;
const Ring = lib.structures.handoff.Ring;
const Structures = lib.structures.list.Structures;
const handOff = lib.structures.handoff.handOff;
const handOffWith = lib.structures.handoff.handOffWith;

test "conduits harvest plants into a cache" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..4) |x| { c.kind[x] = .soil; c.height[x] = 1; c.res[x] = 0; }
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  // plant -> conduit -> conduit -> cache, left to right
  try testing.expect(try plants.placeEx(gpa, &w, 0, 0, .{ .x = 0, .y = 0, .chunk = undefined, .tile = undefined, .sp = .lumenroot, .seed = 0, .growth = 1, .essence = 3 }));
  try testing.expect(try ss.place(gpa, &w, 1, 0, .conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 0, .conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 3, 0, .sap_cache, 0, 0));
  for (0..200) |_| try ss.tick(gpa, &w, &plants, &g, 0.05);
  const cache = ss.at(&w, 3, 0).?;
  try testing.expectEqual(@as(u32, 3), ss.get(cache).inv.count(.essence));
  // removing the middle conduit keeps the others addressable
  _ = ss.remove(&w, ss.at(&w, 1, 0).?);
  try testing.expect(ss.get(ss.at(&w, 3, 0).?).kind() == .sap_cache);
}
test "a conduit's side root reaches a plant beside it and harvests it" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..3) |x| for (0..2) |y| { const t = y * ck.SIZE + x; c.kind[t] = .soil; c.height[t] = 1; c.res[t] = 0; };
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  // conduit -> cache along +x, a mature plant beside the conduit (+y)
  try testing.expect(try plants.placeEx(gpa, &w, 1, 1, .{ .x = 1, .y = 1, .chunk = undefined, .tile = undefined, .sp = .lumenroot, .seed = 0, .growth = 1, .essence = 2 }));
  try testing.expect(try ss.place(gpa, &w, 1, 0, .conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 0, .sap_cache, 0, 0));
  // nothing moves until the root has grown out to it
  try ss.tick(gpa, &w, &plants, &g, 0.05);
  try testing.expect(ss.get(ss.at(&w, 1, 0).?).state.conduit.held == null);
  for (0..200) |_| try ss.tick(gpa, &w, &plants, &g, 0.05);
  try testing.expectEqual(@as(u32, 2), ss.get(ss.at(&w, 2, 0).?).inv.count(.essence));
}

test "a footprint's ring holds every tile that many steps out, once, beside ones first in `m.dirs` order" {
  var one:Ring = .{ .x0 = 0, .y0 = 0, .x1 = 0, .y1 = 0, .d = 1 };
  for (m.dirs) |d| {
    const v = m.dirVec(d);
    try testing.expectEqual([2]i32{ v.x, v.z }, one.next().?);
  }
  try testing.expect(one.next() == null);
  for ([_]i32{ 1, 2 }) |n| for ([_]i32{ 1, 2, 3 }) |d| {
    var r:Ring = .{ .x0 = 0, .y0 = 0, .x1 = n - 1, .y1 = n - 1, .d = d };
    var seen:[64][2]i32 = undefined;
    var c:usize = 0;
    while (r.next()) |t| : (c += 1) {
      const dx = @max(0 - t[0], 0, t[0] - (n - 1));
      const dy = @max(0 - t[1], 0, t[1] - (n - 1));
      try testing.expectEqual(d, dx + dy);
      for (seen[0..c]) |s| try testing.expect(!(s[0] == t[0] and s[1] == t[1]));
      seen[c] = t;
    }
    try testing.expectEqual(@as(usize, @intCast(4 * n + 4 * (d - 1))), c);
  };
}

test "handing off reaches further and hands more when asked, the nearest first" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..4) |x| { c.kind[x] = .soil; c.height[x] = 1; c.res[x] = 0; }
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  const ctx:Ctx = .{ .gpa = gpa, .w = &w, .plants = &plants, .g = &g, .ss = &ss };
  // loomfern, a gap, a cache two steps out
  try testing.expect(try ss.place(gpa, &w, 0, 0, .loomfern, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 0, .sap_cache, 0, 0));
  const fern = ss.at(&w, 0, 0).?;
  const cache = ss.at(&w, 2, 0).?;
  _ = ss.get(fern).inv.add(.fibre, 6);
  try testing.expect(!handOff(ctx, fern));
  try testing.expectEqual(@as(u16, 4), handOffWith(ctx, fern, .{ .range = 2, .amount = 4 }));
  try testing.expectEqual(@as(u32, 4), ss.get(cache).inv.count(.fibre));
  // a cache beside it now comes first; asked for more than it has, all go
  try testing.expect(try ss.place(gpa, &w, 1, 0, .sap_cache, 0, 0));
  const near = ss.at(&w, 1, 0).?;
  try testing.expectEqual(@as(u16, 2), handOffWith(ctx, fern, .{ .range = 2, .amount = 9 }));
  try testing.expectEqual(@as(u32, 2), ss.get(near).inv.count(.fibre));
  try testing.expectEqual(@as(u32, 0), ss.get(fern).inv.count(.fibre));
}

/// `find` and `getChildren` as walking the whole list answers them
fn expectIndexed(ss:*const Structures) !void {
  try testing.expectEqual(ss.list.items.len, ss.where.count());
  try testing.expectEqual(ss.list.items.len, ss.kin.items.len);
  for (ss.list.items, 0..) |*s, i| {
    try testing.expectEqual(Id.of(i), ss.find(s.ref()).?);
    var it = ss.getChildren(Id.of(i));
    for (ss.list.items, 0..) |*o, j| if (o.parent) |p| if (p.eql(s.ref())) {
      try testing.expectEqual(Id.of(j), it.next().?);
    };
    try testing.expect(it.next() == null);
  }
}

test "the tile index and the children agree with the list through placing, adopting, uprooting and a reload" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..10) |x| for (0..10) |y| { const t = y * ck.SIZE + x; c.kind[t] = .soil; c.height[t] = 1; c.res[t] = 0; };
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  var rng = engine.core.rng.Rng.init(7);
  const ks = [_]Kind{ .sap_cache, .monfris, .vultrixi, .vultrixi };
  for (0..400) |_| {
    const n = ss.list.items.len;
    switch (rng.below(4)) {
      0, 1 => _ = try ss.place(gpa, &w, @intCast(rng.below(10)), @intCast(rng.below(10)), ks[rng.below(ks.len)], 0, 0),
      2 => if (n > 0) { _ = ss.dependOn(Id.of(rng.below(@intCast(n))), Id.of(rng.below(@intCast(n)))); },
      else => if (n > 0) {
        if (rng.below(3) == 0) ss.detach(Id.of(rng.below(@intCast(n)))) else _ = ss.remove(&w, Id.of(rng.below(@intCast(n))));
      },
    }
    try expectIndexed(&ss);
  }
  // put back as saved, in the same order
  var again:Structures = .{};
  defer again.deinit(gpa);
  var w2 = World.init(gpa, 5);
  defer w2.deinit();
  try w2.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c2 = w2.chunkOfTile(0, 0).?;
  for (0..10) |x| for (0..10) |y| { const t = y * ck.SIZE + x; c2.kind[t] = .soil; c2.height[t] = 1; c2.res[t] = 0; };
  for (ss.list.items) |s| try testing.expect(try again.restore(gpa, &w2, s));
  again.relink();
  try expectIndexed(&again);
  for (0..ss.list.items.len) |i| try testing.expectEqual(ss.childCount(Id.of(i)), again.childCount(Id.of(i)));
}

test "uprooting keeps the others in the order they were put down, each found on its own tiles" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..12) |x| for (0..2) |y| { const t = y * ck.SIZE + x; c.kind[t] = .soil; c.height[t] = 1; c.res[t] = 0; };
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  const put = [_]struct { x:i32, k:Kind }{ .{ .x = 0, .k = .sap_cache }, .{ .x = 1, .k = .monfris }, .{ .x = 3, .k = .sap_cache }, .{ .x = 4, .k = .monfris }, .{ .x = 6, .k = .loomfern } };
  for (put) |p| try testing.expect(try ss.place(gpa, &w, p.x, 0, p.k, 0, 0));
  _ = ss.remove(&w, ss.at(&w, 0, 0).?);
  _ = ss.remove(&w, ss.at(&w, 3, 0).?);
  const left = [_]i32{ 1, 4, 6 };
  try testing.expectEqual(left.len, ss.list.items.len);
  for (ss.list.items, left, 0..) |*s, x, i| {
    try testing.expectEqual(x, s.x);
    var it = m.footprint(s.x, s.y, s.def().size);
    while (it.next()) |t| try testing.expectEqual(Id.of(i), w.occAt(t[0], t[1]).asStructure().?);
  }
  try testing.expect(w.occAt(0, 0).asStructure() == null and w.occAt(3, 0).asStructure() == null);
  try expectIndexed(&ss);
}
