//! a footstep: leaf litter rustled and crushed under a paw over a muffled pad.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: lerps, clamps, rounding
const m=engine.core.math;
/// the engine's sound pieces: noise, crackle, filters
const dsp=engine.core.dsp;
/// the seeded random numbers each step draws from
const rng=engine.core.rng;
/// a paw coming down: how heavy (`weight`) and how fast (`pace`)
const Footfall=lib.player.Footfall;
/// quieter than this, a step has ended
const silent=lib.sound.silent;
/// the step's shape: seconds to full loudness, then to fall ~63%; a sprint
/// fades this share as long
/// (this one: seconds to full loudness)
const attack:f32=0.005;
/// seconds for the step to fall ~63% after it
const fallTime:f32=0.055;
/// the share as long a sprinting step's fall lasts
const fallFast:f32=0.6;
/// the leaves: the band they rustle in (Hz) and its width (q), a full
/// belly pulling it this share lower; level to match the other layers
/// (this one: the rustle's band, Hz)
const rustleHz:f32=1500;
/// the rustle band's width (q)
const rustleQ:f32=0.8;
/// the share lower a full belly pulls the rustle and the pad
const rustleHeavy:f32=0.35;
/// the rustle's level
const rustle:f32=4;
/// how fast the leaves flutter (Hz, below it) and how deep (0..1)
const flutterHz:f32=45;
/// how deep the flutter dips the rustle (0..1)
const flutterAmount:f32=0.8;
/// crushed bits: grains per second at the footfall (more for a full belly),
/// how long each rings (s), heard above this (Hz), level
/// (this one: grains a second at the footfall)
const crunchDensity:f32=700;
/// how many more grains a full belly crushes (a share)
const crunchHeavy:f32=0.6;
/// how long each grain rings (s)
const crunchGrain:f32=0.0015;
/// the high-pass the grains are heard above (Hz)
const crunchHz:f32=1800;
/// the crushed bits' level
const crunch:f32=0.5;
/// the pad's muffled landing: below this (Hz), falling ~63% in this (s),
/// level light and full
/// (this one: the low-pass the pad is heard below, Hz)
const padHz:f32=180;
/// how long the pad takes to fall ~63% (s)
const padFallTime:f32=0.03;
/// the pad's level under a light wolf
const padLight:f32=1.5;
/// the pad's level under a full one
const padFull:f32=6;
/// what softens all of it (Hz)
const softHz:f32=3800;
/// loudness of a settling paw and of a sprinting one
/// (this one: a settling paw's loudness)
const quiet:f32=0.05;
/// a sprinting paw's loudness
const loud:f32=0.14;
/// each step strays from these by up to this share
const varyAmount:f32=0.2;
/// `x` strayed by up to `varyAmount` either way
pub fn vary(r:*rng.Rng,x:f32)f32{return x*r.range(1-varyAmount,1+varyAmount);}
/// one footstep playing out
pub const Step=struct{
  /// the white noise the rustle and pad are filtered from
  noise:dsp.Noise,
  /// the crackle of crushed grains
  crunch:dsp.Crackle,
  /// the band-pass the leaves rustle through
  rustle:dsp.Biquad,
  /// the high-pass the crushed bits are heard through
  bits:dsp.Biquad,
  /// the low-pass the pad lands through
  pad:dsp.Biquad,
  /// the low-pass that makes the leaves' slow flutter out of noise
  flutter:dsp.OnePole,
  /// scales the flutter's low-passed noise back to about ±1
  flutterNorm:f32,
  /// the low-pass softening all of it
  soft:dsp.OnePole,
  /// samples into the step, and how many the attack takes
  at:u32=0,
  /// how many samples the attack takes
  attack:u32,
  /// the body's and the pad's loudness, each kept by its fall per sample
  body:f32=1,
  /// the pad's loudness now, 1 falling away
  thump:f32=1,
  /// how much of the body's loudness is kept each sample
  fall:f32,
  /// how much of the pad's loudness is kept each sample
  padFall:f32,
  /// the crackle's grains a second at full loudness
  density:f32,
  /// the step's loudness, varied a little
  gain:f32,
  /// the pad's level for the wolf's weight
  padGain:f32,
  /// a fresh step for footfall `f`: lower and fuller the heavier the wolf,
  /// louder and shorter the faster, every part varied a little by `r`
  pub fn init(f:Footfall,r:*rng.Rng,rate:f32)Step{
    // how long this step falls for (s), and the flutter low-pass's coefficient
    const fall=vary(r,fallTime)*m.lerp(1,fallFast,f.pace);
    const a=dsp.OnePole.coeff(flutterHz,rate);
    return.{
      .noise=.init(r.next()),
      .crunch=.init(r.next(),crunchGrain,rate),
      .rustle=.init(.band,vary(r,rustleHz)*(1-rustleHeavy*f.weight),rustleQ,rate),
      .bits=.init(.high,vary(r,crunchHz),0.707,rate),
      .pad=.init(.low,vary(r,padHz)*(1-rustleHeavy*f.weight),0.707,rate),
      .flutter=.{.a=a},
      // decision: white noise in ±1 has a variance of 1/3; a one-pole keeps
      // a/(2-a) of it
      .flutterNorm=@sqrt(3*(2-a)/a),
      .soft=.init(softHz,rate),
      .attack=m.floorTo(u32,attack*rate)+1,
      .fall=dsp.fall(fall,rate),
      .padFall=dsp.fall(padFallTime,rate),
      .density=crunchDensity*(1+crunchHeavy*f.weight),
      .gain=vary(r,m.lerp(quiet,loud,f.pace)),
      .padGain=m.lerp(padLight,padFull,f.weight),
    };
  }
  /// mixes the step into `out`; false once it has ended
  pub fn render(st:*Step,out:[]f32)bool{
    for(out)|*s|{
      // how far into its attack the step is, 0..1
      const rise=m.clamp01(m.f(st.at)/m.f(st.attack));
      if(st.at>=st.attack){
        st.body*=st.fall;
        st.thump*=st.padFall;
      }
      st.at+|=1;
      // the step's loudness now
      const env=rise*st.body;
      // the crushing is all at the footfall, thinning faster than the rustle
      st.crunch.density=st.density*env*env;
      // one noise sample for the rustle and the pad
      const n=st.noise.next();
      // the slow flutter noise, scaled back to about ±1, and how far it dips the rustle
      const z=st.flutter.low(st.noise.next())*st.flutterNorm;
      const flut=1-flutterAmount+flutterAmount*m.clamp01(0.5+0.5*z);
      // the leaves, the crushed bits, and the pad, each this sample
      const leaves=st.rustle.tick(n)*rustle*flut*env;
      const bits=st.bits.tick(st.crunch.next())*crunch;
      const pad=st.pad.tick(n)*st.padGain*rise*st.thump;
      s.*+=st.soft.low(leaves+bits+pad)*st.gain;
    }
    return st.at<st.attack or st.body>silent;
  }
};
