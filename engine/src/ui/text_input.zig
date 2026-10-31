//! a text input: the characters typed into it each frame (the window's one
//! stream of typing, `platform.input`) going in at its caret, which the
//! arrows, home and end move (shift held, marking a selection as it goes).
//! Erase takes back the selection or the character before the caret, erase
//! ahead the one after it; all of it can be selected at once, cut, and text
//! pasted in at the caret; enter hands the text on. Where its text and caret
//! sit in its box follows its alignment: from the left-hand side, the centre
//! or the right-hand side. Which characters it may hold is its owner's to say.
/// the standard library
const std=@import("std");
/// walks UTF-8 text a character at a time, for what is pasted
const Utf8View=std.unicode.Utf8View;
/// moves bytes toward the front, for what follows a taken-out selection
const copyForwards=std.mem.copyForwards;
/// moves bytes toward the back, making room at the caret
const copyBackwards=std.mem.copyBackwards;
/// whether two runs of bytes are the same, to tell whether the text changed
const eql=std.mem.eql;
/// a box in screen pixels: where the input sits
const Box=@import("box.zig").Box;
/// which side of its box an input's text (and so its caret) keeps to
pub const Align=enum{
  /// the text starts at the box's left-hand side
  left,
  /// the text is centred in the box
  centre,
  /// the text ends at the box's right-hand side
  right,
};
/// where the caret is moved to
pub const Move=enum{
  /// back a character
  left,
  /// on a character
  right,
  /// before the first character
  home,
  /// after the last
  end,
};
/// what one frame brought an input: the characters typed, the caret moved,
/// what was erased, cut and pasted, and whether enter went down (the game
/// reads them from its own bindings)
pub const Keys=struct{
  /// the characters typed this frame, in order
  typed:[]const u21=&.{},
  /// the selection, else the character before the caret, is taken back
  erase:bool=false,
  /// the selection, else the character after the caret, is taken out
  eraseAhead:bool=false,
  /// where the caret moves, if anywhere
  move:?Move=null,
  /// the move marks a selection (shift held)
  extend:bool=false,
  /// all of the text is selected
  selectAll:bool=false,
  /// the selection is taken out (its owner copies it away first)
  cut:bool=false,
  /// text pasted in at the caret (UTF-8)
  paste:[]const u8=&.{},
  /// the text is to be handed on (enter)
  confirm:bool=false,
};
/// what feeding an input a frame did to it
pub const Fed=enum{
  /// its text is as it was (its caret may have moved)
  same,
  /// its text changed
  changed,
  /// enter: its text is to be processed
  submitted,
};
/// any text input, as what types into it sees it: fed a frame's keys, and
/// its selection read (to copy or cut it away). `TextInput.edit` makes one.
pub const Edit=struct{
  /// the input itself
  ctx:*anyopaque,
  /// feeds it a frame's keys
  feedFn:*const fn(*anyopaque,Keys)Fed,
  /// its selected text
  selectedFn:*const fn(*anyopaque)[]const u8,
  /// a frame's keys fed to it (`TextInput.feed`)
  pub fn feed(e:Edit,k:Keys)Fed{return e.feedFn(e.ctx,k);}
  /// its selected text (empty when nothing is selected)
  pub fn selected(e:Edit)[]const u8{return e.selectedFn(e.ctx);}
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
    /// where the caret sits: before byte `caret` (`len`: after the last)
    caret:usize=0,
    /// where the selection began, the caret at its other end (null: none)
    anchor:?usize=null,
    /// which side of its box the text and caret keep to
    alignment:Align=.centre,
    /// the text typed so far
    pub fn slice(t:*const Self)[]const u8{return t.buf[0..t.len];}
    /// the selection's ends, first then last (equal when there is none)
    pub fn selection(t:*const Self)[2]usize{
      // the end it was begun from
      const a=t.anchor orelse t.caret;
      return.{@min(a,t.caret),@max(a,t.caret)};
    }
    /// the selected text (empty when nothing is selected)
    pub fn selected(t:*const Self)[]const u8{
      // the selection's ends
      const s=t.selection();
      return t.buf[s[0]..s[1]];
    }
    /// takes the selection out, the caret where it was; false if none
    fn dropSelection(t:*Self)bool{
      // the selection's ends
      const s=t.selection();
      t.anchor=null;
      if(s[0]==s[1])return false;
      copyForwards(u8,t.buf[s[0]..],t.buf[s[1]..t.len]);
      t.len-=s[1]-s[0];
      t.caret=s[0];
      return true;
    }
    /// `c` typed at the caret (over the selection), if it may be held and
    /// there is room
    pub fn put(t:*Self,c:u21)void{
      // the byte it stands for
      const b=accept(c) orelse return;
      _=t.dropSelection();
      if(t.len==cap)return;
      copyBackwards(u8,t.buf[t.caret+1..t.len+1],t.buf[t.caret..t.len]);
      t.buf[t.caret]=b;
      t.len+=1;
      t.caret+=1;
    }
    /// the selection taken back, else the character before the caret
    pub fn erase(t:*Self)void{
      if(t.dropSelection() or t.caret==0)return;
      t.anchor=t.caret-1;
      _=t.dropSelection();
    }
    /// the selection taken out, else the character after the caret
    pub fn eraseAhead(t:*Self)void{
      if(t.dropSelection() or t.caret==t.len)return;
      t.anchor=t.caret+1;
      _=t.dropSelection();
    }
    /// the caret moved `mv`, marking a selection from where it was if
    /// `extend`; without it a selection is let go (a step left or right
    /// stops at its end)
    pub fn move(t:*Self,mv:Move,extend:bool)void{
      // the selection's ends, before the move
      const s=t.selection();
      if(extend){
        if(t.anchor==null)t.anchor=t.caret;
      }else if(t.anchor!=null){
        t.anchor=null;
        switch(mv){
          .left=>{t.caret=s[0];return;},
          .right=>{t.caret=s[1];return;},
          .home,.end=>{},
        }
      }
      t.caret=switch(mv){
        .left=>t.caret-|1,
        .right=>@min(t.caret+1,t.len),
        .home=>0,
        .end=>t.len,
      };
    }
    /// the caret set before byte `i` (kept within the text), nothing selected
    pub fn place(t:*Self,i:usize)void{
      t.caret=@min(i,t.len);
      t.anchor=null;
    }
    /// all of it selected, the caret at its end
    pub fn selectAll(t:*Self)void{
      t.anchor=0;
      t.caret=t.len;
    }
    /// emptied
    pub fn clear(t:*Self)void{
      t.len=0;
      t.caret=0;
      t.anchor=null;
    }
    /// a frame's keys: all selected, the caret moved, the selection cut,
    /// what is erased taken back, the paste and the typing put in at the
    /// caret, then enter handing the text on
    pub fn feed(t:*Self,k:Keys)Fed{
      // the text before this frame, to tell whether it changed
      var was:[cap]u8=undefined;
      const wasLen=t.len;
      @memcpy(was[0..wasLen],t.buf[0..wasLen]);
      if(k.selectAll)t.selectAll();
      if(k.move)|mv|t.move(mv,k.extend);
      if(k.cut)_=t.dropSelection();
      if(k.erase)t.erase();
      if(k.eraseAhead)t.eraseAhead();
      // what is pasted, a character at a time (nothing, if it is not UTF-8)
      if(Utf8View.init(k.paste))|v|{
        var it=v.iterator();
        while(it.nextCodepoint())|c|t.put(c);
      }else|_|{}
      for(k.typed)|c|t.put(c);
      if(k.confirm)return.submitted;
      return if(eql(u8,was[0..wasLen],t.slice())).same else.changed;
    }
    /// it as any text input (`Edit`), typed into through it
    pub fn edit(t:*Self)Edit{return.{.ctx=t,.feedFn=feedAny,.selectedFn=selectedAny};}
    /// `feed`, from an `Edit`
    fn feedAny(p:*anyopaque,k:Keys)Fed{
      // the input the edit stands for
      const t:*Self=@ptrCast(@alignCast(p));
      return t.feed(k);
    }
    /// `selected`, from an `Edit`
    fn selectedAny(p:*anyopaque)[]const u8{
      // the input the edit stands for
      const t:*Self=@ptrCast(@alignCast(p));
      return t.selected();
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
    /// which byte the caret goes before for a click at `x` in `b`, the text
    /// `textW` wide, each character `charW` wide
    pub fn at(t:*const Self,b:Box,textW:f32,pad:f32,x:f32,charW:f32)usize{
      // how far into the text the click is, in characters
      const n=(x-t.textX(b,textW,pad))/charW;
      return if(n<=0)0 else@min(@as(usize,@intFromFloat(@round(n))),t.len);
    }
  };
}
/// the test helpers
const testing=std.testing;
/// a test input's characters: lower-case letters only
fn letters(c:u21)?u8{return if(c>='a' and c<='z')@intCast(c)else null;}
test"a text input takes what it may hold, erases, hands on with enter and keeps its text to its side"{
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
  try testing.expectEqual(@as(f32,15),t.textX(b,40,5));
  t.alignment=.centre;
  try testing.expectEqual(@as(f32,40),t.textX(b,40,5));
  t.alignment=.right;
  try testing.expectEqual(@as(f32,65),t.textX(b,40,5));
  // a click a character and a half into it puts the caret after the second
  try testing.expectEqual(@as(usize,2),t.at(b,40,5,80,10));
  t.clear();
  try testing.expectEqual(@as(usize,0),t.slice().len);
}
test"the caret moves, typing and erasing go where it is, and a selection is typed over, cut and erased"{
  // an eight-letter input holding "moss"
  var t=TextInput(8,letters){};
  _=t.feed(.{.typed=&.{'m','o','s','s'}});
  _=t.feed(.{.move=.left});
  _=t.feed(.{.move=.left});
  _=t.feed(.{.typed=&.{'a'}});
  try testing.expectEqualStrings("moass",t.slice());
  _=t.feed(.{.eraseAhead=true});
  try testing.expectEqualStrings("moas",t.slice());
  _=t.feed(.{.move=.home});
  try testing.expectEqual(Fed.same,t.feed(.{.erase=true}));
  // shift and right twice selects "mo"; typing goes over it
  _=t.feed(.{.move=.right,.extend=true});
  _=t.feed(.{.move=.right,.extend=true});
  try testing.expectEqualStrings("mo",t.selected());
  _=t.feed(.{.typed=&.{'f'}});
  try testing.expectEqualStrings("fas",t.slice());
  // all selected and cut: empty; pasted text goes in, what it may not hold left out
  _=t.feed(.{.selectAll=true,.cut=true});
  try testing.expectEqualStrings("",t.slice());
  _=t.feed(.{.paste="Fern 2 frond"});
  try testing.expectEqualStrings("ernfrond",t.slice());
  // a selection let go by a step stops at its end
  _=t.feed(.{.move=.home});
  _=t.feed(.{.move=.end,.extend=true});
  _=t.feed(.{.move=.left});
  try testing.expectEqual(@as(usize,0),t.caret);
  t.place(3);
  _=t.feed(.{.erase=true});
  try testing.expectEqualStrings("erfrond",t.slice());
  // typed into as any input
  const e=t.edit();
  _=e.feed(.{.move=.home});
  _=e.feed(.{.move=.right,.extend=true});
  try testing.expectEqualStrings("e",e.selected());
  try testing.expectEqual(Fed.changed,e.feed(.{.typed=&.{'a'}}));
  try testing.expectEqualStrings("arfrond",t.slice());
}
