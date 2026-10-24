//! shared pieces for the wolf's body: the leaves that lie over it like fur
//! and the digits of its hands and feet (forms of planes: superellipsoids,
//! flat faces, rounded edges, with curved claws). Not a mesh itself; the
//! wolf's meshes use it.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const color = @import("../../core/color.zig");
const vertex = @import("../vertex.zig");

const V3 = m.V3;
const v3 = m.v3;

fn spow(c:f32, e:f32) f32 { return m.sign(c) * m.pow(f32, @abs(c), e); }

pub const Form = struct {
  center:V3,
  radii:V3,
  /// squareness down its height (`ns`) and around it (`ew`): 1 round,
  /// toward 0 flat faces with sharper edges
  ns:f32 = 0.7,
  ew:f32 = 0.7,
  col:color.Rgba8,
  part:vertex.Part = .stem,
  t:f32 = 0.5,
  rings:u32 = 10,
  segs:u32 = 14,
};

fn formPoint(f:Form, th:f32, ph:f32) V3 {
  const ct = spow(@cos(th), f.ns);
  return f.center + v3(f.radii[0] * ct * spow(@cos(ph), f.ew), f.radii[1] * spow(@sin(th), f.ns), f.radii[2] * ct * spow(@sin(ph), f.ew));
}

fn formNormal(f:Form, th:f32, ph:f32) V3 {
  const ct = spow(@cos(th), 2 - f.ns);
  return m.norm(v3(ct * spow(@cos(ph), 2 - f.ew) / f.radii[0], spow(@sin(th), 2 - f.ns) / f.radii[1], ct * spow(@sin(ph), 2 - f.ew) / f.radii[2]));
}

/// a solid form with defined faces: a superellipsoid, closed at its poles.
pub fn form(b:*mg.Builder, f0:Form) Allocator.Error!void {
  var f = f0;
  f.rings = b.around(f0.rings, 4);
  f.segs = b.around(f0.segs, 6);
  for (0..f.rings) |i| for (0..f.segs) |j| {
    const th0 = -m.pi / 2.0 + m.pi * m.ratio(i, f.rings);
    const th1 = -m.pi / 2.0 + m.pi * m.ratio(i + 1, f.rings);
    const ph0 = m.tau * m.ratio(j, f.segs);
    const ph1 = m.tau * m.ratio(j + 1, f.segs);
    const q = [4][2]f32{.{th0, ph0}, .{th0, ph1}, .{th1, ph1}, .{th1, ph0}};
    var p:[4]V3 = undefined;
    var n:[4]V3 = undefined;
    for (q, 0..) |c, k| {
      p[k] = formPoint(f, c[0], c[1]);
      n[k] = formNormal(f, c[0], c[1]);
    }
    // front faces wind counter-clockwise seen from outside
    // (the quad 0,3,2,1's normal from its diagonals, robust at the poles)
    const flip = m.dot(m.cross(p[2] - p[0], p[1] - p[3]), n[0] + n[1] + n[2] + n[3]) < 0;
    const order = if (flip) [_]usize{0, 1, 2, 0, 2, 3} else [_]usize{0, 2, 1, 0, 3, 2};
    for (order) |c| try b.put(p[c], n[c], f.col, f.t, 0, f.part);
  };
}

pub const Leaf = struct {
  /// where it grows from, flush with the surface
  base:V3,
  /// the way it lies along the surface (unit, tangent to it)
  along:V3,
  /// the surface's outward normal there
  out:V3,
  len:f32,
  width:f32,
  /// how far its tip has lifted off the surface (radians)
  lift:f32 = 0.35,
  /// how much the tip curls back over toward the surface, like an
  /// unfurled frond settling (radians at the tip)
  curl:f32 = 0.25,
  /// cupped across its width, edges toward the surface
  cup:f32 = 0.25,
  col:color.Rgba8,
  tip:color.Rgba8,
  t:f32 = 1,
};

/// a leaf lying over the body like fur: its base flush with the surface it
/// emerges from, lifting off it and curling back toward it at the tip. One
/// shared-vertex sheet, tu.y running base to tip (the part shader moves the
/// tips, never the base).
pub fn leaf(b:*mg.Builder, l:Leaf) Allocator.Error!void {
  const R = 8;
  const C = 5;
  const side = m.norm(m.cross(l.out, l.along));
  var spine:[R]V3 = undefined;
  var face:[R]V3 = undefined;
  spine[0] = l.base;
  for (0..R) |i| {
    const k = m.ratio(i, R - 1);
    const h = l.lift * m.pow(f32, k, 0.7) - l.curl * k * k * k;
    const dir = l.along * m.splat3(@cos(h)) + l.out * m.splat3(@sin(h));
    if (i > 0) spine[i] = spine[i - 1] + dir * m.splat3(l.len / (R - 1));
    face[i] = m.norm(m.cross(dir, side));
  }
  var pts:[R * C]V3 = undefined;
  var ns:[R * C]V3 = undefined;
  var cs:[R * C]color.Rgba8 = undefined;
  var us:[R * C]f32 = undefined;
  for (0..R) |i| {
    const k = m.ratio(i, R - 1);
    // lanceolate: a narrow claw, broadest a third along, a long point
    const w = l.width * @sqrt(@max(@sin(m.pi * m.pow(f32, k, 0.75)), 0)) * (1 - 0.35 * k);
    for (0..C) |j| {
      const u = m.ratio(j, C - 1) * 2 - 1;
      pts[i * C + j] = spine[i] + side * m.splat3(w * u) - face[i] * m.splat3(l.cup * w * u * u);
      cs[i * C + j] = color.mix(l.col, l.tip, k);
      us[i * C + j] = k;
    }
  }
  for (0..R) |i| for (0..C) |j| {
    const dk = pts[@as(usize, @min(i + 1, R - 1)) * C + j] - pts[(if (i == 0) 0 else i - 1) * C + j];
    const du = pts[i * C + @min(j + 1, C - 1)] - pts[i * C + (if (j == 0) 0 else j - 1)];
    var n = m.cross(dk, du);
    if (m.len(n) < 1e-9) n = face[i];
    if (m.dot(n, face[i]) < 0) n = -n;
    ns[i * C + j] = m.norm(n);
  };
  try mg.patch(b, R, C, &pts, &ns, &cs, &us, l.t, .leaf);
}

test "a fur leaf's base stays on the surface it grows from" {
  var b:mg.Builder = .{.gpa = std.testing.allocator};
  defer b.deinit();
  try leaf(&b, .{.base = v3(0, 1, 0), .along = v3(0, 0, -1), .out = v3(0, 1, 0), .len = 0.1, .width = 0.02, .col = .{.r = 0, .g = 0, .b = 0, .a = 255}, .tip = .{.r = 0, .g = 0, .b = 0, .a = 255}});
  for (b.v.items) |vx| if (vx.tu[1] == 0) try std.testing.expectApproxEqAbs(@as(f32, 1), vx.pos[1], 1e-5);
}

/// a claw: a curved, tapering hook from `base` along `dir`, bending toward
/// `down` as it goes, closed to a point.
pub fn claw(b:*mg.Builder, base:V3, dir:V3, down:V3, len:f32, r:f32, col:color.Rgba8) Allocator.Error!void {
  const N = 7;
  var path:[N]V3 = undefined;
  var ts:[N]f32 = undefined;
  var rs:[N]f32 = undefined;
  path[0] = base;
  for (0..N) |i| {
    const k = m.ratio(i, N - 1);
    const d = m.norm(dir * m.splat3(@cos(k * 1.1)) + down * m.splat3(@sin(k * 1.1)));
    if (i > 0) path[i] = path[i - 1] + d * m.splat3(len / (N - 1));
    ts[i] = 0;
    rs[i] = r * (1 - k) + 0.0006;
  }
  try b.tubeR(&path, &ts, &rs, col, .thorn, 5);
}

/// a digit: a knuckle, a finger or toe arching from `base` along `dir` and
/// down to the ground (`down`), and its claw. Segments are forms of planes.
pub const Digit = struct {
  base:V3,
  dir:V3,
  down:V3 = v3(0, -1, 0),
  len:f32,
  r:f32,
  col:color.Rgba8,
  claw:color.Rgba8,
};

pub fn digit(b:*mg.Builder, d:Digit) Allocator.Error!void {
  const side = m.norm(m.cross(d.down, d.dir));
  // knuckle, then two segments, each a little lower and narrower
  const segs = [_]struct { at:f32, drop:f32, w:f32, l:f32 }{
    .{.at = 0.0, .drop = 0.0, .w = 1.15, .l = 0.42},
    .{.at = 0.42, .drop = 0.25, .w = 0.95, .l = 0.36},
    .{.at = 0.75, .drop = 0.55, .w = 0.8, .l = 0.3},
  };
  for (segs) |sg| {
    const c = d.base + d.dir * m.splat3(d.len * sg.at) + d.down * m.splat3(d.r * sg.drop);
    const s = b.mark();
    try form(b, .{.center = v3(0, 0, 0), .radii = v3(d.r * sg.w, d.r * sg.w * 0.85, d.len * sg.l * 0.62), .ns = 0.75, .ew = 0.65, .col = d.col, .rings = 7, .segs = 9});
    // align the segment: its length along dir, its top away from down
    const up = -m.norm(m.cross(d.dir, side));
    b.xform(s, .{
      .{side[0], side[1], side[2], 0},
      .{up[0], up[1], up[2], 0},
      .{d.dir[0], d.dir[1], d.dir[2], 0},
      .{c[0], c[1], c[2], 1},
    });
  }
  const tip = d.base + d.dir * m.splat3(d.len * 0.98) + d.down * m.splat3(d.r * 0.55);
  try claw(b, tip, d.dir, d.down, d.r * 1.6, d.r * 0.42, d.claw);
}

