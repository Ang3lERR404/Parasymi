//! Sounding out a word never said before, the way a child reads one: by
//! what its letters have sounded like in the words already known. Nothing
//! is written in by hand (the gardener, 2026-11-08: "you find them
//! yourself, so that way you can keep learning"): the rules are found in
//! Claude's own word list (tools/voice/words.txt), each word's letters
//! lined up with its sounds, and every word added to the list teaches
//! more. Used by tools/speak.zig for any word not in the list.
const std=@import("std");
const Allocator=std.mem.Allocator;
const ArrayList=std.ArrayList;
const Map=std.StringHashMapUnmanaged;
const tokenize=std.mem.tokenizeScalar;
const trimAll=std.mem.trim;
const indexOfScalar=std.mem.indexOfScalar;
const print=std.debug.print;

/// one word of the list: its letters and its sounds (ARPAbet, a sound a token)
const Entry=struct{letters:[]const u8,sounds:[]const []const u8};
/// the most sounds one letter may make ("x" makes K S)
const maxPer=2;
/// the rounds of lining letters up with sounds, each from the last's counts
const rounds=8;
/// the edge of a word, as a letter, so "the start" and "the end" are context
const edge='#';
/// how far past the word the edges reach (the widest window's side)
const pad=2;
/// the windows a letter is read in, widest first: letters before, letters
/// after. A letter is read by the widest window around it ever seen; a
/// narrower one when that is new (the "e" at a word's end changes the
/// vowel two back, so the right side reaches furthest)
const windows=[_][2]u8{.{2,2},.{1,2},.{2,1},.{1,1},.{0,2},.{0,1},.{1,0},.{0,0}};

/// what was found in the word list: for each window of letters around a
/// letter, how often each run of sounds came of it
pub const Reader=struct{
  seen:Map(Map(u32))=.empty,
};

/// the word list's lines as entries (notes and blank lines skipped; a word
/// is letters and `'`)
fn entriesOf(arena:Allocator,words:[]const u8)Allocator.Error![]Entry{
  var out:ArrayList(Entry)=.empty;
  var lines=tokenize(u8,words,'\n');
  while(lines.next())|raw|{
    const line=trimAll(u8,raw," \r\t");
    if(line.len==0 or line[0]=='#')continue;
    const gap=indexOfScalar(u8,line,' ') orelse continue;
    const word=line[0..gap];
    var ok=true;
    for(word)|c|{
      if(!std.ascii.isLower(c) and c!='\'')ok=false;
    }
    if(!ok)continue;
    var sounds:ArrayList([]const u8)=.empty;
    var it=tokenize(u8,line[gap..],' ');
    while(it.next())|s|try sounds.append(arena,s);
    if(sounds.items.len==0)continue;
    try out.append(arena,.{.letters=word,.sounds=sounds.items});
  }
  return out.items;
}

/// how often each letter made each run of sounds ("" none, "K S" two),
/// as the lining up stands
const Counts=struct{
  by:[256]Map(f32)=@splat(.empty),
  total:[256]f32=@splat(0),
  fn add(c:*Counts,arena:Allocator,letter:u8,run:[]const u8,n:f32)Allocator.Error!void{
    const g=try c.by[letter].getOrPut(arena,run);
    if(!g.found_existing)g.value_ptr.*=0;
    g.value_ptr.*+=n;
    c.total[letter]+=n;
  }
  /// how likely, by the counts, `letter` makes `run` (as a log; a run never
  /// seen keeps a little chance, a run of two a little less)
  fn odds(c:*const Counts,letter:u8,run:[]const u8,k:usize)f32{
    const n=c.by[letter].get(run) orelse 0;
    const p=(n+0.05)/(c.total[letter]+1);
    return @log(p)-@as(f32,if(k==maxPer)1 else 0);
  }
};

/// the sounds `s[a..b]` as one run, spaced
fn runOf(arena:Allocator,s:[]const []const u8)Allocator.Error![]const u8{
  return std.mem.join(arena," ",s);
}

/// a first guess at the lining up, before any counts: each letter near its
/// share of the way through the word with the sound at the same share
fn firstGuess(arena:Allocator,c:*Counts,es:[]const Entry)Allocator.Error!void{
  for(es)|e|{
    const n:f32=@floatFromInt(e.letters.len);
    const m:f32=@floatFromInt(e.sounds.len);
    for(e.letters,0..)|l,i|{
      const at=(@as(f32,@floatFromInt(i))+0.5)*m/n;
      const j:usize=@min(e.sounds.len-1,@as(usize,@intFromFloat(at)));
      try c.add(arena,l,e.sounds[j],1);
      if(j>0)try c.add(arena,l,e.sounds[j-1],0.4);
      if(j+1<e.sounds.len)try c.add(arena,l,e.sounds[j+1],0.4);
      if(n>m)try c.add(arena,l,"",(n-m)/n);
    }
  }
}

/// the likeliest lining up of `e`'s letters with its sounds by the counts:
/// how many sounds each letter makes (null: it can't be lined up)
fn lineUp(arena:Allocator,c:*const Counts,e:Entry)Allocator.Error!?[]u8{
  const n=e.letters.len;
  const m=e.sounds.len;
  const w=m+1;
  const best=try arena.alloc(f32,(n+1)*w);
  const took=try arena.alloc(u8,(n+1)*w);
  @memset(best,-std.math.inf(f32));
  best[0]=0;
  for(0..n)|i|for(0..w)|j|{
    const here=best[i*w+j];
    if(here==-std.math.inf(f32))continue;
    for(0..maxPer+1)|k|{
      if(j+k>m)break;
      const run=try runOf(arena,e.sounds[j..j+k]);
      const s=here+c.odds(e.letters[i],run,k);
      if(s>best[(i+1)*w+j+k]){
        best[(i+1)*w+j+k]=s;
        took[(i+1)*w+j+k]=@intCast(k);
      }
    }
  };
  if(best[n*w+m]==-std.math.inf(f32))return null;
  const per=try arena.alloc(u8,n);
  var j=m;
  var i=n;
  while(i>0):(i-=1){
    per[i-1]=took[i*w+j];
    j-=per[i-1];
  }
  return per;
}

/// `letters` with the edges on, so a window can reach past the word
fn padded(arena:Allocator,letters:[]const u8)Allocator.Error![]u8{
  const p=try arena.alloc(u8,letters.len+2*pad);
  @memset(p,edge);
  @memcpy(p[pad..][0..letters.len],letters);
  return p;
}

/// the key of the window `win` around letter `i` of the padded word `p`
fn keyOf(arena:Allocator,p:[]const u8,i:usize,win:[2]u8)Allocator.Error![]const u8{
  const at=i+pad;
  return std.fmt.allocPrint(arena,"{d}{d}{s}",.{win[0],win[1],p[at-win[0]..at+win[1]+1]});
}

/// what the word list `words` teaches about sounding out: its words lined
/// up letter by letter with their sounds (`rounds` times, each from the
/// last's counts), then every window around every letter counted
pub fn learn(arena:Allocator,words:[]const u8)Allocator.Error!Reader{
  return learnFrom(arena,try entriesOf(arena,words));
}
fn learnFrom(arena:Allocator,es:[]const Entry)Allocator.Error!Reader{
  var c:Counts=.{};
  try firstGuess(arena,&c,es);
  // the lining up of each word, kept from the last round
  const lined=try arena.alloc(?[]u8,es.len);
  for(0..rounds)|_|{
    var next:Counts=.{};
    for(es,0..)|e,wi|{
      lined[wi]=try lineUp(arena,&c,e);
      const per=lined[wi] orelse continue;
      var j:usize=0;
      for(e.letters,per)|l,k|{
        try next.add(arena,l,try runOf(arena,e.sounds[j..j+k]),1);
        j+=k;
      }
    }
    c=next;
  }
  var r:Reader=.{};
  for(es,lined)|e,maybe|{
    const per=maybe orelse continue;
    const p=try padded(arena,e.letters);
    var j:usize=0;
    for(per,0..)|k,i|{
      const run=try runOf(arena,e.sounds[j..j+k]);
      j+=k;
      for(windows)|win|{
        const g=try r.seen.getOrPut(arena,try keyOf(arena,p,i,win));
        if(!g.found_existing)g.value_ptr.*=.empty;
        const h=try g.value_ptr.getOrPut(arena,run);
        if(!h.found_existing)h.value_ptr.*=0;
        h.value_ptr.*+=1;
      }
    }
  }
  return r;
}

/// `word` (small letters and `'`) sounded out by what `r` learned: each
/// letter read by the widest window around it ever seen, as the sounds it
/// most often made there; null if a letter was never seen at all
pub fn soundOut(arena:Allocator,r:*const Reader,word:[]const u8)Allocator.Error!?[]const u8{
  const p=try padded(arena,word);
  var runs:ArrayList([]const u8)=.empty;
  for(0..word.len)|i|{
    const counts=for(windows)|win|{
      if(r.seen.getPtr(try keyOf(arena,p,i,win)))|cs|break cs;
    }else return null;
    const bestRun=bestOf(counts,false);
    if(bestRun.len>0)try runs.append(arena,bestRun);
  }
  // a word with no vowel sound can't be said: its letters that most often
  // make a vowel anywhere (by the list, a sound with a stress digit) are
  // read as that, as a child sounds out a letter by itself
  if(!hasVowel(runs.items)){
    runs.clearRetainingCapacity();
    for(0..word.len)|i|{
      const counts=for(windows)|win|{
        if(r.seen.getPtr(try keyOf(arena,p,i,win)))|cs|break cs;
      }else return null;
      var run=bestOf(counts,false);
      const alone=r.seen.getPtr(try keyOf(arena,p,i,.{0,0})).?;
      if(run.len==0 and voweled(alone))run=bestOf(alone,true);
      if(run.len>0)try runs.append(arena,run);
    }
  }
  return try std.mem.join(arena," ",runs.items);
}
/// whether a sound is a vowel: ARPAbet marks every vowel's stress with a digit
fn isVowel(s:[]const u8)bool{return s.len>0 and std.ascii.isDigit(s[s.len-1]);}
/// whether any of `runs` holds a vowel sound
fn hasVowel(runs:[]const []const u8)bool{
  for(runs)|run|{
    var it=tokenize(u8,run,' ');
    while(it.next())|s|if(isVowel(s))return true;
  }
  return false;
}
/// whether a letter, by all it made (`counts`), is mostly a vowel: more
/// often a run with a vowel in it than one without (silence not counted)
fn voweled(counts:*const Map(u32))bool{
  var v:u32=0;
  var c:u32=0;
  var it=counts.iterator();
  while(it.next())|kv|{
    if(kv.key_ptr.len==0)continue;
    if(hasVowel(&.{kv.key_ptr.*}))v+=kv.value_ptr.* else c+=kv.value_ptr.*;
  }
  return v>c;
}
/// the run most often made in `counts` (ties to the first in spelling
/// order); with `vowel`, only runs holding a vowel count
fn bestOf(counts:*const Map(u32),vowel:bool)[]const u8{
  var bestRun:[]const u8="";
  var bestN:u32=0;
  var it=counts.iterator();
  while(it.next())|kv|{
    if(vowel and !hasVowel(&.{kv.key_ptr.*}))continue;
    const n=kv.value_ptr.*;
    if(n>bestN or (n==bestN and std.mem.order(u8,kv.key_ptr.*,bestRun)==.lt)){
      bestN=n;
      bestRun=kv.key_ptr.*;
    }
  }
  return bestRun;
}

const testing=std.testing;
test "letters are lined up with their sounds and read back" {
  var ar=std.heap.ArenaAllocator.init(testing.allocator);
  defer ar.deinit();
  const a=ar.allocator();
  const r=try learn(a,
    \\cat K AE1 T
    \\hat HH AE1 T
    \\cap K AE1 P
    \\tap T AE1 P
    \\box B AA1 K S
    \\pot P AA1 T
  );
  try testing.expectEqualStrings("HH AE1 P",(try soundOut(a,&r,"hap")).?);
  try testing.expectEqualStrings("T AA1 K S",(try soundOut(a,&r,"tox")).?);
  // a letter never seen can't be sounded out
  try testing.expect(try soundOut(a,&r,"zap")==null);
}
test "how well the words list reads a word it never saw" {
  var ar=std.heap.ArenaAllocator.init(testing.allocator);
  defer ar.deinit();
  const a=ar.allocator();
  const es=try entriesOf(a,@embedFile("voice/words.txt"));
  // each word left out in turn, learned from the rest, then sounded out
  var right:usize=0;
  var tried:usize=0;
  var sounds:usize=0;
  var soundsRight:usize=0;
  for(es,0..)|e,i|{
    var w=std.heap.ArenaAllocator.init(testing.allocator);
    defer w.deinit();
    const wa=w.allocator();
    const rest=try std.mem.concat(wa,Entry,&.{es[0..i],es[i+1..]});
    const r=try learnFrom(wa,rest);
    tried+=1;
    const want=try runOf(wa,e.sounds);
    const got=(try soundOut(wa,&r,e.letters)) orelse "";
    if(std.mem.eql(u8,want,got))right+=1 else print("  {s}: wanted {s}, read {s}\n",.{e.letters,want,got});
    // sounds right, place by place (a rough measure)
    var gi=tokenize(u8,got,' ');
    for(e.sounds)|s|{
      sounds+=1;
      if(gi.next())|g|{if(std.mem.eql(u8,g,s))soundsRight+=1;}
    }
  }
  print("read {d} of {d} unseen words whole; {d} of {d} sounds in place\n",.{right,tried,soundsRight,sounds});
}
