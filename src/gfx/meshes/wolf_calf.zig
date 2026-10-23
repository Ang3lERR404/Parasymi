//! mesh: WOLF CALF. knee at origin, hock (the backward-bending joint) at +Y
//! LEN: tendon and sinew. One smooth vine tapering from 1x the leg radius
//! to 0.7x, with a prominent gastrocnemius swell (+25% at 30%) on its back
//! (+Z here, which faces backward once the rig turns the segment downward)
//! and a single wrap.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const thigh = @import("wolf_thigh.zig");

const V3 = m.V3;
const v3 = m.v3;

pub const LEN:f32 = 0.26;
/// where the calf swells, and by how much
const BULGE_AT:f32 = 0.3;
const BULGE:f32 = 0.25;

const N = 16;

fn radius(k:f32) f32 {
  const bump = @exp(-((k - BULGE_AT) * (k - BULGE_AT)) / 0.03);
  return thigh.LEG_R * m.lerp(1, 0.7, k) * (1 + BULGE * bump);
}

pub fn build(b:*mg.Builder) Allocator.Error!void {
  // the swell is one control point pushed back; the spline smooths it in
  const ks = [_]f32{0, 0.2, BULGE_AT, 0.7, 1};
  var ctrl:[ks.len]V3 = undefined;
  for (&ctrl, ks) |*c, k| c.* = v3(0, k * LEN, if (k == BULGE_AT) BULGE * radius(k) else 0);
  var spine:[N]V3 = undefined;
  m.splineResample(&ctrl, &spine);
  var ts:[N]f32 = undefined;
  var radii:[N]f32 = undefined;
  for (&ts, &radii, 0..) |*t, *r, i| {
    t.* = m.ratio(i, N - 1);
    r.* = radius(t.*);
  }
  try b.tubeR(&spine, &ts, &radii, pal.wolf_vine, .stem, 8);
  try thigh.wraps(b, &radii, LEN, 1, 1.2, 0xCA1F);
}
