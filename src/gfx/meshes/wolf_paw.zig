//! mesh: WOLF PAW
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");

const v3 = m.v3;
const core = pal.core;

pub fn build(b:*mg.Builder) !void {
  try mg.ellipsoid(b, .{.center = v3(0, 0.02, 0.02), .radii = v3(0.045, 0.028, 0.06), .col = core, .rings = 5, .segs = 8});
  for ([_]f32{-0.025, 0, 0.025}) |x| try b.cone(v3(x, 0.015, 0.07), m.norm(v3(x, -0.3, 1)), 0.035, 0.008, color.rgb(.{0.85, 0.8, 0.6}, 255), 0, .thorn);
}
