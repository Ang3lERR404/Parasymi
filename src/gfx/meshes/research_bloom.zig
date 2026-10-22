//! mesh: RESEARCH BLOOM
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");

const v3 = m.v3;
const core = pal.core;

fn stalkProfile(k:f32) f32 { return 0.14 * (1 - 0.45 * k) + 0.05 * @exp(-k * 12); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try mg.ellipsoid(b, .{.center = v3(0, 0.05, 0), .radii = v3(0.9, 0.12, 0.9), .col = core, .rings = 5, .segs = 16});
  const s = b.mark();
  try mg.bundle(b, stalkProfile, 6, 3.2, 0, 0, core, color.rgb(.{0.42, 0.3, 0.6}, 255));
  b.xform(s, m.scale3(v3(1.6, 1.5, 1.6)));
  for (0..11) |i| {
    const a = m.f(i) * 2.39996;
    const r = 0.15 + 0.02 * m.f(i);
    try b.blade(v3(@cos(a) * r * 0.3, 1.45, @sin(a) * r * 0.3), v3(@cos(a), 0, @sin(a)), 0.55 + r, 0.22, -0.7, color.rgb(.{0.35, 0.22, 0.55}, 255), color.rgb(.{0.8, 0.6, 1.0}, 255), 1, .leaf);
  }
  for (0..4) |i| {
    const a = m.f(i) / 4 * m.tau;
    try b.cone(v3(@cos(a) * 0.6, 0.1, @sin(a) * 0.6), m.norm(v3(@cos(a) * 0.3, 1, @sin(a) * 0.3)), 0.6, 0.06, color.rgb(.{0.6, 0.5, 0.9}, 255), 0.3, .bloom);
  }
}
