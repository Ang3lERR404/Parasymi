//! sculpting one seamless surface out of many forms: each form (an
//! ellipsoid, a rounded cone, a rounded box) is a signed distance field,
//! the forms melt into one another by smooth union (or are carved away by
//! smooth subtraction), and the whole is meshed once at startup with
//! surface nets: one vertex per surface cell, pulled onto the surface,
//! its normal the field's gradient. Every form belongs to a bone, so each
//! vertex is also weighted to the bones of the forms it lies nearest
//! (smoothly, only along joints that are actually joined), and the mesh
//! bends as one skin (vertex.Skin, part.vert's skinned mode).
//!
//! The field is sampled sparsely: only blocks of cells the surface can
//! pass through are evaluated, and each block only with the forms that
//! can reach it.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const color = @import("../../core/color.zig");
const vertex = @import("../vertex.zig");

const V3 = m.V3;
const v3 = m.v3;
const M4 = m.M4;

pub const Shape = union(enum) {
  /// centre and radii
  ellipsoid:struct { c:V3, r:V3 },
  /// a cone from `a` (radius `ra`) to `b` (radius `rb`), rounded at both ends
  cone:struct { a:V3, b:V3, ra:f32, rb:f32 },
  /// centre, half extents (rounding included) and the rounding radius
  box:struct { c:V3, half:V3, round:f32 },
};

pub const Form = struct {
  shape:Shape,
  /// where its shape space sits (in the space the surface is built in)
  at:M4 = m.identity,
  /// shape space stretched by this before it is placed (a wide muzzle from
  /// a round cone); the distance is scaled back, near enough at the surface
  stretch:V3 = .{1, 1, 1},
  bone:u8,
  col:color.Rgba8,
  /// how far it melts into what is there before it (metres)
  k:f32 = 0.03,
  /// cut away instead of added
  carve:bool = false,
  /// only colours the surface where it lies (fading over this many metres
  /// outside it), adding nothing: a lip line, the dark round an eye
  ink:f32 = 0,
  /// how softly the skin passes across the joints of its bone (metres;
  /// 0 the sculpt's own): small for a finger, so it bends at its knuckles
  soft:f32 = 0,
};

/// a form ready to evaluate: back from the build space to its shape space,
/// and the sphere it lies in (plus its melt)
const Placed = struct {
  f:Form,
  inv:M4,
  centre:V3,
  reach:f32,
  shrink:f32,
};

fn smin(a:f32, b:f32, k:f32) f32 {
  if (k <= 0) return @min(a, b);
  const h = @max(k - @abs(a - b), 0) / k;
  return @min(a, b) - h * h * k * 0.25;
}
fn smax(a:f32, b:f32, k:f32) f32 { return -smin(-a, -b, k); }

fn ellipsoid(p:V3, r:V3) f32 {
  const k0 = m.len(p / r);
  const k1 = m.len(p / (r * r));
  if (k1 < 1e-9) return -@reduce(.Min, r);
  return k0 * (k0 - 1) / k1;
}

fn roundCone(p:V3, a:V3, b:V3, r1:f32, r2:f32) f32 {
  const ba = b - a;
  const l2 = m.dot(ba, ba);
  const rr = r1 - r2;
  const a2 = l2 - rr * rr;
  const il2 = 1 / l2;
  const pa = p - a;
  const y = m.dot(pa, ba);
  const z = y - l2;
  const q = pa * m.splat3(l2) - ba * m.splat3(y);
  const x2 = m.dot(q, q);
  const y2 = y * y * l2;
  const z2 = z * z * l2;
  const k = m.sign(rr) * rr * rr * x2;
  if (m.sign(z) * a2 * z2 > k) return @sqrt(x2 + z2) * il2 - r2;
  if (m.sign(y) * a2 * y2 < k) return @sqrt(x2 + y2) * il2 - r1;
  return (@sqrt(x2 * a2 * il2) + y * rr) * il2 - r1;
}

fn roundBox(p:V3, half:V3, r:f32) f32 {
  const q = @abs(p) - half + m.splat3(r);
  const out = @max(q, m.splat3(0));
  return m.len(out) + @min(@reduce(.Max, q), 0) - r;
}

fn shapeDist(s:Shape, p:V3) f32 {
  return switch (s) {
    .ellipsoid => |e| ellipsoid(p - e.c, e.r),
    .cone => |c| roundCone(p, c.a, c.b, c.ra, c.rb),
    .box => |x| roundBox(p - x.c, x.half, x.round),
  };
}

/// the sphere (centre, radius) a shape lies in, in its own space
fn shapeBound(s:Shape) struct { c:V3, r:f32 } {
  return switch (s) {
    .ellipsoid => |e| .{ .c = e.c, .r = @reduce(.Max, e.r) },
    .cone => |c| .{ .c = (c.a + c.b) * m.splat3(0.5), .r = m.len(c.b - c.a) * 0.5 + @max(c.ra, c.rb) },
    .box => |x| .{ .c = x.c, .r = m.len(x.half) },
  };
}

fn xf(mat:M4, p:V3) V3 {
  const r = m.mulV(mat, .{ p[0], p[1], p[2], 1 });
  return v3(r[0], r[1], r[2]);
}

fn colV(c:color.Rgba8) V3 { return v3(m.f(c.r), m.f(c.g), m.f(c.b)); }

/// a point on the surface and its outward normal there
pub const Hit = struct { p:V3, n:V3 };

pub const Sculpt = struct {
  gpa:Allocator,
  forms:std.ArrayList(Placed) = .empty,
  /// every form's index, for the few points asked about outside a build
  every:std.ArrayList(u32) = .empty,
  /// each bone's parent (weights only spread along joints)
  parents:[]const ?u8,
  /// how softly a vertex's weight passes from one bone to the next across
  /// a joint (metres)
  soft:f32 = 0.02,
  /// how softly colours meet where forms meet (metres)
  blend:f32 = 0.012,
  /// the bones whose forms it keeps (a bit each); the rest are left out,
  /// for a surface cast onto only part of a body
  only:u64 = ~@as(u64, 0),

  pub fn deinit(s:*Sculpt) void {
    s.forms.deinit(s.gpa);
    s.every.deinit(s.gpa);
  }

  pub fn add(s:*Sculpt, f:Form) Allocator.Error!void {
    if (s.only & (@as(u64, 1) << @intCast(f.bone)) == 0) return;
    const bound = shapeBound(f.shape);
    const grow = @reduce(.Max, f.stretch);
    try s.every.append(s.gpa, @intCast(s.forms.items.len));
    var scale:f32 = 0;
    for (0..3) |c| scale = @max(scale, m.len(v3(f.at[c][0], f.at[c][1], f.at[c][2])));
    try s.forms.append(s.gpa, .{
      .f = f,
      .inv = m.inverseAffine(f.at),
      .centre = xf(f.at, bound.c * f.stretch),
      .reach = bound.r * grow * scale + f.k + f.ink * 4,
      .shrink = @reduce(.Min, f.stretch),
    });
  }

  fn formDist(pf:*const Placed, p:V3) f32 {
    const q = xf(pf.inv, p) / pf.f.stretch;
    return shapeDist(pf.f.shape, q) * pf.shrink;
  }

  /// the field at `p` from the forms listed (indices into `forms`)
  fn dist(s:*const Sculpt, p:V3, list:[]const u32) f32 {
    var d:f32 = 1e9;
    for (list) |i| {
      const pf = &s.forms.items[i];
      if (pf.f.ink > 0) continue;
      const di = formDist(pf, p);
      d = if (pf.f.carve) smax(d, -di, pf.f.k) else smin(d, di, pf.f.k);
    }
    return d;
  }

  fn grad(s:*const Sculpt, p:V3, list:[]const u32, e:f32) V3 {
    const dx = s.dist(p + v3(e, 0, 0), list) - s.dist(p - v3(e, 0, 0), list);
    const dy = s.dist(p + v3(0, e, 0), list) - s.dist(p - v3(0, e, 0), list);
    const dz = s.dist(p + v3(0, 0, e), list) - s.dist(p - v3(0, 0, e), list);
    const g = v3(dx, dy, dz);
    const l = m.len(g);
    return if (l < 1e-12) v3(0, 1, 0) else g / m.splat3(l);
  }


  /// the surface point nearest `p` (a few steps down the field) and the
  /// outward normal there
  pub fn project(s:*const Sculpt, p0:V3) Allocator.Error!Hit {
    const list = s.every.items;
    var p = p0;
    for (0..6) |_| {
      const d = s.dist(p, list);
      p -= s.grad(p, list, 0.001) * m.splat3(d);
    }
    return .{ .p = p, .n = s.grad(p, list, 0.001) };
  }

  /// where a ray from `from` (inside the body) along `dir` comes out of it,
  /// and the outward normal there; null if it never does within `max`
  pub fn cast(s:*const Sculpt, from:V3, dir:V3, max:f32) Allocator.Error!?Hit {
    const list = s.every.items;
    var t:f32 = 0;
    var last:f32 = 0;
    while (t < max) {
      const d = s.dist(from + dir * m.splat3(t), list);
      if (d >= 0) {
        // between the last step inside and this one: halve down to it
        var lo = last;
        var hi = t;
        for (0..12) |_| {
          const mid = (lo + hi) * 0.5;
          if (s.dist(from + dir * m.splat3(mid), list) < 0) lo = mid else hi = mid;
        }
        const p = from + dir * m.splat3(hi);
        return .{ .p = p, .n = s.grad(p, list, 0.001) };
      }
      last = t;
      t += @max(-d, 0.002);
    }
    return null;
  }

  /// the skin weights at `p`: the bones of the nearest forms, softly,
  /// but only the nearest one's parent and children besides it
  pub fn weigh(s:*const Sculpt, p:V3) Allocator.Error!vertex.Skin {
    return s.weighFrom(p, s.every.items);
  }

  fn weighFrom(s:*const Sculpt, p:V3, list:[]const u32) vertex.Skin {
    const MAXB = 64;
    var near:[MAXB]f32 = @splat(1e9);
    var soft:[MAXB]f32 = @splat(s.soft);
    for (list) |i| {
      const pf = &s.forms.items[i];
      if (pf.f.carve or pf.f.ink > 0) continue;
      near[pf.f.bone] = @min(near[pf.f.bone], formDist(pf, p));
      if (pf.f.soft > 0) soft[pf.f.bone] = @min(soft[pf.f.bone], pf.f.soft);
    }
    var first:usize = 0;
    for (near, 0..) |d, b| if (d < near[first]) {
      first = b;
    };
    var w:[MAXB]f32 = @splat(0);
    for (0..s.parents.len) |b| {
      const joined = b == first or s.parents[first] == @as(u8, @intCast(b)) or s.parents[b] == @as(u8, @intCast(first));
      if (!joined or near[b] > 1e8) continue;
      w[b] = @exp(-(near[b] - near[first]) / @min(soft[b], soft[first]));
    }
    return pack(&w);
  }

  /// a skin from weights per bone: the four heaviest, summing to one
  pub fn pack(w:[]const f32) vertex.Skin {
    var idx:[4]u8 = .{ 0, 0, 0, 0 };
    var wt:[4]f32 = .{ 0, 0, 0, 0 };
    for (w, 0..) |x, b| {
      if (x <= wt[3]) continue;
      var k:usize = 3;
      while (k > 0 and x > wt[k - 1]) : (k -= 1) {
        wt[k] = wt[k - 1];
        idx[k] = idx[k - 1];
      }
      wt[k] = x;
      idx[k] = @intCast(b);
    }
    // drop the slightest, so a bone barely there does not drag the skin
    var sum:f32 = 0;
    for (&wt) |*x| {
      if (x.* < 0.03 * wt[0]) x.* = 0;
      sum += x.*;
    }
    var out:vertex.Skin = .{};
    var left:i32 = 255;
    for (0..4) |k| {
      const q:i32 = if (k == 3) left else @intFromFloat(@round(wt[k] / sum * 255));
      const c = std.math.clamp(@min(q, left), 0, 255);
      out.weights[k] = @intCast(c);
      left -= c;
      out.bones |= @as(u32, idx[k]) << @intCast(8 * k);
    }
    return out;
  }

  /// `pack`, with how each bone's weight changes across the mesh (`slope`,
  /// per bone like `w`), so the skin's normals bend as it truly does
  pub fn packWith(w:[]const f32, slope:[]const V3) vertex.Skin {
    var out = pack(w);
    for (0..4) |k| {
      if (out.weights[k] == 0) continue;
      const g = slope[(out.bones >> @intCast(8 * k)) & 255];
      out.gx[k] = g[0];
      out.gy[k] = g[1];
      out.gz[k] = g[2];
    }
    return out;
  }

  /// the field's colour at `p`: the forms' colours meeting softly where
  /// they meet
  fn colourFrom(s:*const Sculpt, p:V3, list:[]const u32) V3 {
    var best:f32 = 1e9;
    for (list) |i| {
      const pf = &s.forms.items[i];
      if (!pf.f.carve and pf.f.ink == 0) best = @min(best, formDist(pf, p));
    }
    var c = v3(0, 0, 0);
    var sum:f32 = 0;
    for (list) |i| {
      const pf = &s.forms.items[i];
      if (pf.f.carve) continue;
      const d = formDist(pf, p);
      const w =if (pf.f.ink > 0) 8 * @exp(-@max(d, 0) / pf.f.ink) else @exp(-(d - best) / s.blend);
      c += colV(pf.f.col) * m.splat3(w);
      sum += w;
    }
    return c / m.splat3(@max(sum, 1e-9));
  }

  /// mesh the surface with cells `h` across, every vertex `part` with tu
  /// (`t`, 0), weighted to its bones.
  pub fn mesh(s:*const Sculpt, b:*mg.Builder, h:f32, t:f32, part:vertex.Part) Allocator.Error!void {
    const gpa = s.gpa;
    var lo = m.splat3(1e9);
    var hi = m.splat3(-1e9);
    for (s.forms.items) |pf| {
      if (pf.f.carve or pf.f.ink > 0) continue;
      lo = @min(lo, pf.centre - m.splat3(pf.reach));
      hi = @max(hi, pf.centre + m.splat3(pf.reach));
    }
    lo -= m.splat3(2 * h);
    hi += m.splat3(2 * h);
    const B = 8;
    const S = B + 1;
    var nb:[3]usize = undefined;
    inline for (0..3) |c| nb[c] = @as(usize, @intFromFloat(@ceil((hi[c] - lo[c]) / (h * B)))) + 1;
    const NONE = std.math.maxInt(u32);
    const map = try gpa.alloc(u32, nb[0] * nb[1] * nb[2]);
    defer gpa.free(map);
    @memset(map, NONE);

    const Block = struct {
      at:[3]usize,
      vals:[S * S * S]f32,
      vid:[B * B * B]u32,
      cand:[]u32,
    };
    var blocks:std.ArrayList(Block) = .empty;
    defer {
      for (blocks.items) |*bl| gpa.free(bl.cand);
      blocks.deinit(gpa);
    }
    var cand:std.ArrayList(u32) = .empty;
    defer cand.deinit(gpa);

    // which blocks the surface can pass through, sampled
    const half = h * B * 0.5 * @sqrt(3.0);
    for (0..nb[2]) |bz| for (0..nb[1]) |by| for (0..nb[0]) |bx| {
      const c = lo + v3(m.f(bx * B) + B * 0.5, m.f(by * B) + B * 0.5, m.f(bz * B) + B * 0.5) * m.splat3(h);
      cand.clearRetainingCapacity();
      for (s.forms.items, 0..) |pf, i| {
        if (m.len(c - pf.centre) - pf.reach < half + 2 * h) {
          try cand.append(gpa, @intCast(i));
        }
      }
      // with nothing to add, carving and inking alone make no surface
      var solid = false;
      for (cand.items) |i| solid = solid or (!s.forms.items[i].f.carve and s.forms.items[i].f.ink == 0);
      if (!solid) continue;
      const d = s.dist(c, cand.items);
      if (@abs(d) > half * 1.6 + 2 * h) continue;
      var bl:Block = .{ .at = .{ bx, by, bz }, .vals = undefined, .vid = @splat(NONE), .cand = try gpa.dupe(u32, cand.items) };
      for (0..S) |z| for (0..S) |y| for (0..S) |x| {
        const p = lo + v3(m.f(bx * B + x), m.f(by * B + y), m.f(bz * B + z)) * m.splat3(h);
        bl.vals[(z * S + y) * S + x] = s.dist(p, bl.cand);
      };
      map[(bz * nb[1] + by) * nb[0] + bx] = @intCast(blocks.items.len);
      try blocks.append(gpa, bl);
    };

    // a vertex in every cell the surface crosses: the mean of where it
    // crosses the cell's edges, pulled onto the surface
    const Vert = struct { p:V3, n:V3, col:color.Rgba8, skin:vertex.Skin };
    var verts:std.ArrayList(Vert) = .empty;
    defer verts.deinit(gpa);
    const corner = [8][3]usize{ .{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 1, 1, 0 }, .{ 0, 0, 1 }, .{ 1, 0, 1 }, .{ 0, 1, 1 }, .{ 1, 1, 1 } };
    const edges = [12][2]u8{ .{ 0, 1 }, .{ 2, 3 }, .{ 4, 5 }, .{ 6, 7 }, .{ 0, 2 }, .{ 1, 3 }, .{ 4, 6 }, .{ 5, 7 }, .{ 0, 4 }, .{ 1, 5 }, .{ 2, 6 }, .{ 3, 7 } };
    for (blocks.items) |*bl| {
      for (0..B) |z| for (0..B) |y| for (0..B) |x| {
        var vals:[8]f32 = undefined;
        var inside:u8 = 0;
        for (corner, 0..) |cc, k| {
          vals[k] = bl.vals[((z + cc[2]) * S + y + cc[1]) * S + x + cc[0]];
          if (vals[k] < 0) inside += 1;
        }
        if (inside == 0 or inside == 8) continue;
        var acc = v3(0, 0, 0);
        var n:f32 = 0;
        for (edges) |e| {
          const a = vals[e[0]];
          const c = vals[e[1]];
          if ((a < 0) == (c < 0)) continue;
          const f = a / (a - c);
          const pa = v3(m.f(corner[e[0]][0]), m.f(corner[e[0]][1]), m.f(corner[e[0]][2]));
          const pc = v3(m.f(corner[e[1]][0]), m.f(corner[e[1]][1]), m.f(corner[e[1]][2]));
          acc += m.lerpV(pa, pc, f);
          n += 1;
        }
        const cell = v3(m.f(bl.at[0] * B + x), m.f(bl.at[1] * B + y), m.f(bl.at[2] * B + z));
        var p = lo + (cell + acc / m.splat3(n)) * m.splat3(h);
        // onto the surface, never leaving the cell's neighbourhood
        const start = p;
        for (0..2) |_| {
          const d = s.dist(p, bl.cand);
          p -= s.grad(p, bl.cand, h * 0.25) * m.splat3(d);
        }
        if (m.len(p - start) > h) p = start;
        const nrm = s.grad(p, bl.cand, h * 0.35);
        const cv = s.colourFrom(p, bl.cand);
        bl.vid[(z * B + y) * B + x] = @intCast(verts.items.len);
        try verts.append(gpa, .{
          .p = p, .n = nrm,
          .col = .{ .r = @intFromFloat(@min(cv[0], 255)), .g = @intFromFloat(@min(cv[1], 255)), .b = @intFromFloat(@min(cv[2], 255)), .a = 255 },
          .skin = s.weighFrom(p, bl.cand),
        });
      };
    }

    const Look = struct {
      fn cellVert(bs:[]const Block, mp:[]const u32, n:[3]usize, ci:[3]isize) ?u32 {
        for (ci) |c| if (c < 0) return null;
        const u = [3]usize{ @intCast(ci[0]), @intCast(ci[1]), @intCast(ci[2]) };
        const bb = [3]usize{ u[0] / B, u[1] / B, u[2] / B };
        if (bb[0] >= n[0] or bb[1] >= n[1] or bb[2] >= n[2]) return null;
        const bi = mp[(bb[2] * n[1] + bb[1]) * n[0] + bb[0]];
        if (bi == NONE) return null;
        const v = bs[bi].vid[((u[2] % B) * B + u[1] % B) * B + u[0] % B];
        return if (v == NONE) null else v;
      }
    };


    // a quad across every edge the surface crosses, joining the four cells
    // around it, facing the way the field rises
    const start = b.mark();
    var skins:std.ArrayList(vertex.Skin) = .empty;
    defer skins.deinit(gpa);
    const steps = [3][3]usize{ .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, 0, 1 } };
    const around = [4][2]isize{ .{ -1, -1 }, .{ 0, -1 }, .{ 0, 0 }, .{ -1, 0 } };
    for (blocks.items) |*bl| {
      for (0..B) |z| for (0..B) |y| for (0..B) |x| {
        const v0 = bl.vals[(z * S + y) * S + x];
        for (steps, 0..) |st, axis| {
          const v1 = bl.vals[((z + st[2]) * S + y + st[1]) * S + x + st[0]];
          if ((v0 < 0) == (v1 < 0)) continue;
          const g = [3]isize{ @intCast(bl.at[0] * B + x), @intCast(bl.at[1] * B + y), @intCast(bl.at[2] * B + z) };
          // the two axes across the edge
          const u_ax = (axis + 1) % 3;
          const w_ax = (axis + 2) % 3;
          var q:[4]u32 = undefined;
          var ok = true;
          for (around, 0..) |o, k| {
            var ci = g;
            ci[u_ax] += o[0];
            ci[w_ax] += o[1];
            if (Look.cellVert(blocks.items, map, nb, ci)) |vi| q[k] = vi else ok = false;
          }
          if (!ok) continue;
          const sgn:f32 = if (v0 < 0) 1 else -1;
          const dir = switch (axis) { 0 => v3(sgn, 0, 0), 1 => v3(0, sgn, 0), else => v3(0, 0, sgn) };
          var P:[4]V3 = undefined;
          for (&P, q) |*pp, vi| pp.* = verts.items[vi].p;
          // split along the shorter diagonal
          const tris:[2][3]usize = if (m.len(P[0] - P[2]) <= m.len(P[1] - P[3])) .{ .{ 0, 1, 2 }, .{ 0, 2, 3 } } else .{ .{ 0, 1, 3 }, .{ 1, 2, 3 } };
          for (tris) |tri| {
            const fnrm = m.cross(P[tri[1]] - P[tri[0]], P[tri[2]] - P[tri[0]]);
            const order = if (m.dot(fnrm, dir) >= 0) [3]usize{ tri[0], tri[1], tri[2] } else [3]usize{ tri[0], tri[2], tri[1] };
            for (order) |k| {
              const vv = verts.items[q[k]];
              try b.put(vv.p, vv.n, vv.col, t, 0, part);
              try skins.append(gpa, vv.skin);
            }
          }
        }
      };
    }
    @memcpy(try b.skinOf(start), skins.items);
  }
};
