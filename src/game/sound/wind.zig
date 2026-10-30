//! the wind over the garden: a hush in slow gusts, whistling in the strong ones.
const lib = @import("../../lib.zig");
const engine = lib.engine;
const m = engine.core.math;
const dsp = engine.core.dsp;
const rng = engine.core.rng;
const RETUNE = lib.sound.sap.RETUNE;
const samples = lib.sound.sap.samples;

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
pub const WHISTLE_FROM:f32 = 0.35;
/// a rounder whistle an octave under, at this share
const UNDER:f32 = 0.5;
const UNDER_LEVEL:f32 = 0.6;
/// what softens it all (Hz) and its loudness
const WIND_SOFT_HZ:f32 = 1700;
const WIND:f32 = 0.05;

/// the wind breathing over the garden, never ending
pub const Wind = struct {
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

  pub fn init(r:*rng.Rng, rate:f32) Wind {
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
  pub fn render(w:*Wind, out:[]f32) void {
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
