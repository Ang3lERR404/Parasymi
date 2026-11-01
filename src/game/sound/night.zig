//! the night's music: a choir of four sections singing "ahh" through slow open chords, strings swelling under it.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: clamps, rounding
const m=engine.core.math;
/// the engine's sound pieces: smoothing
const dsp=engine.core.dsp;
/// the seeded random numbers the night draws from
const rng=engine.core.rng;
/// one note bowed on the strings
const Bow=lib.sound.nightVoices.Bow;
/// the choir: four sections of eight voices
const Choir=lib.sound.choir.Choir;
/// how many sections the choir has
const sections=lib.sound.choir.sections;
/// quieter than this, the music has faded out
const silent=lib.sound.silent;
/// a value nudged a little either way, so no two notes are alike
const vary=lib.sound.footstep.vary;
// ---- the night on paper ----
/// how long a bar lasts (s): a chord a bar, slow as breathing
const barS:f32=5.2;
/// bars to a phrase
const bars=4;
/// a chord as the strings voice it: its notes (MIDI), lowest (its root)
/// first, 0 for none
const Chord=[5]u8;
// decision: the night keeps the day's D Lydian, voiced open and low, so
// dusk and dawn cross-fade without a change of key
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
/// where each section of the choir may sing (MIDI, lowest and highest):
/// soprano E4..G5, alto A3..B4, tenor D3..E4, bass D2..G3
const ranges=[sections]m.Vice(u8,2){.{64,79},.{57,71},.{50,64},.{38,55}};
/// where each section starts, before its first chord
const starts=[sections]u8{73,66,57,50};
/// how loud the choir sings through a phrase's bars: swelling to its third
/// and falling back
const arc=[bars]f32{0.6,0.82,1,0.75};
/// how often a phrase leaves the choir out, the strings alone
const choirRest:f32=0.15;
/// how many bowed notes may sound at once (a chord dying under the next)
const bowCount=12;
/// how fast the music follows the dark (s); it plays only while the
/// daylight is under this
/// (this one: the glide, s)
const glide:f32=4;
/// the daylight under which the night plays (0..1)
const nightUnder:f32=0.95;
/// the night's loudness
const loudness:f32=1;
/// samples rendered at a time between bars
const chunkFrames=256;
/// the night's music: a choir singing "ahh" through slow open chords, each
/// section moving to its nearest note of the next, swelling through each
/// phrase; strings bowing the chords under it; rising with the dusk, gone
/// by morning
pub const Night=struct{
  /// samples per second
  rate:f32,
  /// its own random numbers
  r:rng.Rng,
  /// the bowed notes sounding; null is free
  bows:dsp.Pool(Bow,bowCount)=.{},
  /// the choir
  choir:Choir,
  /// the note each section sang last (MIDI, soprano first)
  sung:[sections]u8=starts,
  /// silent through the day: nothing sounds, the next night starts a phrase
  resting:bool=true,
  /// the music's level, gliding after the dark
  fade:dsp.Smooth,
  /// the bar about to play
  bar:u32=0,
  /// samples until it does
  left:u32=0,
  /// samples a bar lasts
  barLen:u32,
  /// the phrase's chords
  chords:[bars]Chord=progressions[0],
  /// this phrase leaves the choir out
  choirOut:bool=false,
  /// chords bowed (tests count them)
  bowed:u32=0,
  /// chords the choir sang (tests count them)
  sang:u32=0,
  /// its loudness (tests hush it)
  level:f32=loudness,
  /// a silent night, waiting for the dark, drawing its own random numbers from `r`
  pub fn init(r:*rng.Rng,rate:f32)Night{
    // its own random numbers
    var own:rng.Rng=.init(r.next());
    return.{
      .rate=rate,
      .choir=.init(starts,&own,rate),
      .r=own,
      .fade=.init(0,glide,rate),
      .barLen=m.floorTo(u32,barS*rate),
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
  /// the day's rest: every voice cleared, the choir silenced, the next
  /// night starting a phrase from its first bar
  pub fn rest(n:*Night)void{
    n.bows.clear();
    n.choir=.init(starts,&n.r,n.rate);
    n.sung=starts;
    n.bar=0;
    n.left=0;
    n.resting=true;
  }
  /// plays `buf` (zeroed) out, starting each bar as it comes
  pub fn chunk(n:*Night,buf:[]f32)void{
    // how far into `buf` the bars have played
    var i:usize=0;
    while(i<buf.len){
      if(n.left==0){
        n.startBar();
        n.left=n.barLen;
      }
      // samples until the next bar, and the stretch of `buf` played through them
      const k:u32=@intCast(@min(n.left,buf.len-i));
      const part=buf[i..][0..k];
      n.bows.render(part);
      n.choir.render(part);
      n.left-=k;
      i+=k;
    }
    for(buf)|*s|s.*=n.level*n.fade.next()*s.*;
  }
  /// the bar about to play: a phrase's first may change the chords and
  /// whether the choir sings; the strings bow the bar's chord (letting the
  /// last die away under it), the choir moves to it
  pub fn startBar(n:*Night)void{
    if(n.bar==0){
      if(n.r.float()<newChords)n.chords=progressions[n.r.below(progressions.len)];
      n.choirOut=n.r.float()<choirRest;
    }
    // the bar's chord
    const c=n.chords[n.bar];
    n.bowChord(c);
    if(n.choirOut){
      n.choir.hush();
    }else n.singChord(c,arc[n.bar]);
    n.bar=(n.bar+1)%bars;
  }
  /// the strings let their chord go and bow `c`
  pub fn bowChord(n:*Night,c:Chord)void{
    for(&n.bows.slots)|*v|if(v.*)|*b|b.release();
    for(c)|note|if(note!=0){
      n.bows.slots[n.bows.free() orelse n.quietest()]=.init(note,vary(&n.r,bowVel),&n.r,n.rate);
    };
    n.bowed+=1;
  }
  /// the bow to take when none is free: the quietest let go
  fn quietest(n:*Night)usize{
    // the quietest found so far, and how loud it is
    var best:usize=0;
    var low:f32=2;
    for(n.bows.slots,0..)|v,i|if(v)|b|if(!b.swell.held and b.swell.level<low){
      best=i;
      low=b.swell.level;
    };
    return best;
  }
  /// the choir sings `c` at loudness `loud`: the basses its root, every
  /// other section the tone of it nearest what it sang last (the altos
  /// never on the sopranos' note)
  pub fn singChord(n:*Night,c:Chord,loud:f32)void{
    // the notes each section moves to
    var notes:[sections]u8=undefined;
    for(0..sections)|i|{
      // the bass keeps to the root; the altos keep off the sopranos' note
      const only:?u8=if(i==sections-1)c[0]%12 else null;
      const avoid:?u8=if(i==1)notes[0]else null;
      notes[i]=nearest(c,ranges[i],n.sung[i],only,avoid);
    }
    n.sung=notes;
    n.choir.sing(notes,loud,&n.r);
    n.sang+=1;
  }
};
/// the note in `range` nearest `last` that is a tone of `c` (only the pitch
/// class `only`, if given), never `avoid`
fn nearest(c:Chord,range:m.Vice(u8,2),last:u8,only:?u8,avoid:?u8)u8{
  // the best note found, and how far from `last` it is
  var best:u8=last;
  var dist:u8=255;
  for(range[0]..range[1]+1)|t|{
    // this note, and whether it may be sung
    const note:u8=@intCast(t);
    if(avoid)|a|if(note==a)continue;
    const in=if(only)|pc|note%12==pc else for(c)|x|{
      if(x!=0 and x%12==note%12)break true;
    }else false;
    // how far it is from the last
    const d:u8=if(note>last)note-last else last-note;
    if(in and d<dist){
      best=note;
      dist=d;
    }
  }
  return best;
}
/// the test helpers
const testing=lib.std.testing;
test"each section moves to the nearest tone of the next chord, the basses to its root"{
  // a soprano on A4 moving to E over D steps down to G#4; the bass stays on D
  try testing.expectEqual(@as(u8,68),nearest(two,ranges[0],69,null,null));
  try testing.expectEqual(@as(u8,50),nearest(two,ranges[3],50,two[0]%12,null));
  // from Dmaj9 to Bm9 the bass steps down to B2
  try testing.expectEqual(@as(u8,47),nearest(six,ranges[3],50,six[0]%12,null));
  // the altos never take the sopranos' note
  try testing.expect(nearest(one,ranges[1],66,null,66)!=66);
}
