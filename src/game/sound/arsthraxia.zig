//! the arsthraxia's working: a spinning whorl under a swelling choir.
const lib = @import("../../lib.zig");
const std = lib.std;
const testing = std.testing;
const engine = lib.engine;
const m = engine.core.math;
const dsp = engine.core.dsp;
const rng = engine.core.rng;
const Footfall = lib.player.Footfall;
const RETUNE = lib.sound.sap.RETUNE;
const vary = lib.sound.footstep.vary;

// pub const Choir = struct{
//   const This = @This();
//   singers:comptime_int,
//   spread:f32 = 14,
//   vibratoHZ:[]f32 = &.{4.2,5.8},
//   vibrato:f32 = 12,
//   formants:[]f32
// };
// ---- the arsthraxia: whorl → choir crescendo → boom → shimmer ----

// the whorl: two detuned saws whose beat IS the vortex spin; a fast FM
// (depth increasing with progress) creates the "spinning" sensation; a
// band-pass focuses them and tightens as the energy concentrates
const WHORL_BASE = [2]f32{55, 55.5};
const WHORL_FM_HZ = [2]f32{6, 18};
const WHORL_FM_DEPTH = [2]f32{0.02, 0.12};
const WHORL_FILTER = [2]f32{200, 800};
const WHORL_Q = [2]f32{1.5, 6};
const WHORL:f32 = 1.8;
const RUMBLE_HZ:f32 = 35;
const RUMBLE:f32 = 0.4;
const EXPAND_AT:f32 = 0.72;
const RES_SOFT_HZ:f32 = 3500;
const RES:f32 = 0.10;
const RES_FED:f32 = 0.3;

// the choir: a vowel sung by a few voices, swelling with progress
const SINGERS = 4;
const CHOIR_BASE = [2]f32{165, 262};
const CHOIR_SPREAD:f32 = 14;
const VIBRATO_HZ = [2]f32{4.5, 6.0};
const VIBRATO_CENTS:f32 = 15;
const BODY_HZ:f32 = 350;
const BODY:f32 = 0.8;
const F1:f32 = 500;
const F2:f32 = 1200;
const F3:f32 = 2800;
const F1_Q:f32 = 6;
const F2_Q:f32 = 8;
const F3_Q:f32 = 10;
const F1_L:f32 = 1.0;
const F2_L:f32 = 0.5;
const F3_L:f32 = 0.2;
const CHOIR_FROM:f32 = 0.3;
const CHOIR_FULL:f32 = 0.85;
const CHOIR_ATTACK:f32 = 1.5;
const CHOIR:f32 = 0.18;


/// one singer: a detuned saw with its own vibrato
const Singer = struct {
  osc:dsp.Osc,
  vibrato:dsp.Osc,
  base:f32,

  fn init(i:usize, base:f32, r:*rng.Rng, rate:f32) Singer {
    const cents = m.f(@as(i32, @intCast(i)) - (SINGERS - 1) / 2) * CHOIR_SPREAD;
    const hz = base * m.pow(f32, 2, cents / 1200);
    return .{
      .osc = .{.rate = rate, .shape = .saw, .freq = hz},
      .vibrato = .{.rate = rate, .freq = r.range(VIBRATO_HZ[0], VIBRATO_HZ[1])},
      .base = hz,
    };
  }

  fn tick(sg:*Singer, u:f32) f32 {
    const rise = m.lerp(1, CHOIR_BASE[1] / CHOIR_BASE[0], m.smooth(u));
    sg.osc.freq = sg.base * rise * (1 + VIBRATO_CENTS / 100 * 0.01 * sg.vibrato.next());
    return sg.osc.next();
  }
};

/// the sustained voice: whorl + rumble + choir crescendo, driven by progress
pub const Research = struct {
  rate:f32,
  r:rng.Rng,
  oscA:dsp.Osc,
  oscB:dsp.Osc,
  fm:dsp.Osc,
  band:dsp.Biquad,
  rumble:dsp.Osc,
  singers:[SINGERS]Singer,
  body:dsp.OnePole,
  f1:dsp.Biquad,
  f2:dsp.Biquad,
  f3:dsp.Biquad,
  choir_fade:dsp.Smooth,
  soft:dsp.OnePole,
  at:u32 = 0,
  gain:f32,

  pub fn init(r:*rng.Rng, rate:f32) Research {
    var singers:[SINGERS]Singer = undefined;
    for (&singers, 0..) |*sg, i| sg.* = .init(i, CHOIR_BASE[0], r, rate);
    return .{
      .rate = rate,
      .r = .init(r.next()),
      .oscA = .{.rate = rate, .shape = .saw, .freq = WHORL_BASE[0]},
      .oscB = .{.rate = rate, .shape = .saw, .freq = WHORL_BASE[1]},
      .fm = .{.rate = rate, .shape = .sine, .freq = WHORL_FM_HZ[0]},
      .band = .init(.band, WHORL_FILTER[0], WHORL_Q[0], rate),
      .rumble = .{.rate = rate, .shape = .sine, .freq = RUMBLE_HZ},
      .singers = singers,
      .body = .init(BODY_HZ, rate),
      .f1 = .init(.band, F1, F1_Q, rate),
      .f2 = .init(.band, F2, F2_Q, rate),
      .f3 = .init(.band, F3, F3_Q, rate),
      .choir_fade = .init(0, CHOIR_ATTACK, rate),
      .soft = .init(RES_SOFT_HZ, rate),
      .gain = vary(r, RES),
    };
  }

  pub fn render(rs:*Research, out:[]f32, progress:f32, fed:f32) void {
    const u = m.smooth(m.clamp01(progress / EXPAND_AT));
    const fm_hz = m.lerp(WHORL_FM_HZ[0], WHORL_FM_HZ[1], u);
    const fm_depth = m.lerp(WHORL_FM_DEPTH[0], WHORL_FM_DEPTH[1], u);
    const filt_hz = m.lerp(WHORL_FILTER[0], WHORL_FILTER[1], u);
    const q = m.lerp(WHORL_Q[0], WHORL_Q[1], u);
    const ex = m.clamp01((progress - EXPAND_AT) / (1 - EXPAND_AT));
    const q_open = m.lerp(q, 1.0, ex);
    const choir_u = m.clamp01((progress - CHOIR_FROM) / (CHOIR_FULL - CHOIR_FROM));
    rs.choir_fade.target = m.smooth(choir_u);

    for (out) |*s| {
      if (rs.at % RETUNE == 0) rs.band.tune(.band, filt_hz, q_open, rs.rate);
      rs.at +%= 1;
      rs.fm.freq = fm_hz;

      const mod = rs.fm.next() * fm_depth;
      rs.oscA.freq = WHORL_BASE[0] * (1 + mod);
      rs.oscB.freq = WHORL_BASE[1] * (1 - mod);
      const raw = rs.oscA.next() + rs.oscB.next();
      const swirl = rs.band.tick(raw);
      const low = rs.rumble.next();

      var cr:f32 = 0;
      for (rs.singers[0..]) |*sg| cr += sg.tick(progress);
      const bod = rs.body.low(cr) * BODY;
      const formant = rs.f1.tick(cr) * F1_L + rs.f2.tick(cr) * F2_L + rs.f3.tick(cr) * F3_L;
      const voice = (bod + formant) * rs.choir_fade.next();

      const vol = u * u * (1 + 0.5 * ex);
      const y = swirl * WHORL + low * RUMBLE + voice * CHOIR;
      s.* += rs.soft.low(y) * rs.gain * vol * (1 + RES_FED * fed);
    }
  }
};
