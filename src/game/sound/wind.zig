//! the wind over the garden: a hush in slow gusts, whistling in the strong ones.
const lib=@import("../../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const dsp=engine.core.dsp;
const rng=engine.core.rng;
const retune=lib.sound.sap.retune;
const samples=lib.sound.sap.samples;
// ---- the wind (always) ----
/// gusts: seconds between new strengths, and how fast the wind swells or
/// eases toward one (s); strengths lean soft by this power
const gustGap=[2]f32{2.5,7};
const gustGlide:f32=1.6;
const gustSoft:f32=1.6;
/// the hush: noise below this (Hz), a calm and a gusting level
const hushHz:f32=380;
const hushRange=[2]f32{0.35,1};
/// the whistle: narrow-banded noise (Hz range of its pitch, how narrow,
/// level), rising this share in a full gust and gliding to a new pitch
/// in this (s); heard only as the gust passes this strength
const whistleHz=[2]f32{470,720};
const whistleQ:f32=14;
const whistleAmount:f32=5.6;
const whistleRise:f32=0.1;
const whistleGlide:f32=2.5;
pub const whistleFrom:f32=0.35;
/// a rounder whistle an octave under, at this share
const underAt:f32=0.5;
const underLevel:f32=0.6;
/// what softens it all (Hz) and its loudness
const windSoftHz:f32=1700;
const windTimes:f32=0.05;
/// the wind breathing over the garden, never ending
pub const Wind=struct{
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
  wait:u32=0,
  at:u32=0,
  /// its loudness (tests hush it to hear the rest alone)
  level:f32=windTimes,
  pub fn init(r:*rng.Rng,rate:f32)Wind{
    const hz=r.range(whistleHz[0],whistleHz[1]);
    return.{
      .rate=rate,
      .r=.init(r.next()),
      .noise=.init(r.next()),
      .hush=.init(hushHz,rate),
      .whistle=.init(.band,hz,whistleQ,rate),
      .under=.init(.band,hz*underAt,whistleQ,rate),
      .soft=.init(windSoftHz,rate),
      .gust=.init(0.3,gustGlide,rate),
      .pitch=.init(hz,whistleGlide,rate),
    };
  }
  /// mixes the wind into `out`
  pub fn render(w:*Wind,out:[]f32)void{
    for(out)|*s|{
      if(w.wait==0){
        w.gust.target=m.pow(f32,w.r.float(),gustSoft);
        w.pitch.target=w.r.range(whistleHz[0],whistleHz[1]);
        w.wait=samples(&w.r,gustGap,w.rate);
      }
      w.wait-=1;
      const g=w.gust.next();
      const hz=w.pitch.next()*(1+whistleRise*g);
      if(w.at%retune==0){
        w.whistle.tune(.band,hz,whistleQ,w.rate);
        w.under.tune(.band,hz*underAt,whistleQ,w.rate);
      }
      w.at+%=1;
      const n=w.noise.next();
      const hush=w.hush.low(n)*m.lerp(hushRange[0],hushRange[1],g);
      const sing=m.clamp01((g-whistleFrom)/(1-whistleFrom));
      const whistle=(w.whistle.tick(n)+underLevel*w.under.tick(n))*whistleAmount*sing*sing;
      s.*+=w.soft.low(hush+whistle)*w.level;
    }
  }
};
