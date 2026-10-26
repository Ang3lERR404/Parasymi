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
//! - a mote of starlight near the wolf twinkles now and then: a few tiny
//!   glassy pings in quick succession (high bell partials, a little
//!   out of tune with each other), dying away in a soft shimmer; the
//!   nearer the mote, the louder.
//! - by day, music: light piano plunks (felt-hammered strings, a little
//!   stretched and beating) on a steady eighth-note pulse, a wandering
//!   pentatonic line over a soft left hand, phrased as a motif and its
//!   variation over a slow chord progression, a soft low drum on some bars,
//!   all with a dark echo three steps behind; it rises with the morning and
//!   fades out at dusk.
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

// ---- the starlight twinkling (near a mote) ----

/// pings in one twinkle (fewest, most), seconds between them, and the
/// first ping's pitch (Hz); each next steps up or down by one of `STEPS`
const PINGS = [2]u32{2, 4};
const PING_GAP = [2]f32{0.05, 0.13};
const PING_HZ = [2]f32{2100, 3400};
const STEPS = [_]f32{1.122, 1.189, 1.335, 0.891, 0.841};
/// a ping's glassy partials (shares of its pitch, a little stretched so it
/// shimmers), their levels, how long each rings (s, ~63%) and the attack (s)
const PARTIALS = [_]f32{1, 2.32, 4.13};
const PARTIAL_LEVEL = [_]f32{1, 0.4, 0.15};
const PARTIAL_FALL = [_]f32{0.32, 0.14, 0.06};
const PING_ATTACK:f32 = 0.003;
/// a slow shimmer through it all (Hz, share)
const SHIMMER_HZ:f32 = 7;
const SHIMMER:f32 = 0.25;
/// what softens it (Hz), and its loudness for a far and a touching mote
const TWINKLE_SOFT_HZ:f32 = 7000;
const TWINKLE = [2]f32{0.006, 0.03};
/// twinkles that may sound at once
const TWINKLES = 2;
/// a ping this far faded is gone (it is already far quieter than a step)
const PING_SILENT:f32 = 1e-3;

/// one ping: a tiny bell
const Ping = struct {
  osc:[PARTIALS.len]dsp.Osc,
  amp:[PARTIALS.len]f32 = @splat(1),
  fall:[PARTIALS.len]f32,
  start:u32,
  attack:u32,
  level:f32,
  age:u32 = 0,

  fn tick(p:*Ping, at:u32) f32 {
    if (at < p.start) return 0;
    const rise = m.clamp01(m.f(p.age) / m.f(p.attack));
    p.age +|= 1;
    var y:f32 = 0;
    inline for (0..PARTIALS.len) |k| {
      if (p.age > p.attack) p.amp[k] *= p.fall[k];
      y += p.osc[k].next() * p.amp[k] * PARTIAL_LEVEL[k];
    }
    return y * rise * p.level;
  }

  fn done(p:*const Ping) bool { return p.age > p.attack and p.amp[0] < PING_SILENT; }
};

/// one twinkle playing out
const Twinkle = struct {
  pings:[PINGS[1]]Ping,
  n:u32,
  shimmer:dsp.Osc,
  soft:dsp.OnePole,
  at:u32 = 0,
  gain:f32,

  fn init(near:f32, r:*rng.Rng, rate:f32) Twinkle {
    const n = PINGS[0] + r.below(PINGS[1] - PINGS[0] + 1);
    var pings:[PINGS[1]]Ping = undefined;
    var hz = r.range(PING_HZ[0], PING_HZ[1]);
    var start:u32 = 0;
    for (&pings, 0..) |*p, i| {
      var osc:[PARTIALS.len]dsp.Osc = undefined;
      var fall:[PARTIALS.len]f32 = undefined;
      inline for (0..PARTIALS.len) |k| {
        osc[k] = .{.rate = rate, .freq = hz * PARTIALS[k], .phase = r.float()};
        fall[k] = @exp(-1 / (vary(r, PARTIAL_FALL[k]) * rate));
      }
      p.* = .{
        .osc = osc,
        .fall = fall,
        .start = start,
        .attack = m.floorTo(u32, PING_ATTACK * rate) + 1,
        // each later ping a little softer
        .level = if (i < n) vary(r, 1) / m.f(i + 1) else 0,
      };
      start += samples(r, PING_GAP, rate);
      hz *= STEPS[r.below(STEPS.len)];
    }
    return .{
      .pings = pings,
      .n = n,
      .shimmer = .{.rate = rate, .freq = vary(r, SHIMMER_HZ)},
      .soft = .init(TWINKLE_SOFT_HZ, rate),
      .gain = m.lerp(TWINKLE[0], TWINKLE[1], near),
    };
  }

  /// mixes the twinkle into `out`; false once it has ended
  fn render(t:*Twinkle, out:[]f32) bool {
    for (out) |*s| {
      var y:f32 = 0;
      for (t.pings[0..t.n]) |*p| y += p.tick(t.at);
      t.at +|= 1;
      s.* += t.soft.low(y) * (1 - SHIMMER + SHIMMER * t.shimmer.next()) * t.gain;
    }
    for (t.pings[0..t.n]) |p| if (!p.done()) return true;
    return false;
  }
};

// ---- the day's music ----

/// the pulse: eighth notes at this tempo (beats a minute), eight to a bar,
/// four bars to a phrase
const TEMPO:f32 = 84;
const STEP_S:f32 = 60.0 / TEMPO / 2.0;
const BAR = 8;
const BARS = 4;
const PHRASE = BAR * BARS;
/// a motif is two bars; the phrase plays it, then a variation of it
const MOTIF = 2 * BAR;
/// the key (MIDI note of D4) and its pentatonic scale (semitones)
const KEY:u8 = 62;
const PENTA = [_]u8{0, 2, 4, 7, 9};
/// the melody's range, in steps of the scale above the key (B4..E6)
const MEL_LO:u8 = 4;
const MEL_HI:u8 = 11;
/// how likely a note is on a bar's first step, on a beat, off the beat
const NOTE_CHANCE = [3]f32{0.9, 0.6, 0.3};
/// how loud a note is there (before it strays by `VARY`)
const NOTE_VEL = [3]f32{1, 0.8, 0.62};
/// a new motif instead of a variation of the last, a new progression
/// instead of the last, and each step's chance to change in a variation
const NEW_MOTIF:f32 = 0.4;
const NEW_CHORDS:f32 = 0.4;
const MUTATE:f32 = 0.25;
/// the phrase breathes out: its last two steps rest this often
const BREATHE:f32 = 0.7;

/// a chord: its root (semitones above the key) and whether it is minor
const Chord = struct { root:u8, minor:bool = false };
/// I vi IV V, IV I ii V, I V vi IV
const PROGRESSIONS = [_][BARS]Chord{
  .{.{.root = 0}, .{.root = 9, .minor = true}, .{.root = 5}, .{.root = 7}},
  .{.{.root = 5}, .{.root = 0}, .{.root = 2, .minor = true}, .{.root = 7}},
  .{.{.root = 0}, .{.root = 7}, .{.root = 9, .minor = true}, .{.root = 5}},
};
/// the left hand: each bar's root low (D3, roots above this many semitones
/// an octave lower), its fifth on the third beat this often, and how loud
const LOW:u8 = 50;
const LOW_FOLD:u8 = 4;
const FIFTH_CHANCE:f32 = 0.6;
const LOW_VEL:f32 = 0.55;

/// the plunk: a struck string's partials (harmonics a little stretched,
/// as a piano's are), their levels, and a second string a hair sharp
/// beating against the first
const HARMONICS = 5;
const STRETCH:f32 = 0.0004;
const HARMONIC_LEVEL = [HARMONICS]f32{1, 0.5, 0.28, 0.14, 0.07};
const DETUNE:f32 = 1.0007;
const DETUNE_LEVEL:f32 = 0.7;
/// how long it rings (s, ~63%) at this pitch (Hz), shorter for higher
/// notes and within these bounds; each higher partial dies this much faster
const PLUNK_FALL:f32 = 0.55;
const PLUNK_REF_HZ:f32 = 400;
const PLUNK_FALL_SPAN = [2]f32{0.22, 1.3};
const PLUNK_DAMP:f32 = 0.9;
/// a softer note is this much duller (its partials fall by this power)
const DULL:f32 = 0.7;
/// the felt hammer: a tick of noise this many times the pitch (Hz at most),
/// falling in this (s), at this level; the attack (s)
const HAMMER_AT:f32 = 5;
const HAMMER_HZ:f32 = 4500;
const HAMMER_FALL:f32 = 0.004;
const HAMMER:f32 = 0.3;
const PLUNK_ATTACK:f32 = 0.0015;
/// what softens it (Hz), its loudness, and how many may ring at once
const PLUNK_SOFT_HZ:f32 = 3600;
const PLUNK:f32 = 0.032;
const PLUNKS = 10;

/// the drum: a soft low tom on a bar's first step this often, on its third
/// beat this often (lighter); its pitch (Hz) dropping from the first to
/// the second in this (s), its fall (s), the skin's noise (Hz, fall, level)
const DRUM_CHANCE:f32 = 0.5;
const TAP_CHANCE:f32 = 0.12;
const TAP_VEL:f32 = 0.5;
const DRUM_HZ = [2]f32{110, 62};
const DRUM_DROP:f32 = 0.05;
const DRUM_FALL:f32 = 0.22;
const SKIN_HZ:f32 = 220;
const SKIN_FALL:f32 = 0.03;
const SKIN:f32 = 0.5;
/// what muffles it (Hz), its loudness, and how many may sound at once
const DRUM_SOFT_HZ:f32 = 700;
const DRUM:f32 = 0.06;
const DRUMS = 2;

/// a soft echo three steps behind, kept at a quarter of the rate (it is
/// dark anyway), feeding back this much, darkened (Hz) and at this level
const ECHO_STEPS:f32 = 3;
const ECHO_DOWN = 4;
const ECHO_LEN = m.floorTo(usize, ECHO_STEPS * STEP_S * m.f(RATE) / ECHO_DOWN) + 4;
const ECHO_FEEDBACK:f32 = 0.3;
const ECHO_SOFT_HZ:f32 = 1800;
const ECHO:f32 = 0.35;
/// how fast the music follows the daylight (s); it plays only past this
const MUSIC_GLIDE:f32 = 3;
const MUSIC_FROM:f32 = 0.05;
/// the music's loudness (tests hush it to hear the rest alone)
const MUSIC:f32 = 1;

/// a MIDI note of the scale, `i` steps above the key
fn scaleNote(i:u8) u8 { return KEY + 12 * (i / PENTA.len) + PENTA[i % PENTA.len]; }

/// the note nearest `note` (within a whole tone) that is in `c`
fn chordTone(note:u8, c:Chord) u8 {
  const third:u8 = if (c.minor) 3 else 4;
  var best = note;
  var dist:u8 = 3;
  for ([_]u8{0, 1, 2}) |d| for ([_]u8{note -| d, note + d}) |n| {
    const in = (n + 12 - KEY % 12 + 12 - c.root) % 12;
    if ((in == 0 or in == third or in == 7) and d < dist) {
      best = n;
      dist = d;
    }
  };
  return best;
}

/// one piano note: a plunk of a felt-hammered string
const Plunk = struct {
  parts:[HARMONICS + 1]dsp.Sine,
  amp:[HARMONICS + 1]f32 = @splat(1),
  fall:[HARMONICS + 1]f32,
  level:[HARMONICS + 1]f32,
  noise:dsp.Noise,
  hammer:dsp.Biquad,
  knock:f32 = 1,
  knock_fall:f32,
  soft:dsp.OnePole,
  at:u32 = 0,
  attack:u32,
  gain:f32,

  fn init(note:u8, vel:f32, r:*rng.Rng, rate:f32) Plunk {
    const hz = dsp.noteToHz(m.f(note));
    const ring = m.clamp(PLUNK_FALL * @sqrt(PLUNK_REF_HZ / hz), PLUNK_FALL_SPAN[0], PLUNK_FALL_SPAN[1]);
    var p:Plunk = .{
      .parts = undefined,
      .fall = undefined,
      .level = undefined,
      .noise = .init(r.next()),
      .hammer = .init(.band, @min(hz * HAMMER_AT, HAMMER_HZ), 1.2, rate),
      .knock_fall = @exp(-1 / (HAMMER_FALL * rate)),
      .soft = .init(PLUNK_SOFT_HZ, rate),
      .attack = m.floorTo(u32, PLUNK_ATTACK * rate) + 1,
      .gain = vel * PLUNK,
    };
    for (0..HARMONICS) |k| {
      const n = m.f(k + 1);
      const f = hz * n * @sqrt(1 + STRETCH * n * n);
      p.parts[k] = .init(f, rate);
      p.fall[k] = @exp(-1 / (ring / (1 + PLUNK_DAMP * m.f(k)) * rate));
      // above Nyquist a partial is left out, not folded back
      const heard:f32 = if (f < 0.45 * rate) 1 else 0;
      p.level[k] = HARMONIC_LEVEL[k] * m.pow(f32, vel, DULL * m.f(k)) * heard;
    }
    p.parts[HARMONICS] = .init(hz * DETUNE, rate);
    p.fall[HARMONICS] = p.fall[0];
    p.level[HARMONICS] = DETUNE_LEVEL;
    return p;
  }

  /// mixes the note into `out`; false once it has ended
  fn render(p:*Plunk, out:[]f32) bool {
    for (out) |*s| {
      const rise = m.clamp01(m.f(p.at) / m.f(p.attack));
      p.at +|= 1;
      var y:f32 = 0;
      inline for (0..HARMONICS + 1) |k| {
        p.amp[k] *= p.fall[k];
        y += p.parts[k].next() * p.amp[k] * p.level[k];
      }
      p.knock *= p.knock_fall;
      y += p.hammer.tick(p.noise.next()) * HAMMER * p.knock;
      s.* += p.soft.low(y * rise) * p.gain;
    }
    return p.amp[0] > SILENT;
  }
};

/// one soft tom
const Drum = struct {
  osc:dsp.Osc,
  noise:dsp.Noise,
  skin:dsp.Biquad,
  soft:dsp.OnePole,
  /// the pitch's drop still to fall, the body's and the skin's loudness
  drop:f32 = 1,
  body:f32 = 1,
  hit:f32 = 1,
  drop_fall:f32,
  body_fall:f32,
  hit_fall:f32,
  gain:f32,

  fn init(vel:f32, r:*rng.Rng, rate:f32) Drum {
    return .{
      .osc = .{.rate = rate},
      .noise = .init(r.next()),
      .skin = .init(.band, vary(r, SKIN_HZ), 1, rate),
      .soft = .init(DRUM_SOFT_HZ, rate),
      .drop_fall = @exp(-1 / (DRUM_DROP * rate)),
      .body_fall = @exp(-1 / (vary(r, DRUM_FALL) * rate)),
      .hit_fall = @exp(-1 / (SKIN_FALL * rate)),
      .gain = vary(r, vel) * DRUM,
    };
  }

  fn render(d:*Drum, out:[]f32) bool {
    for (out) |*s| {
      d.osc.freq = m.lerp(DRUM_HZ[1], DRUM_HZ[0], d.drop);
      d.drop *= d.drop_fall;
      d.body *= d.body_fall;
      d.hit *= d.hit_fall;
      const y = d.osc.next() * d.body + d.skin.tick(d.noise.next()) * SKIN * d.hit;
      s.* += d.soft.low(y) * d.gain;
    }
    return d.body > SILENT;
  }
};

/// an echo kept at a quarter of the rate in a ring of its own
const Echo = struct {
  buf:[ECHO_LEN]f32 = @splat(0),
  at:usize = 0,
  /// samples summed toward the next slot
  sum:f32 = 0,
  sub:u32 = 0,
  /// slots behind
  delay:usize,
  soft:dsp.OnePole,

  fn init(rate:f32) Echo {
    const d = m.floorTo(usize, ECHO_STEPS * STEP_S * rate / ECHO_DOWN);
    return .{.delay = m.clamp(d, 2, ECHO_LEN - 2), .soft = .init(ECHO_SOFT_HZ, rate)};
  }

  /// `x` in, what it heard `delay` slots ago out (between two slots)
  fn tick(e:*Echo, x:f32) f32 {
    const back = e.at + ECHO_LEN - e.delay;
    const y = m.lerp(e.buf[back % ECHO_LEN], e.buf[(back + 1) % ECHO_LEN], m.f(e.sub) / ECHO_DOWN);
    e.sum += x;
    e.sub += 1;
    if (e.sub == ECHO_DOWN) {
      e.buf[e.at] = e.sum / ECHO_DOWN + ECHO_FEEDBACK * y;
      e.at = (e.at + 1) % ECHO_LEN;
      e.sum = 0;
      e.sub = 0;
    }
    return e.soft.low(y);
  }
};

/// samples the music renders at a time between its steps
const CHUNK = 256;

/// the day's music: light piano plunks over a slow steady pulse, a soft
/// drum now and then, fading in with the morning and out at dusk
const Music = struct {
  rate:f32,
  r:rng.Rng,
  plunks:[PLUNKS]?Plunk = @splat(null),
  drums:[DRUMS]?Drum = @splat(null),
  next_plunk:usize = 0,
  next_drum:usize = 0,
  echo:Echo,
  fade:dsp.Smooth,
  /// the step about to play, and samples until it does
  step:u32 = 0,
  left:u32 = 0,
  step_len:u32,
  chords:[BARS]Chord = PROGRESSIONS[0],
  /// scale steps (null rests) of the motif and of its variation
  motif:[MOTIF]?u8 = @splat(null),
  varied:[MOTIF]?u8 = @splat(null),
  fresh:bool = true,
  /// silent through the night: nothing rings, the next day starts a phrase
  resting:bool = true,
  /// notes and drums struck (tests count them)
  struck:u32 = 0,
  drummed:u32 = 0,
  level:f32 = MUSIC,

  fn init(r:*rng.Rng, rate:f32) Music {
    return .{
      .rate = rate,
      .r = .init(r.next()),
      .echo = .init(rate),
      .fade = .init(0, MUSIC_GLIDE, rate),
      .step_len = m.floorTo(u32, STEP_S * rate),
    };
  }

  fn daylight(mu:*Music, d:f32) void { mu.fade.target = if (d > MUSIC_FROM) m.clamp01(d) else 0; }

  fn render(mu:*Music, out:[]f32) void {
    if (mu.fade.target == 0 and mu.fade.value < SILENT) {
      if (!mu.resting) mu.rest();
      return;
    }
    mu.resting = false;
    var off:usize = 0;
    while (off < out.len) {
      const n = @min(CHUNK, out.len - off);
      var buf:[CHUNK]f32 = @splat(0);
      mu.chunk(buf[0..n]);
      for (out[off..][0..n], buf[0..n]) |*o, x| o.* += x;
      off += n;
    }
  }

  fn rest(mu:*Music) void {
    mu.plunks = @splat(null);
    mu.drums = @splat(null);
    mu.echo = .init(mu.rate);
    mu.step = 0;
    mu.left = 0;
    mu.resting = true;
  }

  /// plays `buf` (zeroed) out, striking each step as it comes
  fn chunk(mu:*Music, buf:[]f32) void {
    var i:usize = 0;
    while (i < buf.len) {
      if (mu.left == 0) {
        mu.strikeStep();
        mu.left = mu.step_len;
      }
      const n:u32 = @intCast(@min(mu.left, buf.len - i));
      const part = buf[i..][0..n];
      for (&mu.plunks) |*v| if (v.*) |*p| {
        if (!p.render(part)) v.* = null;
      };
      for (&mu.drums) |*v| if (v.*) |*d| {
        if (!d.render(part)) v.* = null;
      };
      mu.left -= n;
      i += n;
    }
    for (buf) |*s| s.* = (s.* + ECHO * mu.echo.tick(s.*)) * mu.level * mu.fade.next();
  }

  fn strikeStep(mu:*Music) void {
    if (mu.step == 0) mu.phrase();
    const bar = mu.step / BAR;
    const s = mu.step % BAR;
    const c = mu.chords[bar];
    const at:usize = if (s == 0) 0 else if (s % 2 == 0) 1 else 2;
    const line = if (mu.step < MOTIF) mu.motif else mu.varied;
    if (line[mu.step % MOTIF]) |i| {
      const n = scaleNote(i);
      mu.plunk(if (s == 0) chordTone(n, c) else n, vary(&mu.r, NOTE_VEL[at]));
    }
    const low = LOW + c.root - (if (c.root > LOW_FOLD) @as(u8, 12) else 0);
    if (s == 0) mu.plunk(low, vary(&mu.r, LOW_VEL));
    if (s == BAR / 2 and mu.r.float() < FIFTH_CHANCE) mu.plunk(low + 7, vary(&mu.r, LOW_VEL * 0.8));
    if (s == 0 and mu.r.float() < DRUM_CHANCE) mu.drum(1);
    if (s == BAR / 2 and mu.r.float() < TAP_CHANCE) mu.drum(TAP_VEL);
    mu.step = (mu.step + 1) % PHRASE;
  }

  /// a new phrase: maybe new chords, a new motif or a variation of the last
  fn phrase(mu:*Music) void {
    if (mu.r.float() < NEW_CHORDS) mu.chords = PROGRESSIONS[mu.r.below(PROGRESSIONS.len)];
    if (mu.fresh or mu.r.float() < NEW_MOTIF) {
      mu.motif = mu.newMotif();
      mu.fresh = false;
    } else mu.motif = mu.alter(mu.varied);
    mu.varied = mu.alter(mu.motif);
    if (mu.r.float() < BREATHE) {
      mu.varied[MOTIF - 2] = null;
      mu.varied[MOTIF - 1] = null;
    }
  }

  /// a wandering line: small steps up and down the scale, mostly on beats
  fn newMotif(mu:*Music) [MOTIF]?u8 {
    var out:[MOTIF]?u8 = undefined;
    var i:u8 = @intCast(MEL_LO + 2 + mu.r.below(MEL_HI - MEL_LO - 3));
    for (&out, 0..) |*o, k| {
      const s = k % BAR;
      const at:usize = if (s == 0) 0 else if (s % 2 == 0) 1 else 2;
      if (mu.r.float() >= NOTE_CHANCE[at]) {
        o.* = null;
        continue;
      }
      i = mu.wander(i, 2);
      o.* = i;
    }
    return out;
  }

  /// `line` with some of its steps changed: a note moved a step, dropped,
  /// or a rest filled
  fn alter(mu:*Music, line:[MOTIF]?u8) [MOTIF]?u8 {
    var out = line;
    var last:u8 = MEL_LO + (MEL_HI - MEL_LO) / 2;
    for (&out) |*o| {
      if (mu.r.float() < MUTATE) o.* = if (o.*) |i| (if (mu.r.float() < 0.3) null else mu.wander(i, 1)) else mu.wander(last, 1);
      if (o.*) |i| last = i;
    }
    return out;
  }

  /// `i` moved up to `by` steps either way, kept in the melody's range
  fn wander(mu:*Music, i:u8, by:u8) u8 {
    const d:i32 = @as(i32, @intCast(mu.r.below(2 * by + 1))) - by;
    return @intCast(m.clamp(@as(i32, i) + d, MEL_LO, MEL_HI));
  }

  fn plunk(mu:*Music, note:u8, vel:f32) void {
    mu.plunks[mu.freePlunk()] = .init(note, vel, &mu.r, mu.rate);
    mu.struck += 1;
  }

  fn drum(mu:*Music, vel:f32) void {
    mu.drums[mu.next_drum] = .init(vel, &mu.r, mu.rate);
    mu.next_drum = (mu.next_drum + 1) % DRUMS;
    mu.drummed += 1;
  }

  fn freePlunk(mu:*Music) usize {
    for (mu.plunks, 0..) |v, i| if (v == null) return i;
    defer mu.next_plunk = (mu.next_plunk + 1) % PLUNKS;
    return mu.next_plunk;
  }
};

/// the source the device pulls from (`platform.audio.Output(Sounds)`)
pub const Sounds = struct {
  /// a paw landed; the view entered or left the wolf's eyes; a mote near
  /// the wolf twinkled; the daylight changed (0 night .. 1 day)
  pub const Cmd = union(enum) { step:Footfall, eyes:bool, twinkle:lib.sky.Twinkle, daylight:f32 };

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
  /// a new twinkle takes the oldest's place when both are sounding
  twinkles:[TWINKLES]?Twinkle = @splat(null),
  next_twinkle:usize = 0,
  music:Music,

  pub fn init(seed:u64, rate:f32) Sounds {
    var r:rng.Rng = .init(seed);
    const wind:Wind = .init(&r, rate);
    const music:Music = .init(&r, rate);
    return .{.rate = rate, .r = r, .fade = .init(0, SAP_FADE, rate), .wind = wind, .music = music};
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
      .twinkle => |t| {
        s.twinkles[s.next_twinkle] = .init(m.clamp01(t.near), &s.r, s.rate);
        s.next_twinkle = (s.next_twinkle + 1) % TWINKLES;
      },
      .daylight => |d| s.music.daylight(d),
    }
  }

  pub fn render(s:*Sounds, out:[]f32) void {
    for (&s.steps) |*v| if (v.*) |*st| {
      if (!st.render(out)) v.* = null;
    };
    for (&s.twinkles) |*v| if (v.*) |*t| {
      if (!t.render(out)) v.* = null;
    };
    s.sap(out);
    s.wind.render(out);
    s.music.render(out);
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

test "a twinkle is a few soft high pings, louder the nearer, and ends" {
  var peaks:[2]f32 = undefined;
  for ([_]f32{0.1, 1}, &peaks) |near, *peak| {
    var s:Sounds = .init(11, TEST_RATE);
    s.wind.level = 0;
    s.apply(.{.twinkle = .{.near = near}});
    try testing.expect(s.twinkles[0].?.n >= PINGS[0] and s.twinkles[0].?.n <= PINGS[1]);
    var buf:[480]f32 = undefined;
    peak.* = 0;
    var n:u32 = 0;
    while (s.twinkles[0] != null and n < 4 * 48000) : (n += buf.len) {
      @memset(&buf, 0);
      s.render(&buf);
      for (buf) |x| peak.* = @max(peak.*, @abs(x));
    }
    try testing.expect(s.twinkles[0] == null);
    const len = m.f(n) / TEST_RATE;
    try testing.expect(len > 0.5 and len < 3.5);
  }
  try testing.expect(peaks[0] > 0.002 and peaks[1] < 0.1 and peaks[1] > 2 * peaks[0]);
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

test "the music is silent at night and plays softly by day, on a steady pulse" {
  var s:Sounds = .init(17, TEST_RATE);
  s.wind.level = 0;
  var buf:[480]f32 = undefined;
  // ten seconds of night: nothing
  for (0..1000) |_| {
    @memset(&buf, 0);
    s.render(&buf);
    for (buf) |x| try testing.expectEqual(@as(f32, 0), x);
  }
  try testing.expectEqual(@as(u32, 0), s.music.struck);
  s.apply(.{.daylight = 1});
  var peak:f32 = 0;
  // two minutes of day
  const secs = 120;
  for (0..secs * 100) |_| {
    @memset(&buf, 0);
    s.render(&buf);
    for (buf) |x| peak = @max(peak, @abs(x));
  }
  try testing.expect(peak > 0.02 and peak < 0.35);
  // steps of the pulse that passed: notes on many of them, a drum on some bars
  const steps = m.f(secs) / STEP_S;
  try testing.expect(m.f(s.music.struck) > 0.5 * steps and m.f(s.music.struck) < 1.5 * steps);
  const bars = steps / BAR;
  try testing.expect(m.f(s.music.drummed) > 0.25 * bars and m.f(s.music.drummed) < 0.8 * bars);
  // dusk: it fades out and rests
  s.apply(.{.daylight = 0});
  for (0..3000) |_| {
    @memset(&buf, 0);
    s.render(&buf);
  }
  try testing.expect(s.music.resting);
  for (buf) |x| try testing.expectEqual(@as(f32, 0), x);
}

test "a phrase's second half varies its first, and melody stays in range" {
  var r:rng.Rng = .init(4);
  var mu:Music = .init(&r, TEST_RATE);
  for (0..50) |_| {
    mu.phrase();
    var same:u32 = 0;
    for (mu.motif, mu.varied) |a, b| {
      if (a) |i| try testing.expect(i >= MEL_LO and i <= MEL_HI);
      if (std.meta.eql(a, b)) same += 1;
    }
    try testing.expect(same >= MOTIF / 2);
  }
  // a bar's first note sits in its chord
  try testing.expectEqual(@as(u8, 62), chordTone(63, .{.root = 0}));
  try testing.expectEqual(@as(u8, 71), chordTone(72, .{.root = 9, .minor = true}));
}
