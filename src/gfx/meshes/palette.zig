//! shared look for library meshes: the vine-wolf palette (woody cores, living
//! vines, leaves, amber sap) and a per-mesh deterministic random stream.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the hash a mesh's name is turned into its seed with
const Wyhash=std.hash.Wyhash;
/// the generic engine package
const engine=lib.engine;
/// the engine's deterministic random stream
const Rng=engine.core.rng.Rng;
/// colour conversions: every swatch here is built from linear rgb
const color=engine.core.color;
/// old wood at the heart of things: a dark mossy brown-green
pub const core=color.rgb(0.20,0.26,0.13).toRgba8(255);
/// a living vine: a fresh mid green
pub const vine=color.rgb(0.36,0.58,0.24).toRgba8(255);
/// a leaf in shade, or its underside: deep green
pub const leafDark=color.rgb(0.16,0.42,0.20).toRgba8(255);
/// a leaf in sun, or its tip: bright pale green
pub const leafLite=color.rgb(0.40,0.80,0.38).toRgba8(255);
/// amber sap, the one warm accent: bellies, eyes, glowing pads
pub const sap=color.rgb(1.0,0.68,0.22).toRgba8(255);
/// living roots: the wolf's root brown, its older bark
pub const rootBark=color.rgb(0.19,0.15,0.09).toRgba8(255);
/// living roots where the bark is young: a paler brown
pub const rootLite=color.rgb(0.31,0.26,0.16).toRgba8(255);
/// a conduit's living core showing through its weave: paler, warmer wood
pub const sapwood=color.rgb(0.52,0.38,0.21).toRgba8(255);
/// that sapwood in shadow, or older: a darker warm brown
pub const sapwoodDark=color.rgb(0.36,0.25,0.13).toRgba8(255);
/// soil a root has heaped breaking the ground
pub const soil=color.rgb(0.40,0.29,0.18).toRgba8(255);
/// the darker clods of that heaped soil
pub const soilDark=color.rgb(0.31,0.22,0.14).toRgba8(255);
/// the vine-wolf keeps to muted, low-saturation greens and browns so its only
/// accents are amber sap: the belly, the eyes and the inner ears. Its woody core:
pub const wolfCore=color.rgb(0.23,0.20,0.14).toRgba8(255);
/// the wolf's vines: a dusty grey-green
pub const wolfVine=color.rgb(0.34,0.38,0.26).toRgba8(255);
/// the wolf's leaves in shade: muted dark green
pub const wolfLeafDark=color.rgb(0.22,0.29,0.19).toRgba8(255);
/// the wolf's leaves in light: muted pale green
pub const wolfLeafLite=color.rgb(0.37,0.42,0.29).toRgba8(255);
/// the wolf's body strands are woven by something alive, not a lathe: how
/// far each strand wanders off its true line, as a share of its radius
pub const strandWobble:f32=0.03;
/// the wolf's claws: old bone, a pale warm grey
pub const wolfClaw=color.rgb(0.58,0.54,0.44).toRgba8(255);
/// the same mesh always grows the same way: a random stream seeded from the
/// mesh's `name` at compile time, so each build of it is identical.
pub fn rngFor(comptime name:[]const u8)Rng{
  return Rng.init(comptime Wyhash.hash(0x9A27,name));
}
