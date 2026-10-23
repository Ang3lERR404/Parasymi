//! mesh: WOLF LIMB. unit limb along +Y (the metatarsal); instances scale
//! (thickness, length, thickness). A squared core tapering toward the
//! foot, with vine tendons down its front and back.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const kit = @import("wolf_kit.zig");

const v3 = m.v3;

fn radius(k:f32) f32 { return 0.5 * (1 - 0.3 * k); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try kit.limbCore(b, 1, radius, pal.wolf_core);
  for ([_]f32{-1, 1}) |face| {
    try kit.tendon(b, v3(0, 0.05, face * radius(0.05) * 0.9), v3(0, 0.97, face * radius(0.97) * 0.9), v3(0, 0, face * 0.06), 0.11, pal.wolf_vine);
  }
}
