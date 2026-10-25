//! GANGLION: a parasite's nerve knot that shares out what it is fed. Fed by
//! conduits (or the gardener), it holds a few things in its bladder and
//! hands them on, one at a time and in turn, to every neighbour that will
//! take one: any structure beside it that wants it (so one line can feed
//! several germinators or arsthraxias, each only what it needs), and any
//! carrier leading away from it, which splits a line two or three ways.
//! It never hands back into a carrier facing into it. A nerve grows out to
//! each neighbour it feeds, and a pulse of what it hands on runs out along
//! it.
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
const style = @import("../style.zig");
const Parts = @import("../parts.zig").Parts;
const Look = @import("../parts.zig").Look;
const Draw = @import("../../ui/draw.zig").Draw;
const Color = @import("../../ui/draw.zig").Color;
const mesh = @import("../../gfx/meshes/ganglion.zig");

const v3 = m.v3;

/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes = .{ .belly_lump, .ganglion_nerve };

pub const def:st.Def = .{ .item = .ganglion, .size = 1, .mesh = .ganglion, .store = true, .grow = 4, .sway = 0.4, .tall = 0.45, .sap = 0.3, .pale = true };

/// most it holds at once, and seconds between one hand-off and the next
pub const HOLD = 8;
pub const PASS:f32 = 0.35;
/// how fast a nerve grows out to a neighbour it may feed, and withers
const NERVE_GROW:f32 = 0.8;
const NERVE_WITHER:f32 = 1.2;
/// a pulse runs out along a nerve this fast (its length a second)
const PULSE_RATE:f32 = 3;
/// what it holds hangs in its bladder: in a ring this far out, bobbing
const RING:f32 = 0.45;
const LUMP_R:f32 = 0.022;
const LUMP_GROW:f32 = 0.02;
const BOB:f32 = 0.01;
const TURN:f32 = 0.3;
const GLOW:f32 = 0.2;

pub const State = struct {
  /// the side it hands on to next (round them in turn)
  turn:u8 = 0,
  t:f32 = 0,
  /// how far its nerve toward each side has grown (0..1), by world direction
  reach:[4]f32 = @splat(0),
  /// a pulse running out along each nerve (0 just sent .. 1 arrived, or
  /// none) and the item it carries
  pulse:[4]?f32 = @splat(null),
  sent:[4]items.Item = @splat(.essence),
};

/// whether the neighbour on side `d` may be fed (by a carrier: only one
/// not facing into it)
fn feeds(ctx:st.Ctx, self:*const st.Structure, d:m.Dir) ?st.Id {
  const v = m.dirVec(d);
  const j = ctx.ss.at(ctx.w, self.x + v.x, self.y + v.z) orelse return null;
  const t = ctx.ss.get(j);
  if (t.def().carrier and t.dir == d +% 2) return null;
  return j;
}

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  const self = ctx.ss.get(i);
  const gs = &self.state.ganglion;
  for (m.dirs) |d| {
    const r = &gs.reach[d];
    r.* = if (feeds(ctx, self, d) != null) @min(1, r.* + dt * NERVE_GROW) else @max(0, r.* - dt * NERVE_WITHER);
    if (gs.pulse[d]) |*p| {
      p.* += dt * PULSE_RATE;
      if (p.* >= 1) gs.pulse[d] = null;
    }
  }
  if (self.inv.total() == 0) return false;
  gs.t += dt;
  if (gs.t < PASS) return true;
  // round the sides in turn, each offered what it holds
  for (0..4) |k| {
    const d:m.Dir = @intCast((gs.turn + k) % 4);
    if (gs.reach[d] < 1) continue;
    const j = feeds(ctx, self, d) orelse continue;
    const t = ctx.ss.get(j);
    for (self.inv.slot) |slot| {
      const it = (slot orelse continue).item;
      if (!ctx.ss.handIn(ctx.g, j, it, (d +% 2) -% t.dir)) continue;
      _ = self.inv.take(it, 1);
      gs.pulse[d] = 0;
      gs.sent[d] = it;
      gs.turn = @intCast((@as(usize, d) + 1) % 4);
      gs.t = 0;
      return true;
    }
  }
  // nobody took anything: try again next tick
  return true;
}

/// anything, while it has room.
pub fn wants(s:*const st.Structure, _:*const prog.Progression, _:items.Item) u32 { return HOLD -| s.inv.total(); }

/// its nerves out to the neighbours it feeds, a pulse of what it hands on
/// running out along each, and what it holds hanging in its bladder.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  const gs = &s.state.ganglion;
  for (gs.reach, 0..) |r, d| {
    if (r <= 0) continue;
    const carry = gs.pulse[d] orelse -1;
    const col = color.Rgba8.of(gs.sent[d].info().col).toF4();
    try out.emit(.ganglion_nerve, m.chain(&.{m.translate(ctr), m.rotY(m.dirYaw(@intCast(d)))}), .{
      .glow = GLOW, .phase = s.seed + m.f(d) * 0.2, .grown = r * s.grown, .carry = carry, .carry_col = .{col[0], col[1], col[2]},
    });
  }
  if (s.grown < 1) return;
  var n:usize = 0;
  for (s.inv.slot) |slot| { if (slot != null) n += 1; }
  var k:usize = 0;
  const base = s.place(ctr);
  for (s.inv.slot) |slot| {
    const it = slot orelse continue;
    const a = m.ratio(k, n) * m.tau + tf * TURN + s.seed * 6;
    const ring = if (n == 1) 0 else mesh.HEART_R[0] * RING;
    const at = mesh.HEART + v3(@cos(a) * ring, BOB * @sin(tf * 1.1 + m.f(k) * 2), @sin(a) * ring);
    const r = LUMP_R + LUMP_GROW * m.ratio(it.n, HOLD);
    try out.emit(.belly_lump, m.mul(base, m.chain(&.{m.translate(at), m.scale3(m.splat3(r))})), Look{
      .glow = GLOW, .phase = s.seed, .tint = color.Rgba8.of(it.item.info().col).toF4(),
      .sway = def.sway, .tall = def.tall, .drop = at[1],
    });
    k += 1;
  }
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  var n:u32 = 0;
  for (s.state.ganglion.reach) |r| { if (r >= 1) n += 1; }
  const col = if (n == 0) style.dim else style.white;
  _ = try d.print(x, y, style.text_body, col, txt.s.describe.shares, .{n, s.inv.total(), HOLD});
}

/// its bulb: a pale knot on a short stalk out of the seed, nerves reaching
/// out either side with beads running along them (it shares things out).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  for ([_]f32{-1, 1}) |sx| {
    const nerve = [4]icon_kit.P{.{0.05 * sx, 0.55}, .{0.35 * sx, 0.62}, .{0.6 * sx, 0.5}, .{0.78 * sx, 0.2}};
    try ic.stem(nerve, 0.06, icon_nerve);
    const k = @mod(ic.t * 0.8 + ic.phase + (if (sx < 0) @as(f32, 0.5) else 0), 1);
    try ic.bud(icon_kit.curve(nerve, k), 0.07, icon_bead, @sin(k * m.pi));
  }
  try ic.stem(.{.{0, icon_kit.TOP}, .{0.04, 0.25}, .{-0.03, 0.4}, .{0, 0.5}}, 0.1, icon_skin);
  try ic.glow(.{0, 0.62}, 0.26, icon_sac_glow);
  try ic.bud(.{0, 0.62}, 0.2, icon_sac, 0.3);
  for (0..5) |k| {
    const a = m.ratio(k, 5) * m.tau;
    try ic.bud(.{@cos(a) * 0.2, 0.6 + @sin(a) * 0.16}, 0.075, icon_skin, 0.1);
  }
  try ic.coat(col);
}
const icon_skin:Color = .{190, 182, 205, 255};
const icon_nerve:Color = .{175, 160, 210, 255};
const icon_sac:Color = .{120, 160, 220, 200};
const icon_sac_glow:Color = .{120, 160, 220, 70};
const icon_bead:Color = .{255, 215, 120, 255};

// ---- tests ----

const TEST_DT:f32 = 0.05;

fn fixture(w:*World) !void {
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..6) |x| for (0..5) |y| {
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

test "a ganglion splits a conduit line, never back into it" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  // cache > conduit > ganglion at (2,2); conduits lead away north, east
  // and south into a cache each
  try testing.expect(try ss.place(gpa, &w, 0, 2, .sap_cache, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 1, 2, .conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 2, .ganglion, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 3, 2, .conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 4, 2, .sap_cache, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 1, .conduit, 3, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 0, .sap_cache, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 3, .conduit, 1, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 4, .sap_cache, 0, 0));
  _ = ss.insert(&g, ss.at(&w, 0, 2).?, .fibre, 30);
  try run(&ss, &w, &plants, &g, 40);
  for ([_][2]i32{.{4, 2}, .{2, 0}, .{2, 4}}) |o| {
    const n = ss.get(ss.at(&w, o[0], o[1]).?).inv.count(.fibre);
    try testing.expect(n >= 8 and n <= 12);
  }
  try testing.expectEqual(@as(u32, 0), ss.get(ss.at(&w, 0, 2).?).inv.count(.fibre));
}

test "a ganglion feeds each neighbour only what it wants" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  // a ganglion between two loomferns (they want essence, nothing else)
  w.chunkOfTile(0, 0).?.kind[2 * ck.SIZE + 1] = .moss;
  w.chunkOfTile(0, 0).?.kind[2 * ck.SIZE + 3] = .moss;
  try testing.expect(try ss.place(gpa, &w, 2, 2, .ganglion, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 1, 2, .loomfern, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 3, 2, .loomfern, 0, 0));
  const id = ss.at(&w, 2, 2).?;
  try testing.expectEqual(@as(u16, 4), ss.insert(&g, id, .essence, 4));
  try testing.expectEqual(@as(u16, 4), ss.insert(&g, id, .grit, 4));
  try testing.expectEqual(@as(u16, 0), ss.insert(&g, id, .grit, 1));
  try run(&ss, &w, &plants, &g, 6);
  // the essence shared out between them, the grit kept
  try testing.expectEqual(@as(u32, 0), ss.get(id).inv.count(.essence));
  try testing.expectEqual(@as(u32, 4), ss.get(id).inv.count(.grit));
  try testing.expect(ss.get(ss.at(&w, 1, 2).?).inv.count(.essence) >= 1);
  try testing.expect(ss.get(ss.at(&w, 3, 2).?).inv.count(.essence) >= 1);
}
