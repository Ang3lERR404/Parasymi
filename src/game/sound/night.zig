//! the night's music: strings swelling through slow open chords, glass chimes glistening high over them, a far choir singing "oo".
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub, for sorting a glint
const std=lib.std;
/// the generic engine package
const engine=lib.engine;
/// all the maths: clamps, rounding
const m=engine.core.math;
/// the engine's sound pieces: smoothing
const dsp=engine.core.dsp;
/// the seeded random numbers the night draws from
const rng=engine.core.rng;
/// one chime struck
const Chime=lib.sound.nightVoices.Chime;
/// one note bowed on the strings
const Bow=lib.sound.nightVoices.Bow;
/// one note sung by the choir
const Sung=lib.sound.nightVoices.Sung;
/// the dark echo the day's music has too
const Echo=lib.sound.voices.Echo;
/// quieter than this, the music has faded out
const silent=lib.sound.silent;
/// a value nudged a little either way, so no two notes are alike
const vary=lib.sound.footstep.vary;
// ---- the night on paper ----
/// how long one step lasts (s): slow eighths, the night's pulse never heard
/// as a beat, only felt in when things fall
const stepS:f32=0.6;
/// steps to a bar
const barSlots=8;
/// bars to a phrase
const bars=4;
/// steps to a phrase
const phraseSteps=barSlots*bars;
/// a chord as the strings voice it: its notes (MIDI), lowest first, 0 for
/// none
const Chord=[5]u8;
// decision: the night keeps the day's D Lydian, voiced open and low under
// the chimes, so dusk and dawn cross-fade without a change of key
/// Dmaj9: D3 A3 C#4 E4 F#4
const one:Chord=.{50,57,61,64,66};
/// E over D, the Lydian II over its root: D3 G#3 B3 E4
const two:Chord=.{50,56,59,64,0};
/// Bm9: B2 F#3 A3 C#4 D4
const six:Chord=.{47,54,57,61,62};
/// F#m7 over A: A2 E3 F#3 C#4
const three:Chord=.{45,52,54,61,0};
/// A with its ninth: A2 E3 B3 C#4
const five:Chord=.{45,52,59,61,0};
/// the phrases the night drifts through, a chord a bar
const progressions=[_][bars]Chord{
  .{one,two,one,two},
  .{six,two,one,one},
  .{three,two,six,one},
  .{one,six,two,five},
};
/// the chance of a new progression each phrase
const newChords:f32=0.45;
/// how loud the strings bow
const bowVel:f32=1;
/// the chimes: a chord tone two octaves over its voicing (three, this
/// often), this often on a step (more on a bar's first), how loud
/// (this one: two octaves up, in semitones)
const chimeUp:u8=24;
/// how often a chime goes an octave higher still
const chimeHigher:f32=0.5;
/// how often a chime falls on a bar's first step
const chimeFirst:f32=0.55;
/// how often on any other step
const chimeStep:f32=0.14;
/// how loud a chime is struck (before it strays)
const chimeVel:f32=0.8;
/// now and then, at a bar's middle, a glint: chord tones run quickly
/// down (or up), each softer
/// (this one: how often a bar has one)
const glintChance:f32=0.3;
/// how many notes a glint runs
const glintNotes=5;
/// how far apart they fall (s)
const glintGap:f32=0.11;
/// how much softer each is than the last
const glintFade:f32=0.78;
/// the choir sings a chord tone in this range (MIDI A4..E5), holding it
/// two bars; this often it rests instead
/// (this one: the lowest it sings)
const singLo:u8=69;
/// the highest it sings
const singHi:u8=76;
/// how often it rests for two bars
const singRest:f32=0.3;
/// how loud it sings
const singVel:f32=1;
/// how many bowed notes may sound at once (a chord dying under the next)
const bowCount=12;
/// how many chimes may ring at once
const chimeCount=14;
/// how many sung notes may sound at once
const sungCount=3;
/// the echo's level
const echo:f32=0.45;
/// how fast the music follows the dark (s); it plays only while the
/// daylight is under this
/// (this one: the glide, s)
const glide:f32=4;
/// the daylight under which the night plays (0..1)
const nightUnder:f32=0.95;
/// the night's loudness
const loudness:f32=1;
/// samples rendered at a time between steps
const chunkFrames=256;
/// the night's music: open chords swelling on the strings, chimes high
/// over them and now and then a glint of them run quickly, a far choir
/// holding a note through two bars; rising with the dusk, gone by morning
pub const Night=struct{
  /// samples per second
  rate:f32,
  /// its own random numbers
  r:rng.Rng,
  /// the bowed notes sounding; null is free
  bows:[bowCount]?Bow=@splat(null),
  /// the chimes ringing; null is free
  chimes:[chimeCount]?Chime=@splat(null),
  /// the sung notes sounding; null is free
  sung:[sungCount]?Sung=@splat(null),
  /// the chime taken when none is free (round the pool: the oldest)
  nextChime:usize=0,
  /// the echo everything feeds
  echo:Echo,
  /// the music's level, gliding after the dark
  fade:dsp.Smooth,
  /// the step about to play
  step:u32=0,
  /// samples until it does
  left:u32=0,
  /// samples a step lasts
  stepLen:u32,
  /// the phrase's chords
  chords:[bars]Chord=progressions[0],
  /// the last note the choir sang (MIDI), to move from it by a near step
  lastSung:u8=73,
  /// silent through the day: nothing sounds, the next night starts a phrase
  resting:bool=true,
  /// chimes struck (tests count them)
  struck:u32=0,
  /// chords bowed (tests count them)
  bowed:u32=0,
  /// notes sung (tests count them)
  sang:u32=0,
  /// its loudness (tests hush it)
  level:f32=loudness,
  /// a silent night, waiting for the dark, drawing its own random numbers from `r`
  pub fn init(r:*rng.Rng,rate:f32)Night{
    return.{
      .rate=rate,
      .r=.init(r.next()),
      .echo=.init(rate),
      .fade=.init(0,glide,rate),
      .stepLen=m.floorTo(u32,stepS*rate),
    };
  }
  /// the daylight `d` (0 night .. 1 day) heard: under `nightUnder` the
  /// night glides toward its level, deeper the darker; above it fades out
  pub fn daylight(n:*Night,d:f32)void{n.fade.target=if(d<nightUnder)m.clamp01(1-d)else 0;}
  /// mixes the next `out.len` samples into `out`, a chunk at a time; once
  /// faded out by day it rests, silent
  pub fn render(n:*Night,out:[]f32)void{
    if(n.fade.target==0 and n.fade.value<silent){
      if(!n.resting)n.rest();
      return;
    }
    n.resting=false;
    // how far into `out` the chunks have reached
    var off:usize=0;
    while(off<out.len){
      // this chunk's length, and its own zeroed buffer
      const k=@min(chunkFrames,out.len-off);
      var buf:[chunkFrames]f32=@splat(0);
      n.chunk(buf[0..k]);
      for(out[off..][0..k],buf[0..k])|*o,x|o.*+=x;
      off+=k;
    }
  }
  /// the day's rest: every voice and the echo cleared, the next night
  /// starting a phrase from its first step
  pub fn rest(n:*Night)void{
    n.bows=@splat(null);
    n.chimes=@splat(null);
    n.sung=@splat(null);
    n.echo=.init(n.rate);
    n.step=0;
    n.left=0;
    n.resting=true;
  }
  /// plays `buf` (zeroed) out, striking each step as it comes
  pub fn chunk(n:*Night,buf:[]f32)void{
    // how far into `buf` the steps have played
    var i:usize=0;
    while(i<buf.len){
      if(n.left==0){
        n.strikeStep();
        n.left=n.stepLen;
      }
      // samples until the next step, and the stretch of `buf` played through them
      const k:u32=@intCast(@min(n.left,buf.len-i));
      const part=buf[i..][0..k];
      for(&n.bows)|*v|if(v.*)|*b|{
        if(!b.render(part))v.*=null;
      };
      for(&n.chimes)|*v|if(v.*)|*c|{
        if(!c.render(part))v.*=null;
      };
      for(&n.sung)|*v|if(v.*)|*s|{
        if(!s.render(part))v.*=null;
      };
      n.left-=k;
      i+=k;
    }
    for(buf)|*s|s.*=(s.*+echo*n.echo.tick(s.*))*n.level*n.fade.next();
  }
  /// the step about to play: a bar's first bows its chord (letting the
  /// last die away under it) and, every other bar, the choir moves; any
  /// step may chime; a bar's middle may glint
  pub fn strikeStep(n:*Night)void{
    if(n.step==0 and n.r.float()<newChords)n.chords=progressions[n.r.below(progressions.len)];
    // which bar this is, the step within it, and the bar's chord
    const bar=n.step/barSlots;
    const s=n.step%barSlots;
    const c=n.chords[bar];
    if(s==0){
      n.bowChord(c);
      if(bar%2==0)n.singOn(c);
    }
    if(n.r.float()<(if(s==0)chimeFirst else chimeStep))n.chime(c,vary(&n.r,chimeVel),0);
    if(s==barSlots/2 and n.r.float()<glintChance)n.glint(c);
    n.step=(n.step+1)%phraseSteps;
  }
  /// the strings let their chord go and bow `c`
  pub fn bowChord(n:*Night,c:Chord)void{
    for(&n.bows)|*v|if(v.*)|*b|b.release();
    for(c)|note|if(note!=0){
      // a free bow, else the quietest dying one
      const at=n.freeBow();
      n.bows[at]=.init(note,vary(&n.r,bowVel),&n.r,n.rate);
    };
    n.bowed+=1;
  }
  /// a bow to play on: the first free one, else the quietest let go
  fn freeBow(n:*Night)usize{
    for(n.bows,0..)|v,i|if(v==null)return i;
    // the quietest found so far, and how loud it is
    var best:usize=0;
    var low:f32=2;
    for(n.bows,0..)|v,i|if(v)|b|if(!b.swell.held and b.swell.level<low){
      best=i;
      low=b.swell.level;
    };
    return best;
  }
  /// the choir lets its note go and, unless it rests, sings the chord tone
  /// of `c` nearest the last it sang (within its range)
  pub fn singOn(n:*Night,c:Chord)void{
    for(&n.sung)|*v|if(v.*)|*s|s.release();
    if(n.r.float()<singRest)return;
    // the nearest chord tone to the last note, and how far it is
    var best:u8=n.lastSung;
    var dist:u8=255;
    for(singLo..singHi+1)|t|{
      // this note, and whether it is in the chord (any octave)
      const note:u8=@intCast(t);
      const in=for(c)|x|{
        if(x!=0 and x%12==note%12)break true;
      }else false;
      // how far it is from the last, a step of its own preferred to standing still
      const d:u8=if(note>n.lastSung)note-n.lastSung else n.lastSung-note;
      const cost=if(d==0)@as(u8,3)else d;
      if(in and cost<dist){
        best=note;
        dist=cost;
      }
    }
    n.lastSung=best;
    for(&n.sung)|*v|if(v.*==null){
      v.*=.init(best,vary(&n.r,singVel),&n.r,n.rate);
      n.sang+=1;
      return;
    };
  }
  /// a chime on a tone of `c` (two octaves over its voicing, or three),
  /// struck after `wait` samples
  pub fn chime(n:*Night,c:Chord,vel:f32,wait:u32)void{
    n.chimeNote(n.high(c),vel,wait);
  }
  /// one of `c`'s tones as a chime rings it: two octaves up, or three
  fn high(n:*Night,c:Chord)u8{
    return n.tone(c)+chimeUp+(if(n.r.float()<chimeHigher)@as(u8,12)else 0);
  }
  /// one of `c`'s tones, drawn at random
  fn tone(n:*Night,c:Chord)u8{
    // how many tones the chord has
    var count:u32=0;
    for(c)|x|if(x!=0){count+=1;};
    return c[n.r.below(count)];
  }
  /// the chord's tones run quickly from high to low (or low to high), each
  /// softer than the last
  pub fn glint(n:*Night,c:Chord)void{
    // the run's notes, picked below, and whether it falls
    var notes:[glintNotes]u8=undefined;
    for(&notes)|*x|x.*=n.high(c);
    std.mem.sort(u8,&notes,{},std.sort.desc(u8));
    const falls=n.r.float()<0.7;
    // how loud the next note is
    var vel=vary(&n.r,chimeVel);
    for(0..glintNotes)|k|{
      // this note, from the top or the bottom
      const note=if(falls)notes[k]else notes[glintNotes-1-k];
      n.chimeNote(note,vel,m.floorTo(u32,m.f(k)*glintGap*n.rate));
      vel*=glintFade;
    }
  }
  /// strikes MIDI `note` at `vel` after `wait` samples on the next chime
  /// round the pool
  fn chimeNote(n:*Night,note:u8,vel:f32,wait:u32)void{
    n.chimes[n.nextChime]=.init(note,vel,wait,&n.r,n.rate);
    n.nextChime=(n.nextChime+1)%chimeCount;
    n.struck+=1;
  }
};
