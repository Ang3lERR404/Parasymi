//! the arsthraxia's unit done: a soft bell chord blooming upward and a breath rushing up its stems.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: lerps, powers, rounding
const m=engine.core.math;
/// the engine's sound pieces: sines, noise, filters
const dsp=engine.core.dsp;
/// the seeded random numbers the bloom draws from
const rng=engine.core.rng;
/// quieter than this (before its loudness), a bell's partial has rung out:
/// already far under a footstep
const bellSilent:f32=1e-2;
/// quieter than this, the root has rung out
const silent=lib.sound.silent;
/// samples between retunings of a swept filter
const retune=lib.sound.sap.retune;
/// a value nudged a little either way, so no two blooms are alike
const vary=lib.sound.footstep.vary;
// decision: a bloom, not a boom: a unit learned is a flower opening, so a
// soft bell chord in the music's key rings up through it, and the surge of
// light up the nerves is a breath rushing up the stems
// ---- the bells: the music's Imaj7 rung upward, its Lydian fourth on top ----
/// the chord's notes (MIDI), low to high: D5 F#5 A5 C#6, and G#6 over them
const bellNote=[_]f32{74,78,81,85,92};
/// each note's level: the top one a glint over the chord
const bellLevel=[bellNote.len]f32{1,0.8,0.8,0.7,0.45};
/// how long after the one under it each note rings in (s): the chord blooms upward
const bellStagger:f32=0.07;
/// a bell's glassy partials (shares of its pitch, a little stretched, as a
/// mote's twinkle)
const bellPartials=[_]f32{1,2.32,4.13};
/// each partial's level
const bellPartialLevel=[bellPartials.len]f32{1,0.3,0.1};
/// how long each partial rings (s, ~63%), the lowest note's; higher notes
/// ring a little shorter
const bellFall=[bellPartials.len]f32{2.0,0.8,0.3};
/// how much shorter each note up the chord rings (a share less each)
const bellFallStep:f32=0.1;
/// how long a bell takes to sound (s): struck softly, with felt
const bellAttack:f32=0.012;
/// the low-pass that softens the bells (Hz)
const bellSoftHz:f32=5000;
/// the bells' level in the mix
const bells:f32=1;
// ---- the root: a warm low note blooming under the bells ----
/// its note (MIDI): D3
const rootNote:f32=50;
/// how long it takes to swell in (s)
const rootRise:f32=0.25;
/// how long it rings out (s, ~63%)
const rootFall:f32=1.6;
/// its level in the mix
const root:f32=0.6;
// ---- the breath: rushing up the stems with the surge of light ----
/// where it starts, low among the roots, and where it ends, at the crown (Hz)
const breathSweep=m.Vice(f32,2){220,2600};
/// how long it rushes up (s)
const breathLen:f32=0.75;
/// how tightly it whistles (q)
const breathQ:f32=1.8;
/// its level in the mix
const breath:f32=0.9;
/// the whole bloom's loudness
const bloom:f32=0.025;
/// one bell of the chord
const Bell=struct{
  /// its partials' sines
  osc:[bellPartials.len]dsp.Sine,
  /// each partial's level now, 1 falling away
  amp:[bellPartials.len]f32=@splat(1),
  /// how much of its level each partial keeps a sample
  fall:[bellPartials.len]f32,
  /// the sample it rings in on
  start:u32,
  /// its level in the chord
  level:f32,
  /// where it rings between the speakers
  place:dsp.Frame,
};
/// how wide the chord opens round the flower (pan, its lowest bell to its
/// highest): blooming upward from left to right
const bellSpread:f32=0.6;
/// a unit's bloom: bells, root and breath, ringing out where the flower is heard
pub const Bloom=struct{
  /// samples per second
  rate:f32,
  /// the chord's bells
  bells:[bellNote.len]Bell,
  /// the low-pass softening the bells
  bellSoft:dsp.StereoPole,
  /// where the root and the breath are heard: at the flower
  heart:dsp.Frame,
  /// the root's sine
  root:dsp.Sine,
  /// how much of the root's level it keeps a sample, falling
  rootKeep:f32,
  /// the root's fall so far, 1 falling away
  rootAmp:f32=1,
  /// the noise the breath is drawn from
  noise:dsp.Noise,
  /// the breath's band, swept up
  breath:dsp.Biquad,
  /// samples played so far
  at:u32=0,
  /// its loudness, varied a little each time
  gain:f32,
  /// a fresh bloom where the flower is heard (`pan`), its bells' rings and
  /// its loudness drawn from `r`
  pub fn init(pan:f32,r:*rng.Rng,rate:f32)Bloom{
    // the bells, filled in below
    var bs:[bellNote.len]Bell=undefined;
    for(&bs,bellNote,bellLevel,0..)|*b,note,lv,i|{
      // its pitch, and how much shorter it rings than the lowest
      const hz=dsp.noteToHz(note);
      const short=1-bellFallStep*m.f(i);
      var osc:[bellPartials.len]dsp.Sine=undefined;
      var fall:[bellPartials.len]f32=undefined;
      for(bellPartials,bellFall,0..)|p,fs,k|{
        osc[k]=.init(hz*p,rate);
        fall[k]=dsp.fall(fs*short*r.range(0.85,1.15),rate);
      }
      // how far up the chord it is (-0.5 lowest .. 0.5 highest)
      const up=m.f(i)/m.f(bellNote.len-1)-0.5;
      b.*=.{.osc=osc,.fall=fall,.start=m.floorTo(u32,m.f(i)*bellStagger*rate),.level=lv,.place=dsp.spot(pan+up*bellSpread)};
    }
    return.{
      .rate=rate,
      .bells=bs,
      .bellSoft=.init(bellSoftHz,rate),
      .heart=dsp.spot(pan),
      .root=.init(dsp.noteToHz(rootNote),rate),
      .rootKeep=dsp.fall(rootFall,rate),
      .noise=.init(r.next()),
      .breath=.init(.band,breathSweep[0],breathQ,rate),
      .gain=vary(r,bloom),
    };
  }
  /// mixes the next `out.len` samples into `out`: the bells ringing in one
  /// above the next, the root swelling under them, the breath rushing up;
  /// returns false once all of it has rung out
  pub fn render(b:*Bloom,out:[]dsp.Frame)bool{
    for(out)|*s|{
      // seconds since it began
      const t=m.f(b.at)/b.rate;
      // the bells summed, each in its place, and whether any still rings
      var bl:dsp.Frame=@splat(0);
      var alive=false;
      for(&b.bells)|*bell|{
        if(b.at<bell.start){
          alive=true;
          continue;
        }
        // how far into its soft strike it is (0..1), and this bell's partials summed
        const strike=m.clamp01(m.f(b.at-bell.start)/(bellAttack*b.rate));
        var one:f32=0;
        for(&bell.osc,&bell.amp,bell.fall,bellPartialLevel)|*o,*a,fl,pl|{
          if(a.*<bellSilent)continue;
          alive=true;
          one+=o.next()*pl*bell.level*strike*a.*;
          a.*=fl*a.*;
        }
        bl+=dsp.put(bell.place,one);
      }
      // the root: swelling in, then ringing away
      const rise=m.smooth(m.clamp01(t/rootRise));
      const rt=b.root.next()*rise*b.rootAmp;
      if(t>rootRise)b.rootAmp*=b.rootKeep;
      // the breath: rushing up from the roots to the crown, swelling then gone
      var br:f32=0;
      if(t<breathLen){
        const x=t/breathLen;
        if(b.at%retune==0)b.breath.tune(.band,breathSweep[0]*m.pow(f32,breathSweep[1]/breathSweep[0],x),breathQ,b.rate);
        const env=@sin(m.pi*m.pow(f32,x,0.6));
        br=b.breath.tick(b.noise.next())*env*env;
      }
      s.*+=(b.bellSoft.low(bl)*dsp.mid(bells)+dsp.put(b.heart,rt*root+br*breath))*dsp.mid(b.gain);
      b.at+|=1;
      if(!alive and t>breathLen and b.rootAmp<silent)return false;
    }
    return true;
  }
};
