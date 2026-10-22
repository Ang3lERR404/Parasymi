//! deterministic hashing + small PRNG. Everything procedural derives from these,
//! so the same seed always yields the same world.
const std = @import("std");
const m = @import("math.zig");
const testing = std.testing;

pub inline fn mix64(x0:u64) u64 {
  var x = x0 +% 0x9E3779B97F4A7C15;
  x = (x ^ (x >> 30)) *% 0xBF58476D1CE4E5B9;
  x = (x ^ (x >> 27)) *% 0x94D049BB133111EB;
  return x ^ (x >> 31);
}

/// hash of an integer lattice point (with a seed and a channel salt).
pub inline fn hash2(seed:u64, x:i32, y:i32) u32 {
  const a:u64 = @as(u32, @bitCast(x));
  const b:u64 = @as(u32, @bitCast(y));
  return @truncate(mix64(seed ^ (a << 32 | b)) >> 16);
}

pub inline fn unit(h:u32) f32 { return m.f(h >> 8) * (1.0 / 16777216.0); }

pub const Rng = struct {
  s:u64,
  pub fn init(seed:u64) Rng { return .{.s = mix64(seed)}; }
  pub fn next(r:*Rng) u64 { r.s +%= 0x9E3779B97F4A7C15; return mix64(r.s); }
  pub fn float(r:*Rng) f32 { return unit(@truncate(r.next())); }
  pub fn range(r:*Rng, lo:f32, hi:f32) f32 { return lo + (hi - lo) * r.float(); }
};

test "hash determinism" {
  try testing.expectEqual(hash2(7, -3, 9), hash2(7, -3, 9));
  try testing.expect(hash2(7, -3, 9) != hash2(8, -3, 9));
  var r = Rng.init(1);
  for (0..1000) |_| { const f = r.float(); try testing.expect(f >= 0 and f < 1); }
}
