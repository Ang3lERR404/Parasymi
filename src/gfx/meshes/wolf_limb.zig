//! mesh: WOLF LIMB. unit limb along +Y; instances scale (thickness, length, thickness)
const std = @import("std");
const Allocator = std.mem.Allocator;
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

const core = pal.wolf_core;
const vine = pal.wolf_vine;

fn limbProfile(k:f32) f32 { return 0.5 * (1 - 0.3 * k); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try mg.bundle(b, limbProfile, 4, 2.0, core, vine);
}
