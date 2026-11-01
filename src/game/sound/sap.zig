//! the sap settling, heard from inside the wolf (first person): a groan with gloops.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: lerps, easing, rounding
const m=engine.core.math;
/// the engine's sound pieces: oscillators, noise, filters, smoothing
const dsp=engine.core.dsp;
/// the seeded random numbers each settling draws from
const rng=engine.core.rng;
/// quieter than this, a gloop has rung out
const silent=lib.sound.silent;
/// a value nudged a little either way, so no two settlings are alike
const vary=lib.sound.footstep.vary;
// ---- the sap settling (first person) ----
/// how long a settling lasts (s)
const settleLen=m.Vice(f32,2){2.4,3.8};
/// seconds between settlings while the wolf stands and while it walks; the
/// first comes this soon after the view enters the eyes
/// (this one: the gap while it stands, s)
pub const gapStill=m.Vice(f32,2){3.5,8};
/// the gap while it walks (s)
pub const gapWalk=m.Vice(f32,2){9,18};
/// how soon the first comes after the view enters the eyes (s)
pub const gapFirst=m.Vice(f32,2){1.2,3};
/// the wolf stands once no step has landed for this long (s)
pub const stillAfter:f32=1.2;
/// the groan: a low reedy hum (Hz) sagging this share as it settles,
/// wavering slowly (Hz, share), voiced through a throat (Hz) closing from
/// the first to the second, ringing this much (q); breath in it (noise
/// share) and its level. A full belly pulls it all this share lower.
/// (this one: the hum's pitch, Hz)
const groanHz:f32=48;
/// how far the hum sags as it settles (a share)
const groanSag:f32=0.18;
/// how fast it wavers (Hz)
const waverHz:f32=2.3;
/// how far it wavers (a share)
const waver:f32=0.025;
/// the throat's centre, closing from the first to the second (Hz)
const throatHz=m.Vice(f32,2){260,150};
/// how much the throat rings (q)
const throatQ:f32=3.5;
/// how much breath is in it (a share of noise)
const breathAmount:f32=0.35;
/// the groan's level
const groanLevel:f32=1.2;
/// how much lower a full belly pulls it all (a share)
const sapHeavy:f32=0.25;
/// samples between retunings of the closing throat
pub const retune=32;
/// a kind of gloop: how many (fewest, most), when (shares of the
/// settling), its pitch (Hz), its fall (s) and level
/// (fields: `n` fewest and most, `at` when, `hz` pitch, `fall` s, `level`)
const GloopKind=struct{n:m.Vice(u32,2),at:m.Vice(f32,2),hz:m.Vice(f32,2),fall:m.Vice(f32,2),level:f32};
/// the deep ones every settling has, and the lighter, smaller ones that
/// come with only this share of settlings
/// (this one: the deep ones)
pub const deep:GloopKind=.{.n=.{2,5},.at=.{0.1,0.65},.hz=.{110,210},.fall=.{0.06,0.12},.level=0.6};
/// the lighter, smaller gloops that come with only some settlings
const lightGloop:GloopKind=.{.n=.{1,2},.at=.{0.2,0.75},.hz=.{300,460},.fall=.{0.035,0.06},.level=0.35};
/// the share of settlings that bring the lighter gloops
const lightChance:f32=0.25;
/// the most gloops one settling can hold
const gloopCount=deep.n[1]+lightGloop.n[1];
/// each gloop's pitch rises this share as it fades; its attack (s)
/// (this one: how far the pitch rises, a share)
const gloopRise:f32=0.7;
/// a gloop's attack (s)
const gloopAttack:f32=0.006;
/// heard from inside: what muffles it (Hz), its loudness, and how fast it
/// fades in and out with the view (s)
/// (this one: the low-pass that muffles it, Hz)
const sapSoftHz:f32=650;
/// the settling's loudness
const sap:f32=0.07;
/// how fast it fades in and out with the view (s)
pub const sapFade:f32=0.35;
/// seconds in `span` as samples
pub fn samples(r:*rng.Rng,span:m.Vice(f32,2),rate:f32)u32{return m.floorTo(u32,r.range(span[0],span[1])*rate);}
/// one thick bubble rising through the sap
const Gloop=struct{
  /// its sine
  osc:dsp.Osc,
  /// its pitch before it rises (Hz)
  base:f32,
  /// the settling's sample it starts on (never, for a gloop not used)
  start:u32,
  /// how many samples its attack takes
  attack:u32,
  /// how much of its level it keeps each sample
  fall:f32,
  /// how loud it is
  level:f32,
  /// its level now, 1 falling toward silence
  amp:f32=1,
  /// samples since it started
  age:u32=0,
  /// its next sample at the settling's sample `at`: silent before its
  /// start, rising through its attack, then fading as its pitch lifts
  fn tick(g:*Gloop,at:u32)f32{
    if(at<g.start or g.amp<silent)return 0;
    // how far through its attack it is, 0..1
    const rise=m.clamp01(m.f(g.age)/m.f(g.attack));
    if(g.age>=g.attack)g.amp*=g.fall;
    g.age+|=1;
    g.osc.freq=g.base*(1+gloopRise*(1-g.amp));
    return g.osc.next()*rise*g.amp*g.level;
  }
};
/// one settling of the sap playing out
pub const Settle=struct{
  /// samples per second
  rate:f32,
  /// the reedy hum: a saw
  hum:dsp.Osc,
  /// the hum's slow waver
  waver:dsp.Osc,
  /// the breath's noise
  noise:dsp.Noise,
  /// the closing throat the hum is voiced through
  throat:dsp.Biquad,
  /// the low-pass muffling it all, heard from inside
  soft:dsp.OnePole,
  /// the gloops rising through it
  gloops:[gloopCount]Gloop,
  /// the hum's pitch before it sags, and the belly's lowering
  base:f32,
  /// how far a full belly lowers it all (1 not at all)
  low:f32,
  /// samples played so far
  at:u32=0,
  /// how many samples the settling lasts
  len:u32,
  /// its loudness, varied a little
  gain:f32,
  /// a fresh settling for a belly of `weight` (0 light .. 1 full): its
  /// length, hum and gloops drawn from `r`
  pub fn init(weight:f32,r:*rng.Rng,rate:f32)Settle{
    // how far the belly lowers it, and how long it lasts (samples)
    const low=1-sapHeavy*weight;
    const len=samples(r,settleLen,rate)+1;
    // the gloops, filled in below, and whether the light ones come too
    var gloops:[gloopCount]Gloop=undefined;
    const light=r.float()<lightChance;
    gloopsOf(deep,true,gloops[0..deep.n[1]],.{.r=r,.rate=rate,.len=len,.low=low});
    gloopsOf(lightGloop,light,gloops[deep.n[1]..],.{.r=r,.rate=rate,.len=len,.low=low});
    // the hum's pitch
    const base=vary(r,groanHz)*low;
    return.{
      .rate=rate,
      .hum=.{.rate=rate,.shape=.saw,.freq=base},
      .waver=.{.rate=rate,.freq=vary(r,waverHz)},
      .noise=.init(r.next()),
      .throat=.init(.band,throatHz[0]*low,throatQ,rate),
      .soft=.init(sapSoftHz,rate),
      .gloops=gloops,
      .base=base,
      .low=low,
      .len=len,
      .gain=vary(r,sap),
    };
  }
  /// what a kind's gloops are drawn within: the random numbers, the rate,
  /// the settling's length (samples) and the belly's lowering
  pub const Within=struct{r:*rng.Rng,rate:f32,len:u32,low:f32};
  /// `out` filled with gloops of `kind` (silent unless `used`)
  pub fn gloopsOf(kind:GloopKind,used:bool,out:[]Gloop,w:Within)void{
    // how many of the kind sound: none unless used
    const n=if(used)kind.n[0]+w.r.below(kind.n[1]-kind.n[0]+1)else 0;
    for(out,0..)|*g,i|g.*=.{
      .osc=.{.rate=w.rate},
      .base=w.r.range(kind.hz[0],kind.hz[1])*w.low,
      .start=if(i<n)m.floorTo(u32,w.r.range(kind.at[0],kind.at[1])*m.f(w.len))else m.maxInt(u32),
      .attack=m.floorTo(u32,gloopAttack*w.rate)+1,
      .fall=dsp.fall(w.r.range(kind.fall[0],kind.fall[1]),w.rate),
      .level=kind.level,
    };
  }
  /// mixes the settling into `out`, faded with the view; false once ended
  pub fn render(st:*Settle,out:[]f32,fade:*dsp.Smooth)bool{
    for(out)|*s|{
      if(st.at>=st.len)return false;
      // how far through the settling it is, 0..1
      const u=m.f(st.at)/m.f(st.len);
      if(st.at%retune==0)st.throat.tune(.band,m.lerp(throatHz[0],throatHz[1],m.smooth(u))*st.low,throatQ,st.rate);
      st.hum.freq=st.base*(1-groanSag*u)*(1+waver*st.waver.next());
      // swells early, sinks away slowly
      const sw=@sin(m.pi*m.pow(f32,u,0.6));
      // the groan: the hum and breath through the throat, swelling and sinking
      const groan=st.throat.tick(st.hum.next()+breathAmount*st.noise.next())*groanLevel*sw*sw;
      // the gloops summed
      var gl:f32=0;
      for(&st.gloops)|*g|gl+=g.tick(st.at);
      s.*+=st.soft.low(groan+gl)*st.gain*fade.next();
      st.at+=1;
    }
    return st.at<st.len;
  }
};
