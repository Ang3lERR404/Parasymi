//! mesh: CONDUIT. structures: built around the footprint centre, +X is "forward" for conduits
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");

const v3 = m.v3;
const core = pal.core;
const leaf_dark = pal.leaf_dark;
const leaf_lite = pal.leaf_lite;
const sap = pal.sap;

fn evenProfile(_:f32) f32 { return 0.5; }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const s = b.mark();
  try mg.bundle(b, evenProfile, 3, 3.0, 0, 0, core, color.rgb(.{0.5, 0.38, 0.22}, 255));
  b.xform(s, m.chain(.{m.translate(v3(-0.5, 0.1, 0)), m.rotZ(-m.pi / 2.0), m.scale3(v3(0.2, 1, 0.2))}));
  // sap beads that light up as items pass, and a leaf pointing the way
  for ([_]f32{-0.3, 0, 0.3}) |x| try mg.ellipsoid(b, .{.center = v3(x, 0.17, 0), .radii = v3(0.045, 0.04, 0.045), .col = sap, .part = .bloom, .rings = 4, .segs = 6, .t = x + 0.5});
  try b.blade(v3(0.25, 0.14, 0), v3(1, 0, 0), 0.3, 0.1, -0.2, leaf_dark, leaf_lite, 1, .leaf);
  for ([_]f32{-0.35, 0.35}) |x| for ([_]f32{-1, 1}) |z| try b.cone(v3(x, 0.08, z * 0.05), m.norm(v3(0, -1, z * 0.6)), 0.12, 0.025, core, 0, .tendril);
}
