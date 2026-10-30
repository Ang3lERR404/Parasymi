//! the music's instruments: the piano plunk, the soft drum and the dark echo.
const lib=@import("../../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const dsp=engine.core.dsp;
const rng=engine.core.rng;
const detune=lib.sound.score.detune;
const detuneLevel=lib.sound.score.detuneLevel;
const drum=lib.sound.score.drum;
const drumDrop=lib.sound.score.drumDrop;
const drumFall=lib.sound.score.drumFall;
const drumHz=lib.sound.score.drumHz;
const drumSoftHz=lib.sound.score.drumSoftHz;
const dull=lib.sound.score.dull;
const echoDown=lib.sound.score.echoDown;
const echoFeedback=lib.sound.score.echoFeedback;
const echoLen=lib.sound.score.echoLen;
const echoSoftHz=lib.sound.score.echoSoftHz;
const echoSteps=lib.sound.score.echoSteps;
const hammer=lib.sound.score.hammer;
const hammerAt=lib.sound.score.hammerAt;
const hammerFall=lib.sound.score.hammerFall;
const hammerHz=lib.sound.score.hammerHz;
const harmonics=lib.sound.score.harmonics;
const harmonicLevel=lib.sound.score.harmonicLevel;
const plunk=lib.sound.score.plunk;
const plunkAttack=lib.sound.score.plunkAttack;
const plunkDamp=lib.sound.score.plunkDamp;
const plunkFall=lib.sound.score.plunkFall;
const plunkFallSpan=lib.sound.score.plunkFallSpan;
const plunkRefHz=lib.sound.score.plunkRefHz;
const plunkSoftHz=lib.sound.score.plunkSoftHz;
const silent=lib.sound.silent;
const skin=lib.sound.score.skin;
const skinFall=lib.sound.score.skinFall;
const skinHz=lib.sound.score.skinHz;
const stepS=lib.sound.score.stepS;
const stretch=lib.sound.score.stretch;
const vary=lib.sound.footstep.vary;
/// one piano note: a plunk of a felt-hammered string
pub const Plunk=struct{
  parts:[harmonics+1]dsp.Sine,
  amp:[harmonics+1]f32=@splat(1),
  fall:[harmonics+1]f32,
  level:[harmonics+1]f32,
  noise:dsp.Noise,
  hammer:dsp.Biquad,
  knock:f32=1,
  knockFall:f32,
  soft:dsp.OnePole,
  at:u32=0,
  attack:u32,
  gain:f32,
  pub fn init(note:u8,vel:f32,r:*rng.Rng,rate:f32)Plunk{
    const hz=dsp.noteToHz(m.f(note));
    const ring=m.clamp(plunkFall*@sqrt(plunkRefHz/hz),plunkFallSpan[0],plunkFallSpan[1]);
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
      const rise=m.clamp01(m.f(p.at)/m.f(p.attack));
      p.at+|=1;
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
  osc:dsp.Osc,
  noise:dsp.Noise,
  skin:dsp.Biquad,
  soft:dsp.OnePole,
  /// the pitch's drop still to fall, the body's and the skin's loudness
  drop:f32=1,
  body:f32=1,
  hit:f32=1,
  dropFall:f32,
  bodyFall:f32,
  hitFall:f32,
  gain:f32,
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
  pub fn render(d:*Drum,out:[]f32)bool{
    for(out)|*s|{
      d.osc.freq=m.lerp(drumHz[1],drumHz[0],d.drop);
      d.drop*=d.dropFall;
      d.body*=d.bodyFall;
      d.hit*=d.hitFall;
      const y=d.osc.next()*d.body+d.skin.tick(d.noise.next())*skin*d.hit;
      s.*+=d.soft.low(y)*d.gain;
    }
    return d.body>silent;
  }
};
/// an echo kept at a quarter of the rate in a ring of its own
pub const Echo=struct{
  buf:[echoLen]f32=@splat(0),
  at:usize=0,
  /// samples summed toward the next slot
  sum:f32=0,
  sub:u32=0,
  /// slots behind
  delay:usize,
  soft:dsp.OnePole,
  pub fn init(rate:f32)Echo{
    const d=m.floorTo(usize,echoSteps*stepS*rate/echoDown);
    return.{.delay=m.clamp(d,2,echoLen-2),.soft=.init(echoSoftHz,rate)};
  }
  /// `x` in, what it heard `delay` slots ago out (between two slots)
  pub fn tick(e:*Echo,x:f32)f32{
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
