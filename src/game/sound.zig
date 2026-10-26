//! what the garden sounds like: the source the audio device plays (main.zig
//! opens it on `platform.audio.Output`). The game sends it what happened
//! (`Cmd`) and each sound plays out on a free voice of its pool, nothing
//! allocated while it plays.
//! - a footstep is a soft crunchy rustle: leaf litter shuffled under a paw
//!   (band-passed noise fluttering like leaves), dry bits crushed in it (a
//!   crackle, thick at the footfall and thinning as it fades) and a muffled
//!   pad landing under both. The heavier the wolf the lower and fuller, the
//!   faster the louder and shorter; no two steps are alike.
const lib = @import("../lib.zig");
const std = lib.std;
const testing = std.testing;
const engine = lib.engine;
const m = engine.core.math;
const dsp = engine.core.dsp;
const rng = engine.core.rng;
const Footfall = lib.player.Footfall;

/// samples per second the sounds are built for (a device that will not
/// play at it leaves the garden silent)
pub const RATE:u32 = 48000;
/// steps that may sound at once (a sprint overlaps two or three)
const VOICES = 6;
/// a step quieter than this has ended and frees its voice
const SILENT:f32 = 1e-4;

/// the step's shape: seconds to full loudness, then to fall ~63%; a sprint
/// fades this share as long
const ATTACK:f32 = 0.005;
const FALL:f32 = 0.055;
const FALL_FAST:f32 = 0.6;
/// the leaves: the band they rustle in (Hz) and its width (q), a full
/// belly pulling it this share lower; level to match the other layers
const RUSTLE_HZ:f32 = 2200;
const RUSTLE_Q:f32 = 0.8;
const RUSTLE_HEAVY:f32 = 0.35;
const RUSTLE:f32 = 4;
/// how fast the leaves flutter (Hz, below it) and how deep (0..1)
const FLUTTER_HZ:f32 = 45;
const FLUTTER:f32 = 0.8;
/// crushed bits: grains per second at the footfall (more for a full belly),
/// how long each rings (s), heard above this (Hz), level
const CRUNCH_DENSITY:f32 = 700;
const CRUNCH_HEAVY:f32 = 0.6;
const CRUNCH_GRAIN:f32 = 0.0007;
const CRUNCH_HZ:f32 = 2600;
const CRUNCH:f32 = 0.9;
/// the pad's muffled landing: below this (Hz), falling ~63% in this (s),
/// level light and full
const PAD_HZ:f32 = 180;
const PAD_FALL:f32 = 0.03;
const PAD_LIGHT:f32 = 1.5;
const PAD_FULL:f32 = 6;
/// what softens all of it (Hz)
const SOFT_HZ:f32 = 7000;
/// loudness of a settling paw and of a sprinting one
const QUIET:f32 = 0.1;
const LOUD:f32 = 0.3;
/// each step strays from these by up to this share
const VARY:f32 = 0.2;

/// `x` strayed by up to `VARY` either way
fn vary(r:*rng.Rng, x:f32) f32 { return x * r.range(1 - VARY, 1 + VARY); }

/// one footstep playing out
const Step = struct {
  noise:dsp.Noise,
  crunch:dsp.Crackle,
  rustle:dsp.Biquad,
  bits:dsp.Biquad,
  pad:dsp.Biquad,
  flutter:dsp.OnePole,
  /// scales the flutter's low-passed noise back to about ±1
  flutter_norm:f32,
  soft:dsp.OnePole,
  /// samples into the step, and how many the attack takes
  at:u32 = 0,
  attack:u32,
  /// the body's and the pad's loudness, each kept by its fall per sample
  body:f32 = 1,
  thump:f32 = 1,
  fall:f32,
  pad_fall:f32,
  density:f32,
  gain:f32,
  pad_gain:f32,

  fn init(f:Footfall, r:*rng.Rng, rate:f32) Step {
    const fall = vary(r, FALL) * m.lerp(1, FALL_FAST, f.pace);
    const a = dsp.OnePole.coeff(FLUTTER_HZ, rate);
    return .{
      .noise = .init(r.next()),
      .crunch = .init(r.next(), CRUNCH_GRAIN, rate),
      .rustle = .init(.band, vary(r, RUSTLE_HZ) * (1 - RUSTLE_HEAVY * f.weight), RUSTLE_Q, rate),
      .bits = .init(.high, vary(r, CRUNCH_HZ), 0.707, rate),
      .pad = .init(.low, vary(r, PAD_HZ) * (1 - RUSTLE_HEAVY * f.weight), 0.707, rate),
      .flutter = .{.a = a},
      // decision: white noise in ±1 has a variance of 1/3; a one-pole keeps
      // a/(2-a) of it
      .flutter_norm = @sqrt(3 * (2 - a) / a),
      .soft = .init(SOFT_HZ, rate),
      .attack = m.floorTo(u32, ATTACK * rate) + 1,
      .fall = @exp(-1 / (fall * rate)),
      .pad_fall = @exp(-1 / (PAD_FALL * rate)),
      .density = CRUNCH_DENSITY * (1 + CRUNCH_HEAVY * f.weight),
      .gain = vary(r, m.lerp(QUIET, LOUD, f.pace)),
      .pad_gain = m.lerp(PAD_LIGHT, PAD_FULL, f.weight),
    };
  }

  /// mixes the step into `out`; false once it has ended
  fn render(st:*Step, out:[]f32) bool {
    for (out) |*s| {
      const rise = m.clamp01(m.f(st.at) / m.f(st.attack));
      if (st.at >= st.attack) {
        st.body *= st.fall;
        st.thump *= st.pad_fall;
      }
      st.at +|= 1;
      const env = rise * st.body;
      // the crushing is all at the footfall, thinning faster than the rustle
      st.crunch.density = st.density * env * env;
      const n = st.noise.next();
      const z = st.flutter.low(st.noise.next()) * st.flutter_norm;
      const flut = 1 - FLUTTER + FLUTTER * m.clamp01(0.5 + 0.5 * z);
      const leaves = st.rustle.tick(n) * RUSTLE * flut * env;
      const bits = st.bits.tick(st.crunch.next()) * CRUNCH;
      const pad = st.pad.tick(n) * st.pad_gain * rise * st.thump;
      s.* += st.soft.low(leaves + bits + pad) * st.gain;
    }
    return st.at < st.attack or st.body > SILENT;
  }
};

/// the source the device pulls from (`platform.audio.Output(Sounds)`)
pub const Sounds = struct {
  pub const Cmd = union(enum) { step:Footfall };

  rate:f32,
  r:rng.Rng,
  steps:[VOICES]?Step = @splat(null),
  /// the voice taken when none is free (round the pool: the oldest)
  steal:usize = 0,

  pub fn init(seed:u64, rate:f32) Sounds { return .{.rate = rate, .r = .init(seed)}; }

  pub fn apply(s:*Sounds, cmd:Cmd) void {
    switch (cmd) {
      .step => |f| s.steps[s.free()] = .init(f, &s.r, s.rate),
    }
  }

  pub fn render(s:*Sounds, out:[]f32) void {
    for (&s.steps) |*v| if (v.*) |*st| {
      if (!st.render(out)) v.* = null;
    };
    for (out) |*x| x.* = dsp.softClip(x.*);
  }

  fn free(s:*Sounds) usize {
    for (s.steps, 0..) |v, i| if (v == null) return i;
    defer s.steal = (s.steal + 1) % VOICES;
    return s.steal;
  }
};

const TEST_RATE:f32 = 48000;

/// one step rendered alone: its peak, its loudness (rms) and how long it
/// sounds (s)
fn hear(f:Footfall, seed:u64) struct { peak:f32, rms:f32, len:f32 } {
  var s:Sounds = .init(seed, TEST_RATE);
  s.apply(.{.step = f});
  var buf:[480]f32 = undefined;
  var peak:f32 = 0;
  var sum:f32 = 0;
  var n:u32 = 0;
  while (s.steps[0] != null and n < 48000) {
    @memset(&buf, 0);
    s.render(&buf);
    for (buf) |x| {
      peak = @max(peak, @abs(x));
      sum += x * x;
    }
    n += buf.len;
  }
  return .{.peak = peak, .rms = @sqrt(sum / m.f(n)), .len = m.f(n) / TEST_RATE};
}

test "a footstep is short, soft and never clips; a sprint is louder" {
  const soft = hear(.{.weight = 0, .pace = 0.3}, 1);
  const fast = hear(.{.weight = 0, .pace = 1}, 1);
  const full = hear(.{.weight = 1, .pace = 0.3}, 1);
  for ([_]@TypeOf(soft){soft, fast, full}) |h| {
    try testing.expect(h.peak > 0.02 and h.peak < 0.8);
    try testing.expect(h.len > 0.1 and h.len < 0.8);
  }
  try testing.expect(fast.rms > soft.rms);
  try testing.expect(fast.len < soft.len);
}

test "steps vary, a busy pool steals the oldest, and it ends silent" {
  var s:Sounds = .init(9, TEST_RATE);
  for (0..VOICES + 2) |_| s.apply(.{.step = .{.weight = 0.5, .pace = 0.5}});
  for (s.steps) |v| try testing.expect(v != null);
  try testing.expect(s.steps[0].?.gain != s.steps[1].?.gain);
  var buf:[480]f32 = undefined;
  for (0..200) |_| {
    @memset(&buf, 0);
    s.render(&buf);
  }
  for (s.steps) |v| try testing.expect(v == null);
  for (buf) |x| try testing.expectEqual(@as(f32, 0), x);
}
