//! VULTRIXI: a gathering crown and a ganglion grown into one floating body
//! that feeds a monfris. Configured, then the monfris configured, it is
//! tethered there (at most `monfris.TETHERS` to one). It takes on one
//! kind of what the monfris's weave needs, by its place among the
//! Vultrixi tethered there (the first the weave's first ingredient, and so
//! on), reaches a tendril into the nearest structure within `R` tiles that
//! would let that kind go, pulls it out a unit at a time and sends each
//! along its tether into the monfris, while the monfris wants it.
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
const craft = lib.craft;
const style = lib.style;
const Parts = lib.parts.Parts;
const Look = lib.parts.Look;
const Draw = lib.engine.ui.draw.Draw;
const Color = lib.engine.ui.draw.Color;
const mesh = lib.vultrixi;
const loom_mesh = lib.monfris;
const caster = lib.sporecaster_structure;
const monfris = lib.monfris_structure;

const V3 = m.V3;
const v3 = m.v3;

// decision: its hover is carried by its mesh (`mesh.HOVER`), as a weftstone's
/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes = .{ .item_pod, .monfris_tether, .weftstone_tendril };

pub const def:st.Def = .{ .item = .vultrixi, .size = 1, .mesh = .vultrixi, .grow = 6, .sway = 0.3, .tall = 1.3, .sap = 0.3, .floating = true, .far = true };

/// how far its tendril reaches (tiles between it and a structure's edge)
pub const R = 6;
/// seconds its tendril takes to reach a structure, and to pull a unit out
const REACH:f32 = 0.8;
pub const PULL:f32 = 1;
/// tiles a second what it pulls runs along its tether
const RUN:f32 = 3;
const TENDRIL_FLUTTER:f32 = 0.25;
const TETHER_SAG:f32 = 0.25;
const MOTE_SIZE:f32 = 0.32;
const MOTE_GLOW:f32 = 0.7;
const GLOW:f32 = 0.18;

pub const Carry = struct { item:items.Item, t:f32 = 0 };

pub const State = struct {
  /// the monfris it feeds (by tile) and the ground under it
  dest:?[2]i32 = null,
  dest_h:f32 = 0,
  /// the kind it brings (from its place among the tethered)
  kind:?items.Item = null,
  /// the structure its tendril reaches (by tile, its size and ground), how
  /// far the tendril has reached and how far along the unit it pulls is
  src:?[2]i32 = null,
  src_size:u8 = 1,
  src_h:f32 = 0,
  reach:f32 = 0,
  pull:f32 = 0,
  /// what runs along its tether now
  carry:?Carry = null,
};

fn loomAt(ss:*st.Structures, w:*const World, at:[2]i32) ?st.Id {
  const j = ss.at(w, at[0], at[1]) orelse return null;
  return if (ss.get(j).kind() == .monfris) j else null;
}

/// configured, it waits to be tethered by configuring a monfris next
/// (`monfris.configure`); configured twice over, it is cut loose.
pub fn configure(ss:*st.Structures, id:st.Id, g:*prog.Progression) void {
  const s = ss.get(id);
  const here = [2]i32{s.x, s.y};
  if (ss.pairing) |p| if (p[0] == here[0] and p[1] == here[1]) {
    ss.pairing = null;
    s.state.vultrixi.dest = null;
    return g.say(txt.s.msg.tether_cut, .{});
  };
  ss.pairing = here;
  g.say(txt.s.msg.tether_choose, .{});
}

/// the kind the Vultrixi `i` brings its monfris `j`: the ingredient of
/// its weave at its place among those tethered there
fn assigned(ss:*st.Structures, i:st.Id, j:st.Id) ?items.Item {
  const loom = ss.get(j);
  const at = [2]i32{loom.x, loom.y};
  var rank:usize = 0;
  for (ss.list.items, 0..) |*o, k| {
    if (k == i.idx()) break;
    if (o.kind() != .vultrixi) continue;
    if (o.state.vultrixi.dest) |d| if (d[0] == at[0] and d[1] == at[1]) { rank += 1; };
  }
  const r = craft.hand[loom.state.monfris.recipe];
  return if (rank < r.in.len) r.in[rank].item else null;
}

/// empty tiles between tile `p` and structure `s`'s footprint
fn gap(p:[2]i32, s:*const st.Structure) i32 {
  const n:i32 = s.def().size;
  const dx = @max(s.x - p[0] - 1, p[0] - (s.x + n), -1);
  const dy = @max(s.y - p[1] - 1, p[1] - (s.y + n), -1);
  return @max(dx, dy, 0);
}

/// the nearest structure within reach that would let `kind` go
fn source(ss:*st.Structures, i:st.Id, kind:items.Item) ?st.Id {
  const self = ss.get(i);
  const here = [2]i32{self.x, self.y};
  var best:?st.Id = null;
  var near:i32 = R + 1;
  for (ss.list.items, 0..) |*o, k| {
    if (k == i.idx() or o.def().carrier or o.grown < 1) continue;
    // never from a monfris (what it weaves is the gardener's) or another
    // Vultrixi
    if (o.kind() == .monfris or o.kind() == .vultrixi) continue;
    const d = gap(here, o);
    if (d >= near) continue;
    const id = st.Id.of(k);
    if (!ss.gives(id, kind)) continue;
    best = id;
    near = d;
  }
  return best;
}

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  const vs = &ctx.ss.get(i).state.vultrixi;
  const to = vs.dest orelse {
    vs.kind = null;
    vs.reach = @max(0, vs.reach - dt / REACH);
    return false;
  };
  const j = loomAt(ctx.ss, ctx.w, to) orelse {
    vs.dest = null;
    return false;
  };
  vs.dest_h = caster.groundAt(ctx.w, to);
  vs.kind = assigned(ctx.ss, i, j);
  // what runs along the tether goes into the monfris at its end
  if (vs.carry) |*c| {
    const self = ctx.ss.get(i);
    const far = @max(m.len(v3(m.f(to[0] + 1 - self.x), 0, m.f(to[1] + 1 - self.y))), 1);
    c.t = @min(1, c.t + dt * RUN / far);
    if (c.t >= 1 and ctx.ss.insert(ctx.g, j, c.item, 1) == 1) vs.carry = null;
    return true;
  }
  const kind = vs.kind orelse {
    vs.reach = @max(0, vs.reach - dt / REACH);
    return false;
  };
  if (ctx.ss.wants(ctx.g, j, kind) == 0) {
    vs.reach = @max(0, vs.reach - dt / REACH);
    return false;
  }
  const src = source(ctx.ss, i, kind) orelse {
    vs.reach = @max(0, vs.reach - dt / REACH);
    return false;
  };
  const s = ctx.ss.get(src);
  // a new source: the tendril reaches out to it afresh
  if (vs.src == null or vs.src.?[0] != s.x or vs.src.?[1] != s.y) {
    vs.src = .{s.x, s.y};
    vs.src_size = s.def().size;
    vs.src_h = caster.groundAt(ctx.w, .{s.x, s.y});
    vs.reach = 0;
    vs.pull = 0;
  }
  if (vs.reach < 1) {
    vs.reach = @min(1, vs.reach + dt / REACH);
    return true;
  }
  vs.pull += dt / PULL;
  if (vs.pull < 1) return true;
  vs.pull = 0;
  if (s.inv.take(kind, 1)) vs.carry = .{.item = kind};
  return true;
}

/// cut loose when uprooted: what runs along its tether is lost back to it.
pub fn release(s:*st.Structure) ?items.Item {
  const vs = &s.state.vultrixi;
  defer vs.carry = null;
  return if (vs.carry) |c| c.item else null;
}

/// a point `t` along the curve through `c` (as the GPU bends it, closely enough)
fn along(c:[4]V3, t:f32) V3 {
  const u = 1 - t;
  return c[0] * m.splat3(u * u * u) + c[1] * m.splat3(3 * u * u * t) + c[2] * m.splat3(3 * u * t * t) + c[3] * m.splat3(t * t * t);
}

fn tetherCtrl(s:*const st.Structure, base:m.M4) ?[4]V3 {
  const vs = &s.state.vultrixi;
  const to = vs.dest orelse return null;
  const from = m.mulPoint(base, mesh.CROWN);
  const end = m.footprintCentre(to[0], to[1], 2, vs.dest_h) + loom_mesh.SAC_AT;
  const d = end - from;
  const sag = v3(0, -TETHER_SAG * @min(m.len(d), 4) * 0.25, 0);
  return .{from, from + d * m.splat3(1.0 / 3.0) + sag, from + d * m.splat3(2.0 / 3.0) + sag, end};
}

fn sideOf(c:[4]V3) V3 {
  const flat = v3(c[3][0] - c[0][0], 0, c[3][2] - c[0][2]);
  return if (m.len(flat) > m.EPS) m.norm(m.cross(flat, v3(0, 1, 0))) else v3(1, 0, 0);
}

/// its tether to its monfris, what runs along it, and its tendril into
/// the structure it pulls from.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  _ = tf;
  const vs = &s.state.vultrixi;
  const base = s.place(ctr);
  if (tetherCtrl(s, base)) |c| {
    try out.emitCurve(.monfris_tether, c, sideOf(c), 1, s.grown, .{.flutter = TENDRIL_FLUTTER, .phase = s.seed, .glow = GLOW});
    if (vs.carry) |cr| {
      const look:Look = .{.glow = MOTE_GLOW, .phase = s.seed, .tint = color.Rgba8.of(cr.item.info().col).toF4()};
      try out.emit(.item_pod, m.chain(&.{m.translate(along(c, m.smooth(cr.t))), m.scale3(m.splat3(MOTE_SIZE))}), look);
    }
  }
  if (vs.reach > 0) if (vs.src) |src| {
    const under = m.mulPoint(base, mesh.UNDER);
    const end = m.footprintCentre(src[0], src[1], vs.src_size, vs.src_h) + v3(0, 0.25, 0);
    const d = end - under;
    const c = [4]V3{under, under + v3(d[0] * 0.25, -0.2, d[2] * 0.25), end + v3(-d[0] * 0.15, 0.35, -d[2] * 0.15), end};
    try out.emitCurve(.weftstone_tendril, c, sideOf(c), 1, vs.reach * s.grown, .{.flutter = TENDRIL_FLUTTER, .phase = s.seed + 0.3, .glow = GLOW});
  };
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  const vs = &s.state.vultrixi;
  if (vs.dest == null) {
    _ = try d.print(x, y, style.text_body, style.dim, txt.s.describe.vult_loose, .{});
  } else if (vs.kind != null and (vs.reach > 0 or vs.carry != null)) {
    _ = try d.print(x, y, style.text_body, style.white, txt.s.describe.vult_pulls, .{txt.item(vs.kind.?).name});
  } else {
    _ = try d.print(x, y, style.text_body, style.dim, txt.s.describe.vult_idle, .{});
  }
}

/// its bulb: a pale knot over the seed, petals cupping it, a tendril down
/// into a pod on one side and a tether off to the other with a mote on it.
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const body:icon_kit.P = .{0, 0.7};
  const line = [4]icon_kit.P{body, .{0.35, 0.95}, .{0.65, 0.95}, .{0.85, 0.75}};
  try ic.stem(line, 0.02, icon_tether);
  const k = @mod(ic.t * 0.6 + ic.phase, 1);
  try ic.bud(icon_kit.curve(line, k), 0.045, icon_mote, @sin(k * m.pi));
  try ic.stem(.{body, .{-0.25, 0.5}, .{-0.6, 0.3}, .{-0.7, -0.1}}, 0.03, icon_tendril);
  try ic.bud(.{-0.7, -0.2}, 0.1, icon_pod, 0.4);
  for (0..5) |i| {
    const a = m.half_pi + m.ratio(i, 5) * m.tau;
    try ic.leaf(body, a, 0.18, 0.09, icon_petal, 1);
  }
  try ic.bud(body, 0.12, icon_sac, 0.6);
  for (0..5) |i| {
    const a = m.ratio(i, 5) * m.tau;
    try ic.bud(.{body[0] + 0.13 * @cos(a), body[1] + 0.11 * @sin(a)}, 0.04, icon_pearl, 0.8);
  }
  try ic.coat(col);
}
const icon_tether:Color = .{200, 195, 220, 255};
const icon_mote:Color = .{245, 210, 150, 255};
const icon_tendril:Color = .{175, 160, 210, 255};
const icon_pod:Color = .{210, 160, 70, 255};
const icon_petal:Color = .{235, 160, 100, 255};
const icon_sac:Color = .{180, 140, 230, 220};
const icon_pearl:Color = .{220, 212, 238, 255};

// ---- tests ----

const TEST_DT:f32 = 0.05;

fn fixture(w:*World) !void {
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..16) |x| for (0..16) |y| {
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

fn tether(ss:*st.Structures, w:*World, g:*prog.Progression, v:[2]i32, loom:[2]i32) void {
  st.configure(ss, ss.floaterAt(v[0], v[1]).?, g);
  st.configure(ss, ss.at(w, loom[0], loom[1]).?, g);
}

test "Vultrixi tether to a monfris, six at most, each bringing one kind of its weave" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  g.done.insert(.celestial_defragmentation);
  try testing.expect(try ss.place(gpa, &w, 6, 6, .monfris, 0, 0));
  for (0..7) |k| try testing.expect(try ss.place(gpa, &w, @intCast(k + 1), 2, .vultrixi, 0, 0));
  for (0..7) |k| tether(&ss, &w, &g, .{@intCast(k + 1), 2}, .{6, 6});
  try testing.expectEqual(@as(u32, monfris.TETHERS), monfris.tethers(&ss, .{6, 6}));
  try testing.expect(ss.get(ss.floaterAt(7, 2).?).state.vultrixi.dest == null);
  try run(&ss, &w, &plants, &g, 0.1);
  // the diamond's four kinds go to the first four, in order; the rest idle
  const r = craft.hand[ss.get(ss.at(&w, 6, 6).?).state.monfris.recipe];
  for (0..6) |k| {
    const kind = ss.get(ss.floaterAt(@intCast(k + 1), 2).?).state.vultrixi.kind;
    if (k < r.in.len) try testing.expectEqual(r.in[k].item, kind.?) else try testing.expect(kind == null);
  }
}

test "a Vultrixi pulls what a structure lets go into its monfris, which weaves it" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try fixture(&w);
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  g.done.insert(.celestial_defragmentation);
  try testing.expect(try ss.place(gpa, &w, 8, 8, .monfris, 0, 0));
  const loom = ss.at(&w, 8, 8).?;
  const r = craft.hand[ss.get(loom).state.monfris.recipe];
  // a cache of each kind beside a Vultrixi of its own, all tethered
  for (r.in, 0..) |ing, k| {
    const x:i32 = @intCast(1 + 3 * k);
    try testing.expect(try ss.place(gpa, &w, x, 1, .vultrixi, 0, 0));
    try testing.expect(try ss.place(gpa, &w, x, 3, .sap_cache, 0, 0));
    _ = ss.insert(&g, ss.at(&w, x, 3).?, ing.item, 30);
    tether(&ss, &w, &g, .{x, 1}, .{8, 8});
  }
  // a germinator's unwoven ingredients are never pulled
  try testing.expect(try ss.place(gpa, &w, 13, 1, .germinator, 0, 0));
  _ = ss.insert(&g, ss.at(&w, 13, 1).?, .fibre, 6);
  try run(&ss, &w, &plants, &g, 40);
  try testing.expect(ss.get(loom).inv.count(.diamond) >= 1);
  try testing.expectEqual(@as(u32, 6), ss.get(ss.at(&w, 13, 1).?).inv.count(.fibre));
}
