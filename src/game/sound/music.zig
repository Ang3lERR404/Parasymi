//! the day's music playing: phrases of plunks over a slow pulse, fading with the light.
const lib=@import("../../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const dsp=engine.core.dsp;
const rng=engine.core.rng;
const barSlots=lib.sound.score.barSlots;
const bars=lib.sound.score.bars;
const breathe=lib.sound.score.breathe;
const Chord=lib.sound.score.Chord;
const drums=lib.sound.score.drums;
const drumChance=lib.sound.score.drumChance;
const Drum=lib.sound.voices.Drum;
const echo=lib.sound.score.echo;
const Echo=lib.sound.voices.Echo;
const fifthChance=lib.sound.score.fifthChance;
const lowLevel=lib.sound.score.lowLevel;
const lowFold=lib.sound.score.lowFold;
const lowVel=lib.sound.score.lowVel;
const melHi=lib.sound.score.melHi;
const melLo=lib.sound.score.melLo;
const motif=lib.sound.score.motif;
const music=lib.sound.score.music;
const musicFrom=lib.sound.score.musicFrom;
const musicGlide=lib.sound.score.musicGlide;
const mutate=lib.sound.score.mutate;
const newChords=lib.sound.score.newChords;
const newMotifChance=lib.sound.score.newMotifChance;
const noteChance=lib.sound.score.noteChance;
const noteVel=lib.sound.score.noteVel;
const phraseSteps=lib.sound.score.phraseSteps;
const plunks=lib.sound.score.plunks;
const progressions=lib.sound.score.progressions;
const Plunk=lib.sound.voices.Plunk;
const silent=lib.sound.silent;
const stepS=lib.sound.score.stepS;
const tapChance=lib.sound.score.tapChance;
const tapVel=lib.sound.score.tapVel;
const chordTone=lib.sound.score.chordTone;
const scaleNote=lib.sound.score.scaleNote;
const vary=lib.sound.footstep.vary;
/// samples the music renders at a time between its steps
const chunkFrames=256;
/// the day's music: light piano plunks over a slow steady pulse, a soft
/// drum now and then, fading in with the morning and out at dusk
pub const Music=struct{
  rate:f32,
  r:rng.Rng,
  plunks:[plunks]?Plunk=@splat(null),
  drums:[drums]?Drum=@splat(null),
  nextPlunk:usize=0,
  nextDrum:usize=0,
  echo:Echo,
  fade:dsp.Smooth,
  /// the step about to play, and samples until it does
  step:u32=0,
  left:u32=0,
  stepLen:u32,
  chords:[bars]Chord=progressions[0],
  /// scale steps (null rests) of the motif and of its variation
  motif:[motif]?u8=@splat(null),
  varied:[motif]?u8=@splat(null),
  fresh:bool=true,
  /// silent through the night: nothing rings, the next day starts a phrase
  resting:bool=true,
  /// notes and drums struck (tests count them)
  struck:u32=0,
  drummed:u32=0,
  level:f32=music,
  pub fn init(r:*rng.Rng,rate:f32)Music{
    return.{
      .rate=rate,
      .r=.init(r.next()),
      .echo=.init(rate),
      .fade=.init(0,musicGlide,rate),
      .stepLen=m.floorTo(u32,stepS*rate),
    };
  }
  pub fn daylight(mu:*Music,d:f32)void{mu.fade.target=if(d>musicFrom)m.clamp01(d)else 0;}
  pub fn render(mu:*Music,out:[]f32)void{
    if(mu.fade.target==0 and mu.fade.value<silent){
      if(!mu.resting)mu.rest();
      return;
    }
    mu.resting=false;
    var off:usize=0;
    while(off<out.len){
      const n=@min(chunkFrames,out.len-off);
      var buf:[chunkFrames]f32=@splat(0);
      mu.chunk(buf[0..n]);
      for(out[off..][0..n],buf[0..n])|*o,x|o.*+=x;
      off+=n;
    }
  }
  pub fn rest(mu:*Music)void{
    mu.plunks=@splat(null);
    mu.drums=@splat(null);
    mu.echo=.init(mu.rate);
    mu.step=0;
    mu.left=0;
    mu.resting=true;
  }
  /// plays `buf` (zeroed) out, striking each step as it comes
  pub fn chunk(mu:*Music,buf:[]f32)void{
    var i:usize=0;
    while(i<buf.len){
      if(mu.left==0){
        mu.strikeStep();
        mu.left=mu.stepLen;
      }
      const n:u32=@intCast(@min(mu.left,buf.len-i));
      const part=buf[i..][0..n];
      for(&mu.plunks)|*v|if(v.*)|*p|{
        if(!p.render(part))v.*=null;
      };
      for(&mu.drums)|*v|if(v.*)|*d|{
        if(!d.render(part))v.*=null;
      };
      mu.left-=n;
      i+=n;
    }
    for(buf)|*s|s.*=(s.*+echo*mu.echo.tick(s.*))*mu.level*mu.fade.next();
  }
  pub fn strikeStep(mu:*Music)void{
    if(mu.step==0)mu.phrase();
    const bar=mu.step/barSlots;
    const s=mu.step%barSlots;
    const c=mu.chords[bar];
    const at:usize=if(s==0)0 else if(s%2==0)1 else 2;
    const line=if(mu.step<motif)mu.motif else mu.varied;
    if(line[mu.step%motif])|i|{
      const n=scaleNote(i);
      mu.plunk(if(s==0)chordTone(n,c)else n,vary(&mu.r,noteVel[at]));
    }
    const low=lowLevel+c.root-(if(c.root>lowFold)@as(u8,12)else 0);
    if(s==0)mu.plunk(low,vary(&mu.r,lowVel));
    if(s==barSlots/2 and mu.r.float()<fifthChance)mu.plunk(low+7,vary(&mu.r,lowVel*0.8));
    if(s==0 and mu.r.float()<drumChance)mu.drum(1);
    if(s==barSlots/2 and mu.r.float()<tapChance)mu.drum(tapVel);
    mu.step=(mu.step+1)%phraseSteps;
  }
  /// a new phrase: maybe new chords, a new motif or a variation of the last
  pub fn phrase(mu:*Music)void{
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
    var out:[motif]?u8=undefined;
    var i:u8=@intCast(melLo+2+mu.r.below(melHi-melLo-3));
    for(&out,0..)|*o,k|{
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
    var out=line;
    var last:u8=melLo+(melHi-melLo)/2;
    for(&out)|*o|{
      if(mu.r.float()<mutate)o.*=if(o.*)|i|(if(mu.r.float()<0.3)null else mu.wander(i,1))else mu.wander(last,1);
      if(o.*)|i|last=i;
    }
    return out;
  }
  /// `i` moved up to `by` steps either way, kept in the melody's range
  pub fn wander(mu:*Music,i:u8,by:u8)u8{
    const d:i32=@as(i32,@intCast(mu.r.below(2*by+1)))-by;
    return@intCast(m.clamp(@as(i32,i)+d,melLo,melHi));
  }
  pub fn plunk(mu:*Music,note:u8,vel:f32)void{
    mu.plunks[mu.freePlunk()]=.init(note,vel,&mu.r,mu.rate);
    mu.struck+=1;
  }
  pub fn drum(mu:*Music,vel:f32)void{
    mu.drums[mu.nextDrum]=.init(vel,&mu.r,mu.rate);
    mu.nextDrum=(mu.nextDrum+1)%drums;
    mu.drummed+=1;
  }
  pub fn freePlunk(mu:*Music)usize{
    for(mu.plunks,0..)|v,i|if(v==null)return i;
    defer mu.nextPlunk=(mu.nextPlunk+1)%plunks;
    return mu.nextPlunk;
  }
};
