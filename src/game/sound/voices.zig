//! the music's instruments: the piano plunk, the soft drum and the dark echo.
const lib = @import("../../lib.zig");
const engine = lib.engine;
const m = engine.core.math;
const dsp = engine.core.dsp;
const rng = engine.core.rng;
const DETUNE = lib.sound.score.DETUNE;
const DETUNE_LEVEL = lib.sound.score.DETUNE_LEVEL;
const DRUM = lib.sound.score.DRUM;
const DRUM_DROP = lib.sound.score.DRUM_DROP;
const DRUM_FALL = lib.sound.score.DRUM_FALL;
const DRUM_HZ = lib.sound.score.DRUM_HZ;
const DRUM_SOFT_HZ = lib.sound.score.DRUM_SOFT_HZ;
const DULL = lib.sound.score.DULL;
const ECHO_DOWN = lib.sound.score.ECHO_DOWN;
const ECHO_FEEDBACK = lib.sound.score.ECHO_FEEDBACK;
const ECHO_LEN = lib.sound.score.ECHO_LEN;
const ECHO_SOFT_HZ = lib.sound.score.ECHO_SOFT_HZ;
const ECHO_STEPS = lib.sound.score.ECHO_STEPS;
const HAMMER = lib.sound.score.HAMMER;
const HAMMER_AT = lib.sound.score.HAMMER_AT;
const HAMMER_FALL = lib.sound.score.HAMMER_FALL;
const HAMMER_HZ = lib.sound.score.HAMMER_HZ;
const HARMONICS = lib.sound.score.HARMONICS;
const HARMONIC_LEVEL = lib.sound.score.HARMONIC_LEVEL;
const PLUNK = lib.sound.score.PLUNK;
const PLUNK_ATTACK = lib.sound.score.PLUNK_ATTACK;
const PLUNK_DAMP = lib.sound.score.PLUNK_DAMP;
const PLUNK_FALL = lib.sound.score.PLUNK_FALL;
const PLUNK_FALL_SPAN = lib.sound.score.PLUNK_FALL_SPAN;
const PLUNK_REF_HZ = lib.sound.score.PLUNK_REF_HZ;
const PLUNK_SOFT_HZ = lib.sound.score.PLUNK_SOFT_HZ;
const SILENT = lib.sound.SILENT;
const SKIN = lib.sound.score.SKIN;
const SKIN_FALL = lib.sound.score.SKIN_FALL;
const SKIN_HZ = lib.sound.score.SKIN_HZ;
const STEP_S = lib.sound.score.STEP_S;
const STRETCH = lib.sound.score.STRETCH;
const vary = lib.sound.footstep.vary;

/// one piano note: a plunk of a felt-hammered string
pub const Plunk = struct {
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

  pub fn init(note:u8, vel:f32, r:*rng.Rng, rate:f32) Plunk {
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
  pub fn render(p:*Plunk, out:[]f32) bool {
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
pub const Drum = struct {
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

  pub fn init(vel:f32, r:*rng.Rng, rate:f32) Drum {
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

  pub fn render(d:*Drum, out:[]f32) bool {
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
pub const Echo = struct {
  buf:[ECHO_LEN]f32 = @splat(0),
  at:usize = 0,
  /// samples summed toward the next slot
  sum:f32 = 0,
  sub:u32 = 0,
  /// slots behind
  delay:usize,
  soft:dsp.OnePole,

  pub fn init(rate:f32) Echo {
    const d = m.floorTo(usize, ECHO_STEPS * STEP_S * rate / ECHO_DOWN);
    return .{.delay = m.clamp(d, 2, ECHO_LEN - 2), .soft = .init(ECHO_SOFT_HZ, rate)};
  }

  /// `x` in, what it heard `delay` slots ago out (between two slots)
  pub fn tick(e:*Echo, x:f32) f32 {
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
