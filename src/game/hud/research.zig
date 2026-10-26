//! the research tree (T) as a living sapling growing out of the soil.
//! Leaves are small studies; branches are big ones (`Research.branch`: new
//! structures, species, an event). Nothing is placed by hand: the shape
//! follows from the prerequisites alone, so a new technology needs no layout.
//!   - host: a node grows on the nearest branch up its first-prerequisite
//!     chain, else on the trunk.
//!   - a host's children sit one slot apart along it, by depth (longest
//!     prerequisite chain, a discovery counts one), then declaration order;
//!     leaves and branches each alternate sides. A stem is one slot longer
//!     than it has children, and bends toward the light.
//!   - the fully grown tree is fitted to the panel, so nothing ever moves:
//!     the sapling starts small at the soil and fills the panel as it grows.
//! Known: grown (a leaf, or a branch with a violet bloom at its tip). Open:
//! a gold bud (a shoot growing with progress while studied). Locked: a dim
//! dormant bud where its host has grown; beyond that, nothing yet. The trunk
//! reaches just past the highest open or known node and thickens with all
//! that is known. Hover a node for its card below; click it to study it.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const indexOfScalar = std.mem.indexOfScalar;
const testing = std.testing;
const play = lib.play;
const prog = lib.progression;
const Draw = lib.engine.ui.draw.Draw;
const Color = lib.engine.ui.draw.Color;
const s = lib.style;
const txt = lib.txt;
const m = lib.engine.core.math;
const color = lib.engine.core.color;

const Id = prog.Id;
const V3 = m.V3;
const N = prog.tree.values.len;

const pw:f32 = 600;
const margin:f32 = 24;
const max_h:f32 = 900;
const header_h:f32 = 84;
const card_h:f32 = 132;
const tree_pad:f32 = 36;
const tendril_w:f32 = 150;
const tendril_h = s.bar_h;
/// a slot never draws larger than this many pixels, however few nodes
const max_slot:f32 = 80;
/// hit area around a node, at least this many pixels across
const min_hit:f32 = 26;

// ---- the shape, in slots (one slot = the spacing between nodes on a stem) ----

const SEG = 10;
const UP:f32 = m.half_pi;
/// angles off the host's heading
const BRANCH_ANGLE = m.rad(60);
const TWIG_ANGLE = m.rad(40);
const LEAF_ANGLE = m.rad(56);
/// how far toward straight up a stem turns over its length
const BEND:f32 = 0.4;
/// a branch is at least this long, so even a bare one reaches out
const BRANCH_MIN:f32 = 2.5;
const PETIOLE:f32 = 0.16;
const LEAF_LEN:f32 = 0.7;
const LEAF_W:f32 = 0.34;
const BUD_LEN:f32 = 0.3;
const BUD_W:f32 = 0.2;
/// a branch's closed bud is this much larger than a leaf's
const BRANCH_BUD:f32 = 1.4;
const BLOOM_R:f32 = 0.13;
/// the trunk reaches this far past its highest open or known node
const TRUNK_LEAD:f32 = 0.55;
const TRUNK_EASE:f32 = 1.5;
/// trunk radius: a seedling's, and how it thickens with what is known (sqrt)
const TRUNK_R0:f32 = 0.06;
const TRUNK_RK:f32 = 0.025;
/// a branch starts this thick relative to its host where it leaves it
const BRANCH_R:f32 = 0.7;
/// stems narrow to this fraction of their base radius at the tip
const TAPER:f32 = 0.85;
/// bark turns old (brown) at this radius
const OLD_R:f32 = 0.13;
const ROOT_LEN:f32 = 0.45;
const ROOT_SPREAD:f32 = 0.7;
/// wind: stems sway (the trunk by `TRUNK_SWAY` of it), leaves flutter, each
/// at its own rate
const SWAY:f32 = 0.05;
const SWAY_RATE:f32 = 0.8;
const TRUNK_SWAY:f32 = 0.4;
const FLUTTER:f32 = 0.08;
const FLUTTER_RATE:f32 = 1.3;
/// the sapling's clock wraps after this many seconds (keeps f32 precise)
const TIME_WRAP:f64 = 1000;
/// a frame's trunk easing steps at most this many seconds
const EASE_DT_MAX:f64 = 0.1;

fn isBranch(i:usize) bool { return prog.tree.values[i].branch; }
/// stem index of a host: 0 the trunk, 1 + id a branch.
fn stemOf(h:?Id) usize { return if (h) |id| 1 + @as(usize, @intFromEnum(id)) else 0; }
fn firstPrereq(id:Id) ?Id {
  const r = prog.tree.get(id);
  return if (r.prereq.len > 0) r.prereq[0] else null;
}

/// the static shape of the tree, worked out from the prerequisites.
const Plan = struct {
  host:[N]?Id,
  /// where along its host a node grows, in slots from the host's base
  at:[N]f32,
  /// +1 to the left of the host's heading, -1 to the right
  side:[N]f32,
  /// children per stem
  kids:[N + 1]u32,
  /// branches, each after the stem it grows on
  order:[N]Id,
  branches:usize,
};

const plan:Plan = blk: {
  @setEvalBranchQuota(100_000);
  var p:Plan = undefined;
  var depth:[N]u32 = @splat(0);
  for (0..N) |_| for (prog.tree.values, 0..) |r, i| {
    var dd:u32 = if (r.needs != null) 1 else 0;
    for (r.prereq) |q| dd = @max(dd, depth[@intFromEnum(q)] + 1);
    depth[i] = dd;
  };
  for (0..N) |i| {
    var h = firstPrereq(@enumFromInt(i));
    while (h) |q| : (h = firstPrereq(q)) if (prog.tree.get(q).branch) break;
    p.host[i] = h;
  }
  // stable by depth, so everything grows above what it needs
  var sorted:[N]usize = undefined;
  for (&sorted, 0..) |*o, i| o.* = i;
  for (1..N) |i| {
    var j = i;
    while (j > 0 and depth[sorted[j - 1]] > depth[sorted[j]]) : (j -= 1) {
      const t = sorted[j];
      sorted[j] = sorted[j - 1];
      sorted[j - 1] = t;
    }
  }
  p.kids = @splat(0);
  var leaves:[N + 1]u32 = @splat(0);
  var twigs:[N + 1]u32 = @splat(0);
  p.branches = 0;
  for (sorted) |i| {
    const h = stemOf(p.host[i]);
    p.kids[h] += 1;
    p.at[i] = m.f(p.kids[h]);
    // leaves start on the left, branches on the right, so the crown balances
    const nth = if (isBranch(i)) &twigs[h] else &leaves[h];
    p.side[i] = if ((nth.* % 2 == 0) != isBranch(i)) 1 else -1;
    nth.* += 1;
    if (isBranch(i)) {
      p.order[p.branches] = @enumFromInt(i);
      p.branches += 1;
    }
  }
  break :blk p;
};

/// a stem's full length: one slot past its last child (a branch's at least
/// BRANCH_MIN).
fn stemLen(k:usize) f32 {
  const n = m.f(plan.kids[k] + 1);
  return if (k == 0) n else @max(n, BRANCH_MIN);
}

fn heading(a:f32) V3 { return m.v3(@cos(a), @sin(a), 0); }

/// a stem's centreline: SEG even steps whose heading turns by `bend` of the
/// way to straight up, plus `curl` (sway) growing toward the tip.
const Stem = struct {
  pts:[SEG + 1]V3 = undefined,
  ang:[SEG + 1]f32 = undefined,
  len:f32 = 0,

  fn build(base:V3, a0:f32, len:f32, bend:f32, curl:f32) Stem {
    var st:Stem = .{.len = len};
    st.pts[0] = base;
    st.ang[0] = a0;
    for (1..SEG + 1) |j| {
      const u = m.ratio(j, SEG);
      st.ang[j] = a0 + (UP - a0) * bend * u + curl * u * u;
      st.pts[j] = st.pts[j - 1] + heading((st.ang[j - 1] + st.ang[j]) / 2) * m.splat3(len / SEG);
    }
    return st;
  }
  fn point(st:*const Stem, at:f32) V3 { return m.alongPath(&st.pts, m.clamp01(at / st.len)); }
  fn angle(st:*const Stem, at:f32) f32 {
    const k = m.clamp01(at / st.len) * SEG;
    const i = @min(m.floorTo(usize, k), SEG - 1);
    return m.lerp(st.ang[i], st.ang[i + 1], k - m.f(i));
  }
};

const Layout = struct {
  stems:[N + 1]Stem,
  /// where each node leaves its host, and its heading there
  base:[N]V3,
  ang:[N]f32,
};

/// the whole tree at time `t`; `amp` scales the wind (0: still).
fn layout(t:f32, amp:f32) Layout {
  var l:Layout = undefined;
  l.stems[0] = .build(m.splat3(0), UP, stemLen(0), BEND, amp * sway(0, t) * TRUNK_SWAY);
  place(&l, null, t, amp);
  for (plan.order[0..plan.branches]) |b| {
    const i:usize = @intFromEnum(b);
    l.stems[1 + i] = .build(l.base[i], l.ang[i], stemLen(1 + i), BEND, amp * sway(1 + i, t));
    place(&l, b, t, amp);
  }
  return l;
}

fn place(l:*Layout, h:?Id, t:f32, amp:f32) void {
  const st = &l.stems[stemOf(h)];
  for (0..N) |i| if (stemOf(plan.host[i]) == stemOf(h)) {
    const off = if (!isBranch(i)) LEAF_ANGLE else if (h == null) BRANCH_ANGLE else TWIG_ANGLE;
    const flutter = if (isBranch(i)) 0 else FLUTTER * @sin(t * FLUTTER_RATE + m.f(i) * 2.3);
    l.base[i] = st.point(plan.at[i]);
    l.ang[i] = st.angle(plan.at[i]) + plan.side[i] * off + amp * flutter;
  };
}

fn sway(k:usize, t:f32) f32 { return SWAY * @sin(t * SWAY_RATE + m.f(k) * 1.9); }

/// a leaf's tip, fully open.
fn leafTip(l:*const Layout, i:usize) V3 { return l.base[i] + heading(l.ang[i]) * m.splat3(PETIOLE + LEAF_LEN); }

/// slots to screen pixels: y up becomes y down.
const Fit = struct {
  o:[2]f32,
  k:f32,
  fn at(f:Fit, p:V3) [2]f32 { return .{f.o[0] + p[0] * f.k, f.o[1] - p[1] * f.k}; }
  fn angle(a:f32) f32 { return -a; }
};

/// the fully grown, still tree fitted into the area, standing on its floor.
fn fit(x:f32, y:f32, w:f32, h:f32) Fit {
  const l = layout(0, 0);
  var lo = m.v3(0, -ROOT_LEN, 0);
  var hi = lo;
  const grow = struct {
    fn by(a:*V3, b:*V3, p:V3) void { a.* = @min(a.*, p); b.* = @max(b.*, p); }
  };
  for (0..N + 1) |k| if (k == 0 or isBranch(k - 1)) for (l.stems[k].pts) |p| grow.by(&lo, &hi, p);
  for (0..N) |i| if (!isBranch(i)) grow.by(&lo, &hi, leafTip(&l, i));
  lo -= m.splat3(LEAF_W);
  hi += m.splat3(LEAF_W);
  const k = @min(@min(w / (hi[0] - lo[0]), h / (hi[1] - lo[1])), max_slot);
  return .{.o = .{x + w / 2 - (lo[0] + hi[0]) / 2 * k, y + h + lo[1] * k}, .k = k};
}

/// how far the trunk has grown, eased toward what is known (kept in play.Game).
pub const Sapling = struct {
  trunk:f32 = 0,
  /// ui time of the last draw; negative until the first, which snaps
  t:f64 = -1,
};

fn trunkTarget(g:*const play.Game) f32 {
  var top:f32 = 0;
  for (0..N) |i| if (plan.host[i] == null and g.prog.status(@enumFromInt(i)) != .locked) { top = @max(top, plan.at[i]); };
  return top + TRUNK_LEAD;
}

fn frac(g:*const play.Game, id:Id) f32 {
  if (g.prog.done.contains(id)) return 1;
  return m.ratio(g.prog.progress.get(id), prog.tree.get(id).units);
}

fn mix(a:Color, b:Color, t:f32) Color {
  const c = color.mix(.of(a), .of(b), m.clamp01(t));
  return .{c.r, c.g, c.b, c.a};
}

pub fn visible(g:*const play.Game) bool { return g.mode == .research; }

pub fn draw(g:*play.Game, d:*Draw, W:f32, H:f32) Allocator.Error!void {
  const ph = @min(H - 2 * margin, max_h);
  const px = W - pw - margin;
  const py = (H - ph) / 2;
  try d.trellis(px, py, pw, ph, s.research_panel, 0.77);
  g.rows.add(.{.x = px, .y = py, .w = pw, .h = ph}, .panel);
  _ = try d.text(px + 56, py + s.title_y, s.text_title, s.gold, txt.s.hud.research_title);
  _ = try d.text(px + 56, py + 58, s.text_small, s.dim, txt.s.hud.research_hint);

  const sp = &g.sapling;
  const target = trunkTarget(g);
  if (sp.t < 0) sp.trunk = target else {
    const dt:f32 = @floatCast(m.clamp(g.ui_time - sp.t, 0, EASE_DT_MAX));
    sp.trunk += (target - sp.trunk) * @min(1, dt * TRUNK_EASE);
  }
  sp.t = g.ui_time;

  const area_y = py + header_h;
  const f = fit(px + tree_pad, area_y, pw - 2 * tree_pad, ph - header_h - card_h);
  const t:f32 = @floatCast(@mod(g.ui_time, TIME_WRAP));
  const l = layout(t, 1);

  // how far each stem has grown, and how thick it is at its base
  var grown:[N + 1]f32 = @splat(0);
  var rad:[N + 1]f32 = @splat(0);
  grown[0] = @min(sp.trunk, l.stems[0].len);
  rad[0] = TRUNK_R0 + TRUNK_RK * @sqrt(m.f(g.prog.done.count()));
  for (plan.order[0..plan.branches]) |b| {
    const i:usize = @intFromEnum(b);
    const h = stemOf(plan.host[i]);
    if (!shown(&grown, i)) continue;
    const st = g.prog.status(b);
    grown[1 + i] = if (st == .done) l.stems[1 + i].len else if (g.prog.current == b) frac(g, b) * l.stems[1 + i].len else 0;
    rad[1 + i] = BRANCH_R * radiusAt(rad[h], grown[h], plan.at[i]);
  }

  // soil, roots, then the trunk and branches (each after its host)
  const foot = f.at(m.splat3(0));
  try d.glow(foot[0], foot[1], @max(0.9 * f.k, 24), s.soil);
  for ([_]f32{-1, 0, 1}) |side| {
    const root:Stem = .build(m.splat3(0), -UP + side * ROOT_SPREAD, ROOT_LEN, 0, -side * 0.5);
    try stem(d, f, &root, ROOT_LEN, rad[0] * 0.8);
  }
  try stem(d, f, &l.stems[0], grown[0], rad[0]);
  for (plan.order[0..plan.branches]) |b| {
    const k = 1 + @as(usize, @intFromEnum(b));
    try stem(d, f, &l.stems[k], grown[k], rad[k]);
  }

  // each shown node's look: where it is hit, and what it grows into
  const hover:?Id = if (g.pointed) |p| switch (p) { .research => |id| id, else => null } else null;
  var mark:[N]?[2]f32 = @splat(null);
  for (0..N) |i| if (shown(&grown, i)) {
    const id:Id = @enumFromInt(i);
    const st = g.prog.status(id);
    const along = heading(l.ang[i]);
    const reach:f32 = if (st == .done) 0.5 else 0.25;
    mark[i] = if (!isBranch(i)) f.at(l.base[i] + along * m.splat3(PETIOLE + LEAF_LEN * reach))
      else if (st == .done) f.at(l.stems[1 + i].point(l.stems[1 + i].len))
      else f.at(l.stems[1 + i].point(grown[1 + i]) + heading(l.stems[1 + i].angle(grown[1 + i])) * m.splat3(BUD_LEN * BRANCH_BUD * 0.5));
  };

  // glows beneath: what is studied, what is pointed at, what can be chosen
  for (mark, 0..) |mk, i| if (mk) |c| {
    const id:Id = @enumFromInt(i);
    const r = @max(0.4 * f.k, 14);
    if (g.prog.current == id) try d.glow(c[0], c[1], r * 1.3, s.research_active)
    else if (hover == id) try d.glow(c[0], c[1], r, s.research_hover)
    else if (g.prog.status(id) == .open) try d.glow(c[0], c[1], r * 0.8, s.research_invite);
  };

  for (mark, 0..) |mk, i| if (mk) |c| {
    const id:Id = @enumFromInt(i);
    try node(d, f, &l, g, id, grown[1 + i], rad[0]);
    const hit = @max(0.7 * f.k, min_hit);
    g.rows.add(.{.x = c[0] - hit / 2, .y = c[1] - hit / 2, .w = hit, .h = hit}, .{.research = id});
  };

  try card(g, d, px, py + ph - card_h, hover orelse g.prog.current);
}

/// is node i drawn? Its host must be grown (the trunk always is) up to it.
fn shown(grown:*const [N + 1]f32, i:usize) bool {
  const h = stemOf(plan.host[i]);
  return (h == 0 or grown[h] > 0) and plan.at[i] <= grown[h] + 0.01;
}

/// a stem of base radius r0 grown to `at`, narrowing toward the growing tip.
fn radiusAt(r0:f32, gl:f32, at:f32) f32 { return r0 * (1 - TAPER * m.clamp01(at / @max(gl, m.EPS))); }

fn bark(r:f32) Color { return mix(s.bark_young, s.bark_old, r / OLD_R); }

/// draw a stem grown `gl` slots along, tapering to a point.
fn stem(d:*Draw, f:Fit, st:*const Stem, gl:f32, r0:f32) Allocator.Error!void {
  if (gl <= 0.01) return;
  const P = 8;
  var a0:f32 = 0;
  var p0 = f.at(st.point(0));
  var q0 = r0;
  for (1..P + 1) |j| {
    const a1 = gl * m.ratio(j, P);
    const p1 = f.at(st.point(a1));
    const q1 = radiusAt(r0, gl, a1);
    try d.limb(p0, p1, @max(q0 * f.k, 1.2), @max(q1 * f.k, 0.6), bark(q0), a0 * f.k);
    a0 = a1;
    p0 = p1;
    q0 = q1;
  }
}

/// one node: a leaf (petiole and blade) or a branch's bloom or bud.
fn node(d:*Draw, f:Fit, l:*const Layout, g:*const play.Game, id:Id, gl:f32, trunk_r:f32) Allocator.Error!void {
  const i:usize = @intFromEnum(id);
  const st = g.prog.status(id);
  const cur = g.prog.current == id;
  const seed = m.f(i) * 0.37;
  const fr = frac(g, id);
  if (isBranch(i)) {
    const stm = &l.stems[1 + i];
    if (st == .done) {
      const tip = f.at(stm.point(stm.len));
      return d.pod(tip[0], tip[1], @max(BLOOM_R * f.k, 4), s.research_tendril, 0.8, seed);
    }
    const at = if (cur) gl else 0;
    const base = f.at(stm.point(at));
    const k:f32 = if (st == .locked) BRANCH_BUD * 0.8 else BRANCH_BUD;
    return d.leaf(base, Fit.angle(stm.angle(at)), BUD_LEN * k * f.k, BUD_W * k * f.k, budColor(st), 0, seed);
  }
  // a stalk thin as the youngest twig, then the blade (or bud) at its end
  const a = l.ang[i];
  const p0 = f.at(l.base[i]);
  const p1 = f.at(l.base[i] + heading(a) * m.splat3(PETIOLE));
  try d.limb(p0, p1, @max(trunk_r * 0.35 * f.k, 1), @max(trunk_r * 0.25 * f.k, 0.8), s.bark_young, 0);
  const open:f32 = if (st == .done) 1 else if (cur) fr else 0;
  const k:f32 = if (st == .locked) 0.8 else 1;
  const len = m.lerp(BUD_LEN * k, LEAF_LEN, open);
  const wid = m.lerp(BUD_W * k, LEAF_W, open);
  const col = if (st == .done) s.leaf else mix(budColor(st), s.leaf, open);
  try d.leaf(p1, Fit.angle(a), len * f.k, wid * f.k, col, open, seed);
}

fn budColor(st:prog.Status) Color {
  return switch (st) { .locked => s.bud_dormant, .open, .done => s.bud };
}

/// what the hovered (or studied) node is: name, description, what each unit
/// eats and how long, its progress; or what it still waits for.
fn card(g:*const play.Game, d:*Draw, px:f32, y:f32, focus:?Id) Allocator.Error!void {
  const id = focus orelse return;
  const r = prog.tree.get(id);
  const st = g.prog.status(id);
  const col = if (g.prog.current == id) s.gold else switch (st) {
    .done => s.research_done,
    .open => s.white,
    .locked => s.research_locked,
  };
  const x = px + 56;
  _ = try d.text(x, y, s.text_row, col, txt.research(id).name);
  _ = try d.text(x, y + 24, s.text_fine, s.dim, txt.research(id).desc);
  if (st == .locked) {
    for (r.prereq) |q| if (!g.prog.done.contains(q)) {
      _ = try d.print(x, y + 46, s.text_fine, s.research_locked, txt.s.hud.research_dormant, .{txt.research(q).name});
      return;
    };
    _ = try d.text(x, y + 46, s.text_fine, s.research_locked, txt.s.hud.research_unwitnessed);
    return;
  }
  var cx = x;
  for (r.per_unit, 0..) |ing, j| {
    try d.grain(cx + 6, y + 51, 9, 13, ing.item.info().col, 0.6, m.f(j) * 0.3);
    cx = try d.print(cx + 14, y + 46, s.text_fine, s.dim, txt.s.hud.ingredient, .{ing.n, txt.item(ing.item).short}) + 10;
  }
  _ = try d.print(cx + 8, y + 46, s.text_fine, s.dim, txt.s.hud.research_cost, .{r.units, r.unit_time});
  try d.tendril(x, y + 70, tendril_w, tendril_h, col, frac(g, id), m.f(@intFromEnum(id)) * 0.21);
}

test "the sapling lays itself out: hosts grow first, nodes keep apart" {
  // every branch's host is the trunk or a branch earlier in the order
  for (plan.order[0..plan.branches], 0..) |b, n| if (plan.host[@intFromEnum(b)]) |h| {
    const before = indexOfScalar(Id, plan.order[0..n], h);
    try testing.expect(before != null);
  };
  // no two nodes (leaf middles, branch tips) crowd each other
  const l = layout(0, 0);
  var at:[N]V3 = undefined;
  for (0..N) |i| at[i] = if (isBranch(i)) l.stems[1 + i].point(l.stems[1 + i].len)
    else l.base[i] + heading(l.ang[i]) * m.splat3(PETIOLE + LEAF_LEN / 2);
  for (0..N) |i| for (i + 1..N) |j| try testing.expect(m.len(at[i] - at[j]) > 0.5);
}
