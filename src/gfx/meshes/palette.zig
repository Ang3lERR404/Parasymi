//! shared look for library meshes: the vine-wolf palette (woody cores, living
//! vines, leaves, amber sap) and a per-mesh deterministic random stream.
const std = @import("std");
const Wyhash = std.hash.Wyhash;
const Rng = @import("../../core/rng.zig").Rng;
const color = @import("../../core/color.zig");

pub const core = color.rgb(.{0.20, 0.26, 0.13}, 255);
pub const vine = color.rgb(.{0.36, 0.58, 0.24}, 255);
pub const leaf_dark = color.rgb(.{0.16, 0.42, 0.20}, 255);
pub const leaf_lite = color.rgb(.{0.40, 0.80, 0.38}, 255);
pub const sap = color.rgb(.{1.0, 0.68, 0.22}, 255);

/// the vine-wolf keeps to muted, low-saturation greens and browns so its only
/// accents are amber sap: the belly, the eyes and the inner ears.
pub const wolf_core = color.rgb(.{0.23, 0.20, 0.14}, 255);
pub const wolf_vine = color.rgb(.{0.34, 0.38, 0.26}, 255);
pub const wolf_leaf_dark = color.rgb(.{0.22, 0.29, 0.19}, 255);
pub const wolf_leaf_lite = color.rgb(.{0.37, 0.42, 0.29}, 255);
/// the wolf's body strands are woven by something alive, not a lathe
pub const STRAND_WOBBLE:f32 = 0.03;
pub const wolf_claw = color.rgb(.{0.58, 0.54, 0.44}, 255);

/// the same mesh always grows the same way.
pub fn rngFor(comptime name:[]const u8) Rng {
  return Rng.init(comptime Wyhash.hash(0x9A27, name));
}
