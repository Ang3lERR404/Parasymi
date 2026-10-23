//! mesh: RESEARCH BLOOM. a woven stalk rising from a root mat, leaves along
//! it, opening at the top into a broad flower that cradles the orb hovering
//! above it (`orb`).
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");
const kit = @import("structure_kit.zig");

const V3 = m.V3;
const v3 = m.v3;
const HEIGHT:f32 = 1.5;
const petal_heart = color.rgb(0.30, 0.22, 0.46);
const petal_rim = color.rgb(0.62, 0.5, 0.86);

/// the stalk's radius up its height: a flared foot, a waist, a swelling
/// under the flower.
fn stalkProfile(k:f32) f32 { return 0.14 * (1 - 0.45 * k) + 0.05 * @exp(-k * 12) + 0.03 * @exp(-(1 - k) * 10); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try kit.rootMat(b, 6, 0.9, 0.07, 0x7B01);
  try kit.footLeaves(b, 6, 0.25, 0.5, 0.18, 0x7B02);
  const s = b.mark();
  try mg.bundle(b, stalkProfile, 6, 3.2, pal.STRAND_WOBBLE, 0x7B03, pal.core, color.rgb(0.36, 0.3, 0.46).toRgba8(255));
  b.xform(s, m.scale3(v3(1.6, HEIGHT, 1.6)));
  // leaves along the stalk, as along any vine
  var spine:[10]V3 = undefined;
  for (&spine, 0..) |*p, i| p.* = v3(0, HEIGHT * m.ratio(i, 9), 0);
  try mg.leavesAlong(b, &spine, 5, 0.4, 0.12, 0.25, 0.8, 0.25, 0.8, pal.leaf_dark, pal.leaf_lite, 0x7B04);
  // the flower: a broad outer whorl opening wide, an inner one cupping the orb
  const heart = v3(0, HEIGHT - 0.02, 0);
  for (0..9 + 5) |i| {
    const outer = i < 9;
    const a = if (outer) m.ratio(i, 9) * m.tau else (m.f(i - 9) + 0.5) / 5 * m.tau;
    try mg.petal(b, .{
      .base = heart, .out = v3(@cos(a), 0, @sin(a)),
      .len = if (outer) 0.62 else 0.42, .width = if (outer) 0.3 else 0.22,
      .rise = if (outer) 0.55 else 1.15, .flare = if (outer) 0.7 else 0.4, .cup = 0.4,
      .col = petal_heart.toRgba8(255), .tip = petal_rim.toRgba8(255), .part = .leaf,
    });
  }
}

/// mesh: RESEARCH ORB. a sphere of resin sap held in two grown vine bands,
/// hovering above the bloom; spun and bobbed per instance.
pub const orb = struct {
  const R:f32 = 0.22;

  pub fn build(b:*mg.Builder) Allocator.Error!void {
    try kit.resinPod(b, v3(0, 0, 0), v3(R, R, R), 10, 14);
    // two bands wrapping it, pole to pole, crossing
    const arcs = [_][4]f32{ .{0.15, 0.3, 2.99, 2.4}, .{0.2, 3.5, 2.9, 5.6} };
    try mg.bands(b, v3(0, 0, 0), v3(R, R, R), &arcs, 1, 0.018, 0.12, 0x0B5, pal.vine);
  }
};
