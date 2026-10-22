//! mesh: WOLF LIMB. unit limb along +Y; instances scale (thickness, length, thickness)
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");

const core = pal.core;
const vine = pal.vine;

fn limbProfile(k:f32) f32 { return 0.5 * (1 - 0.3 * k); }

pub fn build(b:*mg.Builder) !void {
  try mg.bundle(b, limbProfile, 4, 2.0, core, vine);
}
