//! growth splines: the hidden skeleton a grown structure is built on and
//! grows along. Never drawn: a structure mesh lays out its splines first
//! (a trunk, then branches off it, offshoots off those), builds its pieces
//! along them with the usual primitives, and tags them (`along`, `on`).
//! Every tagged vertex then carries where it grows out of and when
//! (`vertex.Grow`), and part.vert grows it there on the GPU as the
//! structure's growth (`PartInstance.w.w`) passes: shrunk into its spline
//! until the spline's growth front reaches it, tapering to a point at the
//! front, thickening as its spline finishes. A spline grows only once the
//! one it branches off is done (unless told otherwise, `After`), so the
//! growing is laid out by the skeleton alone, never by hand.
//!
//!   var k = growth.Skeleton.begin(b);
//!   const stem = k.trunk(&.{...}, .{});
//!   try k.tube(b, stem, .{...});            // grows along the stem
//!   const twig = k.branch(stem, 0.7, &.{...}, .{});
//!   try k.leaves(b, twig, .{...});          // unfold as the twig passes
//!   k.finish(b);                            // times to shares of growth
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const m = @import("engine").core.math;
const mg = @import("meshgen.zig");
const vertex = @import("vertex.zig");
const color = @import("engine").core.color;
const Rng = @import("engine").core.rng.Rng;

const V3 = m.V3;

/// splines a skeleton may hold
pub const MAX = 48;
/// points each spline is resampled into, evenly by arc length
pub const RES = 33;
/// how long a spline's growth front is (it tapers to a point over it), as
/// a share of the time the spline takes to grow
pub const FRONT:f32 = 0.35;
/// shortest time a spline takes, so a stub never pops in at once
const MIN_TIME:f32 = 0.05;

pub const Id = enum(u8) {
  _,
  fn idx(id:Id) usize { return @intFromEnum(id); }
};

/// when a branch starts growing
pub const After = enum {
  /// once the spline it grows off is done (the default)
  done,
  /// as that spline's front passes the point it grows from
  passing,
  /// with that spline, from its first moment
  with,
};

pub const Branch = struct {
  /// how long it takes per unit of its length (2: twice as slow)
  pace:f32 = 1,
  after:After = .done,
  /// extra wait before it starts, in the skeleton's time units (per unit length)
  delay:f32 = 0,
  /// share of its own time its front is long (`FRONT`)
  front:f32 = FRONT,
};

pub const Spline = struct {
  pts:[RES]V3,
  /// its length
  len:f32,
  parent:?Id,
  /// how far along its parent it grows from (0..1)
  at:f32,
  /// when it starts and how long its front takes to reach its end (the
  /// skeleton's own time, made shares of the whole growth by `finish`)
  start:f32,
  time:f32,
  front:f32,
};

pub const Skeleton = struct {
  s:[MAX]Spline = undefined,
  n:usize = 0,
  /// the first vertex built on it (`finish` times what follows)
  first:usize,
  /// set by `finish`: no more may be added
  sealed:bool = false,
  /// the share of the whole growth kept after everything on it is grown,
  /// for pieces emitted on their own that form last (a germinator's cups
  /// and core): they `tag` themselves with `tailWindow`
  tail:f32 = 0,

  /// a skeleton for what `b` builds from here on
  pub fn begin(b:*const mg.Builder) Skeleton { return .{.first = b.mark()}; }

  /// the first spline, through the control points `ctrl` (a Catmull-Rom
  /// curve through them, so it never runs straight or kinks).
  pub fn trunk(k:*Skeleton, ctrl:[]const V3, o:Branch) Id {
    return k.add(null, 0, ctrl, o);
  }

  /// a spline off `parent` at `u` along it, through `ctrl` (its first point
  /// is moved onto the parent there, so it always grows out of it).
  pub fn branch(k:*Skeleton, parent:Id, u:f32, ctrl:[]const V3, o:Branch) Id {
    var c:[m.MAX_SPLINE]V3 = undefined;
    @memcpy(c[0..ctrl.len], ctrl);
    c[0] = k.point(parent, u);
    return k.add(parent, u, c[0..ctrl.len], o);
  }

  /// a branch grown the way a vine grows (`mg.Growth`, its `start`
  /// replaced by the point on `parent`), through `ctrl_n` control points.
  pub fn vine(k:*Skeleton, parent:?Id, u:f32, g:mg.Growth, ctrl_n:usize, o:Branch) Id {
    var gg = g;
    if (parent) |p| gg.start = k.point(p, u);
    var c:[m.MAX_SPLINE]V3 = undefined;
    mg.growthPath(gg, c[0..ctrl_n]);
    return k.add(parent, u, c[0..ctrl_n], o);
  }

  fn add(k:*Skeleton, parent:?Id, u:f32, ctrl:[]const V3, o:Branch) Id {
    assert(!k.sealed and k.n < MAX);
    var sp:Spline = .{.pts = undefined, .len = 0, .parent = parent, .at = m.clamp01(u), .start = 0, .time = 0, .front = o.front};
    m.splineResample(ctrl, &sp.pts);
    for (1..RES) |i| sp.len += m.len(sp.pts[i] - sp.pts[i - 1]);
    sp.time = @max(MIN_TIME, sp.len * o.pace);
    if (parent) |p| {
      const ps = k.s[p.idx()];
      sp.start = ps.start + o.delay * sp.len + switch (o.after) {
        .done => ps.time,
        .passing => ps.time * sp.at,
        .with => 0,
      };
    } else sp.start = o.delay * sp.len;
    k.s[k.n] = sp;
    k.n += 1;
    return @enumFromInt(k.n - 1);
  }

  /// done building: every time on it, and in what was built on it, made
  /// a share of the whole growth, the last piece closing at 1 (less its
  /// `tail`).
  pub fn finish(k:*Skeleton, b:*mg.Builder) void {
    assert(!k.sealed);
    k.sealed = true;
    var end:f32 = MIN_TIME;
    for (k.s[0..k.n]) |sp| end = @max(end, sp.start + sp.time * (1 + sp.front));
    const gs:[]vertex.Grow = if (k.first < b.grow.items.len) b.grow.items[k.first..] else &.{};
    for (gs) |g| end = @max(end, g.at[0] + g.at[1]);
    end /= 1 - k.tail;
    for (k.s[0..k.n]) |*sp| {
      sp.start /= end;
      sp.time /= end;
    }
    for (gs) |*g| for (&g.at) |*a| {
      a.* /= end;
    };
  }

  pub fn get(k:*const Skeleton, id:Id) *const Spline { return &k.s[id.idx()]; }

  /// the point `u` (0..1, by arc length) along a spline
  pub fn point(k:*const Skeleton, id:Id, u:f32) V3 { return m.alongPath(&k.s[id.idx()].pts, m.clamp01(u)); }

  /// the way a spline runs at `u` along it (unit)
  pub fn tangent(k:*const Skeleton, id:Id, u:f32) V3 {
    const d = 1.0 / @as(f32, RES - 1);
    return m.norm(k.point(id, u + d) - k.point(id, u - d));
  }

  /// the stretch `from..to` of a spline, evenly resampled into `out` (a tube,
  /// braid or leaf built along it)
  pub fn path(k:*const Skeleton, id:Id, from:f32, to:f32, out:[]V3) void {
    for (out, 0..) |*p, i| p.* = k.point(id, m.lerp(from, to, m.ratio(i, out.len - 1)));
  }

  /// when a spline's front reaches `u` along it (after `finish`, a share
  /// of the whole growth, 0..1)
  pub fn when(k:*const Skeleton, id:Id, u:f32) f32 {
    const sp = k.s[id.idx()];
    return sp.start + sp.time * m.clamp01(u);
  }

  /// when a spline has finished growing, its front closed at its tip
  pub fn done(k:*const Skeleton, id:Id) f32 {
    const sp = k.s[id.idx()];
    return sp.start + sp.time * (1 + sp.front);
  }

  /// how far along a spline (0..1) lies the point nearest `p`
  pub fn nearest(k:*const Skeleton, id:Id, p:V3) f32 {
    const pts = &k.s[id.idx()].pts;
    var best:f32 = m.inf(f32);
    var at:f32 = 0;
    for (0..RES - 1) |i| {
      const a = pts[i];
      const d = pts[i + 1] - a;
      const dd = m.dot(d, d);
      const t = if (dd > m.EPS) m.clamp01(m.dot(p - a, d) / dd) else 0;
      const q = a + d * m.splat3(t);
      const e = m.dot(p - q, p - q);
      if (e < best) {
        best = e;
        at = (m.f(i) + t) / @as(f32, RES - 1);
      }
    }
    return at;
  }

  /// everything built since `start` grows along spline `id`: each vertex
  /// out of its nearest point on it as the front passes there (a tube,
  /// braid or loft built along it grows from its root to its tip, its tip
  /// tapering), thickening until the spline is done.
  pub fn along(k:*const Skeleton, b:*mg.Builder, start:usize, id:Id) Allocator.Error!void {
    assert(!k.sealed);
    const sp = k.s[id.idx()];
    const span = sp.time * sp.front;
    const end = k.done(id);
    const gs = try b.growOf(start);
    for (b.v.items[start..], gs) |v, *g| {
      const u = k.nearest(id, v.pos);
      g.* = .{.from = k.point(id, u), .at = .{k.when(id, u), span, sp.start, end}};
    }
  }

  pub const On = struct {
    /// how long it takes to grow once begun, in the skeleton's time (null:
    /// as long as its spline's front)
    span:?f32 = null,
    /// how long after the front reaches it it begins, in the skeleton's time
    delay:f32 = 0,
    /// where it grows out of, if not the point on the spline
    from:?V3 = null,
  };

  /// everything built since `start` is one piece on spline `id` at `u` (a
  /// leaf, a cup, a pod): it grows out of that point (or `o.from`) once the
  /// front reaches it. Leaves unfold from their base, tips last (part.vert).
  pub fn on(k:*const Skeleton, b:*mg.Builder, start:usize, id:Id, u:f32, o:On) Allocator.Error!void {
    assert(!k.sealed);
    const t0 = k.when(id, u) + o.delay;
    const span = o.span orelse k.s[id.idx()].time * k.s[id.idx()].front;
    const from = o.from orelse k.point(id, u);
    for (try b.growOf(start)) |*g| g.* = .{.from = from, .at = .{t0, span, 0, 0}};
  }

  // ---- building along it: the usual primitives, grown on the spline ----

  pub const Tube = struct {
    r0:f32,
    /// its radius at the tip, a share of `r0`
    tip:f32 = 0.3,
    col:color.Rgba8,
    part:vertex.Part = .stem,
    sides:u32 = 6,
    /// its tu.x from root to tip
    t0:f32 = 0,
    t1:f32 = 1,
  };

  /// a tube the length of spline `id`, tapering, grown along it.
  pub fn tube(k:*const Skeleton, b:*mg.Builder, id:Id, o:Tube) Allocator.Error!void {
    var rs:[RES]f32 = undefined;
    var ts:[RES]f32 = undefined;
    mg.taperRadii(o.r0, o.tip, &rs);
    for (&ts, 0..) |*t, i| t.* = m.lerp(o.t0, o.t1, m.ratio(i, RES - 1));
    const s = b.mark();
    try b.tubeR(&k.s[id.idx()].pts, &ts, &rs, o.col, o.part, o.sides);
    try k.along(b, s, id);
  }

  pub const Braid = struct {
    girth:f32,
    tip:f32 = 0.35,
    strands:u32 = 3,
    twist:f32 = 2.2,
    wobble:f32,
    seed:u64,
    core:color.Rgba8,
    strand:color.Rgba8,
    t0:f32 = 0,
    t1:f32 = 0,
    /// the role of the core showing between its strands
    core_part:vertex.Part = .stem,
  };

  /// a braid (`mg.braid`) the length of spline `id`, grown along it.
  pub fn braid(k:*const Skeleton, b:*mg.Builder, id:Id, o:Braid) Allocator.Error!void {
    var rs:[RES]f32 = undefined;
    var ts:[RES]f32 = undefined;
    var turn:[RES]f32 = undefined;
    for (&rs, &ts, &turn, 0..) |*r, *t, *a, i| {
      const u = m.ratio(i, RES - 1);
      r.* = o.girth * m.lerp(1, o.tip, u);
      t.* = m.lerp(o.t0, o.t1, u);
      a.* = u * o.twist;
    }
    const s = b.mark();
    try mg.braidAround(b, &k.s[id.idx()].pts, &ts, &rs, &turn, o.strands, o.wobble, o.seed, o.core, o.strand, o.core_part);
    try k.along(b, s, id);
  }

  pub const Leaves = struct {
    n:u32,
    len:f32,
    width:f32,
    /// the stretch of the spline they sit along
    from:f32 = 0.15,
    to:f32 = 0.85,
    t0:f32 = 0,
    t1:f32 = 1,
    col:color.Rgba8,
    tip:color.Rgba8,
    seed:u64,
  };

  /// `n` leaves along spline `id` (as `mg.leavesAlong`), each unfolding
  /// from its base once the front has passed it.
  pub fn leaves(k:*const Skeleton, b:*mg.Builder, id:Id, o:Leaves) Allocator.Error!void {
    var rng = Rng.init(o.seed);
    for (0..o.n) |i| {
      const u = m.lerp(o.from, o.to, (m.f(i) + 0.5) / m.f(o.n));
      const s = b.mark();
      try mg.leafAt(b, &k.s[id.idx()].pts, u, i, o.len, o.width, o.t0, o.t1, o.col, o.tip, o.seed, &rng);
      try k.on(b, s, id, u, .{});
    }
  }
};

/// the window (when it begins, how long it takes, shares of the whole
/// growth) of the last `tail` of a structure's growth
pub fn tailWindow(tail:f32) [2]f32 { return .{1 - tail, tail}; }

/// how far a piece forming over the last `tail` of its structure's growth
/// has come when that growth is `g`: the same curve part.vert grows a
/// tagged piece by, for one the structure places itself
pub fn formed(tail:f32, g:f32) f32 { return m.smooth(m.clamp01((g - (1 - tail)) / tail)); }

/// everything built since `start` grows out of `from` over `window` of its
/// structure's growth: a piece built as a mesh of its own (emitted by the
/// structure) kept in step with the skeleton it stands on.
pub fn tag(b:*mg.Builder, start:usize, from:V3, window:[2]f32) Allocator.Error!void {
  for (try b.growOf(start)) |*g| g.* = .{.from = from, .at = .{window[0], window[1], 0, 0}};
}

test "branches wait for their spline, the whole closing at one" {
  var b:mg.Builder = .{.gpa = testing.allocator};
  defer b.deinit();
  var k = Skeleton.begin(&b);
  const t = k.trunk(&.{m.v3(0, 0, 0), m.v3(0, 0.5, 0), m.v3(0, 1, 0)}, .{});
  const a = k.branch(t, 0.5, &.{m.v3(0, 0, 0), m.v3(0.3, 0.7, 0), m.v3(0.6, 0.8, 0)}, .{});
  const p = k.branch(t, 0.5, &.{m.v3(0, 0, 0), m.v3(-0.3, 0.7, 0)}, .{.after = .passing});
  const c = k.branch(a, 1, &.{m.v3(0, 0, 0), m.v3(0.6, 1.1, 0)}, .{});
  k.finish(&b);
  // a branch starts on its parent, and grows once it is done
  try testing.expect(m.len(k.point(a, 0) - k.point(t, 0.5)) < 1e-4);
  try testing.expectApproxEqAbs(k.when(t, 1), k.when(a, 0), 1e-5);
  try testing.expectApproxEqAbs(k.when(a, 1), k.when(c, 0), 1e-5);
  // a passing one as the front goes by
  try testing.expectApproxEqAbs(k.when(t, 0.5), k.when(p, 0), 1e-5);
  try testing.expect(k.when(t, 0) == 0);
  var last:f32 = 0;
  for ([_]Id{t, a, p, c}) |id| last = @max(last, k.done(id));
  try testing.expectApproxEqAbs(@as(f32, 1), last, 1e-5);
  try testing.expect(k.nearest(t, m.v3(0.1, 0.25, 0)) > 0.2 and k.nearest(t, m.v3(0.1, 0.25, 0)) < 0.3);
}

test "pieces built along a spline grow from its root to its tip" {
  var b:mg.Builder = .{.gpa = testing.allocator};
  defer b.deinit();
  try b.put(m.v3(9, 9, 9), m.v3(0, 1, 0), WHITE, 0, 0, .stem); // before: untouched
  var k = Skeleton.begin(&b);
  const t = k.trunk(&.{m.v3(0, 0, 0), m.v3(0, 1, 0)}, .{});
  var p:[8]V3 = undefined;
  k.path(t, 0, 1, &p);
  const s = b.mark();
  try b.tube(&p, &(.{0} ** 8), 0.1, 0.05, WHITE, .stem, 6);
  try k.along(&b, s, t);
  // a leaf on it, built later, still closes by the end
  const l = b.mark();
  try mg.blade(&b, m.v3(0, 1, 0), m.v3(1, 0, 0), 0.3, 0.1, 0, WHITE, WHITE, 0, .leaf);
  try k.on(&b, l, t, 1, .{});
  k.tail = 0.2;
  k.finish(&b);
  try testing.expectApproxEqAbs(@as(f32, 0.8), b.grow.items[b.grow.items.len - 1].at[0] + b.grow.items[b.grow.items.len - 1].at[1], 1e-5);
  try testing.expect(b.grow.items[0].at[1] == 0);
  for (b.v.items[s..l], b.grow.items[s..l]) |v, g| {
    try testing.expect(m.len(@as(V3, g.from) - m.v3(0, v.pos[1], 0)) < 0.02);
    try testing.expectApproxEqAbs(v.pos[1] * k.get(t).time, g.at[0], 0.02);
  }
}

const WHITE = color.Rgba8{.r = 255, .g = 255, .b = 255, .a = 255};
