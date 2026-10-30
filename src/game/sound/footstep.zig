//! a footstep: leaf litter rustled and crushed under a paw over a muffled pad.
const lib = @import("../../lib.zig");
const std = lib.std;
const testing = std.testing;
const engine = lib.engine;
const m = engine.core.math;
const dsp = engine.core.dsp;
const rng = engine.core.rng;
const Footfall = lib.player.Footfall;
const SILENT = lib.sound.SILENT;

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
pub fn vary(r:*rng.Rng, x:f32) f32 { return x * r.range(1 - VARY, 1 + VARY); }

/// one footstep playing out
pub const Step = struct {
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

  pub fn init(f:Footfall, r:*rng.Rng, rate:f32) Step {
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
  pub fn render(st:*Step, out:[]f32) bool {
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
