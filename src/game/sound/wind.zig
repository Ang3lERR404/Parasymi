//! the wind over the garden: a hush in slow gusts, whistling in the strong ones.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: lerps, clamps, powers
const m=engine.core.math;
/// the engine's sound pieces: noise, filters, smoothing
const dsp=engine.core.dsp;
/// the seeded random numbers the wind draws from
const rng=engine.core.rng;
/// samples between retunings of the whistle's band
const retune=lib.sound.sap.retune;
/// a span of seconds drawn as samples
const samples=lib.sound.sap.samples;
// ---- the wind (always) ----
/// gusts: seconds between new strengths, and how fast the wind swells or
/// eases toward one (s); strengths lean soft by this power
/// (this one: seconds between new strengths)
const gustGap=m.Vice(f32,2){2.5,7};
/// how long the wind takes to swell or ease toward one (s)
const gustGlide:f32=1.6;
/// how soft strengths lean (a power over 0..1)
const gustSoft:f32=1.6;
/// the hush: noise below this (Hz), a calm and a gusting level
/// (this one: the low-pass the hush is heard below, Hz)
const hushHz:f32=380;
/// its level calm and in a full gust
const hushRange=m.Vice(f32,2){0.35,1};
/// the whistle: narrow-banded noise (Hz range of its pitch, how narrow,
/// level), rising this share in a full gust and gliding to a new pitch
/// in this (s); heard only as the gust passes this strength
/// (this one: the whistle's pitch range, Hz)
const whistleHz=m.Vice(f32,2){470,720};
/// how narrow its band is (q)
const whistleQ:f32=14;
/// its level
const whistleAmount:f32=5.6;
/// how much higher it rises in a full gust (a share)
const whistleRise:f32=0.1;
/// how long it glides to a new pitch (s)
const whistleGlide:f32=2.5;
/// the gust strength (0..1) past which it is heard
pub const whistleFrom:f32=0.35;
/// a rounder whistle an octave under, at this share
/// (this one: its pitch, as a share of the whistle's)
const underAt:f32=0.5;
/// its level, as a share of the whistle's
const underLevel:f32=0.6;
/// what softens it all (Hz) and its loudness
/// (this one: the low-pass that softens it all, Hz)
const windSoftHz:f32=1700;
/// the wind's loudness
const windTimes:f32=0.05;
/// how far to either side a gust's whistle may come from (pan): the wind
/// blowing in from one side and then another
const whistleSide:f32=0.6;
/// how long the whistle takes to drift to a new side (s)
const sideGlide:f32=3;
/// the wind breathing over the garden, never ending: its hush on both
/// sides unlike (two streams of air), its whistle drifting from side to side
pub const Wind=struct{
  /// samples per second
  rate:f32,
  /// its own random numbers
  r:rng.Rng,
  /// the white noise all of it is made from (the left side's hush, and the whistle)
  noise:dsp.Noise,
  /// the right side's own noise, so the two sides' air is unlike
  noiseRight:dsp.Noise,
  /// the low-pass the hush is heard through, each side
  hush:dsp.StereoPole,
  /// the whistle's narrow band
  whistle:dsp.Biquad,
  /// the rounder whistle's band an octave under
  under:dsp.Biquad,
  /// the low-pass softening it all
  soft:dsp.StereoPole,
  /// the gust's strength, 0..1, gliding to each new one
  gust:dsp.Smooth,
  /// the whistle's pitch (Hz), gliding to each new one
  pitch:dsp.Smooth,
  /// the side the whistle comes from (pan), drifting to each gust's
  side:dsp.Smooth,
  /// the speakers' gains for that side, worked out at each retune
  place:dsp.Frame=dsp.spot(0),
  /// samples until the next gust's strength, and to the next retune
  wait:u32=0,
  /// samples played so far (wraps), for when to retune
  at:u32=0,
  /// its loudness (tests hush it to hear the rest alone)
  level:f32=windTimes,
  /// a fresh wind, its first whistle pitch and its gusts drawn from `r`
  pub fn init(r:*rng.Rng,rate:f32)Wind{
    // the whistle's first pitch (Hz)
    const hz=r.range(whistleHz[0],whistleHz[1]);
    return.{
      .rate=rate,
      .r=.init(r.next()),
      .noise=.init(r.next()),
      .noiseRight=.init(r.next()),
      .hush=.init(hushHz,rate),
      .whistle=.init(.band,hz,whistleQ,rate),
      .under=.init(.band,hz*underAt,whistleQ,rate),
      .soft=.init(windSoftHz,rate),
      .gust=.init(0.3,gustGlide,rate),
      .pitch=.init(hz,whistleGlide,rate),
      .side=.init(0,sideGlide,rate),
    };
  }
  /// mixes the wind into `out`
  pub fn render(w:*Wind,out:[]dsp.Frame)void{
    for(out)|*s|{
      if(w.wait==0){
        w.gust.target=m.pow(f32,w.r.float(),gustSoft);
        w.pitch.target=w.r.range(whistleHz[0],whistleHz[1]);
        w.side.target=w.r.range(-whistleSide,whistleSide);
        w.wait=samples(&w.r,gustGap,w.rate);
      }
      w.wait-=1;
      // the gust's strength this sample, the whistle's pitch, lifted by it, and its side
      const g=w.gust.next();
      const hz=w.pitch.next()*(1+whistleRise*g);
      const side=w.side.next();
      if(w.at%retune==0){
        w.whistle.tune(.band,hz,whistleQ,w.rate);
        w.under.tune(.band,hz*underAt,whistleQ,w.rate);
        w.place=dsp.spot(side);
      }
      w.at+%=1;
      // the noise sample the left hush and the whistle share, and the right side's
      const n=w.noise.next();
      const nr=w.noiseRight.next();
      // the hush, louder in a gust
      const hush=w.hush.low(.{n,nr})*dsp.mid(m.lerp(hushRange[0],hushRange[1],g));
      // how far past `whistleFrom` the gust is, 0..1, and the whistle it brings
      const sing=m.unlerp(whistleFrom,1,g);
      const whistle=(w.whistle.tick(n)+underLevel*w.under.tick(n))*whistleAmount*sing*sing;
      s.*+=w.soft.low(hush+dsp.put(w.place,whistle))*dsp.mid(w.level);
    }
  }
};
