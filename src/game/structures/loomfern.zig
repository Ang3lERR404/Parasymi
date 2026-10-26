//! LOOMFERN: a fern that weaves fibre by itself, so the wolf need not pull
//! it from moss. Grown, it draws threads from its fronds and winds them
//! into a sheaf on its spindle, one fibre a sheaf, slowly from nothing;
//! fed essence (into its calyx), it weaves several sheaves from each at a
//! far quicker pace. Finished fibre goes to a neighbour that wants it, or
//! a conduit behind it pulls it away; with nowhere to go it lays its
//! sheaves at its foot until it holds `BUFFER`, then rests.
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
const style = @import("../style.zig");
const color = @import("engine").core.color;
const Parts = @import("../parts.zig").Parts;
const Look = @import("../parts.zig").Look;
const Draw = @import("engine").ui.draw.Draw;
const Color = @import("engine").ui.draw.Color;
const mesh = @import("../../gfx/meshes/loomfern.zig");

const V3 = m.V3;
const v3 = m.v3;

/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes = .{ .germinator_pool, .loomfern_sheaf, .loomfern_thread };

pub const def:st.Def = .{ .item = .loomfern, .size = 1, .mesh = .loomfern, .store = true, .grow = 5, .sway = 0.7, .tall = 0.5 };

/// a lithophage grown beside it: the study of woven stone
pub const meets:st.Meeting = .{ .kind = .lithophage, .found = .loom_and_stone };

/// seconds a fibre takes unfed, and fed
pub const SLOW:f32 = 12;
pub const FAST:f32 = 3;
/// fibre woven from each essence it is fed
pub const PER_ESSENCE = 4;
/// fibre it holds before it rests, and most essence it takes in
pub const BUFFER = 12;
const ESSENCE_STOCK = 6;
/// threads drawn to the sheaf at once, each over its own stretch of the
/// weave (from, until it is wound in), the fronds they come from taking
/// turns weave by weave
const THREADS = 3;
const THREAD_AT = [THREADS]f32{0.0, 0.2, 0.4};
const THREAD_DRAW:f32 = 0.3;
const THREAD_WIND:f32 = 0.82;
/// where along a frond a thread is drawn from
const THREAD_FROM:f32 = 0.72;
/// the sheaf turns this many times a weave (whole turns, so the next one
/// starts where it left off), and grows on the spindle from `SHEAF_FROM`
const SHEAF_TURNS:f32 = 2;
const SHEAF_FROM:f32 = 0.08;
/// finished sheaves laid at its foot: one per this many fibre held, at most
/// `LAID`, this far out, leaning in against the bole
const PER_LAID = 3;
const LAID = 4;
const LAID_OUT:f32 = 0.17;
const LAID_LEAN:f32 = 1.15;
const LAID_SIZE:f32 = 0.85;
/// the essence in its calyx: a lens this wide empty .. full
const POOL_W = [2]f32{0.012, 0.03};
const GLOW:f32 = 0.15;
const THREAD_GLOW = [2]f32{0.1, 0.45};
const POOL_GLOW:f32 = 0.3;

pub const State = struct {
  /// how far along the fibre being woven is (0..1)
  t:f32 = 0,
  /// fibre still to weave from the essence last taken in
  fed:u8 = 0,
  /// fibre woven so far (which fronds give the threads)
  woven:u32 = 0,
};

/// it roots in living ground only.
pub fn ground(k:ck.Kind) bool { return k == .soil or k == .moss; }

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  _ = st.handOff(ctx, i);
  const self = ctx.ss.get(i);
  const f = &self.state.loomfern;
  if (self.inv.count(.fibre) >= BUFFER) return false;
  if (f.fed == 0 and self.inv.take(.essence, 1)) f.fed = PER_ESSENCE;
  f.t += dt / (if (f.fed > 0) FAST else SLOW);
  if (f.t < 1) return true;
  if (self.inv.add(.fibre, 1) < 1) return false;
  f.t = 0;
  f.woven +%= 1;
  if (f.fed > 0) f.fed -= 1;
  return true;
}

pub fn wants(s:*const st.Structure, _:*const prog.Progression, item:items.Item) u32 {
  return if (item == .essence) ESSENCE_STOCK -| s.inv.count(.essence) else 0;
}

/// only the fibre it has woven leaves it.
pub fn output(s:*const st.Structure) ?items.Item { return if (s.inv.count(.fibre) > 0) .fibre else null; }
pub fn gives(s:*const st.Structure, item:items.Item) bool { return item == .fibre and s.inv.count(.fibre) > 0; }

/// the sheaf forming on its spindle and the threads drawn into it from the
/// fronds, the essence standing in its calyx, finished sheaves at its foot;
/// all of it sways with the fern.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, _:f32) Allocator.Error!void {
  if (s.grown < 1) return;
  const f = &s.state.loomfern;
  const base = s.place(ctr);
  const sway:Look = .{.phase = s.seed, .sway = def.sway, .tall = def.tall, .glow = GLOW};
  const weaving = s.inv.count(.fibre) < BUFFER;
  const p = if (weaving) f.t else 0;
  const fed = f.fed > 0 or s.inv.count(.essence) > 0;

  // the sheaf: growing on the spindle as the weave goes, turning as it
  // winds the threads in
  const sheaf = m.smooth(m.clamp01((p - SHEAF_FROM) / (1 - SHEAF_FROM)));
  if (sheaf > 0) {
    var look = sway;
    look.drop = mesh.SHEAF_AT[1];
    try out.emit(.loomfern_sheaf, m.mul(base, m.chain(&.{m.translate(mesh.SHEAF_AT), m.rotY(p * SHEAF_TURNS * m.tau + s.seed * 5), m.scale3(m.splat3(sheaf))})), look);
  }

  // the threads: each drawn out of a leaflet to the sheaf, then wound in,
  // its far end pulled off the frond and into the sheaf
  if (weaving) for (0..THREADS) |j| {
    const k0 = THREAD_AT[j];
    if (p <= k0) continue;
    const frond = (@as(usize, f.woven) * 2 + j * 3 + m.floorTo(usize, s.seed * 7)) % mesh.FRONDS;
    const from = m.mulPoint(base, mesh.frondAt(frond, THREAD_FROM));
    const to = m.mulPoint(base, mesh.SHEAF_AT);
    const d = to - from;
    const sag = v3(0, -0.04 * m.len(d), 0);
    const ctrl = [4]V3{from, from + d * m.splat3(0.33) + sag, from + d * m.splat3(0.7) + sag * m.splat3(0.5), to};
    const side = m.norm(m.cross(d, v3(0, 1, 0)));
    var look = sway;
    look.glow = if (fed) THREAD_GLOW[1] else THREAD_GLOW[0];
    look.drop = from[1] - ctr[1];
    if (p < THREAD_WIND) {
      try out.emitCurve(.loomfern_thread, ctrl, side, 1, m.smooth(m.clamp01((p - k0) / THREAD_DRAW)), look);
    } else {
      // the same curve from the sheaf's end, shortening: wound in
      const back = [4]V3{ctrl[3], ctrl[2], ctrl[1], ctrl[0]};
      try out.emitCurve(.loomfern_thread, back, -side, 1, 1 - m.smooth((p - THREAD_WIND) / (1 - THREAD_WIND)), look);
    }
  };

  // essence it was fed, standing in the calyx
  const ess = s.inv.count(.essence);
  if (ess > 0 or f.fed > 0) {
    const lv = m.clamp01((m.f(ess) + m.f(f.fed) / PER_ESSENCE) / ESSENCE_STOCK);
    var look = sway;
    look.tint = color.Rgba8.of(items.Item.essence.info().col).toF4();
    look.glow = POOL_GLOW;
    look.drop = mesh.POOL_AT[1];
    try out.emit(.germinator_pool, m.mul(base, m.chain(&.{m.translate(mesh.POOL_AT), m.scale3(m.splat3(m.lerp(POOL_W[0], POOL_W[1], lv)))})), look);
  }

  // finished sheaves laid at its foot, leaning in against the bole, each
  // filling out as the fibre held grows toward it
  const held = s.inv.count(.fibre);
  for (0..LAID) |k| {
    const fill = m.clamp01((m.f(held) - m.f(k * PER_LAID)) / PER_LAID);
    if (fill <= 0) break;
    const a = (m.f(k) + 0.5) / LAID * m.tau + s.seed * 3;
    const at = v3(@cos(a) * LAID_OUT, mesh.SHEAF_H * 0.42, @sin(a) * LAID_OUT);
    var look = sway;
    look.drop = at[1];
    try out.emit(.loomfern_sheaf, m.mul(base, m.chain(&.{m.translate(at), m.rotY(-a), m.rotZ(LAID_LEAN), m.scale3(m.splat3(LAID_SIZE * m.smooth(fill)))})), look);
  }
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  const f = &s.state.loomfern;
  const held = s.inv.count(.fibre);
  if (held >= BUFFER) {
    _ = try d.print(x, y, style.text_body, style.dim, txt.s.describe.loom_full, .{held, BUFFER});
    return;
  }
  const tpl = if (f.fed > 0 or s.inv.count(.essence) > 0) txt.s.describe.loom_fed else txt.s.describe.loom;
  _ = try d.print(x, y, style.text_body, style.white, tpl, .{held, BUFFER});
  try d.tendril(x + style.desc_bar_x, y + 2, style.desc_bar_w, style.bar_h, style.growth, f.t, 0.3);
}

/// its bulb: a fern unrolling out of the seed, a crozier at its heart and
/// a sheaf of fibre bound beside it (it weaves fibre).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  for ([_]f32{-1, 1}) |sx| {
    const fr = [4]icon_kit.P{.{0, icon_kit.TOP}, .{0.12 * sx, 0.5}, .{0.5 * sx, 0.75}, .{0.72 * sx, 0.5}};
    try ic.stem(fr, 0.07, icon_kit.stem_col);
    for (0..3) |k| {
      const at = icon_kit.curve(fr, 0.4 + 0.2 * m.f(k));
      try ic.leaf(at, if (sx < 0) 2.2 - 0.3 * m.f(k) else 0.9 + 0.3 * m.f(k), 0.2, 0.1, icon_kit.sprout, 0.9);
    }
  }
  try ic.stem(.{.{0, icon_kit.TOP}, .{0, 0.4}, .{0.16, 0.62}, .{0.02, 0.6}}, 0.075, icon_kit.sprout);
  try ic.bud(.{0.06, 0.56}, 0.07, icon_kit.sprout, 0.4);
  try ic.kernel(.{0.0, 0.92}, 0.32, icon_fibre);
  try ic.coat(col);
}
const icon_fibre:Color = .{120, 170, 90, 255};

// ---- tests ----

const TEST_DT:f32 = 0.05;

fn fixture(w:*World) !void {
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  var it = w.map.valueIterator();
  while (it.next()) |cp| @memset(&cp.*.res, 0);
  const c = w.chunkOfTile(0, 0).?;
  for (0..4) |x| for (0..2) |y| {
    const t = y * ck.SIZE + x;
    c.kind[t] = .moss;
    c.height[t] = 1;
  };
}

fn run(ss:*st.Structures, w:*World, plants:*Plants, g:*prog.Progression, seconds:f32) !void {
  var t:f32 = 0;
  while (t < seconds) : (t += TEST_DT) try ss.tick(testing.allocator, w, plants, g, TEST_DT);
}

test "a loomfern weaves fibre slowly unfed, and fast from essence" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 0, 0, .loomfern, 0, 0));
  const id = ss.at(&w, 0, 0).?;
  try run(&ss, &w, &plants, &g, SLOW * 2 + 0.2);
  try testing.expectEqual(@as(u32, 2), ss.get(id).inv.count(.fibre));
  // fed one essence: four fibre at the fast pace
  try testing.expectEqual(@as(u16, 1), ss.insert(&g, id, .essence, 1));
  try testing.expectEqual(@as(u16, 0), ss.insert(&g, id, .grit, 1));
  try run(&ss, &w, &plants, &g, FAST * PER_ESSENCE + 0.2);
  try testing.expectEqual(@as(u32, 2 + PER_ESSENCE), ss.get(id).inv.count(.fibre));
  try testing.expectEqual(@as(u32, 0), ss.get(id).inv.count(.essence));
  // only fibre leaves it
  try testing.expect(ss.output(id) == .fibre);
  try testing.expect(!ss.gives(id, .essence));
}

test "a loomfern hands its fibre to a neighbour, and rests when full" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 0, 0, .loomfern, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 1, 0, .sap_cache, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 3, 1, .loomfern, 0, 0));
  _ = ss.insert(&g, ss.at(&w, 0, 0).?, .essence, ESSENCE_STOCK);
  try run(&ss, &w, &plants, &g, 30);
  try testing.expect(ss.get(ss.at(&w, 1, 0).?).inv.count(.fibre) >= 9);
  try run(&ss, &w, &plants, &g, SLOW * (BUFFER + 2));
  const lone = ss.get(ss.at(&w, 3, 1).?);
  try testing.expectEqual(@as(u32, BUFFER), lone.inv.count(.fibre));
  try testing.expect(lone.activity < 0.01);
}
