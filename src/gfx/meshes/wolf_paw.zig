//! mesh: WOLF PAW
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

const v3 = m.v3;
const core = pal.wolf_core;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try mg.ellipsoid(b, .{.center = v3(0, 0.02, 0.02), .radii = v3(0.045, 0.028, 0.06), .col = core, .rings = 5, .segs = 8});
  for ([_]f32{-0.025, 0, 0.025}) |x| try b.cone(v3(x, 0.015, 0.07), m.norm(v3(x, -0.3, 1)), 0.035, 0.008, pal.wolf_claw, 0, .thorn);
}
