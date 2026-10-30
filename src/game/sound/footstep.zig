//! a footstep: leaf litter rustled and crushed under a paw over a muffled pad.
const lib=@import("../../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const dsp=engine.core.dsp;
const rng=engine.core.rng;
const Footfall=lib.player.Footfall;
const silent=lib.sound.silent;
/// the step's shape: seconds to full loudness, then to fall ~63%; a sprint
/// fades this share as long
const attack:f32=0.005;
const fallTime:f32=0.055;
const fallFast:f32=0.6;
/// the leaves: the band they rustle in (Hz) and its width (q), a full
/// belly pulling it this share lower; level to match the other layers
const rustleHz:f32=1500;
const rustleQ:f32=0.8;
const rustleHeavy:f32=0.35;
const rustle:f32=4;
/// how fast the leaves flutter (Hz, below it) and how deep (0..1)
const flutterHz:f32=45;
const flutterAmount:f32=0.8;
/// crushed bits: grains per second at the footfall (more for a full belly),
/// how long each rings (s), heard above this (Hz), level
const crunchDensity:f32=700;
const crunchHeavy:f32=0.6;
const crunchGrain:f32=0.0015;
const crunchHz:f32=1800;
const crunch:f32=0.5;
/// the pad's muffled landing: below this (Hz), falling ~63% in this (s),
/// level light and full
const padHz:f32=180;
const padFallTime:f32=0.03;
const padLight:f32=1.5;
const padFull:f32=6;
/// what softens all of it (Hz)
const softHz:f32=3800;
/// loudness of a settling paw and of a sprinting one
const quiet:f32=0.05;
const loud:f32=0.14;
/// each step strays from these by up to this share
const varyAmount:f32=0.2;
/// `x` strayed by up to `VARY` either way
pub fn vary(r:*rng.Rng,x:f32)f32{return x*r.range(1-varyAmount,1+varyAmount);}
/// one footstep playing out
pub const Step=struct{
  noise:dsp.Noise,
  crunch:dsp.Crackle,
  rustle:dsp.Biquad,
  bits:dsp.Biquad,
  pad:dsp.Biquad,
  flutter:dsp.OnePole,
  /// scales the flutter's low-passed noise back to about ±1
  flutterNorm:f32,
  soft:dsp.OnePole,
  /// samples into the step, and how many the attack takes
  at:u32=0,
  attack:u32,
  /// the body's and the pad's loudness, each kept by its fall per sample
  body:f32=1,
  thump:f32=1,
  fall:f32,
  padFall:f32,
  density:f32,
  gain:f32,
  padGain:f32,
  pub fn init(f:Footfall,r:*rng.Rng,rate:f32)Step{
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
      .fall=@exp(-1/(fall*rate)),
      .padFall=@exp(-1/(padFallTime*rate)),
      .density=crunchDensity*(1+crunchHeavy*f.weight),
      .gain=vary(r,m.lerp(quiet,loud,f.pace)),
      .padGain=m.lerp(padLight,padFull,f.weight),
    };
  }
  /// mixes the step into `out`; false once it has ended
  pub fn render(st:*Step,out:[]f32)bool{
    for(out)|*s|{
      const rise=m.clamp01(m.f(st.at)/m.f(st.attack));
      if(st.at>=st.attack){
        st.body*=st.fall;
        st.thump*=st.padFall;
      }
      st.at+|=1;
      const env=rise*st.body;
      // the crushing is all at the footfall, thinning faster than the rustle
      st.crunch.density=st.density*env*env;
      const n=st.noise.next();
      const z=st.flutter.low(st.noise.next())*st.flutterNorm;
      const flut=1-flutterAmount+flutterAmount*m.clamp01(0.5+0.5*z);
      const leaves=st.rustle.tick(n)*rustle*flut*env;
      const bits=st.bits.tick(st.crunch.next())*crunch;
      const pad=st.pad.tick(n)*st.padGain*rise*st.thump;
      s.*+=st.soft.low(leaves+bits+pad)*st.gain;
    }
    return st.at<st.attack or st.body>silent;
  }
};
