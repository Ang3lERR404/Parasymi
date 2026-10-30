//! per-frame input snapshot with edge detection, fed by GLFW. Keys and
//! buttons are asked about as a `Bind`; what each one does is the game's
//! business (`game/controls.zig`, read from `controls.cfg`).
const std=@import("std");
const log=std.log;
const EnumSet=std.enums.EnumSet;
const values=std.enums.values;
const eql=std.mem.eql;
const startsWith=std.mem.startsWith;
const stringToEnum=std.meta.stringToEnum;
const testing=std.testing;
const glfw=@import("zglfw");
pub const Key=glfw.Key;
pub const Button=glfw.MouseButton;
/// a mouse button's name in a binding is this prefix and the button's
/// (`mouse_left`); a key's is its GLFW name (`w`, `left_shift`, `F5`, `one`).
pub const mouse="mouse_";
/// one physical key or mouse button.
pub const Bind=union(enum){
  key:Key,
  button:Button,
  /// the bind named `name`, or null for no such key or button.
  pub fn parse(name:[]const u8)?Bind{
    if(startsWith(u8,name,mouse))if(stringToEnum(Button,name[mouse.len..]))|b|return.{.button=b};
    if(eql(u8,name,@tagName(Key.unknown)))return null;
    return if(stringToEnum(Key,name))|k|.{.key=k}else null;
  }
};
const Keys=EnumSet(Key);
/// most characters typed in one frame that are kept
pub const maxTyped=16;
const Buttons=EnumSet(Button);
pub const Input=struct{
  win:*glfw.Window,
  cur:Keys=.initEmpty(),
  prev:Keys=.initEmpty(),
  bcur:Buttons=.initEmpty(),
  bprev:Buttons=.initEmpty(),
  mouse:[2]f32=.{0,0},
  mouseDelta:[2]f32=.{0,0},
  scroll:f32=0,
  scrollAcc:f32=0,
  resized:bool=false,
  /// the characters typed this frame (text, not bindings), in order
  typedBuf:[maxTyped]u21=undefined,
  typedLen:u8=0,
  typingBuf:[maxTyped]u21=undefined,
  typingLen:u8=0,
  /// must be called once the Input has its final address.
  pub fn attach(in:*Input)void{
    in.win.setUserPointer(in);
    _=in.win.setScrollCallback(onScroll);
    _=in.win.setFramebufferSizeCallback(onResize);
    _=in.win.setCharCallback(onChar);
  }
  pub fn update(in:*Input)void{
    in.prev=in.cur;
    in.bprev=in.bcur;
    // decision: poll every key, so any key can be bound without a list here
    for(comptime values(Key))|k|if(k!=.unknown)in.cur.setPresent(k,in.win.getKey(k)==.press);
    for(comptime values(Button))|b|in.bcur.setPresent(b,in.win.getMouseButton(b)==.press);
    const mp=in.win.getCursorPos();
    const m:[2]f32=.{@floatCast(mp[0]),@floatCast(mp[1])};
    in.mouseDelta=.{m[0]-in.mouse[0],m[1]-in.mouse[1]};
    in.mouse=m;
    in.scroll=in.scrollAcc;
    in.scrollAcc=0;
    in.typedBuf=in.typingBuf;
    in.typedLen=in.typingLen;
    in.typingLen=0;
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
    };
  }
  /// did `b` go down this frame?
  pub fn pressed(in:*const Input,b:Bind)bool{
    return switch(b){
      .key=>|k|in.cur.contains(k)and!in.prev.contains(k),
      .button=>|k|in.bcur.contains(k)and!in.bprev.contains(k),
    };
  }
  /// headless tests: hold `b` down (or let it go) as of this frame.
  pub fn hold(in:*Input,b:Bind,on:bool)void{
    switch(b){
      .key=>|k|in.cur.setPresent(k,on),
      .button=>|k|in.bcur.setPresent(k,on),
    }
  }
  /// headless tests: start the next frame from this one, as `update` does.
  pub fn advance(in:*Input)void{
    in.prev=in.cur;
    in.bprev=in.bcur;
  }
  /// hide and hold the cursor for mouse look, or give it back.
  pub fn capture(in:*const Input,on:bool)void{
    // without capture the cursor stays visible; look still works while dragging
    in.win.setInputMode(.cursor,if(on).disabled else.normal)catch|e|log.warn("cursor capture: {t}",.{e});
  }
};
fn onScroll(w:*glfw.Window,_:f64,y:f64)callconv(.c)void{
  if(w.getUserPointer(Input))|in|in.scrollAcc+=@floatCast(y);
}
fn onChar(w:*glfw.Window,c:u32)callconv(.c)void{
  const in=w.getUserPointer(Input) orelse return;
  if(c<=0x10ffff)push(&in.typingBuf,&in.typingLen,@intCast(c));
}
/// appends `c` while there is room (more in one frame are dropped)
fn push(buf:*[maxTyped]u21,len:*u8,c:u21)void{
  if(len.*==maxTyped)return;
  buf[len.*]=c;
  len.*+=1;
}
fn onResize(w:*glfw.Window,_:c_int,_:c_int)callconv(.c)void{
  if(w.getUserPointer(Input))|in|in.resized=true;
}
test"binds parse by key and mouse button name"{
  try testing.expectEqual(Bind{.key=.left_shift},Bind.parse("left_shift").?);
  try testing.expectEqual(Bind{.key=.F5},Bind.parse("F5").?);
  try testing.expectEqual(Bind{.button=.right},Bind.parse("mouse_right").?);
  try testing.expectEqual(null,Bind.parse("unknown"));
  try testing.expectEqual(null,Bind.parse("mouse_nose"));
}
