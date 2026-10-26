//! LITHOPHAGE: a parasite that eats stone. Its roots reach into the
//! mineral nodes on the eight tiles round it (grit on soil and stone,
//! shards on ley lines) and draw them up, one at a time, into its crop,
//! where they condense into a crystal; ley shards fed to it go the same
//! way. Once the crystal is whole it is sapped away: it runs out of the
//! crop's lip as a stream of mineral grit, item by item, into the cup on
//! its foot, where conduits pull it or neighbours that want it take it.
//! It gathers from every node round it at once, and a ley shard it eats
//! comes out as three grit.
// decision: it is fed ley shards only: grit it holds is always grit it
// has sapped (what leaves it), never grit it would eat again
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
const resources = lib.resources;
const style = lib.style;
const Parts = lib.parts.Parts;
const Look = lib.parts.Look;
const Draw = lib.engine.ui.draw.Draw;
const Color = lib.engine.ui.draw.Color;
const mesh = lib.lithophage;
const meshlib = lib.meshlib;

const V3 = m.V3;
const v3 = m.v3;

/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes = .{ .lithophage_root, .lithophage_root_far, .lithophage_crystal, .germinator_pool, .germinator_pour, .item_pod };

pub const def:st.Def = .{ .item = .lithophage, .size = 1, .mesh = .lithophage, .store = true, .grow = 6, .sway = 0.35, .tall = 0.7, .sap = 0.32, .pale = true };

/// seconds it takes to draw one mineral up out of the ground (or eat one
/// it was fed)
pub const DRAW:f32 = 3;
/// how much a crystal takes: grit counts one, a ley shard `LEY_WORTH`
pub const CRYSTAL:u32 = 6;
pub const LEY_WORTH:u32 = 3;
/// grit a crystal saps into, one each `SAP` seconds
// decision: as much as went in, so grit drawn from the ground is never lost
pub const YIELD = CRYSTAL;
pub const SAP:f32 = 2;
/// grit it holds in its cup before it stops sapping, and most ley shards
/// it takes in
pub const BUFFER = 8;
const STOCK = 10;
/// the eight tiles round it its roots reach into, a turn at a time
const AROUND = [8][2]i32{.{1, 0}, .{1, 1}, .{0, 1}, .{-1, 1}, .{-1, 0}, .{-1, -1}, .{0, -1}, .{1, -1}};
/// how fast a root grows out to a node (share a second), and withers
const ROOT_GROW:f32 = 0.35;
const ROOT_WITHER:f32 = 0.8;
/// the crystal: its size when whole (of its mesh), turning slowly in the crop
const CRYSTAL_SIZE:f32 = 1.5;
const CRYSTAL_TURN:f32 = 0.25;
/// a mineral drawn up its stalk shows as a mote rising from root to crop
const MOTE_SIZE:f32 = 0.35;
const MOTE_GLOW:f32 = 0.7;
/// the grit in its cup: a lens this wide empty .. full
const POOL_W = [2]f32{0.012, 0.032};
const POOL_GLOW:f32 = 0.35;
const STREAM_GLOW:f32 = 0.75;
const ROOT_FLUTTER:f32 = 0.2;
const GLOW:f32 = 0.15;

pub const State = struct {
  /// how much of a crystal has condensed (of `CRYSTAL`)
  fill:u32 = 0,
  /// how far the mineral being drawn up is (0..1) and where from (an index
  /// into `AROUND`, or none: one it was fed)
  t:f32 = 0,
  from:?u8 = null,
  /// what is being drawn
  drawing:?items.Item = null,
  /// grit still to sap from the crystal, and how far along the next is
  sap:u8 = 0,
  sap_t:f32 = 0,
  /// which tile round it its roots try next
  turn:u8 = 0,
  /// how far its root toward each tile round it has grown (0..1)
  reach:[8]f32 = @splat(0),
};

fn worth(item:items.Item) u32 { return if (item == .ley_shard) LEY_WORTH else 1; }
fn mineral(item:items.Item) bool { return item == .grit or item == .ley_shard; }

/// a mineral node on tile `i` round (x, y), if any: its chunk and tile
fn nodeAt(w:*World, x:i32, y:i32, i:usize) ?struct { c:*ck.Chunk, t:usize, item:items.Item } {
  const tx = x + AROUND[i][0];
  const ty = y + AROUND[i][1];
  const c = w.chunkOfTile(tx, ty) orelse return null;
  const t = ck.localIndex(tx, ty);
  if (c.res[t] == 0 or c.occ[t] != .none) return null;
  const node = resources.of(c.kind[t]) orelse return null;
  if (!mineral(node.item)) return null;
  return .{.c = c, .t = t, .item = node.item};
}

/// grow roots toward the mineral nodes round it, wither those with none.
fn growRoots(w:*World, self:*st.Structure, dt:f32) void {
  const l = &self.state.lithophage;
  for (&l.reach, 0..) |*r, k| {
    const there = nodeAt(w, self.x, self.y, k) != null;
    r.* = if (there) @min(1, r.* + dt * ROOT_GROW) else @max(0, r.* - dt * ROOT_WITHER);
  }
}

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  _ = st.handOff(ctx, i);
  const self = ctx.ss.get(i);
  growRoots(ctx.w, self, dt);
  const l = &self.state.lithophage;
  // sapping the whole crystal away into its cup, as grit
  if (l.sap > 0) {
    if (self.inv.count(.grit) >= BUFFER) return false;
    l.sap_t += dt / SAP;
    if (l.sap_t < 1) return true;
    if (self.inv.add(.grit, 1) < 1) return false;
    l.sap_t = 0;
    l.sap -= 1;
    return true;
  }
  // drawing a mineral up: from what it was fed first, else a node round it
  // its root has reached
  if (l.drawing == null) {
    if (self.inv.take(.ley_shard, 1)) {
      l.drawing = .ley_shard;
      l.from = null;
    } else for (0..AROUND.len) |k| {
      const at:u8 = @intCast((l.turn + k) % AROUND.len);
      if (l.reach[at] < 1) continue;
      const n = nodeAt(ctx.w, self.x, self.y, at) orelse continue;
      n.c.res[n.t] -= 1;
      l.drawing = n.item;
      l.from = at;
      l.turn = @intCast((at + 1) % AROUND.len);
      break;
    }
    if (l.drawing == null) return false;
    l.t = 0;
  }
  l.t += dt / DRAW;
  if (l.t < 1) return true;
  l.fill += worth(l.drawing.?);
  l.drawing = null;
  l.t = 0;
  if (l.fill >= CRYSTAL) {
    l.fill = 0;
    l.sap = YIELD;
  }
  return true;
}

pub fn wants(s:*const st.Structure, _:*const prog.Progression, item:items.Item) u32 {
  return if (item == .ley_shard) STOCK -| s.inv.count(item) else 0;
}

/// only the grit it has sapped leaves it.
pub fn output(s:*const st.Structure) ?items.Item { return if (s.inv.count(.grit) > 0) .grit else null; }
pub fn gives(s:*const st.Structure, item:items.Item) bool { return item == .grit and s.inv.count(.grit) > 0; }

/// its roots out to the nodes round it, a mote of each mineral drawn up
/// one, the crystal condensing in its crop, the stream of grit it saps
/// into its cup and the grit standing there.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  const l = &s.state.lithophage;
  const base = s.place(ctr);
  for (l.reach, 0..) |r, k| {
    if (r <= 0) continue;
    const o = AROUND[k];
    const id:meshlib.Id = if (o[0] != 0 and o[1] != 0) .lithophage_root_far else .lithophage_root;
    try out.emit(id, m.chain(&.{m.translate(ctr), m.rotY(m.atan2(-m.f(o[1]), m.f(o[0])))}), .{.flutter = ROOT_FLUTTER, .phase = s.seed + m.f(k) * 0.1, .grown = r * s.grown, .glow = GLOW});
  }
  if (s.grown < 1) return;
  const sway:Look = .{.phase = s.seed, .sway = def.sway, .tall = def.tall};

  // a mineral being drawn: up its root from the node, then up the stalk
  if (l.drawing) |it| {
    const crop = m.mulPoint(base, mesh.CROP_AT);
    const p = if (l.from) |k| blk: {
      const node = ctr + v3(m.f(AROUND[k][0]) * 0.8, 0.02, m.f(AROUND[k][1]) * 0.8);
      const foot = ctr + v3(0, 0.05, 0);
      break :blk if (l.t < 0.5) m.lerpV(node, foot, m.smooth(l.t * 2)) else m.lerpV(foot, crop, m.smooth(l.t * 2 - 1));
    } else m.lerpV(ctr + v3(0, 0.05, 0), crop, m.smooth(l.t));
    var look = sway;
    look.glow = MOTE_GLOW;
    look.tint = color.Rgba8.of(it.info().col).toF4();
    look.drop = p[1] - ctr[1];
    try out.emit(.item_pod, m.chain(&.{m.translate(p), m.scale3(m.splat3(MOTE_SIZE * @sin(m.pi * m.clamp01(l.t * 1.2))))}), look);
  }

  // the crystal: grown by what has condensed, shrinking as it is sapped
  const whole = if (l.sap > 0) (m.f(l.sap) - l.sap_t) / YIELD else (m.f(l.fill) + (if (l.drawing) |it| m.f(worth(it)) * m.smooth(m.clamp01(l.t * 2 - 1)) else 0)) / m.f(CRYSTAL);
  if (whole > 0) {
    var look = sway;
    look.drop = mesh.CROP_AT[1];
    try out.emit(.lithophage_crystal, m.mul(base, m.chain(&.{m.translate(mesh.CROP_AT), m.rotY(tf * CRYSTAL_TURN + s.seed * 4), m.rotX(0.3), m.scale3(m.splat3(CRYSTAL_SIZE * @sqrt(m.clamp01(whole))))})), look);
  }

  // sapping: a stream out of the crop's lip down into the cup
  const ess = color.Rgba8.of(items.Item.grit.info().col).toF4();
  if (l.sap > 0 and s.inv.count(.grit) < BUFFER) {
    const lip = m.mulPoint(base, mesh.LIP);
    const cup = m.mulPoint(base, mesh.CUP_AT + v3(0, 0.02, 0));
    const d = cup - lip;
    const ctrl = [4]V3{lip, lip + v3(d[0] * 0.5, 0.01, d[2] * 0.5), lip + v3(d[0] * 0.95, d[1] * 0.5, d[2] * 0.95), cup};
    try out.emitCurve(.germinator_pour, ctrl, m.norm(m.cross(d, v3(0, 1, 0))), 1, 1, .{
      .glow = STREAM_GLOW, .phase = s.seed, .fade = 1, .carry_col = .{ess[0], ess[1], ess[2]},
      .sway = def.sway, .tall = def.tall, .drop = cup[1] - ctr[1],
    });
  }
  // the grit standing in its cup
  const held = s.inv.count(.grit);
  if (held > 0) {
    var look = sway;
    look.tint = ess;
    look.glow = POOL_GLOW;
    look.drop = mesh.CUP_AT[1];
    try out.emit(.germinator_pool, m.mul(base, m.chain(&.{m.translate(mesh.CUP_AT + v3(0, 0.01, 0)), m.scale3(m.splat3(m.lerp(POOL_W[0], POOL_W[1], m.ratio(held, BUFFER))))})), look);
  }
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  const l = &s.state.lithophage;
  const held = s.inv.count(.grit);
  if (l.sap > 0) {
    _ = try d.print(x, y, style.text_body, style.white, txt.s.describe.lith_saps, .{held, BUFFER});
    try d.tendril(x + style.desc_bar_x, y + 2, style.desc_bar_w, style.bar_h, style.gold, 1 - (m.f(l.sap) - l.sap_t) / YIELD, 0.3);
    return;
  }
  var roots:u32 = 0;
  for (l.reach) |r| { if (r >= 1) roots += 1; }
  if (l.drawing == null and roots == 0) {
    _ = try d.print(x, y, style.text_body, style.dim, txt.s.describe.lith_starved, .{held, BUFFER});
    return;
  }
  _ = try d.print(x, y, style.text_body, style.white, txt.s.describe.lith_draws, .{l.fill, CRYSTAL, held, BUFFER});
  try d.tendril(x + style.desc_bar_x, y + 2, style.desc_bar_w, style.bar_h, style.lith, (m.f(l.fill) + l.t) / m.f(CRYSTAL), 0.3);
}

/// its bulb: a pale stalk out of the seed swelling into a crop with a gem
/// condensing in it, a bead of grit running from its lip (it draws stone
/// out of the ground round it).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  try ic.stem(.{.{0, icon_kit.TOP}, .{0.05, 0.25}, .{-0.04, 0.38}, .{0, 0.5}}, 0.11, icon_skin);
  try ic.glow(.{0, 0.72}, 0.3, icon_sac_glow);
  try ic.bud(.{0, 0.72}, 0.28, icon_sac, 0.3);
  try ic.gem(.{0, 0.72}, 0.15, icon_gem);
  for ([_]f32{-1, 1}) |sx| try ic.stem(.{.{0.05 * sx, 0.5}, .{0.32 * sx, 0.55}, .{0.34 * sx, 0.95}, .{0.1 * sx, 1.02}}, 0.05, icon_frond);
  const k = @mod(ic.t * 0.7 + ic.phase, 1);
  try ic.bud(.{0.3, m.lerp(0.55, icon_kit.TOP, k)}, 0.07, icon_ess, 1 - k);
  try ic.coat(col);
}
const icon_skin:Color = .{150, 145, 165, 255};
const icon_frond:Color = .{175, 160, 210, 255};
const icon_sac:Color = .{120, 160, 220, 200};
const icon_sac_glow:Color = .{120, 160, 220, 70};
const icon_gem:Color = .{200, 170, 255, 255};
const icon_ess:Color = .{150, 140, 130, 255};

// ---- tests ----

const TEST_DT:f32 = 0.05;

/// soil round (2, 2), a grit node at (3, 2) holding `res`
fn fixture(w:*World, res:ck.Res) !void {
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  var it = w.map.valueIterator();
  while (it.next()) |cp| @memset(&cp.*.res, 0);
  const c = w.chunkOfTile(0, 0).?;
  for (0..6) |x| for (0..5) |y| {
    const t = y * ck.SIZE + x;
    c.kind[t] = .soil;
    c.height[t] = 1;
  };
  c.res[2 * ck.SIZE + 3] = res;
}

fn run(ss:*st.Structures, w:*World, plants:*Plants, g:*prog.Progression, seconds:f32) !void {
  var t:f32 = 0;
  while (t < seconds) : (t += TEST_DT) try ss.tick(testing.allocator, w, plants, g, TEST_DT);
}

test "a lithophage drains the node beside it into a crystal, then saps it into grit" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w, 20);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 2, 2, .lithophage, 0, 0));
  const id = ss.at(&w, 2, 2).?;
  // its root reaches the node, then six grit make a crystal, sapped back out
  const secs = 1 / ROOT_GROW + DRAW * CRYSTAL + SAP * YIELD + 1;
  try run(&ss, &w, &plants, &g, secs);
  try testing.expectEqual(@as(u32, YIELD), ss.get(id).inv.count(.grit));
  // (the next is already being drawn up)
  const left = w.chunkOfTile(3, 2).?.res[2 * ck.SIZE + 3];
  try testing.expect(left == 20 - CRYSTAL or left == 20 - CRYSTAL - 1);
  try testing.expect(ss.output(id) == .grit);
  try testing.expect(!ss.gives(id, .ley_shard));
}

test "a lithophage eats the ley shards it is fed, each worth three grit" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w, 0);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 2, 2, .lithophage, 0, 0));
  const id = ss.at(&w, 2, 2).?;
  try testing.expectEqual(@as(u16, 2), ss.insert(&g, id, .ley_shard, 2));
  try testing.expectEqual(@as(u16, 0), ss.insert(&g, id, .fibre, 2));
  // grit it never takes: what it holds is what it sapped
  try testing.expectEqual(@as(u16, 0), ss.insert(&g, id, .grit, 2));
  try run(&ss, &w, &plants, &g, DRAW * 2 + SAP * YIELD + 1);
  try testing.expectEqual(@as(u32, YIELD), ss.get(id).inv.count(.grit));
  // nothing round it, nothing fed: it rests
  try run(&ss, &w, &plants, &g, 30);
  try testing.expectEqual(@as(u32, YIELD), ss.get(id).inv.count(.grit));
  try testing.expect(ss.get(id).activity < 0.01);
}

test "a lithophage's grit is carried off by a conduit behind it" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w, 30);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 2, 2, .lithophage, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 3, .conduit, 1, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 4, .sap_cache, 0, 0));
  try run(&ss, &w, &plants, &g, 80);
  try testing.expect(ss.get(ss.at(&w, 2, 4).?).inv.count(.grit) >= YIELD * 2);
}
