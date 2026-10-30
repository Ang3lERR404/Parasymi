//! sound out: the default WASAPI device pulling blocks from a `dsp` source.
//! The pull runs on zig-wsapi's render thread (the device's, so the engine
//! spawns none) against a real-time deadline: the source renders, it never
//! allocates, locks or waits. The game never touches a playing source; it
//! `send`s commands, which a lock-free mailbox hands over at the start of
//! the next block.
const std=@import("std");
const wasapi=@import("wasapi");
const m=@import("../core/math.zig");
const testing=std.testing;
const Allocator=std.mem.Allocator;
const Io=std.Io;
const Atomic=std.atomic.Value;
/// the most frames one block holds; a longer device period is served in
/// several blocks (zig-wsapi's own default bound)
const block=4096;
/// commands queued between two blocks before `send` refuses
const inbox=256;
/// how long `open` waits for the device to start
const startS=5;
/// a single-producer single-consumer queue without locks: one thread
/// `push`es, one other `pop`s. `n` is a power of two.
pub fn Mailbox(comptime T:type,comptime n:usize)type{
  if(n==0 or n&(n-1)!=0)@compileError("a mailbox holds a power of two");
  return struct{
    const Self=@This();
    // decision: undefined until pushed; `pop` reads only slots `push` wrote
    items:[n]T=undefined,
    /// the next slot to pop (the consumer's)
    head:Atomic(usize)=.init(0),
    /// the next slot to push (the producer's)
    tail:Atomic(usize)=.init(0),
    pub fn push(q:*Self,x:T)error{Full}!void{
      const t=q.tail.load(.monotonic);
      if(t-%q.head.load(.acquire)==n)return error.Full;
      q.items[t%n]=x;
      q.tail.store(t+%1,.release);
    }
    pub fn pop(q:*Self)?T{
      const h=q.head.load(.monotonic);
      if(h==q.tail.load(.acquire))return null;
      const x=q.items[h%n];
      q.head.store(h+%1,.release);
      return x;
    }
  };
}
pub const Options=struct{
  /// shown in the Windows volume mixer
  name:[]const u8,
  /// samples per second the source was built for
  rate:u32=48000,
};
pub const Error=wasapi.errors.OpenError||Io.Cancelable||error{
  /// the device never started within `START_S`
  NotStreaming,
  /// the device settled on another rate than the source was built for
  RateMismatch,
};
/// the default output device playing a source `S`, which declares
///   `Cmd`                         what the game may tell it
///   `apply(s:*S, cmd:Cmd) void`   act on one, between blocks
///   `render(s:*S, out:[]f32) void` mix one mono block into `out` (zeroed)
/// Every output channel hears the mono block, clamped to -1..1.
pub fn Output(comptime S:type)type{
  return struct{
    const Self=@This();
    src:S,
    inbox:Mailbox(S.Cmd,inbox)=.{},
    stream:*wasapi.Stream=undefined,
    block:[block]f32=undefined,
    /// opens the default device and starts pulling from `src` (built for
    /// `opts.rate`); `close` stops it
    pub fn open(gpa:Allocator,io:Io,src:S,opts:Options)Error!*Self{
      const o=try gpa.create(Self);
      errdefer gpa.destroy(o);
      o.*=.{.src=src};
      o.stream=try wasapi.Stream.open(gpa,io,.{
        .name=opts.name,
        .rate=opts.rate,
        .max_period_frames=block,
        .process=.{.ctx=o,.func=&fill},
      });
      errdefer o.stream.close(io);
      const wait:Io.Timeout=.{.duration=.{.raw=.fromSeconds(startS),.clock=.awake}};
      if(!try o.stream.waitStreaming(io,wait))return error.NotStreaming;
      if(o.stream.rate()!=opts.rate)return error.RateMismatch;
      return o;
    }
    pub fn close(o:*Self,gpa:Allocator,io:Io)void{
      o.stream.close(io);
      gpa.destroy(o);
    }
    /// hands `cmd` to the source; refused only when the game sends faster
    /// than the device plays (`INBOX` commands within one block)
    pub fn send(o:*Self,cmd:S.Cmd)error{Full}!void{return o.inbox.push(cmd);}
    /// silence without closing: the source stops being pulled
    pub fn pause(o:*Self)void{o.stream.pause();}
    pub fn unpause(o:*Self)void{o.stream.unpause();}
    /// how many frames the device had to play without a block in time
    pub fn underruns(o:*Self)u64{return o.stream.underruns();}
    /// the render thread's pull: commands first, then the source block by
    /// block into every channel
    fn fill(ctx:*anyopaque,planes:[]const[]f32,frames:u32)void{
      const o:*Self=@ptrCast(@alignCast(ctx));
      while(o.inbox.pop())|cmd|o.src.apply(cmd);
      var done:usize=0;
      while(done<frames){
        const out=o.block[0..@min(frames-done,block)];
        @memset(out,0);
        o.src.render(out);
        for(out)|*s|s.*=m.clamp(s.*,-1,1);
        for(planes)|p|@memcpy(p[done..][0..out.len],out);
        done+=out.len;
      }
    }
  };
}
test"mailbox keeps order and refuses when full"{
  var q:Mailbox(u32,4)=.{};
  try testing.expectEqual(@as(?u32,null),q.pop());
  for(0..4)|i|try q.push(@intCast(i));
  try testing.expectError(error.Full,q.push(9));
  for(0..4)|i|try testing.expectEqual(@as(?u32,@intCast(i)),q.pop());
  try testing.expectEqual(@as(?u32,null),q.pop());
  // wraps past its length
  for(0..10)|i|{
    try q.push(@intCast(i));
    try testing.expectEqual(@as(?u32,@intCast(i)),q.pop());
  }
}
/// a source that counts what it was told and renders a constant
const Probe=struct{
  pub const Cmd=f32;
  level:f32=0,
  pub fn apply(p:*Probe,c:Cmd)void{p.level=c;}
  pub fn render(p:*Probe,out:[]f32)void{
    for(out)|*s|s.*+=p.level;
  }
};
test"fill applies commands, then renders every channel, clamped"{
  const O=Output(Probe);
  var o:O=.{.src=.{}};
  try o.send(2);
  var l:[block+7]f32=undefined;
  var r:[block+7]f32=undefined;
  O.fill(&o,&.{l[0..],r[0..]},l.len);
  for(l,r)|a,b|{
    try testing.expectEqual(@as(f32,1),a);
    try testing.expectEqual(@as(f32,1),b);
  }
}
