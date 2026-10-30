//! the sap settling, heard from inside the wolf (first person): a groan with gloops.
const lib=@import("../../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const dsp=engine.core.dsp;
const rng=engine.core.rng;
const silent=lib.sound.silent;
const vary=lib.sound.footstep.vary;
// ---- the sap settling (first person) ----
/// how long a settling lasts (s)
const settleLen=[2]f32{2.4,3.8};
/// seconds between settlings while the wolf stands and while it walks; the
/// first comes this soon after the view enters the eyes
pub const gapStill=[2]f32{3.5,8};
pub const gapWalk=[2]f32{9,18};
pub const gapFirst=[2]f32{1.2,3};
/// the wolf stands once no step has landed for this long (s)
pub const stillAfter:f32=1.2;
/// the groan: a low reedy hum (Hz) sagging this share as it settles,
/// wavering slowly (Hz, share), voiced through a throat (Hz) closing from
/// the first to the second, ringing this much (q); breath in it (noise
/// share) and its level. A full belly pulls it all this share lower.
const groanHz:f32=48;
const groanSag:f32=0.18;
const waverHz:f32=2.3;
const waver:f32=0.025;
const throatHz=[2]f32{260,150};
const throatQ:f32=3.5;
const breathAmount:f32=0.35;
const groanRate:f32=1.2;
const sapHeavy:f32=0.25;
/// samples between retunings of the closing throat
pub const retune=32;
/// a kind of gloop: how many (fewest, most), when (shares of the
/// settling), its pitch (Hz), its fall (s) and level
const GloopKind=struct{n:[2]u32,at:[2]f32,hz:[2]f32,fall:[2]f32,level:f32};
/// the deep ones every settling has, and the lighter, smaller ones that
/// come with only this share of settlings
pub const deep:GloopKind=.{.n=.{2,5},.at=.{0.1,0.65},.hz=.{110,210},.fall=.{0.06,0.12},.level=0.6};
const lightGloop:GloopKind=.{.n=.{1,2},.at=.{0.2,0.75},.hz=.{300,460},.fall=.{0.035,0.06},.level=0.35};
const lightChance:f32=0.25;
const gloopCount=deep.n[1]+lightGloop.n[1];
/// each gloop's pitch rises this share as it fades; its attack (s)
const gloopRise:f32=0.7;
const gloopAttack:f32=0.006;
/// heard from inside: what muffles it (Hz), its loudness, and how fast it
/// fades in and out with the view (s)
const sapSoftHz:f32=650;
const sap:f32=0.07;
pub const sapFade:f32=0.35;
/// seconds in `span` as samples
pub fn samples(r:*rng.Rng,span:[2]f32,rate:f32)u32{return m.floorTo(u32,r.range(span[0],span[1])*rate);}
/// one thick bubble rising through the sap
const Gloop=struct{
  osc:dsp.Osc,
  base:f32,
  /// the settling's sample it starts on (never, for a gloop not used)
  start:u32,
  attack:u32,
  fall:f32,
  level:f32,
  amp:f32=1,
  age:u32=0,
  fn tick(g:*Gloop,at:u32)f32{
    if(at<g.start or g.amp<silent)return 0;
    const rise=m.clamp01(m.f(g.age)/m.f(g.attack));
    if(g.age>=g.attack)g.amp*=g.fall;
    g.age+|=1;
    g.osc.freq=g.base*(1+gloopRise*(1-g.amp));
    return g.osc.next()*rise*g.amp*g.level;
  }
};
/// one settling of the sap playing out
pub const Settle=struct{
  rate:f32,
  hum:dsp.Osc,
  waver:dsp.Osc,
  noise:dsp.Noise,
  throat:dsp.Biquad,
  soft:dsp.OnePole,
  gloops:[gloopCount]Gloop,
  /// the hum's pitch before it sags, and the belly's lowering
  base:f32,
  low:f32,
  at:u32=0,
  len:u32,
  gain:f32,
  pub fn init(weight:f32,r:*rng.Rng,rate:f32)Settle{
    const low=1-sapHeavy*weight;
    const len=samples(r,settleLen,rate)+1;
    var gloops:[gloopCount]Gloop=undefined;
    const light=r.float()<lightChance;
    gloopsOf(deep,true,gloops[0..deep.n[1]],.{.r=r,.rate=rate,.len=len,.low=low});
    gloopsOf(lightGloop,light,gloops[deep.n[1]..],.{.r=r,.rate=rate,.len=len,.low=low});
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
  pub const Within=struct{r:*rng.Rng,rate:f32,len:u32,low:f32};
  /// `out` filled with gloops of `kind` (silent unless `used`)
  pub fn gloopsOf(kind:GloopKind,used:bool,out:[]Gloop,w:Within)void{
    const n=if(used)kind.n[0]+w.r.below(kind.n[1]-kind.n[0]+1)else 0;
    for(out,0..)|*g,i|g.*=.{
      .osc=.{.rate=w.rate},
      .base=w.r.range(kind.hz[0],kind.hz[1])*w.low,
      .start=if(i<n)m.floorTo(u32,w.r.range(kind.at[0],kind.at[1])*m.f(w.len))else m.maxInt(u32),
      .attack=m.floorTo(u32,gloopAttack*w.rate)+1,
      .fall=@exp(-1/(w.r.range(kind.fall[0],kind.fall[1])*w.rate)),
      .level=kind.level,
    };
  }
  /// mixes the settling into `out`, faded with the view; false once ended
  pub fn render(st:*Settle,out:[]f32,fade:*dsp.Smooth)bool{
    for(out)|*s|{
      if(st.at>=st.len)return false;
      const u=m.f(st.at)/m.f(st.len);
      if(st.at%retune==0)st.throat.tune(.band,m.lerp(throatHz[0],throatHz[1],m.smooth(u))*st.low,throatQ,st.rate);
      st.hum.freq=st.base*(1-groanSag*u)*(1+waver*st.waver.next());
      // swells early, sinks away slowly
      const sw=@sin(m.pi*m.pow(f32,u,0.6));
      const groan=st.throat.tick(st.hum.next()+breathAmount*st.noise.next())*groanRate*sw*sw;
      var gl:f32=0;
      for(&st.gloops)|*g|gl+=g.tick(st.at);
      s.*+=st.soft.low(groan+gl)*st.gain*fade.next();
      st.at+=1;
    }
    return st.at<st.len;
  }
};
