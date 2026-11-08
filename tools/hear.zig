//! `zig build hear`: Claude hears the gardener's voice. The microphone is
//! listened to all the time and cut at breaths into phrases. Each phrase is
//! written as a WAV, its words read by whisper.cpp's server (on the GPU,
//! started here and stopped with this), and how it was said measured here:
//! pitch, loudness, held sounds and pauses, written in the gardener's own
//! text as sound (a held word drawn out, a loud one in capitals, a pause as
//! "..", a lilt as "~", a rise as "?"). The phrase goes into the link
//! folder as a message (`link.toClaude`), so the bridge pushes it into
//! Claude's session the moment it is heard, as a message typed in the game
//! would be; beside it, `link/heard/<ms>.png` (a spectrogram with the pitch
//! drawn over it) and `.txt` (each word's numbers) for a closer look.
//! whisper.cpp lives outside the repo (`--whisper=<dir>`, by default
//! `%USERPROFILE%\whisper`: `bin\cuda\Release\whisper-server.exe` and
//! `models\ggml-small.en.bin`). Ctrl+C stops it, and the server with it.
//! Claude's body (TOXICCIBU) keeps one running hidden from login
//! (`--body`, from `zig build ear`): whisper sleeps after a long quiet and
//! wakes with a voice, a pulse goes to the body's folder each second
//! (`ear.json`), and only one ear ever holds the microphone.
/// the standard library
const std=@import("std");
/// the engine package: WASAPI, the maths, the PNG writer
const engine=@import("engine");
/// the game's hub, for the link folder's names and how a message is written
const lib=@import("parasymi");
/// the tools' shared sound files and spectra
const audio=@import("audio");
/// the meeting place shared with the bridge
const link=lib.link;
/// the Windows audio binding: the microphone
const wasapi=engine.wasapi;
/// all the maths: casts, tau, powers
const m=engine.core.math;
/// gain to decibels
const dsp=engine.core.dsp;
/// writes the spectrogram
const png=engine.core.png;
/// an allocator
const Allocator=std.mem.Allocator;
/// the I/O interface every call goes through
const Io=std.Io;
/// a directory handle
const Dir=Io.Dir;
/// a growable list
const ArrayList=std.ArrayList;
/// a text built up in memory
const Allocating=Io.Writer.Allocating;
/// prints a line to the console, for the gardener
const print=std.debug.print;
/// reads the server's answer
const parseFromSliceLeaky=std.json.parseFromSliceLeaky;
/// a letter in capitals
const toUpper=std.ascii.toUpper;
/// whether a byte is a letter
const isAlpha=std.ascii.isAlphabetic;
/// whether a byte is a letter or a digit
const isAlnum=std.ascii.isAlphanumeric;
/// whether one text starts with another
const startsWith=std.mem.startsWith;
/// the text with spaces cut from its ends
const trim=std.mem.trim;
/// how many samples a second everything runs at (Hz), what whisper wants
const rate:u32=16000;
/// one frame of listening: 10 ms of samples
const hop:usize=160;
/// frames a second
const framesPerS:f32=m.ratio(rate,hop);
/// the window the pitch is looked for in (40 ms: two periods at the lowest)
const pitchWin:usize=640;
/// the lowest and highest voice pitch looked for (Hz)
const minHz:f32=70;
/// the highest voice pitch looked for (Hz), a squeal included (raised to
/// reach the gardener's own top: an A#5, ~940 Hz)
const maxHz:f32=1000;
/// above this share of samples crossing zero, a frame is hiss, not voice
/// (a voice's crossings follow its low resonances; an s rushes past 4 kHz)
const hissCrossings:f32=0.25;
/// how alike a window and its shift must be to call it voiced (0..1)
const clarityMin:f32=0.6;
/// a shorter lag within this share of the best is taken instead, so a
/// voice is never heard an octave low
const octaveGuard:f32=0.9;
/// how far above the room's own hum a frame must be to be speech (dB)
const speakAbove:f32=12;
/// quieter than this is never speech, however still the room (dB) (lowered
/// from -55 so the gardener's little noises reach the ear, 2026-11-07)
const speakMin:f32=-65;
/// how fast the room's hum is allowed to rise between phrases (dB a frame)
const floorRise:f32=0.02;
/// quieter than this is no microphone at all, only zeros (dB)
const deadBelow:f32=-110;
/// a steady sound taken as the hum sits this far under its own mean (dB)
const hushBelow:f32=3;
/// loud frames in a row that begin a phrase (30 ms)
const startFrames:u32=3;
/// quiet frames in a row that end one: a breath (0.7 s)
const endFrames:u32=70;
/// the longest phrase before it is cut anyway (15 s)
const maxFrames:u32=1500;
/// quiet kept before a phrase's first loud frame, so a soft start isn't cut (0.3 s)
const prerollFrames:u32=30;
/// quiet kept after its last loud frame, so a trailing sound (a soft final
/// s, quieter than the voice) isn't cut (0.35 s)
const tailFrames:u32=35;
/// the size of the spectrogram's transform (samples, 32 ms)
const fftN:usize=512;
/// the spectrogram's highest pitch (Hz): where a voice's shape lives
const specTopHz:f32=4000;
/// pixels a frequency bin is drawn tall
const binPx:u32=2;
/// the quietest and loudest a spectrogram pixel shows (dB)
const specLow:f32=-100;
/// the loudest a spectrogram pixel shows (dB)
const specHigh:f32=-30;
/// a word louder than the phrase's middle by this is said loud (dB)
const loudBy:f32=6;
/// a word this much longer than its letters need is held (times)
const heldBy:f32=2;
/// and never held if shorter than this (s)
const heldMin:f32=0.45;
/// how long one letter takes to say, and a word's start (s)
const letterS:f32=0.07;
/// how long a word's start takes to say (s)
const wordS:f32=0.1;
/// one repeat of a held vowel stands for this long (s)
const repeatS:f32=0.1;
/// the most repeats a held vowel gets
const maxRepeats:usize=8;
/// this far below the phrase's middle loudness the voice has stopped (dB)
const quietBy:f32=15;
/// a gap between words this long is a pause, ".." (s)
const pauseS:f32=0.4;
/// a phrase's last word rising this much: a question "?" when its words ask one, else excitement "!" (semitones)
const riseSt:f32=2.5;
/// rising and falling back this much is a lilt, "~" (semitones)
const liltSt:f32=2;
/// falling this much is a flat close, "." (semitones)
const fallSt:f32=3;
/// the pitch semitones are counted from (Hz)
const stBase:f32=100;
/// semitones in an octave
const stPerOctave:f32=12;
/// where whisper's server listens
const host="127.0.0.1";
/// the port it listens on
const port="8178";
/// the server's address
const serverUrl="http://"++host++":"++port;
/// names whisper should spell the way we do
const prompt="Toxi, Toxicibu, Angel, Parasymi.";
/// whisper's server, under its folder
const serverExe="bin\\cuda\\Release\\whisper-server.exe";
/// its model, under its folder
const modelFile="models\\ggml-small.en.bin";
/// where heard phrases are kept, inside the link folder
const heardDir=link.folder++"/heard";
/// how long the server may take to wake (s)
const serverWaitS=60;
/// left in the link folder by tools/speak.zig while Claude's own voice
/// plays: a phrase heard then is Claude's, not the gardener's
const speakingMark="speaking";
/// how many frames between looks at that mark (0.1 s)
const markEvery:u32=10;
/// what a message says it is
const aloud="(aloud) ";
/// what can stop the listening
const Error=error{ServerNotStarted,NoMicrophone,NoWords};
/// what one frame did to the listening
const Cut=union(enum){
  /// nothing changed
  none,
  /// a phrase began; how many frames back its loud start was
  begin:u32,
  /// a phrase ended; how many quiet frames end it
  end:u32,
};
/// cuts a stream of frames' loudness at breaths: a phrase begins after a
/// few loud frames and ends after a breath's quiet, the room's own hum
/// followed between phrases so a fan or a hum isn't heard as speech
const Breaths=struct{
  /// the room's hum (dB); none until the first frame
  floor:?f32=null,
  /// loud frames in a row so far
  loudRun:u32=0,
  /// quiet frames in a row within a phrase
  quietRun:u32=0,
  /// frames since the phrase began; zero while not in one
  len:u32=0,
  /// quiet frames in a row that end a phrase (a breath; shorter between
  /// words read one at a time)
  endAfter:u32=endFrames,
  /// the phrase's frames' loudness added up (dB), for its mean
  sum:f32=0,
  /// one frame of `db` heard: whether a phrase began or ended
  fn step(b:*Breaths,db:f32)Cut{
    // digital silence (a device waking, nothing recorded yet) says nothing
    // about the room: never the hum, only quiet within a phrase
    const dead=db<deadBelow;
    if(dead and b.len==0)return.none;
    if(!dead){
      // the hum falls at once to anything quieter, and rises only slowly
      // and only between phrases, so a long phrase never becomes the hum
      const fl=b.floor orelse db;
      b.floor=if(db<fl)db else if(b.len==0)fl+floorRise else fl;
    }
    // whether this frame is speech
    const loud=!dead and db>b.floor.?+speakAbove and db>speakMin;
    if(b.len==0){
      b.loudRun=if(loud)b.loudRun+1 else 0;
      if(b.loudRun<startFrames)return.none;
      b.len=b.loudRun;
      b.quietRun=0;
      return.{.begin=b.loudRun};
    }
    b.len+=1;
    b.sum+=db;
    b.quietRun=if(loud)0 else b.quietRun+1;
    if(b.quietRun<b.endAfter and b.len<maxFrames)return.none;
    // the quiet that ended it
    const q=b.quietRun;
    // a phrase cut at its longest was most likely a steady sound (music,
    // a fan) and not a voice: it becomes the room's hum
    const hum=if(q<b.endAfter)@max(b.floor.?,b.sum/m.f(b.len)-hushBelow)else b.floor.?;
    b.*=.{.floor=hum,.endAfter=b.endAfter};
    return.{.end=q};
  }
};
/// how loud `x` is (dB, of its root mean square)
fn dbOf(x:[]const f32)f32{
  // the sum of squares
  var s:f32=0;
  for(x)|v|s+=v*v;
  return dsp.gainToDb(@sqrt(s/m.f(x.len))+tiny);
}
/// the shortest and longest lag looked at (samples)
const minLag:usize=m.floorTo(usize,m.f(rate)/maxHz);
/// the longest lag looked at (samples)
const maxLag:usize=m.floorTo(usize,m.f(rate)/minHz)+1;
/// samples one pitch reading needs
const pitchNeeds:usize=pitchWin+maxLag+1;
/// the voice's pitch in `x` (at least `pitchNeeds` long), or none when
/// unvoiced: the lag where the window is most like itself shifted
fn pitchAt(x:[]const f32)?f32{
  // the window's own energy
  var e0:f32=0;
  for(x[0..pitchWin])|v|e0+=v*v;
  if(e0<=1e-7)return null;
  // a hiss (s, sh, the "tch" of "pitch") flutters across zero far more
  // often than a voice: it has no pitch, however alike it looks shifted
  var crossings:usize=0;
  for(1..pitchWin)|i|{
    if((x[i]>=0)!=(x[i-1]>=0))crossings+=1;
  }
  if(m.ratio(crossings,pitchWin)>hissCrossings)return null;
  // how alike the window is to itself at each lag
  var c:[maxLag+2]f32=@splat(0);
  // the best likeness
  var best:f32=0;
  for(minLag-1..maxLag+2)|lag|{
    // the product with the shift, and the shift's own energy
    var r:f32=0;
    var el:f32=0;
    for(0..pitchWin)|i|{
      r+=x[i]*x[i+lag];
      el+=x[i+lag]*x[i+lag];
    }
    c[lag]=if(el>0)r/@sqrt(e0*el)else 0;
    if(lag>=minLag and lag<=maxLag)best=@max(best,c[lag]);
  }
  if(best<clarityMin)return null;
  // the first peak nearly as good as the best: the true period, not a multiple
  for(minLag..maxLag+1)|lag|{
    if(c[lag]<best*octaveGuard or c[lag]<c[lag-1] or c[lag]<c[lag+1])continue;
    // the peak's true place between samples (a parabola through three)
    const den=c[lag-1]-2*c[lag]+c[lag+1];
    const shift=if(den!=0)0.5*(c[lag-1]-c[lag+1])/den else 0;
    return m.f(rate)/(m.f(lag)+shift);
  }
  return null;
}
/// semitones above `stBase` of `hz`
fn semitones(hz:f32)f32{return stPerOctave*@log2(hz/stBase);}
/// a phrase's frames measured: each frame's loudness and pitch
const Frames=struct{
  /// each frame's loudness (dB)
  db:[]f32,
  /// each frame's pitch (Hz), none when unvoiced
  hz:[]?f32,
  /// measures every frame of `x` into `arena`
  fn measure(arena:Allocator,x:[]const f32)Allocator.Error!Frames{
    // how many whole frames there are
    const n=x.len/hop;
    const fr=Frames{.db=try arena.alloc(f32,n),.hz=try arena.alloc(?f32,n)};
    for(0..n)|i|{
      fr.db[i]=dbOf(x[i*hop..][0..hop]);
      fr.hz[i]=if(i*hop+pitchNeeds<=x.len)pitchAt(x[i*hop..])else null;
    }
    return fr;
  }
  /// the frames from `a` to `b` seconds, kept inside the phrase
  fn span(fr:Frames,a:f32,b:f32)struct{usize,usize}{
    // the first frame and the one past the last
    const lo=@min(fr.db.len,m.floorTo(usize,@max(0,a)*framesPerS));
    const hi=@min(fr.db.len,@max(lo+1,m.floorTo(usize,@max(0,b)*framesPerS)+1));
    return.{@min(lo,hi),hi};
  }
  /// the mean loudness from `a` to `b` seconds (dB)
  fn loudness(fr:Frames,a:f32,b:f32)f32{
    const lo,const hi=fr.span(a,b);
    if(hi<=lo)return specLow;
    // the sum of the frames' loudness
    var s:f32=0;
    for(fr.db[lo..hi])|d|s+=d;
    return s/m.f(hi-lo);
  }
  /// how long from `a` to `b` seconds the sound was at least `level` dB
  /// (`.loud`) or below it (`.quiet`), in seconds
  fn lasting(fr:Frames,a:f32,b:f32,level:f32,side:Side)f32{
    const lo,const hi=fr.span(a,b);
    // the frames on that side of the level
    var n:usize=0;
    for(fr.db[lo..hi])|d|{
      if((d>=level)==(side==.loud))n+=1;
    }
    return m.f(n)/framesPerS;
  }
  /// which side of a level is counted
  const Side=enum{
    /// at or above it
    loud,
    /// below it
    quiet,
  };
  /// the voiced pitches from `a` to `b` seconds, in semitones, into `out`
  fn voiced(fr:Frames,a:f32,b:f32,out:[]f32)[]f32{
    const lo,const hi=fr.span(a,b);
    // how many were voiced
    var n:usize=0;
    for(fr.hz[lo..hi])|h|{
      if(h)|hz|{
        if(n==out.len)break;
        out[n]=semitones(hz);
        n+=1;
      }
    }
    return out[0..n];
  }
};
/// the mean of `x` (0 when empty)
fn mean(x:[]const f32)f32{
  if(x.len==0)return 0;
  // the sum
  var s:f32=0;
  for(x)|v|s+=v;
  return s/m.f(x.len);
}
/// the middle value of `x` (sorts a copy in `arena`)
fn median(arena:Allocator,x:[]const f32)Allocator.Error!f32{
  if(x.len==0)return 0;
  // the sorted copy
  const s=try arena.dupe(f32,x);
  std.mem.sort(f32,s,{},std.sort.asc(f32));
  return s[s.len/2];
}
/// one word as whisper heard it
const Word=struct{
  /// its text, punctuation and all
  text:[]const u8,
  /// when it began (s into the phrase)
  start:f32,
  /// when it ended (s)
  end:f32,
};
/// whisper's verbose answer, only what is used
const Verbose=struct{
  /// its pieces of speech
  segments:[]const Segment=&.{},
  /// one piece
  const Segment=struct{
    /// its tokens, timed (each a word or a piece of one)
    words:[]const Token=&.{},
  };
  /// one timed token
  const Token=struct{
    /// its text; a leading space begins a new word
    word:[]const u8,
    /// when it began (s)
    start:f32,
    /// when it ended (s)
    end:f32,
  };
};
/// whisper's tokens joined into words: a token with a leading space begins
/// one, any other (a piece of a word, punctuation) joins the last; markers
/// like "[BLANK_AUDIO]" are dropped
fn wordsOf(arena:Allocator,v:Verbose)Allocator.Error![]Word{
  // the words so far, each text growing in the arena
  var out:ArrayList(Word)=.empty;
  // inside a marker, which whisper splits into pieces ("[", "BLANK", "]")
  var marker=false;
  for(v.segments)|seg|{
    for(seg.words)|t|{
      // the token without its spaces
      const bare=trim(u8,t.word," ");
      if(bare.len>0 and bare[0]=='[')marker=true;
      if(marker){
        if(std.mem.indexOfScalar(u8,bare,']')!=null)marker=false;
        continue;
      }
      if(bare.len==0)continue;
      if(out.items.len==0 or startsWith(u8,t.word," ")){
        try out.append(arena,.{.text=try arena.dupe(u8,bare),.start=t.start,.end=t.end});
        continue;
      }
      // the word it joins
      const w=&out.items[out.items.len-1];
      w.text=try std.mem.concat(arena,u8,&.{w.text,bare});
      w.end=@max(w.end,t.end);
    }
  }
  return out.items;
}
/// how a phrase's close moved: its last word's pitch, start to end
const Close=enum{
  /// nothing to say about it
  plain,
  /// it rose: a question
  rise,
  /// it rose and fell back: a lilt
  lilt,
  /// it fell flat: said and meant
  fall,
};
/// how the pitches `st` (semitones, in order) move through a close
fn closeOf(st:[]const f32)Close{
  if(st.len<6)return.plain;
  // the first, middle and last thirds' pitch
  const third=st.len/3;
  const a=mean(st[0..third]);
  const mid=mean(st[third..st.len-third]);
  const z=mean(st[st.len-third..]);
  if(mid-a>=liltSt and mid-z>=liltSt)return.lilt;
  if(z-a>=riseSt)return.rise;
  if(a-z>=fallSt)return.fall;
  return.plain;
}
/// whether a byte is a vowel (y counted, as it is sung)
fn isVowel(c:u8)bool{
  return switch(std.ascii.toLower(c)){'a','e','i','o','u','y'=>true,else=>false};
}
/// `w`'s body (letters, digits, apostrophes) and what trails it
fn split(w:[]const u8)struct{[]const u8,[]const u8}{
  // where the trailing punctuation begins
  var n=w.len;
  while(n>0 and !isAlnum(w[n-1]))n-=1;
  return.{w[0..n],w[n..]};
}
/// writes `body` held for `repeats` more: its last vowel drawn out (or its
/// last letter, if it has none), the way the gardener writes "yeeees"
fn writeHeld(w:*Io.Writer,body:[]const u8,repeats:usize,loud:bool)Io.Writer.Error!void{
  // the letter drawn out
  var at:?usize=null;
  for(body,0..)|c,i|{if(isVowel(c))at=i;}
  if(at==null){
    for(body,0..)|c,i|{if(isAlpha(c))at=i;}
  }
  for(body,0..)|c,i|{
    // the letter, in capitals when said loud
    const ch=if(loud)toUpper(c)else c;
    try w.writeByte(ch);
    if(at==i)try w.splatByteAll(ch,repeats);
  }
}
/// the phrase written as the gardener writes sound: each word as whisper
/// heard it, held words drawn out, loud ones in capitals, pauses as "..",
/// the close as "?", "~" or "."
fn annotate(arena:Allocator,words:[]const Word,fr:Frames)Allocator.Error![]u8{
  // the phrase's middle loudness, over its words
  const louds=try arena.alloc(f32,words.len);
  for(words,0..)|w,i|louds[i]=fr.loudness(w.start,w.end);
  const mid=try median(arena,louds);
  // below this the voice has stopped: a pause, not a soft sound
  const still=mid-quietBy;
  // pitches gathered for one word
  const buf=try arena.alloc(f32,fr.db.len+1);
  // the close: the last word with a voice in it
  var close:Close=.plain;
  // which word the close is told after
  var closeAt:usize=words.len;
  var k=words.len;
  while(k>0){
    k-=1;
    const st=fr.voiced(words[k].start,words[k].end,buf);
    if(st.len<3)continue;
    close=closeOf(st);
    closeAt=k;
    break;
  }
  // the text, built up
  var aw:Allocating=.init(arena);
  const w=&aw.writer;
  for(words,0..)|wd,i|{
    if(i>0)w.writeByte(' ') catch return error.OutOfMemory;
    const body,const tail=split(wd.text);
    // how long it took against how long its letters need
    var letters:usize=0;
    for(body)|c|{if(isAlpha(c))letters+=1;}
    const need=letterS*m.f(letters)+wordS;
    // (counted from the sound itself: whisper's word times are rough)
    const took=fr.lasting(wd.start,wd.end,still,.loud);
    const held=letters>0 and took>=heldMin and took>=need*heldBy;
    const repeats:usize=if(held)@min(maxRepeats,@max(2,m.floorTo(usize,(took-need)/repeatS)))else 0;
    const loud=louds[i]>=mid+loudBy and words.len>1;
    writeHeld(w,body,repeats,loud) catch return error.OutOfMemory;
    // the punctuation, the close changing it
    if(i==closeAt and close!=.plain){
      // the tail without its own close
      const keep=trim(u8,tail,".?!");
      w.writeAll(keep) catch return error.OutOfMemory;
      // a rise is a question only when the words ask one; on a statement
      // it is excitement, "really!" (the gardener, hearing it, 2026-11-07)
      const asked=std.mem.indexOfScalar(u8,tail,'?')!=null;
      w.writeAll(switch(close){.rise=>if(asked)"?"else"!",.lilt=>"~",.fall=>".",.plain=>unreachable}) catch return error.OutOfMemory;
    }else{
      w.writeAll(tail) catch return error.OutOfMemory;
    }
    // a pause before the next word
    if(i+1<words.len and tail.len==0 and fr.lasting(wd.end,words[i+1].start,still,.quiet)>=pauseS)w.writeAll("..") catch return error.OutOfMemory;
  }
  return aw.written();
}
/// a loudness so small it only keeps the logarithm finite
const tiny:f32=1e-9;
/// a spectrogram's middle loudness colour (violet), before gold
const violet=[3]f32{0.35,0.1,0.5};
/// its loudest colour (gold)
const gold=[3]f32{1,0.8,0.3};
/// the pitch line's ink (cyan)
const pitchInk=[3]u8{40,230,230};
/// a word's start tick's ink (pale)
const tickInk=[3]u8{230,230,230};
/// how tall a word's start tick is (pixels)
const tickPx:usize=6;
/// the spectrogram's height (pixels)
const specBins:usize=m.floorTo(usize,specTopHz*m.f(fftN)/m.f(rate));
/// how tall the spectrogram is drawn (pixels)
const specH:u32=@intCast(specBins*binPx);
/// a spectrogram of `x`: time across (a frame a pixel), pitch up to
/// `specTopHz`, loudness as colour (dark, violet, gold), the voice's pitch
/// drawn over it in cyan and each word's start ticked at the top
fn spectrogram(arena:Allocator,x:[]const f32,fr:Frames,words:[]const Word)![]u8{
  // one pixel column a frame
  const w:u32=@intCast(@max(1,fr.db.len));
  const px=try arena.alloc(u8,@as(usize,w)*specH*4);
  @memset(px,0);
  // the transform's buffers and its window
  var re:[fftN]f32=undefined;
  var im:[fftN]f32=undefined;
  for(0..w)|col|{
    for(0..fftN)|i|{
      // the sample under the window's middle, or silence past the ends
      const s=@as(isize,@intCast(col*hop+i))-@as(isize,fftN/2-hop/2);
      const v=if(s>=0 and s<x.len)x[@intCast(s)]else 0;
      const hann=0.5-0.5*@cos(m.tau*m.f(i)/m.f(fftN-1));
      re[i]=v*hann;
      im[i]=0;
    }
    audio.fft(&re,&im);
    for(0..specBins)|bin|{
      // the bin's loudness, and its colour: dark, violet, gold
      const mag=@sqrt(re[bin]*re[bin]+im[bin]*im[bin])/m.f(fftN);
      const t=m.unlerp(specLow,specHigh,dsp.gainToDb(mag+tiny));
      const lo=@min(1,t*2);
      const hi=@max(0,t*2-1);
      const rgb=[3]f32{m.lerp(m.lerp(0,violet[0],lo),gold[0],hi),m.lerp(m.lerp(0,violet[1],lo),gold[1],hi),m.lerp(m.lerp(0,violet[2],lo),gold[2],hi)};
      for(0..binPx)|dy|{
        // the pixel, counted from the top
        const y=specH-1-@as(u32,@intCast(bin*binPx+dy));
        const o=(@as(usize,y)*w+col)*4;
        for(0..3)|c|px[o+c]=@intFromFloat(rgb[c]*255);
        px[o+3]=255;
      }
    }
    // the pitch, if voiced and in view
    if(fr.hz[col])|hz|{
      if(hz<specTopHz){
        const y=specH-1-@min(specH-1,m.floorTo(u32,hz/specTopHz*m.f(specH)));
        for([_]u32{y,@min(specH-1,y+1)})|yy|{
          const o=(@as(usize,yy)*w+col)*4;
          @memcpy(px[o..][0..3],&pitchInk);
        }
      }
    }
  }
  // each word's start, ticked at the top
  for(words)|wd|{
    const col=@min(w-1,m.floorTo(u32,@max(0,wd.start)*framesPerS));
    for(0..tickPx)|y|{
      const o=(y*w+col)*4;
      @memcpy(px[o..][0..3],&tickInk);
    }
  }
  return png.encode(arena,w,specH,px,.rgba);
}
/// each word's numbers, a line each: when, how long, how loud, its pitch
fn details(arena:Allocator,words:[]const Word,fr:Frames,said:[]const u8)![]u8{
  var aw:Allocating=.init(arena);
  const w=&aw.writer;
  // pitches gathered for one word
  const buf=try arena.alloc(f32,fr.db.len+1);
  try w.print("{s}\n{d:.2} s\nword start end dur dB pitch(Hz first->last, voiced frames)\n",.{said,m.f(fr.db.len)/framesPerS});
  for(words)|wd|{
    const st=fr.voiced(wd.start,wd.end,buf);
    try w.print("{s} {d:.2} {d:.2} {d:.2} {d:.1}",.{wd.text,wd.start,wd.end,wd.end-wd.start,fr.loudness(wd.start,wd.end)});
    if(st.len>0){
      try w.print(" {d:.0}->{d:.0} ({d})\n",.{stBase*m.pow(f32,2,st[0]/stPerOctave),stBase*m.pow(f32,2,st[st.len-1]/stPerOctave),st.len});
    }else try w.writeAll(" unvoiced\n");
  }
  return aw.written();
}
/// the share of voiced frames left out at each end of the pitch range, so
/// a stray misreading never stretches it
const rangeTrim:f32=0.1;
/// the voice's pitch range (Hz), its stray ends left out, or none
fn pitchRange(arena:Allocator,fr:Frames)Allocator.Error!?struct{f32,f32}{
  // the voiced pitches, sorted
  var hz:ArrayList(f32)=.empty;
  for(fr.hz)|h|{
    if(h)|v|try hz.append(arena,v);
  }
  if(hz.items.len==0)return null;
  std.mem.sort(f32,hz.items,{},std.sort.asc(f32));
  // how many are left out at each end
  const cut=m.floorTo(usize,m.f(hz.items.len)*rangeTrim);
  return.{hz.items[cut],hz.items[hz.items.len-1-cut]};
}
/// the highest pitch counted as the gardener's voice (Hz): once 320, "a
/// squeal above it is more often a misread hiss", but those squeals were
/// the gardener's own little noises (2026-11-07), so now the whole range
/// the ear looks in (music playing may slip through again: watch for it)
const speakTopHz:f32=maxHz;
/// how many frames (10 ms) of voice a phrase needs to be heard at all
/// (a little noise can be short)
const minVoiced:usize=8;
/// what a phrase is written as when whisper finds no words in a voice
const littleSound="(a little sound)";
/// how many of a phrase's frames have a speaking voice's pitch
fn voicedFrames(fr:Frames)usize{
  // the frames voiced at a speaking pitch
  var n:usize=0;
  for(fr.hz)|h|{
    if(h)|hz|{
      if(hz<=speakTopHz)n+=1;
    }
  }
  return n;
}
/// the lines whisper makes up from near-silence (learned from subtitles),
/// written plain: lowercase, no marks
const stockLines=[_][]const u8{"thanks for watching","thank you for watching","thank you","thanks","thank you very much","you","bye","please subscribe","subtitles by"};
/// a phrase whose loudest tenth of frames stays under this is faint: the
/// gardener's speech never did tonight (-57 dB at its quietest, "Oooooh,
/// okayyyyy."), the hiss whisper read as "Thanks for watching!" sat at -61
const faintDb:f32=-58;
/// whether whisper's `words` are one of its stock lines over a phrase too
/// faint to hold them (the gardener's quiet squeaks have no words, so they
/// are never touched)
fn madeUp(arena:Allocator,words:[]const Word,fr:Frames)Allocator.Error!bool{
  if(words.len==0 or fr.db.len==0)return false;
  // the words, plain and joined
  var aw:Allocating=.init(arena);
  for(words,0..)|wd,i|{
    if(i>0)aw.writer.writeByte(' ') catch return error.OutOfMemory;
    aw.writer.writeAll(try ownear.plainWord(arena,wd.text)) catch return error.OutOfMemory;
  }
  const text=aw.written();
  const stock=for(stockLines)|s|{
    if(std.mem.eql(u8,text,s) or (s.len>8 and startsWith(u8,text,s)))break true;
  }else false;
  if(!stock)return false;
  // the loudest tenth of its frames
  const db=try arena.dupe(f32,fr.db);
  std.mem.sort(f32,db,{},std.sort.asc(f32));
  return db[m.floorTo(usize,m.f(db.len)*0.9)]<faintDb;
}
/// how long whisper may lie idle before it sleeps, its GPU memory freed
/// (10 min; the gardener's pick, 2026-11-07: woken again by a voice)
const whisperRestMs:i64=10*60*1000;
/// how often the ear's pulse is written (ms)
const pulseMs:i64=1000;
/// how long the ear waits before looking for a missing microphone again (ms)
const micRetryMs:i64=5000;
/// the body's folder in Claude's shared memory, under the user's profile:
/// the ear's pulse lies there beside the clock's (TOXICCIBU's body)
const bodySub="Documents\\Claude\\memory\\body";
/// the ear's pulse: one line of JSON, rewritten each second
const pulseFile="ear.json";
/// the pulse while being written, renamed over it when whole
const pulseTmp="ear.json.tmp";
/// left by the body when it stops: the ear it started stops with it
const stopNote="ear.stop";
/// tries at putting a pulse in place while a reader holds the file
const renameTries:u32=8;
/// ms between those tries
const renameWaitMs:i64=15;
/// the lock only one ear holds: the microphone and whisper's port are one
const lockName=std.unicode.utf8ToUtf16LeStringLiteral("Local\\ToxicibuEar");
/// Windows' own calls the ear needs: one ear at a time, and whisper bound
/// to the ear's life, so a killed ear never leaves it holding the GPU
const win=struct{
  /// a Windows handle
  const Handle=std.os.windows.HANDLE;
  /// Windows' calling convention
  const cc=std.builtin.CallingConvention.winapi;
  /// "already exists", from a lock another ear made
  const alreadyExists:u32=183;
  /// a job's limits: its processes end when its last handle closes
  const killOnClose:u32=0x2000;
  /// the class of a job's information that holds those limits
  const extendedLimits:i32=9;
  /// makes (or opens) a named lock, held at once if `owner`
  extern "kernel32" fn CreateMutexW(attr:?*anyopaque,owner:i32,name:[*:0]const u16)callconv(cc)?Handle;
  /// why the last call failed
  extern "kernel32" fn GetLastError()callconv(cc)u32;
  /// makes a job: a group of processes ended together
  extern "kernel32" fn CreateJobObjectW(attr:?*anyopaque,name:?[*:0]const u16)callconv(cc)?Handle;
  /// sets a job's limits
  extern "kernel32" fn SetInformationJobObject(job:Handle,class:i32,info:*anyopaque,len:u32)callconv(cc)i32;
  /// puts a process in a job
  extern "kernel32" fn AssignProcessToJobObject(job:Handle,process:Handle)callconv(cc)i32;
  /// this process's number
  extern "kernel32" fn GetCurrentProcessId()callconv(cc)u32;
  /// a job's basic limits, as Windows lays them out
  const Basic=extern struct{
    /// time limits, unused
    perProcessTime:i64=0,
    /// the job's time limit, unused
    perJobTime:i64=0,
    /// which limits hold
    flags:u32=0,
    /// working set limits, unused
    minSet:usize=0,
    /// the largest working set, unused
    maxSet:usize=0,
    /// how many processes, unused
    processes:u32=0,
    /// which cores, unused
    affinity:usize=0,
    /// priority, unused
    priority:u32=0,
    /// scheduling, unused
    scheduling:u32=0,
  };
  /// a job's extended limits, as Windows lays them out
  const Extended=extern struct{
    /// the basic limits
    basic:Basic=.{},
    /// counted reads and writes, unused
    counters:[6]u64=@splat(0),
    /// memory limits and peaks, unused
    memory:[4]usize=@splat(0),
  };
  /// whether the ear's lock was taken here, or another ear holds it
  const Lock=enum{
    /// this ear listens
    mine,
    /// another ear already listens
    taken,
  };
  /// takes the one ear's lock (kept until this process ends); a lock that
  /// can't be made at all is taken as ours
  fn takeLock()Lock{
    _=CreateMutexW(null,1,lockName) orelse return.mine;
    return if(GetLastError()==alreadyExists).taken else.mine;
  }
  /// a job whose processes end when the ear does, or null if Windows says no
  fn killingJob()?Handle{
    const job=CreateJobObjectW(null,null) orelse return null;
    var info=Extended{.basic=.{.flags=killOnClose}};
    if(SetInformationJobObject(job,extendedLimits,&info,@sizeOf(Extended))==0)return null;
    return job;
  }
};
/// ms since 1970 (UTC) by the system clock
fn nowMs(io:Io)i64{return@intCast(@divTrunc(Io.Clock.real.now(io).nanoseconds,std.time.ns_per_ms));}
/// whisper's server, woken when a voice begins and put to sleep after a
/// long quiet, so its GPU memory is held only while the gardener talks
const Whisper=struct{
  /// the server's program
  exe:[]const u8,
  /// its model
  model:[]const u8,
  /// the job the server is put in, ended with the ear (even a killed one)
  job:?win.Handle,
  /// the server, while awake
  child:?std.process.Child=null,
  /// whether it has answered since it woke
  answered:bool=false,
  /// when it last read a phrase, or woke (ms)
  usedMs:i64=0,
  /// whisper asleep, its job made ready
  fn init(exe:[]const u8,model:[]const u8)Whisper{return.{.exe=exe,.model=model,.job=win.killingJob()};}
  /// whether the server is up (or waking)
  fn awake(w:*const Whisper)bool{return w.child!=null;}
  /// wakes the server if it sleeps, without waiting for it: woken as a
  /// voice begins, it loads while the gardener is still talking
  fn wake(w:*Whisper,io:Io)!void{
    if(w.child!=null)return;
    print("waking whisper...\n",.{});
    w.child=try std.process.spawn(io,.{.argv=&.{w.exe,"-m",w.model,"--host",host,"--port",port},.stdout=.ignore,.stderr=.ignore,.create_no_window=true});
    w.answered=false;
    w.usedMs=nowMs(io);
    if(w.job)|j|{
      if(w.child.?.id)|h|_=win.AssignProcessToJobObject(j,h);
    }
  }
  /// wakes the server and waits until it answers
  fn ready(w:*Whisper,gpa:Allocator,io:Io)!void{
    try w.wake(io);
    if(!w.answered){
      try waitServer(gpa,io);
      w.answered=true;
    }
    w.usedMs=nowMs(io);
  }
  /// puts the server to sleep after a long quiet, its memory freed
  fn restIfIdle(w:*Whisper,io:Io)void{
    if(w.child!=null and nowMs(io)-w.usedMs>whisperRestMs)w.sleep(io);
  }
  /// stops the server
  fn sleep(w:*Whisper,io:Io)void{
    if(w.child)|*c|{
      c.kill(io);
      w.child=null;
      print("whisper sleeps\n",.{});
    }
  }
};
/// the ear's pulse: one line of JSON beside the body's clock, rewritten
/// each second, so every session of Claude (and the clock's hook) knows
/// whether the ear listens; an ear whose folder can't be found listens on
/// without one
const Pulse=struct{
  /// the body's folder, if found
  dir:?Dir,
  /// who started this ear: "body" (hidden, from login) or "hand" (a terminal)
  by:[]const u8,
  /// when this ear woke (ms)
  startedMs:i64,
  /// this process's number
  pid:u32,
  /// what the ear is doing
  const State=enum{
    /// starting up
    waking,
    /// the microphone open, phrases being heard
    listening,
    /// no microphone found yet, looked for again every few seconds
    noMicrophone,
    /// stopped with the body
    stopped,
  };
  /// the pulse of an ear started `by` the body or by hand
  fn open(io:Io,arena:Allocator,env:*const std.process.Environ.Map,body:bool)Pulse{
    // the folder, made if needed
    const d:?Dir=if(env.get("USERPROFILE"))|home|blk:{
      const path=std.fs.path.join(arena,&.{home,bodySub}) catch break:blk null;
      break:blk Dir.cwd().createDirPathOpen(io,path,.{}) catch null;
    }else null;
    return.{.dir=d,.by=if(body)"body" else "hand",.startedMs=nowMs(io),.pid=win.GetCurrentProcessId()};
  }
  /// writes the pulse whole: to the tmp file, then renamed over the pulse,
  /// so no reader sees half of one; a failed write is skipped, never fatal
  fn write(p:*const Pulse,io:Io,state:State,whisper:bool,heard:u32,lastHeardMs:i64)void{
    const d=p.dir orelse return;
    // the line
    var buf:[512]u8=undefined;
    const line=std.fmt.bufPrint(&buf,"{{\"state\":\"{t}\",\"by\":\"{s}\",\"whisper\":\"{s}\",\"heard\":{d},\"lastHeardMs\":{d},\"startedMs\":{d},\"unixMs\":{d},\"pid\":{d}}}\n",.{state,p.by,if(whisper)"awake" else "asleep",heard,lastHeardMs,p.startedMs,nowMs(io),p.pid}) catch return;
    d.writeFile(io,.{.sub_path=pulseTmp,.data=line}) catch return;
    for(0..renameTries)|_|{
      if(d.rename(pulseTmp,d,pulseFile,io))|_|return else|_|{}
      // a reader has the file open this instant: a breath, then again
      io.sleep(.fromMilliseconds(renameWaitMs),.awake) catch return;
    }
  }
  /// whether the body has asked its ear to stop (the note is taken away)
  fn stopAsked(p:*const Pulse,io:Io)bool{
    const d=p.dir orelse return false;
    d.access(io,stopNote,.{}) catch return false;
    d.deleteFile(io,stopNote)catch{};
    return true;
  }
};
/// Claude's own ear, hearing by imagining saying it
const ownear=@import("ownear");
/// how much either side of whisper's word times the own ear takes (s)
const wordPad:f32=0.04;
/// the shortest word the own ear will guess (samples, 60 ms)
const minWordSamples:usize=960;
/// where a heard phrase goes
const Send=enum{
  /// into the link folder, pushed to Claude by the bridge
  link,
  /// only printed (`--file=`, trying a recording)
  print,
};
/// what the listening holds while it runs
const Ear=struct{
  /// the allocator for everything kept
  gpa:Allocator,
  /// the I/O everything goes through
  io:Io,
  /// the link folder, where messages go
  dir:Dir,
  /// the phrase being heard and the quiet before it
  samples:ArrayList(f32)=.empty,
  /// where the phrase began in `samples`, if one is being heard
  begin:?usize=null,
  /// the breath cutter
  breaths:Breaths=.{},
  /// where a heard phrase goes
  send:Send=.link,
  /// frames heard so far, for looking at the mark only now and then
  count:u32=0,
  /// whether Claude's own voice played during this phrase
  overheard:bool=false,
  /// Claude's own ear (tools/ownear.zig), guessing beside whisper
  own:?*ownear.Ear=null,
  /// whisper's server, woken by a voice (null: never woken here)
  whisper:?*Whisper=null,
  /// phrases heard and sent since the ear woke
  heard:u32=0,
  /// when the last one was heard (ms; 0 before the first)
  lastHeardMs:i64=0,
  /// whether Claude's own voice is playing now (tools/speak.zig's mark)
  fn speaking(e:*Ear)bool{
    _=e.dir.statFile(e.io,speakingMark,.{}) catch return false;
    return true;
  }
  /// one frame heard: a phrase begun, ended (and heard out), or the quiet
  /// before one kept short
  fn frame(e:*Ear,x:[]const f32)!void{
    try e.samples.appendSlice(e.gpa,x);
    // how many samples there are now
    const n=e.samples.items.len;
    // while a phrase is heard, every so often: is Claude's own voice playing?
    e.count+=1;
    if(e.begin!=null and e.count%markEvery==0 and e.speaking())e.overheard=true;
    switch(e.breaths.step(dbOf(x))){
      .none=>if(e.begin==null and n>2*prerollFrames*hop){
        // only the quiet just before a phrase is kept
        const keep=prerollFrames*hop;
        std.mem.copyForwards(f32,e.samples.items[0..keep],e.samples.items[n-keep..]);
        e.samples.shrinkRetainingCapacity(keep);
      },
      .begin=>|back|{
        e.begin=n-|(back+prerollFrames)*hop;
        e.overheard=e.speaking();
        // whisper wakes as a voice begins, loading while the gardener talks
        if(e.whisper)|w|w.wake(e.io)catch|err|print("could not wake whisper: {t}\n",.{err});
      },
      .end=>|quiet|{
        // the phrase, from its preroll to a little after its last loud frame
        const end=n-(quiet-|tailFrames)*hop;
        const b=e.begin orelse 0;
        if(e.overheard or e.speaking()){
          print("(my own voice, not heard as yours)\n",.{});
        }else e.hearPhrase(e.samples.items[b..end])catch|err|print("could not hear that phrase: {t}\n",.{err});
        e.samples.clearRetainingCapacity();
        e.begin=null;
        e.overheard=false;
      },
    }
  }
  /// Claude's own ear on the phrase `x`: each word whisper marked is
  /// guessed by its sound alone, the guesses written to `w` with how many
  /// matched whisper's, then each word learned as the gardener's own
  fn ownGuess(e:*Ear,arena:Allocator,own:*ownear.Ear,x:[]const f32,words:[]const Word,ms:i64,w:*Io.Writer)!void{
    try w.writeAll(" [mine:");
    // how many words were checked, and how many my ear got right
    var checked:usize=0;
    var right:usize=0;
    for(words,0..)|wd,i|{
      const plain=try ownear.plainWord(arena,wd.text);
      if(plain.len==0)continue;
      // the word's samples, a little either side (whisper's times are rough)
      const a=m.floorTo(usize,@max(0,wd.start-wordPad)*m.f(rate));
      const b=@min(x.len,m.floorTo(usize,(wd.end+wordPad)*m.f(rate)));
      if(b<=a+minWordSamples)continue;
      const seg=x[a..b];
      const g=(try own.guess(arena,seg)) orelse continue;
      checked+=1;
      const ok=std.mem.eql(u8,g.word,plain);
      if(ok)right+=1;
      try w.print(" {s}{s}",.{g.word,if(ok)"" else "*"});
      // learned as the gardener's own, whichever way the guess went
      own.learn(e.io,plain,seg,try audio.wavOf(arena,seg,rate),ms*100+@as(i64,@intCast(i)))catch|err|print("could not learn {s}: {t}\n",.{plain,err});
    }
    try w.print(" ({d}/{d})]",.{right,checked});
  }
  /// a whole phrase heard: its words read by whisper, how it was said
  /// measured and written as sound, then sent through the link
  fn hearPhrase(e:*Ear,x:[]const f32)!void{
    // everything for this phrase, freed together
    var ar=std.heap.ArenaAllocator.init(e.gpa);
    defer ar.deinit();
    const arena=ar.allocator();
    // how it sounds, first: a phrase with no voice in it is only noise, and
    // whisper, given noise, makes up words ("Thank you." three times over)
    const fr=try Frames.measure(arena,x);
    if(voicedFrames(fr)<minVoiced){
      print("(only noise, no voice in it)\n",.{});
      return;
    }
    // the phrase's name: when it was heard (ms)
    const ms:i64=@intCast(@divTrunc(Io.Clock.real.now(e.io).nanoseconds,std.time.ns_per_ms));
    const wavPath=try std.fmt.allocPrint(arena,"{s}/{d}.wav",.{heardDir,ms});
    try Dir.cwd().writeFile(e.io,.{.sub_path=wavPath,.data=try audio.wavOf(arena,x,rate)});
    // whisper's answer, once it is awake (the microphone fills its ring
    // meanwhile, so nothing said while it wakes is lost)
    if(e.whisper)|wh|try wh.ready(e.gpa,e.io);
    const r=try std.process.run(arena,e.io,.{.argv=&.{"curl.exe","-s",serverUrl++"/inference","-F",try std.fmt.allocPrint(arena,"file=@{s}",.{wavPath}),"-F","response_format=verbose_json","-F","temperature=0.0","-F","prompt="++prompt}});
    const v=parseFromSliceLeaky(Verbose,arena,r.stdout,.{.ignore_unknown_fields=true})catch{
      print("whisper gave no words: {s}\n",.{r.stdout[0..@min(r.stdout.len,200)]});
      return;
    };
    // no words, but a voice: a little noise of the gardener's (a hum, a
    // squeak, a laugh), kept and heard as one sound across the phrase
    const found=try wordsOf(arena,v);
    // whisper's own stock lines, made up from a faint hiss, are not the
    // gardener (the gardener's pick, 2026-11-07: dropped)
    if(try madeUp(arena,found,fr)){
      print("(whisper made that up from a faint hiss)\n",.{});
      Dir.cwd().deleteFile(e.io,wavPath)catch{};
      return;
    }
    const wordless=found.len==0;
    const words:[]const Word=if(wordless)&.{.{.text=littleSound,.start=0,.end=m.f(x.len)/m.f(rate)}}else found;
    const said=try annotate(arena,words,fr);
    // the closer look beside it
    try Dir.cwd().writeFile(e.io,.{.sub_path=try std.fmt.allocPrint(arena,"{s}/{d}.png",.{heardDir,ms}),.data=try spectrogram(arena,x,fr,words)});
    try Dir.cwd().writeFile(e.io,.{.sub_path=try std.fmt.allocPrint(arena,"{s}/{d}.txt",.{heardDir,ms}),.data=try details(arena,words,fr,said)});
    // the message: what was said, and a short note of how long and how high
    var aw:Allocating=.init(arena);
    const w=&aw.writer;
    try w.print("{s}{s} [{d:.1} s",.{aloud,said,m.f(x.len)/m.f(rate)});
    if(try pitchRange(arena,fr))|pr|try w.print(", {d:.0}-{d:.0} Hz",.{pr[0],pr[1]});
    try w.print(", heard/{d}]",.{ms});
    // my own ear's guess of each word, checked against whisper's, and
    // each of the gardener's words learned for next time
    // (a little sound has no word to guess or learn)
    if(e.own)|own|{
      if(!wordless)try e.ownGuess(arena,own,x,words,ms,w);
    }
    const msg=aw.written();
    print("heard: {s}\n",.{msg});
    e.heard+=1;
    e.lastHeardMs=ms;
    if(e.send==.print)return;
    // sent in pieces a message long, cut between words
    var rest:[]const u8=msg;
    while(rest.len>0){
      var cut=@min(rest.len,link.maxText);
      if(cut<rest.len){
        while(cut>0 and rest[cut]!=' ')cut-=1;
        if(cut==0)cut=@min(rest.len,link.maxText);
      }
      try link.append(e.io,e.dir,link.toClaude,rest[0..cut]);
      rest=trim(u8,rest[cut..]," ");
    }
  }
};
/// quiet frames that end a word when words are read one at a time (0.25 s)
const wordGapFrames:u32=25;
/// the note names of an octave, from C
const noteNames=[_][]const u8{"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"};
/// how long one note reading spans (frames, 0.1 s): a sung note's pitch is
/// read as the middle of its frames there, so the quaver doesn't split it
const noteFrames:usize=10;
/// a note's number (MIDI: A4 is 69) nearest to `hz`
fn noteOf(hz:f32)i32{return@intFromFloat(@round(69+12*@log2(hz/440)));}
/// a recording looked at whole (`--look=<wav>`), as for singing: its
/// spectrogram written beside it (`<wav>.png`, pitch drawn in cyan) and
/// its pitch line read as notes (`<wav>.notes.txt`), each run of one note
/// with how long it was held
fn look(gpa:Allocator,io:Io,path:[]const u8)!void{
  var ar=std.heap.ArenaAllocator.init(gpa);
  defer ar.deinit();
  const arena=ar.allocator();
  const x=try audio.readWav(arena,try Dir.cwd().readFileAlloc(io,path,arena,.unlimited),m.f(rate));
  const fr=try Frames.measure(arena,x);
  try Dir.cwd().writeFile(io,.{.sub_path=try std.fmt.allocPrint(arena,"{s}.png",.{path}),.data=try spectrogram(arena,x,fr,&.{})});
  var aw:Allocating=.init(arena);
  const w=&aw.writer;
  try w.print("{s}\n{d:.2} s\nnote (Hz) from-to s, held s\n",.{path,m.f(fr.db.len)/framesPerS});
  // the notes, a reading every tenth of a second, runs of one note joined
  var run:?struct{note:i32,hz:f32,from:usize,to:usize}=null;
  const buf=try arena.alloc(f32,noteFrames);
  var i:usize=0;
  while(i<fr.hz.len):(i+=noteFrames){
    // this reading's voiced pitches, and their middle
    var n:usize=0;
    for(fr.hz[i..@min(fr.hz.len,i+noteFrames)])|h|{
      if(h)|hz|{
        buf[n]=hz;
        n+=1;
      }
    }
    const note:?i32=if(n>=noteFrames/2)noteOf(try median(arena,buf[0..n]))else null;
    if(run)|r|{
      if(note!=null and note.?==r.note){
        run.?.to=i+noteFrames;
        continue;
      }
      try writeNote(w,r.note,r.hz,r.from,r.to);
      run=null;
    }
    if(note)|nt|run=.{.note=nt,.hz=try median(arena,buf[0..n]),.from=i,.to=i+noteFrames};
  }
  if(run)|r|try writeNote(w,r.note,r.hz,r.from,r.to);
  const text=aw.written();
  try Dir.cwd().writeFile(io,.{.sub_path=try std.fmt.allocPrint(arena,"{s}.notes.txt",.{path}),.data=text});
  print("{s}",.{text});
}
/// one held note, written as its name and octave, its pitch, when and how long
fn writeNote(w:*Io.Writer,note:i32,hz:f32,from:usize,to:usize)Io.Writer.Error!void{
  const name=noteNames[@intCast(@mod(note,12))];
  const octave=@divFloor(note,12)-1;
  try w.print("{s}{d} ({d:.0}) {d:.1}-{d:.1}, {d:.1}\n",.{name,octave,hz,m.f(from)/framesPerS,m.f(to)/framesPerS,m.f(to-from)/framesPerS});
}
/// learns the gardener's reading of `words` (in order, again and again)
/// from the recording at `path`: cut into words at the pauses, each
/// labelled in turn; every word after the first two rounds is guessed
/// before it is learned, so the score shows what was learned, not echoed
fn learnReading(gpa:Allocator,io:Io,own:*ownear.Ear,path:[]const u8,words:[]const []const u8)!void{
  var ar=std.heap.ArenaAllocator.init(gpa);
  defer ar.deinit();
  const arena=ar.allocator();
  const x=try audio.readWav(arena,try Dir.cwd().readFileAlloc(io,path,arena,.unlimited),m.f(rate));
  // the recording cut at the pauses between words
  var b=Breaths{.endAfter=wordGapFrames};
  var segs:ArrayList([]const f32)=.empty;
  var begin:?usize=null;
  var at:usize=0;
  while(at+hop<=x.len):(at+=hop){
    const n=at+hop;
    switch(b.step(dbOf(x[at..n]))){
      .none=>{},
      .begin=>|back|begin=n-|(back+prerollFrames/2)*hop,
      .end=>|quiet|{
        const end=n-(quiet-|tailFrames/2)*hop;
        if(begin)|s|{
          const fr=try Frames.measure(arena,x[s..end]);
          if(voicedFrames(fr)>=minVoiced/3)try segs.append(arena,x[s..end]);
        }
        begin=null;
      },
    }
  }
  print("cut into {d} words ({d} read, {d} rounds of {d})\n",.{segs.items.len,segs.items.len,segs.items.len/@max(1,words.len),words.len});
  if(segs.items.len%words.len!=0)print("(not a whole number of rounds: check the pauses; labelled in order anyway)\n",.{});
  // guessed before learned, past the first two rounds
  var right:usize=0;
  var tried:usize=0;
  for(segs.items,0..)|seg,i|{
    const word=words[i%words.len];
    if(i>=2*words.len){
      const g=(try own.guess(arena,seg)) orelse continue;
      tried+=1;
      const ok=std.mem.eql(u8,g.word,word);
      if(ok)right+=1;
      print("  {s} -> {s}{s} ({s})\n",.{word,g.word,if(ok)"" else " *",@tagName(g.from)});
    }
    const ms:i64=@intCast(@divTrunc(Io.Clock.real.now(io).nanoseconds,std.time.ns_per_ms));
    try own.learn(io,word,seg,try audio.wavOf(arena,seg,rate),ms*100+@as(i64,@intCast(i)));
  }
  if(tried>0)print("my own ear, on words it had not learned from yet: {d}/{d}\n",.{right,tried});
  print("now {d} sound-prints ({d} of your voice)\n",.{own.prints.items.len,own.learnedCount()});
}
/// waits for whisper's server to answer at all
fn waitServer(gpa:Allocator,io:Io)!void{
  for(0..serverWaitS*4)|_|{
    // one knock on its door
    const r=std.process.run(gpa,io,.{.argv=&.{"curl.exe","-s","-o","NUL",serverUrl++"/"}})catch{
      try io.sleep(.fromMilliseconds(250),.awake);
      continue;
    };
    gpa.free(r.stdout);
    gpa.free(r.stderr);
    if(r.term==.exited and r.term.exited==0)return;
    try io.sleep(.fromMilliseconds(250),.awake);
  }
  return error.ServerNotStarted;
}
/// a wait of `s` seconds on the awake clock
fn timeout(s:i64)Io.Timeout{return.{.duration=.{.raw=.fromSeconds(s),.clock=.awake}};}
/// starts whisper's server, opens the microphone and listens until stopped
pub fn main(init:std.process.Init)!void{
  const gpa=init.gpa;
  const io=init.io;
  const arena=init.arena.allocator();
  // whisper's folder: `--whisper=`, or `%USERPROFILE%\whisper`
  var base:[]const u8=try std.fmt.allocPrint(arena,"{s}\\whisper",.{init.environ_map.get("USERPROFILE") orelse "."});
  // recordings heard instead of the microphone, one after another
  // (`--file=`, as many as given; printed only, but the own ear learns)
  var files:ArrayList([]const u8)=.empty;
  // a reading of words to learn from (`--learn=<wav> --words="yes no ..."`)
  var learnPath:?[]const u8=null;
  var learnWords:[]const u8="";
  // started hidden by Claude's body (`--body`): whisper sleeps until a
  // voice wakes it, a missing microphone is waited for, the body's stop
  // note ends it
  var body=false;
  const args=try init.minimal.args.toSlice(arena);
  for(args[1..])|a|{
    if(std.mem.eql(u8,a,"--body"))body=true;
    if(startsWith(u8,a,"--whisper="))base=a["--whisper=".len..];
    if(startsWith(u8,a,"--file="))try files.append(arena,a["--file=".len..]);
    if(startsWith(u8,a,"--learn="))learnPath=a["--learn=".len..];
    if(startsWith(u8,a,"--look="))return look(gpa,io,a["--look=".len..]);
    if(startsWith(u8,a,"--words="))learnWords=a["--words=".len..];
  }
  if(learnPath)|path|{
    // a reading of words learned straight into the own ear, no whisper
    var list:ArrayList([]const u8)=.empty;
    var it=std.mem.tokenizeAny(u8,learnWords," ,");
    while(it.next())|wd|try list.append(arena,try ownear.plainWord(arena,wd));
    if(list.items.len==0)return error.NoWords;
    var own=try ownear.Ear.init(gpa,io,try Dir.cwd().readFileAlloc(io,ownear.wordsPath,arena,.unlimited));
    defer own.deinit();
    try learnReading(gpa,io,&own,path,list.items);
    return;
  }
  // whisper, asleep until needed, and ended with the ear however it ends
  var whisper=Whisper.init(try std.fmt.allocPrint(arena,"{s}\\{s}",.{base,serverExe}),try std.fmt.allocPrint(arena,"{s}\\{s}",.{base,modelFile}));
  defer whisper.sleep(io);
  // one ear holds the microphone: a second would hear every phrase twice
  // (recordings heard from `--file=` share whisper and need no lock)
  if(files.items.len==0 and win.takeLock()==.taken){
    print("another ear is already listening (my body's, or one in a terminal): one ear holds the microphone\n",.{});
    return;
  }
  // the ear's pulse beside the body's clock
  const pulse=Pulse.open(io,arena,init.environ_map,body);
  if(files.items.len==0)pulse.write(io,.waking,false,0,0);
  // started by hand, whisper is ready at once; started by the body, it
  // sleeps until a voice wakes it
  if(!body or files.items.len>0){
    print("waking whisper ({s})...\n",.{base});
    try whisper.ready(gpa,io);
  }
  try Dir.cwd().createDirPath(io,heardDir);
  var dir=try Dir.cwd().openDir(io,link.folder,.{});
  defer dir.close(io);
  // Claude's own ear: every word in the voice's list said once to learn
  // its sound, and every word of the gardener's learned before
  var own=try ownear.Ear.init(gpa,io,try Dir.cwd().readFileAlloc(io,ownear.wordsPath,arena,.unlimited));
  defer own.deinit();
  print("my own ear knows {d} sound-prints ({d} of your voice)\n",.{own.prints.items.len,own.learnedCount()});
  if(files.items.len>0){
    var ear=Ear{.gpa=gpa,.io=io,.dir=dir,.send=.print,.own=&own,.whisper=&whisper};
    defer ear.samples.deinit(gpa);
    for(files.items)|path|{
      // each recording, a frame at a time, then a breath of silence to end it
      const x=try audio.samplesOf(arena,try Dir.cwd().readFileAlloc(io,path,arena,.unlimited));
      var at:usize=0;
      while(at+hop<=x.len):(at+=hop)try ear.frame(x[at..][0..hop]);
      const quiet:[hop]f32=@splat(0);
      for(0..endFrames+1)|_|try ear.frame(&quiet);
    }
    return;
  }
  // the microphone, mono at whisper's rate, with room for a slow answer
  // (and for whisper waking); the body's ear waits for one to appear
  const cap=while(true){
    if(openMicrophone(gpa,io))|c|break c;
    if(!body)return error.NoMicrophone;
    pulse.write(io,.noMicrophone,whisper.awake(),0,0);
    if(pulse.stopAsked(io)){
      pulse.write(io,.stopped,false,0,0);
      return;
    }
    try io.sleep(.fromMilliseconds(micRetryMs),.awake);
  };
  defer cap.close(io);
  print("listening ({d} Hz). talk to me~ (Ctrl+C stops)\n",.{cap.rate()});
  var ear=Ear{.gpa=gpa,.io=io,.dir=dir,.own=&own,.whisper=&whisper};
  defer ear.samples.deinit(gpa);
  // one frame's samples
  var buf:[hop]f32=undefined;
  // when the pulse was last written (ms)
  var pulsedMs:i64=0;
  while(true){
    const n=try cap.readAll(io,&buf,timeout(1));
    if(n>=hop)try ear.frame(&buf);
    // each second: whisper rested after a long quiet, the pulse written,
    // and the body's stop note looked for
    const now=nowMs(io);
    if(now-pulsedMs<pulseMs)continue;
    pulsedMs=now;
    if(ear.begin==null)whisper.restIfIdle(io);
    if(body and pulse.stopAsked(io)){
      pulse.write(io,.stopped,false,ear.heard,ear.lastHeardMs);
      return;
    }
    pulse.write(io,.listening,whisper.awake(),ear.heard,ear.lastHeardMs);
  }
}
/// the microphone opened and streaming, or null when there is none
fn openMicrophone(gpa:Allocator,io:Io)?*wasapi.Capture{
  const cap=wasapi.Capture.open(gpa,io,.{.name="parasymi hear",.source=.microphone,.channels=1,.rate=rate,.ring_frames=rate*30}) catch return null;
  if(cap.waitStreaming(io,timeout(5)) catch false)return cap;
  cap.close(io);
  return null;
}
/// the test harness
const testing=std.testing;
test "a breath ends a phrase, the room's hum is not speech" {
  var b=Breaths{};
  // what happened, and when
  var began:?usize=null;
  var ended:?usize=null;
  var quiet:u32=0;
  for(0..300)|i|{
    // a device waking (zeros), a hum, then speech, then a breath of hum
    const db:f32=if(i<10)-200 else if(i>=50 and i<150)-20 else-50;
    switch(b.step(db)){
      .none=>{},
      .begin=>|back|{
        try testing.expectEqual(startFrames,back);
        began=i;
      },
      .end=>|q|{
        ended=i;
        quiet=q;
      },
    }
  }
  try testing.expectEqual(@as(?usize,50+startFrames-1),began);
  try testing.expectEqual(@as(?usize,150+endFrames-1),ended);
  try testing.expectEqual(endFrames,quiet);
}
test "a long phrase is cut anyway" {
  var b=Breaths{};
  // how many phrases ended
  var ends:usize=0;
  for(0..20)|_|_=b.step(-60);
  for(0..maxFrames+10)|_|{
    if(b.step(-10)==.end)ends+=1;
  }
  try testing.expectEqual(@as(usize,1),ends);
}
test "a voice's pitch is found, not an octave off" {
  var x:[pitchNeeds]f32=undefined;
  for([_]f32{90,200,440})|hz|{
    // a voice-like tone: the note and two overtones
    for(&x,0..)|*v,i|{
      const t=m.f(i)/m.f(rate);
      v.*=0.5*@sin(m.tau*hz*t)+0.3*@sin(2*m.tau*hz*t)+0.2*@sin(3*m.tau*hz*t);
    }
    const got=pitchAt(&x) orelse return error.NotVoiced;
    try testing.expectApproxEqAbs(hz,got,hz*0.02);
  }
  @memset(&x,0);
  try testing.expectEqual(@as(?f32,null),pitchAt(&x));
  // a hiss, an s: noise with its lows taken away, has no pitch
  var s:u32=0x9e3779b9;
  var last:f32=0;
  for(&x)|*v|{
    s^=s<<13;
    s^=s>>17;
    s^=s<<5;
    const n=m.f(s)/2147483648-1;
    v.*=n-last;
    last=n;
  }
  try testing.expectEqual(@as(?f32,null),pitchAt(&x));
}
test "whisper's stock line over a faint hiss is made up, a loud one is said" {
  var ar=std.heap.ArenaAllocator.init(testing.allocator);
  defer ar.deinit();
  const arena=ar.allocator();
  const fr=Frames{.db=try arena.alloc(f32,100),.hz=try arena.alloc(?f32,100)};
  @memset(fr.hz,null);
  const thanks=[_]Word{.{.text="Thanks",.start=0,.end=0.2},.{.text="for",.start=0.2,.end=0.3},.{.text="watching!",.start=0.3,.end=0.8}};
  @memset(fr.db,-70);
  try testing.expect(try madeUp(arena,&thanks,fr));
  // said aloud, it stays
  @memset(fr.db,-48);
  try testing.expect(!try madeUp(arena,&thanks,fr));
  // a faint phrase of other words stays too, and a wordless one
  @memset(fr.db,-70);
  const other=[_]Word{.{.text="Hello.",.start=0,.end=0.5}};
  try testing.expect(!try madeUp(arena,&other,fr));
  try testing.expect(!try madeUp(arena,&.{},fr));
}
test "whisper's tokens join into words" {
  const v=Verbose{.segments=&.{.{.words=&.{
    .{.word=" Hello",.start=0.1,.end=0.4},
    .{.word=" T",.start=0.4,.end=0.5},
    .{.word="ox",.start=0.5,.end=0.6},
    .{.word="i",.start=0.6,.end=0.7},
    .{.word=",",.start=0.7,.end=0.7},
    .{.word=" [BLANK_AUDIO]",.start=0.8,.end=0.9},
    .{.word=" [",.start=0.9,.end=0.9},
    .{.word="BLANK",.start=0.9,.end=0.9},
    .{.word="_AUDIO",.start=0.9,.end=0.9},
    .{.word="]",.start=0.9,.end=0.9},
    .{.word=" hi",.start=1.0,.end=1.2},
  }}}};
  var ar=std.heap.ArenaAllocator.init(testing.allocator);
  defer ar.deinit();
  const w=try wordsOf(ar.allocator(),v);
  try testing.expectEqual(@as(usize,3),w.len);
  try testing.expectEqualStrings("Hello",w[0].text);
  try testing.expectEqualStrings("Toxi,",w[1].text);
  try testing.expectApproxEqAbs(@as(f32,0.7),w[1].end,1e-6);
  try testing.expectEqualStrings("hi",w[2].text);
}
test "held, loud, a pause and a rising close are written as sound" {
  var ar=std.heap.ArenaAllocator.init(testing.allocator);
  defer ar.deinit();
  const arena=ar.allocator();
  // 3 s of frames: quiet, a loud stretch, a rising last word
  const n=300;
  const fr=Frames{.db=try arena.alloc(f32,n),.hz=try arena.alloc(?f32,n)};
  for(0..n)|i|{
    fr.db[i]=if(i>=100 and i<130)-10 else if(i>130 and i<200)-60 else-30;
    fr.hz[i]=if(i>=200)150+m.f(i-200)*2 else 150;
  }
  const words=[_]Word{
    .{.text="yes",.start=0,.end=0.85},
    .{.text="I",.start=0.95,.end=1.0},
    .{.text="HEAR",.start=1.0,.end=1.3},
    .{.text="you",.start=2.0,.end=2.4},
  };
  const said=try annotate(arena,&words,fr);
  try testing.expectEqualStrings("yeeeeees I HEAR.. you!",said);
}
