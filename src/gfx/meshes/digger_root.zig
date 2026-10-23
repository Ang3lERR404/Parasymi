//! mesh: DIGGER ROOT. one thick grown root from the knot outward along +X,
//! arching down into the ground; instances fan around the knot and stretch
//! along X toward the node being worked
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try mg.vine(b, .{
    .start = v3(0.06, 0.1, 0), .direction = m.norm(v3(1, -0.32, 0)), .length = 0.46,
    .wobble = 0.1, .curl = 0, .taper = 0.4, .seed = 0xD16,
  }, 6, 16, 0.065, pal.core, .stem, 6, 0.2, 1);
}