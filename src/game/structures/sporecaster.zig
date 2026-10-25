//! SPORECASTER: a parasite that sends. Paired with another sporecaster (the
//! configure key on it, then on the one it should send to), it turns what
//! it is fed into spore carriers, a few of one kind to a spore, which rise
//! out of its pore and drift over everything, however far, straight down
//! into the pore of the one it is paired with. Spores cost nothing: a
//! fruiting body manifests them by the thousand. The caster they land in
//! hands what they bring to its neighbours, or conduits pull it away, or,
//! paired on itself, it sends it on again: the loop conduits cannot close.
//! A spore whose caster is gone turns home and gives back what it carried;
//! one whose caster is full hangs over it until there is room.
const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const m = @import("../../core/math.zig");
const color = @import("../../core/color.zig");
const ck = @import("../../world/chunk.zig");
const World = @import("../../world/world.zig").World;
const gen = @import("../../world/gen.zig");
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
const mesh = @import("../../gfx/meshes/sporecaster.zig");

const V3 = m.V3;
const v3 = m.v3;

/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes = .{ .belly_lump, .spore_carrier };

pub const def:st.Def = .{ .item = .sporecaster, .size = 1, .mesh = .sporecaster, .store = true, .grow = 5, .sway = 0.45, .tall = 0.65, .sap = 0.3, .far = true, .pale = true };

/// most it holds, how many of one kind a spore carries, and seconds
/// between one spore and the next
pub const HOLD = 40;
pub const LOAD = 5;
pub const LAUNCH:f32 = 0.25;
/// spores in the air at once from one caster
pub const AIR = 24;
/// tiles a second a spore drifts, and how high it rises over a crossing
/// (a share of how far it goes, at least `RISE_MIN`)
pub const SPEED:f32 = 2.5;
const RISE:f32 = 0.22;
const RISE_MIN:f32 = 1.2;
/// it wanders off its line by this much, back and forth as it goes
const WANDER:f32 = 0.25;
const SPORE_FADE:f32 = 0.35;
const SPORE_GLOW:f32 = 0.6;
const SPORE_SIZE:f32 = 1.7;
/// a spore waiting over a full caster hangs this high over its pore, bobbing
const HANG:f32 = 0.35;
/// what it holds hangs in its sac, in a ring, bobbing
const RING:f32 = 0.45;
const LUMP_R:f32 = 0.022;
const LUMP_GROW:f32 = 0.02;
const BOB:f32 = 0.01;
const TURN:f32 = 0.25;
const GLOW:f32 = 0.2;

pub const Spore = struct {
  item:items.Item,
  n:u8,
  /// how far along it is (0 at the pore it left .. 1 at the one it seeks)
  t:f32 = 0,
  /// the caster it seeks (its tile and ground height), and whether it has
  /// turned home, carrying back what it could not deliver
  to:[2]i32,
  to_h:f32,
  home:bool = false,
};

pub const State = struct {
  /// the caster it sends to (by tile: a structure's id may shift)
  dest:?[2]i32 = null,
  spores:[AIR]?Spore = @splat(null),
  t:f32 = 0,
};

/// the sporecaster on tile `at`, if one stands there.
fn casterAt(ss:*st.Structures, w:*const World, at:[2]i32) ?st.Id {
  const j = ss.at(w, at[0], at[1]) orelse return null;
  return if (ss.get(j).kind() == .sporecaster) j else null;
}

pub fn groundAt(w:*const World, at:[2]i32) f32 {
  if (w.chunkOfTile(at[0], at[1])) |c| return c.height[ck.localIndex(at[0], at[1])];
  return gen.heightAt(w.seed, at[0], at[1]);
}

/// pair it: the first configured waits, the next is where the first sends.
/// Configured twice over, it stops sending.
pub fn configure(ss:*st.Structures, id:st.Id, g:*prog.Progression) void {
  const s = ss.get(id);
  const here = [2]i32{s.x, s.y};
  if (ss.pairing) |p| {
    ss.pairing = null;
    if (p[0] == here[0] and p[1] == here[1]) {
      s.state.sporecaster.dest = null;
      return g.say(txt.s.msg.spores_still, .{});
    }
    // the one waiting sends here
    for (ss.list.items) |*o| if (o.kind() == .sporecaster and o.x == p[0] and o.y == p[1]) {
      o.state.sporecaster.dest = here;
      return g.say(txt.s.msg.spores_paired, .{});
    };
  }
  ss.pairing = here;
  g.say(txt.s.msg.spores_choose, .{});
}

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  const self = ctx.ss.get(i);
  const sc = &self.state.sporecaster;
  // a caster that sends hands nothing to its neighbours: it sends it all
  if (sc.dest == null) _ = st.handOff(ctx, i);
  var busy = false;
  for (&sc.spores) |*slot| {
    const sp = &(slot.* orelse continue);
    busy = true;
    const far = @max(m.len(m.v3(m.f(sp.to[0] - self.x), 0, m.f(sp.to[1] - self.y))), 1);
    if (sp.home) {
      sp.t -= dt * SPEED / far;
      if (sp.t > 0) continue;
      _ = self.inv.add(sp.item, sp.n);
      slot.* = null;
      continue;
    }
    if (sp.t < 1) {
      sp.t = @min(1, sp.t + dt * SPEED / far);
      continue;
    }
    // over the caster it seeks: in, if it is still there and has room
    const j = casterAt(ctx.ss, ctx.w, sp.to) orelse {
      sp.home = true;
      continue;
    };
    const took = ctx.ss.insert(ctx.g, j, sp.item, sp.n);
    sp.n -= @intCast(took);
    if (sp.n == 0) slot.* = null;
  }
  const to = sc.dest orelse return busy;
  if (casterAt(ctx.ss, ctx.w, to) == null or (to[0] == self.x and to[1] == self.y)) return busy;
  if (self.inv.total() == 0) return busy;
  sc.t += dt;
  if (sc.t < LAUNCH) return true;
  for (&sc.spores) |*slot| {
    if (slot.* != null) continue;
    // the kind it holds most of, a load of it
    var best:?items.Stack = null;
    for (self.inv.slot) |s| if (s) |it| if (best == null or it.n > best.?.n) {
      best = it;
    };
    const it = best orelse break;
    const n:u8 = @intCast(@min(it.n, LOAD));
    _ = self.inv.take(it.item, n);
    slot.* = .{.item = it.item, .n = n, .to = to, .to_h = groundAt(ctx.w, to)};
    sc.t = 0;
    break;
  }
  return true;
}

/// uprooted: what its spores carry comes back into its slots with them.
pub fn release(s:*st.Structure) ?items.Item {
  for (&s.state.sporecaster.spores) |*slot| if (slot.*) |sp| {
    _ = s.inv.add(sp.item, sp.n);
    slot.* = null;
  };
  return null;
}

/// anything, while it has room.
pub fn wants(s:*const st.Structure, _:*const prog.Progression, _:items.Item) u32 { return HOLD -| s.inv.total(); }

/// the oldest thing it holds (what a caster that sends nowhere lets go).
pub fn output(s:*const st.Structure) ?items.Item {
  if (s.state.sporecaster.dest != null) return null;
  for (s.inv.slot) |slot| if (slot) |it| return it.item;
  return null;
}
pub fn gives(s:*const st.Structure, item:items.Item) bool { return s.state.sporecaster.dest == null and s.inv.count(item) > 0; }

/// the spores it sent, drifting over to the caster they seek (or home),
/// each its tip leading and a bead of what it carries inside; and what it
/// holds hanging in its sac.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  const sc = &s.state.sporecaster;
  const base = s.place(ctr);
  const pore = m.mulPoint(base, mesh.PORE);
  for (sc.spores, 0..) |slot, k| {
    const sp = slot orelse continue;
    const dest = m.footprintCentre(sp.to[0], sp.to[1], 1, sp.to_h) + mesh.PORE;
    const at = flight(pore, dest, sp.t, s.seed + m.f(k) * 0.37, tf);
    const ahead = flight(pore, dest, if (sp.home) sp.t - 0.02 else sp.t + 0.02, s.seed + m.f(k) * 0.37, tf);
    // a spore waiting over a full caster hangs there, bobbing
    const hang = if (!sp.home and sp.t >= 1) v3(0, HANG + 0.05 * @sin(tf * 2 + m.f(k)), 0) else v3(0, 0, 0);
    const dir = if (m.len(ahead - at) > m.EPS) m.norm(ahead - at) else v3(0, 1, 0);
    const col = color.Rgba8.of(sp.item.info().col).toF4();
    try out.emit(.spore_carrier, m.chain(&.{m.translate(at + hang), m.alignY(dir), m.scale3(m.splat3(SPORE_SIZE))}), .{
      .glow = SPORE_GLOW, .phase = s.seed + m.f(k) * 0.37, .fade = SPORE_FADE, .tint = .{col[0], col[1], col[2], 0}, .flutter = 0.5,
    });
  }
  if (s.grown < 1) return;
  var n:usize = 0;
  for (s.inv.slot) |slot| { if (slot != null) n += 1; }
  var j:usize = 0;
  for (s.inv.slot) |slot| {
    const it = slot orelse continue;
    const a = m.ratio(j, n) * m.tau + tf * TURN + s.seed * 6;
    const ring = if (n == 1) 0 else mesh.SAC_R[0] * RING;
    const at = mesh.SAC_AT + v3(@cos(a) * ring, BOB * @sin(tf * 1.2 + m.f(j) * 2), @sin(a) * ring);
    const r = LUMP_R + LUMP_GROW * m.ratio(it.n, HOLD);
    try out.emit(.belly_lump, m.mul(base, m.chain(&.{m.translate(at), m.scale3(m.splat3(r))})), Look{
      .glow = GLOW, .phase = s.seed, .tint = color.Rgba8.of(it.item.info().col).toF4(),
      .sway = def.sway, .tall = def.tall, .drop = at[1],
    });
    j += 1;
  }
}

/// where a spore is `t` along its drift from `from` to `to`: up out of the
/// pore, a long rise and fall over the ground, straight down into the
/// pore it seeks, wandering a little off its line as it goes
pub fn flight(from:V3, to:V3, t:f32, ph:f32, tf:f32) V3 {
  const k = m.clamp01(t);
  const d = to - from;
  const flat = v3(d[0], 0, d[2]);
  const far = m.len(flat);
  const side = if (far > m.EPS) m.norm(m.cross(flat, v3(0, 1, 0))) else v3(1, 0, 0);
  const rise = @max(RISE_MIN, RISE * far);
  // eased along, so it leaves and arrives slowly
  const e = m.smooth(k);
  const wander = WANDER * @sin(m.pi * k) * @sin(k * 9 + ph * 7 + tf * 0.7);
  return from + flat * m.splat3(e) + v3(0, d[1] * e + rise * @sin(m.pi * k), 0) + side * m.splat3(wander);
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  const sc = &s.state.sporecaster;
  var air:u32 = 0;
  for (sc.spores) |sp| { if (sp != null) air += 1; }
  if (sc.dest) |to| {
    _ = try d.print(x, y, style.text_body, style.white, txt.s.describe.sends, .{to[0] - s.x, to[1] - s.y, air, s.inv.total(), HOLD});
  } else {
    _ = try d.print(x, y, style.text_body, style.dim, txt.s.describe.unpaired, .{s.inv.total(), HOLD});
  }
}

/// its bulb: a tall pale stalk out of the seed holding a sac, spores rising
/// out of its pore and drifting off along an arc (it sends things far).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  try ic.stem(.{.{-0.1, icon_kit.TOP}, .{-0.05, 0.3}, .{-0.16, 0.45}, .{-0.1, 0.58}}, 0.09, icon_skin);
  try ic.glow(.{-0.1, 0.72}, 0.25, icon_sac_glow);
  try ic.bud(.{-0.1, 0.72}, 0.18, icon_sac, 0.3);
  for ([_]f32{-1, 1}) |sx| try ic.stem(.{.{-0.1, 0.86}, .{-0.1 + 0.18 * sx, 0.98}, .{-0.1 + 0.3 * sx, 0.9}, .{-0.1 + 0.28 * sx, 0.78}}, 0.04, icon_frond);
  const arc = [4]icon_kit.P{.{-0.1, 0.9}, .{0.2, 1.1}, .{0.6, 0.9}, .{0.75, 0.3}};
  for (0..3) |k| {
    const t = @mod(ic.t * 0.5 + ic.phase + m.f(k) / 3, 1);
    try ic.bud(icon_kit.curve(arc, t), 0.06, icon_spore, @sin(t * m.pi));
  }
  try ic.coat(col);
}
const icon_skin:Color = .{190, 182, 205, 255};
const icon_frond:Color = .{175, 160, 210, 255};
const icon_sac:Color = .{120, 160, 220, 200};
const icon_sac_glow:Color = .{120, 160, 220, 70};
const icon_spore:Color = .{235, 225, 255, 255};

// ---- tests ----

const TEST_DT:f32 = 0.05;

/// soil along y = 0 and y = 1 from x = 0 to 29
fn fixture(w:*World) !void {
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..30) |x| for (0..2) |y| {
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

test "sporecasters pair by configuring one, then the one it sends to" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 0, 0, .sporecaster, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 25, 1, .sporecaster, 0, 0));
  const a = ss.at(&w, 0, 0).?;
  const b = ss.at(&w, 25, 1).?;
  st.configure(&ss, a, &g);
  try testing.expect(ss.pairing != null);
  st.configure(&ss, b, &g);
  try testing.expectEqual([2]i32{25, 1}, ss.get(a).state.sporecaster.dest.?);
  try testing.expect(ss.get(b).state.sporecaster.dest == null and ss.pairing == null);
  // configured twice over, it stops sending
  st.configure(&ss, a, &g);
  st.configure(&ss, a, &g);
  try testing.expect(ss.get(a).state.sporecaster.dest == null);
}

test "spores carry what a caster is fed to the one it is paired with, however far" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 0, 0, .sporecaster, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 28, 0, .sporecaster, 0, 0));
  const a = ss.at(&w, 0, 0).?;
  ss.get(a).state.sporecaster.dest = .{28, 0};
  try testing.expectEqual(@as(u16, 12), ss.insert(&g, a, .essence, 12));
  try testing.expectEqual(@as(u16, 7), ss.insert(&g, a, .grit, 7));
  // a caster that sends lets nothing go to conduits
  try testing.expect(ss.output(a) == null);
  try run(&ss, &w, &plants, &g, 24);
  const b = ss.get(ss.at(&w, 28, 0).?);
  try testing.expectEqual(@as(u32, 12), b.inv.count(.essence));
  try testing.expectEqual(@as(u32, 7), b.inv.count(.grit));
  try testing.expectEqual(@as(u32, 0), ss.get(a).inv.total());
  // the one it lands in, sending nowhere, lets it go
  try testing.expect(ss.output(ss.at(&w, 28, 0).?) != null);
}

test "spores whose caster is uprooted turn home with what they carry" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 0, 0, .sporecaster, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 28, 0, .sporecaster, 0, 0));
  const a = ss.at(&w, 0, 0).?;
  ss.get(a).state.sporecaster.dest = .{28, 0};
  _ = ss.insert(&g, a, .fibre, 10);
  try run(&ss, &w, &plants, &g, 1);
  _ = ss.remove(&w, ss.at(&w, 28, 0).?);
  try run(&ss, &w, &plants, &g, 24);
  const back = ss.get(ss.at(&w, 0, 0).?);
  try testing.expectEqual(@as(u32, 10), back.inv.count(.fibre));
  for (back.state.sporecaster.spores) |sp| try testing.expect(sp == null);
}
