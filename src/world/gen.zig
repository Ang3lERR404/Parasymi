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

pub const Sample = struct { height:f32, kind:ck.Kind, ley:f32, res:u8 = 0 };

pub fn sample(seed:u64, wx:i32, wy:i32) Sample {
  const x = m.f(wx);
  const y = m.f(wy);
  // domain warp keeps coastlines and ridges organic instead of blobby.
  const wx2 = x + 14 * noise.fbm(seed +% 11, x / 90, y / 90, 3);
  const wy2 = y + 14 * noise.fbm(seed +% 12, x / 90, y / 90, 3);
  const e = noise.fbm(seed, wx2 / 70, wy2 / 70, 5) + 0.25 * noise.fbm(seed +% 1, x / 14, y / 14, 2);
  const wet = noise.fbm(seed +% 2, x / 55, y / 55, 3);
  const vein = noise.ridged(seed +% 3, wx2 / 45, wy2 / 45, 3);

  if (e < -0.28) return .{.height = WATER_H, .kind = .water, .ley = 0};
  const level:f32 = @floor((e + 0.28) * 7) + 1;
  const height = level * TERRACE;
  const kind:ck.Kind = if (e > 0.62) .stone
    else if (vein > 0.955) .ley
    else if (wet > 0.05) .moss
    else .soil;
  const ley = 0.2 + vein * vein * vein * (if (kind == .ley) @as(f32, 4) else 1);

  // resource nodes cluster in noisy patches. No flora: every plant is seeded.
  const h = rng.unit(rng.hash2(seed +% 7, wx, wy));
  const patch = noise.fbm(seed +% 5, x / 16, y / 16, 2);
  const res:u8 = if (patch > 0.42 and h < 0.6) @intFromFloat(6 + h * 20) else 0;
  return .{.height = height, .kind = kind, .ley = ley, .res = res};
}

pub fn heightAt(seed:u64, wx:i32, wy:i32) f32 { return sample(seed, wx, wy).height; }

pub fn generate(seed:u64, c:*ck.Chunk) void {
  const ox = c.originX();
  const oy = c.originY();
  for (0..ck.SIZE) |ly| for (0..ck.SIZE) |lx| {
    const i = ly * ck.SIZE + lx;
    const s = sample(seed, ox + @as(i32, @intCast(lx)), oy + @as(i32, @intCast(ly)));
    c.height[i] = s.height;
    c.kind[i] = s.kind;
    c.ley[i] = s.ley;
    c.ley_cap[i] = s.ley;
    c.res[i] = s.res;

    c.occ[i] = ck.NONE;
  };
}

test "generation is deterministic" {
  var a = ck.blank(.{.x = -3, .y = 7});
  var b = a;
  generate(1234, &a);
  generate(1234, &b);
  try testing.expectEqualSlices(f32, &a.height, &b.height);
  try testing.expectEqualSlices(ck.Kind, &a.kind, &b.kind);
}
