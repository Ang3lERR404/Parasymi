//! per-frame input snapshot with edge detection, fed by GLFW. Keys, mouse
//! buttons and the first gamepad's buttons are polled; held keys the system
//! repeats, the wheel and typing come by callback. Keys and
//! buttons are asked about as a `Bind`; what each one does is the game's
//! business (`game/controls.zig`, read from `controls.cfg`).
/// the standard library
const std=@import("std");
/// the maths: vectors (Vec), rows (Vice) and matrices (Mat)
const m=@import("../core/math.zig");
/// the log, for a cursor capture that fails
const log=std.log;
/// a set of enum tags, packed in bits
const EnumSet=std.enums.EnumSet;
/// every tag of an enum, as an array
const values=std.enums.values;
/// whether two runs of bytes are the same
const eql=std.mem.eql;
/// whether a run of bytes begins with another
const startsWith=std.mem.startsWith;
/// the enum tag a name spells, if any
const stringToEnum=std.meta.stringToEnum;
/// the test helpers
const testing=std.testing;
/// a text writer, for writing a bind's name
const Writer=std.Io.Writer;
/// GLFW: the window, keys and mouse buttons
const glfw=@import("zglfw");
/// a keyboard key, as GLFW names it
pub const Key=glfw.Key;
/// a mouse button, as GLFW names it
pub const Button=glfw.MouseButton;
/// a mouse button's name in a binding is this prefix and the button's
/// (`mouse_left`); a key's is its GLFW name (`w`, `left_shift`, `F5`, `one`).
pub const mouse="mouse_";
/// a gamepad's button, as GLFW names it (its standard layout: a, b, x, y,
/// the bumpers, back, start, the sticks pressed, the d-pad)
pub const PadButton=glfw.Gamepad.Button;
/// a gamepad button's name in a binding is this prefix and the button's
/// (`pad_a`, `pad_dpad_up`)
pub const pad="pad_";
/// one physical key, mouse button or gamepad button.
pub const Bind=union(enum){
  /// a key on the keyboard
  key:Key,
  /// a button on the mouse
  button:Button,
  /// a button on the gamepad
  pad:PadButton,
  /// the bind named `name`, or null for no such key or button.
  pub fn parse(name:[]const u8)?Bind{
    if(startsWith(u8,name,mouse))if(stringToEnum(Button,name[mouse.len..]))|b|return.{.button=b};
    if(startsWith(u8,name,pad))if(stringToEnum(PadButton,name[pad.len..]))|b|return.{.pad=b};
    if(eql(u8,name,@tagName(Key.unknown)))return null;
    return if(stringToEnum(Key,name))|k|.{.key=k}else null;
  }
  /// writes the bind's name to `w` as `parse` reads it back (`w`,
  /// `mouse_left`, `pad_a`)
  pub fn write(b:Bind,w:*Writer)Writer.Error!void{
    switch(b){
      .key=>|k|try w.writeAll(@tagName(k)),
      .button=>|k|try w.print(mouse++"{t}",.{k}),
      .pad=>|k|try w.print(pad++"{t}",.{k}),
    }
  }
  /// whether `b` is a gamepad's button (else the keyboard's or the mouse's)
  pub fn onPad(b:Bind)bool{return b==.pad;}
};
/// which keys are held, one bit a key
const Keys=EnumSet(Key);
/// most characters typed in one frame that are kept
pub const maxTyped=16;
/// which mouse buttons are held, one bit a button
const Buttons=EnumSet(Button);
/// which gamepad buttons are held, one bit a button
const PadButtons=EnumSet(PadButton);
/// a clipboard of a test's own: the text put on it
pub const Clip=struct{
  /// the text's bytes; only the first `len` are real
  buf:[maxClip]u8=undefined,
  /// how many bytes it holds
  len:usize=0,
  /// the text put on it
  pub fn slice(c:*const Clip)[]const u8{return c.buf[0..c.len];}
};
/// the longest text the clipboard is read or written with, in bytes
pub const maxClip=256;
/// what the keys, mouse and window did this frame and the last, sampled
/// once a frame by `update`; callbacks gather scroll, typing and resizes
pub const Input=struct{
  /// the window input is read from
  win:*glfw.Window,
  /// the keys held this frame
  cur:Keys=.initEmpty(),
  /// the keys held last frame
  prev:Keys=.initEmpty(),
  /// the mouse buttons held this frame
  bcur:Buttons=.initEmpty(),
  /// the mouse buttons held last frame
  bprev:Buttons=.initEmpty(),
  /// the cursor's position (window pixels)
  mouse:m.Vice(f32,2)=.{0,0},
  /// how far the cursor moved since last frame (window pixels)
  mouseDelta:m.Vice(f32,2)=.{0,0},
  /// how far the wheel turned this frame (notches; positive is away)
  scroll:f32=0,
  /// the wheel's turning gathered since the last `update`
  scrollAcc:f32=0,
  /// whether the window's framebuffer was resized (the game clears it)
  resized:bool=false,
  /// the characters typed this frame (text, not bindings), in order
  typedBuf:[maxTyped]u21=undefined,
  /// how many of `typedBuf` are filled
  typedLen:u8=0,
  /// the characters being typed for next frame, gathered by the callback
  typingBuf:[maxTyped]u21=undefined,
  /// how many of `typingBuf` are filled
  typingLen:u8=0,
  /// the keys the system repeated this frame, held long enough to type again
  rep:Keys=.initEmpty(),
  /// the keys being repeated for next frame, gathered by the callback
  repAcc:Keys=.initEmpty(),
  /// the gamepad's buttons held this frame (the first gamepad plugged in)
  pcur:PadButtons=.initEmpty(),
  /// the gamepad's buttons held last frame
  pprev:PadButtons=.initEmpty(),
  /// headless tests: a clipboard of their own instead of the window's
  ownClip:?*Clip=null,
  /// must be called once the Input has its final address.
  pub fn attach(in:*Input)void{
    in.win.setUserPointer(in);
    _=in.win.setScrollCallback(onScroll);
    _=in.win.setFramebufferSizeCallback(onResize);
    _=in.win.setCharCallback(onChar);
    _=in.win.setKeyCallback(onKey);
  }
  /// samples the keys, buttons and cursor for a new frame and moves what
  /// the callbacks gathered (scroll, typing) into it; last frame's state
  /// becomes `prev`
  pub fn update(in:*Input)void{
    in.prev=in.cur;
    in.bprev=in.bcur;
    // decision: poll every key, so any key can be bound without a list here
    for(comptime values(Key))|k|if(k!=.unknown)in.cur.setPresent(k,in.win.getKey(k)==.press);
    for(comptime values(Button))|b|in.bcur.setPresent(b,in.win.getMouseButton(b)==.press);
    // the cursor's position, as GLFW gives it and as floats
    const mp=in.win.getCursorPos();
    const at:m.Vice(f32,2)=.{@floatCast(mp[0]),@floatCast(mp[1])};
    in.mouseDelta=.{at[0]-in.mouse[0],at[1]-in.mouse[1]};
    in.mouse=at;
    in.scroll=in.scrollAcc;
    in.scrollAcc=0;
    in.typedBuf=in.typingBuf;
    in.typedLen=in.typingLen;
    in.typingLen=0;
    in.rep=in.repAcc;
    in.repAcc=.initEmpty();
    in.pprev=in.pcur;
    in.pcur=padHeld();
  }
  /// the buttons held on the first gamepad plugged in (none without one)
  fn padHeld()PadButtons{
    // the buttons held, filled from the first gamepad found
    var held=PadButtons.initEmpty();
    for(0..glfw.Joystick.maximum_supported)|i|{
      // this joystick, and it as a gamepad, if it is one
      const j:glfw.Joystick=@enumFromInt(@as(c_int,@intCast(i)));
      const gp=j.asGamepad() orelse continue;
      // its state; one that will not read is passed over
      const st=gp.getState() catch continue;
      for(comptime values(PadButton))|b|held.setPresent(b,st.buttons[@intFromEnum(b)]==.press);
      return held;
    }
    return held;
  }
  /// the characters typed this frame
  pub fn typed(in:*const Input)[]const u21{return in.typedBuf[0..in.typedLen];}
  /// headless tests: type `c` as of this frame.
  pub fn type1(in:*Input,c:u21)void{push(&in.typedBuf,&in.typedLen,c);}
  /// is `b` held this frame?
  pub fn down(in:*const Input,b:Bind)bool{
    return switch(b){
      .key=>|k|in.cur.contains(k),
      .button=>|k|in.bcur.contains(k),
      .pad=>|k|in.pcur.contains(k),
    };
  }
  /// did `b` go down this frame?
  pub fn pressed(in:*const Input,b:Bind)bool{
    return switch(b){
      .key=>|k|in.cur.contains(k)and!in.prev.contains(k),
      .button=>|k|in.bcur.contains(k)and!in.bprev.contains(k),
      .pad=>|k|in.pcur.contains(k)and!in.pprev.contains(k),
    };
  }
  /// was `b` let go this frame?
  pub fn released(in:*const Input,b:Bind)bool{
    return switch(b){
      .key=>|k|in.prev.contains(k)and!in.cur.contains(k),
      .button=>|k|in.bprev.contains(k)and!in.bcur.contains(k),
      .pad=>|k|in.pprev.contains(k)and!in.pcur.contains(k),
    };
  }
  /// did `b` go down this frame, or (a key held long enough) repeat?
  pub fn repeated(in:*const Input,b:Bind)bool{
    return in.pressed(b) or switch(b){
      .key=>|k|in.rep.contains(k),
      .button,.pad=>false,
    };
  }
  /// the first key, mouse button or gamepad button that went down this
  /// frame (keys first), if any: what a binding being set is set to
  pub fn anyPressed(in:*const Input)?Bind{
    for(comptime values(Key))|k|if(k!=.unknown and in.pressed(.{.key=k}))return.{.key=k};
    for(comptime values(Button))|k|if(in.pressed(.{.button=k}))return.{.button=k};
    for(comptime values(PadButton))|k|if(in.pressed(.{.pad=k}))return.{.pad=k};
    return null;
  }
  /// headless tests: hold `b` down (or let it go) as of this frame.
  pub fn hold(in:*Input,b:Bind,on:bool)void{
    switch(b){
      .key=>|k|in.cur.setPresent(k,on),
      .button=>|k|in.bcur.setPresent(k,on),
      .pad=>|k|in.pcur.setPresent(k,on),
    }
  }
  /// headless tests: start the next frame from this one, as `update` does.
  pub fn advance(in:*Input)void{
    in.prev=in.cur;
    in.bprev=in.bcur;
    in.pprev=in.pcur;
    in.rep=.initEmpty();
  }
  /// headless tests: key `k` repeats this frame, as if held long.
  pub fn repeat1(in:*Input,k:Key)void{in.rep.insert(k);}
  /// the text on the clipboard (empty without any), GLFW's until the next
  /// call; an input of its own clipboard (tests) gives what was put on it
  pub fn clipboard(in:*const Input)[]const u8{
    if(in.ownClip)|c|return c.slice();
    return in.win.getClipboardString() orelse "";
  }
  /// `text` put on the clipboard (no more than `maxClip` bytes of it)
  pub fn setClipboard(in:*const Input,text:[]const u8)void{
    // the text as GLFW takes it, its end marked by a zero
    var buf:[maxClip+1]u8=undefined;
    const n=@min(text.len,maxClip);
    @memcpy(buf[0..n],text[0..n]);
    buf[n]=0;
    if(in.ownClip)|c|{
      @memcpy(c.buf[0..n],buf[0..n]);
      c.len=n;
      return;
    }
    in.win.setClipboardString(buf[0..n:0]);
  }
  /// hide and hold the cursor for mouse look, or give it back.
  pub fn capture(in:*const Input,on:bool)void{
    // without capture the cursor stays visible; look still works while dragging
    in.win.setInputMode(.cursor,if(on).disabled else.normal)catch|e|log.warn("cursor capture: {t}",.{e});
  }
};
/// GLFW's scroll callback: gathers the wheel's turning for the next frame
fn onScroll(w:*glfw.Window,_:f64,y:f64)callconv(.c)void{
  if(w.getUserPointer(Input))|in|in.scrollAcc+=@floatCast(y);
}
/// GLFW's character callback: gathers a typed character for the next frame
fn onChar(w:*glfw.Window,c:u32)callconv(.c)void{
  // the input this window belongs to
  const in=w.getUserPointer(Input) orelse return;
  if(c<=0x10ffff)push(&in.typingBuf,&in.typingLen,@intCast(c));
}
/// GLFW's key callback: gathers the keys the system repeats (held long
/// enough to type again) for the next frame; presses and releases are
/// polled by `update`
fn onKey(w:*glfw.Window,k:Key,_:c_int,a:glfw.Action,_:glfw.Mods)callconv(.c)void{
  // the input this window belongs to
  const in=w.getUserPointer(Input) orelse return;
  if(a==.repeat and k!=.unknown)in.repAcc.insert(k);
}
/// appends `c` while there is room (more in one frame are dropped)
fn push(buf:*[maxTyped]u21,len:*u8,c:u21)void{
  if(len.*==maxTyped)return;
  buf[len.*]=c;
  len.*+=1;
}
/// GLFW's resize callback: marks the window resized
fn onResize(w:*glfw.Window,_:c_int,_:c_int)callconv(.c)void{
  if(w.getUserPointer(Input))|in|in.resized=true;
}
test"binds parse by key and mouse button name"{
  try testing.expectEqual(Bind{.key=.left_shift},Bind.parse("left_shift").?);
  try testing.expectEqual(Bind{.key=.F5},Bind.parse("F5").?);
  try testing.expectEqual(Bind{.button=.right},Bind.parse("mouse_right").?);
  try testing.expectEqual(null,Bind.parse("unknown"));
  try testing.expectEqual(null,Bind.parse("mouse_nose"));
  try testing.expectEqual(Bind{.pad=.dpad_up},Bind.parse("pad_dpad_up").?);
  try testing.expectEqual(Bind{.pad=.a},Bind.parse("pad_a").?);
  try testing.expectEqual(null,Bind.parse("pad_z"));
  // each written name parses back to the bind it was written from
  for([_]Bind{.{.key=.left_shift},.{.key=.F5},.{.button=.right},.{.pad=.dpad_up}})|b|{
    // room for the name, and the writer that fills it
    var buf:[32]u8=undefined;
    var w:Writer=.fixed(&buf);
    try b.write(&w);
    try testing.expectEqual(b,Bind.parse(w.buffered()).?);
  }
}
test"a bind goes down, repeats while held long, and is let go"{
  // an input without a window, of its own clipboard
  var clip=Clip{};
  var in:Input=.{.win=undefined,.ownClip=&clip};
  try testing.expectEqual(null,in.anyPressed());
  in.hold(.{.pad=.a},true);
  try testing.expect(in.pressed(.{.pad=.a}) and in.repeated(.{.pad=.a}));
  try testing.expectEqual(Bind{.pad=.a},in.anyPressed().?);
  in.advance();
  try testing.expect(in.down(.{.pad=.a})and!in.pressed(.{.pad=.a}));
  in.hold(.{.pad=.a},false);
  try testing.expect(in.released(.{.pad=.a}));
  // a key held long repeats, without going down again
  in.hold(.{.key=.left},true);
  in.advance();
  try testing.expect(!in.repeated(.{.key=.left}));
  in.repeat1(.left);
  try testing.expect(in.repeated(.{.key=.left})and!in.pressed(.{.key=.left}));
  in.setClipboard("moss");
  try testing.expectEqualStrings("moss",in.clipboard());
}
