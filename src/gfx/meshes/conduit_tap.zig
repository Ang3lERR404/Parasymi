//! mesh: CONDUIT TAP. a side root a conduit sends out along +X from its
//! middle to the plant on the next tile: it creeps over the ground, sinks
//! into the soil at the plant's foot and splits into rootlets around it.
//! Instances stretch it along X as it grows out.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("structure_kit.zig");
const conduit = @import("conduit.zig");

const V3 = m.V3;
const v3 = m.v3;

pub fn build(b:*mg.Builder) Allocator.Error!void {
  // from inside the conduit's own root, so it grows out of it
  const from = v3(0, conduit.rise(0.5), 0);
  var c:[7]V3 = undefined;
  mg.growthPath(.{.start = from, .direction = m.norm(v3(1, -0.12, 0)), .length = 0.68, .wobble = 0.5, .curl = 0.05, .seed = 0x7A9}, &c);
  var p:[16]V3 = undefined;
  m.splineResample(&c, &p);
  // it creeps low over the ground, arching a little, and sinks at the end
  for (&p, 0..) |*q, j| {
    const k = m.ratio(j, 15);
    q[1] = m.lerp(from[1], -0.02, k * k) + 0.035 * @sin(m.pi * k);
  }
  var ts:[16]f32 = undefined;
  var rs:[16]f32 = undefined;
  mg.taperRadii(conduit.END_R * 0.9, 0.45, &rs);
  for (&ts, 0..) |*t, j| t.* = m.ratio(j, 15) * 0.5;
  try b.tubeR(&p, &ts, &rs, pal.root_bark, .stem, 6);
  // at the plant's foot it splits and sinks in around it
  const end = p[15];
  for ([_]f32{-0.9, -0.1, 0.8}, 0..) |a, i| {
    try kit.rootlet(b, end, m.norm(v3(@cos(a) * 0.8, -0.45, @sin(a) * 0.8)), 0.3, rs[15], 0x7AA +% i * 29);
  }
}
