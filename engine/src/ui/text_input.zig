//! a text input: the characters typed into it each frame (the window's one
//! stream of typing, `platform.input`), the last one taken back on erase,
//! and enter handing the text on. Where its text and caret sit in its box
//! follows its alignment: from the left-hand side, the centre or the
//! right-hand side. Which characters it may hold is its owner's to say.
/// the standard library
const std=@import("std");
/// a box in screen pixels: where the input sits
const Box=@import("box.zig").Box;
/// which side of its box an input's text (and so its caret) keeps to
pub const Align=enum{
  /// the text starts at the box's left-hand side, the caret after it
  left,
  /// the text is centred in the box, the caret after it
  centre,
  /// the text ends at the box's right-hand side, the caret there
  right,
};
/// what one frame brought an input: the characters typed, and whether
/// erase or enter went down (the game reads them from its own bindings)
pub const Keys=struct{
  /// the characters typed this frame, in order
  typed:[]const u21=&.{},
  /// the last character is to be taken back
  erase:bool=false,
  /// the text is to be handed on (enter)
  confirm:bool=false,
};
/// what feeding an input a frame did to it
pub const Fed=enum{
  /// nothing: no character it may hold, nothing to erase
  same,
  /// its text changed
  changed,
  /// enter: its text is to be processed
  submitted,
};
/// a text input holding up to `cap` bytes, of the characters `accept`
/// lets in (the byte each stands for, or null to refuse it)
pub fn TextInput(comptime cap:usize,comptime accept:fn(u21)?u8)type{
  return struct{
    /// this input's own type
    const Self=@This();
    /// the text's bytes; only the first `len` are real
    buf:[cap]u8=undefined,
    /// how many bytes the text holds
    len:usize=0,
    /// which side of its box the text and caret keep to
    alignment:Align=.centre,
    /// the text typed so far
    pub fn slice(t:*const Self)[]const u8{return t.buf[0..t.len];}
    /// `c` typed at the end, if it may be held and there is room
    pub fn put(t:*Self,c:u21)void{
      if(t.len==cap)return;
      t.buf[t.len]=accept(c) orelse return;
      t.len+=1;
    }
    /// the last character taken back
    pub fn erase(t:*Self)void{t.len-|=1;}
    /// emptied
    pub fn clear(t:*Self)void{t.len=0;}
    /// a frame's typing: each character put, erase taken back after them,
    /// then enter handing the text on
    pub fn feed(t:*Self,k:Keys)Fed{
      // how long the text was before this frame
      const was=t.len;
      for(k.typed)|c|t.put(c);
      if(k.erase)t.erase();
      if(k.confirm)return.submitted;
      return if(t.len!=was).changed else.same;
    }
    /// where its text starts (x, pixels) in `b`, `textW` pixels wide, `pad`
    /// in from the side it keeps to
    pub fn textX(t:*const Self,b:Box,textW:f32,pad:f32)f32{
      return switch(t.alignment){
        .left=>b.x+pad,
        .centre=>b.x+(b.w-textW)/2,
        .right=>b.x+b.w-pad-textW,
      };
    }
    /// where its caret sits (x, pixels) in `b`: just after the text
    pub fn caretX(t:*const Self,b:Box,textW:f32,pad:f32)f32{return t.textX(b,textW,pad)+textW;}
  };
}
/// the test helpers
const testing=std.testing;
/// a test input's characters: lower-case letters only
fn letters(c:u21)?u8{return if(c>='a' and c<='z')@intCast(c)else null;}
test"a text input takes what it may hold, erases, hands on with enter and keeps its caret to its side"{
  // a four-letter input
  var t=TextInput(4,letters){};
  try testing.expectEqual(Fed.changed,t.feed(.{.typed=&.{'m','O','o','s','s','y'}}));
  try testing.expectEqualStrings("moss",t.slice());
  try testing.expectEqual(Fed.changed,t.feed(.{.erase=true}));
  try testing.expectEqual(Fed.same,t.feed(.{.typed=&.{'1'}}));
  try testing.expectEqual(Fed.submitted,t.feed(.{.typed=&.{'k'},.confirm=true}));
  try testing.expectEqualStrings("mosk",t.slice());
  // a 100 pixel box from x 10, its text 40 wide, 5 in from its side
  const b:Box=.{.x=10,.y=0,.w=100,.h=20};
  t.alignment=.left;
  try testing.expectEqual(@as(f32,55),t.caretX(b,40,5));
  t.alignment=.centre;
  try testing.expectEqual(@as(f32,40),t.textX(b,40,5));
  t.alignment=.right;
  try testing.expectEqual(@as(f32,105),t.caretX(b,40,5));
  t.clear();
  try testing.expectEqual(@as(usize,0),t.slice().len);
}
