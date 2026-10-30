//! the night's instruments: a glass chime struck high, bowed strings swelling under it, and a far choir singing "oo".
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: clamps, conversions, powers
const m=engine.core.math;
/// the engine's sound pieces: oscillators, filters, noise
const dsp=engine.core.dsp;
/// the seeded random numbers each voice draws from
const rng=engine.core.rng;
/// quieter than this, a voice has ended
const silent=lib.sound.silent;
/// a value nudged a little either way, so no two notes are alike
const vary=lib.sound.footstep.vary;
// ---- the chime: a small glass bell struck with a soft mallet ----
/// how many partials a chime rings with
const chimeParts=4;
/// its partials' pitches, as multiples of its note (a bell's: not
/// harmonic, which is what makes it glass and not string)
const chimeRatio=[chimeParts]f32{1,2.756,5.404,8.933};
/// each partial's level
const chimeLevel=[chimeParts]f32{1,0.42,0.2,0.08};
/// how long the note rings (s, ~63%); each higher partial dies this much faster
const chimeRing:f32=2.8;
/// how much faster each higher partial dies
const chimeDamp:f32=1.6;
/// a twin a hair sharp beating against the note: the glisten
const chimeTwin:f32=1.0016;
/// the twin's level
const chimeTwinLevel:f32=0.6;
/// the mallet's tick: a band of noise (Hz), how fast it falls (s), its level
/// (this one: the band's centre, Hz)
const malletHz:f32=7000;
/// how fast the tick falls (s)
const malletFall:f32=0.003;
/// the tick's level
const mallet:f32=0.25;
/// how long the strike takes to rise (s): soft, never a click
const chimeAttack:f32=0.004;
/// a chime's loudness
const chime:f32=0.016;
/// one chime struck: a few glassy partials and a beating twin dying away
pub const Chime=struct{
  /// its partials, and the twin last
  parts:[chimeParts+1]dsp.Sine,
  /// each one's level now, falling away
  amp:[chimeParts+1]f32,
  /// how much of its level each keeps a sample
  fall:[chimeParts+1]f32,
  /// the noise the mallet's tick is filtered from
  noise:dsp.Noise,
  /// the band shaping the tick
  tick:dsp.Biquad,
  /// the tick's level now, falling away
  knock:f32=1,
  /// how much of the tick's level is kept each sample
  knockFall:f32,
  /// samples still to wait before it is struck (a cascade's later notes)
  wait:u32,
  /// samples since it was struck
  at:u32=0,
  /// how many samples the strike's rise takes
  attack:u32,
  /// its loudness for its velocity
  gain:f32,
  /// a chime of MIDI `note` struck at velocity `vel` (0..1) after `wait`
  /// samples, its ring varied a little by `r`
  pub fn init(note:u8,vel:f32,wait:u32,r:*rng.Rng,rate:f32)Chime{
    // the note's pitch (Hz), and how long this one rings (s)
    const hz=dsp.noteToHz(m.f(note));
    const ring=vary(r,chimeRing);
    // the chime, its partials filled in below
    var c:Chime=.{
      .parts=undefined,
      .amp=undefined,
      .fall=undefined,
      .noise=.init(r.next()),
      .tick=.init(.band,malletHz,1.5,rate),
      .knockFall=@exp(-1/(malletFall*rate)),
      .wait=wait,
      .attack=m.floorTo(u32,chimeAttack*rate)+1,
      .gain=vel*chime,
    };
    for(0..chimeParts)|k|{
      // the partial's pitch: above Nyquist it is left out, not folded back
      const f=hz*chimeRatio[k];
      c.parts[k]=.init(f,rate);
      c.amp[k]=if(f<0.45*rate)chimeLevel[k]else 0;
      c.fall[k]=@exp(-1/(ring/(1+chimeDamp*m.f(k))*rate));
    }
    c.parts[chimeParts]=.init(hz*chimeTwin,rate);
    c.amp[chimeParts]=chimeTwinLevel;
    c.fall[chimeParts]=c.fall[0];
    return c;
  }
  /// mixes the chime into `out`; false once it has rung out
  pub fn render(c:*Chime,out:[]f32)bool{
    for(out)|*s|{
      if(c.wait>0){
        c.wait-=1;
        continue;
      }
      // how far through its rise it is, 0..1
      const rise=m.clamp01(m.f(c.at)/m.f(c.attack));
      c.at+|=1;
      // the partials summed, and the mallet's tick
      var y:f32=0;
      inline for(0..chimeParts+1)|k|{
        c.amp[k]*=c.fall[k];
        y+=c.parts[k].next()*c.amp[k];
      }
      c.knock*=c.knockFall;
      y+=c.tick.tick(c.noise.next())*mallet*c.knock;
      s.*+=y*rise*c.gain;
    }
    return c.wait>0 or c.amp[0]>silent;
  }
};
// ---- a swell: how a held voice rises and lets go ----
/// a held voice's loudness: rising toward 1 while held, falling to 0 once
/// let go, each along its own slow curve
const Swell=struct{
  /// its loudness now, 0..1
  level:f32=0,
  /// whether it is held (rising) or let go (falling)
  held:bool=true,
  /// how much of the way to 1 it keeps each sample while held
  rise:f32,
  /// how much of its level it keeps each sample once let go
  fall:f32,
  /// a swell taking about `attack` seconds to rise and `release` to fall
  fn init(attack:f32,release:f32,rate:f32)Swell{
    return.{.rise=@exp(-1/(attack*rate)),.fall=@exp(-1/(release*rate))};
  }
  /// its next level
  fn next(w:*Swell)f32{
    w.level=if(w.held)1-(1-w.level)*w.rise else w.level*w.fall;
    return w.level;
  }
  /// whether it has fallen silent after being let go
  fn done(w:*const Swell)bool{return!w.held and w.level<silent;}
};
// ---- the strings: a soft ensemble bowing one note ----
/// how many players bow each note
const bowers=3;
/// how far apart they are tuned (cents between neighbours)
const bowSpread:f32=7;
/// how long a note takes to swell in (s, ~63%)
const bowAttack:f32=1.6;
/// how long it takes to die away once let go (s, ~63%)
const bowRelease:f32=2.6;
/// the low-pass that keeps the bows soft and far (Hz)
const bowSoftHz:f32=1500;
/// how fast the ensemble's vibrato wavers (Hz)
const bowVibratoHz:f32=4.6;
/// how deep it wavers (cents)
const bowVibratoCents:f32=6;
/// a bowed note's loudness
const bow:f32=0.007;
/// one note of the strings: a few detuned saws, softened twice over,
/// swelling in and dying away
pub const Bow=struct{
  /// the players' saws
  saws:[bowers]dsp.Osc,
  /// each player's own pitch (Hz)
  base:[bowers]f32,
  /// the slow vibrato they share
  vibrato:dsp.Osc,
  /// the first low-pass
  softA:dsp.OnePole,
  /// the second, in series
  softB:dsp.OnePole,
  /// how loud it is now
  swell:Swell,
  /// its loudness for its velocity
  gain:f32,
  /// MIDI `note` bowed at velocity `vel` (0..1), its players starting
  /// apart in their cycles (drawn from `r`)
  pub fn init(note:u8,vel:f32,r:*rng.Rng,rate:f32)Bow{
    // the note's pitch (Hz)
    const hz=dsp.noteToHz(m.f(note));
    // the note, its players tuned below
    var b:Bow=.{
      .saws=undefined,
      .base=undefined,
      .vibrato=.{.rate=rate,.freq=vary(r,bowVibratoHz),.phase=r.float()},
      .softA=.init(bowSoftHz,rate),
      .softB=.init(bowSoftHz,rate),
      .swell=.init(vary(r,bowAttack),bowRelease,rate),
      .gain=vel*bow,
    };
    for(0..bowers)|k|{
      // how far this player is tuned (cents)
      const cents=(m.f(k)-(bowers-1)/2.0)*bowSpread;
      b.base[k]=hz*m.pow(f32,2,cents/1200);
      b.saws[k]=.{.rate=rate,.shape=.saw,.freq=b.base[k],.phase=r.float()};
    }
    return b;
  }
  /// let the note go: it dies away
  pub fn release(b:*Bow)void{b.swell.held=false;}
  /// mixes the note into `out`; false once it has died away
  pub fn render(b:*Bow,out:[]f32)bool{
    for(out)|*s|{
      // the vibrato's pitch ratio this sample
      const v=1+bowVibratoCents/1200*0.69*b.vibrato.next();
      // the players summed
      var y:f32=0;
      inline for(0..bowers)|k|{
        b.saws[k].freq=b.base[k]*v;
        y+=b.saws[k].next();
      }
      s.*+=b.softB.low(b.softA.low(y))*b.swell.next()*b.gain;
    }
    return!b.swell.done();
  }
};
// ---- the choir: far voices singing "oo" ----
/// how many voices sing each note
const singers=3;
/// how far apart they are tuned (cents between neighbours)
const singSpread:f32=9;
/// they start this far flat (cents) and glide up into the note
const scoop:f32=35;
/// how long that glide takes (s, ~63%)
const scoopTime:f32=0.35;
/// how fast each voice's vibrato wavers, drawn between these (Hz)
const singVibratoHz=[2]f32{4.6,5.6};
/// how deep it wavers once grown (cents)
const singVibratoCents:f32=14;
/// how long the vibrato takes to grow in (s, ~63%)
const vibratoGrow:f32=1.2;
/// how long a sung note takes to swell in (s, ~63%)
const singAttack:f32=1.4;
/// how long it takes to die away once let go (s, ~63%)
const singRelease:f32=2.2;
/// the "oo" vowel's three formants (Hz), how tightly each rings (q) and
/// how loud each is
/// (this one: the formants, Hz)
const formantHz=[3]f32{320,800,2500};
/// how tightly each rings (q)
const formantQ=[3]f32{5,7,9};
/// how loud each is
const formantLevel=[3]f32{1,0.35,0.1};
/// the breath: a little noise through the second formant
const breath:f32=0.06;
/// a sung note's loudness
const sing:f32=0.03;
/// one note of the choir: a few voices, scooping up into it, an "oo"
/// shaped out of them, a breath through it
pub const Sung=struct{
  /// the voices' saws
  saws:[singers]dsp.Osc,
  /// each voice's own pitch (Hz)
  base:[singers]f32,
  /// each voice's vibrato
  vibrato:[singers]dsp.Osc,
  /// the vowel's formants
  formants:[3]dsp.Biquad,
  /// the breath's noise
  noise:dsp.Noise,
  /// how far flat it still is (a share of `scoop`, 1 falling to 0)
  flat:f32=1,
  /// how much of the scoop is kept each sample
  scoopFall:f32,
  /// how far the vibrato has grown in (0 rising to 1)
  depth:f32=0,
  /// how much of the way to its full depth it keeps each sample
  depthRise:f32,
  /// how loud it is now
  swell:Swell,
  /// its loudness for its velocity
  gain:f32,
  /// MIDI `note` sung at velocity `vel` (0..1), its voices drawn apart by `r`
  pub fn init(note:u8,vel:f32,r:*rng.Rng,rate:f32)Sung{
    // the note's pitch (Hz)
    const hz=dsp.noteToHz(m.f(note));
    // the note, its voices tuned below
    var n:Sung=.{
      .saws=undefined,
      .base=undefined,
      .vibrato=undefined,
      .formants=undefined,
      .noise=.init(r.next()),
      .scoopFall=@exp(-1/(scoopTime*rate)),
      .depthRise=@exp(-1/(vibratoGrow*rate)),
      .swell=.init(singAttack,singRelease,rate),
      .gain=vel*sing,
    };
    for(0..singers)|k|{
      // how far this voice is tuned (cents)
      const cents=(m.f(k)-(singers-1)/2.0)*singSpread;
      n.base[k]=hz*m.pow(f32,2,cents/1200);
      n.saws[k]=.{.rate=rate,.shape=.saw,.freq=n.base[k],.phase=r.float()};
      n.vibrato[k]=.{.rate=rate,.freq=r.range(singVibratoHz[0],singVibratoHz[1]),.phase=r.float()};
    }
    for(&n.formants,0..)|*f,k|f.*=.init(.band,formantHz[k],formantQ[k],rate);
    return n;
  }
  /// let the note go: it dies away
  pub fn release(n:*Sung)void{n.swell.held=false;}
  /// mixes the note into `out`; false once it has died away
  pub fn render(n:*Sung,out:[]f32)bool{
    for(out)|*s|{
      n.flat*=n.scoopFall;
      n.depth=1-(1-n.depth)*n.depthRise;
      // the voices summed, each scooping and wavering
      var y:f32=0;
      inline for(0..singers)|k|{
        // this voice's bend this sample (cents)
        const cents=-scoop*n.flat+singVibratoCents*n.depth*n.vibrato[k].next();
        n.saws[k].freq=n.base[k]*(1+cents/1200*0.69);
        y+=n.saws[k].next();
      }
      y=y/singers+breath*n.noise.next();
      // the vowel shaped out of them
      var v:f32=0;
      inline for(0..3)|k|v+=n.formants[k].tick(y)*formantLevel[k];
      s.*+=v*n.swell.next()*n.gain;
    }
    return!n.swell.done();
  }
};
