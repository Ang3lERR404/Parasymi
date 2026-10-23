//! mesh: MOTE. a fallen fragment of starlight: a small faceted bipyramid
//! of light at the heart, a thin ring of light circling it at a tilt, and
//! four long, needle-thin rays crossing through it like the glint of a star.
//! All of it glows (the instance's glow); the view turns it slowly and lets
//! it twinkle.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const color = @import("../../core/color.zig");
const kit = @import("mineral_kit.zig");

const V3 = m.V3;
const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const core = color.rgb(1, 0.96, 0.82).toRgba8(255);
  const pale = color.rgb(0.85, 0.9, 1.0).toRgba8(255);
  // the heart: a faceted bipyramid, taller than wide
  const S = 6;
  const top = v3(0, 0.075, 0);
  const bottom = v3(0, -0.075, 0);
  for (0..S) |i| {
    const a0 = m.tau * m.ratio(i, S);
    const a1 = m.tau * m.ratio(i + 1, S);
    const p0 = v3(@cos(a0) * 0.034, 0, @sin(a0) * 0.034);
    const p1 = v3(@cos(a1) * 0.034, 0, @sin(a1) * 0.034);
    try kit.facet(b, .{p0, p1, top}, v3(0, 0, 0), .{core, core, pale}, 1, .bloom);
    try kit.facet(b, .{p1, p0, bottom}, v3(0, 0, 0), .{core, core, pale}, 1, .bloom);
  }
  // the ring, tilted across the heart
  var ring:[25]V3 = undefined;
  var ts:[25]f32 = undefined;
  for (&ring, &ts, 0..) |*p, *t, j| {
    const a = m.ratio(j, 24) * m.tau;
    const q = v3(@cos(a) * 0.1, 0, @sin(a) * 0.1);
    p.* = v3(q[0], q[1] * @cos(0.5) - q[2] * @sin(0.5), q[1] * @sin(0.5) + q[2] * @cos(0.5));
    t.* = 1;
  }
  try b.tube(&ring, &ts, 0.0035, 0.0035, pale, .bloom, 4);
  // rays: needle-thin diamonds through the heart, two long, two short
  const rays = [_]struct { d:V3, len:f32 }{
    .{.d = v3(1, 0, 0), .len = 0.24}, .{.d = v3(0, 1, 0), .len = 0.3},
    .{.d = m.norm(v3(1, 0, 1)), .len = 0.14}, .{.d = m.norm(v3(-1, 0, 1)), .len = 0.14},
  };
  for (rays) |r| {
    const w = m.norm(m.cross(r.d, if (@abs(r.d[1]) > 0.9) v3(0, 0, 1) else v3(0, 1, 0))) * m.splat3(0.006);
    const w2 = m.norm(m.cross(r.d, w)) * m.splat3(0.006);
    for ([_]V3{w, w2}) |side| {
      const a = r.d * m.splat3(r.len);
      try kit.facet(b, .{a, side, -side}, side * m.splat3(0.0) + m.cross(side, r.d), .{pale, core, core}, 1, .bloom);
      try kit.facet(b, .{-a, -side, side}, m.cross(side, r.d), .{pale, core, core}, 1, .bloom);
    }
  }
}
