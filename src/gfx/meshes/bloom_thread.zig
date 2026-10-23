//! mesh: BLOOM THREAD. a thread of light between two celestial blooms:
//! a thin tube built straight up +Y over 0..1 (x and z in metres), bent on
//! the GPU along the curve from one bloom's core to the other's (part.vert
//! curve mode), with small beads of light strung along it. Part `.thread`:
//! part.frag gives it a warm iridescent film with light running along it.
//! Listed last: it is translucent and blends over everything.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const color = @import("../../core/color.zig");

const V3 = m.V3;
const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const warm = color.rgb(1.0, 0.86, 0.62).toRgba8(255);
  const N = 32;
  var spine:[N]V3 = undefined;
  var ts:[N]f32 = undefined;
  var rs:[N]f32 = undefined;
  for (&spine, &ts, &rs, 0..) |*p, *t, *r, i| {
    t.* = m.ratio(i, N - 1);
    p.* = v3(0, t.*, 0);
    // a little fuller in the middle, fine where it meets each bloom
    r.* = 0.007 + 0.006 * @sin(m.pi * t.*);
  }
  try b.tubeR(&spine, &ts, &rs, warm, .thread, 5);
  for ([_]f32{0.25, 0.5, 0.75}) |k| {
    const s = b.mark();
    try mg.ellipsoid(b, .{.center = v3(0, k, 0), .radii = v3(0.018, 0.018, 0.018), .col = warm, .part = .thread, .rings = 4, .segs = 6, .t = k});
    // beads keep the length fraction of where they sit (curve mode reads y
    // as a fraction of a thread some 8 m long)
    for (b.v.items[s..]) |*vx| vx.pos[1] = k + (vx.pos[1] - k) / 8;
  }
}
