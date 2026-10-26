//! audio DSP building blocks, one sample at a time: oscillators, noise,
//! filters (one-pole, biquad), an ADSR envelope, a parameter smoother and a
//! delay line, plus level and pitch conversions. Pure maths at a sample
//! `rate` (Hz) each unit keeps; nothing here touches a device, so a sound is
//! built by chaining units (`Voice` shows how) and the platform's output
//! pulls blocks of samples from it.
const std = @import("std");
const m = @import("math.zig");
const rng = @import("rng.zig");
const testing = std.testing;
const Allocator = std.mem.Allocator;

/// the highest cutoff a filter takes, as a fraction of the sample rate (just
/// under Nyquist, where the biquad's maths breaks down)
const MAX_CUTOFF:f32 = 0.49;
/// 0 dB is a gain of 1; every 20 dB is a factor of 10
const DB_PER_DECADE:f32 = 20;
/// MIDI note 69 is A4, 440 Hz; 12 notes to the octave
const A4_NOTE:f32 = 69;
const A4_HZ:f32 = 440;
const NOTES_PER_OCTAVE:f32 = 12;
/// `softClip` reaches ±1 at ±3 and holds there
const CLIP_KNEE:f32 = 3;

// ---- conversions ----

/// decibels to a linear gain (-6 dB ≈ 0.5)
pub fn dbToGain(db:f32) f32 { return m.pow(f32, 10, db / DB_PER_DECADE); }
/// a linear gain (> 0) to decibels
pub fn gainToDb(g:f32) f32 { return DB_PER_DECADE * @log10(g); }
/// a MIDI note number (fractional for bends) to Hz
pub fn noteToHz(note:f32) f32 { return A4_HZ * m.pow(f32, 2, (note - A4_NOTE) / NOTES_PER_OCTAVE); }
/// a smooth saturator close to tanh: linear near 0, ±1 past ±3, so a loud
/// mix bends instead of clipping hard
pub fn softClip(x:f32) f32 {
  const c = m.clamp(x, -CLIP_KNEE, CLIP_KNEE);
  return c * (27 + c * c) / (27 + 9 * c * c);
}
/// `x` placed in stereo at `p` (-1 left, 0 centre, 1 right), equal power so
/// it stays as loud wherever it sits: .{left, right}
pub fn pan(x:f32, p:f32) [2]f32 {
  const a = (m.clamp(p, -1, 1) + 1) * (m.pi / 4.0);
  return .{x * @cos(a), x * @sin(a)};
}

/// the fractional part of a phase (wraps 0..1)
inline fn wrap(t:f32) f32 { return t - @floor(t); }

// ---- sources ----

pub const Shape = enum { sine, saw, square, triangle };

/// a periodic waveform. `phase` runs 0..1 per cycle; saw and square are
/// band-limited (polyBLEP) so high notes don't alias into whine.
pub const Osc = struct {
  rate:f32,
  shape:Shape = .sine,
  freq:f32 = A4_HZ,
  phase:f32 = 0,

  pub fn next(o:*Osc) f32 {
    const dt = o.freq / o.rate;
    const t = o.phase;
    const y = switch (o.shape) {
      .sine => @sin(m.tau * t),
      .saw => 2 * t - 1 - blep(t, dt),
      .square => (if (t < 0.5) @as(f32, 1) else -1) + blep(t, dt) - blep(wrap(t + 0.5), dt),
      // shifted a quarter cycle so it starts at 0 rising, like the sine
      .triangle => 1 - 4 * @abs(wrap(t + 0.25) - 0.5),
    };
    o.phase = wrap(t + dt);
    return y;
  }
};

/// polyBLEP: the correction that rounds off a unit jump at phase 0 over one
/// sample each side, `dt` being one sample's phase step
fn blep(t:f32, dt:f32) f32 {
  if (t < dt) {
    const x = t / dt;
    return x + x - x * x - 1;
  }
  if (t > 1 - dt) {
    const x = (t - 1) / dt;
    return x * x + x + x + 1;
  }
  return 0;
}

/// white noise in -1..1, the same stream for the same seed (wind, rustle,
/// the attack of a pluck)
pub const Noise = struct {
  r:rng.Rng,
  pub fn init(seed:u64) Noise { return .{.r = .init(seed)}; }
  pub fn next(n:*Noise) f32 { return n.r.float() * 2 - 1; }
};

// ---- filters ----

/// the cheapest filter: one pole, 6 dB/octave. `low` darkens, `high` thins;
/// call one of them per sample, not both.
pub const OnePole = struct {
  /// how far the state moves toward the input each sample (0..1; lower is darker)
  a:f32,
  z:f32 = 0,

  pub fn init(cutoff:f32, rate:f32) OnePole { return .{.a = coeff(cutoff, rate)}; }
  /// the coefficient whose -3 dB point sits at `cutoff` Hz
  pub fn coeff(cutoff:f32, rate:f32) f32 {
    return 1 - @exp(-m.tau * m.clamp(cutoff, 0, MAX_CUTOFF * rate) / rate);
  }
  pub fn low(p:*OnePole, x:f32) f32 {
    p.z += p.a * (x - p.z);
    return p.z;
  }
  pub fn high(p:*OnePole, x:f32) f32 { return x - p.low(x); }
};

/// a value that glides to its `target` instead of jumping, so a gain or
/// cutoff changed between blocks doesn't click ("zipper noise")
pub const Smooth = struct {
  value:f32,
  target:f32,
  a:f32,

  /// starts at `value`; `time` seconds to get ~63% of the way to a new target
  pub fn init(value:f32, time:f32, rate:f32) Smooth {
    return .{.value = value, .target = value, .a = 1 - @exp(-1 / @max(time * rate, 1))};
  }
  pub fn next(s:*Smooth) f32 {
    s.value += s.a * (s.target - s.value);
    return s.value;
  }
};

pub const BiquadKind = enum { low, high, band, notch };

/// the workhorse two-pole filter, 12 dB/octave (RBJ cookbook, transposed
/// direct form II). `q` is the resonance: 0.707 is flat, higher rings at
/// the cutoff.
pub const Biquad = struct {
  b0:f32, b1:f32, b2:f32, a1:f32, a2:f32,
  z1:f32 = 0,
  z2:f32 = 0,

  pub fn init(kind:BiquadKind, cutoff:f32, q:f32, rate:f32) Biquad {
    var f:Biquad = .{.b0 = 1, .b1 = 0, .b2 = 0, .a1 = 0, .a2 = 0};
    f.tune(kind, cutoff, q, rate);
    return f;
  }

  /// new coefficients, keeping the state so a sweep doesn't click
  pub fn tune(f:*Biquad, kind:BiquadKind, cutoff:f32, q:f32, rate:f32) void {
    const w = m.tau * m.clamp(cutoff, 1, MAX_CUTOFF * rate) / rate;
    const c = @cos(w);
    const alpha = @sin(w) / (2 * @max(q, 0.01));
    const b:[3]f32 = switch (kind) {
      .low => .{(1 - c) / 2, 1 - c, (1 - c) / 2},
      .high => .{(1 + c) / 2, -(1 + c), (1 + c) / 2},
      // 0 dB at the centre
      .band => .{alpha, 0, -alpha},
      .notch => .{1, -2 * c, 1},
    };
    const a0 = 1 + alpha;
    f.b0 = b[0] / a0;
    f.b1 = b[1] / a0;
    f.b2 = b[2] / a0;
    f.a1 = -2 * c / a0;
    f.a2 = (1 - alpha) / a0;
  }

  pub fn tick(f:*Biquad, x:f32) f32 {
    const y = f.b0 * x + f.z1;
    f.z1 = f.b1 * x - f.a1 * y + f.z2;
    f.z2 = f.b2 * x - f.a2 * y;
    return y;
  }
};

// ---- envelope ----

/// attack, decay, sustain, release: the loudness shape of one note, 0..1.
/// `on` starts it, `off` lets it fade; it is `.idle` once silent.
pub const Adsr = struct {
  pub const Stage = enum { idle, attack, decay, sustain, release };

  rate:f32,
  /// seconds
  attack:f32 = 0.01,
  decay:f32 = 0.1,
  /// level held while the note is down, 0..1
  sustain:f32 = 0.7,
  /// seconds from full level to silence
  release:f32 = 0.3,
  level:f32 = 0,
  stage:Stage = .idle,

  pub fn on(e:*Adsr) void { e.stage = .attack; }
  pub fn off(e:*Adsr) void {
    if (e.stage != .idle) e.stage = .release;
  }

  pub fn next(e:*Adsr) f32 {
    switch (e.stage) {
      .idle => e.level = 0,
      .attack => {
        e.level += e.step(e.attack);
        if (e.level >= 1) {
          e.level = 1;
          e.stage = .decay;
        }
      },
      .decay => {
        e.level -= (1 - e.sustain) * e.step(e.decay);
        if (e.level <= e.sustain) {
          e.level = e.sustain;
          e.stage = .sustain;
        }
      },
      .sustain => e.level = e.sustain,
      .release => {
        e.level -= e.step(e.release);
        if (e.level <= 0) {
          e.level = 0;
          e.stage = .idle;
        }
      },
    }
    return e.level;
  }

  /// the change per sample that covers 0..1 in `time` seconds
  fn step(e:Adsr, time:f32) f32 { return 1 / @max(time * e.rate, 1); }
};

// ---- delay ----

/// a ring of past samples: echoes, chorus, the start of a reverb. Owns its
/// buffer (`deinit`).
pub const Delay = struct {
  buf:[]f32,
  at:usize = 0,

  /// room for `max` samples of delay
  pub fn init(gpa:Allocator, max:usize) Allocator.Error!Delay {
    const buf = try gpa.alloc(f32, max + 1);
    @memset(buf, 0);
    return .{.buf = buf};
  }
  pub fn deinit(d:*Delay, gpa:Allocator) void { gpa.free(d.buf); }

  /// the sample written `delay` samples ago (fractional, interpolated;
  /// clamped to 1..max)
  pub fn read(d:Delay, delay:f32) f32 {
    const n = d.buf.len;
    const dl = m.clamp(delay, 1, m.f(n - 1));
    const whole = m.floorTo(usize, dl);
    const s0 = d.buf[(d.at + n - whole) % n];
    const s1 = d.buf[(d.at + n - whole - 1) % n];
    return m.lerp(s0, s1, dl - m.f(whole));
  }
  pub fn write(d:*Delay, x:f32) void {
    d.buf[d.at] = x;
    d.at = (d.at + 1) % d.buf.len;
  }
  /// `read` then `write`: a plain delay of `delay` samples
  pub fn tick(d:*Delay, x:f32, delay:f32) f32 {
    const y = d.read(delay);
    d.write(x);
    return y;
  }
};

// ---- a voice ----

/// one playable note, showing how the units chain: oscillator → low-pass →
/// envelope → gain. A game's sounds are built the same way.
pub const Voice = struct {
  osc:Osc,
  filter:Biquad,
  env:Adsr,
  gain:Smooth,

  pub fn init(rate:f32, shape:Shape) Voice {
    return .{
      .osc = .{.rate = rate, .shape = shape},
      .filter = .init(.low, 2000, 0.707, rate),
      .env = .{.rate = rate},
      .gain = .init(0.2, 0.01, rate),
    };
  }

  pub fn play(v:*Voice, freq:f32) void {
    v.osc.freq = freq;
    v.env.on();
  }
  pub fn stop(v:*Voice) void { v.env.off(); }

  /// what a game sends a playing voice (`platform.audio.Output`)
  pub const Cmd = union(enum) { play:f32, stop, gain:f32 };
  pub fn apply(v:*Voice, cmd:Cmd) void {
    switch (cmd) {
      .play => |hz| v.play(hz),
      .stop => v.stop(),
      .gain => |g| v.gain.target = g,
    }
  }

  /// fills `out` (mono), mixing into what is there so voices sum
  pub fn render(v:*Voice, out:[]f32) void {
    if (v.env.stage == .idle) return;
    for (out) |*s| s.* += v.filter.tick(v.osc.next()) * v.env.next() * v.gain.next();
  }
};

// ---- tests ----

const TEST_RATE:f32 = 48000;

test "conversions" {
  try testing.expectApproxEqAbs(@as(f32, 0.501), dbToGain(-6), 0.001);
  try testing.expectApproxEqAbs(@as(f32, -6), gainToDb(dbToGain(-6)), 0.001);
  try testing.expectApproxEqAbs(A4_HZ, noteToHz(69), 0.001);
  try testing.expectApproxEqAbs(@as(f32, 880), noteToHz(81), 0.01);
  try testing.expectEqual(@as(f32, 1), softClip(10));
  try testing.expectApproxEqAbs(@as(f32, 0.1), softClip(0.1), 0.001);
  const c = pan(1, 0);
  try testing.expectApproxEqAbs(@as(f32, 1), c[0] * c[0] + c[1] * c[1], 0.001);
}

test "sine at a quarter of the rate walks 0, 1, 0, -1" {
  var o:Osc = .{.rate = TEST_RATE, .freq = TEST_RATE / 4};
  for ([_]f32{0, 1, 0, -1}) |want| try testing.expectApproxEqAbs(want, o.next(), 0.001);
}

test "band-limited saw and square stay bounded and centred" {
  for ([_]Shape{.saw, .square, .triangle}) |shape| {
    var o:Osc = .{.rate = TEST_RATE, .shape = shape, .freq = 3001};
    var sum:f32 = 0;
    const n = 48000;
    for (0..n) |_| {
      const y = o.next();
      try testing.expect(@abs(y) <= 1.2);
      sum += y;
    }
    try testing.expect(@abs(sum / n) < 0.01);
  }
}

test "noise repeats for a seed" {
  var a:Noise = .init(7);
  var b:Noise = .init(7);
  for (0..64) |_| {
    const y = a.next();
    try testing.expect(@abs(y) <= 1);
    try testing.expectEqual(y, b.next());
  }
}

test "one-pole low passes DC, high blocks it" {
  var lo:OnePole = .init(100, TEST_RATE);
  var hi:OnePole = .init(100, TEST_RATE);
  var l:f32 = 0;
  var h:f32 = 1;
  for (0..TEST_RATE) |_| {
    l = lo.low(1);
    h = hi.high(1);
  }
  try testing.expectApproxEqAbs(@as(f32, 1), l, 0.001);
  try testing.expectApproxEqAbs(@as(f32, 0), h, 0.001);
}

test "biquad low passes DC and stops Nyquist; high the reverse" {
  var lo:Biquad = .init(.low, 1000, 0.707, TEST_RATE);
  var hi:Biquad = .init(.high, 1000, 0.707, TEST_RATE);
  var l_dc:f32 = 0;
  var h_dc:f32 = 1;
  for (0..4800) |_| {
    l_dc = lo.tick(1);
    h_dc = hi.tick(1);
  }
  try testing.expectApproxEqAbs(@as(f32, 1), l_dc, 0.001);
  try testing.expectApproxEqAbs(@as(f32, 0), h_dc, 0.001);

  lo = .init(.low, 1000, 0.707, TEST_RATE);
  hi = .init(.high, 1000, 0.707, TEST_RATE);
  var l_ny:f32 = 0;
  var h_ny:f32 = 0;
  for (0..4800) |i| {
    const x:f32 = if (i % 2 == 0) 1 else -1;
    l_ny = @max(l_ny * 0.99, @abs(lo.tick(x)));
    h_ny = @abs(hi.tick(x));
  }
  try testing.expect(l_ny < 0.01);
  try testing.expectApproxEqAbs(@as(f32, 1), h_ny, 0.01);
}

test "adsr rises, holds, fades to idle" {
  var e:Adsr = .{.rate = 1000, .attack = 0.01, .decay = 0.01, .sustain = 0.5, .release = 0.01};
  e.on();
  for (0..10) |_| _ = e.next();
  try testing.expectEqual(@as(f32, 1), e.level);
  for (0..20) |_| _ = e.next();
  try testing.expectEqual(Adsr.Stage.sustain, e.stage);
  try testing.expectEqual(@as(f32, 0.5), e.next());
  e.off();
  for (0..10) |_| _ = e.next();
  try testing.expectEqual(Adsr.Stage.idle, e.stage);
  try testing.expectEqual(@as(f32, 0), e.level);
}

test "delay returns an impulse after its length" {
  var d:Delay = try .init(testing.allocator, 16);
  defer d.deinit(testing.allocator);
  var got:?usize = null;
  for (0..20) |i| {
    const y = d.tick(if (i == 0) 1 else 0, 5);
    if (y == 1) got = i;
  }
  try testing.expectEqual(@as(?usize, 5), got);
  // half way between two samples reads half of each
  d.write(1);
  d.write(0);
  try testing.expectApproxEqAbs(@as(f32, 0.5), d.read(1.5), 0.001);
}

test "a voice sounds while held and falls silent after release" {
  var v:Voice = .init(TEST_RATE, .saw);
  var buf:[480]f32 = @splat(0);
  v.render(&buf);
  try testing.expectEqual(@as(f32, 0), buf[100]);
  v.play(220);
  v.render(&buf);
  var peak:f32 = 0;
  for (buf) |s| peak = @max(peak, @abs(s));
  try testing.expect(peak > 0.05);
  v.stop();
  for (0..100) |_| {
    @memset(&buf, 0);
    v.render(&buf);
  }
  try testing.expectEqual(Adsr.Stage.idle, v.env.stage);
}
