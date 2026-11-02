//! the day's piano: a felt-hammered string struck and ringing.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: lerps, clamps, rounding
const m=engine.core.math;
/// the engine's sound pieces: sines, noise, filters, note pitches
const dsp=engine.core.dsp;
/// the seeded random numbers each voice draws from
const rng=engine.core.rng;
/// the second string's pitch, a hair sharp (a ratio)
const detune=lib.sound.score.detune;
/// the second string's level
const detuneLevel=lib.sound.score.detuneLevel;
/// how much duller a softer note is (its partials fall by this power)
const dull=lib.sound.score.dull;
/// the hammer's tick level
const hammer=lib.sound.score.hammer;
/// the hammer's tick pitch, in multiples of the note's
const hammerAt=lib.sound.score.hammerAt;
/// how fast the hammer's tick falls (s)
const hammerFall=lib.sound.score.hammerFall;
/// the highest the hammer's tick may go (Hz)
const hammerHz=lib.sound.score.hammerHz;
/// how many partials a plunk has
const harmonics=lib.sound.score.harmonics;
/// each partial's level
const harmonicLevel=lib.sound.score.harmonicLevel;
/// a plunk's loudness
const plunk=lib.sound.score.plunk;
/// a plunk's attack (s)
const plunkAttack=lib.sound.score.plunkAttack;
/// how much faster each higher partial dies
const plunkDamp=lib.sound.score.plunkDamp;
/// how long a plunk rings at the reference pitch (s)
const plunkFall=lib.sound.score.plunkFall;
/// the shortest and longest a plunk may ring (s)
const plunkFallSpan=lib.sound.score.plunkFallSpan;
/// the reference pitch a plunk's ring is set at (Hz)
const plunkRefHz=lib.sound.score.plunkRefHz;
/// the low-pass that softens a plunk (Hz)
const plunkSoftHz=lib.sound.score.plunkSoftHz;
/// quieter than this, a note has ended
const silent=lib.sound.silent;
/// how much each partial is stretched sharp
const stretch=lib.sound.score.stretch;
/// the piano heard from its bench: its strings across the speakers, low to
/// the left and high to the right, the middle of the keyboard (MIDI, D4)
/// in the middle
const keyMid:f32=62;
/// how many semitones from the middle reach the widest a note sits
const keySpan:f32=30;
/// how wide the strings reach (pan): a piano, not the whole room
const keyWidth:f32=0.5;
/// where MIDI `note` sits between the speakers (pan)
pub fn keyPan(note:f32)f32{return m.clamp((note-keyMid)/keySpan,-1,1)*keyWidth;}
/// one piano note: a plunk of a felt-hammered string
pub const Plunk=struct{
  /// the string's partials, and the second string last
  parts:[harmonics+1]dsp.Sine,
  /// each one's level now, 1 falling away
  amp:[harmonics+1]f32=@splat(1),
  /// how much of its level each keeps a sample
  fall:[harmonics+1]f32,
  /// how loud each is
  level:[harmonics+1]f32,
  /// the noise the hammer's tick is filtered from
  noise:dsp.Noise,
  /// the band-pass shaping the hammer's tick
  hammer:dsp.Biquad,
  /// the tick's level now, 1 falling away
  knock:f32=1,
  /// how much of the tick's level is kept each sample
  knockFall:f32,
  /// the low-pass softening the note
  soft:dsp.OnePole,
  /// samples played so far
  at:u32=0,
  /// how many samples the attack takes
  attack:u32,
  /// its loudness for its velocity
  gain:f32,
  /// where its string sits between the speakers
  place:dsp.Frame,
  /// a fresh note: MIDI `note` struck at velocity `vel` (0..1), softer
  /// notes duller, higher ones ringing shorter, sitting where its string does
  pub fn init(note:u8,vel:f32,r:*rng.Rng,rate:f32)Plunk{
    // the note's pitch (Hz), and how long it rings (s)
    const hz=dsp.noteToHz(m.f(note));
    const ring=m.clamp(plunkFall*@sqrt(plunkRefHz/hz),plunkFallSpan[0],plunkFallSpan[1]);
    // the note, its partials filled in below
    var p:Plunk=.{
      .parts=undefined,
      .fall=undefined,
      .level=undefined,
      .noise=.init(r.next()),
      .hammer=.init(.band,@min(hz*hammerAt,hammerHz),1.2,rate),
      .knockFall=dsp.fall(hammerFall,rate),
      .soft=.init(plunkSoftHz,rate),
      .attack=m.floorTo(u32,plunkAttack*rate)+1,
      .gain=vel*plunk,
      .place=dsp.spot(keyPan(m.f(note))),
    };
    for(0..harmonics)|k|{
      // the partial's number, from 1, and its stretched pitch
      const n=m.f(k+1);
      const f=hz*n*@sqrt(1+stretch*n*n);
      p.parts[k]=.init(f,rate);
      p.fall[k]=dsp.fall(ring/(1+plunkDamp*m.f(k)),rate);
      // above Nyquist a partial is left out, not folded back
      const heard:f32=if(f<0.45*rate)1 else 0;
      p.level[k]=harmonicLevel[k]*m.pow(f32,vel,dull*m.f(k))*heard;
    }
    p.parts[harmonics]=.init(hz*detune,rate);
    p.fall[harmonics]=p.fall[0];
    p.level[harmonics]=detuneLevel;
    return p;
  }
  /// mixes the note into `out`; false once it has ended
  pub fn render(p:*Plunk,out:[]dsp.Frame)bool{
    for(out)|*s|{
      // how far through its attack it is, 0..1
      const rise=m.clamp01(m.f(p.at)/m.f(p.attack));
      p.at+|=1;
      // the partials summed
      var y:f32=0;
      inline for(0..harmonics+1)|k|{
        p.amp[k]*=p.fall[k];
        y+=p.parts[k].next()*p.amp[k]*p.level[k];
      }
      p.knock*=p.knockFall;
      y+=p.hammer.tick(p.noise.next())*hammer*p.knock;
      s.*+=dsp.put(p.place,p.soft.low(y*rise)*p.gain);
    }
    return p.amp[0]>silent;
  }
};
