//! the unforming's own theme: the garden's music breaking. The music cuts, a lone cello plays the garden's Lydian line over a choir's hum, its raised fourth bends down and the key falls into D minor, a heartbeat of timpani and the choir's falling lament build to the whole orchestra with brass, the world screaming far off under it; all of it drops out for the seed's fall, and the landing brings the raised fourth back in bells, choir and strings.
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
/// quieter than this, a sound has ended
const silent=lib.sound.silent;
/// samples between retunings of a swept filter
const retune=lib.sound.sap.retune;
// decision: the theme is the garden's own D Lydian broken: its raised
// fourth (G#, the sound of wonder) bends down to G and the key falls into D
// minor, and the landing gives the G# back; scored for the instruments the
// garden already has (choir, strings, timpani, taiko) with a cello and
// brass, so it rings in the same great hall as the day's and night's music
// ---- when it all happens (s since the event began) ----
/// the music cuts at once, and this long it is silent
const silenceS:f32=1;
/// the lament: the cello alone over the choir's hum, still in Lydian
const lamentAt:f32=silenceS;
/// the bend: the raised fourth bends down, the heartbeat begins
const bendAt:f32=5;
/// the loss: the key has fallen, the choir's line falls, the timpani roll
/// swells up into the peak
const lossAt:f32=7.5;
/// the peak: the whole orchestra, brass and all, the world screaming under it
const peakAt:f32=10;
/// the drop: everything stops for the seed's fall
const dropAt:f32=ev.shatterEnd;
/// the landing: the raised fourth returns
const landAt:f32=ev.landAt;
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
// ---- the cello: one bow singing the line ----
/// how many strings bow the cello's note together (a section, a hair apart)
const celloStrings=3;
/// how far apart they are tuned (cents)
const celloCents=[celloStrings]f32{-4,0,5};
/// how fast and how deep its vibrato (Hz, cents)
const celloVibratoHz:f32=5.2;
/// (how deep, cents)
const celloVibratoCents:f32=16;
/// how long its vibrato takes to grow in on a fresh note (s, ~63%)
const celloVibratoGrow:f32=0.5;
/// how quickly it moves between notes when not bending (s, ~63%)
const celloLegato:f32=0.05;
/// how long a stroke takes to swell in and to die away (s, ~63%)
const celloSwell:f32=0.25;
/// what keeps it warm (Hz) and the wood's body ringing under it (Hz, q, level)
const celloDark:f32=1900;
/// (the wood, Hz)
const celloWoodHz:f32=230;
/// (its q)
const celloWoodQ:f32=1.4;
/// (its level)
const celloWood:f32=0.6;
/// the bow's hair on the string: noise this high (Hz), this loud
const celloHairHz:f32=1600;
/// (this loud)
const celloHair:f32=0.03;
/// where it sits (pan): the cellos' side of the stage
const celloPan:f32=0.2;
/// how loud
const cello:f32=0.035;
/// the cello: a few saws a hair apart bowing one line, gliding or bending
/// between notes, its vibrato growing in on each, warmed and given a body
const Cello=struct{
  /// its strings' saws
  saws:[celloStrings]dsp.Osc,
  /// each string's tuning off the note (a ratio)
  tune:[celloStrings]f32,
  /// the note it plays now (MIDI), gliding
  pitch:dsp.Smooth,
  /// its vibrato
  vibrato:dsp.Osc,
  /// how far its vibrato has grown in (0..1)
  grown:f32=0,
  /// how much of the way still to grow it keeps each sample
  grow:f32,
  /// how loud it is now (0..1), swelling and dying away
  swell:dsp.Smooth,
  /// what warms it
  tone:dsp.Biquad,
  /// the wood's body
  wood:dsp.Biquad,
  /// the bow hair's noise, and the band it rasps in
  hair:dsp.Noise,
  /// (the band)
  hairBand:dsp.Biquad,
  /// where it sits between the speakers
  place:dsp.Frame,
  /// samples a second
  rate:f32,
  /// a silent cello, its quirks drawn from `r`
  fn init(r:*rng.Rng,rate:f32)Cello{
    // the cello, its strings tuned below
    var c:Cello=.{
      .saws=undefined,
      .tune=undefined,
      .pitch=.init(50,celloLegato,rate),
      .vibrato=.{.rate=rate,.freq=celloVibratoHz,.phase=r.float()},
      .grow=dsp.fall(celloVibratoGrow,rate),
      .swell=.init(0,celloSwell,rate),
      .tone=.init(.low,celloDark,0.707,rate),
      .wood=.init(.band,celloWoodHz,celloWoodQ,rate),
      .hair=.init(r.next()),
      .hairBand=.init(.band,celloHairHz,1,rate),
      .place=dsp.spot(celloPan),
      .rate=rate,
    };
    for(&c.saws,&c.tune,celloCents)|*o,*t,cents|{
      o.*=.{.rate=rate,.shape=.saw,.phase=r.float()};
      t.*=m.pow(f32,2,cents/1200);
    }
    return c;
  }
  /// play MIDI `note`: bending there over `glide` seconds, or (0) moving
  /// straight there, a fresh note whose vibrato grows in again
  fn play(c:*Cello,note:f32,glide:f32)void{
    // whether it is silent enough to start the note where it is
    const fresh=c.swell.value<0.02;
    c.pitch=.init(if(fresh)note else c.pitch.value,if(glide>0)glide else celloLegato,c.rate);
    c.pitch.target=note;
    if(glide==0)c.grown=0;
    c.swell.target=1;
  }
  /// let the note go: it dies away
  fn rest(c:*Cello)void{c.swell.target=0;}
  /// its next sample
  fn tick(c:*Cello)dsp.Frame{
    if(c.swell.target==0 and c.swell.value<silent)return@splat(0);
    c.grown=1-(1-c.grown)*c.grow;
    // the note bent by the vibrato, as a pitch
    const hz=dsp.noteToHz(c.pitch.next()+celloVibratoCents/100*c.grown*c.vibrato.next());
    // the strings summed, with the hair's rasp
    var y:f32=0;
    for(&c.saws,c.tune)|*o,t|{
      o.freq=hz*t;
      y+=o.next();
    }
    y=y/celloStrings+c.hairBand.tick(c.hair.next())*celloHair;
    return dsp.put(c.place,(c.tone.tick(y)+c.wood.tick(y)*celloWood)*c.swell.next()*cello);
  }
};
// ---- the brass: low horns opening as they swell ----
/// how many saws a horn's note is made of, and how far apart (cents)
const hornSaws=3;
/// (how far apart)
const hornCents=[hornSaws]f32{-6,0,7};
/// how long a horn takes to swell in and to die away (s, ~63%)
const hornSwell:f32=0.35;
/// how dark it is held back, and how far it opens as it swells (Hz)
const hornDark:f32=280;
/// (how far it opens)
const hornOpen:f32=2400;
/// how much it rings where it is held back
const hornQ:f32=0.9;
/// where the two horns sit (pan)
const hornPan=m.Vice(f32,4){-0.35,-0.2,-0.05,0.1};
/// how loud
const horn:f32=0.06;
/// how many horns play (each a note)
const hornCount=4;
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
  /// what holds it dark, opening as it swells
  tone:dsp.Biquad,
  /// samples since it was last retuned
  at:u32=0,
  /// where it sits between the speakers
  place:dsp.Frame,
  /// samples a second
  rate:f32,
  /// a silent horn at `pan`, its saws starting apart (drawn from `r`)
  fn init(pan:f32,r:*rng.Rng,rate:f32)Horn{
    // the horn, its saws tuned below
    var h:Horn=.{.saws=undefined,.tune=undefined,.swell=.init(0,hornSwell,rate),.tone=.init(.low,hornDark,hornQ,rate),.place=dsp.spot(pan),.rate=rate};
    for(&h.saws,&h.tune,hornCents)|*o,*t,cents|{
      o.*=.{.rate=rate,.shape=.saw,.phase=r.float()};
      t.*=m.pow(f32,2,cents/1200);
    }
    return h;
  }
  /// play MIDI `note` swelling to `loud` (0..1)
  fn play(h:*Horn,note:u8,loud:f32)void{
    h.hz=dsp.noteToHz(m.f(note));
    h.swell.target=loud;
  }
  /// its next sample
  fn tick(h:*Horn)dsp.Frame{
    if(h.swell.target==0 and h.swell.value<silent)return@splat(0);
    // how loud it is now
    const s=h.swell.next();
    if(h.at%retune==0)h.tone.tune(.low,hornDark+hornOpen*s*s,hornQ,h.rate);
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
// ---- the world screaming, far off ----
// decision: until the starlit patches fire their beams up (they are not in
// the game yet), the world screams as its light is torn out: the voices
// come in one by one through the loss and the peak and stop dead at the drop
/// when each voice comes in (s since the event began), and the note it
/// screams (MIDI): high in D minor, a C and a G straining against it
const wailAt=[_]f32{6,6.7,7.4,8.1,8.8,9.5,10.2,10.9};
/// (the notes)
const wailNote=[wailAt.len]f32{74,81,77,86,72,79,84,89};
/// how far under its note a voice scoops in from (semitones), and how long
/// it takes (s)
const wailScoop:f32=3;
/// (how long)
const wailRise:f32=0.7;
/// how far it climbs as it strains (semitones)
const wailClimb:f32=1.5;
/// how long it takes to strain all the way (s)
const wailStrain:f32=4;
/// its vibrato, calm and strained (cents, Hz)
const wailVibratoCents=m.Vice(f32,2){15,70};
/// (Hz)
const wailVibratoHz=m.Vice(f32,2){5.5,7};
/// its voice cracks once: how far up (semitones, least and most), how long (s)
const wailCrackBy=m.Vice(f32,2){4,7};
/// (how long)
const wailCrackTime:f32=0.35;
/// when it cracks (s after it came in, earliest and latest)
const wailCrackAt=m.Vice(f32,2){1.2,3.5};
/// its throat's roughness as it strains, and how slowly it shakes (Hz)
const wailGrowl:f32=0.35;
/// (how slowly)
const wailGrowlHz:f32=70;
/// how much breath is in it
const wailBreath:f32=0.15;
/// its vowel's three formants, calm ("ahh") and strained (opening to a cry):
/// where (Hz), how sharp and how loud
const wailCalm=m.Vice(f32,3){800,1150,2900};
/// (strained)
const wailStrained=m.Vice(f32,3){1050,1650,3100};
/// (how sharp)
const wailQ=m.Vice(f32,3){10,12,24};
/// (how loud, calm)
const wailCalmLevel=m.Vice(f32,3){1,0.5,0.025};
/// (how loud, strained)
const wailStrainedLevel=m.Vice(f32,3){1,0.6,0.12};
/// what the distance leaves of it (Hz)
const wailFar:f32=2200;
/// how long a voice takes to swell in (s, ~63%)
const wailSwell:f32=0.8;
/// how far to either side the voices scream from (pan)
const wailSide:f32=0.85;
/// how loud each
const wail:f32=0.04;
/// one voice of the world screaming: a throat's buzz shaped into a vowel
/// that opens into a cry as it strains, scooping in, climbing, its vibrato
/// widening, cracking once, heard from far off
const Wail=struct{
  /// its throat
  osc:dsp.Osc,
  /// its note (MIDI)
  note:f32,
  /// how long it has screamed (s)
  age:f32=0,
  /// when it cracks (s after it came in), and how far up
  crackAt:f32,
  /// (how far up, semitones)
  crackBy:f32,
  /// its vibrato
  vibrato:dsp.Osc,
  /// the noise its throat shakes by, slowed
  rough:dsp.Noise,
  /// (slowed)
  roughLp:dsp.OnePole,
  /// its breath
  breath:dsp.Noise,
  /// its vowel's formants
  vowel:[3]dsp.Biquad,
  /// how loud each formant is now
  gains:m.Vice(f32,3)=wailCalmLevel,
  /// what the distance leaves of it
  far:dsp.OnePole,
  /// how loud it is now, swelling in
  swell:dsp.Smooth,
  /// samples since it was last retuned
  at:u32=0,
  /// where it screams from between the speakers
  place:dsp.Frame,
  /// samples a second
  rate:f32,
  /// a voice screaming MIDI `note`, its quirks and place drawn from `r`
  fn init(note:f32,r:*rng.Rng,rate:f32)Wail{
    // the voice, its vowel tuned below
    var w:Wail=.{
      .osc=.{.rate=rate,.shape=.saw,.phase=r.float()},
      .note=note,
      .crackAt=r.range(wailCrackAt[0],wailCrackAt[1]),
      .crackBy=r.range(wailCrackBy[0],wailCrackBy[1]),
      .vibrato=.{.rate=rate,.freq=wailVibratoHz[0],.phase=r.float()},
      .rough=.init(r.next()),
      .roughLp=.init(wailGrowlHz,rate),
      .breath=.init(r.next()),
      .vowel=undefined,
      .far=.init(wailFar,rate),
      .swell=.init(0,wailSwell,rate),
      .place=dsp.spot(r.range(-wailSide,wailSide)),
      .rate=rate,
    };
    for(&w.vowel,0..)|*f,k|f.*=.init(.band,wailCalm[k],wailQ[k],rate);
    w.swell.target=1;
    return w;
  }
  /// mixes it into `out`; it screams until it is stopped
  pub fn render(w:*Wail,out:[]dsp.Frame)bool{
    for(out)|*s|{
      // how far it has strained (0..1)
      const st=m.clamp01(w.age/wailStrain);
      if(w.at%retune==0){
        for(&w.vowel,0..)|*f,k|{
          f.tune(.band,m.lerp(wailCalm[k],wailStrained[k],st),wailQ[k],w.rate);
          w.gains[k]=m.lerp(wailCalmLevel[k],wailStrainedLevel[k],st);
        }
        w.vibrato.freq=m.lerp(wailVibratoHz[0],wailVibratoHz[1],st);
      }
      w.at+%=1;
      // how far under its note it still is, and how far its crack lifts it
      const scoop=wailScoop*(1-m.smooth(m.clamp01(w.age/wailRise)));
      const ck=(w.age-w.crackAt)/wailCrackTime;
      const crack=if(ck>0 and ck<1)w.crackBy*@sin(m.pi*ck)else 0;
      // its vibrato now (cents)
      const cents=m.lerp(wailVibratoCents[0],wailVibratoCents[1],st)*w.vibrato.next();
      w.osc.freq=dsp.noteToHz(w.note-scoop+wailClimb*st+crack+cents/100);
      // the throat, shaking as it strains (the slowed noise is small, so it
      // is scaled back up), and its breath
      const src=w.osc.next()*(1+wailGrowl*st*30*w.roughLp.low(w.rough.next()))+w.breath.next()*wailBreath;
      // the vowel shaped out of it
      var y:f32=0;
      for(&w.vowel,0..)|*f,k|y+=f.tick(src)*w.gains[k];
      s.*+=dsp.put(w.place,w.far.low(y)*w.swell.next()*wail);
      w.age+=1/w.rate;
    }
    return true;
  }
};
// ---- the heartbeat and the roll ----
/// how long a heartbeat lasts (s): slow, heavy
const beatS:f32=0.9;
/// how long after the first beat of a heartbeat its second falls (s)
const dubS:f32=0.26;
/// how much quieter its second beat is
const dub:f32=0.6;
/// how hard it beats as it starts, as it reaches the peak, and in it
const beatVel=m.Vice(f32,3){0.25,0.6,0.95};
/// how hard the great taiko booms under each beat in the peak
const peakBoom:f32=0.7;
/// its note (MIDI): D2
const beatNote:u8=38;
/// where the kettles stand (pan): the low one, the high one
const kettlePan=lib.sound.score.kettlePan;
/// the roll: strokes a second, how hard it starts and ends
const rollRate:f32=14;
/// (how hard)
const rollVel=m.Vice(f32,2){0.12,0.85};
/// the great taiko: its pitch (Hz) and how long it rings (s)
const boomHz=lib.sound.score.boomHz;
/// (how long it rings)
const boomRing:f32=1.6;
// ---- the score ----
/// a chord the choir sings: its four notes (MIDI, soprano first) and how loud
const Sing=struct{
  /// the notes
  notes:[lib.sound.choir.sections]u8,
  /// how loud (1 a night's full voice; the peak sings past it)
  loud:f32,
};
/// a chord the strings bow: its notes (MIDI, 0 for none) and how hard
const Bowed=struct{
  /// the notes
  notes:[6]u8,
  /// how hard (1 a night's bowing)
  vel:f32,
};
/// a note of the cello's line: where to (MIDI) and how long it bends there
/// (s; 0 moves straight there)
const Line=struct{
  /// the note
  note:f32,
  /// how long it bends there
  glide:f32=0,
};
/// a chord the horns hold: their notes (MIDI) and how loud
const Brass=struct{
  /// the notes
  notes:[hornCount]u8,
  /// how loud (0..1)
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
  /// the choir sings a chord
  sing:Sing,
  /// the choir falls silent
  hush,
  /// the strings let their chord go and bow another
  bow:Bowed,
  /// the strings let their chord go
  unbow,
  /// the cello plays a note
  line:Line,
  /// the cello lets its note go
  rest,
  /// the horns hold a chord
  brass:Brass,
  /// the horns let go
  unbrass,
  /// the timpani strike, the great taiko under them
  strike:Strike,
  /// everything stops dead: the seed falls
  drop,
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
/// the lament's chord, still Lydian: D, A and C# under the raised fourth
/// (G#4 on top)
const lament=Sing{.notes=.{68,61,57,38},.loud=0.18};
/// the landing's chord: Dmaj7 with the raised fourth back (C#5, G#4, F#3, D2)
const reborn=Sing{.notes=.{73,68,54,38},.loud=1.4};
/// the whole score, in time order
const cues=[_]Cue{
  // the lament: the garden's line alone over the choir's hum
  .{.at=lamentAt,.what=.{.sing=lament}},
  .{.at=lamentAt,.what=.{.bow=.{.notes=.{38,45,0,0,0,0},.vel=0.5}}},
  .{.at=lamentAt+0.2,.what=.{.line=.{.note=50}}},
  .{.at=lamentAt+1.3,.what=.{.line=.{.note=57}}},
  .{.at=lamentAt+2.2,.what=.{.line=.{.note=56}}},
  .{.at=lamentAt+3.4,.what=.{.line=.{.note=54}}},
  // the bend: back to the raised fourth, which sinks to G
  .{.at=bendAt,.what=.{.line=.{.note=56}}},
  .{.at=bendAt,.what=.{.sing=.{.notes=lament.notes,.loud=0.3}}},
  .{.at=bendAt+0.6,.what=.{.line=.{.note=55,.glide=0.7}}},
  .{.at=bendAt+1.3,.what=.{.sing=.{.notes=.{67,62,58,38},.loud=0.5}}},
  .{.at=bendAt+1.3,.what=.{.bow=.{.notes=.{26,38,50,55,58,0},.vel=1.2}}},
  .{.at=bendAt+2.2,.what=.{.line=.{.note=53}}},
  // the loss: D minor, the choir's line falling
  .{.at=lossAt,.what=.{.sing=.{.notes=.{65,62,57,38},.loud=0.65}}},
  .{.at=lossAt,.what=.{.bow=.{.notes=.{26,38,45,50,53,0},.vel=1.6}}},
  .{.at=lossAt+0.5,.what=.{.line=.{.note=50}}},
  .{.at=lossAt+1.1,.what=.{.sing=.{.notes=.{70,65,58,46},.loud=0.8}}},
  .{.at=lossAt+1.1,.what=.{.line=.{.note=53}}},
  .{.at=lossAt+1.8,.what=.{.sing=.{.notes=.{69,64,61,45},.loud=0.85}}},
  .{.at=lossAt+1.8,.what=.{.line=.{.note=52}}},
  // the peak: the whole orchestra
  .{.at=peakAt,.what=.{.strike=.{.note=38,.vel=1,.boom=1}}},
  .{.at=peakAt,.what=.{.sing=.{.notes=.{74,69,62,38},.loud=1.6}}},
  .{.at=peakAt,.what=.{.brass=.{.notes=.{38,50,57,62},.loud=1}}},
  .{.at=peakAt,.what=.{.bow=.{.notes=.{26,38,50,57,62,65},.vel=3}}},
  .{.at=peakAt,.what=.{.line=.{.note=38}}},
  .{.at=peakAt+1.2,.what=.{.strike=.{.note=46,.vel=0.9,.boom=0.8}}},
  .{.at=peakAt+1.2,.what=.{.sing=.{.notes=.{77,70,62,46},.loud=1.7}}},
  .{.at=peakAt+1.2,.what=.{.brass=.{.notes=.{34,46,53,58},.loud=1}}},
  .{.at=peakAt+1.2,.what=.{.bow=.{.notes=.{34,46,53,58,62,65},.vel=3}}},
  .{.at=peakAt+1.2,.what=.{.line=.{.note=46}}},
  .{.at=peakAt+2.3,.what=.{.strike=.{.note=45,.vel=1,.boom=1}}},
  .{.at=peakAt+2.3,.what=.{.sing=.{.notes=.{76,69,61,45},.loud=1.8}}},
  .{.at=peakAt+2.3,.what=.{.brass=.{.notes=.{33,45,52,57},.loud=1}}},
  .{.at=peakAt+2.3,.what=.{.bow=.{.notes=.{33,45,52,57,61,64},.vel=3.2}}},
  .{.at=peakAt+2.3,.what=.{.line=.{.note=45}}},
  // the drop: the seed falls in silence
  .{.at=dropAt,.what=.drop},
  // the landing: a great boom, then the raised fourth back, the magic
  // reborn rising slowly out of the bell (no brass: brass on a major chord
  // read as a fanfare)
  .{.at=landAt,.what=.land},
  .{.at=landAt,.what=.{.strike=.{.note=38,.vel=1,.boom=1}}},
  .{.at=landAt+0.3,.what=.{.bow=.{.notes=.{26,38,45,54,61,68},.vel=1.8}}},
  .{.at=landAt+0.7,.what=.{.sing=reborn}},
  .{.at=landAt+1.2,.what=.{.line=.{.note=50}}},
  .{.at=landAt+5,.what=.{.sing=.{.notes=reborn.notes,.loud=0.5}}},
  .{.at=landAt+8,.what=.unbow},
  .{.at=landAt+8,.what=.rest},
  .{.at=landAt+9,.what=.hush},
};
// ---- the whole theme ----
/// how many bowed notes, timpani strokes and taiko booms may sound at once
const bowCount=18;
/// (timpani strokes)
const timpCount=32;
/// (taiko booms)
const boomCount=6;
/// how fast the drop cuts it and the landing opens it again (s, ~63%)
const gateS:f32=0.05;
/// how much of the hall's tail is left through the drop, and how fast it
/// is taken (s, ~63%)
const dropTail:f32=0.1;
/// (how fast)
const tailS:f32=0.12;
/// how many choirs sing
const choirCount=2;
/// how loud the theme is
const level:f32=2.2;
/// samples rendered at a time
const chunk=256;
/// the unforming's theme played out, from its moment `clock`
pub const Theme=struct{
  /// samples a second
  rate:f32,
  /// its own random numbers
  r:rng.Rng,
  /// the event's clock as the theme hears it (s)
  clock:f32,
  /// the next cue to play
  cue:usize,
  /// when the heart next beats
  beatAt:f32,
  /// when the roll next strikes
  rollAt:f32,
  /// how many of the world's voices have come in
  wailed:usize,
  /// the choir, twice over (each its own voices, so the two thicken each
  /// other as a great choir does)
  choirs:[choirCount]Choir,
  /// the strings
  bows:dsp.Pool(Bow,bowCount)=.{},
  /// the timpani
  timps:dsp.Pool(Timpani,timpCount)=.{},
  /// the great taiko
  booms:dsp.Pool(Taiko,boomCount)=.{},
  /// the cello
  cello:Cello,
  /// the horns
  horns:[hornCount]Horn,
  /// the world's voices screaming
  wails:dsp.Pool(Wail,wailAt.len)=.{},
  /// how much of it is let through: shut by the drop, open again at the landing
  gate:dsp.Smooth,
  /// how much of the hall's tail is let through
  tail:dsp.Smooth,
  /// the theme heard from its moment `t`, drawn from `seed`
  pub fn init(t:f32,seed:u64,rate:f32)Theme{
    // its own random numbers, and whether `t` falls in the drop
    var r:rng.Rng=.init(seed);
    const dropped=t>=dropAt and t<landAt;
    // the theme, its voices made below
    var th:Theme=.{
      .rate=rate,
      .r=r,
      .clock=t,
      .cue=0,
      .beatAt=bendAt,
      .rollAt=lossAt,
      .wailed=0,
      .cello=.init(&r,rate),
      .choirs=undefined,
      .horns=undefined,
      .gate=.init(if(dropped)0 else 1,gateS,rate),
      .tail=.init(if(dropped)dropTail else 1,tailS,rate),
    };
    for(&th.choirs)|*ch|ch.*=.init(lament.notes,&r,rate);
    for(&th.horns,0..)|*h,k|h.*=.init(hornPan[k],&r,rate);
    th.r=r;
    // what came before `t` is past
    while(th.cue<cues.len and cues[th.cue].at<t)th.cue+=1;
    while(th.beatAt<t)th.beatAt+=beatS;
    while(th.rollAt<t)th.rollAt+=1/rollRate;
    while(th.wailed<wailAt.len and wailAt[th.wailed]<t)th.wailed+=1;
    return th;
  }
  /// the event's clock as told: only a slip is mended
  pub fn keep(th:*Theme,t:f32)void{
    if(@abs(t-th.clock)>0.25)th.clock=t;
  }
  /// how much the garden's music gives way to it (0 none .. 1 all): cut at
  /// once as it begins, given back slowly after the landing
  pub fn hush(th:*const Theme)f32{
    return m.smooth(m.clamp01(th.clock/cutIn))*(1-m.smooth(m.clamp01((th.clock-landAt-giveBackAfter)/giveBack)));
  }
  /// how much of the hall's tail is let through (the drop takes it)
  pub fn tailLeft(th:*const Theme)f32{return th.tail.value;}
  /// whether it has rung away and the garden's music is back
  pub fn done(th:*const Theme)bool{return th.clock>doneAt;}
  /// mixes the next samples into `dry` (heard on the stage) and `far` (the
  /// world's screaming, heard from far off: mostly through the hall), playing
  /// what the score holds as its moments come
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
  /// samples until the next thing the score does (at least one)
  fn until(th:*const Theme)usize{
    // the soonest of the next cue, beat, roll stroke and voice
    var next=@min(th.beatAt,th.rollAt);
    if(th.cue<cues.len)next=@min(next,cues[th.cue].at);
    if(th.wailed<wailAt.len)next=@min(next,wailAt[th.wailed]);
    if(next>=never)return chunk;
    return@max(1,m.floorTo(usize,@max(next-th.clock,0)*th.rate)+1);
  }
  /// everything the score does by now
  fn fire(th:*Theme)void{
    while(th.cue<cues.len and cues[th.cue].at<=th.clock):(th.cue+=1)th.cueOf(cues[th.cue].what);
    while(th.beatAt<=th.clock){
      if(th.beatAt>=dropAt){
        th.beatAt=never;
        break;
      }
      th.beat();
      th.beatAt+=beatS;
    }
    while(th.rollAt<=th.clock){
      if(th.rollAt>=peakAt){
        th.rollAt=never;
        break;
      }
      // how far through the roll, its strokes growing ever harder
      const k=m.clamp01((th.rollAt-lossAt)/(peakAt-lossAt));
      th.timps.cycle(.init(beatNote,m.lerp(rollVel[0],rollVel[1],k*k),0,kettlePan[th.r.below(2)],&th.r,th.rate));
      th.rollAt+=1/rollRate;
    }
    while(th.wailed<wailAt.len and wailAt[th.wailed]<=th.clock):(th.wailed+=1){
      th.wails.add(.init(wailNote[th.wailed],&th.r,th.rate));
    }
  }
  /// one heartbeat: two strokes, the second softer, harder the nearer the
  /// peak, the great taiko under it in the peak
  fn beat(th:*Theme)void{
    // how hard it beats now
    const vel=if(th.clock>=peakAt)beatVel[2]else m.lerp(beatVel[0],beatVel[1],m.clamp01((th.clock-bendAt)/(peakAt-bendAt)));
    th.timps.cycle(.init(beatNote,vel,0,kettlePan[0],&th.r,th.rate));
    th.timps.cycle(.init(beatNote,vel*dub,m.floorTo(u32,dubS*th.rate),kettlePan[0],&th.r,th.rate));
    if(th.clock>=peakAt)th.booms.cycle(.init(boomHz,boomRing,peakBoom,0,&th.r,th.rate));
  }
  /// does what one cue says
  fn cueOf(th:*Theme,w:What)void{
    switch(w){
      .sing=>|s|for(&th.choirs)|*ch|ch.sing(s.notes,s.loud,&th.r),
      .hush=>for(&th.choirs)|*ch|ch.hush(),
      .bow=>|b|{
        th.unbow();
        for(b.notes)|note|if(note!=0)th.bows.add(.init(note,b.vel,&th.r,th.rate));
      },
      .unbow=>th.unbow(),
      .line=>|l|th.cello.play(l.note,l.glide),
      .rest=>th.cello.rest(),
      .brass=>|b|for(&th.horns,b.notes)|*h,note|h.play(note,b.loud),
      .unbrass=>for(&th.horns)|*h|{h.swell.target=0;},
      .strike=>|s|{
        th.timps.cycle(.init(s.note,s.vel,0,kettlePan[0],&th.r,th.rate));
        if(s.boom>0)th.booms.cycle(.init(boomHz,boomRing,s.boom,0,&th.r,th.rate));
      },
      .drop=>{
        th.gate.target=0;
        th.tail.target=dropTail;
      },
      .land=>{
        // every voice silenced and made afresh, so the landing blooms from nothing
        for(&th.choirs)|*ch|ch.*=.init(reborn.notes,&th.r,th.rate);
        th.bows.clear();
        th.timps.clear();
        th.booms.clear();
        th.wails.clear();
        th.cello=.init(&th.r,th.rate);
        for(&th.horns,0..)|*h,k|h.*=.init(hornPan[k],&th.r,th.rate);
        th.gate.target=1;
        th.tail.target=1;
      },
    }
  }
  /// the strings let their chord go
  fn unbow(th:*Theme)void{
    for(&th.bows.slots)|*v|if(v.*)|*b|b.release();
  }
  /// plays `dry.len` samples (at most a chunk) of everything sounding
  fn play(th:*Theme,dry:[]dsp.Frame,far:[]dsp.Frame)void{
    // the stage and the far-off voices, before the gate
    var stage:[chunk]dsp.Frame=@splat(@splat(0));
    var cry:[chunk]dsp.Frame=@splat(@splat(0));
    const s=stage[0..dry.len];
    const c=cry[0..dry.len];
    for(&th.choirs)|*ch|ch.render(s);
    th.bows.render(s);
    th.timps.render(s);
    th.booms.render(s);
    th.wails.render(c);
    for(dry,far,s,c)|*d,*f,x,y|{
      // the cello and the horns, then the gate over all of it
      var z=x+th.cello.tick();
      for(&th.horns)|*h|z+=h.tick();
      const g=th.gate.next();
      _=th.tail.next();
      d.*+=z*dsp.mid(g*level);
      f.*+=y*dsp.mid(g*level);
    }
  }
};
/// the sample rate the tests render at (samples a second)
const testRate:f32=48000;
/// the test harness
const testing=lib.std.testing;
test"the score runs in time order, its drop and landing where the seed falls and lands"{
  // the last cue's moment
  var last:f32=0;
  for(cues)|c|{
    try testing.expect(c.at>=last);
    last=c.at;
    // nothing plays in the drop but the drop itself
    switch(c.what){
      .drop=>try testing.expectEqual(dropAt,c.at),
      .land=>try testing.expectEqual(landAt,c.at),
      else=>try testing.expect(c.at<dropAt or c.at>=landAt),
    }
  }
  try testing.expect(peakAt+2.3<dropAt);
}
test"the theme is silent at first, builds to its peak, drops out for the fall, blooms at the landing and rings away"{
  // the theme from its first moment, the loudness (rms) and peak of each
  // half second, of the stage and the far voices
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
      peak=@max(peak,@abs(x[0]),@abs(x[1]));
    }
  }
  for(&rms,&cry)|*a,*c|{
    a.*=@sqrt(a.*/(testRate/2));
    c.*=@sqrt(c.*/(testRate/2));
  }
  // it rings away and never clips
  try testing.expect(th.done());
  try testing.expect(peak<1);
  // silent as it begins, the lament heard, the peak far louder
  try testing.expect(rms[0]<1e-4);
  const lamentRms=rms[6];
  const peakRms=rms[@intFromFloat(peakAt*2+3)];
  try testing.expect(lamentRms>1e-3);
  try testing.expect(peakRms>lamentRms*2.5);
  // the world screams in the peak, not before the bend
  try testing.expect(cry[@intFromFloat(peakAt*2+3)]>1e-3);
  try testing.expect(cry[@intFromFloat(bendAt*2-2)]<1e-6);
  // the drop is all but silent
  const dropped:usize=@intFromFloat(@ceil(dropAt*2)+1);
  try testing.expect(rms[dropped]<peakRms*0.02);
  try testing.expect(cry[dropped]<1e-5);
  // the landing blooms again
  try testing.expect(rms[@intFromFloat(landAt*2+3)]>lamentRms);
}
