//! the editors' toolbar: a column of buttons down the window's right side
//! (more columns leftwards when one runs out of room), each a bud, its
//! words and its key, on a trellis like the game's panels. A button does
//! just what its key does (`Bind` ties keys to the same acts), lit while
//! what it toggles is on, dim while it would do nothing. Also the backed
//! text the editors write their help and notes on, dark behind light words.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the allocator type drawing may fail with
const Allocator=std.mem.Allocator;
/// a set of acts: the lit ones, the live ones
const EnumSet=std.enums.EnumSet;
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// all the maths: maxima
const m=engine.core.math;
/// the keys and buttons held this frame
const Input=engine.platform.input.Input;
/// a keyboard key, named as the window library names it
const Key=engine.platform.input.Key;
/// the UI's draw batch, and text widths
const Draw=engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=engine.ui.draw.Color;
/// a box in screen pixels
const Box=engine.ui.box.Box;
/// the engine's button: the states a box is in under the pointer, and a click
const button=engine.ui.button;
/// the glyphs' height, unscaled (px)
const glyphH=engine.ui.font.glyphH;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the HUD's shared colours and type sizes
const s=ps.style;
/// the HUD's bud, drawn before each button's words
const bullet=ps.hud.bullet;
/// a button's words, and the backed text's
pub const text:f32=s.textSub;
/// a button's key, smaller beside its words
const keyText:f32=s.textNote;
/// one button's height (px)
const buttonH:f32=26;
/// the room before a group of buttons (px)
const groupGap:f32=10;
/// the gap round the window's edge (px)
const pad:f32=16;
/// the gap between two columns (px)
const colGap:f32=28;
/// the room the bud takes before the words (px)
const budW:f32=26;
/// the room between the words and the key, and after the key (px)
const keyGap:f32=18;
const tail:f32=8;
/// the bud's radius (px)
const budR:f32=6;
/// the most buttons and columns a bar holds
const cap=48;
const colCap=4;
/// how open a bud is at rest, and pressed
const restOpen:f32=0.15;
const pressedOpen:f32=0.7;
/// a button that would do nothing: its words and bud, greyed
const deadCol:Color=.{105,110,105,255};
/// the room round backed text (px)
const inset:f32=10;
/// one line of backed text's height (px)
pub const lineH:f32=22;
/// a key that does an act: the key, whether ctrl is held with it, and
/// whether shift must be (null: either way)
pub fn Bind(comptime Act:type)type{
  return struct{
    /// the key
    key:Key,
    /// ctrl held with it (exactly: ctrl+c is not c)
    ctrl:bool=false,
    /// shift held (true), not held (false), or either (null)
    shift:?bool=null,
    /// what it does
    act:Act,
    /// whether it went down this frame, held as it asks
    pub fn hit(b:@This(),in:*const Input)bool{
      if(!in.pressed(.{.key=b.key}))return false;
      if(held(in,.left_control,.right_control)!=b.ctrl)return false;
      return if(b.shift)|sh|held(in,.left_shift,.right_shift)==sh else true;
    }
  };
}
/// whether either of two keys (a left and a right) is held
fn held(in:*const Input,a:Key,b:Key)bool{return in.down(.{.key=a}) or in.down(.{.key=b});}
/// one button: the act it does, its words, its key, and whether a little
/// room goes before it (the first of a group)
pub fn Item(comptime Act:type)type{
  return struct{
    /// what it does
    act:Act,
    /// its words
    label:[]const u8,
    /// its key, as written beside it
    key:[]const u8="",
    /// the first of a group: a little room before it
    gap:bool=false,
    /// how wide it is (px)
    fn width(it:@This())f32{return budW+Draw.width(it.label,text)+keyGap+Draw.width(it.key,keyText)+tail;}
  };
}
/// a toolbar of buttons doing `Act`s: laid out each frame (`lay`), then
/// clicked (`click`) and drawn (`draw`)
pub fn Bar(comptime Act:type)type{
  return struct{
    /// this bar's own type
    const Self=@This();
    /// a set of acts
    pub const Set=EnumSet(Act);
    /// one button
    pub const Entry=Item(Act);
    /// the press being followed, for a click
    press:button.Press(Act)=.{},
    /// the buttons laid out this frame
    items:[]const Entry=&.{},
    /// where each stands (px)
    boxes:[cap]Box=undefined,
    /// each column's box (px), and how many there are
    cols:[colCap]Box=undefined,
    colCount:usize=0,
    /// the pointer as the last click saw it, for drawing each button's state
    seen:button.Pointer=.{},
    /// `items` laid down the window's right side from its top, a new
    /// column leftwards each time one would reach below `bottom` (px)
    pub fn lay(b:*Self,items:[]const Entry,screen:m.Vice(f32,2),bottom:f32)void{
      b.items=items[0..@min(items.len,cap)];
      // each button's column and top, each column's width and foot
      var col:usize=0;
      var y:f32=pad;
      var colOf:[cap]usize=undefined;
      var tops:[cap]f32=undefined;
      var widths:[colCap]f32=@splat(0);
      var feet:[colCap]f32=@splat(pad);
      for(b.items,0..)|it,i|{
        // the room before it (none at a column's top)
        const room:f32=if(it.gap and y>pad)groupGap else 0;
        if(y+room+buttonH>bottom and y>pad and col+1<colCap){
          col+=1;
          y=pad;
        }else y+=room;
        colOf[i]=col;
        tops[i]=y;
        widths[col]=@max(widths[col],it.width());
        y+=buttonH;
        feet[col]=y;
      }
      b.colCount=if(b.items.len>0)col+1 else 0;
      // the columns, right to left
      var x=screen[0]-pad;
      for(0..b.colCount)|c|{
        x-=widths[c];
        b.cols[c]=.{.x=x,.y=pad,.w=widths[c],.h=feet[c]-pad};
        x-=colGap;
      }
      for(b.items,0..)|_,i|b.boxes[i]=.{.x=b.cols[colOf[i]].x,.y=tops[i],.w=b.cols[colOf[i]].w,.h=buttonH};
    }
    /// whether `at` (px) is over the bar, where the scene doesn't answer
    pub fn over(b:*const Self,at:m.Vice(f32,2))bool{
      for(b.cols[0..b.colCount])|c|if(c.contains(at))return true;
      return false;
    }
    /// the live button under `at` (px), if any
    fn under(b:*const Self,at:m.Vice(f32,2),live:Set)?Act{
      for(b.items,0..)|it,i|if(live.contains(it.act) and b.boxes[i].contains(at))return it.act;
      return null;
    }
    /// the act clicked this frame (mouse1 let go over the live button it
    /// went down on), if any
    pub fn click(b:*Self,in:*const Input,live:Set)?Act{
      b.seen=pointer(in);
      return b.press.track(b.seen,b.under(in.mouse,live));
    }
    /// the bar drawn: a trellis behind each column, each button a bud, its
    /// words and its key, glowing under the mouse; `lit` ones gold, their
    /// buds open, ones not `live` greyed
    pub fn draw(b:*const Self,d:*Draw,lit:Set,live:Set)Allocator.Error!void{
      for(b.cols[0..b.colCount],0..)|c,i|try d.trellis(c.x-inset,c.y-inset,c.w+2*inset,c.h+2*inset,s.panel,0.45+m.f(i)*0.2);
      // the pointer, for each button's state
      const p=b.seen;
      for(b.items,0..)|it,i|{
        // where it stands, its state, and the middle of its line (px)
        const bx=b.boxes[i];
        const on=live.contains(it.act);
        const st=if(on)button.state(bx,p)else.idle;
        const cy=bx.y+buttonH/2;
        const isLit=lit.contains(it.act);
        if(st.over())try d.glow(bx.x+budW/2,cy,22,s.menuHover);
        // how open its bud is: open lit or under the mouse, half shut pressed
        const open:f32=if(st.down())pressedOpen else if(isLit or st.over())1 else restOpen;
        try bullet(d,bx.x+budW/2-4,cy,budR,if(!on)deadCol else if(isLit)s.gold else s.bud,open,bx.y*0.01);
        _=try d.text(bx.x+budW,cy-glyphH*text/2,text,if(!on)deadCol else if(isLit or st.over())s.gold else s.white,it.label);
        _=try d.text(bx.x+bx.w-tail-Draw.width(it.key,keyText),cy-glyphH*keyText/2,keyText,if(on)s.dim else deadCol,it.key);
      }
    }
  };
}
/// the main mouse button and the cursor this frame, as a button reads them
fn pointer(in:*const Input)button.Pointer{
  return.{.at=in.mouse,.down=in.down(.{.button=.left}),.went=in.pressed(.{.button=.left}),.up=in.released(.{.button=.left})};
}
/// one line of backed text: its words and their colour
pub const Line=struct{
  /// the words
  words:[]const u8,
  /// their colour
  col:Color=s.white,
  /// their size
  size:f32=text,
};
/// each of `words` a white line, for `backed`
pub fn lines(comptime words:[]const[]const u8)[words.len]Line{
  // the lines, filled one by one
  var out:[words.len]Line=undefined;
  for(words,0..)|w,i|out[i]=.{.words=w};
  return out;
}
/// `lines` written from (`x`,`y`) on a dark trellis just big enough for
/// them, so they read over the bright sky; where the trellis ends below (px)
pub fn backed(d:*Draw,x:f32,y:f32,list:[]const Line)Allocator.Error!f32{
  // the widest line (px)
  var w:f32=0;
  for(list)|l|w=@max(w,Draw.width(l.words,l.size));
  if(list.len==0)return y;
  // how tall the lines are (px)
  const h=m.f(list.len)*lineH;
  try d.trellis(x-inset,y-inset,w+2*inset,h+inset,s.panel,0.8);
  for(list,0..)|l,i|_=try d.text(x,y+m.f(i)*lineH,l.size,l.col,l.words);
  return y+h;
}
/// the test helpers
const testing=std.testing;
test"buttons stack down the right side and spill into a second column leftwards"{
  // three acts, and a bar of them
  const A=enum{one,two,three};
  var b=Bar(A){};
  const items=[_]Bar(A).Entry{.{.act=.one,.label="one",.key="1"},.{.act=.two,.label="two",.key="2",.gap=true},.{.act=.three,.label="three",.key="3"}};
  b.lay(&items,.{800,600},600);
  try testing.expectEqual(@as(usize,1),b.colCount);
  try testing.expect(b.boxes[1].y>=b.boxes[0].y+buttonH+groupGap);
  try testing.expect(b.boxes[0].x+b.boxes[0].w<=800-pad);
  // too short a window: the third starts a column to the left of the first
  b.lay(&items,.{800,600},pad+2*buttonH+groupGap+1);
  try testing.expectEqual(@as(usize,2),b.colCount);
  try testing.expect(b.boxes[2].x+b.boxes[2].w<b.boxes[0].x);
  try testing.expect(b.over(b.boxes[2].center()) and !b.over(.{0,0}));
  // a button not live is never under the mouse
  var live=Bar(A).Set.initFull();
  try testing.expectEqual(@as(?A,.three),b.under(b.boxes[2].center(),live));
  live.remove(.three);
  try testing.expectEqual(@as(?A,null),b.under(b.boxes[2].center(),live));
}
