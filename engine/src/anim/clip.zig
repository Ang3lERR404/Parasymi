//! keyframed animation, the generic half: a clip is a set of named
//! channels, each a run of keys (time, value) eased between, each key's
//! ease shaping the way on to the next (smooth unless said), and the text
//! it is kept in. `Channels(T)` reads and writes every f32 of a plain
//! struct (nested structs, arrays, vectors) as a channel of its own, named
//! by its path (`arms.0.root.x`), so a whole pose or look can be keyed.
//! A clip also holds marks: named moments along it (a footfall, a blink).
/// the standard library
const std=@import("std");
/// the allocator type clips own their names and keys through
const Allocator=std.mem.Allocator;
/// the stream writer a clip's text is written into
const Writer=std.Io.Writer;
/// walks the words of a line, skipping repeated spaces
const tokenizeScalar=std.mem.tokenizeScalar;
/// walks the pieces between each separator byte
const splitScalar=std.mem.splitScalar;
/// strips the given bytes from both ends
const trim=std.mem.trim;
/// whether two runs of bytes are the same
const eql=std.mem.eql;
/// reads a float from its digits
const parseFloat=std.fmt.parseFloat;
/// a word turned into its enum tag, or null if none matches
const stringToEnum=std.meta.stringToEnum;
/// every tag of an enum, in order (the tests walk the eases)
const values=std.enums.values;
/// where a run of bytes first falls in another (the tests find a key's line)
const indexOf=std.mem.indexOf;
/// the test helpers
const testing=std.testing;
/// the engine's maths: lerp, smoothstep
const m=@import("../core/math.zig");
/// keys this close in time are the same key
pub const same:f32=1e-4;
/// the first line of a clip's text
pub const header="# clip";
/// how far `back` swings past the next key before it settles (the
/// classic overshoot: about a tenth of the way, at its widest)
pub const overshoot:f32=1.70158;
/// how a key's value runs on to the next key's: the curve's shape, from
/// 0 at the key to 1 at the next
pub const Ease=enum{
  /// eased out of the key and into the next, flat at both (smoothstep):
  /// the default, kept unwritten in a clip's text
  smooth,
  /// straight on at one pace
  linear,
  /// held at the key, then a jump at the next
  step,
  /// a slow start, gathering pace into the next key
  easeIn,
  /// a quick start, slowing to a stop at the next key
  easeOut,
  /// quick, swinging a little past the next key and settling back onto it
  back,
  /// how far along (0 at the key, 1 at the next; `back` a little past
  /// before 1) the value is at share `k` of the way in time
  pub fn at(ea:Ease,k:f32)f32{
    return switch(ea){
      .smooth=>m.smooth(k),
      .linear=>k,
      .step=>if(k<1)0 else 1,
      .easeIn=>k*k,
      .easeOut=>k*(2-k),
      .back=>back:{
        // how far is left to go, a negative share
        const r=k-1;
        break:back 1+r*r*((overshoot+1)*r+overshoot);
      },
    };
  }
};
/// one key: a value pinned at a time, and the ease on to the next
pub const Key=struct{
  /// when the key sits (seconds into the clip)
  t:f32,
  /// the value it holds there
  v:f32,
  /// how the value runs from here to the next key
  ease:Ease=.smooth,
};
/// one channel's keys, in time order
pub const Track=struct{
  /// the channel's name, its path (`arms.0.root.x`); owned by the clip
  name:[]const u8,
  /// its keys, sorted by time
  keys:std.ArrayList(Key)=.empty,
  /// its value at `t`: held before the first key and after the last,
  /// between two run as the first's ease shapes it (null without keys)
  pub fn sample(tr:*const Track,t:f32)?f32{
    // the keys
    const k=tr.keys.items;
    if(k.len==0)return null;
    if(t<=k[0].t)return k[0].v;
    for(k[1..],1..)|b,i|if(t<b.t){
      // the key before `t`
      const a=k[i-1];
      return m.lerp(a.v,b.v,a.ease.at((t-a.t)/(b.t-a.t)));
    };
    return k[k.len-1].v;
  }
  /// the key at `t` (within `same` seconds), if there is one: its index
  pub fn at(tr:*const Track,t:f32)?usize{
    for(tr.keys.items,0..)|k,i|if(@abs(k.t-t)<same)return i;
    return null;
  }
};
/// a named moment in a clip, as a footfall or a blink is
pub const Mark=struct{
  /// when it falls (seconds into the clip)
  t:f32,
  /// what it is called (may be empty); owned by the clip
  name:[]const u8,
};
/// what reading a clip's text can fail with
pub const ParseError=error{
  /// a line that is not a header, comment, `subject`, `length`, `key` or `mark`,
  /// or one missing its words or numbers, or a key's ease not one known
  BadClip,
  /// no room for the clip's names and keys
  OutOfMemory
};
/// a named set of tracks: one movement, kept as text in `src/anim/`
pub const Clip=struct{
  /// the allocator its subject, names and keys are owned through
  gpa:Allocator,
  /// what it animates (the game's word for it)
  subject:[]const u8,
  /// seconds it runs
  length:f32=2,
  /// its tracks, one per channel keyed, in the order they were first keyed
  tracks:std.ArrayList(Track)=.empty,
  /// its marks, in time order
  marks:std.ArrayList(Mark)=.empty,
  /// an empty clip of `subject`, which is copied
  pub fn init(gpa:Allocator,subject:[]const u8)Allocator.Error!Clip{
    return.{.gpa=gpa,.subject=try gpa.dupe(u8,subject)};
  }
  /// frees the subject, every track's name and keys, the tracks, and the marks
  pub fn deinit(c:*Clip)void{
    for(c.tracks.items)|*tr|{
      c.gpa.free(tr.name);
      tr.keys.deinit(c.gpa);
    }
    c.tracks.deinit(c.gpa);
    for(c.marks.items)|mk|c.gpa.free(mk.name);
    c.marks.deinit(c.gpa);
    c.gpa.free(c.subject);
  }
  /// the mark at `t` (within `same` seconds), if there is one: its index
  pub fn markAt(c:*const Clip,t:f32)?usize{
    for(c.marks.items,0..)|mk,i|if(@abs(mk.t-t)<same)return i;
    return null;
  }
  /// a mark named `name` (copied) at `t`; one already there is renamed
  pub fn mark(c:*Clip,t:f32,name:[]const u8)Allocator.Error!void{
    // the name, owned by the clip
    const owned=try c.gpa.dupe(u8,name);
    if(c.markAt(t))|i|{
      c.gpa.free(c.marks.items[i].name);
      c.marks.items[i].name=owned;
      return;
    }
    errdefer c.gpa.free(owned);
    // where the new mark goes, keeping the marks in time order
    var i:usize=0;
    while(i<c.marks.items.len and c.marks.items[i].t<t)i+=1;
    try c.marks.insert(c.gpa,i,.{.t=t,.name=owned});
  }
  /// the mark at `t` taken out; whether there was one
  pub fn unmark(c:*Clip,t:f32)bool{
    // the mark at `t`
    const i=c.markAt(t) orelse return false;
    c.gpa.free(c.marks.orderedRemove(i).name);
    return true;
  }
  /// the track named `name`, or null when none is keyed yet
  pub fn track(c:*const Clip,name:[]const u8)?*Track{
    for(c.tracks.items)|*tr|if(eql(u8,tr.name,name))return tr;
    return null;
  }
  /// `name` keyed to `v` at `t` (an existing key there takes the value
  /// and keeps its ease; a new one eases smooth)
  pub fn put(c:*Clip,name:[]const u8,t:f32,v:f32)Allocator.Error!void{
    // the channel's track, made (with its name copied) when it is new
    const tr=c.track(name) orelse add:{
      // the name, owned by the clip
      const owned=try c.gpa.dupe(u8,name);
      errdefer c.gpa.free(owned);
      try c.tracks.append(c.gpa,.{.name=owned});
      break:add&c.tracks.items[c.tracks.items.len-1];
    };
    if(tr.at(t))|i|{
      tr.keys.items[i].v=v;
      return;
    }
    // where the new key goes, keeping the keys in time order
    var i:usize=0;
    while(i<tr.keys.items.len and tr.keys.items[i].t<t)i+=1;
    try tr.keys.insert(c.gpa,i,.{.t=t,.v=v});
  }
  /// `name` keyed to `v` at `t` with the ease `ea` on to the next key
  pub fn putEased(c:*Clip,name:[]const u8,t:f32,v:f32,ea:Ease)Allocator.Error!void{
    try c.put(name,t,v);
    _=c.ease(name,t,ea);
  }
  /// `name`'s key at `t` given the ease `ea`; whether there was one
  pub fn ease(c:*Clip,name:[]const u8,t:f32,ea:Ease)bool{
    // the channel's track, and the key at `t`
    const tr=c.track(name) orelse return false;
    const i=tr.at(t) orelse return false;
    tr.keys.items[i].ease=ea;
    return true;
  }
  /// `name`'s key at `t`, if there is one
  pub fn keyAt(c:*const Clip,name:[]const u8,t:f32)?Key{
    // the channel's track, and the key at `t`
    const tr=c.track(name) orelse return null;
    return tr.keys.items[tr.at(t) orelse return null];
  }
  /// `name`'s key at `t` taken out; whether there was one
  pub fn remove(c:*Clip,name:[]const u8,t:f32)bool{
    // the channel's track, and the key at `t`
    const tr=c.track(name) orelse return false;
    const i=tr.at(t) orelse return false;
    _=tr.keys.orderedRemove(i);
    return true;
  }
  /// `name`'s value at `t` (see `Track.sample`), or null when it has no track
  pub fn sample(c:*const Clip,name:[]const u8,t:f32)?f32{
    return if(c.track(name))|tr|tr.sample(t)else null;
  }
  /// the nearest key or mark time after (`dir` 1) or before (-1) `t`
  pub fn nextKey(c:*const Clip,t:f32,dir:f32)?f32{
    // the nearest time so far
    var best:?f32=null;
    for(c.tracks.items)|tr|for(tr.keys.items)|k|{
      // how far ahead (along `dir`) this key lies
      const d=(k.t-t)*dir;
      if(d>same and (best==null or d<(best.?-t)*dir))best=k.t;
    };
    for(c.marks.items)|mk|{
      // how far ahead (along `dir`) this mark lies
      const d=(mk.t-t)*dir;
      if(d>same and (best==null or d<(best.?-t)*dir))best=mk.t;
    }
    return best;
  }
  /// its text: a header, `subject`, `length`, a `key <channel> <time>
  /// <value> [ease]` line for each key (the ease left off when smooth, so
  /// clips from before eases read and write the same), then a `mark
  /// <time> <name>` line for each mark
  pub fn write(c:*const Clip,w:*Writer)Writer.Error!void{
    try w.print("{s}\nsubject {s}\nlength {d}\n",.{header,c.subject,c.length});
    for(c.tracks.items)|tr|for(tr.keys.items)|k|{
      try w.print("key {s} {d} {d}",.{tr.name,k.t,k.v});
      if(k.ease!=.smooth)try w.print(" {t}",.{k.ease});
      try w.writeByte('\n');
    };
    for(c.marks.items)|mk|try w.print("mark {d} {s}\n",.{mk.t,mk.name});
  }
  /// a clip from its text (`#` starts a comment)
  pub fn parse(gpa:Allocator,text:[]const u8)ParseError!Clip{
    // the clip, empty until its lines fill it
    var c=try Clip.init(gpa,"");
    errdefer c.deinit();
    // the text, line by line
    var lines=splitScalar(u8,text,'\n');
    while(lines.next())|raw|{
      // this line, trimmed of spaces and its CR
      const line=trim(u8,raw," \t\r");
      if(line.len==0 or line[0]=='#')continue;
      // the line's words, and the first, which says what the line is
      var it=tokenizeScalar(u8,line,' ');
      const word=it.next() orelse continue;
      if(eql(u8,word,"subject")){
        // the subject's word
        const s=it.next() orelse return error.BadClip;
        gpa.free(c.subject);
        c.subject="";
        c.subject=try gpa.dupe(u8,s);
      }else if(eql(u8,word,"length")){
        c.length=parseFloat(f32,it.next() orelse return error.BadClip) catch return error.BadClip;
      }else if(eql(u8,word,"key")){
        // the key's channel, time and value, and its ease (smooth unless said)
        const name=it.next() orelse return error.BadClip;
        const t=parseFloat(f32,it.next() orelse return error.BadClip) catch return error.BadClip;
        const v=parseFloat(f32,it.next() orelse return error.BadClip) catch return error.BadClip;
        const ea=if(it.next())|ew|stringToEnum(Ease,ew) orelse return error.BadClip else.smooth;
        try c.putEased(name,t,v,ea);
      }else if(eql(u8,word,"mark")){
        // the mark's time, then its name: the rest of the line, spaces and all
        const ts=it.next() orelse return error.BadClip;
        const t=parseFloat(f32,ts) catch return error.BadClip;
        try c.mark(t,trim(u8,it.rest()," \t"));
      }else return error.BadClip;
    }
    return c;
  }
};
/// every f32 in `T` as a channel: its name (path) and how to read and
/// write it. Other fields (bools, ints) are left out.
pub fn Channels(comptime T:type)type{
  return struct{
    /// how many channels `T` has
    pub const count=countOf(T);
    /// each channel's name, its dotted path, in channel order
    pub const names:[count][]const u8=namesOf(T,"");
    /// channel `i`'s value in `x`
    pub fn get(x:*const T,i:usize)f32{
      // a copy, since `walk` takes something it may write
      var copy=x.*;
      return walk(T,&copy,i,null);
    }
    /// sets channel `i` in `x` to `v`
    pub fn set(x:*T,i:usize,v:f32)void{_=walk(T,x,i,v);}
    /// the channel named `name`
    pub fn find(name:[]const u8)?usize{
      for(names,0..)|n,i|if(eql(u8,n,name))return i;
      return null;
    }
  };
}
/// how many f32 channels a `U` holds: a float one, a struct its fields',
/// an array its items', a vector its lanes (other types none)
fn countOf(comptime U:type)usize{
  return switch(@typeInfo(U)){
    .float=>if(U==f32)1 else 0,
    .@"struct"=>|s|blk:{
      // the fields' channels, summed
      var n:usize=0;
      for(s.fields)|fl|n+=countOf(fl.type);
      break:blk n;
    },
    .array=>|a|a.len*countOf(a.child),
    .vector=>|v|if(v.child==f32)v.len else 0,
    else=>0,
  };
}
/// how a vector's lanes are named, by index
const axes=[_][]const u8{"x","y","z","w"};
/// each channel's name in a `U`, dotted from `prefix`: field names, array
/// indices and vector axes, in channel order
fn namesOf(comptime U:type,comptime prefix:[]const u8)[countOf(U)][]const u8{
  @setEvalBranchQuota(100_000);
  // the names, filled as the type is walked
  var out:[countOf(U)][]const u8=undefined;
  // the prefix with its dot, or nothing at the top
  const dot=if(prefix.len==0)""else prefix++".";
  switch(@typeInfo(U)){
    .float=>if(U==f32){
      out[0]=prefix;
    },
    .@"struct"=>|s|{
      // where the next field's names go
      var n:usize=0;
      for(s.fields)|fl|{
        // the field's names
        const sub=namesOf(fl.type,dot++fl.name);
        for(sub,0..)|nm,i|out[n+i]=nm;
        n+=sub.len;
      }
    },
    .array=>|a|{
      // how many channels one item holds
      const per=countOf(a.child);
      for(0..a.len)|j|{
        // the item's names
        const sub=namesOf(a.child,dot++std.fmt.comptimePrint("{d}",.{j}));
        for(sub,0..)|nm,i|out[j*per+i]=nm;
      }
    },
    .vector=>|v|if(v.child==f32){
      for(0..v.len)|j|out[j]=dot++axes[j];
    },
    else=>{},
  }
  return out;
}
/// channel `i` of `x` (its value; set to `v` first when there is one)
fn walk(comptime U:type,x:*U,i:usize,v:?f32)f32{
  switch(@typeInfo(U)){
    .float=>if(U==f32){
      if(v)|nv|x.*=nv;
      return x.*;
    },
    .@"struct"=>|s|{
      // where this field's channels start
      comptime var base:usize=0;
      inline for(s.fields)|fl|{
        // how many channels this field holds
        const n=comptime countOf(fl.type);
        if(n>0 and i>=base and i<base+n)return walk(fl.type,&@field(x,fl.name),i-base,v);
        base+=n;
      }
    },
    .array=>|a|{
      // how many channels one item holds
      const per=comptime countOf(a.child);
      if(per>0)inline for(0..a.len)|j|{
        if(i>=j*per and i<(j+1)*per)return walk(a.child,&x[j],i-j*per,v);
      };
    },
    .vector=>|vec|if(vec.child==f32){
      // the vector as an array, so one lane can be set
      var arr:[vec.len]f32=x.*;
      if(v)|nv|arr[i]=nv;
      x.*=arr;
      return arr[i];
    },
    else=>{},
  }
  unreachable;
}
test"a track eases between its keys and holds past its ends"{
  // a clip with one channel keyed twice, at 0 and at 1
  var c=try Clip.init(testing.allocator,"thing");
  defer c.deinit();
  try c.put("a",1,2);
  try c.put("a",0,0);
  try c.put("a",1,4);
  // the channel's track
  const tr=c.track("a").?;
  try testing.expectEqual(@as(usize,2),tr.keys.items.len);
  try testing.expectEqual(@as(f32,0),c.sample("a",-1).?);
  try testing.expectApproxEqAbs(@as(f32,2),c.sample("a",0.5).?,1e-5);
  try testing.expectEqual(@as(f32,4),c.sample("a",3).?);
  try testing.expect(c.sample("b",0)==null);
  try testing.expectEqual(@as(f32,1),c.nextKey(0,1).?);
  try testing.expectEqual(@as(f32,0),c.nextKey(1,-1).?);
  try testing.expect(c.remove("a",1));
  try testing.expect(!c.remove("a",1));
  // a mark is a stop on the way too, renamed in place and taken out
  try c.mark(0.5,"step");
  try c.mark(0.5,"left step");
  try testing.expectEqual(@as(usize,1),c.marks.items.len);
  try testing.expectEqualStrings("left step",c.marks.items[c.markAt(0.5).?].name);
  try testing.expectEqual(@as(f32,0.5),c.nextKey(0,1).?);
  try testing.expect(c.unmark(0.5));
  try testing.expect(!c.unmark(0.5));
}
test"a clip comes back from its text"{
  // the allocator, which finds leaks
  const gpa=testing.allocator;
  // a clip with a length and three keys on two channels
  var c=try Clip.init(gpa,"wolf");
  defer c.deinit();
  c.length=1.5;
  try c.put("head.x",0,0.25);
  try c.put("head.x",0.75,-0.5);
  try c.put("jaw",0.5,0.1);
  try c.mark(0.25,"paw lands");
  try c.mark(1,"");
  // the clip's text, written into memory
  var out:Writer.Allocating=.init(gpa);
  defer out.deinit();
  try c.write(&out.writer);
  // the clip read back from that text
  var back=try Clip.parse(gpa,out.written());
  defer back.deinit();
  try testing.expectEqualStrings("wolf",back.subject);
  try testing.expectEqual(@as(f32,1.5),back.length);
  try testing.expectEqual(@as(f32,-0.5),back.sample("head.x",1).?);
  try testing.expectEqual(@as(f32,0.1),back.sample("jaw",0).?);
  try testing.expectEqual(@as(usize,2),back.marks.items.len);
  try testing.expectEqualStrings("paw lands",back.marks.items[0].name);
  try testing.expectEqualStrings("",back.marks.items[1].name);
  try testing.expectError(error.BadClip,Clip.parse(gpa,"key head.x zero 1"));
  try testing.expectError(error.BadClip,Clip.parse(gpa,"key head.x 0 1 wobbly"));
}
test"each ease starts at its key, ends at the next, and runs its own way between"{
  for(values(Ease))|ea|{
    try testing.expectApproxEqAbs(@as(f32,0),ea.at(0),1e-6);
    try testing.expectApproxEqAbs(@as(f32,1),ea.at(1),1e-6);
  }
  try testing.expectApproxEqAbs(@as(f32,0.5),Ease.smooth.at(0.5),1e-6);
  try testing.expectApproxEqAbs(@as(f32,0.25),Ease.linear.at(0.25),1e-6);
  // step holds the key all the way to the next
  try testing.expectEqual(@as(f32,0),Ease.step.at(0.99));
  // ease in lags the straight line, ease out leads it
  try testing.expect(Ease.easeIn.at(0.5)<0.5);
  try testing.expect(Ease.easeOut.at(0.5)>0.5);
  // back swings past the next key before settling onto it
  // the farthest back reaches along the way
  var most:f32=0;
  for(1..100)|i|most=@max(most,Ease.back.at(m.f(i)/100));
  try testing.expect(most>1.05 and most<1.15);
  try testing.expect(Ease.back.at(0.2)>Ease.linear.at(0.2));
  // in a clip: a key's ease shapes the way on to the next, and putting a
  // new value keeps it
  var c=try Clip.init(testing.allocator,"thing");
  defer c.deinit();
  try c.putEased("a",0,0,.step);
  try c.put("a",1,4);
  try testing.expectEqual(@as(f32,0),c.sample("a",0.9).?);
  try testing.expectEqual(@as(f32,4),c.sample("a",1).?);
  try c.put("a",0,2);
  try testing.expectEqual(Ease.step,c.keyAt("a",0).?.ease);
  try testing.expect(c.ease("a",0,.linear));
  try testing.expectApproxEqAbs(@as(f32,3),c.sample("a",0.5).?,1e-5);
  try testing.expect(!c.ease("a",0.5,.back));
  try testing.expect(c.keyAt("b",0)==null);
}
test"a clip written before eases reads back and writes out the same, and eases keep"{
  // the allocator, which finds leaks
  const gpa=testing.allocator;
  // a clip's text as kept before keys had eases
  const old="# clip\nsubject wolf\nlength 2\nkey arms.1.root.x 0 0.30598304\nkey arms.1.root.x 1.0666667 0.1910734\nkey arms.1.mid 0.56666666 1.953561\nmark 0.5 paw lands\n";
  var c=try Clip.parse(gpa,old);
  defer c.deinit();
  for(c.tracks.items)|tr|for(tr.keys.items)|k|try testing.expectEqual(Ease.smooth,k.ease);
  // the clip written again, word for word what it was
  var out:Writer.Allocating=.init(gpa);
  defer out.deinit();
  try c.write(&out.writer);
  try testing.expectEqualStrings(old,out.written());
  // every ease but smooth written after its key's value, and read back
  try testing.expect(c.ease("arms.1.root.x",0,.back));
  try testing.expect(c.ease("arms.1.mid",0.56666666,.step));
  // the eased clip's text
  var eased:Writer.Allocating=.init(gpa);
  defer eased.deinit();
  try c.write(&eased.writer);
  try testing.expect(indexOf(u8,eased.written(),"key arms.1.root.x 0 0.30598304 back\n")!=null);
  var back=try Clip.parse(gpa,eased.written());
  defer back.deinit();
  try testing.expectEqual(Ease.back,back.keyAt("arms.1.root.x",0).?.ease);
  try testing.expectEqual(Ease.smooth,back.keyAt("arms.1.root.x",1.0666667).?.ease);
  try testing.expectEqual(Ease.step,back.keyAt("arms.1.mid",0.56666666).?.ease);
}
test"every f32 of a struct is a channel, named by its path"{
  // a float, a bool (no channel), a vector and an array of structs
  const S=struct{
    /// one channel, `a`
    a:f32=1,
    /// no channel: not a float
    on:bool=true,
    /// three channels, `p.x` to `p.z`
    p:m.V3=.{2,3,4},
    /// two legs of three channels each, `legs.0.b` to `legs.1.c.1`
    legs:[2]struct{b:f32=5,c:[2]f32=.{6,7}}=@splat(.{}),
  };
  // the struct's channels
  const C=Channels(S);
  try testing.expectEqual(@as(usize,1+3+2*3),C.count);
  try testing.expectEqualStrings("p.y",C.names[2]);
  try testing.expectEqualStrings("legs.1.c.0",C.names[8]);
  // a struct to read and write
  var s:S=.{};
  try testing.expectEqual(@as(f32,3),C.get(&s,2));
  C.set(&s,8,-1);
  try testing.expectEqual(@as(f32,-1),s.legs[1].c[0]);
  C.set(&s,3,9);
  try testing.expectEqual(@as(f32,9),s.p[2]);
  try testing.expectEqual(@as(usize,8),C.find("legs.1.c.0").?);
}
