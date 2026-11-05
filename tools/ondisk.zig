//! the editors' file kept an eye on: about once a second its modified time
//! is looked at, and only when that moved is the file read again (made
//! canonical, as the editor would write it). Then the editor is told what
//! to do: the same as it holds (saved), changed while the editor has
//! nothing of its own (taken quietly), or changed while the editor has
//! changes of its own too (a clash: never overwritten silently, the
//! gardener picks which to keep).
/// the standard library, reached through the game's hub
const std=ps.std;
/// the allocator type the kept text lives in
const Allocator=std.mem.Allocator;
/// the I/O interface every file call goes through
const Io=std.Io;
/// a directory handle (the working directory the file is under)
const Dir=Io.Dir;
/// whether two byte strings are the same
const eql=std.mem.eql;
/// the test helpers
const testing=std.testing;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// how often the file's modified time is looked at (s)
pub const every:f32=1;
/// the largest file read (bytes)
const maxFile=1<<22;
/// the editor's text made canonical (read and written back as the editor
/// would write it), the caller's to free; null when it will not read
pub const Canon=*const fn(gpa:Allocator,raw:[]const u8)?[]u8;
/// what the editor should do after a look
pub const Verdict=enum{
  /// nothing new on disk, and what the editor holds differs from it (unsaved)
  differs,
  /// what the editor holds is what the file holds: saved
  same,
  /// the file changed and the editor had nothing of its own: take the file's
  take,
  /// the file changed and the editor has changes of its own: the gardener picks
  clash,
};
/// the file as last seen: its text and when it was modified
pub const OnDisk=struct{
  /// the allocator the kept text lives in
  gpa:Allocator,
  /// how the editor makes a text canonical
  canon:Canon,
  /// the file's text as last read or written, canonical (null: none, or it would not read)
  kept:?[]u8=null,
  /// when the file was modified as last seen (null: not there)
  stamp:?i96=null,
  /// seconds since the last look
  since:f32=0,
  /// the file changed while the editor had changes of its own, not yet settled
  clash:bool=false,
  /// lets the kept text go
  pub fn deinit(d:*OnDisk)void{
    if(d.kept)|k|d.gpa.free(k);
    d.kept=null;
  }
  /// the file's modified time now (null: not there, or not looked at)
  fn stampOf(io:Io,path:[]const u8)?i96{
    const st=Dir.cwd().statFile(io,path,.{}) catch return null;
    return st.mtime.nanoseconds;
  }
  /// the editor just wrote `text` (canonical) to `path` itself: kept as
  /// the file's, with its new time, and any clash settled
  pub fn wrote(d:*OnDisk,io:Io,path:[]const u8,text:[]const u8)Allocator.Error!void{
    const k=try d.gpa.dupe(u8,text);
    d.deinit();
    d.kept=k;
    d.stamp=stampOf(io,path);
    d.clash=false;
  }
  /// the file read again if its time moved since the last look; true if so
  pub fn look(d:*OnDisk,io:Io,path:[]const u8)Allocator.Error!bool{
    const st=stampOf(io,path);
    if(st==d.stamp)return false;
    d.stamp=st;
    // the file's text as it is now, made canonical (none if it will not read)
    const raw=Dir.cwd().readFileAlloc(io,path,d.gpa,.limited(maxFile))catch{
      d.deinit();
      return true;
    };
    defer d.gpa.free(raw);
    const k=d.canon(d.gpa,raw);
    d.deinit();
    d.kept=k;
    return true;
  }
  /// what the editor should do, holding `now` (canonical), `dirty` if it
  /// has changes since it last saved or took the file, `fresh` if the file
  /// was read again just now
  pub fn judge(d:*OnDisk,now:[]const u8,dirty:bool,fresh:bool)Verdict{
    // a file gone, or one that will not read, is left be: the editor's stays
    const k=d.kept orelse return.differs;
    if(eql(u8,k,now)){
      d.clash=false;
      return.same;
    }
    if(!fresh)return.differs;
    if(!dirty)return.take;
    d.clash=true;
    return.clash;
  }
  /// the clock run on `dt`; true once a second, when a look is due (the
  /// editor makes its text only then)
  pub fn tick(d:*OnDisk,dt:f32)bool{
    d.since+=dt;
    if(d.since<every)return false;
    d.since=0;
    return true;
  }
  /// the file looked at and judged against the editor's `now`
  pub fn check(d:*OnDisk,io:Io,path:[]const u8,now:[]const u8,dirty:bool)Allocator.Error!Verdict{
    const fresh=try d.look(io,path);
    return d.judge(now,dirty,fresh);
  }
};
/// the tests' canon: the text as it is, unless it is "bad"
fn testCanon(gpa:Allocator,raw:[]const u8)?[]u8{
  if(eql(u8,raw,"bad"))return null;
  return gpa.dupe(u8,raw) catch null;
}
test"a file judged: the same is saved, a change taken when the editor has none, a clash when both changed"{
  // the allocator, and a kept text standing in for the file
  const gpa=testing.allocator;
  var d:OnDisk=.{.gpa=gpa,.canon=testCanon};
  defer d.deinit();
  d.kept=try gpa.dupe(u8,"a");
  // the editor holding the file's text: saved, whether it was dirty or not
  try testing.expectEqual(Verdict.same,d.judge("a",true,false));
  try testing.expectEqual(Verdict.same,d.judge("a",false,true));
  // nothing new on disk and the editor's differs: unsaved, nothing taken
  try testing.expectEqual(Verdict.differs,d.judge("b",false,false));
  // the file changed under an editor with nothing of its own: taken
  try testing.expectEqual(Verdict.take,d.judge("b",false,true));
  // under an editor with changes of its own: a clash, until the two agree
  try testing.expectEqual(Verdict.clash,d.judge("b",true,true));
  try testing.expect(d.clash);
  try testing.expectEqual(Verdict.same,d.judge("a",true,false));
  try testing.expect(!d.clash);
  // a file that will not read is left be
  d.deinit();
  try testing.expectEqual(Verdict.differs,d.judge("b",false,true));
}
test"a file looked at: read again only when its time moves, and the editor's own write settles a clash"{
  // the allocator, the I/O, and a folder of the test's own
  const gpa=testing.allocator;
  const io=testing.io;
  var tmp=testing.tmpDir(.{});
  defer tmp.cleanup();
  // the file's path from the working directory
  var pb:[256]u8=undefined;
  const path=try std.fmt.bufPrint(&pb,".zig-cache/tmp/{s}/f.txt",.{tmp.sub_path});
  try Dir.cwd().writeFile(io,.{.sub_path=path,.data="one"});
  var d:OnDisk=.{.gpa=gpa,.canon=testCanon};
  defer d.deinit();
  try testing.expect(try d.look(io,path));
  try testing.expectEqualStrings("one",d.kept.?);
  // looked at again, nothing moved: not read
  try testing.expect(!try d.look(io,path));
  // the editor's own write: kept as the file's, a clash settled
  d.clash=true;
  try Dir.cwd().writeFile(io,.{.sub_path=path,.data="two"});
  try d.wrote(io,path,"two");
  try testing.expect(!d.clash);
  try testing.expectEqualStrings("two",d.kept.?);
  try testing.expect(!try d.look(io,path));
  // a file that will not read keeps nothing
  d.stamp=0;
  try Dir.cwd().writeFile(io,.{.sub_path=path,.data="bad"});
  try testing.expect(try d.look(io,path));
  try testing.expect(d.kept==null);
}
