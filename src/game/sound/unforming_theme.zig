//! the unforming's own theme, after Little Inferno's "Incident on the Other Side of the Wall" as the gardener heard it: a creak and swell as if the world is about to break under its own weight, one great deep horn, then a cacophony (rumbling, crumbling, masses falling), and over it a heavenly wall of choirs and strings, bright and consonant but never resolving over a held D, climbing and climbing, dipping and swelling again; fire, trumpets ringing out, fireworks rising that never burst; one woman's scream near the end, almost joining the choir; then it all falls slowly away into silence and a few rumbles of earth, and after the landing the garden's theme comes home on the bells.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: lerps, clamps, powers
const m=engine.core.math;
/// the engine's sound pieces: oscillators, noise, filters, pools
const dsp=engine.core.dsp;
/// the seeded random numbers the theme draws from
const rng=engine.core.rng;
/// the event's moments: when the seed falls and lands
const ev=lib.unforming;
/// the choir: four sections of eight voices singing "ahh"
const Choir=lib.sound.choir.Choir;
/// one note bowed on the strings
const Bow=lib.sound.nightVoices.Bow;
/// a timpani stroke
const Timpani=lib.sound.drums.Timpani;
/// a great taiko struck
const Taiko=lib.sound.drums.Taiko;
/// one note of the day's piano
const Plunk=lib.sound.voices.Plunk;
/// the day's music on paper: the garden's theme, its scale
const score=lib.sound.score;
/// steps in a motif (the theme's length)
const motif=score.motif;
/// quieter than this, a sound has ended
const silent=lib.sound.silent;
/// samples between retunings of a swept filter
const retune=lib.sound.sap.retune;
// decision: scored from the gardener's own hearing of the reference: no
// minor and no tune in the build, only a wall of suspended Lydian chords
// over a held D, bright and sorrowful, never resolving, the world's
// breaking heard round it; the garden's theme (score.theme) only comes
// home after the landing
// ---- when it all happens (s since the event began) ----
/// the world creaks and swells, about to give
const creakAt:f32=0;
/// the great horn: the beginning of the end; the wall and the cacophony begin
const hornAt:f32=1.6;
/// how long each chord of the wall is held before the next (s)
const chordS:f32=1.45;
/// the fireworks begin rising (the shards flying up to the star)
const fireworksAt:f32=8;
/// the burning begins
const fireAt:f32=8.5;
/// the trumpets ring out
const trumpetsAt:f32=hornAt+5*chordS;
/// the woman screams
const screamAt:f32=11.4;
/// the music begins to fall away, slowly, into the seed's fall
const fallAt:f32=12.5;
/// the drop: the seed falls (the music is falling away already)
const dropAt:f32=ev.shatterEnd;
/// the earth's last rumbles in the silence
const lastRumbles=[_]f32{dropAt+0.7,dropAt+1.5};
/// the landing
const landAt:f32=ev.landAt;
/// the theme comes home after the landing, upright, on the bells
const homeAt:f32=landAt+1.6;
/// how long one step of the theme lasts as it comes home (s)
const stepS:f32=0.3;
/// how soon after the landing the music gives the garden back, and how
/// slowly (s)
const giveBackAfter:f32=8;
/// (how slowly)
const giveBack:f32=10;
/// how fast the garden's music is cut at the start (s)
const cutIn:f32=0.25;
/// the moment the theme has rung away and the garden's music is back
const doneAt:f32=landAt+giveBackAfter+giveBack+1;
/// a moment that never comes
const never:f32=1e9;
/// how far the event's clock may drift from the theme's before it is mended (s)
pub const slip:f32=0.25;
/// cents in an octave: a tuning `c` cents off is a ratio of 2^(c/1200)
const centsPerOctave:f32=1200;
/// the ratio a tuning `c` cents off its note plays at
fn centsRatio(c:f32)f32{return m.pow(f32,2,c/centsPerOctave);}
/// the least random draw a wait is taken from (so no wait is endless)
const gapFloor:f32=1e-3;
/// a random wait (s) until the next of something heard `perS` times a
/// second on average, drawn from `r`
fn gap(r:*rng.Rng,perS:f32)f32{return -@log(@max(r.float(),gapFloor))/perS;}
/// how far round the stage masses fall and fireworks rise (pan, either way)
const scatterPan:f32=0.9;
/// how many notes a chord of the strings has (0 for none)
const bowNotes=6;
// ---- the bells: a celesta and glockenspiel struck together ----
/// a bell's partials (shares of its pitch), levels and rings (s)
const bellPartials=[_]f32{1,2,2.76,5.4};
/// (their levels)
const bellLevel=[bellPartials.len]f32{1,0.25,0.3,0.08};
/// (their rings)
const bellRing=[bellPartials.len]f32{2.4,1.3,0.9,0.4};
/// a bell's soft strike (s)
const bellAttack:f32=0.002;
/// how loud
const bell:f32=0.02;
/// one bell struck: a few partials ringing out
const Bell=struct{
  /// its partials
  osc:[bellPartials.len]dsp.Sine,
  /// each partial's level now
  amp:[bellPartials.len]f32=@splat(1),
  /// how much of its level each keeps a sample
  fall:[bellPartials.len]f32,
  /// samples since it was struck
  at:u32=0,
  /// samples its strike takes
  attack:u32,
  /// its loudness
  gain:f32,
  /// where it rings between the speakers
  place:dsp.Frame,
  /// MIDI `note` struck at velocity `vel`
  fn init(note:u8,vel:f32,rate:f32)Bell{
    // the note's pitch
    const hz=dsp.noteToHz(m.f(note));
    // the bell, its partials tuned below
    var b:Bell=.{.osc=undefined,.fall=undefined,.attack=m.floorTo(u32,bellAttack*rate)+1,.gain=vel*bell,.place=dsp.spot(lib.sound.voices.keyPan(m.f(note)))};
    for(&b.osc,&b.fall,bellPartials,bellRing)|*o,*f,p,ring|{
      o.*=.init(hz*p,rate);
      f.*=dsp.fall(ring,rate);
    }
    return b;
  }
  /// mixes it into `out`; false once rung out
  pub fn render(b:*Bell,out:[]dsp.Frame)bool{
    for(out)|*s|{
      // how far into its strike
      const rise=m.clamp01(m.f(b.at)/m.f(b.attack));
      b.at+|=1;
      var y:f32=0;
      for(&b.osc,&b.amp,b.fall,bellLevel)|*o,*a,f,l|{
        y+=o.next()*l*a.*;
        a.*=f*a.*;
      }
      s.*+=dsp.put(b.place,y*rise*b.gain);
    }
    return b.amp[0]>silent;
  }
};
// ---- the violins: one bowed line, high ----
/// how many players bow the line together, and how far apart (cents)
const fiddlers=4;
/// (how far apart)
const fiddleCents=[fiddlers]f32{-6,-2,3,7};
/// how fast and how deep their vibrato (Hz, cents)
const fiddleVibratoHz:f32=5.6;
/// (how deep)
const fiddleVibratoCents:f32=18;
/// how long their vibrato takes to grow in on a fresh note (s, ~63%)
const fiddleVibratoGrow:f32=0.35;
/// how quickly the line moves between notes (s, ~63%)
const fiddleLegato:f32=0.04;
/// how long the line takes to swell in and to die away (s, ~63%)
const fiddleSwell:f32=0.3;
/// what keeps it sweet (Hz), and the body's ring under it (Hz, q, level)
const fiddleDark:f32=4200;
/// (the body, Hz)
const fiddleBodyHz:f32=2800;
/// (its q)
const fiddleBodyQ:f32=1.2;
/// (its level)
const fiddleBody:f32=0.5;
/// where they sit (pan): the violins' side of the stage
const fiddlePan:f32=-0.3;
/// how far apart the players sit (pan)
const fiddleSpread:f32=0.4;
/// how loud
const fiddle:f32=0.03;
/// the violins: a few players a hair apart bowing one line, moving
/// legato from note to note, their vibrato growing in on each
const Fiddle=struct{
  /// each player's saw
  saws:[fiddlers]dsp.Osc,
  /// each player's tuning off the note (a ratio)
  tune:[fiddlers]f32,
  /// where each player sits
  seats:[fiddlers]dsp.Frame,
  /// the note it plays now (MIDI), gliding
  pitch:dsp.Smooth,
  /// its vibrato
  vibrato:dsp.Osc,
  /// how far its vibrato has grown in (0..1)
  grown:f32=0,
  /// how much of the way still to grow it keeps each sample
  grow:f32,
  /// how loud it is now, swelling and dying away
  swell:dsp.Smooth,
  /// what keeps it sweet, each side
  tone:dsp.StereoBiquad,
  /// the body's ring, each side
  body:dsp.StereoBiquad,
  /// samples a second
  rate:f32,
  /// a silent section, its players starting apart (drawn from `r`)
  fn init(r:*rng.Rng,rate:f32)Fiddle{
    // the section, its players tuned below
    var f:Fiddle=.{
      .saws=undefined,
      .tune=undefined,
      .seats=undefined,
      .pitch=.init(74,fiddleLegato,rate),
      .vibrato=.{.rate=rate,.freq=fiddleVibratoHz,.phase=r.float()},
      .grow=dsp.fall(fiddleVibratoGrow,rate),
      .swell=.init(0,fiddleSwell,rate),
      .tone=.init(.low,fiddleDark,0.707,rate),
      .body=.init(.band,fiddleBodyHz,fiddleBodyQ,rate),
      .rate=rate,
    };
    for(&f.saws,&f.tune,&f.seats,fiddleCents,0..)|*o,*t,*seat,cents,k|{
      o.*=.{.rate=rate,.shape=.saw,.phase=r.float()};
      t.*=centsRatio(cents);
      seat.*=dsp.spot(fiddlePan+(m.f(k)/(fiddlers-1)-0.5)*fiddleSpread);
    }
    return f;
  }
  /// play MIDI `note` at loudness `loud`
  fn play(f:*Fiddle,note:u8,loud:f32)void{
    // whether it is silent enough to start the note where it is
    const fresh=f.swell.value<0.02;
    f.pitch=.init(if(fresh)m.f(note)else f.pitch.value,fiddleLegato,f.rate);
    f.pitch.target=m.f(note);
    f.grown=0;
    f.swell.target=loud;
  }
  /// its next sample
  fn tick(f:*Fiddle)dsp.Frame{
    if(f.swell.target==0 and f.swell.value<silent)return@splat(0);
    f.grown=1-(1-f.grown)*f.grow;
    // the note bent by the vibrato, as a pitch
    const hz=dsp.noteToHz(f.pitch.next()+fiddleVibratoCents/100*f.grown*f.vibrato.next());
    // the players summed, each from its seat
    var y:dsp.Frame=@splat(0);
    for(&f.saws,f.tune,f.seats)|*o,t,seat|{
      o.freq=hz*t;
      y+=dsp.put(seat,o.next());
    }
    y=y*dsp.mid(1/m.f(fiddlers));
    return(f.tone.tick(y)+f.body.tick(y)*dsp.mid(fiddleBody))*dsp.mid(f.swell.next()*fiddle);
  }
};
// ---- the brass: trumpets ringing out, low brass under them ----
/// how many saws a horn's note is made of, and how far apart (cents)
const hornSaws=3;
/// (how far apart)
const hornCents=[hornSaws]f32{-6,0,7};
/// how long a horn takes to swell in and to die away (s, ~63%)
const hornSwell:f32=0.2;
/// how dark it is held back (Hz)
const hornDark:f32=300;
/// how far a trumpet and a low horn open as they swell (Hz)
const hornOpen=m.Vice(f32,2){5200,2400};
/// how much it rings where it is held back
const hornQ:f32=0.9;
/// how many horns play: two trumpets on the tune, two low horns on the chord
const hornCount=4;
/// where they sit (pan)
const hornPan=m.Vice(f32,hornCount){0.15,0.3,-0.35,-0.2};
/// how loud
const horn:f32=0.05;
/// one horn: a few saws a hair apart, held dark and opening brassy the
/// louder it swells
const Horn=struct{
  /// its saws
  saws:[hornSaws]dsp.Osc,
  /// each saw's tuning off the note (a ratio)
  tune:[hornSaws]f32,
  /// the note's pitch (Hz)
  hz:f32=100,
  /// how loud it is now, swelling and dying away
  swell:dsp.Smooth,
  /// how far it opens at its loudest (Hz)
  open:f32,
  /// what holds it dark, opening as it swells
  tone:dsp.Biquad,
  /// samples since it was last retuned
  at:u32=0,
  /// where it sits between the speakers
  place:dsp.Frame,
  /// samples a second
  rate:f32,
  /// a silent horn at `pan` opening `open` Hz, its saws starting apart (drawn from `r`)
  fn init(pan:f32,open:f32,r:*rng.Rng,rate:f32)Horn{
    // the horn, its saws tuned below
    var h:Horn=.{.saws=undefined,.tune=undefined,.swell=.init(0,hornSwell,rate),.open=open,.tone=.init(.low,hornDark,hornQ,rate),.place=dsp.spot(pan),.rate=rate};
    for(&h.saws,&h.tune,hornCents)|*o,*t,cents|{
      o.*=.{.rate=rate,.shape=.saw,.phase=r.float()};
      t.*=centsRatio(cents);
    }
    return h;
  }
  /// play MIDI `note` swelling to `loud`
  fn play(h:*Horn,note:u8,loud:f32)void{
    h.hz=dsp.noteToHz(m.f(note));
    h.swell=.init(h.swell.value,hornSwell,h.rate);
    h.swell.target=loud;
  }
  /// let go, dying away over about `s` seconds
  fn release(h:*Horn,s:f32)void{
    h.swell=.init(h.swell.value,s,h.rate);
    h.swell.target=0;
  }
  /// its next sample
  fn tick(h:*Horn)dsp.Frame{
    if(h.swell.target==0 and h.swell.value<silent)return@splat(0);
    // how loud it is now
    const s=h.swell.next();
    if(h.at%retune==0)h.tone.tune(.low,hornDark+h.open*@min(s*s,1),hornQ,h.rate);
    h.at+%=1;
    // the saws summed
    var y:f32=0;
    for(&h.saws,h.tune)|*o,t|{
      o.freq=h.hz*t;
      y+=o.next();
    }
    return dsp.put(h.place,h.tone.tick(y)*s*horn/hornSaws);
  }
};
// ---- the scream: one woman, far off ----
// decision: one voice, not a choir of them, so the scream is someone's:
// a throat's pulse (Rosenberg's glottal shape, shaking from cycle to cycle)
// through a woman's open "ah", out of tune with the score; echoed by the
// land (each echo the same voice later, quieter, darker, elsewhere)
/// how long her breath in lasts before the cry (s)
const inhaleS:f32=0.35;
/// the cry: how long it rises, holds and falls into a sob (s)
const riseS:f32=0.45;
/// (holds)
const holdS:f32=1.2;
/// (falls)
const sobS:f32=2.2;
// decision: she almost joins the choir, never quite: her crest sits 30
// cents over D6, the held D's high octave, her vibrato sliding about it
/// her pitch: where the cry starts, crests and the sob ends (Hz): from A5,
/// to just over D6, sinking to A4
const cryHz=m.Vice(f32,3){880,1196,440};
/// how far her pitch climbs as she holds the cry (cents)
const cryClimb:f32=60;
/// her vibrato as the cry holds, calm and strained (cents), and how fast (Hz)
const cryVibrato=m.Vice(f32,2){30,110};
/// (how fast)
const cryVibratoHz:f32=6.5;
/// where in the hold her voice breaks (s into the hold, from and to)
const breakS=m.Vice(f32,2){0.5,0.95};
/// how long her voice takes to break and to mend at either edge of it (s)
const breakEdge:f32=0.05;
/// how much her pitch shakes from cycle to cycle, steady and breaking (a share)
const jitter=m.Vice(f32,2){0.008,0.04};
/// how much her loudness shakes from cycle to cycle, steady and breaking (a share)
const shimmer=m.Vice(f32,2){0.06,0.25};
/// how rough the break is: rasp in the flow, and every other cycle weakened
const rasp:f32=0.5;
/// (every other cycle)
const subharmonic:f32=0.6;
/// the sob's tremble (Hz) and how deep (a share)
const sobHz:f32=6;
/// (how deep)
const sobDepth:f32=0.55;
/// the glottis: how long it opens and closes, shares of a cycle
const openShare:f32=0.42;
/// (closes)
const closeShare:f32=0.16;
/// her "ah", crying and sobbing: three formants (Hz), how sharp, how loud
const cryVowel=m.Vice(f32,3){1050,1650,2950};
/// (sobbing)
const sobVowel=m.Vice(f32,3){750,1200,2700};
/// (how sharp)
const vowelQ=m.Vice(f32,3){6,8,12};
/// (how loud)
const vowelLevel=m.Vice(f32,3){1,0.7,0.3};
/// the breath: its band (Hz) and how loud breathing in, crying and sobbing
const breathHz:f32=2400;
/// (how loud)
const breathLevel=m.Vice(f32,3){0.5,0.08,0.3};
/// how far off she is: what the distance leaves of her (Hz)
const screamFar:f32=3200;
/// how loud she is
const screamLoud:f32=0.09;
/// the land's echoes of her: how late (s), how loud, how dark (Hz)
const echoS=[_]f32{0.42,0.95,1.6,2.4};
/// (how loud)
const echoLevel=[echoS.len]f32{0.45,0.3,0.2,0.12};
/// (how dark)
const echoDark=[echoS.len]f32{2400,1800,1400,1000};
/// where she screams from, and her echoes (pan)
const screamPan:f32=0.35;
/// (her echoes, alternately to either side)
const echoPan:f32=0.7;
/// one scream heard: her breath, the cry rising, breaking and falling into a sob
const Scream=struct{
  /// seconds since it began (negative: an echo still on its way)
  age:f32,
  /// its own random numbers (an echo draws the same as its cry)
  r:rng.Rng,
  /// where in the glottis' cycle she is (0..1)
  phase:f32=0,
  /// this cycle's pitch and loudness shake (ratios)
  jit:f32=1,
  /// (loudness)
  shim:f32=1,
  /// whether this cycle is the weakened one of a pair
  odd:bool=false,
  /// the flow through the glottis a sample ago
  last:f32=0,
  /// her vibrato's phase (cycles)
  vib:f32=0,
  /// the breath's noise and its band
  breath:dsp.Noise,
  /// (its band)
  breathBand:dsp.Biquad,
  /// the rasp's noise
  grit:dsp.Noise,
  /// her vowel
  vowel:[3]dsp.Biquad,
  /// what the distance leaves of her
  far:dsp.OnePole,
  /// samples since the vowel was last retuned
  at:u32=0,
  /// how loud this one is heard
  gain:f32,
  /// where it is heard between the speakers
  place:dsp.Frame,
  /// samples a second
  rate:f32,
  /// her cry, its shake drawn from `seed`, heard `delay` seconds from now
  /// at `gain`, darkened above `dark`, at `pan`
  fn init(seed:u64,delay:f32,gain:f32,dark:f32,pan:f32,rate:f32)Scream{
    // its random numbers
    var r:rng.Rng=.init(seed);
    // the scream, its vowel tuned below
    var s:Scream=.{.age=-delay,.r=undefined,.breath=.init(r.next()),.breathBand=.init(.band,breathHz,0.8,rate),.grit=.init(r.next()),.vowel=undefined,.far=.init(dark,rate),.gain=gain,.place=dsp.spot(pan),.rate=rate};
    s.r=r;
    for(&s.vowel,0..)|*f,k|f.*=.init(.band,cryVowel[k],vowelQ[k],rate);
    return s;
  }
  /// how long it lasts, breath to the sob's end (s)
  fn length(s:*const Scream)f32{
    _=s;
    return inhaleS+riseS+holdS+sobS;
  }
  /// mixes it into `out`; false once it has ended
  pub fn render(s:*Scream,out:[]dsp.Frame)bool{
    // how long a sample lasts
    const dt=1/s.rate;
    for(out)|*o|{
      const a=s.age;
      s.age+=dt;
      if(a<0)continue;
      // how far into the voiced cry and into its hold, and where: rising, holding, sobbing
      const v=a-inhaleS;
      const held=v-riseS;
      const holdK=m.clamp01(held/holdS);
      const sobK=m.clamp01((held-holdS)/sobS);
      // whether her voice is breaking now (0..1, smooth at its edges)
      const bk=m.clamp01((held-breakS[0])/breakEdge)*(1-m.clamp01((held-breakS[1])/breakEdge));
      // her pitch: rising to the crest, climbing as she holds, sinking into the sob
      var hz=if(v<riseS)m.lerp(cryHz[0],cryHz[1],m.smooth(m.clamp01(v/riseS)))else m.lerp(cryHz[1],cryHz[2],m.smooth(sobK));
      hz*=centsRatio(cryClimb*holdK*(1-sobK)+m.lerp(cryVibrato[0],cryVibrato[1],holdK)*(1-sobK)*@sin(m.tau*s.vib));
      s.vib+=cryVibratoHz/s.rate;
      s.vib-=@floor(s.vib);
      // the glottis: a new cycle shakes anew
      s.phase+=hz*s.jit/s.rate;
      if(s.phase>=1){
        s.phase-=1;
        s.jit=1+s.r.range(-1,1)*m.lerp(jitter[0],jitter[1],bk);
        s.shim=1+s.r.range(-1,1)*m.lerp(shimmer[0],shimmer[1],bk);
        s.odd=!s.odd;
      }
      // the flow through it (Rosenberg's shape), and its change: the voice
      const p=s.phase;
      const flow=if(p<openShare)0.5*(1-@cos(m.pi*p/openShare))else if(p<openShare+closeShare)@cos(m.pi*0.5*(p-openShare)/closeShare)else 0;
      var src=(flow-s.last)*s.rate/@max(hz,1)*0.12;
      s.last=flow;
      src*=s.shim*(if(s.odd)1-subharmonic*bk else 1);
      src+=s.grit.next()*flow*rasp*bk;
      // how loud her voice is: in on the rise, trembling and fading through the sob
      const voiced:f32=if(v<0)0 else m.smooth(m.clamp01(v/0.12))*(1-m.smooth(sobK))*(1-sobDepth*sobK*(0.5+0.5*@sin(m.tau*sobHz*a)));
      // her vowel, opening into the cry, closing into the sob
      if(s.at%retune==0)for(&s.vowel,0..)|*f,k|f.tune(.band,m.lerp(cryVowel[k],sobVowel[k],sobK),vowelQ[k],s.rate);
      s.at+%=1;
      var y:f32=0;
      for(&s.vowel,vowelLevel)|*f,l|y+=f.tick(src)*l;
      y*=voiced;
      // her breath: drawn in, through the cry, ragged in the sob
      const br=if(v<0)breathLevel[0]*m.smooth(m.clamp01(a/inhaleS))else m.lerp(breathLevel[1],breathLevel[2],sobK)*(1-sobK*0.7);
      y+=s.breathBand.tick(s.breath.next())*br;
      o.*+=dsp.put(s.place,s.far.low(y)*s.gain*screamLoud);
    }
    return s.age<s.length();
  }
};
// ---- the world breaking ----
/// the creak: grains of strain ringing in timbers and stone, how many a
/// second, how long each, where they ring (Hz) and how sharply
const creakGrains:f32=35;
/// (how long each, s)
const creakGrain:f32=0.012;
/// (where they ring, Hz)
const creakHz=m.Vice(f32,3){130,215,480};
/// (how sharply)
const creakQ=m.Vice(f32,3){18,18,12};
/// how far the creak sinks as it strains (a share of its pitch)
const creakSink:f32=0.15;
/// how long it rings on under the horn before it is gone (s)
const creakAfter:f32=2.5;
/// how loud
const creak:f32=0.5;
/// the rumble: deep noise under everything (Hz), how loud it starts and grows to
const rumbleHz:f32=55;
/// (how loud)
const rumbleLevel=m.Vice(f32,3){0.3,0.5,1};
/// how slowly the rumble follows (s, ~63%)
const rumbleGlide:f32=0.8;
/// how loud the rumble is
const rumble:f32=0.22;
/// masses falling: how many a second as the cacophony starts and at its height
const debrisRate=m.Vice(f32,2){0.8,3.5};
/// the burning: crackles a second, how long each, where they ring (Hz)
const fireGrains:f32=250;
/// (how long each, s)
const fireGrain:f32=0.003;
/// (where they ring, Hz)
const fireHz:f32=2500;
/// its roar under the crackle (Hz)
const fireRoarHz:f32=300;
/// how slowly the burning swells (s, ~63%)
const fireGlide:f32=1.2;
/// how loud the crackle and the roar
const burning:f32=0.12;
/// (the roar)
const fireRoar:f32=1.5;
/// the fireworks: how many rise a second, from where to where (Hz), how long
const fireworksRate:f32=1.8;
/// (from, Hz)
const fireworkFrom=m.Vice(f32,2){350,550};
/// (to, Hz)
const fireworkTo=m.Vice(f32,2){1800,3200};
/// (how long, s)
const fireworkLen=m.Vice(f32,2){0.9,1.6};
/// how loud
const firework:f32=0.018;
/// how sharply a firework's whistle rings in its band
const whistleQ:f32=12;
/// how a fall is heard: its body's pitch (Hz), how long it rings (s), how
/// much crunch and gravel, and how long the gravel trickles (s)
const Fall=struct{
  /// its body's pitch (Hz)
  hz:f32,
  /// how long its body rings (s)
  ring:f32,
  /// how much crunch
  crunch:f32,
  /// how much gravel
  gravel:f32,
  /// how long the gravel trickles (s)
  trickle:f32,
};
/// a mass of stone hitting the ground (its pitch drawn between these, Hz)
const debrisHz=m.Vice(f32,2){50,85};
/// (the rest of it)
const debris=Fall{.hz=0,.ring=0.35,.crunch=0.7,.gravel=0.5,.trickle=0.6};
/// the earth rumbling in the silence
const earth=Fall{.hz=32,.ring=1.4,.crunch=0.15,.gravel=0.35,.trickle=1.6};
/// how far a fall's body is bent up as it strikes, and how fast it sinks (s)
const fallBend:f32=1.2;
/// (how fast)
const fallSink:f32=0.04;
/// the crunch's darkness (Hz), how fast it dies (s)
const crunchHz:f32=700;
/// (how fast)
const crunchFall:f32=0.08;
/// the gravel's grains a second
const gravelGrains:f32=900;
/// how loud a fall is
const fall:f32=0.05;
/// one mass falling and hitting the ground: a deep body bent sharp by the
/// blow, a crunch, gravel trickling after
const Thud=struct{
  /// its body
  body:dsp.Osc,
  /// its body's resting pitch (Hz)
  hz:f32,
  /// how much of the blow's bend is left (1 falling to 0)
  bent:f32=1,
  /// how much of the bend is kept each sample
  bentKeep:f32,
  /// its body's level now, and how much it keeps a sample
  amp:f32=1,
  /// (keeps)
  keep:f32,
  /// the crunch's noise and its darkening
  crunch:dsp.Noise,
  /// (its darkening)
  crunchLp:dsp.OnePole,
  /// the crunch's level now, and how much it keeps a sample
  crunchAmp:f32=1,
  /// (keeps)
  crunchKeep:f32,
  /// the gravel
  gravel:dsp.Crackle,
  /// the gravel's level now, and how much it keeps a sample
  gravelAmp:f32=1,
  /// (keeps)
  gravelKeep:f32,
  /// what it is
  shape:Fall,
  /// how loud
  gain:f32,
  /// where it falls between the speakers
  place:dsp.Frame,
  /// a fall shaped `f`, its body at `hz`, at `gain`, at `pan`
  fn init(f:Fall,hz:f32,gain:f32,pan:f32,r:*rng.Rng,rate:f32)Thud{
    // the gravel, as thick as it trickles
    var g:dsp.Crackle=.init(r.next(),0.004,rate);
    g.density=gravelGrains;
    return.{
      .body=.{.rate=rate,.freq=hz*(1+fallBend)},
      .hz=hz,
      .bentKeep=dsp.fall(fallSink,rate),
      .keep=dsp.fall(f.ring,rate),
      .crunch=.init(r.next()),
      .crunchLp=.init(crunchHz,rate),
      .crunchKeep=dsp.fall(crunchFall,rate),
      .gravel=g,
      .gravelKeep=dsp.fall(f.trickle,rate),
      .shape=f,
      .gain=gain,
      .place=dsp.spot(pan),
    };
  }
  /// mixes it into `out`; false once it has settled
  pub fn render(t:*Thud,out:[]dsp.Frame)bool{
    for(out)|*s|{
      t.bent*=t.bentKeep;
      t.body.freq=t.hz*(1+fallBend*t.bent);
      t.amp*=t.keep;
      t.crunchAmp*=t.crunchKeep;
      t.gravelAmp*=t.gravelKeep;
      // the body, the crunch (the darkened noise is small, so it is scaled
      // back up) and the gravel
      const y=t.body.next()*t.amp+t.crunchLp.low(t.crunch.next())*4*t.crunchAmp*t.shape.crunch+t.gravel.next()*t.gravelAmp*t.shape.gravel;
      s.*+=dsp.put(t.place,y*t.gain*fall);
    }
    return t.amp>silent or t.gravelAmp>silent;
  }
};
/// one firework rising into the sky, whistling, never bursting
const Whistle=struct{
  /// its tone
  tone:dsp.Osc,
  /// the air it rushes through, and the band its whistle rings in
  air:dsp.Noise,
  /// (the band)
  band:dsp.Biquad,
  /// where its pitch starts and ends (Hz)
  from:f32,
  /// (ends)
  to:f32,
  /// how long it rises (s)
  len:f32,
  /// how long it has risen (s)
  age:f32=0,
  /// samples since its band was last retuned
  at:u32=0,
  /// how loud
  gain:f32,
  /// where it rises between the speakers
  place:dsp.Frame,
  /// samples a second
  rate:f32,
  /// a firework drawn from `r`
  fn init(r:*rng.Rng,rate:f32)Whistle{
    // where its whistle starts
    const from=r.range(fireworkFrom[0],fireworkFrom[1]);
    return.{.tone=.{.rate=rate,.freq=from},.air=.init(r.next()),.band=.init(.band,from,whistleQ,rate),.from=from,.to=r.range(fireworkTo[0],fireworkTo[1]),.len=r.range(fireworkLen[0],fireworkLen[1]),.gain=r.range(0.6,1),.place=dsp.spot(r.range(-scatterPan,scatterPan)),.rate=rate};
  }
  /// mixes it into `out`; false once it has risen out of hearing
  pub fn render(w:*Whistle,out:[]dsp.Frame)bool{
    for(out)|*s|{
      // how far it has risen, and its pitch there
      const k=w.age/w.len;
      const hz=w.from*m.pow(f32,w.to/w.from,k);
      if(w.at%retune==0)w.band.tune(.band,hz,whistleQ,w.rate);
      w.at+%=1;
      w.tone.freq=hz;
      // in quickly, thinning out as it climbs
      const env=m.smooth(m.clamp01(k/0.15))*(1-m.smooth(m.clamp01((k-0.55)/0.45)));
      s.*+=dsp.put(w.place,(w.tone.next()*0.5+w.band.tick(w.air.next())*1.5)*env*w.gain*firework);
      w.age+=1/w.rate;
    }
    return w.age<w.len;
  }
};
// ---- the drums ----
/// where the kettles stand (pan)
const kettlePan=score.kettlePan;
/// the great taiko: its pitch (Hz) and how long it rings (s)
const boomHz=score.boomHz;
/// (how long it rings)
const boomRing:f32=1.6;
/// how hard the great taiko booms under each chord of the wall, first and last
const wallBoom=m.Vice(f32,2){0.45,0.95};
// ---- the wall: suspended Lydian chords over a held D ----
/// one chord of the wall: what the choirs sing, the strings bow, the
/// violins soar on, how loud, and the trumpets' two notes (0: not yet)
const Chord=struct{
  /// the choirs' notes (MIDI, soprano first)
  sing:[lib.sound.choir.sections]u8,
  /// the strings' notes (MIDI)
  bow:[bowNotes]u8,
  /// the violins' note (MIDI)
  high:u8,
  /// how loud the choirs (1 a night's full voice) and how hard the strings
  loud:f32,
  /// (how hard the strings)
  vel:f32,
  /// the trumpets' notes (MIDI; 0 not yet playing)
  trumpets:[2]u8=.{0,0},
};
/// the wall, a chord every `chordS` from the horn: climbing, dipping once,
/// climbing again, never resolving over the held D (Dmaj9, E/D, A/D, Bm9/D,
/// E/D again, F#m7/D, E/D high, Dmaj7#11)
const wall=[_]Chord{
  .{.sing=.{64,61,57,38},.bow=.{26,38,52,57,61,64},.high=76,.loud=0.8,.vel=1.4},
  .{.sing=.{68,64,59,38},.bow=.{26,38,56,59,64,68},.high=80,.loud=0.95,.vel=1.7},
  .{.sing=.{69,64,61,38},.bow=.{26,38,57,61,64,69},.high=81,.loud=1.1,.vel=2},
  .{.sing=.{71,66,61,38},.bow=.{26,38,59,61,66,71},.high=83,.loud=1.25,.vel=2.3},
  .{.sing=.{68,64,59,38},.bow=.{26,38,56,59,64,68},.high=80,.loud=1.2,.vel=2.2},
  .{.sing=.{73,69,64,38},.bow=.{26,38,57,64,69,73},.high=85,.loud=1.5,.vel=2.8,.trumpets=.{73,69}},
  .{.sing=.{76,71,64,38},.bow=.{26,38,59,64,71,76},.high=88,.loud=1.75,.vel=3.2,.trumpets=.{76,71}},
  .{.sing=.{78,68,61,38},.bow=.{26,38,61,68,73,78},.high=90,.loud=2,.vel=3.6,.trumpets=.{78,73}},
};
/// when chord `i` of the wall comes in
fn wallAt(i:usize)f32{return hornAt+m.f(i)*chordS;}
// ---- the score besides the wall ----
/// a chord the choirs sing: its four notes (MIDI, soprano first) and how loud
const Sing=struct{
  /// the notes
  notes:[lib.sound.choir.sections]u8,
  /// how loud (1 a night's full voice)
  loud:f32,
};
/// a chord the strings bow: its notes (MIDI, 0 for none) and how hard
const Bowed=struct{
  /// the notes
  notes:[bowNotes]u8,
  /// how hard (1 a night's bowing)
  vel:f32,
};
/// a chord the low horns hold: their notes (MIDI) and how loud
const Brass=struct{
  /// the notes
  notes:[2]u8,
  /// how loud
  loud:f32,
};
/// a stroke of the timpani, and the great taiko under it
const Strike=struct{
  /// the timpani's note (MIDI)
  note:u8,
  /// how hard
  vel:f32,
  /// how hard the great taiko booms under it (0: not at all)
  boom:f32=0,
};
/// one thing the score does
const What=union(enum){
  /// the choirs sing a chord
  sing:Sing,
  /// the choirs fall silent
  hush,
  /// the strings let their chord go and bow another
  bow:Bowed,
  /// the strings let their chord go
  unbow,
  /// the low horns hold a chord
  brass:Brass,
  /// the low horns let go, dying away over this long (s)
  unbrass:f32,
  /// the timpani strike, the great taiko under them
  strike:Strike,
  /// the music falls away, slowly
  fall,
  /// the seed lands: everything starts afresh
  land,
};
/// one moment of the score: when, and what
const Cue=struct{
  /// when (s since the event began)
  at:f32,
  /// what
  what:What,
};
/// the landing's chord: Dmaj7 with the raised fourth (C#5, G#4, F#3, D2)
const reborn=Sing{.notes=.{73,68,54,38},.loud=1.2};
/// the score besides the wall and the world breaking, in time order
const cues=[_]Cue{
  // the swell under the creak
  .{.at=creakAt,.what=.{.bow=.{.notes=.{26,38,45,0,0,0},.vel=1}}},
  .{.at=creakAt+0.3,.what=.{.sing=.{.notes=.{64,61,57,38},.loud=0.3}}},
  // the great horn
  .{.at=hornAt,.what=.{.brass=.{.notes=.{26,38},.loud=1.6}}},
  .{.at=hornAt,.what=.{.strike=.{.note=38,.vel=1,.boom=1}}},
  .{.at=hornAt+1.4,.what=.{.unbrass=1.2}},
  // the low horns hold the D as the trumpets ring out
  .{.at=trumpetsAt,.what=.{.brass=.{.notes=.{26,38},.loud=0.8}}},
  // it all falls away
  .{.at=fallAt,.what=.fall},
  .{.at=fallAt,.what=.{.unbrass=1.5}},
  // the landing: the bell and boom ring alone a moment, then the raised
  // fourth in the choirs and strings, and the theme comes home
  .{.at=landAt,.what=.land},
  .{.at=landAt,.what=.{.strike=.{.note=38,.vel=1,.boom=1}}},
  .{.at=landAt+0.3,.what=.{.bow=.{.notes=.{26,38,45,54,61,68},.vel=1.4}}},
  .{.at=landAt+0.7,.what=.{.sing=reborn}},
  .{.at=landAt+5,.what=.{.sing=.{.notes=reborn.notes,.loud=0.5}}},
  .{.at=landAt+8,.what=.unbow},
  .{.at=landAt+9,.what=.hush},
};
/// how loud the theme comes home on the bells and the piano
const homeBells:f32=0.5;
/// (the piano)
const homePiano:f32=0.35;
/// how far over the theme's own notes the bells and the piano play it (semitones)
const bellsUp:u8=24;
/// (the piano)
const pianoUp:u8=12;
// ---- the whole theme ----
/// how many bowed notes, timpani strokes, taiko booms, piano notes, bells,
/// screams, falls and fireworks may sound at once
const bowCount=24;
/// (timpani strokes)
const timpCount=8;
/// (taiko booms)
const boomCount=6;
/// (piano notes)
const plunkCount=12;
/// (bells)
const bellCount=16;
/// (screams: her cry and its echoes)
const screamCount=echoS.len+1;
/// (falls)
const thudCount=12;
/// (fireworks)
const whistleCount=8;
/// how many choirs sing (each its own voices, so the two thicken each
/// other as a great choir does)
const choirCount=2;
/// how fast the landing opens the music again (s, ~63%)
const gateS:f32=0.05;
/// how slowly the music falls away (s, ~63%)
const fallS:f32=0.7;
/// how much of the hall's tail is left once the music has fallen, and how
/// slowly it is taken (s, ~63%), so silence falls before the seed lands
const fallenTail:f32=0.25;
/// (how slowly)
const tailS:f32=0.8;
// decision: the world breaking was too loud and buried her scream (the
// gardener's word): it sits under the music, and gives way further for her
/// how much of the world breaking is left while she screams, and how fast
/// it gives way (s, ~63%)
const screamDuck:f32=0.4;
/// (how fast)
const duckS:f32=0.3;
/// how long before her scream the world begins to give way (s)
const duckLead:f32=0.3;
/// how loud the theme is
const level:f32=1.4;
/// samples rendered at a time
const chunk=256;
/// the unforming's theme played out, from its moment `clock`
pub const Theme=struct{
  /// samples a second
  rate:f32,
  /// its own random numbers
  r:rng.Rng,
  /// the seed her scream shakes by
  screamSeed:u64,
  /// the event's clock as the theme hears it (s)
  clock:f32,
  /// the next cue to play
  cue:usize,
  /// the next chord of the wall
  chord:usize,
  /// the next step of the theme coming home
  step:usize,
  /// whether she has screamed
  screamed:bool,
  /// when the next mass falls, and the next firework rises
  debrisAt:f32,
  /// (the next firework)
  fireworkAt:f32,
  /// how many of the earth's last rumbles have sounded
  rumbled:usize,
  /// the choirs
  choirs:[choirCount]Choir,
  /// the strings' chords
  bows:dsp.Pool(Bow,bowCount)=.{},
  /// the timpani
  timps:dsp.Pool(Timpani,timpCount)=.{},
  /// the great taiko
  booms:dsp.Pool(Taiko,boomCount)=.{},
  /// the piano
  plunks:dsp.Pool(Plunk,plunkCount)=.{},
  /// the bells
  bells:dsp.Pool(Bell,bellCount)=.{},
  /// the violins
  violins:Fiddle,
  /// the horns: two trumpets, two low horns
  horns:[hornCount]Horn,
  /// her scream and its echoes
  screams:dsp.Pool(Scream,screamCount)=.{},
  /// masses falling, and the earth's rumbles
  thuds:dsp.Pool(Thud,thudCount)=.{},
  /// fireworks rising
  whistles:dsp.Pool(Whistle,whistleCount)=.{},
  /// the creak's grains, and where they ring
  creakGrit:dsp.Crackle,
  /// (where they ring)
  creakBands:[3]dsp.Biquad,
  /// the rumble's noise and its darkening, each side
  rumbleNoise:[2]dsp.Noise,
  /// (its darkening)
  rumbleLp:dsp.StereoPole,
  /// how loud the rumble is now
  rumbleLoud:dsp.Smooth,
  /// the burning's crackle, its band, its roar and the roar's darkening
  fireGrit:dsp.Crackle,
  /// (its band)
  fireBand:dsp.Biquad,
  /// (its roar)
  roar:dsp.Noise,
  /// (the roar's darkening)
  roarLp:dsp.OnePole,
  /// how loud the burning is now
  fireLoud:dsp.Smooth,
  /// samples since the world's filters were last retuned
  at:u32=0,
  /// how much of the music is let through: falling away at the end, open
  /// again at the landing
  gate:dsp.Smooth,
  /// how much of the hall's tail is let through
  tail:dsp.Smooth,
  /// how much of the world breaking is heard: giving way while she screams
  world:dsp.Smooth,
  /// the theme heard from its moment `t`, drawn from `seed`
  pub fn init(t:f32,seed:u64,rate:f32)Theme{
    // its own random numbers, and whether `t` falls where the music is gone
    var r:rng.Rng=.init(seed);
    const gone=t>=fallAt and t<landAt;
    // the theme, its voices made below
    var th:Theme=.{
      .rate=rate,
      .r=r,
      .screamSeed=r.next(),
      .clock=t,
      .cue=0,
      .chord=0,
      .step=0,
      .screamed=t>screamAt,
      .debrisAt=@max(t,hornAt),
      .fireworkAt=@max(t,fireworksAt),
      .rumbled=0,
      .choirs=undefined,
      .violins=.init(&r,rate),
      .horns=undefined,
      .creakGrit=.init(r.next(),creakGrain,rate),
      .creakBands=undefined,
      .rumbleNoise=.{.init(r.next()),.init(r.next())},
      .rumbleLp=.init(rumbleHz,rate),
      .rumbleLoud=.init(0,rumbleGlide,rate),
      .fireGrit=.init(r.next(),fireGrain,rate),
      .fireBand=.init(.band,fireHz,0.6,rate),
      .roar=.init(r.next()),
      .roarLp=.init(fireRoarHz,rate),
      .fireLoud=.init(0,fireGlide,rate),
      .gate=.init(if(gone)0 else 1,gateS,rate),
      .tail=.init(if(gone)fallenTail else 1,tailS,rate),
      .world=.init(1,duckS,rate),
    };
    th.creakGrit.density=creakGrains;
    th.fireGrit.density=fireGrains;
    for(&th.creakBands,0..)|*f,k|f.*=.init(.band,creakHz[k],creakQ[k],rate);
    for(&th.choirs)|*ch|ch.*=.init(reborn.notes,&r,rate);
    th.horns=hornsOf(&r,rate);
    th.r=r;
    // what came before `t` is past
    while(th.cue<cues.len and cues[th.cue].at<t)th.cue+=1;
    while(th.chord<wall.len and wallAt(th.chord)<t)th.chord+=1;
    while(th.step<motif and homeAt+m.f(th.step)*stepS<t)th.step+=1;
    while(th.rumbled<lastRumbles.len and lastRumbles[th.rumbled]<t)th.rumbled+=1;
    return th;
  }
  /// the event's clock as told: only a slip is mended
  pub fn keep(th:*Theme,t:f32)void{
    if(@abs(t-th.clock)>slip)th.clock=t;
  }
  /// how much the garden's music gives way to it (0 none .. 1 all): cut at
  /// once as it begins, given back slowly after the landing
  pub fn hush(th:*const Theme)f32{
    return m.smooth(m.clamp01(th.clock/cutIn))*(1-m.smooth(m.clamp01((th.clock-landAt-giveBackAfter)/giveBack)));
  }
  /// how much of the hall's tail is let through (taken down as the music falls)
  pub fn tailLeft(th:*const Theme)f32{return th.tail.value;}
  /// whether it has rung away and the garden's music is back
  pub fn done(th:*const Theme)bool{return th.clock>doneAt;}
  /// mixes the next samples into `dry` (heard on the stage) and `far` (her
  /// scream, heard from far off: mostly through the hall), playing what the
  /// score holds as its moments come
  pub fn render(th:*Theme,dry:[]dsp.Frame,far:[]dsp.Frame)void{
    // how far into the buffers it has played
    var i:usize=0;
    while(i<dry.len){
      th.fire();
      // how many samples until the next thing happens, at most a chunk
      const k=@min(dry.len-i,th.until(),chunk);
      th.play(dry[i..][0..k],far[i..][0..k]);
      th.clock+=m.f(k)/th.rate;
      i+=k;
    }
  }
  /// when the next chord of the wall comes in
  fn chordAt(th:*const Theme)f32{return if(th.chord<wall.len)wallAt(th.chord)else never;}
  /// when the next step of the theme coming home sounds
  fn stepAt(th:*const Theme)f32{return if(th.step<motif)homeAt+m.f(th.step)*stepS else never;}
  /// when the earth next rumbles in the silence
  fn rumbleAt(th:*const Theme)f32{return if(th.rumbled<lastRumbles.len)lastRumbles[th.rumbled]else never;}
  /// samples until the next thing the score does (at least one)
  fn until(th:*const Theme)usize{
    // the soonest of everything still to come
    var next=@min(@min(th.chordAt(),th.stepAt()),@min(th.rumbleAt(),if(th.screamed)never else screamAt));
    if(th.debrisAt<fallAt)next=@min(next,th.debrisAt);
    if(th.fireworkAt<fallAt)next=@min(next,th.fireworkAt);
    if(th.cue<cues.len)next=@min(next,cues[th.cue].at);
    if(next>=never)return chunk;
    return@max(1,m.floorTo(usize,@max(next-th.clock,0)*th.rate)+1);
  }
  /// everything the score does by now
  fn fire(th:*Theme)void{
    while(th.cue<cues.len and cues[th.cue].at<=th.clock):(th.cue+=1)th.cueOf(cues[th.cue].what);
    while(th.chordAt()<=th.clock):(th.chord+=1)th.wallChord(th.chord);
    while(th.stepAt()<=th.clock):(th.step+=1){
      const i=score.theme[th.step] orelse continue;
      const n=score.scaleNote(i);
      th.bells.add(.init(n+bellsUp,homeBells,th.rate));
      th.plunks.add(.init(n+pianoUp,homePiano,&th.r,th.rate));
    }
    while(th.rumbleAt()<=th.clock):(th.rumbled+=1)th.thuds.add(.init(earth,earth.hz,1,th.r.range(-0.5,0.5),&th.r,th.rate));
    if(!th.screamed and screamAt<=th.clock){
      th.screamed=true;
      th.scream();
    }
    // masses falling, thicker as it goes on
    while(th.debrisAt<=th.clock and th.debrisAt<fallAt){
      th.thuds.cycle(.init(debris,th.r.range(debrisHz[0],debrisHz[1]),th.r.range(0.5,1),th.r.range(-scatterPan,scatterPan),&th.r,th.rate));
      const k=m.clamp01((th.debrisAt-hornAt)/(fallAt-hornAt));
      th.debrisAt+=gap(&th.r,m.lerp(debrisRate[0],debrisRate[1],k));
    }
    // fireworks rising
    while(th.fireworkAt<=th.clock and th.fireworkAt<fallAt){
      th.whistles.cycle(.init(&th.r,th.rate));
      th.fireworkAt+=gap(&th.r,fireworksRate);
    }
  }
  /// chord `i` of the wall comes in on the choirs, strings, violins and
  /// (late) trumpets, the great taiko under it
  fn wallChord(th:*Theme,i:usize)void{
    // the chord, and how far up the wall it is
    const c=wall[i];
    const k=m.f(i)/m.f(wall.len-1);
    th.sing(c.sing,c.loud);
    th.bow(c.bow,c.vel);
    th.violins.play(c.high,m.lerp(0.6,1.3,k));
    if(c.trumpets[0]!=0)for(th.horns[0..2],c.trumpets)|*h,note|h.play(note,m.lerp(0.7,1.1,k));
    th.boom(m.lerp(wallBoom[0],wallBoom[1],k));
  }
  /// both choirs sing `notes` at `loud`
  fn sing(th:*Theme,notes:[lib.sound.choir.sections]u8,loud:f32)void{
    for(&th.choirs)|*ch|ch.sing(notes,loud,&th.r);
  }
  /// the strings let their chord go and bow `notes` (0 for none) at `vel`
  fn bow(th:*Theme,notes:[bowNotes]u8,vel:f32)void{
    th.unbow();
    for(notes)|note|if(note!=0)th.bows.add(.init(note,vel,&th.r,th.rate));
  }
  /// the great taiko booms, as hard as `vel`
  fn boom(th:*Theme,vel:f32)void{
    th.booms.cycle(.init(boomHz,boomRing,vel,0,&th.r,th.rate));
  }
  /// the horns made afresh, silent, drawn from `r`: two trumpets, two low horns
  fn hornsOf(r:*rng.Rng,rate:f32)[hornCount]Horn{
    // the horns, each at its seat
    var hs:[hornCount]Horn=undefined;
    for(&hs,0..)|*h,k|h.*=.init(hornPan[k],hornOpen[k/2],r,rate);
    return hs;
  }
  /// her scream, and the land's echoes of it
  fn scream(th:*Theme)void{
    th.screams.add(.init(th.screamSeed,0,1,screamFar,screamPan,th.rate));
    for(echoS,echoLevel,echoDark,0..)|d,l,dark,k|th.screams.add(.init(th.screamSeed,d,l,dark,if(k%2==0)-echoPan else echoPan,th.rate));
  }
  /// does what one cue says
  fn cueOf(th:*Theme,w:What)void{
    switch(w){
      .sing=>|s|th.sing(s.notes,s.loud),
      .hush=>for(&th.choirs)|*ch|ch.hush(),
      .bow=>|b|th.bow(b.notes,b.vel),
      .unbow=>th.unbow(),
      .brass=>|b|for(th.horns[2..],b.notes)|*h,note|h.play(note,b.loud),
      .unbrass=>|s|for(th.horns[2..])|*h|h.release(s),
      .strike=>|s|{
        th.timps.cycle(.init(s.note,s.vel,0,kettlePan[0],&th.r,th.rate));
        if(s.boom>0)th.boom(s.boom);
      },
      .fall=>{
        th.gate=.init(th.gate.value,fallS,th.rate);
        th.gate.target=0;
        th.tail.target=fallenTail;
      },
      .land=>{
        // every voice silenced and made afresh, so the landing blooms from nothing
        for(&th.choirs)|*ch|ch.*=.init(reborn.notes,&th.r,th.rate);
        th.bows.clear();
        th.timps.clear();
        th.booms.clear();
        th.plunks.clear();
        th.bells.clear();
        th.screams.clear();
        th.whistles.clear();
        th.violins=.init(&th.r,th.rate);
        th.horns=hornsOf(&th.r,th.rate);
        th.gate=.init(0,gateS,th.rate);
        th.gate.target=1;
        th.tail.target=1;
      },
    }
  }
  /// the strings let their chord go
  fn unbow(th:*Theme)void{
    for(&th.bows.slots)|*v|if(v.*)|*b|b.release();
  }
  /// how loud the creak is now: swelling to the horn, ringing on under it, gone
  fn creakNow(th:*const Theme)f32{
    return m.smooth(m.clamp01((th.clock-creakAt)/(hornAt-creakAt)))*(1-m.smooth(m.clamp01((th.clock-hornAt)/creakAfter)));
  }
  /// plays `dry.len` samples (at most a chunk) of everything sounding
  fn play(th:*Theme,dry:[]dsp.Frame,far:[]dsp.Frame)void{
    // the music before the gate
    var stage:[chunk]dsp.Frame=@splat(@splat(0));
    const s=stage[0..dry.len];
    for(&th.choirs)|*ch|ch.render(s);
    th.bows.render(s);
    th.timps.render(s);
    th.booms.render(s);
    th.plunks.render(s);
    th.bells.render(s);
    // the world breaking and her scream, past the gate: the music falls
    // away, the world goes on
    var broken:[chunk]dsp.Frame=@splat(@splat(0));
    const w=broken[0..dry.len];
    th.thuds.render(w);
    th.whistles.render(w);
    th.screams.render(far);
    // how loud the creak, the rumble and the burning should be now
    const cr=th.creakNow();
    const into=m.clamp01((th.clock-hornAt)/(fallAt-hornAt));
    th.rumbleLoud.target=if(th.clock<hornAt)rumbleLevel[0]*cr else if(th.clock<fallAt)m.lerp(rumbleLevel[1],rumbleLevel[2],into)else 0;
    th.fireLoud.target=if(th.clock>=fireAt and th.clock<fallAt)1 else 0;
    th.world.target=if(th.clock>=screamAt-duckLead and th.clock<landAt)screamDuck else 1;
    for(dry,s,w)|*d,x,b|{
      // the violins and the horns, then the gate over all of it
      var z=x+th.violins.tick();
      for(&th.horns)|*h|z+=h.tick();
      d.*+=z*dsp.mid(th.gate.next()*level);
      _=th.tail.next();
      // the creak: its grains ringing in timbers and stone, sinking as they strain
      if(cr>silent){
        if(th.at%retune==0)for(&th.creakBands,0..)|*f,k|f.tune(.band,creakHz[k]*(1-creakSink*cr),creakQ[k],th.rate);
        const g=th.creakGrit.next();
        var y:f32=0;
        for(&th.creakBands)|*f|y+=f.tick(g);
        d.*+=dsp.pan(y*cr*creak,-0.2);
      }
      th.at+%=1;
      // the world breaking, giving way for her: the falls and fireworks,
      // the rumble (the darkened noise is small, so it is scaled back up)
      var wb=b;
      const rl=th.rumbleLoud.next();
      if(rl>silent)wb+=th.rumbleLp.low(.{th.rumbleNoise[0].next(),th.rumbleNoise[1].next()})*dsp.mid(rl*rumble*12);
      // the burning
      const fl=th.fireLoud.next();
      if(fl>silent)wb+=dsp.mid((th.fireBand.tick(th.fireGrit.next())+th.roarLp.low(th.roar.next())*fireRoar)*fl*burning);
      d.*+=wb*dsp.mid(th.world.next());
    }
  }
};
/// the sample rate the tests render at (samples a second)
const testRate:f32=48000;
/// the test harness
const testing=lib.std.testing;
test"the score runs in time order, the wall climbs to its last chord before it falls, the landing where the seed lands"{
  // the last cue's moment
  var last:f32=0;
  for(cues)|c|{
    try testing.expect(c.at>=last);
    last=c.at;
    if(c.what==.land)try testing.expectEqual(landAt,c.at);
  }
  // the wall ends higher than it began, held on D throughout, before it falls
  try testing.expect(wallAt(wall.len-1)<fallAt and fallAt<dropAt);
  try testing.expect(wall[wall.len-1].sing[0]>wall[0].sing[0]);
  for(wall)|c|try testing.expectEqual(@as(u8,38),c.sing[3]);
  try testing.expect(screamAt<fallAt and screamAt>wallAt(5));
}
/// the theme from its first moment to its end: it creaks, builds without a
/// break, screams, falls away and blooms again at the landing (heard
/// beside the other long listens, sound/tests.zig)
pub fn listenTheme()lib.sound.tests.Failed!void{
  // the theme from its first moment, the loudness (rms) of each half
  // second, of the stage and of her scream
  var th:Theme=.init(0,11,testRate);
  var dry:[480]dsp.Frame=undefined;
  var far:[480]dsp.Frame=undefined;
  var rms:[80]f32=@splat(0);
  var cry:[80]f32=@splat(0);
  var peak:f32=0;
  // the block, and its half second
  var b:usize=0;
  while(!th.done() and b<4000):(b+=1){
    const half=b/50;
    @memset(&dry,@splat(0));
    @memset(&far,@splat(0));
    th.render(&dry,&far);
    for(dry,far)|x,y|{
      rms[half]+=m.sumOf(f32,2,x*x)*0.5;
      cry[half]+=m.sumOf(f32,2,y*y)*0.5;
      peak=@max(peak,@abs(x[0]),@abs(x[1]),@abs(y[0]),@abs(y[1]));
    }
  }
  for(&rms,&cry)|*a,*c|{
    a.*=@sqrt(a.*/(testRate/2));
    c.*=@sqrt(c.*/(testRate/2));
  }
  // it rings away and never clips
  try testing.expect(th.done());
  try testing.expect(peak<1);
  // the creak is heard before the horn, and every half second of the build
  const start=rms[2];
  try testing.expect(start>1e-4);
  for(4..@intFromFloat(fallAt*2))|h|try testing.expect(rms[h]>start);
  // the top far louder than the creak
  try testing.expect(rms[@intFromFloat(fallAt*2-1)]>start*5);
  // she screams near the end and not before
  try testing.expect(cry[@intFromFloat(screamAt*2+1)]>1e-3);
  try testing.expect(cry[@intFromFloat(screamAt*2-2)]<1e-6);
  // it has fallen from its top by the time the seed lands, and the landing opened the music again
  try testing.expect(rms[@intFromFloat(landAt*2-1)]<rms[@intFromFloat(fallAt*2-1)]);
  try testing.expect(th.gate.value>0.5);
}
