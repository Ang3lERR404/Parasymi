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
    return.{.rise=dsp.fall(attack,rate),.fall=dsp.fall(release,rate)};
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
/// the strings seated as an orchestra's: the high ones to the left, the
/// low ones to the right, this note (MIDI, A3) in the middle
const seatMid:f32=57;
/// how many semitones from the middle reach the widest a note sits
const seatSpan:f32=24;
/// how wide the strings are seated (pan)
const seatWidth:f32=0.45;
/// how far apart a note's players sit (pan, from the first to the last)
const playerSpread:f32=0.5;
/// one note of the strings: a few detuned saws, each player in its own
/// seat, softened twice over, swelling in and dying away
pub const Bow=struct{
  /// the players' saws
  saws:[bowers]dsp.Osc,
  /// each player's own pitch (Hz)
  base:[bowers]f32,
  /// where each player sits between the speakers
  seats:[bowers]dsp.Frame,
  /// the slow vibrato they share
  vibrato:dsp.Osc,
  /// the first low-pass
  softA:dsp.StereoPole,
  /// the second, in series
  softB:dsp.StereoPole,
  /// how loud it is now
  swell:Swell,
  /// its loudness for its velocity
  gain:f32,
  /// MIDI `note` bowed at velocity `vel` (0..1), its players starting
  /// apart in their cycles (drawn from `r`), seated round where its
  /// strings sit
  pub fn init(note:u8,vel:f32,r:*rng.Rng,rate:f32)Bow{
    // the note's pitch (Hz), and where its strings sit
    const hz=dsp.noteToHz(m.f(note));
    const seat=m.clamp((seatMid-m.f(note))/seatSpan,-1,1)*seatWidth;
    // the note, its players tuned below
    var b:Bow=.{
      .saws=undefined,
      .base=undefined,
      .seats=undefined,
      .vibrato=.{.rate=rate,.freq=vary(r,bowVibratoHz),.phase=r.float()},
      .softA=.init(bowSoftHz,rate),
      .softB=.init(bowSoftHz,rate),
      .swell=.init(vary(r,bowAttack),bowRelease,rate),
      .gain=vel*bow,
    };
    for(0..bowers)|k|{
      // how far this player is along the desk (-0.5 .. 0.5), and how far it is tuned (cents)
      const along=m.f(k)/m.f(bowers-1)-0.5;
      const cents=(m.f(k)-m.f(bowers-1)/2)*bowSpread;
      b.base[k]=hz*m.pow(f32,2,cents/1200);
      b.saws[k]=.{.rate=rate,.shape=.saw,.freq=b.base[k],.phase=r.float()};
      b.seats[k]=dsp.spot(seat+along*playerSpread);
    }
    return b;
  }
  /// let the note go: it dies away
  pub fn release(b:*Bow)void{b.swell.held=false;}
  /// mixes the note into `out`; false once it has died away
  pub fn render(b:*Bow,out:[]dsp.Frame)bool{
    for(out)|*s|{
      // the vibrato's pitch ratio this sample
      const v=1+bowVibratoCents/1200*0.69*b.vibrato.next();
      // the players summed, each from its seat
      var y:dsp.Frame=@splat(0);
      inline for(0..bowers)|k|{
        b.saws[k].freq=b.base[k]*v;
        y+=dsp.put(b.seats[k],b.saws[k].next());
      }
      s.*+=b.softB.low(b.softA.low(y))*dsp.mid(b.swell.next()*b.gain);
    }
    return!b.swell.done();
  }
};
