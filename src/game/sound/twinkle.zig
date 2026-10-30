//! a mote of starlight twinkling: a few glassy pings dying in a shimmer.
const lib=@import("../../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const dsp=engine.core.dsp;
const rng=engine.core.rng;
const samples=lib.sound.sap.samples;
const vary=lib.sound.footstep.vary;
// ---- the starlight twinkling (near a mote) ----
/// pings in one twinkle (fewest, most), seconds between them, and the
/// first ping's pitch (Hz); each next steps up or down by one of `STEPS`
pub const pingRange=[2]u32{2,4};
const pingGap=[2]f32{0.05,0.13};
const pingHz=[2]f32{2100,3400};
const stepCount=[_]f32{1.122,1.189,1.335,0.891,0.841};
/// a ping's glassy partials (shares of its pitch, a little stretched so it
/// shimmers), their levels, how long each rings (s, ~63%) and the attack (s)
const partials=[_]f32{1,2.32,4.13};
const partialLevel=[_]f32{1,0.4,0.15};
const partialFall=[_]f32{0.32,0.14,0.06};
const pingAttack:f32=0.003;
/// a slow shimmer through it all (Hz, share)
const shimmerHz:f32=7;
const shimmer:f32=0.25;
/// what softens it (Hz), and its loudness for a far and a touching mote
const twinkleSoftHz:f32=7000;
const twinkle=[2]f32{0.006,0.03};
/// twinkles that may sound at once
pub const twinkles=2;
/// a ping this far faded is gone (it is already far quieter than a step)
const pingSilent:f32=1e-3;
/// one ping: a tiny bell
const Ping=struct{
  osc:[partials.len]dsp.Osc,
  amp:[partials.len]f32=@splat(1),
  fall:[partials.len]f32,
  start:u32,
  attack:u32,
  level:f32,
  age:u32=0,
  fn tick(p:*Ping,at:u32)f32{
    if(at<p.start)return 0;
    const rise=m.clamp01(m.f(p.age)/m.f(p.attack));
    p.age+|=1;
    var y:f32=0;
    inline for(0..partials.len)|k|{
      if(p.age>p.attack)p.amp[k]*=p.fall[k];
      y+=p.osc[k].next()*p.amp[k]*partialLevel[k];
    }
    return y*rise*p.level;
  }
  fn done(p:*const Ping)bool{return p.age>p.attack and p.amp[0]<pingSilent;}
};
/// one twinkle playing out
pub const Twinkle=struct{
  pings:[pingRange[1]]Ping,
  n:u32,
  shimmer:dsp.Osc,
  soft:dsp.OnePole,
  at:u32=0,
  gain:f32,
  pub fn init(near:f32,r:*rng.Rng,rate:f32)Twinkle{
    const n=pingRange[0]+r.below(pingRange[1]-pingRange[0]+1);
    var pings:[pingRange[1]]Ping=undefined;
    var hz=r.range(pingHz[0],pingHz[1]);
    var start:u32=0;
    for(&pings,0..)|*p,i|{
      var osc:[partials.len]dsp.Osc=undefined;
      var fall:[partials.len]f32=undefined;
      inline for(0..partials.len)|k|{
        osc[k]=.{.rate=rate,.freq=hz*partials[k],.phase=r.float()};
        fall[k]=@exp(-1/(vary(r,partialFall[k])*rate));
      }
      p.*=.{
        .osc=osc,
        .fall=fall,
        .start=start,
        .attack=m.floorTo(u32,pingAttack*rate)+1,
        // each later ping a little softer
        .level=if(i<n)vary(r,1)/m.f(i+1)else 0,
      };
      start+=samples(r,pingGap,rate);
      hz*=stepCount[r.below(stepCount.len)];
    }
    return.{
      .pings=pings,
      .n=n,
      .shimmer=.{.rate=rate,.freq=vary(r,shimmerHz)},
      .soft=.init(twinkleSoftHz,rate),
      .gain=m.lerp(twinkle[0],twinkle[1],near),
    };
  }
  /// mixes the twinkle into `out`; false once it has ended
  pub fn render(t:*Twinkle,out:[]f32)bool{
    for(out)|*s|{
      var y:f32=0;
      for(t.pings[0..t.n])|*p|y+=p.tick(t.at);
      t.at+|=1;
      s.*+=t.soft.low(y)*(1-shimmer+shimmer*t.shimmer.next())*t.gain;
    }
    for(t.pings[0..t.n])|p|if(!p.done())return true;
    return false;
  }
};
