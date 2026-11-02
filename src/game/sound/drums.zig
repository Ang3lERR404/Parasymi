//! the day's drums, played big: taiko struck with heavy sticks, tuned timpani rolled into the phrase, a cymbal swelling to a crash.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: clamps, lerps, conversions
const m=engine.core.math;
/// the engine's sound pieces: oscillators, noise, filters
const dsp=engine.core.dsp;
/// the seeded random numbers each hit draws from
const rng=engine.core.rng;
/// quieter than this, a hit has rung out
const silent=lib.sound.silent;
/// a value nudged a little either way, so no two hits are alike
const vary=lib.sound.footstep.vary;
// ---- the taiko: a great barrel drum, its skin hit hard ----
/// how many of the skin's modes ring
const skinModes=4;
/// the skin's modes, as multiples of its pitch (a membrane's: not harmonic)
const skinRatio=[skinModes]f32{1,1.59,2.14,2.65};
/// how loud each mode rings
const skinLevel=[skinModes]f32{1,0.45,0.25,0.12};
/// how much faster each higher mode dies
const skinDamp:f32=1.4;
/// the stroke bends the pitch this far sharp (a ratio), falling back in this (s)
/// (this one: the bend, a ratio)
const bend:f32=1.5;
/// how fast it falls back (s)
const bendFall:f32=0.025;
/// the stick on the hide: noise darkened under this (Hz), falling in this (s), this loud
/// (this one: the low-pass, Hz)
const thwackHz:f32=1400;
/// how fast it falls (s)
const thwackFall:f32=0.012;
/// how loud it is
const thwack:f32=0.6;
/// how hard the body is driven into its soft clip (weight, not distortion)
const drive:f32=1.6;
/// a taiko's loudness
const taiko:f32=0.026;
/// one taiko hit: the skin's modes, bent sharp by the stroke, a thwack of
/// the stick, the whole driven warm
pub const Taiko=struct{
  /// the skin's modes
  modes:[skinModes]dsp.Osc,
  /// each mode's resting pitch (Hz)
  base:[skinModes]f32,
  /// each mode's level now, falling away
  amp:[skinModes]f32,
  /// how much of its level each keeps a sample
  fall:[skinModes]f32,
  /// how much of the stroke's bend is left (1 falling to 0)
  bent:f32=1,
  /// how much of the bend is kept each sample
  bentFall:f32,
  /// the noise the thwack is made of
  noise:dsp.Noise,
  /// the low-pass darkening it
  dark:dsp.OnePole,
  /// the thwack's level now, falling away
  hit:f32=1,
  /// how much of the thwack is kept each sample
  hitFall:f32,
  /// its loudness for its velocity
  gain:f32,
  /// where it stands between the speakers
  place:dsp.Frame,
  /// a drum pitched at `hz`, ringing `ring` seconds, struck at velocity
  /// `vel` (0..1), standing at `pan`
  pub fn init(hz:f32,ring:f32,vel:f32,pan:f32,r:*rng.Rng,rate:f32)Taiko{
    // the hit, its modes tuned below
    var t:Taiko=.{
      .modes=undefined,
      .base=undefined,
      .amp=undefined,
      .fall=undefined,
      .bentFall=dsp.fall(bendFall,rate),
      .noise=.init(r.next()),
      .dark=.init(thwackHz,rate),
      .hitFall=dsp.fall(thwackFall,rate),
      .gain=vel*taiko,
      .place=dsp.spot(pan),
    };
    // this drum's pitch, a hair off its neighbours'
    const f=vary(r,hz);
    for(0..skinModes)|k|{
      t.base[k]=f*skinRatio[k];
      t.modes[k]=.{.rate=rate,.freq=t.base[k]};
      // a harder stroke wakes the higher modes more
      t.amp[k]=skinLevel[k]*m.pow(f32,vel,0.5*m.f(k));
      t.fall[k]=dsp.fall(ring/(1+skinDamp*m.f(k)),rate);
    }
    return t;
  }
  /// mixes the hit into `out`; false once it has rung out
  pub fn render(t:*Taiko,out:[]dsp.Frame)bool{
    for(out)|*s|{
      t.bent*=t.bentFall;
      // the pitch ratio the stroke still bends it by
      const b=1+(bend-1)*t.bent;
      // the modes summed, and the stick's thwack
      var y:f32=0;
      inline for(0..skinModes)|k|{
        t.modes[k].freq=t.base[k]*b;
        t.amp[k]*=t.fall[k];
        y+=t.modes[k].next()*t.amp[k];
      }
      t.hit*=t.hitFall;
      y+=t.dark.low(t.noise.next())*thwack*t.hit;
      s.*+=dsp.put(t.place,dsp.softClip(y*drive)*t.gain);
    }
    return t.amp[0]>silent;
  }
};
// ---- the timpani: a tuned kettle drum under a felt mallet ----
/// how many of the kettle's modes ring
const kettleModes=5;
/// its modes, as multiples of its note (tuned near harmonic, as a
/// kettle's air makes them)
const kettleRatio=[kettleModes]f32{1,1.5,1.98,2.44,2.94};
/// how loud each mode rings
const kettleLevel=[kettleModes]f32{1,0.6,0.35,0.2,0.1};
/// how long its note rings (s, ~63%)
const kettleRing:f32=1.8;
/// how much faster each higher mode dies
const kettleDamp:f32=0.9;
/// the felt: a soft thump of noise darkened under this (Hz), falling in this (s)
/// (this one: the low-pass, Hz)
const feltHz:f32=600;
/// how fast it falls (s)
const feltFall:f32=0.008;
/// how loud it is
const felt:f32=0.5;
/// a timpani stroke's loudness
const timpani:f32=0.022;
/// one timpani stroke: the kettle's modes ringing at its note, a soft felt thump
pub const Timpani=struct{
  /// the kettle's modes
  modes:[kettleModes]dsp.Sine,
  /// each mode's level now, falling away
  amp:[kettleModes]f32,
  /// how much of its level each keeps a sample
  fall:[kettleModes]f32,
  /// the noise the felt's thump is made of
  noise:dsp.Noise,
  /// the low-pass darkening it
  dark:dsp.OnePole,
  /// the thump's level now, falling away
  hit:f32=1,
  /// how much of the thump is kept each sample
  hitFall:f32,
  /// samples still to wait before it is struck (a roll's later strokes)
  wait:u32,
  /// its loudness for its velocity
  gain:f32,
  /// where its kettle stands between the speakers
  place:dsp.Frame,
  /// MIDI `note` struck at velocity `vel` (0..1) after `wait` samples, its
  /// kettle standing at `pan`
  pub fn init(note:u8,vel:f32,wait:u32,pan:f32,r:*rng.Rng,rate:f32)Timpani{
    // the note's pitch (Hz)
    const hz=dsp.noteToHz(m.f(note));
    // the stroke, its modes tuned below
    var t:Timpani=.{
      .modes=undefined,
      .amp=undefined,
      .fall=undefined,
      .noise=.init(r.next()),
      .dark=.init(feltHz,rate),
      .hitFall=dsp.fall(feltFall,rate),
      .wait=wait,
      .gain=vel*timpani,
      .place=dsp.spot(pan),
    };
    for(0..kettleModes)|k|{
      t.modes[k]=.init(hz*kettleRatio[k],rate);
      t.amp[k]=kettleLevel[k]*m.pow(f32,vel,0.4*m.f(k));
      t.fall[k]=dsp.fall(kettleRing/(1+kettleDamp*m.f(k)),rate);
    }
    return t;
  }
  /// mixes the stroke into `out`; false once it has rung out
  pub fn render(t:*Timpani,out:[]dsp.Frame)bool{
    for(out)|*s|{
      if(t.wait>0){
        t.wait-=1;
        continue;
      }
      // the modes summed, and the felt's thump
      var y:f32=0;
      inline for(0..kettleModes)|k|{
        t.amp[k]*=t.fall[k];
        y+=t.modes[k].next()*t.amp[k];
      }
      t.hit*=t.hitFall;
      y+=t.dark.low(t.noise.next())*felt*t.hit;
      s.*+=dsp.put(t.place,y*t.gain);
    }
    return t.wait>0 or t.amp[0]>silent;
  }
};
// ---- the cymbal: a suspended cymbal rolled up to a crash ----
/// how many square partials ring in its metal (inharmonic, as a cymbal's)
const metalParts=6;
/// their pitches (Hz)
const metalHz=[metalParts]f32{410.6,608.8,739.2,1045.4,1080,1600};
/// the metal heard above this (Hz)
const metalHigh:f32=3000;
/// the hiss above this (Hz)
const hissHigh:f32=5000;
/// how loud the hiss is against the metal
const hiss:f32=0.8;
/// how quiet it starts (a share of the crash)
const swellFrom:f32=0.02;
/// the crash rings this long (s, ~63%)
const crashRing:f32=1.6;
/// the cymbal's loudness
const cymbal:f32=0.02;
/// how far either side of where it hangs its metal rings (pan)
const cymbalWidth=lib.sound.score.cymbalWidth;
/// one cymbal: a roll swelling up out of nothing to a crash, ringing away,
/// its metal wide: half its partials and one stream of hiss to one side of
/// where it hangs, the rest to the other
pub const Cymbal=struct{
  /// the metal's square partials (the even ones its left half, the odd its right)
  metal:[metalParts]dsp.Osc,
  /// the noise of its left half's hiss
  noise:dsp.Noise,
  /// the noise of its right half's hiss
  noiseRight:dsp.Noise,
  /// what keeps only the metal's top, each half
  metalHp:dsp.StereoBiquad,
  /// what keeps only the hiss's top, each half
  hissHp:dsp.StereoBiquad,
  /// where its left and its right half ring between the speakers
  sides:[2]dsp.Frame,
  /// samples still to swell before the crash (0: it has crashed)
  swell:u32,
  /// samples the whole swell takes
  swellLen:u32,
  /// how loud it is after the crash, falling away
  ring:f32=1,
  /// how much of that is kept each sample
  ringFall:f32,
  /// its loudness for its velocity
  gain:f32,
  /// a roll swelling for `len` samples to a crash at velocity `vel` (0:
  /// a crash at once), hanging at `pan`
  pub fn init(vel:f32,len:u32,pan:f32,r:*rng.Rng,rate:f32)Cymbal{
    // the cymbal, its partials tuned below
    var c:Cymbal=.{
      .metal=undefined,
      .noise=.init(r.next()),
      .noiseRight=.init(r.next()),
      .metalHp=.init(.high,metalHigh,0.7,rate),
      .hissHp=.init(.high,hissHigh,0.7,rate),
      .sides=.{dsp.spot(pan-cymbalWidth),dsp.spot(pan+cymbalWidth)},
      .swell=len,
      .swellLen=len,
      .ringFall=dsp.fall(vary(r,crashRing),rate),
      .gain=vel*cymbal,
    };
    for(&c.metal,0..)|*o,k|o.*=.{.rate=rate,.shape=.square,.freq=vary(r,metalHz[k])};
    return c;
  }
  /// mixes the cymbal into `out`; false once it has rung out
  pub fn render(c:*Cymbal,out:[]dsp.Frame)bool{
    for(out)|*s|{
      // how loud it is now: swelling (rising ever faster), or ringing away
      var lv:f32=undefined;
      if(c.swell>0){
        // how far through the swell, 0..1
        const k=1-m.f(c.swell)/m.f(c.swellLen);
        lv=swellFrom+(1-swellFrom)*k*k*k*0.55;
        c.swell-=1;
      }else{
        c.ring*=c.ringFall;
        lv=c.ring;
      }
      // each half's metal summed, then each half's top and its hiss (each
      // partial and stream heard in one place, so as loud in all as one was)
      var halves:dsp.Frame=@splat(0);
      inline for(0..metalParts)|k|halves[k%2]+=c.metal[k].next();
      const y=c.metalHp.tick(halves*dsp.mid(1/m.f(metalParts)))+c.hissHp.tick(.{c.noise.next(),c.noiseRight.next()})*dsp.mid(hiss/m.sqrt2);
      s.*+=(dsp.put(c.sides[0],y[0])+dsp.put(c.sides[1],y[1]))*dsp.mid(lv*c.gain);
    }
    return c.swell>0 or c.ring>silent;
  }
};
