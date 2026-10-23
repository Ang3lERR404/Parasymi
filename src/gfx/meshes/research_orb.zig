//! mesh: RESEARCH ORB. a sphere of resin sap held in two grown vine bands,
//! hovering above the research bloom; spun and bobbed per instance.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("structure_kit.zig");

const v3 = m.v3;
const R:f32 = 0.22;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try kit.resinPod(b, v3(0, 0, 0), v3(R, R, R), 10, 14);
  // two bands wrapping it, pole to pole, crossing
  const arcs = [_][4]f32{ .{0.15, 0.3, 2.99, 2.4}, .{0.2, 3.5, 2.9, 5.6} };
  try mg.bands(b, v3(0, 0, 0), v3(R, R, R), &arcs, 1, 0.018, 0.12, 0x0B5, pal.vine);
}
