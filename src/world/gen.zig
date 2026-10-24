//! world generation: a pure function of (seed, tile coordinate). Chunks never
//! depend on neighbours being loaded, so meshing and streaming stay order-free.
const std = @import("std");
const testing = std.testing;
const m = @import("../core/math.zig");
const noise = @import("../core/noise.zig");
const ck = @import("chunk.zig");
const rng = @import("../core/rng.zig");

pub const TERRACE = 0.35;
pub const WATER_H = 0.0;
/// where the land meets the water it dips just under the surface
pub const SHORE = WATER_H - 0.14;
/// terrace levels per unit of elevation noise; below `SEA` is water
const LEVELS:f32 = 7;
const SEA:f32 = -0.28;
/// elevation above which the ground is bare stone
const STONE:f32 = 0.62;
/// ridged vein noise above this is a ley line; ley lines carry 4x the ley
const VEIN:f32 = 0.955;
const LEY_BASE:f32 = 0.2;
const LEY_LINE:f32 = 4;
/// wetness above which the ground is moss, not soil
const WET:f32 = 0.05;
/// noise wavelengths (tiles): domain warp (and how far it pushes),
/// continents, hills (and their share), wetness, veins, resource patches
const WARP_L:f32 = 90;
const WARP:f32 = 14;
const CONTINENT_L:f32 = 70;
const HILL_L:f32 = 14;
const HILLS:f32 = 0.25;
const WET_L:f32 = 55;
const VEIN_L:f32 = 45;
const PATCH_L:f32 = 16;
/// octaves of each: warp, continents, hills, wetness, veins, patches
const WARP_OCT = 3;
const CONTINENT_OCT = 5;
const HILL_OCT = 2;
const WET_OCT = 3;
const VEIN_OCT = 3;
const PATCH_OCT = 2;
/// resource nodes: in patches denser than `PATCH`, on `NODE_CHANCE` of their
/// tiles, holding `RES_MIN` plus up to `RES_SPREAD` scaled by the tile hash
const PATCH:f32 = 0.42;
const NODE_CHANCE:f32 = 0.6;
const RES_MIN:f32 = 1500;
const RES_SPREAD:f32 = 3000;
/// the yardstick for how full a node looks (drawn at full size)
pub const RES_FULL:f32 = RES_MIN + RES_SPREAD;
/// the most ley a tile holds (a ley line at full vein strength)
pub const LEY_MAX:f32 = LEY_BASE + LEY_LINE;

pub const Sample = struct { height:f32, kind:ck.Kind, ley:f32, res:ck.Res = 0 };

pub fn sample(seed:u64, wx:i32, wy:i32) Sample {
  const x = m.f(wx);
  const y = m.f(wy);
  // domain warp keeps coastlines and ridges organic instead of blobby.
  const wx2 = x + WARP * noise.fbm(seed +% 11, x / WARP_L, y / WARP_L, WARP_OCT);
  const wy2 = y + WARP * noise.fbm(seed +% 12, x / WARP_L, y / WARP_L, WARP_OCT);
  const e = noise.fbm(seed, wx2 / CONTINENT_L, wy2 / CONTINENT_L, CONTINENT_OCT) + HILLS * noise.fbm(seed +% 1, x / HILL_L, y / HILL_L, HILL_OCT);
  const wet = noise.fbm(seed +% 2, x / WET_L, y / WET_L, WET_OCT);
  const vein = noise.ridged(seed +% 3, wx2 / VEIN_L, wy2 / VEIN_L, VEIN_OCT);

  if (e < SEA) return .{.height = WATER_H, .kind = .water, .ley = 0};
  const level:f32 = @floor((e - SEA) * LEVELS) + 1;
  const height = level * TERRACE;
  const kind:ck.Kind = if (e > STONE) .stone
    else if (vein > VEIN) .ley
    else if (wet > WET) .moss
    else .soil;
  const ley = LEY_BASE + vein * vein * vein * (if (kind == .ley) LEY_LINE else 1);

  // resource nodes cluster in noisy patches. No flora: every plant is seeded.
  const h = rng.unit(rng.hash2(seed +% 7, wx, wy));
  const patch = noise.fbm(seed +% 5, x / PATCH_L, y / PATCH_L, PATCH_OCT);
  const res:ck.Res = if (patch > PATCH and h < NODE_CHANCE) @intFromFloat(RES_MIN + h * RES_SPREAD) else 0;
  return .{.height = height, .kind = kind, .ley = ley, .res = res};
}

pub fn heightAt(seed:u64, wx:i32, wy:i32) f32 { return sample(seed, wx, wy).height; }

pub fn generate(seed:u64, c:*ck.Chunk) void {
  for (0..ck.N) |i| {
    const wx, const wy = c.tileOf(i);
    const s = sample(seed, wx, wy);
    c.height[i] = s.height;
    c.kind[i] = s.kind;
    c.ley[i] = s.ley;
    c.ley_cap[i] = s.ley;
    c.res[i] = s.res;

    c.occ[i] = .none;
  }
}

test "generation is deterministic" {
  var a = ck.blank(.{.x = -3, .y = 7});
  var b = a;
  generate(1234, &a);
  generate(1234, &b);
  try testing.expectEqualSlices(f32, &a.height, &b.height);
  try testing.expectEqualSlices(ck.Kind, &a.kind, &b.kind);
}
