//! `--link` in the editors (meshedit, animedit): the editor talking with
//! Claude through the same link folder the game uses (`game/link.zig`,
//! the bridge `tools/bridge.zig`). The gardener types in the editor's own
//! chat (Enter, as in the game, or the grave key opens it; Enter sends, Esc
//! closes; while a name field is open Enter is the field's); Claude answers
//! into it. The editor keeps `state.txt` (what is open) and
//! `document.txt` (the sculpt or clip as its file would hold it) fresh,
//! answers a frame asked for, turns its camera as Claude asks
//! (`view.txt`), and takes a whole edited document Claude
//! leaves in `edit.txt` as one step of its history, so ctrl+z takes back
//! anything Claude did.
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the standard library, reached through the game's hub
const std=ps.std;
/// the allocator type everything is made with
const Allocator=std.mem.Allocator;
/// the I/O interface every file call goes through
const Io=std.Io;
/// a directory handle (the working directory the link folder sits in)
const Dir=Io.Dir;
/// the engine package, reached through the hub
const engine=ps.engine;
/// all the maths: conversions
const m=engine.core.math;
/// the keys and buttons down this frame
const Input=engine.platform.input.Input;
/// the UI's draw batch, and text widths
const Draw=engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=ps.style;
/// the link's files, chat and messages
const link=ps.link;
/// PNG pictures: the frame written, made small first
const png=engine.core.png;
/// the renderer's captured frame
const Shot=ps.renderer.Shot;
/// the editors' typing keys (shared with their name fields)
const labels=@import("labels.zig");
/// Claude's ask of the editor's camera
const Ask=@import("orbit.zig").Ask;
/// the log, for a link file that cannot be written
const log=std.log;
/// how often the state and the document are rewritten (s)
const stateEvery:f32=1;
/// the chat card's width and top (pixels), and its lines' height
const cardW:f32=560;
/// (see `cardW`)
const cardTop:f32=12;
/// (see `cardW`)
const lineH:f32=18;
/// how far the card's text stands in from its edges (pixels)
const pad:f32=14;
/// how many lines of the conversation the card shows
const shownLines=6;
/// how many characters a line of the card holds
const perLine=72;
/// the largest edited document taken (bytes)
const maxEdit=1<<20;
/// where across the screen the card's middle sits (a share of its width:
/// right of the middle, clear of the editors' panels on the left)
const cardAt:f32=0.6;
/// the card's trellis seed (its own vines)
const cardSeed:f32=0.37;
/// whether the editor's own name field holds the keyboard (then Enter is
/// its, not the chat's)
pub const Field=enum{
  /// no field open: Enter opens the chat
  free,
  /// a form, bone, mark or the sculpt's name being typed
  typing,
};
/// the editor's half of the link: the folder, the conversation and the
/// clock the state is rewritten by
pub const EditLink=struct{
  /// the game's link: the folder, Claude's answers read so far, a frame asked for
  link:link.Link,
  /// the conversation, and what the gardener is typing
  chat:link.Chat=.{},
  /// whether the gardener is typing into the chat now
  open:bool=false,
  /// seconds since the state and the document were rewritten
  since:f32=stateEvery,
  /// room for the folder's path, for the log
  whereBuf:[link.maxWhere]u8=undefined,
  /// opens (making it) the link folder in the working directory
  pub fn init(el:*EditLink,io:Io)link.Error!void{
    // (made in place: the folder's path is kept in it)
    el.chat=.{};
    el.open=false;
    el.since=stateEvery;
    const where=link.here(io,&el.whereBuf);
    el.link=try link.Link.open(io,Dir.cwd(),where);
    // a stale edit or answer from an earlier run is let go
    el.link.dir.deleteFile(io,link.editFile)catch{};
    el.link.dir.deleteFile(io,link.editResultFile)catch{};
    log.info("link: talking with Claude through {s}\\{s}",.{where,link.folder});
  }
  /// lets go of the folder
  pub fn deinit(el:*EditLink,io:Io)void{el.link.close(io);}
  /// the chat's keys this frame: Enter (as in the game) or the grave key
  /// opens it, Enter sends what was typed, Esc closes it; while the
  /// editor's own name field holds the keyboard (`field`), Enter is its
  /// and nothing opens. True while the chat holds the keyboard (the
  /// editor's own keys wait)
  pub fn keys(el:*EditLink,io:Io,in:*const Input,at:f64,field:Field)bool{
    if(!el.open){
      if(field==.typing)return false;
      if(in.pressed(.{.key=.grave_accent}) or in.pressed(.{.key=.enter}) or in.pressed(.{.key=.kp_enter}))el.open=true;
      return el.open;
    }
    if(in.pressed(.{.key=.escape})){
      el.open=false;
      return true;
    }
    if(in.pressed(.{.key=.enter}) or in.pressed(.{.key=.kp_enter})){
      // what was typed, sent unless empty
      const t=el.chat.typed.slice();
      if(t.len>0)el.link.say(io,&el.chat,t,at)catch|e|log.warn("link: {t}",.{e});
      el.chat.typed.clear();
      el.open=false;
      return true;
    }
    _=el.chat.typed.feed(labels.keys(in));
    return true;
  }
  /// one frame of the link: Claude's answers and a frame asked for looked
  /// for; true when the state and the document are due again (`publish`)
  pub fn tick(el:*EditLink,gpa:Allocator,io:Io,dt:f32,at:f64)bool{
    if(el.link.step(dt))el.link.poll(gpa,io,&el.chat,at)catch|e|log.warn("link: {t}",.{e});
    el.since+=dt;
    if(el.since<stateEvery)return false;
    el.since=0;
    return true;
  }
  /// the state and the document rewritten (`state`, `doc`: what the
  /// editor shows and holds now)
  pub fn publish(el:*EditLink,io:Io,state:[]const u8,doc:[]const u8)void{
    el.link.writeState(io,state)catch{};
    el.link.dir.writeFile(io,.{.sub_path=link.documentFile,.data=doc})catch|e|log.warn("link: document NOT written: {t}",.{e});
  }
  /// whether Claude asked for a frame not yet taken
  pub fn wantsFrame(el:*const EditLink)bool{return el.link.frameWanted;}
  /// the frame asked for, written at half size (whole before it takes its name)
  pub fn sendFrame(el:*EditLink,gpa:Allocator,io:Io,sh:Shot)void{
    defer el.link.frameTaken(io);
    // the frame made small, then encoded
    const px=png.shrink(gpa,sh.px,sh.w,sh.h,2)catch{return;};
    defer gpa.free(px);
    const bytes=png.encode(gpa,sh.w/2,sh.h/2,px,if(sh.bgra).bgra else.rgba)catch{return;};
    defer gpa.free(bytes);
    el.link.dir.writeFile(io,.{.sub_path=link.frameTmp,.data=bytes})catch{return;};
    Dir.rename(el.link.dir,link.frameTmp,el.link.dir,link.frameFile,io)catch{};
  }
  /// a whole edited document Claude left, if one waits (the caller's to
  /// free, then to `answer`)
  pub fn takeEdit(el:*EditLink,gpa:Allocator,io:Io)?[]u8{
    return el.link.dir.readFileAlloc(io,link.editFile,gpa,.limited(maxEdit))catch{return null;};
  }
  /// how Claude asked the camera to look, if an ask waits (taken away;
  /// one that will not read is let go, logged)
  pub fn takeView(el:*EditLink,io:Io)?Ask{
    // the ask's text (small)
    var buf:[1024]u8=undefined;
    const t=el.link.dir.readFile(io,link.viewFile,&buf)catch{return null;};
    el.link.dir.deleteFile(io,link.viewFile)catch|e|log.warn("link: view NOT taken away: {t}",.{e});
    return Ask.parse(t)catch|e|{
      log.warn("link: view: {t}",.{e});
      return null;
    };
  }
  /// tells Claude how its edit went (`result`), then takes the edit away
  /// (the bridge waits for it to go, then reads the answer)
  pub fn answer(el:*EditLink,io:Io,result:[]const u8)void{
    el.link.dir.writeFile(io,.{.sub_path=link.editResultFile,.data=result})catch|e|log.warn("link: answer NOT written: {t}",.{e});
    el.link.dir.deleteFile(io,link.editFile)catch{};
  }
  /// the chat card along the top: the conversation's last lines,
  /// and while open what is being typed (else a hint that it opens)
  pub fn draw(el:*const EditLink,d:*Draw,screen:m.Vice(f32,2))Allocator.Error!void{
    // the card's place and height
    const x=screen[0]*cardAt-cardW/2;
    const h=lineH*m.f(shownLines+1)+2*pad;
    try d.trellis(x,cardTop,cardW,h,s.card,cardSeed);
    // the conversation's lines, newest at the bottom, cut to what fits
    var lines:[shownLines]Line=undefined;
    const n=lastLines(el.chat.kept(),&lines);
    for(lines[0..n],0..)|l,i|{
      _=try d.text(x+pad,cardTop+pad+lineH*m.f(i),s.textSmall,if(l.claude)s.gold else s.white,l.text);
    }
    // the typing line, or the hint
    const ty=cardTop+pad+lineH*m.f(shownLines);
    if(el.open){
      const t=el.chat.typed.slice();
      const shownT=if(t.len>perLine)t[t.len-perLine..]else t;
      const end=try d.text(x+pad,ty,s.textSmall,s.white,shownT);
      try d.leaf(.{end+2,ty+12},-m.halfPi,11,5,s.leaf,0.8,0.2);
    }else _=try d.text(x+pad,ty,s.textSmall,s.dim,"ENTER TALKS WITH CLAUDE");
  }
};
/// one line of the card: its text and whether Claude said it
const Line=struct{
  /// the line's text
  text:[]const u8,
  /// whether it is Claude's
  claude:bool,
};
/// the conversation `said` cut into lines of `perLine` characters (at a
/// space where one falls near), the last `out.len` of them; how many
fn lastLines(said:[]const link.Said,out:[]Line)usize{
  // every line, walked from the newest message back, filled from the end
  var n:usize=0;
  var i=said.len;
  while(i>0 and n<out.len){
    i-=1;
    // this message's lines, cut from its end back
    const t=said[i].text();
    var cuts:[link.maxText/8+2]usize=undefined;
    var k:usize=0;
    var at:usize=0;
    cuts[0]=0;
    while(at<t.len){
      var end=@min(at+perLine,t.len);
      if(end<t.len)if(std.mem.lastIndexOfScalar(u8,t[at..end],' '))|sp|{
        if(sp>perLine/2)end=at+sp+1;
      };
      k+=1;
      cuts[k]=end;
      at=end;
    }
    var j=k;
    while(j>0 and n<out.len){
      j-=1;
      out[out.len-1-n]=.{.text=t[cuts[j]..cuts[j+1]],.claude=said[i].who==.claude};
      n+=1;
    }
  }
  // the lines moved to the front, oldest first
  std.mem.copyForwards(Line,out[0..n],out[out.len-n..]);
  return n;
}
test"a conversation is cut into the card's last lines, newest last, long ones at a space"{
  // the test helpers, and a chat of three messages
  const testing=std.testing;
  var c=link.Chat{};
  c.add(.gardener,"hello",0);
  c.add(.claude,"x"**(perLine-10)++" "++"y"**20,0);
  c.add(.gardener,"last",0);
  var out:[shownLines]Line=undefined;
  const n=lastLines(c.kept(),&out);
  try testing.expectEqual(@as(usize,4),n);
  try testing.expectEqualStrings("hello",out[0].text);
  try testing.expect(out[1].claude and out[2].claude);
  try testing.expectEqualStrings("y"**20,out[2].text);
  try testing.expectEqualStrings("last",out[3].text);
  // fewer room than lines: only the newest kept
  var two:[2]Line=undefined;
  try testing.expectEqual(@as(usize,2),lastLines(c.kept(),&two));
  try testing.expectEqualStrings("last",two[1].text);
}
