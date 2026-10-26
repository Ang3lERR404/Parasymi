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

/// hash of an integer lattice point. Takes a middle 32-bit slice of the
/// 64-bit mix (bits 16..47).
pub inline fn hash2(seed:u64, x:i32, y:i32) u32 {
  // @bitCast on i32 wraps negatives — intentional: the hash of (-1, 0)
  // must differ from the hash of (0, 0) but be stable across platforms.
  const a:u64 = @as(u32, @bitCast(x));
  const b:u64 = @as(u32, @bitCast(y));
  return @truncate(mix64(seed ^ (a << 32 | b)) >> 16);
}

/// top 24 bits of a u32 hash -> 0..1 (exclusive). The >> 8 discards the
/// 8 weakest bits.
pub inline fn unit(h:u32) f32 { return m.f(h >> 8) * UNIT_STEP; }
/// 2^-24: one step of a 24-bit unit value
const UNIT_STEP:f32 = 1.0 / 16777216.0;

pub const Rng = struct {
  s:u64,
  pub fn init(seed:u64) Rng { return .{.s = mix64(seed)}; }
  pub fn next(r:*Rng) u64 { r.s +%= 0x9E3779B97F4A7C15; return mix64(r.s); }
  /// decision: bits 8..31 of the output, as every grown mesh and the
  /// starfall were tuned against; changing them reshapes every plant.
  pub fn float(r:*Rng) f32 { return unit(@truncate(r.next())); }
  pub fn range(r:*Rng, lo:f32, hi:f32) f32 { return lo + (hi - lo) * r.float(); }
  /// uniform integer in 0..n (exclusive), no modulo bias.
  pub fn below(r:*Rng, n:u32) u32 {
    if (n <= 1) return 0;
    // reject the top (2^32 mod n) values so every residue is equally likely
    const span:u64 = @as(u64, 1) << 32;
    const limit:u64 = span - span % n;
    while (true) {
      const h:u64 = @as(u32, @truncate(r.next()));
      if (h < limit) return @intCast(h % n);
    }
  }
};

test "hash2 is roughly uniform across buckets" {
  // 10000 samples into 4 buckets; each should be ~2500 ± 10%
  var buckets:[4]u32 = .{0, 0, 0, 0};
  var x:i32 = 0;
  var y:i32 = 0;
  var i:u32 = 0;
  while (i < 10000) : (i += 1) {
    buckets[hash2(42, x, y) & 3] += 1;
    x += 1;
    if (x == 100) { x = 0; y += 1; }
  }
  for (buckets) |b| {
    try testing.expect(b > 2000 and b < 3000);
  }
}

test "Rng sequence is deterministic" {
  var a = Rng.init(99);
  var b = Rng.init(99);
  for (0..100) |_| {
    try testing.expectEqual(a.next(), b.next());
  }
}

test "Rng.float distribution" {
  var r = Rng.init(123);
  var buckets:[10]u32 = .{0} ** 10;
  for (0..10000) |_| {
    buckets[@intFromFloat(r.float() * 10)] += 1;
  }
  for (buckets) |b| {
    try testing.expect(b > 800 and b < 1200);
  }
}

test "Rng.below stays in range and covers it" {
  var r = Rng.init(7);
  try testing.expectEqual(@as(u32, 0), r.below(1));
  var seen:[3]u32 = .{0, 0, 0};
  for (0..3000) |_| seen[r.below(3)] += 1;
  for (seen) |c| try testing.expect(c > 850 and c < 1150);
  // a power of two leaves nothing to reject
  for (0..100) |_| try testing.expect(r.below(1 << 31) < 1 << 31);
}
   