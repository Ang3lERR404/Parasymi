//! the bridge between the game and Claude Code: a Model Context Protocol
//! server Claude Code starts (`.mcp.json`) and talks to over stdin and
//! stdout, one JSON-RPC message a line. It meets the game through the
//! link folder in the working directory (`game/link.zig`): what the gardener
//! types in the game's chat is pushed into Claude's session as a channel
//! event (`notifications/claude/channel`, when Claude Code runs with
//! `--dangerously-load-development-channels server:parasymi`), and Claude
//! has three tools: `reply` (into the game's sidebar), `game_state` (what
//! the game believes now) and `game_frame` (what it shows, as a picture).
//! The editors linked the same way (`tools/editlink.zig`) answer those
//! too, and two more: `editor_document` (the open sculpt or clip, as its
//! file would hold it) and `editor_edit` (a whole edited one, taken as one
//! step of the editor's history, so ctrl+z takes it back).
//! Without the channel flag the tools still work; only the pushing waits.
/// the standard library
const std=@import("std");
/// the game, for its link folder
const lib=@import("parasymi");
/// the link's files and message lines
const link=lib.link;
/// the allocator everything is made with
const Allocator=std.mem.Allocator;
/// the I/O interface every file call goes through
const Io=std.Io;
/// a directory handle
const Dir=Io.Dir;
/// where a message is written
const Writer=Io.Writer;
/// a JSON value, read loosely
const Value=std.json.Value;
/// a JSON object's fields (a tool's arguments)
const ObjectMap=std.json.ObjectMap;
/// reads one JSON-RPC message
const parseFromSlice=std.json.parseFromSlice;
/// writes a JSON value
const stringify=std.json.Stringify.value;
/// the encoding a picture travels in
const base64=std.base64.standard.Encoder;
/// are two strings equal?
const eql=std.mem.eql;
/// a growable list
const ArrayList=std.ArrayList;
/// the test harness
const testing=std.testing;
/// the protocol revision answered with
// decision: a channel server must not negotiate 2026-07-28 (Claude Code
// does not register channels on it), so this one is always offered
const protocol="2025-06-18";
/// how long a frame is waited for before giving up (ms)
const frameWaitMs=6000;
/// how often a frame, or the gardener's file, is looked at (ms)
const lookMs=100;
/// the gardener's file is looked at this often (ms)
const watchMs=250;
/// the state counts as fresh (the game running, linked) this long (s)
const freshS=5;
/// the longest line read from Claude Code (bytes)
const maxLine=1<<22;
/// the largest frame read back (bytes)
const maxFrame=32<<20;
/// the most of the game's state file read (bytes)
const maxState=1<<16;
/// the most of an editor's open document read (bytes)
const maxDocument=1<<20;
/// the most of an edit's answer read (bytes)
const maxAnswer=4096;
/// what Claude is told when the server connects
const instructions=
  \\Parasymi's bridge. The gardener can type to you from the game's chat
  \\sidebar while playing; each message arrives as <channel source="parasymi">.
  \\Answer with the reply tool: it shows in the game's sidebar (as written,
  \\at most 280 characters, so keep it short). game_state tells what the game
  \\believes right now (open panel, where back leads, camera, the wolf's
  \\place, buttons pressed); game_frame shows the screen as a picture.
  \\The mesh and animation editors can be linked the same way (--link): then
  \\game_state and game_frame tell and show the editor, reply lands in its
  \\chat card, editor_document gives the open sculpt or clip as its file's
  \\text, editor_edit takes a whole edited text back as one undoable step,
  \\and editor_view turns the editor's camera (focus a form, zoom, pan) and shows it.
;
/// the tools offered, as Claude Code lists them (on one line: a message
/// is one line)
const toolsJson=oneLine(
  \\[{"name":"reply","description":"Send a message to the gardener's in-game chat sidebar (shown as written, capitals and small letters, at most 280 characters).","inputSchema":{"type":"object","properties":{"text":{"type":"string","description":"The message"}},"required":["text"]}},
  \\{"name":"game_state","description":"What the running game believes right now: mode, where back leads, camera, the wolf's place, hotbar, what is pointed at, actions pressed lately.","inputSchema":{"type":"object","properties":{}}},
  \\{"name":"game_frame","description":"A picture of what the running game shows right now (half size PNG).","inputSchema":{"type":"object","properties":{}}},
  \\{"name":"editor_document","description":"The sculpt (meshedit) or clip (animedit) open in a linked editor, as the text its file holds.","inputSchema":{"type":"object","properties":{}}},
  \\{"name":"editor_edit","description":"Give a linked editor a whole edited sculpt or clip text (editor_document's, changed): it is taken as one step of the editor's history, so ctrl+z there takes it back. Answers whether it was taken.","inputSchema":{"type":"object","properties":{"text":{"type":"string","description":"The whole edited document"}},"required":["text"]}},
  \\{"name":"editor_view","description":"Turn a linked editor's camera at once, then answer with its frame. Each left out keeps the view: home (back to the first view), focus (meshedit: frame form N, counted from 1), then at, dist, yaw, pitch, zoom, pan.","inputSchema":{"type":"object","properties":{"home":{"type":"boolean","description":"back to the view the editor opened with, first"},"focus":{"type":"integer","description":"meshedit: the form (from 1) to frame first"},"at":{"type":"array","items":{"type":"number"},"description":"the point looked at, [x,y,z] m from the subject's foot"},"dist":{"type":"number","description":"how far from the target (m)"},"yaw":{"type":"number","description":"turn round the target (degrees; 0 looks down -z from +z, 90 from +x)"},"pitch":{"type":"number","description":"height over the target (degrees; 90 straight down, negative from under)"},"zoom":{"type":"number","description":"wheel notches nearer (negative: back)"},"pan":{"type":"array","items":{"type":"number"},"description":"move the target across the view, [right,up,forward] m"}}}}]
);
/// `s` with its line breaks taken out, at compile time
fn oneLine(comptime s:[]const u8)[]const u8{
  comptime{
    @setEvalBranchQuota(100000);
    var out:[]const u8="";
    for(s)|c|if(c!='\n'){out=out++&[_]u8{c};};
    return out;
  }
}
/// the bridge: the link folder, the gardener's file read so far, and the
/// one writer every message out goes through
const Bridge=struct{
  /// the link folder in the working directory
  dir:Dir,
  /// the gardener's messages, read so far
  inbox:link.Inbox=.{},
  /// stdout, shared by the replies and the watcher's pushes
  out:*Writer,
  /// keeps two messages from being written at once
  lock:Io.Mutex=.init,
  /// whether Claude Code said it is ready (pushes wait until then)
  ready:bool=false,
  /// writes one whole message line, alone
  fn send(b:*Bridge,io:Io,bytes:[]const u8)void{
    b.lock.lockUncancelable(io);
    defer b.lock.unlock(io);
    b.out.writeAll(bytes) catch return;
    b.out.writeByte('\n') catch return;
    b.out.flush() catch return;
  }
  /// answers one message from Claude Code (`line`); writes the answer, if
  /// one is owed, to `w`
  fn handle(b:*Bridge,gpa:Allocator,io:Io,line:[]const u8,w:*Writer)!void{
    // the message, read loosely
    const p=parseFromSlice(Value,gpa,line,.{}) catch return rpcError(w,.null,-32700,"parse error");
    defer p.deinit();
    const msg=switch(p.value){.object=>|o|o,else=>return rpcError(w,.null,-32600,"invalid request")};
    const id=msg.get("id");
    const method=if(msg.get("method"))|mv|switch(mv){.string=>|s|s,else=>""}else"";
    if(eql(u8,method,"notifications/initialized")){
      b.ready=true;
      return;
    }
    // a notification: nothing owed
    const rid=id orelse return;
    if(eql(u8,method,"initialize"))return result(w,rid,"{\"protocolVersion\":\""++protocol++"\",\"capabilities\":{\"experimental\":{\"claude/channel\":{}},\"tools\":{}},\"serverInfo\":{\"name\":\"parasymi\",\"version\":\"0.1.0\"},\"instructions\":"++jsonText(instructions)++"}");
    if(eql(u8,method,"ping"))return result(w,rid,"{}");
    if(eql(u8,method,"tools/list"))return result(w,rid,"{\"tools\":"++toolsJson++"}");
    if(eql(u8,method,"tools/call"))return b.call(gpa,io,rid,msg.get("params"),w);
    return rpcError(w,rid,-32601,"method not found");
  }
  /// runs one tool
  fn call(b:*Bridge,gpa:Allocator,io:Io,id:Value,params:?Value,w:*Writer)!void{
    // the tool's name and arguments
    const ps=if(params)|pv|switch(pv){.object=>|o|o,else=>null}else null;
    const name=if(ps)|o|if(o.get("name"))|nv|switch(nv){.string=>|s|s,else=>""}else""else"";
    const args=if(ps)|o|if(o.get("arguments"))|av|switch(av){.object=>|ao|ao,else=>null}else null else null;
    if(eql(u8,name,"reply")){
      // the text to send
      const text=if(args)|a|if(a.get("text"))|tv|switch(tv){.string=>|s|s,else=>null}else null else null;
      const t=text orelse return toolText(w,id,"reply needs a text",true);
      link.append(io,b.dir,link.fromClaude,t) catch return toolText(w,id,"could not write the link folder",true);
      return toolText(w,id,if(fresh(io,b.dir))"sent"else"sent (the game does not seem to be running with --link; it will show when it is)",false);
    }
    if(eql(u8,name,"game_state")){
      if(!fresh(io,b.dir))return toolText(w,id,"the game is not running with --link (no fresh state)",true);
      // the state's text
      const st=b.dir.readFileAlloc(io,link.stateFile,gpa,.limited(maxState)) catch return toolText(w,id,"could not read the state",true);
      defer gpa.free(st);
      return toolText(w,id,st,false);
    }
    if(eql(u8,name,"game_frame"))return b.frame(gpa,io,id,w);
    if(eql(u8,name,"editor_document")){
      if(!fresh(io,b.dir))return toolText(w,id,"no editor is running with --link (no fresh state)",true);
      // the document's text
      const doc=b.dir.readFileAlloc(io,link.documentFile,gpa,.limited(maxDocument)) catch return toolText(w,id,"no document: is it an editor that is linked, not the game?",true);
      defer gpa.free(doc);
      return toolText(w,id,doc,false);
    }
    if(eql(u8,name,"editor_edit")){
      // the edited text
      const text=if(args)|a|if(a.get("text"))|tv|switch(tv){.string=>|str|str,else=>null}else null else null;
      const t=text orelse return toolText(w,id,"editor_edit needs the whole edited text",true);
      return b.edit(gpa,io,id,t,w);
    }
    if(eql(u8,name,"editor_view"))return b.view(gpa,io,id,args,w);
    return toolText(w,id,"no such tool",true);
  }
  /// leaves Claude's ask of a linked editor's camera, waits for it to be
  /// taken, then answers with the frame it shows
  fn view(b:*Bridge,gpa:Allocator,io:Io,id:Value,args:?ObjectMap,w:*Writer)!void{
    if(!fresh(io,b.dir))return toolText(w,id,"no editor is running with --link (no fresh state)",true);
    // the ask's text, a word and its numbers a line
    var buf:[1024]u8=undefined;
    var tw:Writer=.fixed(&buf);
    viewText(args,&tw) catch return toolText(w,id,"editor_view: at and pan are three numbers each; the rest one number (home true or false)",true);
    b.dir.writeFile(io,.{.sub_path=link.viewTmp,.data=tw.buffered()}) catch return toolText(w,id,"could not write the view",true);
    Dir.rename(b.dir,link.viewTmp,b.dir,link.viewFile,io) catch return toolText(w,id,"could not leave the view",true);
    // how long has been waited (ms)
    var waited:u32=0;
    while(waited<frameWaitMs):(waited+=lookMs){
      io.sleep(.fromMilliseconds(lookMs),.awake)catch{};
      if(b.dir.access(io,link.viewFile,.{}))|_|continue else|_|return b.frame(gpa,io,id,w);
    }
    b.dir.deleteFile(io,link.viewFile)catch{};
    return toolText(w,id,"the editor did not take the view in time (is it the game that is linked, not an editor?)",true);
  }
  /// leaves a whole edited document for the linked editor and waits for
  /// it to be taken, answered with the editor's word on it
  fn edit(b:*Bridge,gpa:Allocator,io:Io,id:Value,t:[]const u8,w:*Writer)!void{
    if(!fresh(io,b.dir))return toolText(w,id,"no editor is running with --link (no fresh state)",true);
    b.dir.deleteFile(io,link.editResultFile)catch{};
    // written whole, then given its name, so the editor never reads half
    b.dir.writeFile(io,.{.sub_path=link.editTmp,.data=t}) catch return toolText(w,id,"could not write the edit",true);
    Dir.rename(b.dir,link.editTmp,b.dir,link.editFile,io) catch return toolText(w,id,"could not leave the edit",true);
    // how long has been waited (ms)
    var waited:u32=0;
    while(waited<frameWaitMs):(waited+=lookMs){
      io.sleep(.fromMilliseconds(lookMs),.awake)catch{};
      if(b.dir.access(io,link.editFile,.{}))|_|continue else|_|{}
      // the editor's answer, written before it took the edit away
      const ans=b.dir.readFileAlloc(io,link.editResultFile,gpa,.limited(maxAnswer)) catch return toolText(w,id,"the edit was taken, but no answer was left",true);
      defer gpa.free(ans);
      return toolText(w,id,ans,!std.mem.startsWith(u8,ans,"taken"));
    }
    b.dir.deleteFile(io,link.editFile)catch{};
    return toolText(w,id,"the editor did not take the edit in time (is it the game that is linked, not an editor?)",true);
  }
  /// asks the game for a frame and waits for it, answered as a picture
  fn frame(b:*Bridge,gpa:Allocator,io:Io,id:Value,w:*Writer)!void{
    if(!fresh(io,b.dir))return toolText(w,id,"the game is not running with --link (no fresh state)",true);
    // when it was asked for
    const asked=Io.Clock.real.now(io).nanoseconds;
    b.dir.writeFile(io,.{.sub_path=link.wantFrame,.data=""}) catch return toolText(w,id,"could not ask for a frame",true);
    // how long has been waited (ms)
    var waited:u32=0;
    while(waited<frameWaitMs):(waited+=lookMs){
      io.sleep(.fromMilliseconds(lookMs),.awake)catch{};
      // the ask still there: not taken yet
      if(b.dir.access(io,link.wantFrame,.{}))|_|continue else|_|{}
      // the picture, once written after the ask
      const st=b.dir.statFile(io,link.frameFile,.{}) catch continue;
      if(st.mtime.nanoseconds<asked)continue;
      const png=b.dir.readFileAlloc(io,link.frameFile,gpa,.limited(maxFrame)) catch continue;
      defer gpa.free(png);
      return picture(gpa,w,id,png);
    }
    b.dir.deleteFile(io,link.wantFrame)catch{};
    return toolText(w,id,"the game did not answer with a frame in time",true);
  }
  /// pushes each message the gardener added since the last look, as a
  /// channel event, until cancelled
  fn watch(b:*Bridge,gpa:Allocator,io:Io)void{
    while(true){
      io.sleep(.fromMilliseconds(watchMs),.awake) catch return;
      if(!b.ready)continue;
      b.push(gpa,io)catch|e|std.log.warn("watching the gardener's messages: {t}",.{e});
    }
  }
  /// one look: each new message of the gardener's sent as a channel event
  fn push(b:*Bridge,gpa:Allocator,io:Io)!void{
    // the messages new since the last look
    var got:ArrayList([]u8)=.empty;
    defer link.freeAll(gpa,&got);
    try b.inbox.take(gpa,io,b.dir,link.toClaude,&got);
    for(got.items)|t|{
      // the event, written whole
      var aw:Writer.Allocating=.init(gpa);
      defer aw.deinit();
      try event(&aw.writer,t);
      b.send(io,aw.written());
    }
  }
};
/// a text as a JSON string literal, at compile time
fn jsonText(comptime s:[]const u8)[]const u8{
  comptime{
    @setEvalBranchQuota(100000);
    var out:[]const u8="\"";
    for(s)|c|out=out++switch(c){
      '"'=>"\\\"",
      '\\'=>"\\\\",
      '\n'=>"\\n",
      else=>&[_]u8{c},
    };
    return out++"\"";
  }
}
/// writes a result whose body is already JSON
fn result(w:*Writer,id:Value,comptime body:[]const u8)!void{
  try w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
  try stringify(id,.{},w);
  try w.writeAll(",\"result\":"++body++"}");
}
/// writes an error answer
fn rpcError(w:*Writer,id:Value,code:i32,msg:[]const u8)!void{
  try w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
  try stringify(id,.{},w);
  try w.print(",\"error\":{{\"code\":{d},\"message\":",.{code});
  try stringify(msg,.{},w);
  try w.writeAll("}}");
}
/// writes a tool's answer as text (an error when `bad`)
fn toolText(w:*Writer,id:Value,text:[]const u8,bad:bool)!void{
  try w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
  try stringify(id,.{},w);
  try w.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":");
  try stringify(text,.{},w);
  try w.print("}}],\"isError\":{}}}}}",.{bad});
}
/// writes a tool's answer as a PNG picture
fn picture(gpa:Allocator,w:*Writer,id:Value,png:[]const u8)!void{
  // the picture, as base64
  const enc=try gpa.alloc(u8,base64.calcSize(png.len));
  defer gpa.free(enc);
  _=base64.encode(enc,png);
  try w.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
  try stringify(id,.{},w);
  try w.writeAll(",\"result\":{\"content\":[{\"type\":\"image\",\"mimeType\":\"image/png\",\"data\":\"");
  try w.writeAll(enc);
  try w.writeAll("\"}]}}");
}
/// a JSON number as a float, or null when it is none
fn num(v:Value)?f64{
  return switch(v){.integer=>|i|@floatFromInt(i),.float=>|x|x,else=>null};
}
/// the names of the one-number words of a view's ask (tools/orbit.zig `Ask`)
const viewNums=[_][]const u8{"dist","yaw","pitch","zoom"};
/// the names of the three-number words
const viewTriples=[_][]const u8{"at","pan"};
/// writes `editor_view`'s arguments as the ask's text the editor reads
fn viewText(args:?ObjectMap,w:*Writer)error{BadView,WriteFailed}!void{
  const a=args orelse return;
  if(a.get("home"))|h|switch(h){.bool=>|on|if(on)try w.writeAll("home\n"),else=>return error.BadView};
  if(a.get("focus"))|f|switch(f){.integer=>|n|try w.print("focus {d}\n",.{n}),else=>return error.BadView};
  for(viewTriples)|word|if(a.get(word))|v|{
    // three numbers, no more or fewer
    const xs=switch(v){.array=>|l|l.items,else=>return error.BadView};
    if(xs.len!=3)return error.BadView;
    try w.print("{s}",.{word});
    for(xs)|x|try w.print(" {d}",.{num(x) orelse return error.BadView});
    try w.writeByte('\n');
  };
  for(viewNums)|word|if(a.get(word))|v|try w.print("{s} {d}\n",.{word,num(v) orelse return error.BadView});
}
/// writes the channel event for one of the gardener's messages
fn event(w:*Writer,text:[]const u8)!void{
  try w.writeAll("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/claude/channel\",\"params\":{\"content\":");
  try stringify(text,.{},w);
  try w.writeAll(",\"meta\":{\"from\":\"gardener\"}}}");
}
/// whether the game wrote its state lately (running, linked)
fn fresh(io:Io,dir:Dir)bool{
  // the state's last change, and now
  const st=dir.statFile(io,link.stateFile,.{}) catch return false;
  const now=Io.Clock.real.now(io).nanoseconds;
  return now-st.mtime.nanoseconds<freshS*std.time.ns_per_s;
}
/// opens the link folder, then answers Claude Code
/// line by line until stdin closes, the watcher pushing beside it
pub fn main(init:std.process.Init)!void{
  // the allocator, and the I/O
  const gpa=init.gpa;
  const io=init.io;
  // the link folder, in the working directory (the project, as the game's)
  Dir.cwd().createDirPath(io,link.folder)catch{};
  var dir=try Dir.cwd().openDir(io,link.folder,.{});
  defer dir.close(io);
  // stdout and stdin, buffered
  var outBuf:[1<<16]u8=undefined;
  var out=Io.File.stdout().writerStreaming(io,&outBuf);
  const inBuf=try gpa.alloc(u8,maxLine);
  defer gpa.free(inBuf);
  var in=Io.File.stdin().readerStreaming(io,inBuf);
  var b=Bridge{.dir=dir,.out=&out.interface};
  // only what the gardener says from now on is pushed
  b.inbox.skip(io,dir,link.toClaude);
  // the watcher, beside the reading
  var watcher=try io.concurrent(Bridge.watch,.{&b,gpa,io});
  defer watcher.cancel(io);
  while(in.interface.takeDelimiter('\n') catch null)|raw|{
    // one message, its carriage return gone
    const line=std.mem.trim(u8,raw,"\r ");
    if(line.len==0)continue;
    var aw:Writer.Allocating=.init(gpa);
    defer aw.deinit();
    b.handle(gpa,io,line,&aw.writer)catch|e|std.log.err("answering: {t}",.{e});
    if(aw.written().len>0)b.send(io,aw.written());
  }
}
/// a bridge on a scratch folder, answering into a buffer
fn testBridge(dir:Dir,out:*Writer)Bridge{return.{.dir=dir,.out=out};}
/// one answer to `line`, read back as JSON
fn ask(b:*Bridge,line:[]const u8)!std.json.Parsed(Value){
  var aw:Writer.Allocating=.init(testing.allocator);
  defer aw.deinit();
  try b.handle(testing.allocator,testing.io,line,&aw.writer);
  return parseFromSlice(Value,testing.allocator,aw.written(),.{});
}
test"initialize offers the channel and the tools"{
  var tmp=testing.tmpDir(.{});
  defer tmp.cleanup();
  var sink:Writer.Allocating=.init(testing.allocator);
  defer sink.deinit();
  var b=testBridge(tmp.dir,&sink.writer);
  const p=try ask(&b,"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2026-07-28\"}}");
  defer p.deinit();
  const r=p.value.object.get("result").?.object;
  try testing.expectEqualStrings(protocol,r.get("protocolVersion").?.string);
  try testing.expect(r.get("capabilities").?.object.get("experimental").?.object.get("claude/channel")!=null);
  try testing.expect(r.get("instructions").?.string.len>0);
  try testing.expectEqual(@as(i64,1),p.value.object.get("id").?.integer);
}
test"tools are listed, unknown methods refused, notifications unanswered"{
  var tmp=testing.tmpDir(.{});
  defer tmp.cleanup();
  var sink:Writer.Allocating=.init(testing.allocator);
  defer sink.deinit();
  var b=testBridge(tmp.dir,&sink.writer);
  const l=try ask(&b,"{\"jsonrpc\":\"2.0\",\"id\":\"a\",\"method\":\"tools/list\"}");
  defer l.deinit();
  try testing.expectEqual(@as(usize,6),l.value.object.get("result").?.object.get("tools").?.array.items.len);
  // every answer is one line: the protocol splits messages on line breaks
  var one:Writer.Allocating=.init(testing.allocator);
  defer one.deinit();
  try b.handle(testing.allocator,testing.io,"{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/list\"}",&one.writer);
  try testing.expect(std.mem.indexOfScalar(u8,one.written(),'\n')==null);
  one.clearRetainingCapacity();
  try b.handle(testing.allocator,testing.io,"{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"initialize\"}",&one.writer);
  try testing.expect(std.mem.indexOfScalar(u8,one.written(),'\n')==null);
  const u=try ask(&b,"{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"nope\"}");
  defer u.deinit();
  try testing.expectEqual(@as(i64,-32601),u.value.object.get("error").?.object.get("code").?.integer);
  // a notification owes nothing, and marks Claude Code ready
  var aw:Writer.Allocating=.init(testing.allocator);
  defer aw.deinit();
  try b.handle(testing.allocator,testing.io,"{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",&aw.writer);
  try testing.expectEqual(@as(usize,0),aw.written().len);
  try testing.expect(b.ready);
  // a broken line is answered with a parse error
  const bad=try ask(&b,"{oops");
  defer bad.deinit();
  try testing.expectEqual(@as(i64,-32700),bad.value.object.get("error").?.object.get("code").?.integer);
}
test"a view's arguments become the ask's lines; a bad one is refused"{
  // the arguments, read as Claude Code sends them
  const p=try parseFromSlice(Value,testing.allocator,"{\"home\":true,\"focus\":2,\"at\":[0,0.1,0],\"yaw\":45,\"zoom\":-1.5}",.{});
  defer p.deinit();
  var buf:[256]u8=undefined;
  var w:Writer=.fixed(&buf);
  try viewText(p.value.object,&w);
  try testing.expectEqualStrings("home\nfocus 2\nat 0 0.1 0\nyaw 45\nzoom -1.5\n",w.buffered());
  const bad=try parseFromSlice(Value,testing.allocator,"{\"pan\":[1,2]}",.{});
  defer bad.deinit();
  var w2:Writer=.fixed(&buf);
  try testing.expectError(error.BadView,viewText(bad.value.object,&w2));
}
test"reply lands in the game's file; state needs a running game"{
  var tmp=testing.tmpDir(.{});
  defer tmp.cleanup();
  var sink:Writer.Allocating=.init(testing.allocator);
  defer sink.deinit();
  var b=testBridge(tmp.dir,&sink.writer);
  const r=try ask(&b,"{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"reply\",\"arguments\":{\"text\":\"hi \\\"angel\\\"\"}}}");
  defer r.deinit();
  try testing.expect(!r.value.object.get("result").?.object.get("isError").?.bool);
  // what the game will read
  var ib=link.Inbox{};
  var got:ArrayList([]u8)=.empty;
  defer link.freeAll(testing.allocator,&got);
  try ib.take(testing.allocator,testing.io,tmp.dir,link.fromClaude,&got);
  try testing.expectEqualStrings("hi \"angel\"",got.items[0]);
  // no state yet: the game is not running
  const s0=try ask(&b,"{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"game_state\"}}");
  defer s0.deinit();
  try testing.expect(s0.value.object.get("result").?.object.get("isError").?.bool);
  try tmp.dir.writeFile(testing.io,.{.sub_path=link.stateFile,.data="mode roam\n"});
  const s1=try ask(&b,"{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"game_state\"}}");
  defer s1.deinit();
  const c=s1.value.object.get("result").?.object.get("content").?.array.items[0].object;
  try testing.expectEqualStrings("mode roam\n",c.get("text").?.string);
  // a reply with no text is refused, not sent
  const e=try ask(&b,"{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"reply\",\"arguments\":{}}}");
  defer e.deinit();
  try testing.expect(e.value.object.get("result").?.object.get("isError").?.bool);
}
test"an editor's document is read; an edit needs its text and a linked editor"{
  var tmp=testing.tmpDir(.{});
  defer tmp.cleanup();
  var sink:Writer.Allocating=.init(testing.allocator);
  defer sink.deinit();
  var b=testBridge(tmp.dir,&sink.writer);
  // nothing linked: refused
  const d0=try ask(&b,"{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"editor_document\"}}");
  defer d0.deinit();
  try testing.expect(d0.value.object.get("result").?.object.get("isError").?.bool);
  // an editor linked: its state fresh, its document read whole
  try tmp.dir.writeFile(testing.io,.{.sub_path=link.stateFile,.data="editor: meshedit\n"});
  try tmp.dir.writeFile(testing.io,.{.sub_path=link.documentFile,.data="# mesh\ncell 0.01\n"});
  const d1=try ask(&b,"{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/call\",\"params\":{\"name\":\"editor_document\"}}");
  defer d1.deinit();
  const c=d1.value.object.get("result").?.object.get("content").?.array.items[0].object;
  try testing.expectEqualStrings("# mesh\ncell 0.01\n",c.get("text").?.string);
  // an edit with no text is refused, and nothing is left for the editor
  const e=try ask(&b,"{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"editor_edit\",\"arguments\":{}}}");
  defer e.deinit();
  try testing.expect(e.value.object.get("result").?.object.get("isError").?.bool);
  try testing.expectError(error.FileNotFound,tmp.dir.access(testing.io,link.editFile,.{}));
}
test"the gardener's messages are pushed once each, as channel events"{
  var tmp=testing.tmpDir(.{});
  defer tmp.cleanup();
  var sink:Writer.Allocating=.init(testing.allocator);
  defer sink.deinit();
  var b=testBridge(tmp.dir,&sink.writer);
  try link.append(testing.io,tmp.dir,link.toClaude,"before the bridge");
  b.inbox.skip(testing.io,tmp.dir,link.toClaude);
  try link.append(testing.io,tmp.dir,link.toClaude,"what is \"that\"?");
  try b.push(testing.allocator,testing.io);
  try b.push(testing.allocator,testing.io);
  // one line pushed, the earlier message never
  const lines=sink.written();
  try testing.expectEqual(@as(usize,1),std.mem.count(u8,lines,"\n"));
  const p=try parseFromSlice(Value,testing.allocator,lines[0..lines.len-1],.{});
  defer p.deinit();
  try testing.expectEqualStrings("notifications/claude/channel",p.value.object.get("method").?.string);
  try testing.expectEqualStrings("what is \"that\"?",p.value.object.get("params").?.object.get("content").?.string);
}
test"a frame asked of no game gives up at once"{
  var tmp=testing.tmpDir(.{});
  defer tmp.cleanup();
  var sink:Writer.Allocating=.init(testing.allocator);
  defer sink.deinit();
  var b=testBridge(tmp.dir,&sink.writer);
  const f=try ask(&b,"{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"game_frame\"}}");
  defer f.deinit();
  try testing.expect(f.value.object.get("result").?.object.get("isError").?.bool);
  try testing.expectError(error.FileNotFound,tmp.dir.access(testing.io,link.wantFrame,.{}));
}
