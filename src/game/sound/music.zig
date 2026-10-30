//! the day's music playing: Lydian phrases of a full piano over open chords, driven by taiko, timpani rolls and cymbal swells, fading with the light.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: clamps, rounding
const m=engine.core.math;
/// the engine's sound pieces: smoothing
const dsp=engine.core.dsp;
/// the seeded random numbers the music draws from
const rng=engine.core.rng;
/// steps to a bar
const barSlots=lib.sound.score.barSlots;
/// bars to a phrase
const bars=lib.sound.score.bars;
/// how often a phrase's last two steps rest
const breathe=lib.sound.score.breathe;
/// a chord: its root and whether it is minor
const Chord=lib.sound.score.Chord;
/// how often the left hand's fifth sounds on the third beat
const fifthChance=lib.sound.score.fifthChance;
/// how often the left hand's ninth rings there instead
const ninthChance=lib.sound.score.ninthChance;
/// the left hand's low root (MIDI)
const lowLevel=lib.sound.score.lowLevel;
/// roots above this many semitones drop an octave
const lowFold=lib.sound.score.lowFold;
/// how loud the left hand plays
const lowVel=lib.sound.score.lowVel;
/// the melody's highest scale step
const melHi=lib.sound.score.melHi;
/// the melody's lowest scale step
const melLo=lib.sound.score.melLo;
/// steps in a motif
const motif=lib.sound.score.motif;
/// the music's loudness
const music=lib.sound.score.music;
/// the daylight the music plays above (0..1)
const musicFrom=lib.sound.score.musicFrom;
/// how fast the music follows the daylight (s)
const musicGlide=lib.sound.score.musicGlide;
/// each step's chance to change in a variation
const mutate=lib.sound.score.mutate;
/// the chance of a new progression each phrase
const newChords=lib.sound.score.newChords;
/// the chance of a new motif instead of a variation
const newMotifChance=lib.sound.score.newMotifChance;
/// how likely a note is on a bar's first step, a beat, off the beat
const noteChance=lib.sound.score.noteChance;
/// how loud a note is there
const noteVel=lib.sound.score.noteVel;
/// steps to a phrase
const phraseSteps=lib.sound.score.phraseSteps;
/// how many plunks may ring at once
const plunks=lib.sound.score.plunks;
/// the chord progressions a phrase plays over
const progressions=lib.sound.score.progressions;
/// one struck piano note
const Plunk=lib.sound.voices.Plunk;
/// a taiko struck
const Taiko=lib.sound.drums.Taiko;
/// a timpani stroke
const Timpani=lib.sound.drums.Timpani;
/// a cymbal, swelling or crashing
const Cymbal=lib.sound.drums.Cymbal;
/// the day's score: the drums' pattern and voices
const score=lib.sound.score;
/// quieter than this, the music has faded out
const silent=lib.sound.silent;
/// how long one step lasts (s)
const stepS=lib.sound.score.stepS;
/// the note nearest a given one that is in a chord
const chordTone=lib.sound.score.chordTone;
/// a MIDI note of the scale, steps above the key
const scaleNote=lib.sound.score.scaleNote;
/// a value nudged a little either way, so no two notes are alike
const vary=lib.sound.footstep.vary;
/// samples the music renders at a time between its steps
const chunkFrames=256;
/// the day's music: a full piano over open chords, driven by great taiko
/// on a steady pulse, timpani rolled up into each phrase and a cymbal
/// swelling to crash on its first step; fading in with the morning and
/// out at dusk
pub const Music=struct{
  /// samples per second
  rate:f32,
  /// its own random numbers
  r:rng.Rng,
  /// the plunks ringing; null is free
  plunks:[plunks]?Plunk=@splat(null),
  /// the taiko sounding; null is free
  taikos:[score.taikos]?Taiko=@splat(null),
  /// the timpani strokes sounding; null is free
  timps:[score.timps]?Timpani=@splat(null),
  /// the cymbals sounding; null is free
  cymbals:[score.cymbals]?Cymbal=@splat(null),
  /// the plunk taken when none is free (round the pool: the oldest)
  nextPlunk:usize=0,
  /// the taiko slot the next hit takes
  nextTaiko:usize=0,
  /// the timpani slot the next stroke takes
  nextTimp:usize=0,
  /// the cymbal slot the next takes
  nextCymbal:usize=0,
  /// this phrase is calm: the deep taiko and one stroke a bar only
  calm:bool=false,
  /// the music's level, gliding after the daylight
  fade:dsp.Smooth,
  /// the step about to play, and samples until it does
  step:u32=0,
  /// samples until that step plays
  left:u32=0,
  /// samples a step lasts
  stepLen:u32,
  /// the phrase's four chords
  chords:[bars]Chord=progressions[0],
  /// scale steps (null rests) of the motif and of its variation
  motif:[motif]?u8=@splat(null),
  /// the variation's scale steps (null rests)
  varied:[motif]?u8=@splat(null),
  /// whether the next phrase is the first, which always takes a new motif
  fresh:bool=true,
  /// silent through the night: nothing rings, the next day starts a phrase
  resting:bool=true,
  /// notes and drums struck (tests count them)
  struck:u32=0,
  /// taiko struck so far
  drummed:u32=0,
  /// timpani strokes so far
  rolled:u32=0,
  /// cymbals crashed so far
  crashed:u32=0,
  /// the music's loudness (tests hush it)
  level:f32=music,
  /// fresh music, silent until day, drawing its own random numbers from `r`
  pub fn init(r:*rng.Rng,rate:f32)Music{
    return.{
      .rate=rate,
      .r=.init(r.next()),
      .fade=.init(0,musicGlide,rate),
      .stepLen=m.floorTo(u32,stepS*rate),
    };
  }
  /// the daylight `d` (0 night .. 1 day) heard: past `musicFrom` the music
  /// glides toward its level, below it fades out
  pub fn daylight(mu:*Music,d:f32)void{mu.fade.target=if(d>musicFrom)m.clamp01(d)else 0;}
  /// mixes the next `out.len` samples into `out`, a chunk at a time; once
  /// faded out by night it rests, silent
  pub fn render(mu:*Music,out:[]f32)void{
    if(mu.fade.target==0 and mu.fade.value<silent){
      if(!mu.resting)mu.rest();
      return;
    }
    mu.resting=false;
    // how far into `out` the chunks have reached
    var off:usize=0;
    while(off<out.len){
      // this chunk's length, and its own zeroed buffer
      const n=@min(chunkFrames,out.len-off);
      var buf:[chunkFrames]f32=@splat(0);
      mu.chunk(buf[0..n]);
      for(out[off..][0..n],buf[0..n])|*o,x|o.*+=x;
      off+=n;
    }
  }
  /// the night's rest: every voice cleared, the next day starting a
  /// phrase from its first step
  pub fn rest(mu:*Music)void{
    mu.plunks=@splat(null);
    mu.taikos=@splat(null);
    mu.timps=@splat(null);
    mu.cymbals=@splat(null);
    mu.step=0;
    mu.left=0;
    mu.resting=true;
  }
  /// plays `buf` (zeroed) out, striking each step as it comes
  pub fn chunk(mu:*Music,buf:[]f32)void{
    // how far into `buf` the steps have played
    var i:usize=0;
    while(i<buf.len){
      if(mu.left==0){
        mu.strikeStep();
        mu.left=mu.stepLen;
      }
      // samples until the next step, and the stretch of `buf` played through them
      const n:u32=@intCast(@min(mu.left,buf.len-i));
      const part=buf[i..][0..n];
      for(&mu.plunks)|*v|if(v.*)|*p|{
        if(!p.render(part))v.*=null;
      };
      for(&mu.taikos)|*v|if(v.*)|*d|{
        if(!d.render(part))v.*=null;
      };
      for(&mu.timps)|*v|if(v.*)|*d|{
        if(!d.render(part))v.*=null;
      };
      for(&mu.cymbals)|*v|if(v.*)|*d|{
        if(!d.render(part))v.*=null;
      };
      mu.left-=n;
      i+=n;
    }
    for(buf)|*s|s.*=mu.level*mu.fade.next()*s.*;
  }
  /// strikes the step about to play: the melody's note (on a bar's first
  /// step, the nearest chord tone), the left hand's root, its octave and
  /// fifth, and the drums; a phrase's first step writes a new phrase
  pub fn strikeStep(mu:*Music)void{
    if(mu.step==0)mu.phrase();
    // which bar this is, the step within it, and the bar's chord
    const bar=mu.step/barSlots;
    const s=mu.step%barSlots;
    const c=mu.chords[bar];
    // where the step falls: a bar's first, on a beat, or off it
    const at:usize=if(s==0)0 else if(s%2==0)1 else 2;
    // the motif's first time through, then its variation
    const line=if(mu.step<motif)mu.motif else mu.varied;
    if(line[mu.step%motif])|i|{
      // the note of that scale step
      const n=scaleNote(i);
      mu.plunk(if(s==0)chordTone(n,c)else n,vary(&mu.r,noteVel[at]));
    }
    // the left hand's root, dropped an octave if high
    const low=lowLevel+c.root-(if(c.root>lowFold)@as(u8,12)else 0);
    if(s==0){
      mu.plunk(low,vary(&mu.r,lowVel));
      mu.plunk(low+12,vary(&mu.r,lowVel*0.6));
    }
    if(s==barSlots/2){
      // the left hand's second note: the ninth, left open, or the fifth
      const second=mu.r.float();
      if(second<ninthChance)mu.plunk(low+14,vary(&mu.r,lowVel*0.7))
      else if(second<ninthChance+fifthChance*(1-ninthChance))mu.plunk(low+7,vary(&mu.r,lowVel*0.8));
    }
    mu.drumStep(s);
    mu.step=(mu.step+1)%phraseSteps;
  }
  /// a new phrase: maybe new chords, a new motif or a variation of the last
  pub fn phrase(mu:*Music)void{
    mu.calm=mu.r.float()<score.calmChance;
    if(mu.r.float()<newChords)mu.chords=progressions[mu.r.below(progressions.len)];
    if(mu.fresh or mu.r.float()<newMotifChance){
      mu.motif=mu.newMotif();
      mu.fresh=false;
    }else mu.motif=mu.alter(mu.varied);
    mu.varied=mu.alter(mu.motif);
    if(mu.r.float()<breathe){
      mu.varied[motif-2]=null;
      mu.varied[motif-1]=null;
    }
  }
  /// a wandering line: small steps up and down the scale, mostly on beats
  pub fn newMotif(mu:*Music)[motif]?u8{
    // the line, filled in below
    var out:[motif]?u8=undefined;
    // the scale step it is on, starting low in the range
    var i:u8=@intCast(melLo+2+mu.r.below(melHi-melLo-3));
    for(&out,0..)|*o,k|{
      // the step within the bar, and where it falls: first, a beat, or off it
      const s=k%barSlots;
      const at:usize=if(s==0)0 else if(s%2==0)1 else 2;
      if(mu.r.float()>=noteChance[at]){
        o.*=null;
        continue;
      }
      i=mu.wander(i,2);
      o.*=i;
    }
    return out;
  }
  /// `line` with some of its steps changed: a note moved a step, dropped,
  /// or a rest filled
  pub fn alter(mu:*Music,line:[motif]?u8)[motif]?u8{
    // the line, altered in place
    var out=line;
    // the last note heard, starting mid-range, for filling a rest near it
    var last:u8=melLo+(melHi-melLo)/2;
    for(&out)|*o|{
      if(mu.r.float()<mutate)o.*=if(o.*)|i|(if(mu.r.float()<0.3)null else mu.wander(i,1))else mu.wander(last,1);
      if(o.*)|i|last=i;
    }
    return out;
  }
  /// `i` moved up to `by` steps either way, kept in the melody's range
  pub fn wander(mu:*Music,i:u8,by:u8)u8{
    // how far it moves: -`by` .. `by`
    const d:i32=@as(i32,@intCast(mu.r.below(2*by+1)))-by;
    return@intCast(m.clamp(@as(i32,i)+d,melLo,melHi));
  }
  /// strikes `note` (MIDI) at velocity `vel` on a free plunk
  pub fn plunk(mu:*Music,note:u8,vel:f32)void{
    mu.plunks[mu.freePlunk()]=.init(note,vel,&mu.r,mu.rate);
    mu.struck+=1;
  }
  /// the drums on step `s` of its bar: the deep taiko on a bar's first,
  /// the taiko on their beats, the small ones now and then (only the deep
  /// one and the seventh step's stroke in a calm phrase); at a phrase's
  /// end the cymbal swells (crashing on the next one's first step) and the
  /// timpani roll up into it, landing on the low kettle
  pub fn drumStep(mu:*Music,s:u32)void{
    if(s==0)mu.taiko(score.boomHz,score.boomRing,1);
    // how hard the taiko and the small taiko strike here (0: not at all)
    const big=score.taikoBeat[s];
    const small=score.smallBeat[s];
    if(big>0 and (!mu.calm or s==6))mu.taiko(score.taikoHz,score.taikoRing,vary(&mu.r,big));
    if(small>0 and !mu.calm and mu.r.float()<score.smallChance)mu.taiko(score.smallHz,score.smallRing,vary(&mu.r,small));
    if(mu.step==0 and mu.rolled>0)mu.timp(score.kettles[0],1,0);
    if(mu.step==phraseSteps-score.swellSteps)mu.crash(m.floorTo(u32,m.f(score.swellSteps)*m.f(mu.stepLen)));
    if(mu.step>=score.rollFrom){
      // how far through the roll this step is, 0..1, and its kettle
      const into=m.f(mu.step-score.rollFrom)/m.f(phraseSteps-score.rollFrom);
      const kettle=score.kettles[if(mu.step%2==0)0 else 1];
      for(0..score.rollPerStep)|k|{
        // this stroke's place in the roll, and how loud it is
        const at=into+m.f(k)/m.f(score.rollPerStep*(phraseSteps-score.rollFrom));
        mu.timp(kettle,m.lerp(score.rollVel[0],score.rollVel[1],at*at),@intCast(k*mu.stepLen/score.rollPerStep));
      }
    }
  }
  /// strikes a taiko pitched at `hz`, ringing `ring` seconds, at velocity `vel`
  pub fn taiko(mu:*Music,hz:f32,ring:f32,vel:f32)void{
    mu.taikos[mu.nextTaiko]=.init(hz,ring,vel,&mu.r,mu.rate);
    mu.nextTaiko=(mu.nextTaiko+1)%score.taikos;
    mu.drummed+=1;
  }
  /// strikes a timpani kettle (MIDI `note`) at velocity `vel` after `wait` samples
  pub fn timp(mu:*Music,note:u8,vel:f32,wait:u32)void{
    mu.timps[mu.nextTimp]=.init(note,vel,wait,&mu.r,mu.rate);
    mu.nextTimp=(mu.nextTimp+1)%score.timps;
    mu.rolled+=1;
  }
  /// a cymbal swelling for `swell` samples to its crash (0: a crash now)
  pub fn crash(mu:*Music,swell:u32)void{
    mu.cymbals[mu.nextCymbal]=.init(score.crashVel,swell,&mu.r,mu.rate);
    mu.nextCymbal=(mu.nextCymbal+1)%score.cymbals;
    mu.crashed+=1;
  }
  /// a plunk to play on: the first free one, or else the next in turn
  /// round the pool (the oldest)
  pub fn freePlunk(mu:*Music)usize{
    for(mu.plunks,0..)|v,i|if(v==null)return i;
    defer mu.nextPlunk=(mu.nextPlunk+1)%plunks;
    return mu.nextPlunk;
  }
};
