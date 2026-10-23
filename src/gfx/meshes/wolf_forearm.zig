//! mesh: WOLF FOREARM. elbow at origin, wrist at +Y LEN (mesh -Z faces the
//! arm's front). Tapers from 1.1x the arm radius to 0.7x, with the
//! brachioradialis swelling forward at 40%: one control point pushed
//! forward, smoothed in by the spline.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const upper = @import("wolf_upper_arm.zig");

const V3 = m.V3;
const v3 = m.v3;

pub const LEN:f32 = 0.24;
const SWELL_AT:f32 = 0.4;
/// overall forearm scale relative to the upper arm (thinner)
const FOREARM_SCALE:f32 = 0.8;

fn radius(k:f32) f32 {
  const bump = @exp(-((k - SWELL_AT) * (k - SWELL_AT)) / 0.03);
  return upper.ARM_R * FOREARM_SCALE * m.lerp(1.1, 0.7, k) * (1 + 0.12 * bump);
}

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const ks = [_]f32{0, 0.2, SWELL_AT, 0.7, 1};
  var ctrl:[ks.len]V3 = undefined;
  for (&ctrl, ks) |*c, k| c.* = v3(0, k * LEN, if (k == SWELL_AT) -0.12 * radius(k) else 0);
  const N = 14;
  var spine:[N]V3 = undefined;
  m.splineResample(&ctrl, &spine);
  var ts:[N]f32 = undefined;
  var radii:[N]f32 = undefined;
  for (&ts, &radii, 0..) |*t, *r, i| {
    t.* = m.ratio(i, N - 1);
    r.* = radius(t.*);
  }
  try b.tubeR(&spine, &ts, &radii, pal.wolf_vine, .stem, 8);
}
