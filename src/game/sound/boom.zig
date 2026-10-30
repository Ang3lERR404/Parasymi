//! the arsthraxia's completion: a pop into a deep thud and a fracturing shimmer.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: lerps, exponentials, rounding
const m=engine.core.math;
/// the engine's sound pieces: oscillators, noise, filters
const dsp=engine.core.dsp;
/// the seeded random numbers the boom draws from
const rng=engine.core.rng;
/// quieter than this, a part has rung out
const silent=lib.sound.silent;
/// a value nudged a little either way, so no two booms are alike
const vary=lib.sound.footstep.vary;
// the boom: a sharp pop into a deep, long thud
/// the core saw's pitch at the pop, and where it drops to (Hz)
const boomCore=[2]f32{55,30};
/// how long that pitch drop takes (s to fall to about a third)
const boomDrop:f32=0.2;
/// how long the core rings out (s to fall to about a third)
const boomCoreFall:f32=1.8;
/// the core's level in the impact
const boomThud:f32=2.0;
/// the sub-bass sine under it (Hz)
const boomSubHz:f32=28;
/// how long the sub rings out (s)
const boomSubFall:f32=2.5;
/// the sub's level in the impact
const boomSub:f32=0.6;
/// the high-pass on the noise that makes the pop (Hz)
const boomPopHz:f32=2500;
/// how short the pop is (s)
const boomPopFall:f32=0.008;
/// the pop's level in the impact
const boomPop:f32=0.8;
/// the low-pass on the noise that makes the thump (Hz)
const boomThumpHz:f32=100;
/// how long the thump lasts (s)
const boomThumpFall:f32=0.15;
/// the thump's level in the impact
const boomThump:f32=1.2;
/// the whole impact's loudness
const boom:f32=0.15;
// the shimmer: a cascade of inharmonic partials (a crystalline structure
// fracturing), each starting slightly after the last, some wobbling as
// they ring out
/// how many partials ring
const boomShimmerN=10;
/// the lowest partial's pitch (Hz), varied a little each time
const boomShimmerBase:f32=660;
/// how far each partial strays sharp of a true harmonic (grows with its number squared)
const boomShimmerInharm:f32=0.004;
/// how long after the last each partial starts (s)
const boomShimmerStagger:f32=0.012;
/// the low-pass that softens the shimmer (Hz)
const boomShimmerSoftHz:f32=6000;
/// the shimmer's level in the mix
const boomShimmer:f32=0.08;
/// which partials wobble as they ring (every second one)
const boomShimmerWobble=[boomShimmerN]bool{
  false,true,false,true,false,true,false,true,false,true,
};
/// how fast a wobbling partial wobbles, drawn between these (Hz)
const boomShimmerWobbleHz=[2]f32{2.0,3.5};
/// how deep a wobble dips its partial (0..1)
const boomShimmerWobbleDepth:f32=0.25;
/// the boom and its shimmer
pub const Boom=struct{
  /// the core saw, its pitch dropping
  core:dsp.Osc,
  /// the white noise the thump and pop are filtered from
  noise:dsp.Noise,
  /// the low-pass shaping the thump
  thump:dsp.Biquad,
  /// the high-pass shaping the pop
  pop:dsp.Biquad,
  /// the sub-bass sine
  sub:dsp.Sine,
  /// the shimmer's partials
  shimmer:[boomShimmerN]dsp.Sine,
  /// each partial's level now, 1 falling toward silence
  shimmerAmp:[boomShimmerN]f32=@splat(1),
  /// how much of its level each partial keeps a sample
  shimmerFall:[boomShimmerN]f32,
  /// the sample each partial starts on
  shimmerStart:[boomShimmerN]u32,
  /// each partial's wobble
  shimmerWobble:[boomShimmerN]dsp.Osc,
  /// whether each partial wobbles
  shimmerWobbleOn:[boomShimmerN]bool,
  /// the low-pass softening the shimmer
  shimmerSoft:dsp.OnePole,
  /// how far the core's pitch is from its drop, 1 at the pop .. 0 dropped
  drop:f32=1,
  /// the core's level now, 1 falling away
  coreAmp:f32=1,
  /// the thump's level now
  thumpAmp:f32=1,
  /// the pop's level now
  popAmp:f32=1,
  /// the sub's level now
  subAmp:f32=1,
  /// how much of the pitch drop is left after each sample
  dropFall:f32,
  /// how much of the core's level is kept each sample
  coreFall:f32,
  /// how much of the thump's level is kept each sample
  thumpFall:f32,
  /// how much of the pop's level is kept each sample
  popFall:f32,
  /// how much of the sub's level is kept each sample
  subFall:f32,
  /// samples played so far
  at:u32=0,
  /// the impact's loudness, varied a little each time
  gain:f32,
  /// a fresh boom, its partials' pitches, falls and wobbles drawn from `r`
  pub fn init(r:*rng.Rng,rate:f32)Boom{
    // each partial's sine, fall, start, wobble, and whether it wobbles, filled in below
    var sp:[boomShimmerN]dsp.Sine=undefined;
    var sf:[boomShimmerN]f32=undefined;
    var ss:[boomShimmerN]u32=undefined;
    var sw:[boomShimmerN]dsp.Osc=undefined;
    var swn:[boomShimmerN]bool=undefined;
    // the lowest partial's pitch, varied
    const base=vary(r,boomShimmerBase);
    inline for(0..boomShimmerN)|k|{
      // the partial's number, from 1, and its stretched pitch
      const n=m.f(k+1);
      const hz=base*n*(1+boomShimmerInharm*n*n);
      sp[k]=.init(hz,rate);
      // how long this partial rings (s): higher ones a little shorter
      const fallS=(2.2-m.f(k)*0.18)*r.range(0.8,1.3);
      sf[k]=@exp(-1/(fallS*rate));
      ss[k]=m.floorTo(u32,m.f(k)*boomShimmerStagger*rate);
      swn[k]=boomShimmerWobble[k];
      sw[k]=.{.rate=rate,.freq=r.range(boomShimmerWobbleHz[0],boomShimmerWobbleHz[1])};
    }
    return.{
      .core=.{.rate=rate,.shape=.saw,.freq=boomCore[0]},
      .noise=.init(r.next()),
      .thump=.init(.low,boomThumpHz,0.707,rate),
      .pop=.init(.high,boomPopHz,0.707,rate),
      .sub=.init(boomSubHz,rate),
      .shimmer=sp,
      .shimmerFall=sf,
      .shimmerStart=ss,
      .shimmerWobble=sw,
      .shimmerWobbleOn=swn,
      .shimmerSoft=.init(boomShimmerSoftHz,rate),
      .dropFall=@exp(-1/(boomDrop*rate)),
      .coreFall=@exp(-1/(boomCoreFall*rate)),
      .thumpFall=@exp(-1/(boomThumpFall*rate)),
      .popFall=@exp(-1/(boomPopFall*rate)),
      .subFall=@exp(-1/(boomSubFall*rate)),
      .gain=vary(r,boom),
    };
  }
  /// mixes the next `out.len` samples into `out`: the pop, thud and sub
  /// falling away while the shimmer's partials ring in one after the next;
  /// returns false once all of it has rung out
  pub fn render(b:*Boom,out:[]f32)bool{
    for(out)|*s|{
      b.core.freq=m.lerp(boomCore[1],boomCore[0],b.drop);
      b.drop*=b.dropFall;
      b.coreAmp*=b.coreFall;
      b.thumpAmp*=b.thumpFall;
      b.popAmp*=b.popFall;
      b.subAmp*=b.subFall;
      // one noise sample for both the thump and the pop
      const n=b.noise.next();
      // the impact: core, thump, pop and sub mixed
      const impact=b.core.next()*boomThud*b.coreAmp+b.thump.tick(n)*boomThump*b.thumpAmp+b.pop.tick(n)*boomPop*b.popAmp+b.sub.next()*boomSub*b.subAmp;
      // the shimmer summed, and whether any partial still rings
      var sh:f32=0;
      var alive=false;
      for(0..boomShimmerN)|k|{
        if(b.at<b.shimmerStart[k])continue;
        if(b.shimmerAmp[k]<silent)continue;
        alive=true;
        b.shimmerAmp[k]*=b.shimmerFall[k];
        // this partial's level, dipped by its wobble
        var amp=b.shimmerAmp[k];
        if(b.shimmerWobbleOn[k]){
          amp*=1-boomShimmerWobbleDepth+boomShimmerWobbleDepth*(1+b.shimmerWobble[k].next())*0.5;
        }
        sh+=b.shimmer[k].next()*amp*(1-m.f(k)*0.07);
      }
      s.*+=impact*b.gain+b.shimmerSoft.low(sh)*boomShimmer;
      b.at+|=1;
      if(!alive and b.coreAmp<silent and b.subAmp<silent)return false;
    }
    return true;
  }
};
