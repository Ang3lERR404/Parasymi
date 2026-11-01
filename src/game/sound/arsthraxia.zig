//! the arsthraxia's working: a flower thinking, glass sung by its turning whorls over a thrum of thought.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: lerps, easing, clamps, powers
const m=engine.core.math;
/// the engine's sound pieces: oscillators, noise, filters, smoothing
const dsp=engine.core.dsp;
/// the seeded random numbers each voice draws from
const rng=engine.core.rng;
/// samples between retunings of a swept filter
const retune=lib.sound.sap.retune;
/// a span of seconds drawn as samples
const samples=lib.sound.sap.samples;
/// quieter than this (before its loudness), the faded voice has ended
const fadeSilent:f32=1e-3;
/// a value nudged a little either way, so no two plays are alike
const vary=lib.sound.footstep.vary;
// ---- the glass: each whorl of its flower a wine glass sung by a wet finger ----
// decision: rubbed glass, not saws: the turning whorls sing like a finger
// round a glass rim, each one two tones a hair apart so they swell and
// fade against each other as the whorls turn against each other
/// each glass's note (MIDI): the outer whorl on A4, the inner cup on E5,
/// the fifth and the second of the music's D Lydian
const glassNote=m.Vice(f32,2){69,76};
/// how fast each glass's two tones beat against each other (Hz): the outer
/// whorl slow, the cup faster, as they turn (structures/arsthraxia.zig)
const glassBeat=m.Vice(f32,2){0.35,0.6};
/// how much faster they beat while it is fed (a share more at full feed)
const glassBeatFed:f32=0.5;
/// each glass's level in the mix: the outer whorl fuller than the cup
const glassLevel=m.Vice(f32,2){1,0.6};
/// a rubbed glass's partials: its harmonics, as shares of its pitch
const glassPartials=[_]f32{1,2,3};
/// each partial's level: nearly a pure tone
const glassPartialLevel=[_]f32{1,0.16,0.05};
/// the finger's friction: noise rung at the glass's pitch, how tightly (q)
const rubQ:f32=40;
/// how much of the friction is heard against the tone
const rub:f32=0.5;
/// how much the finger's pressure wavers the glass's loudness (a share)
const pressure:f32=0.15;
/// how slowly the finger's pressure wavers, drawn between these (Hz)
const pressureHz=m.Vice(f32,2){0.2,0.45};
/// the low-pass over the glass, unfed and fully fed (Hz): brighter fed
const glassSoftHz=m.Vice(f32,2){1600,3200};
/// the glass's level in the mix
const glass:f32=0.5;
// ---- the thrum: thought climbing the nerves, felt as a slow low pulse ----
/// how often a pulse of thought passes up a nerve (Hz): part.vert's
/// NERVE_RISE (rad/s) as cycles
const thrumRate:f32=7.0/m.tau;
/// how narrow each pulse is: part.vert's same power over its sine
const thrumSharp:f32=6;
/// the thrum's note (MIDI): D2, the music's key two octaves down
const thrumNote:f32=38;
/// how far its pitch rises through each pulse as it climbs (a share)
const thrumBend:f32=0.12;
/// how much of its octave is heard over it
const thrumOctave:f32=0.35;
/// the low-pass that rounds it (Hz)
const thrumSoftHz:f32=400;
/// the thrum's level in the mix
const thrum:f32=0.7;
// ---- the wisps: breath drawn in to the core ----
/// how many wisps may whisper at once
const wispCount=3;
/// seconds between wisps, unfed
const wispGap=m.Vice(f32,2){0.6,1.6};
/// how much sooner they come at full feed (a share of the gap)
const wispGapFed:f32=0.45;
/// how long a wisp is drawn in for (s)
const wispLen=m.Vice(f32,2){0.7,1.3};
/// where a wisp's whisper starts, high and airy (Hz)
const wispFrom=m.Vice(f32,2){2600,3800};
/// where it ends, drawn down into the core (Hz)
const wispTo=m.Vice(f32,2){650,1000};
/// how tightly it whispers (q)
const wispQ:f32=4;
/// the wisps' level in the mix
const wisp:f32=0.9;
// ---- the core: a soft hum swelling as the unit condenses ----
/// the core's two notes (MIDI): D3 and A3 under the glass
const coreNote=m.Vice(f32,2){50,57};
/// how slowly its pitch wavers (Hz) and how far (cents)
const coreWaverHz:f32=0.3;
/// how far its pitch wavers (cents)
const coreWaver:f32=6;
/// how loud it is as a unit starts, a share of when it is condensed
const coreFrom:f32=0.15;
/// the core's level in the mix
const core:f32=0.45;
// ---- the whole ----
/// how long it takes to hum in, or fade away when the work stops (s, ~63%)
const fadeS:f32=0.8;
/// the whole voice's loudness
const res:f32=0.022;
/// how much louder it grows while fed (a share at full feed)
const resFed:f32=0.25;
/// one glass: two tones a hair apart, each a nearly pure tone, sung by friction
const Glass=struct{
  /// the first tone's partials
  a:[glassPartials.len]dsp.Osc,
  /// the second tone's partials, a beat above
  b:[glassPartials.len]dsp.Osc,
  /// the finger's friction, rung at its pitch
  rub:dsp.Biquad,
  /// the finger's pressure, slowly wavering
  pressure:dsp.Osc,
  /// its pitch (Hz)
  hz:f32,
  /// how fast its two tones beat (Hz)
  beat:f32,
  /// the glass of note `note` beating at `beat` Hz, its pressure drawn from `r`
  fn init(note:f32,beat:f32,r:*rng.Rng,rate:f32)Glass{
    // its pitch
    const hz=dsp.noteToHz(note);
    // each partial's two tones, filled in below
    var a:[glassPartials.len]dsp.Osc=undefined;
    var b:[glassPartials.len]dsp.Osc=undefined;
    for(glassPartials,0..)|p,k|{
      a[k]=.{.rate=rate,.freq=hz*p,.phase=r.float()};
      b[k]=.{.rate=rate,.freq=(hz+beat)*p,.phase=r.float()};
    }
    return.{
      .a=a,
      .b=b,
      .rub=.init(.band,hz,rubQ,rate),
      .pressure=.{.rate=rate,.freq=r.range(pressureHz[0],pressureHz[1]),.phase=r.float()},
      .hz=hz,
      .beat=beat,
    };
  }
  /// its next sample, its two tones beating `speed` times faster than at
  /// rest, the friction rung from noise `n`
  fn tick(g:*Glass,speed:f32,n:f32)f32{
    // the tones summed, the second a beat above the first
    var y:f32=0;
    for(glassPartials,glassPartialLevel,0..)|p,l,k|{
      g.b[k].freq=(g.hz+g.beat*speed)*p;
      y+=(g.a[k].next()+g.b[k].next())*l;
    }
    // the finger's pressure this sample
    const press=1-pressure+pressure*g.pressure.next();
    return(y*0.5+g.rub.tick(n)*rub)*press;
  }
};
/// one wisp: a whisper of breath drawn down into the core
const Wisp=struct{
  /// its band of noise, swept down
  band:dsp.Biquad,
  /// where its sweep starts and ends (Hz)
  from:f32,
  /// where its sweep ends (Hz)
  to:f32,
  /// how long it lasts (samples)
  len:u32,
  /// samples played so far
  at:u32=0,
  /// a fresh wisp, its sweep and length drawn from `r`
  fn init(r:*rng.Rng,rate:f32)Wisp{
    // where it starts
    const from=r.range(wispFrom[0],wispFrom[1]);
    return.{
      .band=.init(.band,from,wispQ,rate),
      .from=from,
      .to=r.range(wispTo[0],wispTo[1]),
      .len=samples(r,wispLen,rate),
    };
  }
  /// its next sample from noise `n`; null once it has been drawn in
  fn tick(w:*Wisp,n:f32,rate:f32)?f32{
    if(w.at>=w.len)return null;
    // how far it has been drawn in (0..1)
    const x=m.f(w.at)/m.f(w.len);
    if(w.at%retune==0)w.band.tune(.band,w.from*m.pow(f32,w.to/w.from,x),wispQ,rate);
    w.at+=1;
    // it swells in and is gone as it reaches the core
    const s=@sin(m.pi*x);
    return w.band.tick(n)*s*s;
  }
};
/// the working voice: the glass, the thrum, the wisps and the core, its
/// core swelling with the unit's progress and all of it brighter as it is fed
pub const Research=struct{
  /// samples per second
  rate:f32,
  /// its own random numbers
  r:rng.Rng,
  /// the noise the friction and wisps are drawn from
  noise:dsp.Noise,
  /// the outer whorl's glass and the inner cup's
  glasses:[2]Glass,
  /// the low-pass over the glass, brighter fed
  glassSoft:dsp.OnePole,
  /// where the thrum stands in its pulse, 0..1
  thrumPhase:f32=0,
  /// the thrum's tone
  thrumOsc:dsp.Osc,
  /// the thrum's octave
  thrumUp:dsp.Osc,
  /// the low-pass that rounds the thrum
  thrumSoft:dsp.OnePole,
  /// the wisps whispering now; null is free
  wisps:[wispCount]?Wisp=@splat(null),
  /// samples until the next wisp
  wispWait:u32,
  /// the core's two tones
  coreOsc:[2]dsp.Osc,
  /// the core's two resting pitches (Hz)
  coreHz:m.Vice(f32,2),
  /// the core's slow waver
  coreWaver:dsp.Osc,
  /// the core's level, gliding with the unit's progress
  coreSwell:dsp.Smooth,
  /// the whole voice's level: in while it works, fading when it stops
  level:dsp.Smooth,
  /// samples played so far (wraps), for when to retune the glass's low-pass
  at:u32=0,
  /// this voice's loudness, varied a little each time
  gain:f32,
  /// a fresh voice humming in, its glasses, wisps and loudness drawn from `r`
  pub fn init(r:*rng.Rng,rate:f32)Research{
    // its own random numbers, drawn first
    var own:rng.Rng=.init(r.next());
    // the two glasses, each its whorl's own
    const glasses=[2]Glass{.init(glassNote[0],glassBeat[0],&own,rate),.init(glassNote[1],glassBeat[1],&own,rate)};
    // the thrum's pitch
    const th=dsp.noteToHz(thrumNote);
    // the first wisp's wait
    const wait=samples(&own,wispGap,rate);
    var lv:dsp.Smooth=.init(0,fadeS,rate);
    lv.target=1;
    return.{
      .rate=rate,
      .r=own,
      .noise=.init(own.next()),
      .glasses=glasses,
      .glassSoft=.init(glassSoftHz[0],rate),
      .thrumOsc=.{.rate=rate,.freq=th},
      .thrumUp=.{.rate=rate,.freq=th*2},
      .thrumSoft=.init(thrumSoftHz,rate),
      .wispWait=wait,
      .coreOsc=.{.{.rate=rate,.freq=dsp.noteToHz(coreNote[0])},.{.rate=rate,.freq=dsp.noteToHz(coreNote[1])}},
      .coreHz=.{dsp.noteToHz(coreNote[0]),dsp.noteToHz(coreNote[1])},
      .coreWaver=.{.rate=rate,.freq=coreWaverHz},
      .coreSwell=.init(coreFrom,fadeS,rate),
      .level=lv,
      .gain=vary(r,res),
    };
  }
  /// the work has stopped: it fades away, and `render` ends it once silent
  pub fn stop(rs:*Research)void{rs.level.target=0;}
  /// the work goes on: it hums back in if it was fading
  pub fn go(rs:*Research)void{rs.level.target=1;}
  /// mixes the next `out.len` samples into `out`, the core swelling with
  /// the unit's `progress` (0..1), all of it brighter, quicker and a little
  /// louder as it is `fed` (0..1); returns false once it has faded away
  pub fn render(rs:*Research,out:[]f32,progress:f32,fed:f32)bool{
    // how fast the glass beats, how bright it is, and how loud the core is, for this feed and progress
    const speed=1+glassBeatFed*fed;
    const bright=m.lerp(glassSoftHz[0],glassSoftHz[1],fed);
    rs.coreSwell.target=m.lerp(coreFrom,1,m.smooth(m.clamp01(progress)));
    // how far the thrum's pitch moves on one sample
    const thStep=thrumRate/rs.rate;
    // the thrum's resting pitch
    const thHz=dsp.noteToHz(thrumNote);
    for(out)|*s|{
      if(rs.at%retune==0)rs.glassSoft.a=dsp.OnePole.coeff(bright,rs.rate);
      rs.at+%=1;
      rs.spawn(fed);
      // one noise sample for the friction and the wisps
      const n=rs.noise.next();
      // the glass: both whorls singing
      const gl=rs.glassSoft.low(rs.glasses[0].tick(speed,n)*glassLevel[0]+rs.glasses[1].tick(speed,n)*glassLevel[1]);
      // the thrum: a narrow pulse each time thought passes up, rising as it climbs
      const pulse=m.pow(f32,0.5+0.5*@sin(m.tau*rs.thrumPhase),thrumSharp);
      rs.thrumOsc.freq=thHz*(1+thrumBend*rs.thrumPhase);
      rs.thrumUp.freq=rs.thrumOsc.freq*2;
      const th=rs.thrumSoft.low(rs.thrumOsc.next()+rs.thrumUp.next()*thrumOctave)*pulse;
      rs.thrumPhase+=thStep;
      if(rs.thrumPhase>=1)rs.thrumPhase-=1;
      // the wisps whispering
      var ws:f32=0;
      for(&rs.wisps)|*v|if(v.*)|*w|{
        if(w.tick(n,rs.rate))|y|ws+=y else v.*=null;
      };
      // the core's two tones, wavering together
      const wv=m.pow(f32,2,coreWaver/1200*rs.coreWaver.next());
      var cr:f32=0;
      inline for(0..2)|k|{
        rs.coreOsc[k].freq=rs.coreHz[k]*wv;
        cr+=rs.coreOsc[k].next();
      }
      // all of it mixed at the voice's level
      const y=gl*glass+th*thrum+ws*wisp+cr*core*rs.coreSwell.next();
      s.*+=y*rs.gain*rs.level.next()*(1+resFed*fed);
    }
    return rs.level.target>0 or rs.level.value>fadeSilent;
  }
  /// counts down to the next wisp and starts it on a free slot (sooner fed)
  fn spawn(rs:*Research,fed:f32)void{
    if(rs.wispWait>0){
      rs.wispWait-=1;
      return;
    }
    for(&rs.wisps)|*v|if(v.*==null){
      v.*=.init(&rs.r,rs.rate);
      break;
    };
    rs.wispWait=m.floorTo(u32,m.f(samples(&rs.r,wispGap,rs.rate))*(1-wispGapFed*fed));
  }
};
