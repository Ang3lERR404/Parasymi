//! the night's choir: sopranos, altos, tenors and basses, eight voices each, singing "ahh" through slow chords.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: clamps, conversions, powers
const m=engine.core.math;
/// the engine's sound pieces: oscillators, filters, noise, smoothing
const dsp=engine.core.dsp;
/// the seeded random numbers each singer draws from
const rng=engine.core.rng;
/// the choir's four sections, high to low
pub const Section=enum{
  /// the highest voices
  soprano,
  /// below them
  alto,
  /// the high men's voices
  tenor,
  /// the lowest
  bass,
};
/// how many sections sing
pub const sections=4;
/// how many voices each section has
const voices=8;
/// each section's "ah" (the classic choir vowel tables): its five formants
/// (Hz), how loud each is (dB) and how wide (Hz)
/// (this one: the formants, Hz)
const formantHz=[sections][5]f32{
  .{800,1150,2900,3900,4950},
  .{800,1150,2800,3500,4950},
  .{650,1080,2650,2900,3250},
  .{600,1040,2250,2450,2750},
};
/// how loud each formant is (dB)
const formantDb=[sections][5]f32{
  .{0,-6,-32,-20,-50},
  .{0,-4,-20,-36,-60},
  .{0,-6,-7,-8,-22},
  .{0,-7,-9,-9,-20},
};
/// how wide each formant is (Hz)
const formantBw=[sections][5]f32{
  .{80,90,120,130,140},
  .{80,90,120,130,140},
  .{80,90,120,130,140},
  .{60,70,110,120,130},
};
/// each section's place in the blend: the inner voices a little under
/// the outer ones
const sectionLevel=[sections]f32{1,0.8,0.8,0.95};
/// where each section stands between the speakers (pan): sopranos, altos,
/// tenors and basses from left to right, as a choir stands
const sectionPan=[sections]f32{-0.55,-0.2,0.2,0.55};
/// how far either side of its place a section's two halves stand (pan)
const halfApart:f32=0.15;
/// how far apart a section's voices are tuned at most (cents either way)
const spread:f32=11;
/// how fast a voice's vibrato wavers, drawn between these (Hz)
const vibratoHz=m.Vice(f32,2){4.8,5.8};
/// how deep it wavers, drawn between these (cents)
const vibratoCents=m.Vice(f32,2){12,30};
/// how long the vibrato takes to grow in on a fresh note (s, ~63%)
const vibratoGrow:f32=0.9;
/// how far a voice's pitch wanders on its own (cents) and how slowly
/// (the low-pass over its noise, Hz)
/// (this one: how far, cents)
const drift:f32=7;
/// how slowly it wanders (Hz)
const driftHz:f32=2.5;
/// how much a voice's loudness wavers (a share) and how slowly (Hz)
/// (this one: how much)
const shimmer:f32=0.25;
/// how slowly it wavers (Hz)
const shimmerHz:f32=1.8;
/// how long a voice takes to glide to its next note, drawn between these (s, ~63%)
const glideS=m.Vice(f32,2){0.09,0.2};
/// how late a voice may move to its next note (s): a choir never moves as one
const lagS:f32=0.12;
/// how much breath there is in the voices
const breath:f32=0.05;
/// how long a section takes to swell to a new loudness (s, ~63%)
const swellS:f32=1.3;
/// the choir's loudness
const choir:f32=0.11;
/// one voice: a bright source wavering in pitch and loudness, gliding late
/// between notes
const Voice=struct{
  /// its source
  osc:dsp.Osc,
  /// its own tuning off the note (a ratio)
  detune:f32,
  /// its vibrato
  vibrato:dsp.Osc,
  /// how deep its vibrato wavers (cents)
  depth:f32,
  /// the noise its pitch wanders by, and the low-pass slowing it
  wander:dsp.Noise,
  /// the low-pass slowing its pitch's wander
  wanderLp:dsp.OnePole,
  /// the noise its loudness wavers by
  waver:dsp.Noise,
  /// the low-pass slowing its loudness's waver
  waverLp:dsp.OnePole,
  /// the pitch it sings now (Hz)
  hz:f32,
  /// the pitch it is moving to (Hz)
  target:f32,
  /// the pitch it will move to once its lag is up (Hz)
  next:f32,
  /// samples until it moves
  lag:u32=0,
  /// how much of the way to its target it moves each sample
  glide:f32,
  /// a fresh voice at `hz`, its quirks drawn from `r`
  fn init(hz:f32,r:*rng.Rng,rate:f32)Voice{
    return.{
      .osc=.{.rate=rate,.shape=.saw,.freq=hz,.phase=r.float()},
      .detune=m.pow(f32,2,r.range(-spread,spread)/1200),
      .vibrato=.{.rate=rate,.freq=r.range(vibratoHz[0],vibratoHz[1]),.phase=r.float()},
      .depth=r.range(vibratoCents[0],vibratoCents[1]),
      .wander=.init(r.next()),
      .wanderLp=.init(driftHz,rate),
      .waver=.init(r.next()),
      .waverLp=.init(shimmerHz,rate),
      .hz=hz,
      .target=hz,
      .next=hz,
      .glide=1-dsp.fall(r.range(glideS[0],glideS[1]),rate),
    };
  }
  /// its next sample, its vibrato grown in as far as `grown` (0..1)
  fn tick(v:*Voice,grown:f32)f32{
    if(v.lag>0){
      v.lag-=1;
      if(v.lag==0)v.target=v.next;
    }
    v.hz+=v.glide*(v.target-v.hz);
    // how far off the note it bends this sample (cents): vibrato and wander
    // (the slowed noise is small, so it is scaled back up)
    const cents=v.depth*grown*v.vibrato.next()+drift*60*v.wanderLp.low(v.wander.next());
    v.osc.freq=v.hz*v.detune*(1+cents/1200*0.69);
    // its loudness this sample, wavering
    const loud=1+shimmer*60*v.waverLp.low(v.waver.next());
    return v.osc.next()*loud;
  }
};
/// one section: its voices in two halves standing side by side, the vowel
/// shaped out of each, how loud it is
const Part=struct{
  /// its voices (the even ones its left half, the odd its right)
  voices:[voices]Voice,
  /// its five formants, each half's own
  formants:[5]dsp.StereoBiquad,
  /// where its left and its right half stand between the speakers
  seats:[2]dsp.Frame,
  /// how loud each formant is
  gains:[5]f32,
  /// the breath's noise
  noise:dsp.Noise,
  /// how loud it sings now, gliding
  swell:dsp.Smooth,
  /// how far a fresh note's vibrato has grown in (0 rising to 1)
  grown:f32=0,
  /// how much of the way to full the vibrato grows each sample
  grow:f32,
  /// its place in the blend
  level:f32,
  /// samples a lag may run at most
  lagMax:u32,
  /// section `sc`, silent, its voices on MIDI `note`
  fn init(sc:Section,note:u8,r:*rng.Rng,rate:f32)Part{
    // which section, as an index into the tables
    const i=@intFromEnum(sc);
    // the note's pitch (Hz)
    const hz=dsp.noteToHz(m.f(note));
    // the section, its voices and vowel filled in below
    var p:Part=.{
      .voices=undefined,
      .formants=undefined,
      .seats=.{dsp.spot(sectionPan[i]-halfApart),dsp.spot(sectionPan[i]+halfApart)},
      .gains=undefined,
      .noise=.init(r.next()),
      .swell=.init(0,swellS,rate),
      .grow=dsp.fall(vibratoGrow,rate),
      .level=sectionLevel[i],
      .lagMax=m.floorTo(u32,lagS*rate),
    };
    for(&p.voices)|*v|v.*=.init(hz,r,rate);
    for(0..5)|k|{
      p.formants[k]=.init(.band,formantHz[i][k],formantHz[i][k]/formantBw[i][k],rate);
      p.gains[k]=dsp.dbToGain(formantDb[i][k]);
    }
    return p;
  }
  /// sing MIDI `note` at loudness `loud` (0..1): a silent section takes
  /// its note at once, a singing one glides there, each voice in its own time
  fn sing(p:*Part,note:u8,loud:f32,r:*rng.Rng)void{
    // the note's pitch (Hz)
    const hz=dsp.noteToHz(m.f(note));
    // whether it is silent enough to take the note fresh
    const fresh=p.swell.value<0.02;
    if(fresh)p.grown=0;
    for(&p.voices)|*v|{
      if(fresh){
        v.hz=hz;
        v.target=hz;
        v.next=hz;
        v.lag=0;
      }else{
        v.next=hz;
        v.lag=1+r.below(p.lagMax+1);
      }
    }
    p.swell.target=loud;
  }
  /// fall silent, slowly
  fn hush(p:*Part)void{p.swell.target=0;}
  /// its next sample, each half from where it stands
  fn tick(p:*Part)dsp.Frame{
    p.grown=1-(1-p.grown)*p.grow;
    // each half's voices summed, with a breath through each (its own, so
    // the halves breathe unlike; as loud in all as the one breath was)
    var x:dsp.Frame=@splat(0);
    inline for(0..voices)|k|x[k%2]+=p.voices[k].tick(p.grown);
    x=x*dsp.mid(1.0/m.f(voices))+dsp.Frame{p.noise.next(),p.noise.next()}*dsp.mid(breath/m.sqrt2);
    // the vowel shaped out of each half
    var y:dsp.Frame=@splat(0);
    inline for(0..5)|k|y+=p.formants[k].tick(x)*dsp.mid(p.gains[k]);
    return(dsp.put(p.seats[0],y[0])+dsp.put(p.seats[1],y[1]))*dsp.mid(p.swell.next()*p.level);
  }
};
/// the whole choir: four sections, each singing its own note of a chord
pub const Choir=struct{
  /// soprano, alto, tenor, bass
  parts:[sections]Part,
  /// a silent choir, its sections resting on `notes` (MIDI, soprano first)
  pub fn init(notes:[sections]u8,r:*rng.Rng,rate:f32)Choir{
    // the choir, its sections filled in below
    var c:Choir=.{.parts=undefined};
    for(&c.parts,0..)|*p,i|p.*=.init(@enumFromInt(i),notes[i],r,rate);
    return c;
  }
  /// sing `notes` (MIDI, soprano first) at loudness `loud` (0..1)
  pub fn sing(c:*Choir,notes:[sections]u8,loud:f32,r:*rng.Rng)void{
    for(&c.parts,notes)|*p,n|p.sing(n,loud,r);
  }
  /// every section falls silent, slowly
  pub fn hush(c:*Choir)void{
    for(&c.parts)|*p|p.hush();
  }
  /// whether every section has fallen silent
  pub fn quiet(c:*const Choir)bool{
    for(c.parts)|p|if(p.swell.value>lib.sound.silent or p.swell.target>0)return false;
    return true;
  }
  /// mixes the choir into `out`
  pub fn render(c:*Choir,out:[]dsp.Frame)void{
    for(out)|*s|{
      // the sections summed
      var y:dsp.Frame=@splat(0);
      inline for(0..sections)|k|y+=c.parts[k].tick();
      s.*+=y*dsp.mid(choir);
    }
  }
};
