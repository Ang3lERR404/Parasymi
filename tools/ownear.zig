//! Claude's own ear: hearing a word by imagining saying it. Every word in
//! the voice's word list (tools/voice/words.txt) is said once in Claude's
//! own voice (tools/speak.zig) and its sound-print kept: a short row of
//! frames, each the shape of the sound's spectrum then (log mel bands
//! folded into cepstra, the loudness set aside). A heard word is matched
//! against every sound-print, the two stretched in time to fit each other
//! (dynamic time warping) and its pitch scale slid a little either way so
//! a different throat still matches (vocal tract length); the closest is
//! the guess. And it learns: each word the gardener says is kept as a
//! sound-print of their own voice (in `link/ear/`, outside git), so the
//! ear leans less on its own voice and more on theirs as it goes.
//! whisper still marks where each word starts and ends, and says what it
//! heard, so every guess is checked, a teacher at first.
/// the standard library
const std=@import("std");
/// the engine package: the maths
const engine=@import("engine");
/// Claude's own voice, which says each word to learn its sound
const voice=@import("speak");
/// the tools' shared sound files and spectra
const audio=@import("audio");
/// all the maths: casts, tau, powers
const m=engine.core.math;
/// an allocator
const Allocator=std.mem.Allocator;
/// the I/O interface every call goes through
const Io=std.Io;
/// a directory handle
const Dir=Io.Dir;
/// a growable list
const ArrayList=std.ArrayList;
/// swaps two values in place
const swap=std.mem.swap;
/// splits a text at a byte
const tokenize=std.mem.tokenizeScalar;
/// the text with the given bytes cut from its ends
const trimAll=std.mem.trim;
/// where a byte first is in a text
const indexOfScalar=std.mem.indexOfScalar;
/// whether two texts are the same
const eql=std.mem.eql;
/// the rate everything is heard at (Hz): whisper's, and the ear's
pub const rate:f32=16000;
/// one frame's step (samples, 10 ms)
const hop:usize=160;
/// one frame's window (samples, 25 ms, zero-padded to the transform)
const win:usize=400;
/// the transform's size
const fftN:usize=512;
/// how many mel bands a frame is read in
const bands:usize=24;
/// the lowest and highest band edge (Hz)
const lowHz:f32=100;
/// the highest band edge (Hz)
const highHz:f32=7600;
/// how many cepstra a frame keeps (the first, loudness, left out)
pub const dims:usize=12;
/// the mel scale's size (mels a decade)
const melScale:f32=2595;
/// where the mel scale bends from even to logarithmic (Hz)
const melKnee:f32=700;
/// the least a band's energy or a peak may be, so a logarithm stays finite
const bandFloor:f32=1e-10;
/// quieter than this share of a word's peak is the quiet round it
const quietShare:f32=0.05;
/// the pitch-scale slides tried, so another throat still matches
const warps=[_]f32{0.86,0.93,1,1.07,1.14};
/// a match too far to count, past any real one
const far:f32=1e30;
/// how many sound-prints of the gardener's voice are kept for each word
const keepPerWord:usize=6;
/// where the gardener's sound-prints are kept (as WAVs, a folder a word)
pub const learnedDir="link/ear";
/// the voice's word list, every word the ear first learns by saying it
pub const wordsPath=voice.wordsPath;
/// where a sound-print came from
pub const From=enum{
  /// Claude's own voice, imagining saying it
  voice,
  /// the gardener's voice, learned from hearing it
  heard,
};
/// one word's sound-print
const Print=struct{
  /// the word
  word:[]const u8,
  /// its frames' cepstra, `dims` a frame, row after row
  feats:[]f32,
  /// where it came from
  from:From,
  /// how many frames it has
  fn frames(p:Print)usize{return p.feats.len/dims;}
};
/// a guess: the closest word, how close, and whose sound-print it matched
pub const Guess=struct{
  /// the word guessed
  word:[]const u8,
  /// how far its sound-print was (mean distance a step of the match)
  cost:f32,
  /// whose voice the matched sound-print was
  from:From,
};
/// a frequency on the mel scale, how the ear spaces pitch
fn mel(hz:f32)f32{return melScale*@log10(1+hz/melKnee);}
/// back from the mel scale to Hz
fn hzOf(mels:f32)f32{return melKnee*(m.pow(f32,10,mels/melScale)-1);}
/// the sound-print of `x` (at `rate`), its pitch scale slid by `warp`:
/// each frame's mel bands, logged, folded into cepstra, the whole print's
/// mean taken away (so a louder or brighter room matches a quieter one)
pub fn printOf(arena:Allocator,x:[]const f32,warp:f32)Allocator.Error![]f32{
  const n=if(x.len>win)(x.len-win)/hop+1 else 1;
  const out=try arena.alloc(f32,n*dims);
  // the band edges, in transform bins, slid by the warp
  var edges:[bands+2]f32=undefined;
  for(0..bands+2)|i|{
    const mm=m.lerp(mel(lowHz),mel(highHz),m.ratio(i,bands+1));
    edges[i]=hzOf(mm)*warp*m.f(fftN)/rate;
  }
  var re:[fftN]f32=undefined;
  var im:[fftN]f32=undefined;
  var logs:[bands]f32=undefined;
  for(0..n)|fi|{
    for(0..fftN)|i|{
      const s=fi*hop+i;
      const hann=0.5-0.5*@cos(m.tau*m.f(i)/m.f(win-1));
      re[i]=if(i<win and s<x.len)x[s]*hann else 0;
      im[i]=0;
    }
    audio.fft(&re,&im);
    for(0..bands)|b|{
      // the band's triangle over the bins
      var e:f32=bandFloor;
      const lo=edges[b];
      const mid=edges[b+1];
      const hi=edges[b+2];
      var k=m.floorTo(usize,@max(0,lo));
      while(m.f(k)<hi and k<fftN/2):(k+=1){
        const fk=m.f(k);
        const w=if(fk<mid)(fk-lo)/@max(1e-6,mid-lo)else(hi-fk)/@max(1e-6,hi-mid);
        if(w>0)e+=w*(re[k]*re[k]+im[k]*im[k]);
      }
      logs[b]=@log(e);
    }
    // folded into cepstra (a cosine transform), the first left out
    for(0..dims)|c|{
      var s:f32=0;
      for(0..bands)|b|s+=logs[b]*@cos(m.pi*m.f(c+1)*(m.f(b)+0.5)/m.f(bands));
      out[fi*dims+c]=s;
    }
  }
  // the print's own mean taken away
  for(0..dims)|c|{
    var s:f32=0;
    for(0..n)|fi|s+=out[fi*dims+c];
    const mean=s/m.f(n);
    for(0..n)|fi|out[fi*dims+c]-=mean;
  }
  return out;
}
/// how far apart two frames are (their cepstra's distance)
fn gap(a:[]const f32,b:[]const f32)f32{
  var s:f32=0;
  for(0..dims)|i|{
    const d=a[i]-b[i];
    s+=d*d;
  }
  return @sqrt(s);
}
/// how far two prints are, stretched in time to fit each other at best
/// (dynamic time warping, steps of one frame either side), a step's mean;
/// `row` is scratch at least two rows of `b`'s frames long
fn warpCost(a:[]const f32,b:[]const f32,row:[]f32)f32{
  const na=a.len/dims;
  const nb=b.len/dims;
  // a match stretched beyond twice either way is no match
  if(na>nb*2+2 or nb>na*2+2)return far;
  const big=far;
  var prev=row[0..nb];
  var cur=row[nb..2*nb];
  for(0..na)|i|{
    for(0..nb)|j|{
      const d=gap(a[i*dims..][0..dims],b[j*dims..][0..dims]);
      // the cheapest way here: along, across, or both
      var best=big;
      if(i==0 and j==0)best=0;
      if(i>0)best=@min(best,prev[j]);
      if(j>0)best=@min(best,cur[j-1]);
      if(i>0 and j>0)best=@min(best,prev[j-1]);
      cur[j]=best+d;
    }
    swap([]f32,&prev,&cur);
  }
  return prev[nb-1]/m.f(na+nb);
}
/// the ear: every word's sound-prints, Claude's voice's and the gardener's
pub const Ear=struct{
  /// everything it keeps lives here
  arena:std.heap.ArenaAllocator,
  /// every sound-print
  prints:ArrayList(Print)=.empty,
  /// learns every word in the word list `words` by saying it in Claude's
  /// own voice, and every sound-print of the gardener's already kept
  pub fn init(gpa:Allocator,io:Io,words:[]const u8)!Ear{
    var e=Ear{.arena=.init(gpa)};
    errdefer e.arena.deinit();
    const a=e.arena.allocator();
    var lines=tokenize(u8,words,'\n');
    while(lines.next())|raw|{
      const line=trimAll(u8,raw," \r\t");
      if(line.len==0 or line[0]=='#')continue;
      const sp=indexOfScalar(u8,line,' ') orelse continue;
      const word=try a.dupe(u8,line[0..sp]);
      // said in Claude's voice, at the ear's rate
      var scratch=std.heap.ArenaAllocator.init(gpa);
      defer scratch.deinit();
      const s=scratch.allocator();
      const v=voice.Voice{};
      const said=try voice.speak(s,try voice.plan(s,try voice.read(s,trimAll(u8,line[sp..]," ")),v),v);
      const x=try audio.resample(s,said,voice.rate,rate);
      try e.prints.append(a,.{.word=word,.feats=try printOf(a,trimmed(x),1),.from=.voice});
    }
    try e.loadLearned(io);
    return e;
  }
  /// frees everything
  pub fn deinit(e:*Ear)void{e.arena.deinit();}
  /// how many sound-prints of the gardener's voice it has
  pub fn learnedCount(e:*const Ear)usize{
    var n:usize=0;
    for(e.prints.items)|p|{
      if(p.from==.heard)n+=1;
    }
    return n;
  }
  /// the gardener's sound-prints kept before (`learnedDir/<word>/<n>.wav`)
  fn loadLearned(e:*Ear,io:Io)!void{
    const a=e.arena.allocator();
    var dir=Dir.cwd().openDir(io,learnedDir,.{.iterate=true}) catch return;
    defer dir.close(io);
    var it=dir.iterate();
    while(try it.next(io))|entry|{
      if(entry.kind!=.directory)continue;
      var sub=try dir.openDir(io,entry.name,.{.iterate=true});
      defer sub.close(io);
      var files=sub.iterate();
      while(try files.next(io))|f|{
        if(f.kind!=.file)continue;
        const bytes=try sub.readFileAlloc(io,f.name,a,.unlimited);
        try e.prints.append(a,.{.word=try a.dupe(u8,entry.name),.feats=try printOf(a,try audio.samplesOf(a,bytes),1),.from=.heard});
      }
    }
  }
  /// the closest word to `x` (a heard word, at `rate`), or none if there
  /// is nothing to match against
  pub fn guess(e:*const Ear,scratch:Allocator,x:[]const f32)!?Guess{
    if(e.prints.items.len==0)return null;
    var best:?Guess=null;
    // the heard word, once for each pitch-scale slide
    for(warps)|w|{
      const feats=try printOf(scratch,trimmed(x),w);
      for(e.prints.items)|p|{
        const row=try scratch.alloc(f32,2*p.frames());
        const c=warpCost(feats,p.feats,row);
        if(best==null or c<best.?.cost)best=.{.word=p.word,.cost=c,.from=p.from};
      }
    }
    return best;
  }
  /// learns `x` as the gardener's own sound-print of `word`, kept on disk
  /// as a WAV too; the oldest is let go past `keepPerWord`
  pub fn learn(e:*Ear,io:Io,word:[]const u8,x:[]const f32,wav:[]const u8,ms:i64)!void{
    const a=e.arena.allocator();
    // how many of this word are kept already
    var n:usize=0;
    for(e.prints.items)|p|{
      if(p.from==.heard and eql(u8,p.word,word))n+=1;
    }
    if(n>=keepPerWord){
      // the oldest let go, in memory
      for(e.prints.items,0..)|p,i|{
        if(p.from==.heard and eql(u8,p.word,word)){
          _=e.prints.orderedRemove(i);
          break;
        }
      }
    }
    try e.prints.append(a,.{.word=try a.dupe(u8,word),.feats=try printOf(a,trimmed(x),1),.from=.heard});
    var pb:[256]u8=undefined;
    const folder=try std.fmt.bufPrint(&pb,"{s}/{s}",.{learnedDir,word});
    try Dir.cwd().createDirPath(io,folder);
    var fb:[256]u8=undefined;
    try Dir.cwd().writeFile(io,.{.sub_path=try std.fmt.bufPrint(&fb,"{s}/{d}.wav",.{folder,ms}),.data=wav});
  }
};
/// `x` without the quiet at its ends (below a twentieth of its peak)
fn trimmed(x:[]const f32)[]const f32{
  var top:f32=bandFloor;
  for(x)|v|top=@max(top,@abs(v));
  const floor=top*quietShare;
  var a:usize=0;
  while(a<x.len and @abs(x[a])<floor)a+=1;
  var b=x.len;
  while(b>a and @abs(x[b-1])<floor)b-=1;
  return if(b-a>=win)x[a..b]else x;
}
/// a word as whisper wrote it, made a word-list word: small letters, its
/// punctuation gone (apostrophes kept)
pub fn plainWord(arena:Allocator,w:[]const u8)Allocator.Error![]u8{
  var out:ArrayList(u8)=.empty;
  for(w)|c|{
    if(std.ascii.isAlphanumeric(c) or c=='\'')try out.append(arena,std.ascii.toLower(c));
  }
  return out.items;
}
/// the test harness
const testing=std.testing;
test "a print matches itself stretched better than another word" {
  var ar=std.heap.ArenaAllocator.init(testing.allocator);
  defer ar.deinit();
  const a=ar.allocator();
  const v=voice.Voice{};
  // three words in Claude's own voice; one said again slower
  const yes=try audio.resample(a,try voice.speak(a,try voice.plan(a,try voice.read(a,"Y EH1 S"),v),v),voice.rate,rate);
  const no=try audio.resample(a,try voice.speak(a,try voice.plan(a,try voice.read(a,"N OW1"),v),v),voice.rate,rate);
  const slow=voice.Voice{.pace=0.75};
  const yesSlow=try audio.resample(a,try voice.speak(a,try voice.plan(a,try voice.read(a,"Y EH1 S"),slow),slow),voice.rate,rate);
  const pYes=try printOf(a,trimmed(yes),1);
  const pNo=try printOf(a,trimmed(no),1);
  const pSlow=try printOf(a,trimmed(yesSlow),1);
  const row=try a.alloc(f32,4096);
  try testing.expect(warpCost(pSlow,pYes,row)<warpCost(pSlow,pNo,row));
}
test "whisper's words become word-list words" {
  var ar=std.heap.ArenaAllocator.init(testing.allocator);
  defer ar.deinit();
  try testing.expectEqualStrings("that's",try plainWord(ar.allocator(),"That's,"));
}
