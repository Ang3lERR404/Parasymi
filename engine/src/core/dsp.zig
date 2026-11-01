//! audio DSP building blocks, one sample at a time: oscillators, noise,
//! crackle, filters (one-pole, biquad), an ADSR envelope, a parameter
//! smoother, a delay line and a hall reverb, plus level and pitch conversions. Pure maths at a sample
//! `rate` (Hz) each unit keeps; nothing here touches a device, so a sound is
//! built by chaining units (`Voice` shows how) and the platform's output
//! pulls blocks of samples from it.
/// the standard library
const std=@import("std");
/// the engine's maths: clamp, pow, tau, lerp
const m=@import("math.zig");
/// the seeded random numbers noise and crackle draw from
const rng=@import("rng.zig");
/// the test helpers
const testing=std.testing;
/// the allocator type a `Delay` takes
const Allocator=std.mem.Allocator;
/// the highest cutoff a filter takes, as a fraction of the sample rate (just
/// under Nyquist, where the biquad's maths breaks down)
const maxCutoff:f32=0.49;
/// 0 dB is a gain of 1; every 20 dB is a factor of 10
const dbPerDecade:f32=20;
/// MIDI note 69 is A4: the note the tuning hangs from
const a4Note:f32=69;
/// A4's pitch, 440 Hz
const a4Hz:f32=440;
/// semitones to the octave, 12
const notesPerOctave:f32=12;
/// `softClip` reaches ±1 at ±3 and holds there
const clipKnee:f32=3;
// ---- conversions ----
/// decibels to a linear gain (-6 dB ≈ 0.5)
pub fn dbToGain(db:f32)f32{return m.pow(f32,10,db/dbPerDecade);}
/// a linear gain (> 0) to decibels
pub fn gainToDb(g:f32)f32{return dbPerDecade*@log10(g);}
/// a MIDI note number (fractional for bends) to Hz
pub fn noteToHz(note:f32)f32{return a4Hz*m.pow(f32,2,(note-a4Note)/notesPerOctave);}
/// what a level keeps each sample to fade to 1/e over `seconds` at `rate`:
/// `level*=fall(ring,rate)` every sample rings for about `ring` seconds
pub fn fall(seconds:f32,rate:f32)f32{return@exp(-1/(seconds*rate));}
/// a smooth saturator close to tanh: linear near 0, ±1 past ±3, so a loud
/// mix bends instead of clipping hard
pub fn softClip(x:f32)f32{
  // the input held within the knee, where the curve meets ±1
  const c=m.clamp(x,-clipKnee,clipKnee);
  return c*(27+c*c)/(27+9*c*c);
}
/// `x` placed in stereo at `p` (-1 left, 0 centre, 1 right), equal power so
/// it stays as loud wherever it sits: .{left, right}
pub fn pan(x:f32,p:f32)m.Vice(f32,2){
  // the pan as an angle, 0 (all left) to a quarter turn (all right)
  const a=(m.clamp(p,-1,1)+1)*(m.pi/4.0);
  return.{x*@cos(a),x*@sin(a)};
}
/// the fractional part of a phase (wraps 0..1)
inline fn wrap(t:f32)f32{return t-@floor(t);}
// ---- sources ----
/// the four waveforms an oscillator can sing
pub const Shape=enum{
  /// pure and round: a single tone
  sine,
  /// bright and buzzy: every harmonic, ramping up then dropping
  saw,
  /// hollow and reedy: odd harmonics, high half then low half
  square,
  /// soft and flute-like: odd harmonics, fading fast
  triangle
};
/// a periodic waveform. `phase` runs 0..1 per cycle; saw and square are
/// band-limited (polyBLEP) so high notes don't alias into whine.
pub const Osc=struct{
  /// samples a second (Hz)
  rate:f32,
  /// which waveform it sings
  shape:Shape=.sine,
  /// its pitch (Hz)
  freq:f32=a4Hz,
  /// where in the cycle it stands, 0..1
  phase:f32=0,
  /// the next sample, -1..1 (a touch past for the band-limited edges), and
  /// the phase stepped on by one sample
  pub fn next(o:*Osc)f32{
    // how far one sample moves the phase, and where it stands now
    const dt=o.freq/o.rate;
    const t=o.phase;
    // the sample, shaped by the waveform
    const y=switch(o.shape){
      .sine=>@sin(m.tau*t),
      .saw=>2*t-1-blep(t,dt),
      .square=>(if(t<0.5)@as(f32,1)else-1)+blep(t,dt)-blep(wrap(t+0.5),dt),
      // shifted a quarter cycle so it starts at 0 rising, like the sine
      .triangle=>1-4*@abs(wrap(t+0.25)-0.5),
    };
    o.phase=wrap(t+dt);
    return y;
  }
};
/// a sine at a fixed pitch by recurrence (y = 2cos(w)·y₁ − y₂): two
/// multiplies a sample instead of a `@sin`, for the many partials of a
/// struck string or bell. Starts at phase 0, rising.
pub const Sine=struct{
  /// the recurrence's multiplier, 2cos(w)
  c:f32,
  /// the last sample
  y1:f32=0,
  /// the sample before it
  y2:f32,
  /// a sine of `freq` Hz at `rate` samples a second (held under Nyquist)
  pub fn init(freq:f32,rate:f32)Sine{
    // the angle one sample turns (radians)
    const w=m.tau*m.clamp(freq,0,maxCutoff*rate)/rate;
    return.{.c=2*@cos(w),.y2=-@sin(w)};
  }
  /// the next sample, -1..1
  pub fn next(s:*Sine)f32{
    // the new sample from the last two
    const y=s.c*s.y1-s.y2;
    s.y2=s.y1;
    s.y1=y;
    return y;
  }
};
/// polyBLEP: the correction that rounds off a unit jump at phase 0 over one
/// sample each side, `dt` being one sample's phase step
fn blep(t:f32,dt:f32)f32{
  if(t<dt){
    // how far past the jump, in samples (0..1)
    const x=t/dt;
    return x+x-x*x-1;
  }
  if(t>1-dt){
    // how far before the jump, in samples (-1..0)
    const x=(t-1)/dt;
    return x*x+x+x+1;
  }
  return 0;
}
/// white noise in -1..1, the same stream for the same seed (wind, rustle,
/// the attack of a pluck)
pub const Noise=struct{
  /// the generator the noise is drawn from
  r:rng.Rng,
  /// a noise stream for `seed`
  pub fn init(seed:u64)Noise{return.{.r=.init(seed)};}
  /// the next sample, -1..1
  pub fn next(n:*Noise)f32{return n.r.float()*2-1;}
};
/// sparse crackle: tiny bursts of noise ("grains") at random moments, each
/// of random loudness and fading within a few milliseconds (dry leaves
/// crushed, twigs, embers, rain on a leaf). `density` may change per sample.
pub const Crackle=struct{
  /// samples a second (Hz)
  rate:f32,
  /// grains per second, on average
  density:f32=0,
  /// how much a grain keeps per sample (from its fade time)
  fall:f32,
  /// the generator grains and their loudness are drawn from
  r:rng.Rng,
  /// how loud the current grain still is, 0..1
  level:f32=0,
  /// a grain falls ~63% in `grain` seconds
  pub fn init(seed:u64,grain:f32,rate:f32)Crackle{
    return.{.rate=rate,.fall=@exp(-1/@max(grain*rate,1)),.r=.init(seed)};
  }
  /// the next sample: maybe a new grain begins, then the grain fades on;
  /// noise scaled by its loudness, -1..1
  pub fn next(c:*Crackle)f32{
    if(c.r.float()<c.density/c.rate){
      // mostly soft grains, a few loud ones
      // the new grain's loudness, squared below
      const a=c.r.float();
      c.level=@max(c.level,a*a);
    }
    c.level*=c.fall;
    return(c.r.float()*2-1)*c.level;
  }
};
// ---- filters ----
/// the cheapest filter: one pole, 6 dB/octave. `low` darkens, `high` thins;
/// call one of them per sample, not both.
pub const OnePole=struct{
  /// how far the state moves toward the input each sample (0..1; lower is darker)
  a:f32,
  /// the filtered signal so far
  z:f32=0,
  /// a filter whose -3 dB point sits at `cutoff` Hz
  pub fn init(cutoff:f32,rate:f32)OnePole{return.{.a=coeff(cutoff,rate)};}
  /// the coefficient whose -3 dB point sits at `cutoff` Hz
  pub fn coeff(cutoff:f32,rate:f32)f32{
    return 1-@exp(-m.tau*m.clamp(cutoff,0,maxCutoff*rate)/rate);
  }
  /// the low-passed sample: the state drawn `a` of the way toward `x`
  pub fn low(p:*OnePole,x:f32)f32{
    p.z+=p.a*(x-p.z);
    return p.z;
  }
  /// the high-passed sample: what the low pass leaves out
  pub fn high(p:*OnePole,x:f32)f32{return x-p.low(x);}
};
/// a value that glides to its `target` instead of jumping, so a gain or
/// cutoff changed between blocks doesn't click ("zipper noise")
pub const Smooth=struct{
  /// where the value stands now
  value:f32,
  /// where it is gliding to
  target:f32,
  /// how far it moves toward the target each sample, 0..1
  a:f32,
  /// starts at `value`; `time` seconds to get ~63% of the way to a new target
  pub fn init(value:f32,time:f32,rate:f32)Smooth{
    return.{.value=value,.target=value,.a=1-@exp(-1/@max(time*rate,1))};
  }
  /// the next value, one sample further along its glide
  pub fn next(s:*Smooth)f32{
    s.value+=s.a*(s.target-s.value);
    return s.value;
  }
};
/// what a biquad lets through
pub const BiquadKind=enum{
  /// what lies under the cutoff: darkens
  low,
  /// what lies over the cutoff: thins
  high,
  /// a band round the cutoff, as wide as `q` lets it
  band,
  /// all but a narrow band round the cutoff
  notch
};
/// the workhorse two-pole filter, 12 dB/octave (RBJ cookbook, transposed
/// direct form II). `q` is the resonance: 0.707 is flat, higher rings at
/// the cutoff.
pub const Biquad=struct{
  /// how much of this sample's input passes
  b0:f32,
  /// how much of the input one sample ago passes
  b1:f32,
  /// how much of the input two samples ago passes
  b2:f32,
  /// how much of the output one sample ago feeds back (subtracted)
  a1:f32,
  /// how much of the output two samples ago feeds back (subtracted)
  a2:f32,
  /// the filter's first carried state
  z1:f32=0,
  /// its second carried state
  z2:f32=0,
  /// a filter of `kind` at `cutoff` Hz with resonance `q`
  pub fn init(kind:BiquadKind,cutoff:f32,q:f32,rate:f32)Biquad{
    // a filter passing everything, about to be tuned
    var f:Biquad=.{.b0=1,.b1=0,.b2=0,.a1=0,.a2=0};
    f.tune(kind,cutoff,q,rate);
    return f;
  }
  /// new coefficients, keeping the state so a sweep doesn't click
  pub fn tune(f:*Biquad,kind:BiquadKind,cutoff:f32,q:f32,rate:f32)void{
    // the cutoff as an angle per sample (radians), and its cosine
    const w=m.tau*m.clamp(cutoff,1,maxCutoff*rate)/rate;
    const c=@cos(w);
    // how wide the response is, from the resonance
    const alpha=@sin(w)/(2*@max(q,0.01));
    // the input weights for this kind, not yet normalised
    const b:m.Vice(f32,3)=switch(kind){
      .low=>.{(1-c)/2,1-c,(1-c)/2},
      .high=>.{(1+c)/2,-(1+c),(1+c)/2},
      // 0 dB at the centre
      .band=>.{alpha,0,-alpha},
      .notch=>.{1,-2*c,1},
    };
    // the output weight everything is divided by
    const a0=1+alpha;
    f.b0=b[0]/a0;
    f.b1=b[1]/a0;
    f.b2=b[2]/a0;
    f.a1=-2*c/a0;
    f.a2=(1-alpha)/a0;
  }
  /// the filtered sample for input `x`, the state carried on
  pub fn tick(f:*Biquad,x:f32)f32{
    // the output, from this input and the carried state
    const y=f.b0*x+f.z1;
    f.z1=f.b1*x-f.a1*y+f.z2;
    f.z2=f.b2*x-f.a2*y;
    return y;
  }
};
// ---- envelope ----
/// attack, decay, sustain, release: the loudness shape of one note, 0..1.
/// `on` starts it, `off` lets it fade; it is `.idle` once silent.
pub const Adsr=struct{
  /// where a note's envelope stands
  pub const Stage=enum{
    /// silent, waiting for `on`
    idle,
    /// rising to full
    attack,
    /// falling to the sustain level
    decay,
    /// holding while the note is down
    sustain,
    /// fading to silence after `off`
    release
  };
  /// samples a second (Hz)
  rate:f32,
  /// seconds from silence to full level
  attack:f32=0.01,
  /// seconds from full level down to the sustain level
  decay:f32=0.1,
  /// level held while the note is down, 0..1
  sustain:f32=0.7,
  /// seconds from full level to silence
  release:f32=0.3,
  /// the loudness now, 0..1
  level:f32=0,
  /// which part of its shape the envelope is in
  stage:Stage=.idle,
  /// a note begins: rise from wherever it stands
  pub fn on(e:*Adsr)void{e.stage=.attack;}
  /// the note is let go: fade from wherever it stands (an idle one stays idle)
  pub fn off(e:*Adsr)void{
    if(e.stage!=.idle)e.stage=.release;
  }
  /// the next loudness, 0..1, moving the envelope on through its stages
  pub fn next(e:*Adsr)f32{
    switch(e.stage){
      .idle=>e.level=0,
      .attack=>{
        e.level+=e.step(e.attack);
        if(e.level>=1){
          e.level=1;
          e.stage=.decay;
        }
      },
      .decay=>{
        e.level-=(1-e.sustain)*e.step(e.decay);
        if(e.level<=e.sustain){
          e.level=e.sustain;
          e.stage=.sustain;
        }
      },
      .sustain=>e.level=e.sustain,
      .release=>{
        e.level-=e.step(e.release);
        if(e.level<=0){
          e.level=0;
          e.stage=.idle;
        }
      },
    }
    return e.level;
  }
  /// the change per sample that covers 0..1 in `time` seconds
  fn step(e:Adsr,time:f32)f32{return 1/@max(time*e.rate,1);}
};
// ---- delay ----
/// a ring of past samples: echoes, chorus, the start of a reverb. Owns its
/// buffer (`deinit`).
pub const Delay=struct{
  /// the past samples, a ring
  buf:[]f32,
  /// where the next sample is written
  at:usize=0,
  /// room for `max` samples of delay
  pub fn init(gpa:Allocator,max:usize)Allocator.Error!Delay{
    // the ring, one longer than the longest delay, silent
    const buf=try gpa.alloc(f32,max+1);
    @memset(buf,0);
    return.{.buf=buf};
  }
  /// frees the ring
  pub fn deinit(d:*Delay,gpa:Allocator)void{gpa.free(d.buf);}
  /// the sample written `delay` samples ago (fractional, interpolated;
  /// clamped to 1..max)
  pub fn read(d:Delay,delay:f32)f32{
    // the ring's length, and the delay held within it
    const n=d.buf.len;
    const dl=m.clamp(delay,1,m.f(n-1));
    // the whole samples back, and the two samples either side of the delay
    const whole=m.floorTo(usize,dl);
    const s0=d.buf[(d.at+n-whole)%n];
    const s1=d.buf[(d.at+n-whole-1)%n];
    return m.lerp(s0,s1,dl-m.f(whole));
  }
  /// stores `x` as the newest sample, the ring turning on by one
  pub fn write(d:*Delay,x:f32)void{
    d.buf[d.at]=x;
    d.at=(d.at+1)%d.buf.len;
  }
  /// `read` then `write`: a plain delay of `delay` samples
  pub fn tick(d:*Delay,x:f32,delay:f32)f32{
    // the delayed sample, read before this one overwrites the oldest
    const y=d.read(delay);
    d.write(x);
    return y;
  }
};
// ---- a hall ----
/// the hall's lines (samples at 48 kHz, scaled to the rate): spread apart
/// and sharing no factor, so their echoes never pile up into one ringing
/// pitch (this one: the eight feedback lines)
const hallLines=[8]usize{1931,2213,2591,2953,3361,3797,4159,4733};
/// the four diffusers smearing what comes in before the lines hear it
const hallDiffusers=m.Vice(usize,4){142,107,379,277};
/// how much each diffuser feeds round itself
const hallDiffuse:f32=0.62;
/// the longest pre-delay a hall holds (samples at 48 kHz)
const hallPreMax=4800;
/// the rate the line lengths are written for
const hallRef:f32=48000;
/// the most a rate may stretch the lines (their rings are sized for it)
const hallStretch=2;
/// a large stone hall: what goes in comes back as a long, dense, darkening
/// tail (an eight-line feedback delay network, its lines mixed through a
/// Hadamard matrix every sample, each line darkened as it feeds back, after
/// a pre-delay and four diffusing all-passes). Its rings are fixed arrays:
/// no allocation, about 270 KB.
pub const Hall=struct{
  /// the eight lines' rings
  lines:[8][hallLines[7]*hallStretch+1]f32=@splat(@splat(0)),
  /// each line's length (samples)
  len:[8]usize,
  /// where each line writes next
  at:[8]usize=@splat(0),
  /// how much of each line's sound is kept round one trip (its decay)
  keep:[8]f32,
  /// each line's darkening as it feeds back
  damp:[8]OnePole,
  /// the diffusers' rings
  diff:[4][hallDiffusers[2]*hallStretch+1]f32=@splat(@splat(0)),
  /// each diffuser's length (samples)
  dlen:m.Vice(usize,4),
  /// where each diffuser writes next
  dat:m.Vice(usize,4)=@splat(0),
  /// the pre-delay's ring
  pre:[hallPreMax*hallStretch+1]f32=@splat(0),
  /// the pre-delay's length (samples)
  preLen:usize,
  /// where the pre-delay writes next
  preAt:usize=0,
  /// a hall ringing about `rt60` seconds (to -60 dB), after `preS` seconds
  /// of pre-delay, its tail darkened above `dampHz`, at `rate` samples a
  /// second (at most twice 48 kHz)
  pub fn init(rt60:f32,preS:f32,dampHz:f32,rate:f32)Hall{
    // how much the rate stretches the lengths
    const k=m.clamp(rate/hallRef,0.25,hallStretch);
    // the hall, its lengths and decays filled in below
    var h:Hall=.{.len=undefined,.keep=undefined,.damp=undefined,.dlen=undefined,.preLen=m.clamp(m.floorTo(usize,preS*rate),1,hallPreMax*hallStretch)};
    for(0..8)|i|{
      h.len[i]=@max(m.floorTo(usize,m.f(hallLines[i])*k),1);
      // -60 dB over rt60 seconds, taken a trip of this line at a time
      h.keep[i]=m.pow(f32,10,-3*m.f(h.len[i])/(@max(rt60,0.1)*rate));
      h.damp[i]=.init(dampHz,rate);
    }
    for(0..4)|i|h.dlen[i]=@max(m.floorTo(usize,m.f(hallDiffusers[i])*k),1);
    return h;
  }
  /// what the hall sends back for `x` this sample (the wet sound alone)
  pub fn tick(h:*Hall,x:f32)f32{
    // the pre-delayed input
    const back=(h.preAt+h.pre.len-h.preLen)%h.pre.len;
    var y=h.pre[back];
    h.pre[h.preAt]=x;
    h.preAt=(h.preAt+1)%h.pre.len;
    // smeared through the diffusers (Schroeder all-passes)
    inline for(0..4)|i|{
      // what the diffuser heard its length ago
      const d=h.diff[i][(h.dat[i]+h.diff[i].len-h.dlen[i])%h.diff[i].len];
      const v=y+hallDiffuse*d;
      h.diff[i][h.dat[i]]=v;
      h.dat[i]=(h.dat[i]+1)%h.diff[i].len;
      y=d-hallDiffuse*v;
    }
    // each line's output, read its length ago
    var o:[8]f32=undefined;
    inline for(0..8)|i|o[i]=h.lines[i][(h.at[i]+h.lines[i].len-h.len[i])%h.lines[i].len];
    // the lines mixed through an 8x8 Hadamard (fast Walsh-Hadamard, kept
    // to unit gain), so each feeds every other
    var w=o;
    inline for(.{1,2,4})|span|{
      inline for(0..8)|i|if(i&span==0){
        // the pair this butterfly mixes
        const a=w[i];
        const b=w[i+span];
        w[i]=a+b;
        w[i+span]=a-b;
      };
    }
    // the Hadamard's scale: one over the square root of eight
    const norm:f32=0.35355339;
    // what is heard: the lines summed, alternately signed
    var out:f32=0;
    inline for(0..8)|i|{
      out+=if(i%2==0)o[i]else-o[i];
      h.lines[i][h.at[i]]=h.damp[i].low(w[i]*norm*h.keep[i])+y*0.5;
      h.at[i]=(h.at[i]+1)%h.lines[i].len;
    }
    return out*0.35;
  }
};
// ---- a voice ----
/// one playable note, showing how the units chain: oscillator → low-pass →
/// envelope → gain. A game's sounds are built the same way.
pub const Voice=struct{
  /// the sound's source
  osc:Osc,
  /// the low pass that softens it
  filter:Biquad,
  /// the loudness shape of the note
  env:Adsr,
  /// the overall loudness, gliding to new settings
  gain:Smooth,
  /// a silent voice of `shape` at `rate` samples a second
  pub fn init(rate:f32,shape:Shape)Voice{
    return.{
      .osc=.{.rate=rate,.shape=shape},
      .filter=.init(.low,2000,0.707,rate),
      .env=.{.rate=rate},
      .gain=.init(0.2,0.01,rate),
    };
  }
  /// starts a note at `freq` Hz
  pub fn play(v:*Voice,freq:f32)void{
    v.osc.freq=freq;
    v.env.on();
  }
  /// lets the note go, to fade by its release
  pub fn stop(v:*Voice)void{v.env.off();}
  /// what a game sends a playing voice (`platform.audio.Output`)
  pub const Cmd=union(enum){
    /// start a note at this pitch (Hz)
    play:f32,
    /// let the note go
    stop,
    /// glide to this loudness
    gain:f32
  };
  /// does what `cmd` says: play, stop, or change the loudness
  pub fn apply(v:*Voice,cmd:Cmd)void{
    switch(cmd){
      .play=>|hz|v.play(hz),
      .stop=>v.stop(),
      .gain=>|g|v.gain.target=g,
    }
  }
  /// fills `out` (mono), mixing into what is there so voices sum
  pub fn render(v:*Voice,out:[]f32)void{
    if(v.env.stage==.idle)return;
    for(out)|*s|s.*+=v.filter.tick(v.osc.next())*v.env.next()*v.gain.next();
  }
};
// ---- a pool of voices ----
/// up to `n` voices of `t` sounding at once; null slots are free. A `t`
/// that `render`s has `render(*t,[]f32)bool`, false once it has ended
pub fn Pool(comptime t:type,comptime n:usize)type{
  return struct{
    /// this pool's own type
    const Self=@This();
    /// the voices, each sounding or free (null)
    slots:[n]?t=@splat(null),
    /// the slot taken next in turn round the pool (the oldest started)
    turn:usize=0,
    /// the first free slot, if any
    pub fn free(p:*const Self)?usize{
      for(p.slots,0..)|v,i|if(v==null)return i;
      return null;
    }
    /// the slot next in turn round the pool, moving the turn on
    pub fn next(p:*Self)usize{
      defer p.turn=(p.turn+1)%n;
      return p.turn;
    }
    /// `v` sounds on the first free slot, or else on the next in turn
    pub fn add(p:*Self,v:t)void{p.slots[p.free() orelse p.next()]=v;}
    /// `v` sounds on the next slot in turn, free or not: the newest always
    /// takes the oldest's place
    pub fn cycle(p:*Self,v:t)void{p.slots[p.next()]=v;}
    /// `v` sounds on the first free slot; with none free it is dropped
    pub fn addFree(p:*Self,v:t)void{
      if(p.free())|i|p.slots[i]=v;
    }
    /// every voice silenced
    pub fn clear(p:*Self)void{p.slots=@splat(null);}
    /// every sounding voice mixed into `out`, those that have ended freed
    pub fn render(p:*Self,out:[]f32)void{
      for(&p.slots)|*s|if(s.*)|*v|{
        if(!v.render(out))s.*=null;
      };
    }
  };
}
// ---- tests ----
/// the sample rate the tests run at (Hz)
const testRate:f32=48000;
test"a pool fills free slots, then the oldest; voices that end are freed"{
  // a voice that sounds for `left` blocks, adding its `id` to each sample
  const Beep=struct{
    /// what it adds to each sample, to tell voices apart
    id:f32,
    /// blocks until it ends
    left:u32,
    /// adds its id to each sample; false once its blocks are spent
    fn render(b:*@This(),out:[]f32)bool{
      for(out)|*s|s.*+=b.id;
      b.left-=1;
      return b.left>0;
    }
  };
  var p:Pool(Beep,2)=.{};
  p.add(.{.id=1,.left=1});
  p.add(.{.id=2,.left=3});
  // full: the next in turn, the oldest, is taken
  p.add(.{.id=4,.left=3});
  try testing.expectEqual(@as(f32,4),p.slots[0].?.id);
  var out=[_]f32{0};
  p.render(&out);
  try testing.expectEqual(@as(f32,6),out[0]);
  // one free slot again after the second's turn ends: addFree takes it
  p.slots[1]=null;
  p.addFree(.{.id=8,.left=1});
  try testing.expectEqual(@as(f32,8),p.slots[1].?.id);
  p.addFree(.{.id=16,.left=1});
  try testing.expectEqual(@as(f32,4),p.slots[0].?.id);
  // cycle takes the next in turn even with a slot free
  p.clear();
  p.cycle(.{.id=1,.left=1});
  try testing.expect(p.slots[0]==null and p.slots[1]!=null);
}
test"a fall fades to 1/e over its seconds"{
  try testing.expectApproxEqAbs(@exp(@as(f32,-1)),m.pow(f32,fall(0.5,100),50),1e-4);
}
test"conversions"{
  try testing.expectApproxEqAbs(@as(f32,0.501),dbToGain(-6),0.001);
  try testing.expectApproxEqAbs(@as(f32,-6),gainToDb(dbToGain(-6)),0.001);
  try testing.expectApproxEqAbs(a4Hz,noteToHz(69),0.001);
  try testing.expectApproxEqAbs(@as(f32,880),noteToHz(81),0.01);
  try testing.expectEqual(@as(f32,1),softClip(10));
  try testing.expectApproxEqAbs(@as(f32,0.1),softClip(0.1),0.001);
  // a sound panned to the centre
  const c=pan(1,0);
  try testing.expectApproxEqAbs(@as(f32,1),c[0]*c[0]+c[1]*c[1],0.001);
}
test"sine at a quarter of the rate walks 0, 1, 0, -1"{
  // a sine at a quarter of the rate: four samples a cycle
  var o:Osc=.{.rate=testRate,.freq=testRate/4};
  for([_]f32{0,1,0,-1})|want|try testing.expectApproxEqAbs(want,o.next(),0.001);
}
test"a recurrence sine follows @sin for seconds"{
  // a recurrence sine
  var s:Sine=.init(1234,testRate);
  for(0..2*48000)|i|{
    // what @sin gives for this sample
    const want=@sin(m.tau*1234*m.f(i+1)/testRate);
    try testing.expectApproxEqAbs(want,s.next(),0.01);
  }
}
test"band-limited saw and square stay bounded and centred"{
  for([_]Shape{.saw,.square,.triangle})|shape|{
    // an oscillator of this shape, high enough to alias without its blep
    var o:Osc=.{.rate=testRate,.shape=shape,.freq=3001};
    // the samples summed, to find their centre
    var sum:f32=0;
    // a second's worth of samples
    const n=48000;
    for(0..n)|_|{
      // this sample
      const y=o.next();
      try testing.expect(@abs(y)<=1.2);
      sum+=y;
    }
    try testing.expect(@abs(sum/n)<0.01);
  }
}
test"noise repeats for a seed"{
  // two noise streams from the same seed
  var a:Noise=.init(7);
  var b:Noise=.init(7);
  for(0..64)|_|{
    // this sample
    const y=a.next();
    try testing.expect(@abs(y)<=1);
    try testing.expectEqual(y,b.next());
  }
}
test"crackle is silent without grains, sparse with them, repeats for a seed"{
  // a crackle with grains a millisecond long, no grains yet
  var a:Crackle=.init(3,0.001,testRate);
  for(0..4800)|_|try testing.expectEqual(@as(f32,0),a.next());
  a.density=100;
  // a copy, which must crackle the same
  var b=a;
  // a grain is loud for a few samples, then gone: count where one starts,
  // and how many samples are quiet
  var loud:usize=0;
  var quiet:usize=0;
  for(0..48000)|_|{
    // this sample
    const y=a.next();
    try testing.expectEqual(y,b.next());
    try testing.expect(@abs(y)<=1);
    if(a.level<1e-3)quiet+=1 else loud+=1;
  }
  // a hundred grains of ~1 ms each sound for well under half the second
  try testing.expect(loud>100 and loud<24000);
  try testing.expect(quiet>24000);
}
test"one-pole low passes DC, high blocks it"{
  // a low pass and a high pass at 100 Hz
  var lo:OnePole=.init(100,testRate);
  var hi:OnePole=.init(100,testRate);
  // their last outputs on a steady input
  var l:f32=0;
  var h:f32=1;
  for(0..testRate)|_|{
    l=lo.low(1);
    h=hi.high(1);
  }
  try testing.expectApproxEqAbs(@as(f32,1),l,0.001);
  try testing.expectApproxEqAbs(@as(f32,0),h,0.001);
}
test"biquad low passes DC and stops Nyquist; high the reverse"{
  // a low pass and a high pass at 1 kHz
  var lo:Biquad=.init(.low,1000,0.707,testRate);
  var hi:Biquad=.init(.high,1000,0.707,testRate);
  // their last outputs on a steady input
  var lDc:f32=0;
  var hDc:f32=1;
  for(0..4800)|_|{
    lDc=lo.tick(1);
    hDc=hi.tick(1);
  }
  try testing.expectApproxEqAbs(@as(f32,1),lDc,0.001);
  try testing.expectApproxEqAbs(@as(f32,0),hDc,0.001);
  lo=.init(.low,1000,0.707,testRate);
  hi=.init(.high,1000,0.707,testRate);
  // their loudest outputs on the fastest wave there is
  var lNy:f32=0;
  var hNy:f32=0;
  for(0..4800)|i|{
    // a sample of that wave, flipping every sample
    const x:f32=if(i%2==0)1 else-1;
    lNy=@max(lNy*0.99,@abs(lo.tick(x)));
    hNy=@abs(hi.tick(x));
  }
  try testing.expect(lNy<0.01);
  try testing.expectApproxEqAbs(@as(f32,1),hNy,0.01);
}
test"adsr rises, holds, fades to idle"{
  // a quick envelope at 1000 samples a second
  var e:Adsr=.{.rate=1000,.attack=0.01,.decay=0.01,.sustain=0.5,.release=0.01};
  e.on();
  for(0..10)|_|_=e.next();
  try testing.expectEqual(@as(f32,1),e.level);
  for(0..20)|_|_=e.next();
  try testing.expectEqual(Adsr.Stage.sustain,e.stage);
  try testing.expectEqual(@as(f32,0.5),e.next());
  e.off();
  for(0..10)|_|_=e.next();
  try testing.expectEqual(Adsr.Stage.idle,e.stage);
  try testing.expectEqual(@as(f32,0),e.level);
}
test"delay returns an impulse after its length"{
  // a delay of up to 16 samples
  var d:Delay=try.init(testing.allocator,16);
  defer d.deinit(testing.allocator);
  // when the impulse came back
  var got:?usize=null;
  for(0..20)|i|{
    // this sample out, five samples behind
    const y=d.tick(if(i==0)1 else 0,5);
    if(y==1)got=i;
  }
  try testing.expectEqual(@as(?usize,5),got);
  // half way between two samples reads half of each
  d.write(1);
  d.write(0);
  try testing.expectApproxEqAbs(@as(f32,0.5),d.read(1.5),0.001);
}
test"a voice sounds while held and falls silent after release"{
  // a saw voice
  var v:Voice=.init(testRate,.saw);
  // a block of samples, silent to start
  var buf:[480]f32=@splat(0);
  v.render(&buf);
  try testing.expectEqual(@as(f32,0),buf[100]);
  v.play(220);
  v.render(&buf);
  // the loudest sample in the block
  var peak:f32=0;
  for(buf)|s|peak=@max(peak,@abs(s));
  try testing.expect(peak>0.05);
  v.stop();
  for(0..100)|_|{
    @memset(&buf,0);
    v.render(&buf);
  }
  try testing.expectEqual(Adsr.Stage.idle,v.env.stage);
}
test"a hall answers an impulse late, keeps ringing for seconds, darkens and dies away"{
  // a hall ringing three seconds after 20 ms
  var h=Hall.init(3,0.02,5000,48000);
  // its answer to one click, block by block of a tenth of a second
  var first:?usize=null;
  var energy:[60]f32=@splat(0);
  for(0..48000*6)|i|{
    // the hall's answer this sample
    const y=h.tick(if(i==0)1 else 0);
    try testing.expect(y==y and @abs(y)<4);
    if(first==null and @abs(y)>1e-6)first=i;
    energy[i/4800]+=y*y;
  }
  // nothing before the pre-delay
  try testing.expect(first.?>=960);
  // still heard a second and a half on, about 30 dB down by three seconds,
  // and gone by six
  try testing.expect(energy[15]>1e-7);
  try testing.expect(energy[30]<energy[2]*0.01);
  try testing.expect(energy[59]<energy[2]*1e-4);
}
