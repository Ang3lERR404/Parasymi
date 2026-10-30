//! the music's instruments: the piano plunk, the soft drum and the dark echo.
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
/// a drum's loudness
const drum=lib.sound.score.drum;
/// how long the drum's pitch drop takes (s)
const drumDrop=lib.sound.score.drumDrop;
/// how long the drum rings (s)
const drumFall=lib.sound.score.drumFall;
/// the drum's pitch, from the strike to where it drops (Hz)
const drumHz=lib.sound.score.drumHz;
/// the low-pass that muffles the drum (Hz)
const drumSoftHz=lib.sound.score.drumSoftHz;
/// how much duller a softer note is (its partials fall by this power)
const dull=lib.sound.score.dull;
/// the share of the rate the echo is kept at
const echoDown=lib.sound.score.echoDown;
/// how much of the echo feeds back into itself
const echoFeedback=lib.sound.score.echoFeedback;
/// how many slots the echo's ring holds
const echoLen=lib.sound.score.echoLen;
/// the low-pass that darkens the echo (Hz)
const echoSoftHz=lib.sound.score.echoSoftHz;
/// how many steps behind the echo sounds
const echoSteps=lib.sound.score.echoSteps;
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
/// the skin's noise level
const skin=lib.sound.score.skin;
/// how fast the skin's noise falls (s)
const skinFall=lib.sound.score.skinFall;
/// the skin's noise band (Hz)
const skinHz=lib.sound.score.skinHz;
/// how long one step lasts (s)
const stepS=lib.sound.score.stepS;
/// how much each partial is stretched sharp
const stretch=lib.sound.score.stretch;
/// a value nudged a little either way, so no two hits are alike
const vary=lib.sound.footstep.vary;
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
  /// a fresh note: MIDI `note` struck at velocity `vel` (0..1), softer
  /// notes duller, higher ones ringing shorter
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
      .knockFall=@exp(-1/(hammerFall*rate)),
      .soft=.init(plunkSoftHz,rate),
      .attack=m.floorTo(u32,plunkAttack*rate)+1,
      .gain=vel*plunk,
    };
    for(0..harmonics)|k|{
      // the partial's number, from 1, and its stretched pitch
      const n=m.f(k+1);
      const f=hz*n*@sqrt(1+stretch*n*n);
      p.parts[k]=.init(f,rate);
      p.fall[k]=@exp(-1/(ring/(1+plunkDamp*m.f(k))*rate));
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
  pub fn render(p:*Plunk,out:[]f32)bool{
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
      s.*+=p.soft.low(y*rise)*p.gain;
    }
    return p.amp[0]>silent;
  }
};
/// one soft tom
pub const Drum=struct{
  /// the body's sine
  osc:dsp.Osc,
  /// the noise the skin is filtered from
  noise:dsp.Noise,
  /// the band-pass shaping the skin
  skin:dsp.Biquad,
  /// the low-pass muffling it
  soft:dsp.OnePole,
  /// the pitch's drop still to fall, the body's and the skin's loudness
  drop:f32=1,
  /// the body's loudness now, 1 falling away
  body:f32=1,
  /// the skin's loudness now, 1 falling away
  hit:f32=1,
  /// how much of the pitch drop is left after each sample
  dropFall:f32,
  /// how much of the body's loudness is kept each sample
  bodyFall:f32,
  /// how much of the skin's loudness is kept each sample
  hitFall:f32,
  /// its loudness for its velocity
  gain:f32,
  /// a fresh hit at velocity `vel` (0..1), varied a little by `r`
  pub fn init(vel:f32,r:*rng.Rng,rate:f32)Drum{
    return.{
      .osc=.{.rate=rate},
      .noise=.init(r.next()),
      .skin=.init(.band,vary(r,skinHz),1,rate),
      .soft=.init(drumSoftHz,rate),
      .dropFall=@exp(-1/(drumDrop*rate)),
      .bodyFall=@exp(-1/(vary(r,drumFall)*rate)),
      .hitFall=@exp(-1/(skinFall*rate)),
      .gain=vary(r,vel)*drum,
    };
  }
  /// mixes the hit into `out`; false once it has rung out
  pub fn render(d:*Drum,out:[]f32)bool{
    for(out)|*s|{
      d.osc.freq=m.lerp(drumHz[1],drumHz[0],d.drop);
      d.drop*=d.dropFall;
      d.body*=d.bodyFall;
      d.hit*=d.hitFall;
      // the body and the skin, this sample
      const y=d.osc.next()*d.body+d.skin.tick(d.noise.next())*skin*d.hit;
      s.*+=d.soft.low(y)*d.gain;
    }
    return d.body>silent;
  }
};
/// an echo kept at a quarter of the rate in a ring of its own
pub const Echo=struct{
  /// the ring of slots
  buf:[echoLen]f32=@splat(0),
  /// the slot written next
  at:usize=0,
  /// samples summed toward the next slot
  sum:f32=0,
  /// how many samples are in that sum
  sub:u32=0,
  /// slots behind
  delay:usize,
  /// the low-pass darkening what comes back
  soft:dsp.OnePole,
  /// an echo `echoSteps` steps long at `rate` samples a second
  pub fn init(rate:f32)Echo{
    // the delay in slots
    const d=m.floorTo(usize,echoSteps*stepS*rate/echoDown);
    return.{.delay=m.clamp(d,2,echoLen-2),.soft=.init(echoSoftHz,rate)};
  }
  /// `x` in, what it heard `delay` slots ago out (between two slots)
  pub fn tick(e:*Echo,x:f32)f32{
    // the slot read from, and what it heard there, eased between two slots
    const back=e.at+echoLen-e.delay;
    const y=m.lerp(e.buf[back%echoLen],e.buf[(back+1)%echoLen],m.f(e.sub)/echoDown);
    e.sum+=x;
    e.sub+=1;
    if(e.sub==echoDown){
      e.buf[e.at]=e.sum/echoDown+echoFeedback*y;
      e.at=(e.at+1)%echoLen;
      e.sum=0;
      e.sub=0;
    }
    return e.soft.low(y);
  }
};
