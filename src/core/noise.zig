//! 2D gradient noise + fractal variants. Output of `grad` is roughly -1..1.
const std = @import("std");
const m = @import("math.zig");
const testing = std.testing;
const rng = @import("rng.zig");

inline fn fade(t:f32) f32 { return t * t * t * (t * (t * 6 - 15) + 10); }

inline fn gdot(seed:u64, ix:i32, iy:i32, fx:f32, fy:f32) f32 {
  const h = rng.hash2(seed, ix, iy);
  const a = m.f(h & 0xffff) * (m.tau / 65536.0);
  return @cos(a) * fx + @sin(a) * fy;
}

pub fn grad(seed:u64, x:f32, y:f32) f32 {
  const x0 = @floor(x);
  const y0 = @floor(y);
  const ix:i32 = @intFromFloat(x0);
  const iy:i32 = @intFromFloat(y0);
  const fx = x - x0;
  const fy = y - y0;
  const u = fade(fx);
  const v = fade(fy);
  const n00 = gdot(seed, ix, iy, fx, fy);
  const n10 = gdot(seed, ix + 1, iy, fx - 1, fy);
  const n01 = gdot(seed, ix, iy + 1, fx, fy - 1);
  const n11 = gdot(seed, ix + 1, iy + 1, fx - 1, fy - 1);
  const a = n00 + (n10 - n00) * u;
  const b = n01 + (n11 - n01) * u;
  return (a + (b - a) * v) * 1.414;
}

/// fractal brownian motion, normalised to about -1..1.
pub fn fbm(seed:u64, x:f32, y:f32, octaves:u32) f32 {
  var sum:f32 = 0;
  var amp:f32 = 1;
  var freq:f32 = 1;
  var norm:f32 = 0;
  var s = seed;
  for (0..octaves) |_| {
    sum += grad(s, x * freq, y * freq) * amp;
    norm += amp;
    amp *= 0.5;
    freq *= 2.03;
    s = rng.mix64(s);
  }
  return sum / norm;
}

/// ridged noise: thin bright lines (used for ley veins), 0..1.
pub fn ridged(seed:u64, x:f32, y:f32, octaves:u32) f32 {
  const n = 1 - @abs(fbm(seed, x, y, octaves));
  return n * n;
}

test "noise range + determinism" {
  var x:f32 = -50;
  while (x < 50) : (x += 0.37) {
    const n = fbm(42, x, x * 0.7, 4);
    try testing.expect(n >= -1.5 and n <= 1.5);
    try testing.expectEqual(n, fbm(42, x, x * 0.7, 4));
  }
}
