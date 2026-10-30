//! the sap settling, heard from inside the wolf (first person): a groan with gloops.
const lib = @import("../../lib.zig");
const engine = lib.engine;
const m = engine.core.math;
const dsp = engine.core.dsp;
const rng = engine.core.rng;
const SILENT = lib.sound.SILENT;
const vary = lib.sound.footstep.vary;

// ---- the sap settling (first person) ----

/// how long a settling lasts (s)
const SETTLE_LEN = [2]f32{2.4, 3.8};
/// seconds between settlings while the wolf stands and while it walks; the
/// first comes this soon after the view enters the eyes
pub const GAP_STILL = [2]f32{3.5, 8};
pub const GAP_WALK = [2]f32{9, 18};
pub const GAP_FIRST = [2]f32{1.2, 3};
/// the wolf stands once no step has landed for this long (s)
pub const STILL_AFTER:f32 = 1.2;
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
pub const RETUNE = 32;
/// a kind of gloop: how many (fewest, most), when (shares of the
/// settling), its pitch (Hz), its fall (s) and level
const GloopKind = struct { n:[2]u32, at:[2]f32, hz:[2]f32, fall:[2]f32, level:f32 };
/// the deep ones every settling has, and the lighter, smaller ones that
/// come with only this share of settlings
pub const DEEP:GloopKind = .{.n = .{2, 5}, .at = .{0.1, 0.65}, .hz = .{110, 210}, .fall = .{0.06, 0.12}, .level = 0.6};
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
pub const SAP_FADE:f32 = 0.35;

/// seconds in `span` as samples
pub fn samples(r:*rng.Rng, span:[2]f32, rate:f32) u32 { return m.floorTo(u32, r.range(span[0], span[1]) * rate); }

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
pub const Settle = struct {
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

  pub fn init(weight:f32, r:*rng.Rng, rate:f32) Settle {
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

  pub const Within = struct { r:*rng.Rng, rate:f32, len:u32, low:f32 };

  /// `out` filled with gloops of `kind` (silent unless `used`)
  pub fn gloopsOf(kind:GloopKind, used:bool, out:[]Gloop, w:Within) void {
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
  pub fn render(st:*Settle, out:[]f32, fade:*dsp.Smooth) bool {
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
