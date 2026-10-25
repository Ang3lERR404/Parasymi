//! ROOT-DIGGER: the first gathering automation. Its roots work the resource
//! node beside it, drawing out one item at a time (the same item the wolf
//! would gather there) into a small buffer. Conduits behind it pull from
//! that buffer; any other structure beside it that wants the item is fed
//! directly. When the node runs dry it idles, and it takes up any node that
//! appears beside it later by itself. Its digging root reaches out to the
//! node it works and withers back from one gone; what it draws out swells
//! up the root home into the gourd its knot of roots grips.
const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const m = @import("../../core/math.zig");
const color = @import("../../core/color.zig");
const ck = @import("../../world/chunk.zig");
const World = @import("../../world/world.zig").World;
const items = @import("../../sim/items.zig");
const Plants = @import("../../sim/plants.zig").Plants;
const st = @import("../structures.zig");
const icon_kit = @import("../icon.zig");
const txt = @import("../text.zig");
const prog = @import("../progression.zig");
const resources = @import("../resources.zig");
const style = @import("../style.zig");
const Parts = @import("../parts.zig").Parts;
const Draw = @import("../../ui/draw.zig").Draw;
const Color = @import("../../ui/draw.zig").Color;
const play = @import("../play.zig");
const actions = @import("../actions.zig");
const Look = @import("../parts.zig").Look;
const mesh = @import("../../gfx/meshes/root_digger.zig");

/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes = .{ .belly_lump, .digger_clod, .digger_root };

pub const def:st.Def = .{ .item = .root_digger, .size = 1, .mesh = .root_digger, .store = true, .grow = 4, .sway = 0.5, .tall = 0.6 };

/// seconds per item drawn from the node
pub const RATE:f32 = 4;
/// items it holds before it stops digging
pub const BUFFER = 8;
/// how fast its digging root reaches out to a node (its length a second)
/// and withers back from one gone
const ROOT_GROW:f32 = 0.6;
const ROOT_WITHER:f32 = 0.9;
const ROOT_FLUTTER:f32 = 0.3;
const GLOW:f32 = 0.15;
const GLOW_ACTIVE:f32 = 0.5;
/// each item drawn: over the first `PRISE` of it the root prises it loose,
/// clods of the node flung up about its claw, then it swells up the root's
/// core in its own colour, home into the gourd
const PRISE:f32 = 0.3;
const CLODS = 4;
const CLOD_SIZE:f32 = 0.034;
const CLOD_FLING:f32 = 0.13;
const CLOD_OUT:f32 = 0.11;
/// what it has dug hangs in its gourd, in a ring, bobbing
const RING:f32 = 0.45;
const LUMP_R:f32 = 0.022;
const LUMP_GROW:f32 = 0.018;
const BOB:f32 = 0.008;
const TURN:f32 = 0.25;
/// its describe bar sits further right (a longer line) and is shorter
const BAR_X:f32 = 300;
const BAR_W:f32 = 60;

/// the node being worked: which side it lies on, what it yields, and how far
/// along the current item is.
pub const Dig = struct {
  dir:m.Dir,
  item:items.Item,
  t:f32 = 0,
};

pub const State = struct {
  /// null while there is no node beside it
  dig:?Dig = null,
  /// how far its digging root toward each side has reached (0..1)
  reach:[4]f32 = @splat(0),
};

/// it roots in living ground only.
pub fn ground(k:ck.Kind) bool { return k == .soil or k == .moss; }

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  const self = ctx.ss.get(i);
  _ = st.handOff(ctx, i);
  const d = &self.state.root_digger;
  const found = findNode(ctx.w, self.x, self.y, if (d.dig) |dg| dg.dir else 0);
  // its root reaches out to the node it works, and withers from any other
  for (&d.reach, 0..) |*r, k| {
    const there = if (found) |f| f.dir == k else false;
    r.* = if (there) @min(1, r.* + dt * ROOT_GROW / mesh.root.REACH) else @max(0, r.* - dt * ROOT_WITHER);
  }
  if (found == null) {
    d.dig = null;
    return false;
  }
  const f = found.?;
  if (d.dig == null or d.dig.?.dir != f.dir) d.dig = .{ .dir = f.dir, .item = f.item };
  const dg = &d.dig.?;
  if (self.inv.total() >= BUFFER) return false;
  dg.t += dt;
  if (dg.t < RATE) return true;
  dg.t -= RATE;
  f.chunk.res[f.tile] -= 1;
  _ = self.inv.add(dg.item, 1);
  return true;
}

const Found = struct {
  dir:m.Dir,
  item:items.Item,
  chunk:*ck.Chunk,
  tile:usize,
};

/// an unoccupied resource node beside (x, y), trying `prefer` first so a
/// digger stays on the node it is working.
fn findNode(w:*const World, x:i32, y:i32, prefer:m.Dir) ?Found {
  for (m.dirs) |k| {
    const dir = prefer +% k;
    const v = m.dirVec(dir);
    const c = w.chunkOfTile(x + v.x, y + v.z) orelse continue;
    const t = ck.localIndex(x + v.x, y + v.z);
    if (c.res[t] == 0 or c.occ[t] != .none) continue;
    const node = resources.of(c.kind[t]) orelse continue;
    return .{ .dir = dir, .item = node.item, .chunk = c, .tile = t };
  }
  return null;
}

pub fn wants(_:*const st.Structure, _:*const prog.Progression, _:items.Item) u32 { return 0; }

/// the oldest buffered item.
pub fn output(s:*const st.Structure) ?items.Item {
  for (s.inv.slot) |slot| if (slot) |it| return it.item;
  return null;
}

/// anything it has dug.
pub fn gives(s:*const st.Structure, item:items.Item) bool { return s.inv.count(item) > 0; }

/// its digging root, reaching to the node (or withering from one gone);
/// while it works each item is prised loose, clods flung up about the
/// claw, and swells up the root's core home into the gourd, where what it
/// has dug hangs. All but the root sway with the knot.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  const d = &s.state.root_digger;
  const dg = d.dig;
  const working = dg != null and s.inv.total() < BUFFER;
  const k = if (dg) |g| g.t / RATE else 0;
  for (d.reach, 0..) |r, side| {
    if (r <= 0) continue;
    const dir:m.Dir = @intCast(side);
    const on = working and dg.?.dir == dir and r >= 1;
    const v = m.dirVec(dir);
    const col:[4]u8 = if (dg) |g| g.item.info().col else .{0, 0, 0, 255};
    const c = color.Rgba8.of(col).toF4();
    try out.emit(.digger_root, m.chain(&.{m.translate(ctr), m.rotY(m.atan2(-m.f(v.z), m.f(v.x)))}), .{
      .glow = GLOW + GLOW_ACTIVE * s.activity, .flutter = ROOT_FLUTTER, .phase = s.seed + m.f(side) * 0.1, .grown = r * s.grown,
      .carry = if (on and k > PRISE) m.smooth((k - PRISE) / (1 - PRISE)) else -1, .carry_col = .{c[0], c[1], c[2]},
    });
    if (!on or k > PRISE) continue;
    // clods of the node flung up about the claw, falling back
    const node = ctr + m.v3(m.f(v.x), 0, m.f(v.z)) * m.splat3(mesh.root.REACH);
    const t = k / PRISE;
    for (0..CLODS) |j| {
      const a = m.ratio(j, CLODS) * m.tau + s.seed * 5 + m.f(j) * 0.7;
      const reach = CLOD_OUT * (0.7 + 0.3 * m.f(j % 2));
      const p = node + m.v3(@cos(a) * reach * t, CLOD_FLING * (0.8 + 0.2 * m.f(j % 3)) * 4 * t * (1 - t), @sin(a) * reach * t);
      const size = CLOD_SIZE * (0.75 + 0.25 * m.f(j % 2)) * (1 - m.smooth(m.clamp01((t - 0.85) / 0.15)));
      try out.emit(.digger_clod, m.chain(&.{m.translate(p), m.rotY(a + t * 4), m.rotX(t * 3 + m.f(j)), m.scale3(m.splat3(size))}), .{.phase = s.seed});
    }
  }
  // what it has dug, hanging in its gourd
  if (s.grown < 1) return;
  const base = s.place(ctr);
  var n:usize = 0;
  for (s.inv.slot) |slot| { if (slot != null) n += 1; }
  var j:usize = 0;
  for (s.inv.slot) |slot| {
    const it = slot orelse continue;
    const a = m.ratio(j, n) * m.tau + tf * TURN + s.seed * 6;
    const ring = if (n == 1) 0 else mesh.POD_R[0] * RING;
    const at = mesh.POD_AT + m.v3(@cos(a) * ring, BOB * @sin(tf * 0.9 + m.f(j) * 2), @sin(a) * ring);
    const r = LUMP_R + LUMP_GROW * m.ratio(it.n, BUFFER);
    try out.emit(.belly_lump, m.mul(base, m.chain(&.{m.translate(at), m.scale3(m.splat3(r))})), Look{
      .glow = GLOW, .phase = s.seed, .tint = color.Rgba8.of(it.item.info().col).toF4(),
      .sway = def.sway, .tall = def.tall, .drop = at[1],
    });
    j += 1;
  }
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  const n = s.inv.total();
  const dg = s.state.root_digger.dig orelse {
    _ = try d.print(x, y, style.text_body, style.dim, txt.s.describe.no_node, .{ n, BUFFER });
    return;
  };
  const what = if (n >= BUFFER) txt.s.describe.digger_full else txt.item(dg.item).name;
  _ = try d.print(x, y, style.text_body, style.white, txt.s.describe.digs, .{ what, n, BUFFER });
  try d.tendril(x + BAR_X, y + 2, BAR_W, style.bar_h, style.digger, dg.t / RATE, 0.4);
}

// ---- tests ----

/// tests tick structures at 20 Hz
const TEST_DT:f32 = 0.05;

/// a strip of soil at y = 0 (x = 0..5) with a moss node of `res` fibre at
/// (2, 0); the digger goes at (1, 0).
fn fixture(w:*World, res:ck.Res) !void {
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  var it = w.map.valueIterator();
  while (it.next()) |cp| @memset(&cp.*.res, 0);
  const c = w.chunkOfTile(0, 0).?;
  for (0..6) |x| for (0..2) |y| {
    const t = y * ck.SIZE + x;
    c.kind[t] = .soil;
    c.height[t] = 1;
    c.res[t] = 0;
  };
  c.kind[2] = .moss;
  c.res[2] = res;
}

fn run(ss:*st.Structures, w:*World, plants:*Plants, g:*prog.Progression, seconds:f32) !void {
  var t:f32 = 0;
  while (t < seconds) : (t += TEST_DT) try ss.tick(testing.allocator, w, plants, g, TEST_DT);
}

test "a digger beside a node draws one item every 4 seconds" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w, 5);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 1, 0, .root_digger, 0, 0));
  const id = ss.at(&w, 1, 0).?;
  try run(&ss, &w, &plants, &g, 3.9);
  try testing.expectEqual(@as(u32, 0), ss.get(id).inv.count(.fibre));
  try run(&ss, &w, &plants, &g, 8.2);
  try testing.expectEqual(@as(u32, 3), ss.get(id).inv.count(.fibre));
  try testing.expectEqual(@as(ck.Res, 2), w.chunkOfTile(2, 0).?.res[2]);
}

test "a digger with no node beside it idles" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w, 5);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 4, 1, .root_digger, 0, 0));
  try run(&ss, &w, &plants, &g, 20);
  const s = ss.get(ss.at(&w, 4, 1).?);
  try testing.expectEqual(@as(u32, 0), s.inv.total());
  try testing.expect(s.state.root_digger.dig == null);
  w.chunkOfTile(0, 0).?.kind[ck.SIZE + 3] = .stone;
  try testing.expect(!ss.canPlace(&w, 3, 1, .root_digger));
}

test "a digger with nowhere to send buffers 8, then pauses" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w, 20);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 1, 0, .root_digger, 0, 0));
  try run(&ss, &w, &plants, &g, 60);
  try testing.expectEqual(@as(u32, BUFFER), ss.get(ss.at(&w, 1, 0).?).inv.total());
  try testing.expectEqual(@as(ck.Res, 20 - BUFFER), w.chunkOfTile(2, 0).?.res[2]);
}

test "a conduit behind the digger carries its items away" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w, 6);
  const c = w.chunkOfTile(0, 0).?;
  c.kind[2] = .soil;
  c.res[2] = 0;
  c.kind[ck.SIZE + 1] = .moss;
  c.res[ck.SIZE + 1] = 6;
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 1, 0, .root_digger, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 0, .conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 3, 0, .sap_cache, 0, 0));
  const conduit = ss.at(&w, 2, 0).?;
  var carried = false;
  var t:f32 = 0;
  while (t < 30) : (t += 0.05) {
    try ss.tick(testing.allocator, &w, &plants, &g, 0.05);
    if (ss.get(conduit).state.conduit.held) |it| carried = carried or it == .fibre;
  }
  try testing.expect(carried);
  try testing.expect(ss.get(ss.at(&w, 3, 0).?).inv.count(.fibre) >= 6);
}

test "uprooting a digger returns its bulb and what it holds" {
  const gpa = testing.allocator;
  var g = try play.Game.init(gpa, play.DEFAULT_SEED);
  defer g.deinit();
  const at = m.tileAt(g.player.pos);
  const c = g.world.chunkOfTile(at[0], at[1]).?;
  c.kind[ck.localIndex(at[0], at[1])] = .soil;
  try testing.expect(try g.structs.place(gpa, &g.world, at[0], at[1], .root_digger, 0, 0));
  const id = g.structs.at(&g.world, at[0], at[1]).?;
  _ = g.structs.get(id).inv.add(.grit, 3);
  const grit = g.player.inv.count(.grit);
  actions.unbuild(&g, id);
  try testing.expectEqual(@as(u32, 1), g.player.inv.count(.root_digger));
  try testing.expectEqual(grit + 3, g.player.inv.count(.grit));
  try testing.expect(g.structs.at(&g.world, at[0], at[1]) == null);
}

/// its bulb: a small sprout above, roots reaching down from the seed to a
/// stone and a ley shard (it digs nodes).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  try ic.stem(.{.{-0.12, -0.62}, .{-0.25, -0.62}, .{-0.4, -0.55}, .{-0.5, -0.66}}, 0.11, icon_kit.root_col);
  try ic.stem(.{.{0.12, -0.62}, .{0.25, -0.66}, .{0.38, -0.55}, .{0.5, -0.62}}, 0.11, icon_kit.root_col);
  try ic.bud(.{-0.58, -0.7}, 0.19, icon_stone, 0.2);
  try ic.gem(.{0.6, -0.66}, 0.21, icon_ley);
  try ic.stem(.{.{0, icon_kit.TOP}, .{0, 0.25}, .{0.06, 0.35}, .{0.02, 0.45}}, 0.09, icon_kit.stem_col);
  try ic.leaf(.{0.02, 0.42}, 0.6, 0.3, 0.18, icon_kit.sprout, 0.9);
  try ic.leaf(.{0.02, 0.4}, m.pi - 0.6, 0.28, 0.17, icon_kit.sprout, 0.9);
  try ic.coat(col);
}
const icon_stone:Color = .{150, 140, 130, 255};
const icon_ley:Color = .{170, 120, 255, 255};
