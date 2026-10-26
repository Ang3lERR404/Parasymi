//! GATHERING CROWN: a symbiote that gathers for the garden. It sends a
//! woven root out to every plant on the tiles within two of it and, once a
//! root has reached its plant, gathers what that plant has ripened, a unit
//! at a time and each plant in turn, into the pod at its heart: one crown
//! harvests a whole bed, where conduits need a root beside every plant.
//! What it gathers goes to a neighbour that wants it, or a conduit behind
//! it pulls it away; with nowhere to go it holds `BUFFER`, then rests.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const m = lib.engine.core.math;
const color = lib.engine.core.color;
const ck = lib.ck;
const World = lib.world.World;
const items = lib.items;
const Plants = lib.plants.Plants;
const st = lib.structures;
const icon_kit = lib.icon;
const txt = lib.txt;
const prog = lib.progression;
const style = lib.style;
const Parts = lib.parts.Parts;
const Look = lib.parts.Look;
const Draw = lib.engine.ui.draw.Draw;
const Color = lib.engine.ui.draw.Color;
const meshlib = lib.meshlib;
const mesh = lib.gathering_crown;

const v3 = m.v3;

/// a ganglion grown beside it: the study of shared nerves
pub const meets:st.Meeting = .{ .kind = .ganglion, .found = .crown_and_nerve };
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes = .{ .belly_lump, .item_pod, .crown_root1, .crown_root2, .crown_root3, .crown_root4, .crown_root5 };

pub const def:st.Def = .{ .item = .gathering_crown, .size = 1, .mesh = .gathering_crown, .store = true, .grow = 5, .sway = 0.6, .tall = 0.45, .sap = 0.35 };

/// how far it reaches (tiles, every way), and the tiles that makes
pub const R = 2;
const SIDE = 2 * R + 1;
const TILES = SIDE * SIDE;
/// seconds between one gathering and the next, and most it holds
pub const GATHER:f32 = 1.5;
pub const BUFFER = 12;
/// how fast a root grows out to a plant (its length a second at one tile
/// out; farther ones take longer) and withers when the plant is gone
const ROOT_GROW:f32 = 0.5;
const ROOT_WITHER:f32 = 1.2;
const ROOT_FLUTTER:f32 = 0.3;
/// what it gathers travels up the root to the pod this fast (its length a
/// second), arcing this high
const CARRY_RATE:f32 = 1.5;
const ARC:f32 = 0.18;
const MOTE_SIZE:f32 = 0.45;
const MOTE_GLOW:f32 = 0.8;
/// what it holds hangs in the pod, in a ring, bobbing
const RING:f32 = 0.45;
const LUMP_R:f32 = 0.024;
const LUMP_GROW:f32 = 0.02;
const BOB:f32 = 0.01;
const TURN:f32 = 0.2;
const GLOW:f32 = 0.2;

pub const State = struct {
  /// how far its root toward each tile round it has grown (0..1), by
  /// `index` of the tile's offset
  reach:[TILES]f32 = @splat(0),
  /// the tile it gathers from next, and time since it last gathered
  turn:u8 = 0,
  t:f32 = 0,
  /// the last thing gathered, travelling up its root (from which tile,
  /// how far along, what)
  from:?u8 = null,
  carry:f32 = 0,
  carried:items.Item = .essence,
};

fn offset(i:usize) [2]i32 { return .{@as(i32, @intCast(i % SIDE)) - R, @as(i32, @intCast(i / SIDE)) - R}; }

/// the plant whose own tile (its corner, for one larger than a tile) is
/// `i` round (x, y), if any: one root to each plant
fn plantAt(ctx:st.Ctx, x:i32, y:i32, i:usize) ?ck.PlantId {
  const o = offset(i);
  if (o[0] == 0 and o[1] == 0) return null;
  const p = ctx.plants.at(ctx.w, x + o[0], y + o[1]) orelse return null;
  const s = ctx.plants.list.slice();
  if (s.items(.x)[p.idx()] != x + o[0] or s.items(.y)[p.idx()] != y + o[1]) return null;
  return p;
}

/// which root mesh reaches the tile at offset `o`
fn rootFor(o:[2]i32) meshlib.Id {
  const d2 = o[0] * o[0] + o[1] * o[1];
  return switch (d2) {
    1 => .crown_root1,
    2 => .crown_root2,
    4 => .crown_root3,
    5 => .crown_root4,
    else => .crown_root5,
  };
}

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  _ = st.handOff(ctx, i);
  const self = ctx.ss.get(i);
  const c = &self.state.gathering_crown;
  var roots:usize = 0;
  for (&c.reach, 0..) |*r, k| {
    const o = offset(k);
    const len = @sqrt(m.f(o[0] * o[0] + o[1] * o[1]));
    const there = plantAt(ctx, self.x, self.y, k) != null;
    r.* = if (there) @min(1, r.* + dt * ROOT_GROW / @max(len, 1)) else @max(0, r.* - dt * ROOT_WITHER);
    if (r.* >= 1) roots += 1;
  }
  if (c.from) |_| {
    c.carry += dt * CARRY_RATE;
    if (c.carry >= 1) c.from = null;
  }
  if (roots == 0 or self.inv.total() >= BUFFER) return false;
  c.t += dt;
  if (c.t < GATHER) return true;
  // each plant its root has reached, in turn
  for (0..TILES) |k| {
    const at:u8 = @intCast((c.turn + k) % TILES);
    if (c.reach[at] < 1) continue;
    const p = plantAt(ctx, self.x, self.y, at) orelse continue;
    const item = st.harvestOne(ctx.plants, p) orelse continue;
    _ = self.inv.add(item, 1);
    c.turn = @intCast((@as(usize, at) + 1) % TILES);
    c.t = 0;
    c.from = at;
    c.carry = 0;
    c.carried = item;
    return true;
  }
  // nothing ripe: it waits, ready
  c.t = GATHER;
  return false;
}

pub fn wants(_:*const st.Structure, _:*const prog.Progression, _:items.Item) u32 { return 0; }

/// the oldest thing it gathered.
pub fn output(s:*const st.Structure) ?items.Item {
  for (s.inv.slot) |slot| if (slot) |it| return it.item;
  return null;
}
pub fn gives(s:*const st.Structure, item:items.Item) bool { return s.inv.count(item) > 0; }

/// its roots out to the plants round it, what it last gathered travelling
/// up one, and what it holds hanging in its pod.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  const c = &s.state.gathering_crown;
  for (c.reach, 0..) |r, k| {
    if (r <= 0) continue;
    const o = offset(k);
    try out.emit(rootFor(o), m.chain(&.{m.translate(ctr), m.rotY(m.atan2(-m.f(o[1]), m.f(o[0])))}), .{
      .flutter = ROOT_FLUTTER, .phase = s.seed + m.f(k) * 0.07, .grown = r * s.grown, .glow = GLOW,
    });
  }
  if (s.grown < 1) return;
  const base = s.place(ctr);
  if (c.from) |k| {
    const o = offset(k);
    const from = ctr + v3(m.f(o[0]), 0.05, m.f(o[1]));
    const to = m.mulPoint(base, mesh.POD_AT);
    const p = m.lerpV(from, to, m.smooth(c.carry)) + v3(0, ARC * @sin(m.pi * c.carry), 0);
    try out.emit(.item_pod, m.chain(&.{m.translate(p), m.scale3(m.splat3(MOTE_SIZE * @sin(m.pi * m.clamp01(c.carry * 1.1 + 0.05))))}), .{
      .glow = MOTE_GLOW, .tint = color.Rgba8.of(c.carried.info().col).toF4(),
    });
  }
  var n:usize = 0;
  for (s.inv.slot) |slot| { if (slot != null) n += 1; }
  var j:usize = 0;
  for (s.inv.slot) |slot| {
    const it = slot orelse continue;
    const a = m.ratio(j, n) * m.tau + tf * TURN + s.seed * 6;
    const ring = if (n == 1) 0 else mesh.POD_R[0] * RING;
    const at = mesh.POD_AT + v3(@cos(a) * ring, BOB * @sin(tf * 0.9 + m.f(j) * 2), @sin(a) * ring);
    const r = LUMP_R + LUMP_GROW * m.ratio(it.n, BUFFER);
    try out.emit(.belly_lump, m.mul(base, m.chain(&.{m.translate(at), m.scale3(m.splat3(r))})), Look{
      .glow = GLOW, .phase = s.seed, .tint = color.Rgba8.of(it.item.info().col).toF4(),
      .sway = def.sway, .tall = def.tall, .drop = at[1],
    });
    j += 1;
  }
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  const c = &s.state.gathering_crown;
  var n:u32 = 0;
  for (c.reach) |r| { if (r >= 1) n += 1; }
  const held = s.inv.total();
  if (held >= BUFFER) {
    _ = try d.print(x, y, style.text_body, style.dim, txt.s.describe.crown_full, .{held, BUFFER});
    return;
  }
  _ = try d.print(x, y, style.text_body, if (n == 0) style.dim else style.white, txt.s.describe.gathers, .{n, held, BUFFER});
  try d.tendril(x + style.desc_bar_x, y + 2, style.desc_bar_w, style.bar_h, style.growth, c.t / GATHER, 0.3);
}

/// its bulb: a cupped crown of petals on a sprout out of the seed, roots
/// reaching out either side to small buds (it gathers from the plants
/// round it).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  for ([_]f32{-1, 1}) |sx| {
    try ic.stem(.{.{0.08 * sx, -0.6}, .{0.35 * sx, -0.5}, .{0.55 * sx, -0.62}, .{0.7 * sx, -0.5}}, 0.07, icon_kit.root_col);
    try ic.bud(.{0.72 * sx, -0.4}, 0.11, icon_kit.sprout, 0.5);
  }
  try ic.stem(.{.{0, icon_kit.TOP}, .{0.03, 0.3}, .{-0.03, 0.45}, .{0, 0.55}}, 0.1, icon_kit.stem_col);
  try ic.glow(.{0, 0.7}, 0.25, icon_glow);
  try ic.bud(.{0, 0.7}, 0.15, icon_sap, 0.7);
  for (0..5) |k| try ic.leaf(.{0, 0.6}, 0.35 + m.f(k) * 0.6, 0.32, 0.12, if (k % 2 == 0) icon_petal else icon_kit.sprout, 0.6);
  try ic.coat(col);
}
const icon_sap:Color = .{255, 190, 90, 255};
const icon_glow:Color = .{255, 190, 90, 80};
const icon_petal:Color = .{245, 190, 100, 255};

// ---- tests ----

const TEST_DT:f32 = 0.05;

fn fixture(w:*World) !void {
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..7) |x| for (0..7) |y| {
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

fn ripe(gpa:Allocator, w:*World, plants:*Plants, x:i32, y:i32, essence:f32) !void {
  try testing.expect(try plants.placeEx(gpa, w, x, y, .{ .x = x, .y = y, .chunk = undefined, .tile = undefined, .sp = .lumenroot, .seed = 0, .growth = 1, .essence = essence }));
}

test "a gathering crown roots out to every plant within two tiles and gathers them" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 3, 3, .gathering_crown, 0, 0));
  // beside, on a diagonal, two out, and the far corner; one too far
  try ripe(gpa, &w, &plants, 4, 3, 2);
  try ripe(gpa, &w, &plants, 2, 2, 2);
  try ripe(gpa, &w, &plants, 3, 5, 2);
  try ripe(gpa, &w, &plants, 1, 1, 2);
  try ripe(gpa, &w, &plants, 6, 3, 2);
  try run(&ss, &w, &plants, &g, 30);
  const id = ss.at(&w, 3, 3).?;
  try testing.expectEqual(@as(u32, 8), ss.get(id).inv.count(.essence));
  // the one three tiles out is left alone
  const far = plants.at(&w, 6, 3).?;
  try testing.expectEqual(@as(f32, 2), plants.list.items(.essence)[far.idx()]);
}

test "a gathering crown hands what it gathers to a cache beside it" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 3, 3, .gathering_crown, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 3, 4, .sap_cache, 0, 0));
  try ripe(gpa, &w, &plants, 5, 3, 20);
  try run(&ss, &w, &plants, &g, 40);
  try testing.expect(ss.get(ss.at(&w, 3, 4).?).inv.count(.essence) >= 15);
  try testing.expectEqual(@as(u32, 0), ss.get(ss.at(&w, 3, 3).?).inv.total());
}
