//! the garden's meshes: every plant grown from its species genome out of the
//! engine's primitives (engine gfx/meshgen.zig: tubes, lofts, vines, braids)
//! and the garden's own (blades, laminae, petals, stamens, flowers).
const lib = @import("../lib.zig");
const engine = lib.engine;
const m = engine.core.math;
const vertex = lib.vertex;
const species = lib.species;

pub const blades = @import("meshgen/blades.zig");
pub const laminae = @import("meshgen/laminae.zig");
pub const petals = @import("meshgen/petals.zig");
pub const shoots = @import("meshgen/shoots.zig");
pub const flowers = @import("meshgen/flowers.zig");
pub const drifts = @import("meshgen/drifts.zig");
pub const tests = @import("meshgen/tests.zig");
pub const blade = blades.blade;
pub const bladeAlong = blades.bladeAlong;
pub const bladeSpine = blades.bladeSpine;
pub const LAMINA_THICK = laminae.LAMINA_THICK;
pub const Lamina = laminae.Lamina;
pub const lamina = laminae.lamina;
pub const Petal = petals.Petal;
pub const petal = petals.petal;
pub const POLLEN = petals.POLLEN;
pub const Stamens = petals.Stamens;
pub const stamens = petals.stamens;
pub const plant = shoots.plant;
pub const shootCount = shoots.shootCount;
pub const Shoot = shoots.Shoot;
pub const SHOOT_RES = shoots.SHOOT_RES;
pub const offshoot = shoots.offshoot;
pub const shootPath = shoots.shootPath;
pub const shootFoldNearest = shoots.shootFoldNearest;
pub const shootFold = shoots.shootFold;
pub const shootFoldAlong = shoots.shootFoldAlong;
pub const Calyx = flowers.Calyx;
pub const flower = flowers.flower;
pub const bud = flowers.bud;
pub const leavesAlong = flowers.leavesAlong;
pub const leafAt = flowers.leafAt;
pub const BLADE_SEGS = 8;
/// mesh variants grown per species, so neighbouring plants differ in shape.
pub const VARIANTS = 4;

/// the engine's builder and primitives, writing the garden's vertex roles
pub const gen = engine.gfx.meshgen.Mesher(vertex.Part, .stem);
pub const Builder = gen.Builder;
pub const vine = gen.vine;
pub const braid = gen.braid;
pub const braidTurned = gen.braidTurned;
pub const braidAround = gen.braidAround;
pub const loft = gen.loft;
pub const patch = gen.patch;
pub const bands = gen.bands;
pub const Ellipsoid = gen.Ellipsoid;
pub const ellipsoid = gen.ellipsoid;
pub const bundle = gen.bundle;
const eg = engine.gfx.meshgen;
pub const LODS = eg.LODS;
pub const LOD_AT = eg.LOD_AT;
pub const lodAt = eg.lodAt;
pub const stride = eg.stride;
pub const BRAID_CORE = eg.BRAID_CORE;
pub const BRAID_STRAND = eg.BRAID_STRAND;
pub const BRAID_OFF = eg.BRAID_OFF;
pub const STRAND_SALT = eg.STRAND_SALT;
pub const strandTurn = eg.strandTurn;
pub const strandSwell = eg.strandSwell;
pub const transport = eg.transport;
pub const Growth = eg.Growth;
pub const grow = eg.grow;
pub const growthPath = eg.growthPath;
pub const taperRadii = eg.taperRadii;
/// growth keys a confluence is built at, evenly from sprout (0) to bloom (1).
/// Every key has the same vertices in the same order, so the plant shader
/// blends between the two around a plant's growth: it grows, never jumps.
pub const KEYS = 8;

/// how many meshes a species is built as: shapes picked by tile, or for a
/// confluence its growth keys.
pub fn variants(id:species.Id) u32 {
  return switch (species.get(id).genome.form) {
    .herb, .coil, .drift, .radiant, .star => VARIANTS,
    .confluence => KEYS,
  };
}

/// for a species grown through keys, the key below `growth` and how far
/// toward the next one it is; null for a species of fixed shapes.
pub const Key = struct { v:u32, f:f32 };
pub fn growthKey(id:species.Id, growth:f32) ?Key {
  switch (species.get(id).genome.form) {
    .herb, .coil, .drift, .radiant, .star => return null,
    .confluence => {
      const x = m.clamp01(growth) * (KEYS - 1);
      const v = @min(m.floorTo(u32, x), KEYS - 2);
      return .{.v = v, .f = x - m.f(v)};
    },
  }
}

/// slots per species in per-variant tables (the most any species uses).
pub const MAX_VARIANTS = @max(VARIANTS, KEYS);

/// where a (species, variant, level of detail) mesh sits in per-variant tables.
pub fn plantSlot(id:species.Id, variant:u32, lod:u32) usize { return (@as(usize, @intFromEnum(id)) * MAX_VARIANTS + variant) * LODS + lod; }

test {
  _ = blades;
  _ = laminae;
  _ = petals;
  _ = shoots;
  _ = flowers;
  _ = drifts;
  _ = tests;
}
