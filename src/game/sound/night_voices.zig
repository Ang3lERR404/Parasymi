//! the night's strings: a soft ensemble bowing each note of a chord, swelling in and dying away.
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
const bowers=4;
/// how far apart they are tuned (cents between neighbours)
const bowSpread:f32=7;
/// how long a note takes to swell in (s, ~63%)
const bowAttack:f32=1.6;
/// how long it takes to die away once let go (s, ~63%)
const bowRelease:f32=2.6;
/// the low-pass that keeps the bows soft and far (Hz)
const bowSoftHz:f32=2000;
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
      const cents=(m.f(k)-m.f(bowers-1)/2)*bowSpread;
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
