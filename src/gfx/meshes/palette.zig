//! shared look for library meshes: the vine-wolf palette (woody cores, living
//! vines, leaves, amber sap) and a per-mesh deterministic random stream.
const lib=@import("../../lib.zig");
const std=lib.std;
const Wyhash=std.hash.Wyhash;
const engine=lib.engine;
const Rng=engine.core.rng.Rng;
const color=engine.core.color;
pub const core=color.rgb(0.20,0.26,0.13).toRgba8(255);
pub const vine=color.rgb(0.36,0.58,0.24).toRgba8(255);
pub const leafDark=color.rgb(0.16,0.42,0.20).toRgba8(255);
pub const leafLite=color.rgb(0.40,0.80,0.38).toRgba8(255);
pub const sap=color.rgb(1.0,0.68,0.22).toRgba8(255);
/// living roots: the wolf's root brown, paler where the bark is young
pub const rootBark=color.rgb(0.19,0.15,0.09).toRgba8(255);
pub const rootLite=color.rgb(0.31,0.26,0.16).toRgba8(255);
/// a conduit's living core showing through its weave: paler, warmer wood
pub const sapwood=color.rgb(0.52,0.38,0.21).toRgba8(255);
pub const sapwoodDark=color.rgb(0.36,0.25,0.13).toRgba8(255);
/// soil a root has heaped breaking the ground, and its clods
pub const soil=color.rgb(0.40,0.29,0.18).toRgba8(255);
pub const soilDark=color.rgb(0.31,0.22,0.14).toRgba8(255);
/// the vine-wolf keeps to muted, low-saturation greens and browns so its only
/// accents are amber sap: the belly, the eyes and the inner ears.
pub const wolfCore=color.rgb(0.23,0.20,0.14).toRgba8(255);
pub const wolfVine=color.rgb(0.34,0.38,0.26).toRgba8(255);
pub const wolfLeafDark=color.rgb(0.22,0.29,0.19).toRgba8(255);
pub const wolfLeafLite=color.rgb(0.37,0.42,0.29).toRgba8(255);
/// the wolf's body strands are woven by something alive, not a lathe
pub const strandWobble:f32=0.03;
pub const wolfClaw=color.rgb(0.58,0.54,0.44).toRgba8(255);
/// the same mesh always grows the same way.
pub fn rngFor(comptime name:[]const u8)Rng{
  return Rng.init(comptime Wyhash.hash(0x9A27,name));
}
