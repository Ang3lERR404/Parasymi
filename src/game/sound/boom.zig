//! the arsthraxia's completion: a pop into a deep thud and a fracturing shimmer.
const lib=@import("../../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const dsp=engine.core.dsp;
const rng=engine.core.rng;
const silent=lib.sound.silent;
const vary=lib.sound.footstep.vary;
// the boom: a sharp pop into a deep, long thud
const boomCore=[2]f32{55,30};
const boomDrop:f32=0.2;
const boomCoreFall:f32=1.8;
const boomThud:f32=2.0;
const boomSubHz:f32=28;
const boomSubFall:f32=2.5;
const boomSub:f32=0.6;
const boomPopHz:f32=2500;
const boomPopFall:f32=0.008;
const boomPop:f32=0.8;
const boomThumpHz:f32=100;
const boomThumpFall:f32=0.15;
const boomThump:f32=1.2;
const boom:f32=0.15;
// the shimmer: a cascade of inharmonic partials (a crystalline structure
// fracturing), each starting slightly after the last, some wobbling as
// they ring out
const boomShimmerN=10;
const boomShimmerBase:f32=660;
const boomShimmerInharm:f32=0.004;
const boomShimmerStagger:f32=0.012;
const boomShimmerSoftHz:f32=6000;
const boomShimmer:f32=0.08;
const boomShimmerWobble=[boomShimmerN]bool{
  false,true,false,true,false,true,false,true,false,true,
};
const boomShimmerWobbleHz=[2]f32{2.0,3.5};
const boomShimmerWobbleDepth:f32=0.25;
/// the boom and its shimmer
pub const Boom=struct{
  core:dsp.Osc,
  noise:dsp.Noise,
  thump:dsp.Biquad,
  pop:dsp.Biquad,
  sub:dsp.Sine,
  shimmer:[boomShimmerN]dsp.Sine,
  shimmerAmp:[boomShimmerN]f32=@splat(1),
  shimmerFall:[boomShimmerN]f32,
  shimmerStart:[boomShimmerN]u32,
  shimmerWobble:[boomShimmerN]dsp.Osc,
  shimmerWobbleOn:[boomShimmerN]bool,
  shimmerSoft:dsp.OnePole,
  drop:f32=1,
  coreAmp:f32=1,
  thumpAmp:f32=1,
  popAmp:f32=1,
  subAmp:f32=1,
  dropFall:f32,
  coreFall:f32,
  thumpFall:f32,
  popFall:f32,
  subFall:f32,
  at:u32=0,
  gain:f32,
  pub fn init(r:*rng.Rng,rate:f32)Boom{
    var sp:[boomShimmerN]dsp.Sine=undefined;
    var sf:[boomShimmerN]f32=undefined;
    var ss:[boomShimmerN]u32=undefined;
    var sw:[boomShimmerN]dsp.Osc=undefined;
    var swn:[boomShimmerN]bool=undefined;
    const base=vary(r,boomShimmerBase);
    inline for(0..boomShimmerN)|k|{
      const n=m.f(k+1);
      const hz=base*n*(1+boomShimmerInharm*n*n);
      sp[k]=.init(hz,rate);
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
  pub fn render(b:*Boom,out:[]f32)bool{
    for(out)|*s|{
      b.core.freq=m.lerp(boomCore[1],boomCore[0],b.drop);
      b.drop*=b.dropFall;
      b.coreAmp*=b.coreFall;
      b.thumpAmp*=b.thumpFall;
      b.popAmp*=b.popFall;
      b.subAmp*=b.subFall;
      const n=b.noise.next();
      const impact=b.core.next()*boomThud*b.coreAmp+b.thump.tick(n)*boomThump*b.thumpAmp+b.pop.tick(n)*boomPop*b.popAmp+b.sub.next()*boomSub*b.subAmp;
      var sh:f32=0;
      var alive=false;
      for(0..boomShimmerN)|k|{
        if(b.at<b.shimmerStart[k])continue;
        if(b.shimmerAmp[k]<silent)continue;
        alive=true;
        b.shimmerAmp[k]*=b.shimmerFall[k];
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
