//! a mote of starlight twinkling: a few glassy pings dying in a shimmer.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: lerps, clamps, rounding
const m=engine.core.math;
/// the engine's sound pieces: oscillators, the soft low-pass
const dsp=engine.core.dsp;
/// the seeded random numbers each twinkle draws from
const rng=engine.core.rng;
/// a span of seconds drawn as samples
const samples=lib.sound.sap.samples;
/// a value nudged a little either way, so no two twinkles are alike
const vary=lib.sound.footstep.vary;
// ---- the starlight twinkling (near a mote) ----
/// pings in one twinkle (fewest, most), seconds between them, and the
/// first ping's pitch (Hz); each next steps up or down by one of `stepRatios`
/// (this one: how many pings)
pub const pingRange=m.Vice(u32,2){2,4};
/// seconds between pings
const pingGap=m.Vice(f32,2){0.05,0.13};
/// the first ping's pitch (Hz)
const pingHz=m.Vice(f32,2){2100,3400};
/// the ratios a ping's pitch may step by to the next: up or down a little
const stepRatios=[_]f32{1.122,1.189,1.335,0.891,0.841};
/// a ping's glassy partials (shares of its pitch, a little stretched so it
/// shimmers), their levels, how long each rings (s, ~63%) and the attack (s)
/// (this one: the partials' pitches, as shares of the ping's)
const partials=[_]f32{1,2.32,4.13};
/// each partial's level
const partialLevel=[_]f32{1,0.4,0.15};
/// how long each partial rings (s, ~63%)
const partialFall=[_]f32{0.32,0.14,0.06};
/// a ping's attack (s)
const pingAttack:f32=0.003;
/// a slow shimmer through it all (Hz, share)
/// (this one: how fast it shimmers, Hz)
const shimmerHz:f32=7;
/// how deep it shimmers (a share)
const shimmer:f32=0.25;
/// what softens it (Hz), and its loudness for a far and a touching mote
/// (this one: the low-pass that softens it, Hz)
const twinkleSoftHz:f32=7000;
/// its loudness for a far mote and for a touching one
const twinkle=m.Vice(f32,2){0.006,0.03};
/// twinkles that may sound at once
pub const twinkles=2;
/// a ping this far faded is gone (it is already far quieter than a step)
const pingSilent:f32=1e-3;
/// how far either way of the mote each ping may ring (pan): a scatter of
/// glints round one point of light
const pingScatter:f32=0.2;
/// one ping: a tiny bell
const Ping=struct{
  /// each partial's sine
  osc:[partials.len]dsp.Osc,
  /// each partial's level now, 1 falling away
  amp:[partials.len]f32=@splat(1),
  /// how much of its level each partial keeps a sample
  fall:[partials.len]f32,
  /// the twinkle's sample it starts on
  start:u32,
  /// how many samples its attack takes
  attack:u32,
  /// how loud it is (0: a ping not used)
  level:f32,
  /// where it rings between the speakers
  place:dsp.Frame,
  /// samples since it started
  age:u32=0,
  /// its next sample at the twinkle's sample `at`, in its place: silent
  /// before its start, rising through its attack, its partials ringing away
  fn tick(p:*Ping,at:u32)dsp.Frame{
    if(at<p.start)return@splat(0);
    // how far through its attack it is, 0..1
    const rise=m.clamp01(m.f(p.age)/m.f(p.attack));
    p.age+|=1;
    // the partials summed
    var y:f32=0;
    inline for(0..partials.len)|k|{
      if(p.age>p.attack)p.amp[k]*=p.fall[k];
      y+=p.osc[k].next()*p.amp[k]*partialLevel[k];
    }
    return dsp.put(p.place,y*rise*p.level);
  }
  /// whether it has rung out
  fn done(p:*const Ping)bool{return p.age>p.attack and p.amp[0]<pingSilent;}
};
/// one twinkle playing out
pub const Twinkle=struct{
  /// its pings (only the first `n` sound)
  pings:[pingRange[1]]Ping,
  /// how many pings sound
  n:u32,
  /// the slow shimmer's wave
  shimmer:dsp.Osc,
  /// the low-pass softening it
  soft:dsp.StereoPole,
  /// samples played so far
  at:u32=0,
  /// its loudness, for how near the mote is
  gain:f32,
  /// a fresh twinkle for a mote `near` (0 far .. 1 touching) heard at
  /// `pan` (-1 left .. 1 right): its pings' count, pitches, spacing and
  /// scatter round it drawn from `r`
  pub fn init(near:f32,pan:f32,r:*rng.Rng,rate:f32)Twinkle{
    // how many pings sound
    const n=pingRange[0]+r.below(pingRange[1]-pingRange[0]+1);
    // the pings, filled in below
    var pings:[pingRange[1]]Ping=undefined;
    // the next ping's pitch, and the sample it starts on
    var hz=r.range(pingHz[0],pingHz[1]);
    var start:u32=0;
    for(&pings,0..)|*p,i|{
      // this ping's partials' sines and falls, filled in below
      var osc:[partials.len]dsp.Osc=undefined;
      var fall:[partials.len]f32=undefined;
      inline for(0..partials.len)|k|{
        osc[k]=.{.rate=rate,.freq=hz*partials[k],.phase=r.float()};
        fall[k]=dsp.fall(vary(r,partialFall[k]),rate);
      }
      p.*=.{
        .osc=osc,
        .fall=fall,
        .start=start,
        .attack=m.floorTo(u32,pingAttack*rate)+1,
        // each later ping a little softer
        .level=if(i<n)vary(r,1)/m.f(i+1)else 0,
        .place=dsp.spot(pan+r.range(-pingScatter,pingScatter)),
      };
      start+=samples(r,pingGap,rate);
      hz*=stepRatios[r.below(stepRatios.len)];
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
  pub fn render(t:*Twinkle,out:[]dsp.Frame)bool{
    for(out)|*s|{
      // the pings summed this sample, each in its place
      var y:dsp.Frame=@splat(0);
      for(t.pings[0..t.n])|*p|y+=p.tick(t.at);
      t.at+|=1;
      s.*+=t.soft.low(y)*dsp.mid((1-shimmer+shimmer*t.shimmer.next())*t.gain);
    }
    for(t.pings[0..t.n])|p|if(!p.done())return true;
    return false;
  }
};
