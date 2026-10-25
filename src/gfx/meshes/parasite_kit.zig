//! shared pieces for the parasitic lineage's structures, in the language of
//! its plants (meshgen `coil`): alien, not hostile. A pale pearl skin over
//! a stalk of three strands wound tight, swelling into a bulbous foot half
//! sunk in the soil; translucent bladders of thin-film sap clinging to it;
//! lilac fronds that rise, arc out and curl in at their tips; pale roots
//! reaching into the ground. Every piece grows on a structure's growth
//! splines (gfx/growth.zig). Not a mesh itself; the structure meshes use it.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const color = @import("../../core/color.zig");
const growth = @import("../growth.zig");
const Rng = @import("../../core/rng.zig").Rng;

const V3 = m.V3;
const v3 = m.v3;

/// the lineage's colours: its skin, the core showing between its strands,
/// pearl where it is youngest, its fronds, its sap
pub const skin = color.rgb(0.56, 0.54, 0.62).toRgba8(255);
pub const core = color.rgb(0.39, 0.37, 0.45).toRgba8(255);
pub const pearl = color.rgb(0.78, 0.74, 0.84).toRgba8(255);
pub const lilac = color.rgb(0.68, 0.62, 0.82).toRgba8(255);
pub const sac = color.rgb(0.46, 0.62, 0.86).toRgba8(255);
/// its strands are wound by something alive, but tighter than a symbiote's
pub const WOBBLE:f32 = 0.05;
pub const TWIST:f32 = 4.5;

/// a frond's control points from `from` out along `out` (horizontal, unit):
/// its heading starts at `rise` and turns ever faster (by `curl` at its tip;
/// negative curls it back in over), so it rises, arcs and curls like an
/// unfurling fern, never quite smooth
pub fn frondPath(from:V3, out:V3, len:f32, rise:f32, curl:f32, seed:u64, pts:[]V3) void {
  const n = pts.len;
  pts[0] = from;
  for (1..n) |j| {
    const s = m.ratio(j, n - 1);
    const heading = rise - s * s * curl;
    const step = len / m.f(n - 1) * (1 - 0.55 * s);
    pts[j] = pts[j - 1] + (out * m.splat3(@cos(heading)) + v3(0, @sin(heading), 0)) * m.splat3(step);
  }
  mg.grow(pts, .{.start = from, .direction = m.norm(pts[n - 1] - from), .length = len, .wobble = 0.08, .seed = seed});
}

pub const Frond = struct {
  out:V3,
  len:f32,
  r:f32,
  rise:f32 = 1.25,
  curl:f32 = 5.2,
  t0:f32 = 0.6,
  seed:u64,
  grow:growth.Branch = .{},
};

/// a frond off spline `parent` at `u`, grown along its own spline, tapering
/// to a point; returns its spline
pub fn frond(b:*mg.Builder, k:*growth.Skeleton, parent:growth.Id, u:f32, f:Frond) Allocator.Error!growth.Id {
  var c:[10]V3 = undefined;
  frondPath(k.point(parent, u), f.out, f.len, f.rise, f.curl, f.seed, &c);
  const id = k.branch(parent, u, &c, f.grow);
  try k.tube(b, id, .{.r0 = f.r, .tip = 0.12, .col = lilac, .part = .tendril, .sides = 5, .t0 = f.t0, .t1 = 1});
  return id;
}

/// the stalk along spline `id`: three strands wound tight round a darker
/// core, swelling hard into its foot, `girth` at its middle
pub fn stalk(b:*mg.Builder, k:*growth.Skeleton, id:growth.Id, girth:f32, seed:u64) Allocator.Error!void {
  var sp:[growth.RES]V3 = undefined;
  var ts:[growth.RES]f32 = undefined;
  var rs:[growth.RES]f32 = undefined;
  k.path(id, 0, 1, &sp);
  for (&ts, &rs, 0..) |*t, *r, i| {
    const u = m.ratio(i, growth.RES - 1);
    t.* = u * 0.85;
    const low = 1 - u;
    r.* = girth * m.lerp(1.15, 0.75, u) * (1 + 0.9 * low * low * low * low * low);
  }
  const s = b.mark();
  try mg.braid(b, &sp, &ts, &rs, 3, TWIST, WOBBLE, seed, core, skin);
  try k.along(b, s, id);
}

/// the bulbous foot at `at`, half sunk in the soil, swelling out of the
/// stalk's root as it starts
pub fn foot(b:*mg.Builder, k:*growth.Skeleton, id:growth.Id, at:V3, radii:V3) Allocator.Error!void {
  const s = b.mark();
  try mg.ellipsoid(b, .{.center = at, .radii = radii, .col = skin, .rings = 7, .segs = 12, .t = 0});
  try k.on(b, s, id, 0, .{.from = at, .span = k.get(id).time * 0.3});
}

/// `n` pale roots out of the foot, reaching `reach` and sinking into the
/// ground, each a branch growing with the stalk
pub fn roots(b:*mg.Builder, k:*growth.Skeleton, id:growth.Id, n:u32, reach:f32, r:f32, seed:u64) Allocator.Error!void {
  var rng = Rng.init(seed);
  for (0..n) |i| {
    const a = (m.f(i) + rng.range(-0.25, 0.25)) / m.f(n) * m.tau;
    const out = v3(@cos(a), 0, @sin(a));
    const from = out * m.splat3(0.05) + v3(0, 0.03, 0);
    var c:[6]V3 = undefined;
    for (&c, 0..) |*p, j| {
      const f = m.ratio(j, 5);
      // out low over the ground, then down into it
      p.* = from + out * m.splat3(reach * rng.range(0.8, 1.05) * f) + v3(0, 0.03 * @sin(m.pi * f * 0.8) - 0.09 * f * f, 0);
    }
    mg.grow(&c, .{.start = from, .direction = out, .length = reach, .wobble = 0.3, .seed = seed +% i * 17});
    const root = k.branch(id, 0, &c, .{.after = .with});
    try k.tube(b, root, .{.r0 = r, .tip = 0.1, .col = pearl, .part = .tendril, .sides = 5, .t0 = 0, .t1 = 0.1});
  }
}

/// a translucent bladder of thin-film sap (part `.bloom`: the instance's
/// `fade` makes it see-through) at `center`, swelling out of spline `id`
/// at `u` once its front reaches it
pub fn bladder(b:*mg.Builder, k:*growth.Skeleton, id:growth.Id, u:f32, center:V3, radii:V3, t:f32, o:growth.Skeleton.On) Allocator.Error!void {
  const s = b.mark();
  try mg.ellipsoid(b, .{.center = center, .radii = radii, .col = sac, .part = .bloom, .rings = 8, .segs = 12, .t = t});
  var on = o;
  if (on.from == null) on.from = k.point(id, u);
  try k.on(b, s, id, u, on);
}

/// small bladders clinging up spline `id` between `from` and `to` along
/// it, smaller higher up, set round it by the golden angle
pub fn clinging(b:*mg.Builder, k:*growth.Skeleton, id:growth.Id, n:u32, from:f32, to:f32, r:f32, girth:f32) Allocator.Error!void {
  for (0..n) |i| {
    const u = m.lerp(from, to, m.ratio(i, @max(n, 2) - 1));
    const ang = m.f(i) * 2.39996 + 0.7;
    const out = v3(@cos(ang), 0, @sin(ang));
    const rr = r * m.lerp(1, 0.65, m.ratio(i, @max(n, 2) - 1));
    const at = k.point(id, u) + out * m.splat3(girth + rr * 0.5);
    try bladder(b, k, id, u, at, v3(rr, rr * 1.3, rr), u, .{});
  }
}
