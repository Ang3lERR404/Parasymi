//! what the garden sounds like: the source the audio device plays (main.zig
//! opens it on `platform.audio.Output`). The game sends it what happened
//! (`Cmd`) and each sound plays out on a free voice of its pool, nothing
//! allocated while it plays.
//! - a footstep is a soft crunchy rustle: leaf litter shuffled under a paw
//!   (band-passed noise fluttering like leaves), dry bits crushed in it (a
//!   crackle, thick at the footfall and thinning as it fades) and a muffled
//!   pad landing under both. The heavier the wolf the lower and fuller, the
//!   faster the louder and shorter; no two steps are alike.
//! - out of the wolf's eyes (first person) its sap is heard settling now and
//!   then, from inside: a soft slow groan, a low reedy hum through a closing
//!   throat sagging as it sinks, with a few thick gloops rising through it
//!   (now and then a lighter, smaller one or two among them), all muffled. It settles more often while the wolf stands; a full belly
//!   groans lower.
//! - all the while a gentle wind breathes over the garden: a soft low hush
//!   swelling and easing in slow gusts, and in the stronger ones a warm,
//!   breathy whistle (low, soft-edged banded air with a rounder octave
//!   under it) leaning up a little with the gust.
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
const RUSTLE_HZ:f32 = 1500;
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
const CRUNCH_GRAIN:f32 = 0.0015;
const CRUNCH_HZ:f32 = 1800;
const CRUNCH:f32 = 0.5;
/// the pad's muffled landing: below this (Hz), falling ~63% in this (s),
/// level light and full
const PAD_HZ:f32 = 180;
const PAD_FALL:f32 = 0.03;
const PAD_LIGHT:f32 = 1.5;
const PAD_FULL:f32 = 6;
/// what softens all of it (Hz)
const SOFT_HZ:f32 = 3800;
/// loudness of a settling paw and of a sprinting one
const QUIET:f32 = 0.05;
const LOUD:f32 = 0.14;
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

// ---- the sap settling (first person) ----

/// how long a settling lasts (s)
const SETTLE_LEN = [2]f32{2.4, 3.8};
/// seconds between settlings while the wolf stands and while it walks; the
/// first comes this soon after the view enters the eyes
const GAP_STILL = [2]f32{3.5, 8};
const GAP_WALK = [2]f32{9, 18};
const GAP_FIRST = [2]f32{1.2, 3};
/// the wolf stands once no step has landed for this long (s)
const STILL_AFTER:f32 = 1.2;
/// the groan: a low reedy hum (Hz) sagging this share as it settles,
/// wavering slowly (Hz, share), voiced through a throat (Hz) closing from
/// the first to the second, ringing this much (q); breath in it (noise
/// share) and its level. A full belly pulls it all this share lower.
const GROAN_HZ:f32 = 48;
const GROAN_SAG:f32 = 0.18;
const WAVER_HZ:f32 = 2.3;
const WAVER:f32 = 0.025;
const THROAT_HZ = [2]f32{260, 150};
const THROAT_Q:f32 = 3.5;
const BREATH:f32 = 0.35;
const GROAN:f32 = 1.2;
const SAP_HEAVY:f32 = 0.25;
/// samples between retunings of the closing throat
const RETUNE = 32;
/// a kind of gloop: how many (fewest, most), when (shares of the
/// settling), its pitch (Hz), its fall (s) and level
const GloopKind = struct { n:[2]u32, at:[2]f32, hz:[2]f32, fall:[2]f32, level:f32 };
/// the deep ones every settling has, and the lighter, smaller ones that
/// come with only this share of settlings
const DEEP:GloopKind = .{.n = .{2, 5}, .at = .{0.1, 0.65}, .hz = .{110, 210}, .fall = .{0.06, 0.12}, .level = 0.6};
const LIGHT:GloopKind = .{.n = .{1, 2}, .at = .{0.2, 0.75}, .hz = .{300, 460}, .fall = .{0.035, 0.06}, .level = 0.35};
const LIGHT_CHANCE:f32 = 0.25;
const GLOOPS = DEEP.n[1] + LIGHT.n[1];
/// each gloop's pitch rises this share as it fades; its attack (s)
const GLOOP_RISE:f32 = 0.7;
const GLOOP_ATTACK:f32 = 0.006;
/// heard from inside: what muffles it (Hz), its loudness, and how fast it
/// fades in and out with the view (s)
const SAP_SOFT_HZ:f32 = 650;
const SAP:f32 = 0.07;
const SAP_FADE:f32 = 0.35;

/// seconds in `span` as samples
fn samples(r:*rng.Rng, span:[2]f32, rate:f32) u32 { return m.floorTo(u32, r.range(span[0], span[1]) * rate); }

/// one thick bubble rising through the sap
const Gloop = struct {
  osc:dsp.Osc,
  base:f32,
  /// the settling's sample it starts on (never, for a gloop not used)
  start:u32,
  attack:u32,
  fall:f32,
  level:f32,
  amp:f32 = 1,
  age:u32 = 0,

  fn tick(g:*Gloop, at:u32) f32 {
    if (at < g.start or g.amp < SILENT) return 0;
    const rise = m.clamp01(m.f(g.age) / m.f(g.attack));
    if (g.age >= g.attack) g.amp *= g.fall;
    g.age +|= 1;
    g.osc.freq = g.base * (1 + GLOOP_RISE * (1 - g.amp));
    return g.osc.next() * rise * g.amp * g.level;
  }
};

/// one settling of the sap playing out
const Settle = struct {
  rate:f32,
  hum:dsp.Osc,
  waver:dsp.Osc,
  noise:dsp.Noise,
  throat:dsp.Biquad,
  soft:dsp.OnePole,
  gloops:[GLOOPS]Gloop,
  /// the hum's pitch before it sags, and the belly's lowering
  base:f32,
  low:f32,
  at:u32 = 0,
  len:u32,
  gain:f32,

  fn init(weight:f32, r:*rng.Rng, rate:f32) Settle {
    const low = 1 - SAP_HEAVY * weight;
    const len = samples(r, SETTLE_LEN, rate) + 1;
    var gloops:[GLOOPS]Gloop = undefined;
    const light = r.float() < LIGHT_CHANCE;
    gloopsOf(DEEP, true, gloops[0..DEEP.n[1]], .{.r = r, .rate = rate, .len = len, .low = low});
    gloopsOf(LIGHT, light, gloops[DEEP.n[1]..], .{.r = r, .rate = rate, .len = len, .low = low});
    const base = vary(r, GROAN_HZ) * low;
    return .{
      .rate = rate,
      .hum = .{.rate = rate, .shape = .saw, .freq = base},
      .waver = .{.rate = rate, .freq = vary(r, WAVER_HZ)},
      .noise = .init(r.next()),
      .throat = .init(.band, THROAT_HZ[0] * low, THROAT_Q, rate),
      .soft = .init(SAP_SOFT_HZ, rate),
      .gloops = gloops,
      .base = base,
      .low = low,
      .len = len,
      .gain = vary(r, SAP),
    };
  }

  const Within = struct { r:*rng.Rng, rate:f32, len:u32, low:f32 };

  /// `out` filled with gloops of `kind` (silent unless `used`)
  fn gloopsOf(kind:GloopKind, used:bool, out:[]Gloop, w:Within) void {
    const n = if (used) kind.n[0] + w.r.below(kind.n[1] - kind.n[0] + 1) else 0;
    for (out, 0..) |*g, i| g.* = .{
      .osc = .{.rate = w.rate},
      .base = w.r.range(kind.hz[0], kind.hz[1]) * w.low,
      .start = if (i < n) m.floorTo(u32, w.r.range(kind.at[0], kind.at[1]) * m.f(w.len)) else m.maxInt(u32),
      .attack = m.floorTo(u32, GLOOP_ATTACK * w.rate) + 1,
      .fall = @exp(-1 / (w.r.range(kind.fall[0], kind.fall[1]) * w.rate)),
      .level = kind.level,
    };
  }

  /// mixes the settling into `out`, faded with the view; false once ended
  fn render(st:*Settle, out:[]f32, fade:*dsp.Smooth) bool {
    for (out) |*s| {
      if (st.at >= st.len) return false;
      const u = m.f(st.at) / m.f(st.len);
      if (st.at % RETUNE == 0) st.throat.tune(.band, m.lerp(THROAT_HZ[0], THROAT_HZ[1], m.smooth(u)) * st.low, THROAT_Q, st.rate);
      st.hum.freq = st.base * (1 - GROAN_SAG * u) * (1 + WAVER * st.waver.next());
      // swells early, sinks away slowly
      const sw = @sin(m.pi * m.pow(f32, u, 0.6));
      const groan = st.throat.tick(st.hum.next() + BREATH * st.noise.next()) * GROAN * sw * sw;
      var gl:f32 = 0;
      for (&st.gloops) |*g| gl += g.tick(st.at);
      s.* += st.soft.low(groan + gl) * st.gain * fade.next();
      st.at += 1;
    }
    return st.at < st.len;
  }
};

// ---- the wind (always) ----

/// gusts: seconds between new strengths, and how fast the wind swells or
/// eases toward one (s); strengths lean soft by this power
const GUST_GAP = [2]f32{2.5, 7};
const GUST_GLIDE:f32 = 1.6;
const GUST_SOFT:f32 = 1.6;
/// the hush: noise below this (Hz), a calm and a gusting level
const HUSH_HZ:f32 = 380;
const HUSH = [2]f32{0.35, 1};
/// the whistle: narrow-banded noise (Hz range of its pitch, how narrow,
/// level), rising this share in a full gust and gliding to a new pitch
/// in this (s); heard only as the gust passes this strength
const WHISTLE_HZ = [2]f32{470, 720};
const WHISTLE_Q:f32 = 14;
const WHISTLE:f32 = 5.6;
const WHISTLE_RISE:f32 = 0.1;
const WHISTLE_GLIDE:f32 = 2.5;
const WHISTLE_FROM:f32 = 0.35;
/// a rounder whistle an octave under, at this share
const UNDER:f32 = 0.5;
const UNDER_LEVEL:f32 = 0.6;
/// what softens it all (Hz) and its loudness
const WIND_SOFT_HZ:f32 = 1700;
const WIND:f32 = 0.05;

/// the wind breathing over the garden, never ending
const Wind = struct {
  rate:f32,
  r:rng.Rng,
  noise:dsp.Noise,
  hush:dsp.OnePole,
  whistle:dsp.Biquad,
  under:dsp.Biquad,
  soft:dsp.OnePole,
  gust:dsp.Smooth,
  pitch:dsp.Smooth,
  /// samples until the next gust's strength, and to the next retune
  wait:u32 = 0,
  at:u32 = 0,
  /// its loudness (tests hush it to hear the rest alone)
  level:f32 = WIND,

  fn init(r:*rng.Rng, rate:f32) Wind {
    const hz = r.range(WHISTLE_HZ[0], WHISTLE_HZ[1]);
    return .{
      .rate = rate,
      .r = .init(r.next()),
      .noise = .init(r.next()),
      .hush = .init(HUSH_HZ, rate),
      .whistle = .init(.band, hz, WHISTLE_Q, rate),
      .under = .init(.band, hz * UNDER, WHISTLE_Q, rate),
      .soft = .init(WIND_SOFT_HZ, rate),
      .gust = .init(0.3, GUST_GLIDE, rate),
      .pitch = .init(hz, WHISTLE_GLIDE, rate),
    };
  }

  /// mixes the wind into `out`
  fn render(w:*Wind, out:[]f32) void {
    for (out) |*s| {
      if (w.wait == 0) {
        w.gust.target = m.pow(f32, w.r.float(), GUST_SOFT);
        w.pitch.target = w.r.range(WHISTLE_HZ[0], WHISTLE_HZ[1]);
        w.wait = samples(&w.r, GUST_GAP, w.rate);
      }
      w.wait -= 1;
      const g = w.gust.next();
      const hz = w.pitch.next() * (1 + WHISTLE_RISE * g);
      if (w.at % RETUNE == 0) {
        w.whistle.tune(.band, hz, WHISTLE_Q, w.rate);
        w.under.tune(.band, hz * UNDER, WHISTLE_Q, w.rate);
      }
      w.at +%= 1;
      const n = w.noise.next();
      const hush = w.hush.low(n) * m.lerp(HUSH[0], HUSH[1], g);
      const sing = m.clamp01((g - WHISTLE_FROM) / (1 - WHISTLE_FROM));
      const whistle = (w.whistle.tick(n) + UNDER_LEVEL * w.under.tick(n)) * WHISTLE * sing * sing;
      s.* += w.soft.low(hush + whistle) * w.level;
    }
  }
};

/// the source the device pulls from (`platform.audio.Output(Sounds)`)
pub const Sounds = struct {
  /// a paw landed; the view entered or left the wolf's eyes
  pub const Cmd = union(enum) { step:Footfall, eyes:bool };

  rate:f32,
  r:rng.Rng,
  steps:[VOICES]?Step = @splat(null),
  /// the voice taken when none is free (round the pool: the oldest)
  steal:usize = 0,
  eyes:bool = false,
  /// how much of the settling is heard (1 in the eyes)
  fade:dsp.Smooth,
  settle:?Settle = null,
  /// samples until the next settling, and since a paw last landed
  wait:u32 = 0,
  since_step:u32 = m.maxInt(u32),
  /// the belly at the last step
  weight:f32 = 0,
  wind:Wind,

  pub fn init(seed:u64, rate:f32) Sounds {
    var r:rng.Rng = .init(seed);
    const wind:Wind = .init(&r, rate);
    return .{.rate = rate, .r = r, .fade = .init(0, SAP_FADE, rate), .wind = wind};
  }

  pub fn apply(s:*Sounds, cmd:Cmd) void {
    switch (cmd) {
      .step => |f| {
        s.steps[s.free()] = .init(f, &s.r, s.rate);
        s.since_step = 0;
        s.weight = f.weight;
      },
      .eyes => |e| {
        if (e and !s.eyes) s.wait = samples(&s.r, GAP_FIRST, s.rate);
        s.eyes = e;
        s.fade.target = if (e) 1 else 0;
      },
    }
  }

  pub fn render(s:*Sounds, out:[]f32) void {
    for (&s.steps) |*v| if (v.*) |*st| {
      if (!st.render(out)) v.* = null;
    };
    s.sap(out);
    s.wind.render(out);
    for (out) |*x| x.* = dsp.softClip(x.*);
  }

  /// the sap settling now and then while in the eyes
  fn sap(s:*Sounds, out:[]f32) void {
    const n:u32 = @intCast(out.len);
    s.since_step +|= n;
    if (s.eyes) {
      s.wait -|= n;
      if (s.wait == 0 and s.settle == null) {
        s.settle = .init(s.weight, &s.r, s.rate);
        const still = m.f(s.since_step) > STILL_AFTER * s.rate;
        s.wait = s.settle.?.len + samples(&s.r, if (still) GAP_STILL else GAP_WALK, s.rate);
      }
    }
    if (s.settle) |*st| {
      if (!st.render(out, &s.fade) or (!s.eyes and s.fade.value < SILENT)) s.settle = null;
    }
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
  s.wind.level = 0;
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
  s.wind.level = 0;
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

test "the sap settles only in the eyes, softly, and fades out with the view" {
  var s:Sounds = .init(3, TEST_RATE);
  s.wind.level = 0;
  var buf:[480]f32 = undefined;
  // a minute out of the eyes: nothing
  for (0..6000) |_| {
    @memset(&buf, 0);
    s.render(&buf);
    for (buf) |x| try testing.expectEqual(@as(f32, 0), x);
  }
  s.apply(.{.eyes = true});
  var peak:f32 = 0;
  var settles:u32 = 0;
  var was = false;
  for (0..3000) |_| {
    @memset(&buf, 0);
    s.render(&buf);
    for (buf) |x| peak = @max(peak, @abs(x));
    if (s.settle != null and !was) settles += 1;
    was = s.settle != null;
  }
  // half a minute standing in the eyes settles a few times, softly
  try testing.expect(settles >= 2 and settles <= 6);
  try testing.expect(peak > 0.01 and peak < 0.3);
  s.apply(.{.eyes = false});
  for (0..400) |_| {
    @memset(&buf, 0);
    s.render(&buf);
  }
  try testing.expect(s.settle == null);
  for (buf) |x| try testing.expectEqual(@as(f32, 0), x);
}

test "now and then a settling has lighter gloops" {
  var r:rng.Rng = .init(21);
  var light:u32 = 0;
  for (0..200) |_| {
    const st:Settle = .init(0.5, &r, TEST_RATE);
    if (st.gloops[DEEP.n[1]].start != m.maxInt(u32)) light += 1;
  }
  try testing.expect(light > 20 and light < 90);
}

test "the wind is gentle, swells in gusts and whistles only in some" {
  var s:Sounds = .init(5, TEST_RATE);
  var buf:[4800]f32 = undefined;
  var peak:f32 = 0;
  var lo:f32 = 1;
  var hi:f32 = 0;
  var whistled:u32 = 0;
  // a minute, a tenth of a second at a time
  for (0..600) |_| {
    @memset(&buf, 0);
    s.render(&buf);
    var sum:f32 = 0;
    for (buf) |x| {
      peak = @max(peak, @abs(x));
      sum += x * x;
    }
    const rms = @sqrt(sum / m.f(buf.len));
    lo = @min(lo, rms);
    hi = @max(hi, rms);
    if (s.wind.gust.value > WHISTLE_FROM + 0.2) whistled += 1;
  }
  try testing.expect(peak > 0.005 and peak < 0.15);
  try testing.expect(lo > 0.0005 and hi > 2 * lo);
  try testing.expect(whistled > 10 and whistled < 400);
}
