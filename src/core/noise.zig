//! 2D gradient noise + fractal variants. Output of `grad` is roughly -1..1.
const std = @import("std");
const m = @import("math.zig");
const testing = std.testing;
const rng = @import("rng.zig");

/// quintic smoothstep (C2 continuous). Used for Perlin interpolation;
/// m.smooth is cubic (C1) and shows pinch points at cell boundaries.
inline fn fade(t:f32) f32 { return t * t * t * (t * (t * 6 - 15) + 10); }

/// 16 bits of the hash give 65536 gradient angles — visually indistinguishable
/// from 64 bits at game scale, and keeps the multiply cheap.
const GRAD_BITS = 16;
const GRAD_MASK = (1 << GRAD_BITS) - 1;
const GRAD_SCALE = m.tau / m.f(1 << GRAD_BITS);

inline fn gdot(seed:u64, ix:i32, iy:i32, fx:f32, fy:f32) f32 {
  const h = rng.hash2(seed, ix, iy);
  const a = m.f(h & GRAD_MASK) * GRAD_SCALE;
  return @cos(a) * fx + @sin(a) * fy;
}

/// √2: the max of bilinearly-interpolated 2D dot products is ~1/√2,
/// so multiplying normalises the output to roughly -1..1.
const NORM:f32 = 1.41421356;

/// octave frequency multiplier. The 0.03 offset breaks the exact 2× lattice
/// so adjacent octaves don't align into visible grid artifacts.
const LACUNARITY:f32 = 2.03;

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
  return (a + (b - a) * v) * NORM;
}

/// fractal brownian motion, normalised to about -1..1.
/// NOTE: changing `octaves` changes the output for all lower octaves too,
/// because each octave is re-seeded from the previous. Don't "add an octave
/// later" expecting the existing ones to stay the same.
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
    freq *= LACUNARITY;
    s = rng.mix64(s);
  }
  return sum / norm;
}

/// ridged noise: thin bright lines (used for ley veins), 0..1.
pub fn ridged(seed:u64, x:f32, y:f32, octaves:u32) f32 {
  const n = 1 - @abs(fbm(seed, x, y, octaves));
  return n * n;
}

// ---- tests ----

test "grad range + determinism" {
  var x:f32 = -50;
  while (x < 50) : (x += 0.37) {
    var y:f32 = -50;
    while (y < 50) : (y += 0.37) {
      const n = grad(42, x, y);
      try testing.expect(n >= -1.5 and n <= 1.5);
      try testing.expectEqual(n, grad(42, x, y));
    }
  }
}

test "fbm range + determinism + seed sensitivity" {
  var differs:usize = 0;
  var x:f32 = -20;
  while (x < 20) : (x += 0.5) {
    const n = fbm(42, x, x * 0.7, 4);
    try testing.expect(n >= -1.5 and n <= 1.5);
    try testing.expectEqual(n, fbm(42, x, x * 0.7, 4));
    if (@abs(n - fbm(43, x, x * 0.7, 4)) > 1e-6) differs += 1;
  }
  // another seed is another field almost everywhere
  try testing.expect(differs > 70);
}

test "ridged is in 0..1" {
  var x:f32 = -10;
  while (x < 10) : (x += 0.3) {
    const n = ridged(7, x, x * 1.3, 3);
    try testing.expect(n >= 0 and n <= 1);
  }
}

test "fbm single octave ≈ grad" {
  // with 1 octave, fbm is just grad normalised by amp=1, so they should match
  const a = fbm(99, 3.7, -2.1, 1);
  const b = grad(99, 3.7, -2.1);
  try testing.expectApproxEqAbs(a, b, 1e-5);
}   