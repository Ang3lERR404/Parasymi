//! `--link`: the game talking with Claude while the gardener plays. A
//! little folder in the gardener's home (`link/`) is the meeting place,
//! shared with the bridge (`tools/bridge.zig`, the MCP server Claude Code
//! runs): the game appends what the gardener types to `toClaude.jsonl`,
//! the bridge appends Claude's answers to `fromClaude.jsonl`, each side
//! reading only the lines new since it last looked. The game keeps
//! `state.txt` fresh (what it believes, as the trail's note), and when the
//! bridge leaves a `wantFrame` the game answers with `frame.png`.
//! Plain files and no sockets: nothing in the game waits on Claude.
//!
//! The folder sits in the working directory (the project, where both
//! `zig build run` and `.mcp.json`'s bridge start), not in AppData: the
//! Claude app is a packaged app, and Windows hands it (and everything it
//! starts) a private copy of AppData, so a game started from the
//! gardener's own console and a bridge started by Claude would each meet
//! in a different folder.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator texts are read with
const Allocator=std.mem.Allocator;
/// the I/O interface every file call goes through
const Io=std.Io;
/// a directory handle
const Dir=Io.Dir;
/// where a line is written
const Writer=Io.Writer;
/// a growable list, the texts read out
const ArrayList=std.ArrayList;
/// reads one message's JSON
const parseFromSlice=std.json.parseFromSlice;
/// writes one message's JSON, its text escaped
const stringify=std.json.Stringify.value;
/// finds a line's end
const lastIndexOfScalar=std.mem.lastIndexOfScalar;
/// splits the new text into lines
const splitScalar=std.mem.splitScalar;
/// strips a line's carriage return
const trim=std.mem.trim;
/// the test harness
const testing=std.testing;
/// the text input a message is typed into
const TextInput=lib.engine.ui.textInput.TextInput;
/// the log, telling where messages went
const log=std.log;
/// the working directory's full path, for the log
const currentPath=std.process.currentPath;
// decision: file names, not player-facing text, so not in the strings
/// the meeting place's folder, inside the working directory
pub const folder="link";
/// the longest working directory path told in the log (bytes)
pub const maxWhere=512;
/// the working directory's full path written into `buf` (".", when it
/// cannot be found), told so the log says where the meeting place is
pub fn here(io:Io,buf:*[maxWhere]u8)[]const u8{
  const n=currentPath(io,buf) catch return".";
  return buf[0..n];
}
/// what the gardener said, a JSON line each, appended by the game
pub const toClaude="toClaude.jsonl";
/// what Claude said, a JSON line each, appended by the bridge
pub const fromClaude="fromClaude.jsonl";
/// what the game believes now, rewritten every `stateEvery` seconds
pub const stateFile="state.txt";
/// left by the bridge to ask for a frame; taken away by the game
pub const wantFrame="wantFrame";
/// the frame asked for, a PNG at half the screen's size
pub const frameFile="frame.png";
/// the frame while it is still being written (renamed when whole)
pub const frameTmp="frame.png.part";
/// the longest message kept, in bytes (longer is cut)
pub const maxText=280;
/// how many messages the sidebar keeps
pub const keep=8;
/// how often the game rewrites its state and looks for news (s)
pub const stateEvery:f32=1;
/// how often the game looks for Claude's answers and a frame asked for (s)
pub const pollEvery:f32=0.25;
/// one message's line, its text alone
const Message=struct{
  /// what was said
  text:[]const u8,
};
/// who said a message
pub const Who=enum{
  /// the gardener, typed in the game
  gardener,
  /// Claude, through the bridge
  claude,
};
/// a character a message may hold: printable ASCII (the font's own)
pub fn chatChar(c:u21)?u8{
  return if(c>=0x20 and c<=0x7e)@intCast(c)else null;
}
/// the chat's text input: printable ASCII, as long as a message may be
pub const Typed=TextInput(maxText,chatChar);
/// one message kept for the sidebar
pub const Said=struct{
  /// who said it
  who:Who=.gardener,
  /// its bytes; only the first `len` are real
  buf:[maxText]u8=undefined,
  /// how many bytes it holds
  len:usize=0,
  /// when it was said (the game's `uiTime`)
  at:f64=0,
  /// the gardener's, and it could not be written for Claude (shown so)
  failed:bool=false,
  /// what was said
  pub fn text(s:*const Said)[]const u8{return s.buf[0..s.len];}
};
/// the sidebar's conversation: the newest `keep` messages, oldest first,
/// and the one being typed
pub const Chat=struct{
  /// the messages kept, oldest first
  said:[keep]Said=@splat(.{}),
  /// how many are kept
  count:usize=0,
  /// the message being typed
  typed:Typed=.{.alignment=.left},
  /// keeps a message (cut to `maxText`), letting the oldest go when full
  pub fn add(c:*Chat,who:Who,text:[]const u8,at:f64)void{
    if(c.count==keep){
      for(0..keep-1)|i|c.said[i]=c.said[i+1];
      c.count-=1;
    }
    // the message's place, and how much of it fits
    const s=&c.said[c.count];
    const n=@min(text.len,maxText);
    s.*=.{.who=who,.len=n,.at=at};
    @memcpy(s.buf[0..n],text[0..n]);
    c.count+=1;
  }
  /// the messages kept, oldest first
  pub fn kept(c:*const Chat)[]const Said{return c.said[0..c.count];}
  /// the newest message did not reach Claude
  pub fn failLast(c:*Chat)void{
    if(c.count>0)c.said[c.count-1].failed=true;
  }
};
/// writes one message as its JSON line (newline ended) to `w`
pub fn encode(w:*Writer,text:[]const u8)Writer.Error!void{
  try stringify(Message{.text=text},.{},w);
  try w.writeByte('\n');
}
/// the text of one JSON line (owned), or null if it is not a message
pub fn decode(gpa:Allocator,line:[]const u8)Allocator.Error!?[]u8{
  // the line read, its strings borrowed until freed
  const p=parseFromSlice(Message,gpa,line,.{.ignore_unknown_fields=true})catch|e|switch(e){
    error.OutOfMemory=>return error.OutOfMemory,
    else=>return null,
  };
  defer p.deinit();
  return try gpa.dupe(u8,p.value.text);
}
/// what reading or writing the meeting place can fail with
pub const Error=error{LinkUnreadable,LinkUnwritable}||Allocator.Error;
/// appends `text` as one message's line to `path` in `dir`, made if missing
pub fn append(io:Io,dir:Dir,path:[]const u8,text:[]const u8)Error!void{
  // the line, escaped (a message is short; the escapes at most six a byte)
  var buf:[maxText*6+32]u8=undefined;
  var w:Writer=.fixed(&buf);
  encode(&w,text[0..@min(text.len,maxText)]) catch return error.LinkUnwritable;
  // the file, kept as it is, and where it ends
  var f=dir.createFile(io,path,.{.truncate=false,.read=true}) catch return error.LinkUnwritable;
  defer f.close(io);
  const end=f.length(io) catch return error.LinkUnwritable;
  f.writePositionalAll(io,w.buffered(),end) catch return error.LinkUnwritable;
}
/// one side's reading of a message file: how far it has read
pub const Inbox=struct{
  /// the bytes already read (only whole lines are ever taken)
  offset:u64=0,
  /// starts reading at the file's end, so only what comes after is heard
  pub fn skip(ib:*Inbox,io:Io,dir:Dir,path:[]const u8)void{
    ib.offset=if(dir.statFile(io,path,.{}))|st|st.size else|_|0;
  }
  /// the messages added since the last look (each owned, appended to
  /// `out`); a file grown shorter (begun again) is read from its start
  pub fn take(ib:*Inbox,gpa:Allocator,io:Io,dir:Dir,path:[]const u8,out:*ArrayList([]u8))Error!void{
    // the file; missing, nothing new
    var f=dir.openFile(io,path,.{})catch|e|switch(e){
      error.FileNotFound=>return,
      else=>return error.LinkUnreadable,
    };
    defer f.close(io);
    const size=f.length(io) catch return error.LinkUnreadable;
    if(size<ib.offset)ib.offset=0;
    if(size==ib.offset)return;
    // what was added, read whole
    const fresh=try gpa.alloc(u8,@intCast(size-ib.offset));
    defer gpa.free(fresh);
    const got=f.readPositionalAll(io,fresh,ib.offset) catch return error.LinkUnreadable;
    ib.offset+=try takeLines(gpa,fresh[0..got],out);
  }
};
/// decodes each whole line of `fresh` into `out` (lines that are not
/// messages skipped); returns the bytes taken, up to the last newline
pub fn takeLines(gpa:Allocator,fresh:[]const u8,out:*ArrayList([]u8))Allocator.Error!u64{
  // where the last whole line ends; none yet, and nothing is taken
  const end=(lastIndexOfScalar(u8,fresh,'\n') orelse return 0)+1;
  var it=splitScalar(u8,fresh[0..end],'\n');
  while(it.next())|raw|{
    // one line, its carriage return gone
    const line=trim(u8,raw,"\r ");
    if(line.len==0)continue;
    const text=try decode(gpa,line) orelse continue;
    errdefer gpa.free(text);
    try out.append(gpa,text);
  }
  return end;
}
/// frees the texts `take` read, and the list
pub fn freeAll(gpa:Allocator,out:*ArrayList([]u8))void{
  for(out.items)|t|gpa.free(t);
  out.deinit(gpa);
}
/// the game's half of the link: its clocks, its reading of Claude's file,
/// and a frame asked for
pub const Link=struct{
  /// the meeting place, opened inside the working directory
  dir:Dir,
  /// the meeting place's full path, for the log
  where:[]const u8=".",
  /// whether the state's last write failed (told once, and again when mended)
  stateFailed:bool=false,
  /// whether the state was ever written (the first is told)
  stateWritten:bool=false,
  /// Claude's answers, read so far
  inbox:Inbox=.{},
  /// seconds since the last look for news
  sincePoll:f32=0,
  /// whether a frame was asked for and is still to be taken
  frameWanted:bool=false,
  /// opens (making it) the meeting place in `base` (the working
  /// directory, `where` its path), hearing only what Claude says from now on
  pub fn open(io:Io,base:Dir,where:[]const u8)Error!Link{
    base.createDirPath(io,folder) catch return error.LinkUnwritable;
    // the folder
    const d=base.openDir(io,folder,.{}) catch return error.LinkUnreadable;
    var l=Link{.dir=d,.where=where};
    l.inbox.skip(io,d,fromClaude);
    return l;
  }
  /// lets go of the folder
  pub fn close(l:*Link,io:Io)void{l.dir.close(io);}
  /// counts the frame's time; true when Claude's file and a frame asked
  /// for are due a look
  pub fn step(l:*Link,dt:f32)bool{
    l.sincePoll+=dt;
    if(l.sincePoll<pollEvery)return false;
    l.sincePoll=0;
    return true;
  }
  /// Claude's new answers, added to `chat`, and whether a frame is asked
  /// for (not asked again until it is taken)
  pub fn poll(l:*Link,gpa:Allocator,io:Io,chat:*Chat,at:f64)Error!void{
    // the answers new since the last look
    var got:ArrayList([]u8)=.empty;
    defer freeAll(gpa,&got);
    try l.inbox.take(gpa,io,l.dir,fromClaude,&got);
    for(got.items)|t|chat.add(.claude,t,at);
    if(!l.frameWanted){
      l.frameWanted=if(l.dir.access(io,wantFrame,.{}))|_|true else|_|false;
    }
  }
  /// the gardener said `text`: kept in `chat` and handed to Claude, the
  /// log telling where it went; when it cannot be written it is marked
  /// in the sidebar (and the log says so)
  pub fn say(l:*Link,io:Io,chat:*Chat,text:[]const u8,at:f64)Error!void{
    chat.add(.gardener,text,at);
    append(io,l.dir,toClaude,text)catch|e|{
      chat.failLast();
      log.warn("link: NOT sent, {s}\\{s}\\{s}: {t}",.{l.where,folder,toClaude,e});
      return e;
    };
    log.info("link: sent to {s}\\{s}\\{s}",.{l.where,folder,toClaude});
  }
  /// writes the state's text, whole, over the last; the first write, a
  /// failure and its mending are told in the log (once each, not every second)
  pub fn writeState(l:*Link,io:Io,text:[]const u8)Error!void{
    l.dir.writeFile(io,.{.sub_path=stateFile,.data=text})catch{
      if(!l.stateFailed)log.warn("link: state NOT written, {s}\\{s}\\{s}",.{l.where,folder,stateFile});
      l.stateFailed=true;
      return error.LinkUnwritable;
    };
    if(l.stateFailed or !l.stateWritten)log.info("link: state written to {s}\\{s}\\{s}",.{l.where,folder,stateFile});
    l.stateFailed=false;
    l.stateWritten=true;
  }
  /// the frame asked for is being taken: the ask is answered (its file
  /// taken away, so the bridge knows to wait for the picture)
  pub fn frameTaken(l:*Link,io:Io)void{
    l.frameWanted=false;
    l.dir.deleteFile(io,wantFrame)catch{};
  }
};
test"a message survives its line, quotes and all"{
  // the line written, and the text read back
  var buf:[512]u8=undefined;
  var w:Writer=.fixed(&buf);
  try encode(&w,"he said \"hi\"\\ and left\n");
  const back=(try decode(testing.allocator,w.buffered())).?;
  defer testing.allocator.free(back);
  try testing.expectEqualStrings("he said \"hi\"\\ and left\n",back);
  try testing.expect((try decode(testing.allocator,"not json"))==null);
}
test"only whole lines are taken, the rest waits"{
  var out:ArrayList([]u8)=.empty;
  defer freeAll(testing.allocator,&out);
  // two whole lines and half a third, one of them not a message
  const fresh="{\"text\":\"a\"}\nnope\n{\"text\":\"b\"}\r\n{\"text\":\"c";
  const n=try takeLines(testing.allocator,fresh,&out);
  try testing.expectEqual(@as(usize,2),out.items.len);
  try testing.expectEqualStrings("a",out.items[0]);
  try testing.expectEqualStrings("b",out.items[1]);
  try testing.expectEqual(@as(u64,fresh.len-"{\"text\":\"c".len),n);
}
test"the sidebar keeps the newest messages"{
  var c=Chat{};
  for(0..keep+3)|i|{
    // the message's text, its number
    var b:[8]u8=undefined;
    c.add(.claude,try std.fmt.bufPrint(&b,"{d}",.{i}),0);
  }
  try testing.expectEqual(keep,c.kept().len);
  try testing.expectEqualStrings("3",c.kept()[0].text());
  try testing.expectEqualStrings("10",c.kept()[keep-1].text());
  // a long message is cut, never spilled
  c.add(.gardener,"x"**(maxText+40),0);
  try testing.expectEqual(maxText,c.kept()[keep-1].len);
}
test"a file read across turns: appended lines heard once, truncation begun again"{
  const io=testing.io;
  var tmp=testing.tmpDir(.{});
  defer tmp.cleanup();
  var ib=Inbox{};
  ib.skip(io,tmp.dir,"m.jsonl");
  try testing.expectEqual(@as(u64,0),ib.offset);
  var out:ArrayList([]u8)=.empty;
  defer freeAll(testing.allocator,&out);
  try append(io,tmp.dir,"m.jsonl","one");
  try append(io,tmp.dir,"m.jsonl","two");
  try ib.take(testing.allocator,io,tmp.dir,"m.jsonl",&out);
  try testing.expectEqual(@as(usize,2),out.items.len);
  try ib.take(testing.allocator,io,tmp.dir,"m.jsonl",&out);
  try testing.expectEqual(@as(usize,2),out.items.len);
  try append(io,tmp.dir,"m.jsonl","three");
  try ib.take(testing.allocator,io,tmp.dir,"m.jsonl",&out);
  try testing.expectEqualStrings("three",out.items[2]);
  // begun again, shorter: read from the start
  try tmp.dir.writeFile(io,.{.sub_path="m.jsonl",.data="{\"text\":\"anew\"}\n"});
  try ib.take(testing.allocator,io,tmp.dir,"m.jsonl",&out);
  try testing.expectEqualStrings("anew",out.items[3]);
}
test"the link asks for a frame once, until it is taken"{
  const io=testing.io;
  var tmp=testing.tmpDir(.{});
  defer tmp.cleanup();
  var l=try Link.open(io,tmp.dir,"tmp");
  defer l.close(io);
  var c=Chat{};
  try l.poll(testing.allocator,io,&c,0);
  try testing.expect(!l.frameWanted);
  try l.dir.writeFile(io,.{.sub_path=wantFrame,.data=""});
  try append(io,l.dir,fromClaude,"hello gardener");
  try l.poll(testing.allocator,io,&c,1);
  try testing.expect(l.frameWanted);
  try testing.expectEqualStrings("hello gardener",c.kept()[0].text());
  try testing.expectEqual(Who.claude,c.kept()[0].who);
  l.frameTaken(io);
  try l.poll(testing.allocator,io,&c,2);
  try testing.expect(!l.frameWanted);
  try l.say(io,&c,"hi claude",3);
  try testing.expect(!c.kept()[c.count-1].failed);
  // what the gardener said lands in Claude's file
  var ib=Inbox{};
  var out:ArrayList([]u8)=.empty;
  defer freeAll(testing.allocator,&out);
  try ib.take(testing.allocator,io,l.dir,toClaude,&out);
  try testing.expectEqualStrings("hi claude",out.items[0]);
}
test"a message that cannot be written is marked, the state's failure told"{
  const io=testing.io;
  var tmp=testing.tmpDir(.{});
  defer tmp.cleanup();
  var l=try Link.open(io,tmp.dir,"tmp");
  defer l.close(io);
  // (the failures it tells are meant here: the warnings would fail the run)
  const was=testing.log_level;
  testing.log_level=.err;
  defer testing.log_level=was;
  // Claude's file stands in the way as a folder: nothing can be written there
  try l.dir.createDirPath(io,toClaude);
  try l.dir.createDirPath(io,stateFile);
  var c=Chat{};
  try testing.expectError(error.LinkUnwritable,l.say(io,&c,"lost",0));
  try testing.expect(c.kept()[0].failed);
  try testing.expectEqualStrings("lost",c.kept()[0].text());
  try testing.expectError(error.LinkUnwritable,l.writeState(io,"x"));
  try testing.expect(l.stateFailed);
}
