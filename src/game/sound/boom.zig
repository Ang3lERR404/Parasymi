//! the arsthraxia's completion: a pop into a deep thud and a fracturing shimmer.
const lib = @import("../../lib.zig");
const engine = lib.engine;
const m = engine.core.math;
const dsp = engine.core.dsp;
const rng = engine.core.rng;
const SILENT = lib.sound.SILENT;
const vary = lib.sound.footstep.vary;

// the boom: a sharp pop into a deep, long thud
const BOOM_CORE = [2]f32{55, 30};
const BOOM_DROP:f32 = 0.2;
const BOOM_CORE_FALL:f32 = 1.8;
const BOOM_THUD:f32 = 2.0;
const BOOM_SUB_HZ:f32 = 28;
const BOOM_SUB_FALL:f32 = 2.5;
const BOOM_SUB:f32 = 0.6;
const BOOM_POP_HZ:f32 = 2500;
const BOOM_POP_FALL:f32 = 0.008;
const BOOM_POP:f32 = 0.8;
const BOOM_THUMP_HZ:f32 = 100;
const BOOM_THUMP_FALL:f32 = 0.15;
const BOOM_THUMP:f32 = 1.2;
const BOOM:f32 = 0.15;

// the shimmer: a cascade of inharmonic partials (a crystalline structure
// fracturing), each starting slightly after the last, some wobbling as
// they ring out
const BOOM_SHIMMER_N = 10;
const BOOM_SHIMMER_BASE:f32 = 660;
const BOOM_SHIMMER_INHARM:f32 = 0.004;
const BOOM_SHIMMER_STAGGER:f32 = 0.012;
const BOOM_SHIMMER_SOFT_HZ:f32 = 6000;
const BOOM_SHIMMER:f32 = 0.08;
const BOOM_SHIMMER_WOBBLE = [BOOM_SHIMMER_N]bool{
  false, true, false, true, false, true, false, true, false, true,
};
const BOOM_SHIMMER_WOBBLE_HZ = [2]f32{2.0, 3.5};
const BOOM_SHIMMER_WOBBLE_DEPTH:f32 = 0.25;

/// the boom and its shimmer
pub const Boom = struct {
  core:dsp.Osc,
  noise:dsp.Noise,
  thump:dsp.Biquad,
  pop:dsp.Biquad,
  sub:dsp.Sine,
  shimmer:[BOOM_SHIMMER_N]dsp.Sine,
  shimmer_amp:[BOOM_SHIMMER_N]f32 = @splat(1),
  shimmer_fall:[BOOM_SHIMMER_N]f32,
  shimmer_start:[BOOM_SHIMMER_N]u32,
  shimmer_wobble:[BOOM_SHIMMER_N]dsp.Osc,
  shimmer_wobble_on:[BOOM_SHIMMER_N]bool,
  shimmer_soft:dsp.OnePole,
  drop:f32 = 1,
  core_amp:f32 = 1,
  thump_amp:f32 = 1,
  pop_amp:f32 = 1,
  sub_amp:f32 = 1,
  drop_fall:f32,
  core_fall:f32,
  thump_fall:f32,
  pop_fall:f32,
  sub_fall:f32,
  at:u32 = 0,
  gain:f32,

  pub fn init(r:*rng.Rng, rate:f32) Boom {
    var sp:[BOOM_SHIMMER_N]dsp.Sine = undefined;
    var sf:[BOOM_SHIMMER_N]f32 = undefined;
    var ss:[BOOM_SHIMMER_N]u32 = undefined;
    var sw:[BOOM_SHIMMER_N]dsp.Osc = undefined;
    var swn:[BOOM_SHIMMER_N]bool = undefined;
    const base = vary(r, BOOM_SHIMMER_BASE);
    inline for (0..BOOM_SHIMMER_N) |k| {
      const n = m.f(k + 1);
      const hz = base * n * (1 + BOOM_SHIMMER_INHARM * n * n);
      sp[k] = .init(hz, rate);
      const fall_s = (2.2 - m.f(k) * 0.18) * r.range(0.8, 1.3);
      sf[k] = @exp(-1 / (fall_s * rate));
      ss[k] = m.floorTo(u32, m.f(k) * BOOM_SHIMMER_STAGGER * rate);
      swn[k] = BOOM_SHIMMER_WOBBLE[k];
      sw[k] = .{.rate = rate, .freq = r.range(BOOM_SHIMMER_WOBBLE_HZ[0], BOOM_SHIMMER_WOBBLE_HZ[1])};
    }
    return .{
      .core = .{.rate = rate, .shape = .saw, .freq = BOOM_CORE[0]},
      .noise = .init(r.next()),
      .thump = .init(.low, BOOM_THUMP_HZ, 0.707, rate),
      .pop = .init(.high, BOOM_POP_HZ, 0.707, rate),
      .sub = .init(BOOM_SUB_HZ, rate),
      .shimmer = sp,
      .shimmer_fall = sf,
      .shimmer_start = ss,
      .shimmer_wobble = sw,
      .shimmer_wobble_on = swn,
      .shimmer_soft = .init(BOOM_SHIMMER_SOFT_HZ, rate),
      .drop_fall = @exp(-1 / (BOOM_DROP * rate)),
      .core_fall = @exp(-1 / (BOOM_CORE_FALL * rate)),
      .thump_fall = @exp(-1 / (BOOM_THUMP_FALL * rate)),
      .pop_fall = @exp(-1 / (BOOM_POP_FALL * rate)),
      .sub_fall = @exp(-1 / (BOOM_SUB_FALL * rate)),
      .gain = vary(r, BOOM),
    };
  }

  pub fn render(b:*Boom, out:[]f32) bool {
    for (out) |*s| {
      b.core.freq = m.lerp(BOOM_CORE[1], BOOM_CORE[0], b.drop);
      b.drop *= b.drop_fall;
      b.core_amp *= b.core_fall;
      b.thump_amp *= b.thump_fall;
      b.pop_amp *= b.pop_fall;
      b.sub_amp *= b.sub_fall;
      const n = b.noise.next();
      const impact = b.core.next() * BOOM_THUD * b.core_amp + b.thump.tick(n) * BOOM_THUMP * b.thump_amp + b.pop.tick(n) * BOOM_POP * b.pop_amp + b.sub.next() * BOOM_SUB * b.sub_amp;
      var sh:f32 = 0;
      var alive = false;
      for (0..BOOM_SHIMMER_N) |k| {
        if (b.at < b.shimmer_start[k]) continue;
        if (b.shimmer_amp[k] < SILENT) continue;
        alive = true;
        b.shimmer_amp[k] *= b.shimmer_fall[k];
        var amp = b.shimmer_amp[k];
        if (b.shimmer_wobble_on[k]) {
          amp *= 1 - BOOM_SHIMMER_WOBBLE_DEPTH + BOOM_SHIMMER_WOBBLE_DEPTH * (1 + b.shimmer_wobble[k].next()) * 0.5;
        }
        sh += b.shimmer[k].next() * amp * (1 - m.f(k) * 0.07);
      }
      s.* += impact * b.gain + b.shimmer_soft.low(sh) * BOOM_SHIMMER;
      b.at +|= 1;
      if (!alive and b.core_amp < SILENT and b.sub_amp < SILENT) return false;
    }
    return true;
  }
};
