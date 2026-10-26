//! viewport gizmos for the tools' editors (tools/meshedit.zig,
//! tools/animedit.zig): handles drawn over the 3D view on the UI batch,
//! held at one size on screen, that move a point along an axis or across
//! the view, turn it about an axis, or size it along one. An editor says
//! where the gizmo stands and which way each handle's axis runs; a drag on
//! a handle comes back as metres or radians along that handle.
const std = ps.std;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const ps = @import("parasymi");
const engine = ps.engine;
const m = engine.core.math;
const Draw = engine.ui.draw.Draw;
const Color = engine.ui.draw.Color;
const s = ps.style;

const V3 = m.V3;
const v3 = m.v3;
const M4 = m.M4;

/// the gizmo's reach as a share of its distance from the eye (so it keeps
/// its size on screen)
const REACH:f32 = 0.14;
/// a ring's radius as a share of the reach; its segments
const RING:f32 = 0.85;
const SEGS = 48;
/// how near the mouse picks a handle, and a turn's least distance from the
/// centre (px)
const PICK:f32 = 10;
const NEAR_CENTRE:f32 = 4;
/// a handle seen end on (shorter than this on screen, px) cannot be dragged
const END_ON:f32 = 6;
/// a ring whose plane the eye's ray crosses this shallowly (cosine) is
/// turned by its angle on screen instead
const EDGE_ON:f32 = 0.15;
/// stroke radii, tip and centre radii (px)
const STROKE:f32 = 1.6;
const HOT_STROKE:f32 = 2.6;
const TIP_R:f32 = 6;
const SIZE_R:f32 = 4.5;
const CENTRE_R:f32 = 6;
/// each axis's colour (x rose, y leaf, z sky), a handle under the mouse or
/// held, and the alpha of a ring's far half
const AXIS_COL = [3]Color{ .{ 235, 120, 105, 255 }, .{ 150, 225, 110, 255 }, .{ 110, 170, 245, 255 } };
const HOT:Color = s.gold;
const CENTRE:Color = s.white;
const FAR_ALPHA = 80;

pub const Mode = enum { move, turn, size };
/// a handle: one of the three axes, or (moving) the centre, across the view
pub const Part = enum { x, y, z, free };

/// how the 3D view is seen this frame
pub const View = struct {
  vp:M4,
  eye:V3,
  screen:[2]f32,

  /// `p` (world) on screen, or null behind the eye
  pub fn project(v:View, p:V3) ?[2]f32 {
    const c = m.mulV(v.vp, .{ p[0], p[1], p[2], 1 });
    if (c[3] <= 1e-4) return null;
    return .{ (c[0] / c[3] * 0.5 + 0.5) * v.screen[0], (c[1] / c[3] * 0.5 + 0.5) * v.screen[1] };
  }

  /// where the ray through pixel `px` meets the plane through `at` across
  /// `n`, or null where it runs too nearly along the plane
  fn onPlane(v:View, px:[2]f32, at:V3, n:V3) ?V3 {
    const inv = m.inverse(v.vp);
    const x = px[0] / v.screen[0] * 2 - 1;
    const y = px[1] / v.screen[1] * 2 - 1;
    const a = m.mulV(inv, .{ x, y, 0, 1 });
    const b = m.mulV(inv, .{ x, y, 1, 1 });
    const o = v3(a[0], a[1], a[2]) / m.splat3(a[3]);
    const dir = m.norm(v3(b[0], b[1], b[2]) / m.splat3(b[3]) - o);
    const across = m.dot(dir, n);
    if (@abs(across) < EDGE_ON) return null;
    return o + dir * m.splat3(m.dot(at - o, n) / across);
  }
};

pub const Gizmo = struct {
  /// where it stands (world)
  at:V3,
  mode:Mode,
  /// each handle's axis in the world (unit); null where there is none
  axes:[3]?V3,

  fn reach(g:Gizmo, v:View) f32 { return m.len(g.at - v.eye) * REACH; }

  /// point `i` of `SEGS` round axis `k`'s ring
  fn ringPoint(g:Gizmo, a:V3, r:f32, i:usize) V3 {
    const t = m.tau * m.f(i) / SEGS;
    const ref = if (@abs(a[1]) < 0.9) v3(0, 1, 0) else v3(1, 0, 0);
    const u = m.norm(m.cross(a, ref));
    const w = m.cross(a, u);
    return g.at + (u * m.splat3(@cos(t)) + w * m.splat3(@sin(t))) * m.splat3(r);
  }

  /// the handle under `mouse`, if any
  pub fn pick(g:Gizmo, v:View, mouse:[2]f32) ?Part {
    const c = v.project(g.at) orelse return null;
    const r = g.reach(v);
    var best:f32 = PICK;
    var hit:?Part = null;
    if (g.mode == .move and dist2(c, mouse) < CENTRE_R + PICK / 2) return .free;
    for (g.axes, 0..) |ax, k| if (ax) |a| {
      const d = switch (g.mode) {
        .move, .size => if (v.project(g.at + a * m.splat3(r))) |tip| segDist(mouse, c, tip) else continue,
        .turn => ring: {
          var near:f32 = m.inf(f32);
          var prev = v.project(g.ringPoint(a, r * RING, 0));
          for (1..SEGS + 1) |i| {
            const cur = v.project(g.ringPoint(a, r * RING, i));
            if (prev != null and cur != null) near = @min(near, segDist(mouse, prev.?, cur.?));
            prev = cur;
          }
          break :ring near;
        },
      };
      if (d < best) {
        best = d;
        hit = @enumFromInt(k);
      }
    };
    return hit;
  }

  /// how far a drag from `from` to `to` (px) carries axis `k`: metres
  /// along it (moving, sizing) or radians about it (turning)
  pub fn along(g:Gizmo, v:View, k:usize, from:[2]f32, to:[2]f32) f32 {
    const a = g.axes[k] orelse return 0;
    const c = v.project(g.at) orelse return 0;
    switch (g.mode) {
      .move, .size => {
        const r = g.reach(v);
        const tip = v.project(g.at + a * m.splat3(r)) orelse return 0;
        const d = [2]f32{ tip[0] - c[0], tip[1] - c[1] };
        const l = @sqrt(d[0] * d[0] + d[1] * d[1]);
        if (l < END_ON) return 0;
        // pixels along the handle's line, over its pixels per metre
        return ((to[0] - from[0]) * d[0] + (to[1] - from[1]) * d[1]) / l / (l / r);
      },
      .turn => {
        if (dist2(from, c) < NEAR_CENTRE or dist2(to, c) < NEAR_CENTRE) return 0;
        // where the mouse meets the ring's plane, turned about the axis
        if (v.onPlane(from, g.at, a)) |p0| if (v.onPlane(to, g.at, a)) |p1| {
          const q0 = p0 - g.at;
          const q1 = p1 - g.at;
          return m.atan2(m.dot(m.cross(q0, q1), a), m.dot(q0, q1));
        };
        // the ring seen edge on: by the angle round its centre on screen
        const da = m.angleDiff(m.atan2(from[1] - c[1], from[0] - c[0]), m.atan2(to[1] - c[1], to[0] - c[0]));
        // screen y runs down: an axis toward the eye turns the other way round
        return if (m.dot(a, v.eye - g.at) > 0) -da else da;
      },
    }
  }

  /// where a drag of the centre from `from` to `to` (px) carries it, across
  /// the view at its depth (world metres)
  pub fn across(g:Gizmo, v:View, from:[2]f32, to:[2]f32) V3 {
    const fw = m.norm(g.at - v.eye);
    const right = m.norm(m.cross(fw, v3(0, 1, 0)));
    const up = m.cross(right, fw);
    const r = g.reach(v);
    const c = v.project(g.at) orelse return v3(0, 0, 0);
    const px = v.project(g.at + right * m.splat3(r)) orelse return v3(0, 0, 0);
    const per = dist2(px, c) / r;
    if (per < m.EPS) return v3(0, 0, 0);
    return (right * m.splat3(to[0] - from[0]) - up * m.splat3(to[1] - from[1])) * m.splat3(1 / per);
  }

  /// drawn over the view, `hot` (under the mouse or held) in gold
  pub fn draw(g:Gizmo, d:*Draw, v:View, hot:?Part) Allocator.Error!void {
    const c = v.project(g.at) orelse return;
    const r = g.reach(v);
    for (g.axes, 0..) |ax, k| if (ax) |a| {
      const lit = hot != null and @intFromEnum(hot.?) == k;
      const col = if (lit) HOT else AXIS_COL[k];
      const w = if (lit) HOT_STROKE else STROKE;
      switch (g.mode) {
        .move, .size => {
          const tip = v.project(g.at + a * m.splat3(r)) orelse continue;
          try d.limb(c, tip, w, w, col, 0);
          if (g.mode == .move) try d.leaf(tip, m.atan2(tip[1] - c[1], tip[0] - c[0]), TIP_R * 2, TIP_R * 1.4, col, 0, m.f(k)) else try d.pod(tip[0], tip[1], SIZE_R, col, 1, m.f(k));
        },
        .turn => {
          var prev = g.ringPoint(a, r * RING, 0);
          for (1..SEGS + 1) |i| {
            const cur = g.ringPoint(a, r * RING, i);
            const p0 = v.project(prev);
            const p1 = v.project(cur);
            // the ring's half beyond the centre, seen from the eye, faint
            const near = m.dot((prev + cur) * m.splat3(0.5) - g.at, v.eye - g.at) >= 0;
            var cc = col;
            if (!near) cc[3] = FAR_ALPHA;
            if (p0 != null and p1 != null) try d.limb(p0.?, p1.?, w, w, cc, m.f(i));
            prev = cur;
          }
        },
      }
    };
    if (g.mode == .move) try d.pod(c[0], c[1], CENTRE_R, if (hot == .free) HOT else CENTRE, 1, 0) else try d.pod(c[0], c[1], CENTRE_R * 0.6, CENTRE, 1, 0);
  }
};

fn dist2(a:[2]f32, b:[2]f32) f32 { return m.len(v3(a[0] - b[0], a[1] - b[1], 0)); }

/// from `p` to the segment `a`..`b` (px)
fn segDist(p:[2]f32, a:[2]f32, b:[2]f32) f32 {
  const ab = v3(b[0] - a[0], b[1] - a[1], 0);
  const ap = v3(p[0] - a[0], p[1] - a[1], 0);
  const l2 = m.dot(ab, ab);
  const t = if (l2 > m.EPS) m.clamp01(m.dot(ap, ab) / l2) else 0;
  return m.len(ap - ab * m.splat3(t));
}

fn testView(eye:V3) View {
  const vp = m.mul(m.perspective(m.rad(50), 16.0 / 9.0, 0.05, 100), m.lookAt(eye, v3(0, 0, 0), v3(0, 1, 0)));
  return .{ .vp = vp, .eye = eye, .screen = .{ 1600, 900 } };
}

test "a turn's drag reads as the turn that carries a point there" {
  for ([_]V3{ v3(2, 1.5, 3), v3(-3, 2, -2) }) |eye| {
    const v = testView(eye);
    const turns = [3]M4{ m.rotX(0.1), m.rotY(0.1), m.rotZ(0.1) };
    const axes = [3]V3{ v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1) };
    for (turns, axes, 0..) |t, a, k| {
      const g:Gizmo = .{ .at = v3(0, 0, 0), .mode = .turn, .axes = .{ a, a, a } };
      // a point off the axis, turned by 0.1 about it
      const p = m.norm(m.cross(a, v3(0.3, 0.5, 0.7))) * m.splat3(0.5);
      const got = g.along(v, k, v.project(p).?, v.project(m.mulPoint(t, p)).?);
      try testing.expectApproxEqAbs(@as(f32, 0.1), got, 0.002);
    }
  }
}

test "a move's drag reads as the metres along the handle" {
  const v = testView(v3(2, 1.5, 3));
  const g:Gizmo = .{ .at = v3(0, 0, 0), .mode = .move, .axes = .{ v3(1, 0, 0), v3(0, 1, 0), v3(0, 0, 1) } };
  for (0..3) |k| {
    const step = g.axes[k].? * m.splat3(0.05);
    const got = g.along(v, k, v.project(g.at).?, v.project(step).?);
    try testing.expectApproxEqAbs(@as(f32, 0.05), got, 0.01);
  }
  // across the view: back where the mouse went
  const to = v.project(v3(0.05, 0.03, 0)).?;
  const moved = g.across(v, v.project(g.at).?, to);
  const back = v.project(moved).?;
  try testing.expectApproxEqAbs(to[0], back[0], 2);
  try testing.expectApproxEqAbs(to[1], back[1], 2);
}

test "a handle is picked where it is drawn" {
  const v = testView(v3(2, 1.5, 3));
  const g:Gizmo = .{ .at = v3(0, 0, 0), .mode = .size, .axes = .{ v3(1, 0, 0), null, v3(0, 0, 1) } };
  const r = g.reach(v);
  try testing.expectEqual(Part.x, g.pick(v, v.project(v3(r * 0.7, 0, 0)).?).?);
  try testing.expectEqual(Part.z, g.pick(v, v.project(v3(0, 0, r * 0.7)).?).?);
  // no y handle
  try testing.expect(g.pick(v, v.project(v3(0, r * 0.7, 0)).?) == null);
}
