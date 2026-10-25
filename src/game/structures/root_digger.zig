//! ROOT-DIGGER: the first gathering automation. Its roots work the resource
//! node beside it, drawing out one item at a time (the same item the wolf
//! would gather there) into a small buffer. Conduits behind it pull from
//! that buffer; any other structure beside it that wants the item is fed
//! directly. When the node runs dry it idles, and it takes up any node that
//! appears beside it later by itself.
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

pub const def:st.Def = .{ .item = .root_digger, .size = 1, .mesh = .root_digger, .store = true, .grow = 4, .sway = 0.5, .tall = 0.6 };

/// seconds per item drawn from the node
pub const RATE:f32 = 4;
/// items it holds before it stops digging
pub const BUFFER = 8;
/// roots radiating from the knot (see `emit`)
const ROOTS = 6;
/// idle roots breathe this deep at this tempo; roots facing the node
/// (within 60 degrees) stretch by `STRETCH` with each item drawn
const BREATH:f32 = 0.02;
const BREATH_RATE:f32 = 1.3;
const FACING:f32 = 0.5;
const STRETCH:f32 = 0.15;
/// each root's size varies by `SIZE_SPREAD` about `SIZE_MIN` (it grows out
/// along its spline with the digger, `grown`)
const SIZE_MIN:f32 = 0.9;
const SIZE_SPREAD:f32 = 0.2;
const GLOW:f32 = 0.2;
const GLOW_ACTIVE:f32 = 0.6;
/// the item drawn in arcs from `ARC_BASE` up by `ARC`, carried at this size
const ARC_BASE:f32 = 0.12;
const ARC:f32 = 0.15;
const MOTE_SIZE:f32 = 0.5;
const MOTE_GLOW:f32 = 0.9;
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
};

/// it roots in living ground only.
pub fn ground(k:ck.Kind) bool { return k == .soil or k == .moss; }

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  const self = ctx.ss.get(i);
  handOff(ctx, i);
  const d = &self.state.root_digger;
  const found = findNode(ctx.w, self.x, self.y, if (d.dig) |dg| dg.dir else 0) orelse {
    d.dig = null;
    return false;
  };
  if (d.dig == null or d.dig.?.dir != found.dir) d.dig = .{ .dir = found.dir, .item = found.item };
  const dg = &d.dig.?;
  if (self.inv.total() >= BUFFER) return false;
  dg.t += dt;
  if (dg.t < RATE) return true;
  dg.t -= RATE;
  found.chunk.res[found.tile] -= 1;
  _ = self.inv.add(dg.item, 1);
  return true;
}

/// feed the next buffered item to a neighbour that wants it. Carriers are
/// left alone: one behind the digger pulls through `output` itself.
fn handOff(ctx:st.Ctx, i:st.Id) void {
  const self = ctx.ss.get(i);
  const item = output(self) orelse return;
  for (m.dirs) |d| {
    const v = m.dirVec(d);
    const j = ctx.ss.at(ctx.w, self.x + v.x, self.y + v.z) orelse continue;
    if (ctx.ss.get(j).def().carrier) continue;
    if (ctx.ss.insert(ctx.g, j, item, 1) == 1) {
      _ = self.inv.take(item, 1);
      return;
    }
  }
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

/// roots radiating from the knot; those facing the node stretch toward it
/// in time with each item drawn, and a mote of it travels in. Idle roots
/// only breathe.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  const dg = s.state.root_digger.dig;
  const working = dg != null and s.inv.total() < BUFFER;
  const k = if (dg) |d| d.t / RATE else 0;
  const node_yaw = if (dg) |d| m.dirYaw(d.dir) else 0;
  for (0..ROOTS) |r| {
    const yaw = m.ratio(r, ROOTS) * m.tau + s.seed * 2;
    const breathe = 1 + BREATH * @sin(tf * BREATH_RATE + m.f(r) * 1.7);
    const facing = working and @cos(m.angleDiff(yaw, node_yaw)) > FACING;
    const reach = if (facing) 1 + STRETCH * (0.5 - 0.5 * @cos(k * m.tau)) else breathe;
    const size = SIZE_MIN + SIZE_SPREAD * @abs(@sin(s.seed * 13 + m.f(r) * 2.3));
    try out.emit(.digger_root, m.chain(&.{
      m.translate(ctr),
      m.rotY(yaw),
      m.scale3(m.v3(reach * size, size, size)),
    }), .{ .glow = GLOW + GLOW_ACTIVE * s.activity, .phase = s.seed, .grown = s.grown });
  }
  if (!working) return;
  const d = dg.?;
  const v = m.dirVec(d.dir);
  const from = ctr + m.v3(m.f(v.x), 0, m.f(v.z));
  const p = m.lerpV(from, ctr, k) + m.v3(0, ARC_BASE + ARC * @sin(k * m.pi), 0);
  try out.emit(.item_pod, m.chain(&.{
    m.translate(p),
    m.scale3(m.splat3(MOTE_SIZE)),
  }), .{ .glow = MOTE_GLOW, .tint = color.Rgba8.of(d.item.info().col).toF4() });
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
