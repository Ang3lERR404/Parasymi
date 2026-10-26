//! BRAIDED CONDUIT: a root conduit grown dense, four cores bound in one
//! weave, each core a lane of its own. Each lane carries one kind of item
//! at a time, so up to four kinds travel side by side through one tile and
//! never wait on one another, and it carries faster than a conduit. It
//! pulls what is behind it one kind to a lane (whatever that structure
//! lets go, `gives`), takes in what conduits and braided conduits feed it,
//! and passes each lane's item forward on its own: into a conduit ahead of
//! it, the next braided conduit, or any structure that wants it.
//! It chains and turns as conduits do, its arches joining theirs under the
//! ground.
const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const m = @import("engine").core.math;
const ck = @import("../../world/chunk.zig");
const World = @import("../../world/world.zig").World;
const items = @import("../../sim/items.zig");
const Plants = @import("../../sim/plants.zig").Plants;
const st = @import("../structures.zig");
const icon_kit = @import("../icon.zig");
const txt = @import("../text.zig");
const prog = @import("../progression.zig");
const color = @import("engine").core.color;
const style = @import("../style.zig");
const Parts = @import("../parts.zig").Parts;
const Draw = @import("engine").ui.draw.Draw;
const Color = @import("engine").ui.draw.Color;
const meshlib = @import("../../gfx/meshlib.zig");
const mesh = @import("../../gfx/meshes/braided_conduit.zig");

/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes = .{ .braid_wrap, .braid_wrap_left, .braid_wrap_right, .braid_lane0, .braid_lane1, .braid_lane2, .braid_lane3, .braid_lane0_left, .braid_lane1_left, .braid_lane2_left, .braid_lane3_left, .braid_lane0_right, .braid_lane1_right, .braid_lane2_right, .braid_lane3_right };

/// decision: like a conduit, it grows along its arches' growth splines but
/// never sways (its arches join the next one's under the ground) and draws
/// its own arches, one per edge it is fed from; `mesh` is its preview.
pub const def:st.Def = .{ .item = .braided_conduit, .size = 1, .mesh = .braided_conduit, .grow = 2, .carrier = true, .bare = true, .tall = 0.3 };

/// a sporecaster grown beside it: the study of braided drift
pub const meets:st.Meeting = .{ .kind = .sporecaster, .found = .braid_and_spore };

pub const LANES = mesh.LANES;
/// tiles per second a lane carries (a conduit carries 2.5)
pub const SPEED:f32 = 3.5;
/// the arch (its weave and each lane's core) by the edge it comes in at,
/// counted from the way it faces: 1 the side +Z of it, 2 behind, 3 the
/// other side (as a conduit's)
const WRAP = [4]?meshlib.Id{null, .braid_wrap_left, .braid_wrap, .braid_wrap_right};
const LANE_MESH = [4][LANES]meshlib.Id{
  .{.braid_lane0, .braid_lane1, .braid_lane2, .braid_lane3},
  .{.braid_lane0_left, .braid_lane1_left, .braid_lane2_left, .braid_lane3_left},
  .{.braid_lane0, .braid_lane1, .braid_lane2, .braid_lane3},
  .{.braid_lane0_right, .braid_lane1_right, .braid_lane2_right, .braid_lane3_right},
};
const BEHIND:m.Dir = 2;
/// an item waiting for room ahead shows here, where its lane goes down
const WAIT_AT:f32 = 0.86;
const FLUTTER:f32 = 0.5;

pub const Lane = struct {
  /// the kind it carries (held in the inventory: one of each at most),
  /// how far along it is (0..1), and the edge it came in by
  item:?items.Item = null,
  t:f32 = 0,
  came:m.Dir = BEHIND,
};

pub const State = struct {
  lanes:[LANES]Lane = @splat(.{}),
  /// the edges it is fed at (bit per edge counted from the way it faces)
  feeds:u8 = 1 << BEHIND,
  /// an item handed in by a carrier this tick: the edge it came by
  came:m.Dir = BEHIND,
};

fn bit(r:m.Dir) u8 { return @as(u8, 1) << r; }

/// which edges its arches come up at: from each carrier facing into it,
/// and from behind when anything else stands there or nothing feeds it.
pub fn link(ctx:st.Ctx, i:st.Id) void {
  const self = ctx.ss.get(i);
  var feeds:u8 = 0;
  for ([_]m.Dir{1, 2, 3}) |r| {
    const d = self.dir +% r;
    const v = m.dirVec(d);
    const j = ctx.ss.at(ctx.w, self.x + v.x, self.y + v.z) orelse continue;
    const t = ctx.ss.get(j);
    if (t.def().carrier) {
      if (t.dir == d +% 2) feeds |= bit(r);
    } else if (r == BEHIND) feeds |= bit(r);
  }
  self.state.braided_conduit.feeds = if (feeds == 0) bit(BEHIND) else feeds;
}

fn laneOf(s:*const st.Structure, item:items.Item) ?usize {
  for (s.state.braided_conduit.lanes, 0..) |l, k| if (l.item == item) return k;
  return null;
}

/// one more of an item it carries in no lane yet, while a lane is free.
pub fn wants(s:*const st.Structure, _:*const prog.Progression, item:items.Item) u32 {
  if (s.inv.count(item) > 0 or laneOf(s, item) != null) return 0;
  var kinds:usize = 0;
  for (s.inv.slot) |slot| { if (slot != null) kinds += 1; }
  return if (kinds < LANES) 1 else 0;
}

/// keep the lanes to what it holds: one taken out of it (by the gardener)
/// leaves its lane, one handed in takes a free lane.
fn reconcile(s:*st.Structure) void {
  const b = &s.state.braided_conduit;
  for (&b.lanes) |*l| if (l.item) |it| if (s.inv.count(it) == 0) {
    l.* = .{};
  };
  for (s.inv.slot) |slot| {
    const it = (slot orelse continue).item;
    if (laneOf(s, it) != null) continue;
    for (&b.lanes) |*l| if (l.item == null) {
      l.* = .{.item = it, .came = b.came};
      break;
    };
  }
  b.came = BEHIND;
}

/// fill free lanes from what is behind it, one kind to a lane.
fn pull(ctx:st.Ctx, self:*st.Structure) void {
  const v = m.dirVec(self.dir +% BEHIND);
  const j = ctx.ss.at(ctx.w, self.x + v.x, self.y + v.z) orelse return;
  const from = ctx.ss.get(j);
  if (from.def().carrier) return; // carriers push, they are never pulled
  for (from.inv.slot) |slot| {
    const it = (slot orelse continue).item;
    if (wants(self, ctx.g, it) == 0 or !ctx.ss.gives(j, it)) continue;
    if (!from.inv.take(it, 1)) continue;
    _ = self.inv.add(it, 1);
    self.state.braided_conduit.came = BEHIND;
    reconcile(self);
  }
}

/// hand a lane's item to what is ahead: a conduit's free core, the next
/// carrier, or a structure that wants it. Returns whether it went.
fn pass(ctx:st.Ctx, self:*st.Structure, item:items.Item) bool {
  const v = m.dirVec(self.dir);
  const j = ctx.ss.at(ctx.w, self.x + v.x, self.y + v.z) orelse return false;
  const t = ctx.ss.get(j);
  if (t.def().carrier) {
    const back = m.dirVec(t.dir);
    // never hand back into a carrier facing us
    if (back.x == -v.x and back.z == -v.z) return false;
  }
  // (it comes in at the edge facing this one)
  return ctx.ss.handIn(ctx.g, j, item, (self.dir +% 2) -% t.dir);
}

/// take an item handed in at `edge` into a free lane, if it carries none
/// of it yet.
pub fn receive(s:*st.Structure, g:*const prog.Progression, item:items.Item, edge:m.Dir) bool {
  if (wants(s, g, item) == 0 or s.inv.add(item, 1) < 1) return false;
  s.state.braided_conduit.came = edge;
  reconcile(s);
  return true;
}

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  const self = ctx.ss.get(i);
  reconcile(self);
  pull(ctx, self);
  var busy = false;
  for (&self.state.braided_conduit.lanes) |*l| {
    const it = l.item orelse continue;
    busy = true;
    l.t = @min(1, l.t + dt * SPEED);
    if (l.t < 1) continue;
    if (pass(ctx, self, it)) {
      _ = self.inv.take(it, 1);
      l.* = .{};
    }
  }
  return busy;
}

/// an item at the end of its lane, waiting for room ahead.
pub fn output(s:*const st.Structure) ?items.Item {
  for (s.state.braided_conduit.lanes) |l| if (l.item) |it| if (l.t >= 1) return it;
  return null;
}
pub fn gives(s:*const st.Structure, item:items.Item) bool {
  const k = laneOf(s, item) orelse return false;
  return s.state.braided_conduit.lanes[k].t >= 1;
}

/// its arches, one up out of the soil from each edge it is fed at: the
/// weave and the four cores, each lane's item running through its own core
/// in the arch it came in by.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, _:f32) Allocator.Error!void {
  const b = &s.state.braided_conduit;
  const place = m.chain(&.{m.translate(ctr), m.rotY(m.dirYaw(s.dir))});
  var busy:f32 = 0;
  for (b.lanes) |l| if (l.item != null) { busy += 1.0 / @as(f32, LANES); };
  const glow = @max(s.activity * 0.5, busy);
  // what came in by an edge with no arch runs through the first
  const first:m.Dir = @intCast(@ctz(b.feeds));
  for (WRAP, 0..) |id, r| {
    if (b.feeds & bit(@intCast(r)) == 0) continue;
    try out.emit(id.?, place, .{.glow = glow, .flutter = FLUTTER, .phase = s.seed, .grown = s.grown});
    for (b.lanes, 0..) |l, k| {
      const by = if (b.feeds & bit(l.came) != 0) l.came else first;
      const carry = if (l.item != null and r == by) (if (l.t >= 1) WAIT_AT else l.t) else -1;
      const col = if (l.item) |it| color.Rgba8.of(it.info().col).toF4() else [4]f32{0, 0, 0, 0};
      try out.emit(LANE_MESH[r][k], place, .{.glow = glow, .phase = s.seed + m.f(k) * 0.17, .grown = s.grown, .carry = carry, .carry_col = .{col[0], col[1], col[2]}});
    }
  }
}

pub fn release(s:*st.Structure) ?items.Item {
  s.state.braided_conduit.lanes = @splat(.{});
  return null;
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  var names:[LANES][]const u8 = undefined;
  for (s.state.braided_conduit.lanes, &names) |l, *n| n.* = if (l.item) |it| txt.item(it).short else txt.s.describe.lane_empty;
  _ = try d.print(x, y, style.text_body, style.white, txt.s.describe.lanes, .{names[0], names[1], names[2], names[3]});
}

/// its bulb: four roots braided together, arching out of the seed and
/// diving back in, beads of four colours running along them (it carries
/// four things at once).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const arch = [4]icon_kit.P{.{0, icon_kit.TOP}, .{-0.15, 0.66}, .{0.8, 0.94}, .{0.72, 0.02}};
  for (0..LANES) |k| {
    const o = (m.f(k) - 1.5) * 0.045;
    try ic.stem(.{.{arch[0][0] + o, arch[0][1]}, .{arch[1][0] + o, arch[1][1] + o}, .{arch[2][0] - o, arch[2][1] + o}, .{arch[3][0] - o, arch[3][1]}}, 0.06, icon_kit.root_col);
  }
  try ic.leaf(.{-0.04, 0.34}, 2.5, 0.3, 0.17, icon_kit.sprout, 0.9);
  try ic.leaf(.{0.5, 0.86}, 0.6, 0.26, 0.15, icon_kit.sprout, 0.9);
  for (icon_beads, 0..) |c, k| {
    const t = @mod(ic.t * ICON_RUN + ic.phase + m.f(k) * 0.25, 1);
    try ic.bud(icon_kit.curve(arch, t), 0.075, c, @sin(t * m.pi));
  }
  try ic.coat(col);
}
const icon_beads = [_]Color{.{255, 215, 120, 255}, .{120, 170, 90, 255}, .{170, 120, 255, 255}, .{150, 140, 130, 255}};
const ICON_RUN:f32 = 0.4;

// ---- tests ----

const TEST_DT:f32 = 0.05;

fn fixture(w:*World) !void {
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..8) |x| for (0..3) |y| {
    const t = y * ck.SIZE + x;
    c.kind[t] = .soil;
    c.height[t] = 1;
    c.res[t] = 0;
  };
}

fn run(ss:*st.Structures, w:*World, plants:*Plants, g:*prog.Progression, seconds:f32) !void {
  var t:f32 = 0;
  while (t < seconds) : (t += TEST_DT) try ss.tick(testing.allocator, w, plants, g, TEST_DT);
}

test "a braided conduit carries four kinds side by side, each in its own lane" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  // cache -> braid -> braid -> cache, left to right
  try testing.expect(try ss.place(gpa, &w, 0, 0, .sap_cache, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 1, 0, .braided_conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 0, .braided_conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 3, 0, .sap_cache, 0, 0));
  const src = ss.at(&w, 0, 0).?;
  for ([_]items.Item{.essence, .fibre, .grit, .ley_shard}) |it| _ = ss.insert(&g, src, it, 10);
  // one tick: four lanes, one kind each
  try ss.tick(gpa, &w, &plants, &g, TEST_DT);
  const b = ss.get(ss.at(&w, 1, 0).?);
  var kinds:usize = 0;
  for (b.state.braided_conduit.lanes) |l| { if (l.item != null) kinds += 1; }
  try testing.expectEqual(@as(usize, LANES), kinds);
  try testing.expectEqual(@as(u32, LANES), b.inv.total());
  try run(&ss, &w, &plants, &g, 12);
  const dst = ss.get(ss.at(&w, 3, 0).?);
  for ([_]items.Item{.essence, .fibre, .grit, .ley_shard}) |it| try testing.expectEqual(@as(u32, 10), dst.inv.count(it));
}

test "a braided conduit hands on into a conduit and takes from one" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  // cache -> conduit -> braid -> conduit -> cache
  try testing.expect(try ss.place(gpa, &w, 0, 0, .sap_cache, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 1, 0, .conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 0, .braided_conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 3, 0, .conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 4, 0, .sap_cache, 0, 0));
  _ = ss.insert(&g, ss.at(&w, 0, 0).?, .fibre, 5);
  _ = ss.insert(&g, ss.at(&w, 0, 0).?, .grit, 5);
  try run(&ss, &w, &plants, &g, 20);
  const dst = ss.get(ss.at(&w, 4, 0).?);
  try testing.expectEqual(@as(u32, 5), dst.inv.count(.fibre));
  try testing.expectEqual(@as(u32, 5), dst.inv.count(.grit));
  // the conduit feeding it comes up behind it: its arch is there
  try testing.expect(ss.get(ss.at(&w, 2, 0).?).state.braided_conduit.feeds == bit(BEHIND));
}

test "a braided conduit turns: fed from the side, it hands on ahead" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  // a braid at (1,0) facing +z into a braid at (1,1) facing +x, into a cache at (2,1)
  try testing.expect(try ss.place(gpa, &w, 1, 0, .braided_conduit, 1, 0));
  try testing.expect(try ss.place(gpa, &w, 1, 1, .braided_conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 1, .sap_cache, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 1, 2, .sap_cache, 0, 0));
  _ = ss.insert(&g, ss.at(&w, 1, 0).?, .essence, 1);
  try run(&ss, &w, &plants, &g, 3);
  try testing.expectEqual(@as(u32, 1), ss.get(ss.at(&w, 2, 1).?).inv.count(.essence));
  try testing.expectEqual(@as(u32, 0), ss.get(ss.at(&w, 1, 2).?).inv.count(.essence));
  // (fed from its -z side: the edge three quarters round from the way it faces)
  try testing.expect(ss.get(ss.at(&w, 1, 1).?).state.braided_conduit.feeds == bit(3));
}
