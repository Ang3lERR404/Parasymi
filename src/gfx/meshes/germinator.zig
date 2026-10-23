//! mesh: GERMINATOR. a seed nursery grown like the plants it weaves: a
//! woven root mat, broad leaves at its foot, and grown vines arching up
//! around a pod of resin sap with a seed curled inside it.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("structure_kit.zig");

const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var rng = pal.rngFor("germinator");
  try kit.rootMat(b, 7, 0.95, 0.07, 0x6E41);
  try kit.footLeaves(b, 8, 0.32, 0.62, 0.22, 0x6E42);
  // the seed, dark inside the sap
  try mg.ellipsoid(b, .{.center = v3(0, 0.46, 0), .radii = v3(0.12, 0.15, 0.11), .col = pal.wolf_core, .rings = 6, .segs = 8, .t = 0.5});
  try kit.resinPod(b, v3(0, 0.5, 0), v3(0.34, 0.4, 0.34), 10, 14);
  // the cradle: vines rising from the mat and arching in over the pod
  for (0..5) |i| {
    const a = (m.f(i) + rng.range(-0.15, 0.15)) / 5 * m.tau + 0.3;
    const from = v3(@cos(a) * 0.55, 0.04, @sin(a) * 0.55);
    const to = v3(@cos(a + 0.9) * 0.12, 1.02, @sin(a + 0.9) * 0.12);
    try kit.leafyVine(b, from, to, 0.045, 0.12, 3, 0.1, 0.9, 0x6E50 +% i * 13);
  }
}
