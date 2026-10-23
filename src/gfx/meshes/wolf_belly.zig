//! mesh: WOLF BELLY, in torso units around the gut's centre (+Z forward).
//! A sac of sap shaped like the pectorals' lobes are: not a ball but a
//! teardrop. A full, rounded gut below, its upper side drawing in along a
//! smooth concave flank into a narrow tongue that runs up the chest to
//! finish between the pectorals, at their middle. A net of grown vines
//! wraps it (tapering at both ends, leaves along them) and a belly button
//! sits sunk in the sap at the front of the gut.
//!
//! tu.x on every vertex is how much of the gut it is (1 in the gut, 0 up
//! the tongue): the part shader inflates the sac by it as the belly fills,
//! so the gut swells and drops while the tongue stays on the chest. The
//! belly button's vertices carry tu.y = NAVEL: the shader raises it from
//! inside the sap to the surface, and on out, the fuller the belly.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("wolf_kit.zig");
const color = @import("../../core/color.zig");

const V3 = m.V3;
const v3 = m.v3;

/// the gut's radii when empty (x, y, z)
pub const GUT = v3(0.13, 0.12, 0.12);
/// where the tongue finishes, between the pectorals (relative to the gut's
/// centre when empty)
const TIP_Y:f32 = 0.2;
const TIP_Z:f32 = 0.07;
/// tu.y marking the belly button for the shader
pub const NAVEL:f32 = 2;

const N = 28;
const SIDES = 20;

/// the sac's centreline and half-width/depth at s (0 bottom .. 1 tip)
const Section = struct { at:V3, w:f32, d:f32, gut:f32 };

fn section(s:f32) Section {
  const y = m.lerp(-GUT[1], TIP_Y, s);
  // the gut: round below its centre
  const below = @sqrt(@max(0, 1 - m.pow(f32, @min(y, 0) / GUT[1], 2)));
  // above it the flank draws in, concave, into the tongue
  const up = m.clamp01(y / TIP_Y);
  const draw = 1 - 0.82 * m.smooth(m.pow(f32, up, 0.8));
  // the tongue's end rounds off
  const end = @sqrt(@max(0, 1 - m.pow(f32, m.clamp01((y - (TIP_Y - 0.03)) / 0.03), 2)));
  const r = (if (y < 0) below else draw) * end;
  return .{
    .at = v3(0, y, TIP_Z * m.smooth(up)),
    .w = GUT[0] * r,
    .d = GUT[2] * r * (if (y < 0) @as(f32, 1) else m.lerp(1, 0.35, m.smooth(up))),
    .gut = 1 - m.smooth(m.clamp01((y - 0.02) / 0.15)),
  };
}

/// a point on the sac's surface at s, around it by a (0 the right side,
/// pi/2 the front)
fn surface(s:f32, a:f32, lift:f32) V3 {
  const sc = section(s);
  return sc.at + v3(@cos(a) * sc.w * lift, 0, @sin(a) * sc.d * lift);
}

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var spine:[N]V3 = undefined;
  var ts:[N]f32 = undefined;
  var ws:[N]f32 = undefined;
  var hs:[N]f32 = undefined;
  for (0..N) |i| {
    // finer toward the ends, where the shape turns fastest
    const s = 0.5 - 0.5 * @cos(m.pi * m.ratio(i, N - 1));
    const sc = section(s);
    spine[i] = sc.at;
    ts[i] = sc.gut;
    ws[i] = @max(sc.w, 0.0015);
    hs[i] = @max(sc.d, 0.0015);
  }
  try mg.loft(b, &spine, &ts, &ws, &hs, v3(0, 0, 1), ellipse, pal.sap, .bloom, SIDES);

  // the net: grown vines from under the gut up over it, twisting, the
  // front ones running on up the tongue; tapering at both ends, leaves
  // lying along them
  for (0..6) |vi| {
    const a0 = m.ratio(vi, 6) * m.tau + 0.3;
    const front = @sin(a0) > 0.3;
    const top:f32 = if (front) 0.9 else 0.62;
    var path:[22]V3 = undefined;
    var vts:[22]f32 = undefined;
    var rs:[22]f32 = undefined;
    for (&path, &vts, &rs, 0..) |*p, *t, *r, j| {
      const k = m.ratio(j, 21);
      const s = m.lerp(0.06, top, k);
      p.* = surface(s, a0 + k * 0.9, 1.06);
      t.* = section(s).gut;
      r.* = @max(0.0075 * @sqrt(@sin(m.pi * k)), 0.0005);
    }
    try b.tubeR(&path, &vts, &rs, pal.wolf_vine, .stem, 5);
    for ([_]usize{7, 14}) |j| {
      const out = m.norm(path[j] - section(m.lerp(0.06, top, m.ratio(j, 21))).at);
      try kit.leaf(b, .{
        .base = path[j], .along = m.norm(path[j - 1] - path[j + 1]), .out = out,
        .len = 0.045, .width = 0.014, .lift = 0.35, .curl = 0.4, .cup = 0.3,
        .col = pal.wolf_leaf_dark, .tip = pal.wolf_leaf_lite, .t = vts[j],
      });
    }
  }

  // the belly button: a small knot of vine sunk in the sap at the front of
  // the gut, a puckered ring around it
  const s0 = navelS();
  const at = surface(s0, m.pi / 2.0, 0.78);
  const out = m.norm(surface(s0, m.pi / 2.0, 1) - section(s0).at);
  const start = b.mark();
  const knot = color.mix(pal.wolf_core, pal.wolf_vine, 0.3);
  try mg.ellipsoid(b, .{.center = at, .radii = v3(0.011, 0.013, 0.009), .col = knot, .rings = 6, .segs = 9, .t = 1});
  var ring:[13]V3 = undefined;
  var rts:[13]f32 = undefined;
  const side = v3(1, 0, 0);
  const up = m.norm(m.cross(out, side));
  for (&ring, &rts, 0..) |*p, *t, j| {
    const a = m.ratio(j, 12) * m.tau;
    p.* = at - out * m.splat3(0.004) + (side * m.splat3(@cos(a)) + up * m.splat3(@sin(a))) * m.splat3(0.017);
    t.* = 1;
  }
  try b.tube(&ring, &rts, 0.0045, 0.0045, knot, .stem, 5);
  for (b.v.items[start..]) |*vx| vx.tu[1] = NAVEL;
}

fn ellipse(a:f32) [2]f32 { return .{@cos(a), @sin(a)}; }

/// where the belly button sits up the sac: a little below the gut's centre
fn navelS() f32 { return (0.0 + GUT[1] - 0.012) / (GUT[1] + TIP_Y); }

test "the belly tapers from a full gut to a narrow tongue between the pectorals" {
  const gut = section(GUT[1] / (GUT[1] + TIP_Y));
  const tongue = section(0.9);
  try std.testing.expect(gut.w > 0.12);
  try std.testing.expect(tongue.w < gut.w * 0.35);
  try std.testing.expect(tongue.gut < 0.05 and gut.gut > 0.95);
}
