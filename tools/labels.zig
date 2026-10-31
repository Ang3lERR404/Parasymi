//! the editors' words: each value's dotted path (`arms.1.root.z`,
//! `col.x`) put into plain words (`right shoulder lean`, `colour red`) for
//! the panels to show, the files keeping the paths; and the names the
//! gardener types (a form's, a mark's), with the keyboard read for typing.
/// the standard library, reached through the game's hub
const std=ps.std;
/// whether two byte strings are the same
const eql=std.mem.eql;
/// whether a path begins with a rule's
const startsWith=std.mem.startsWith;
/// splits what is left of a path at its dots
const splitScalar=std.mem.splitScalar;
/// whether a segment is a digit (an index)
const isDigit=std.ascii.isDigit;
/// formats text at compile time (sides and indices)
const comptimePrint=std.fmt.comptimePrint;
/// reads an index out of a segment
const parseInt=std.fmt.parseInt;
/// where a byte first falls in text, if anywhere
const indexOfScalar=std.mem.indexOfScalar;
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// the keys and buttons held this frame
const Input=engine.platform.input.Input;
/// a keyboard key, named as the window library names it
const Key=engine.platform.input.Key;
/// the engine's text input: a caret, a selection, typing
const textInput=engine.ui.textInput;
/// keyframed clips, for the pose's channel names
const clip=engine.anim.clip;
/// all the maths: angles
const m=engine.core.math;
/// the UI's draw batch, and text widths
const Draw=engine.ui.draw.Draw;
/// the allocator type drawing may fail with
const Allocator=std.mem.Allocator;
/// the HUD's shared colours and type sizes
const s=ps.style;
/// the editors' panel text size
const small=s.textSmall;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the wolf's skeleton: how many tail segments and fingers it has
const skel=ps.skeleton;
/// how a turn's three channels read: about x it bends, about y it
/// twists, about z it leans
pub const turnAxes=[3][]const u8{"bend","twist","lean"};
/// how a place's three channels read: across the body, up, along it
pub const placeAxes=[3][]const u8{"across","up","along"};
/// how a colour's three channels read
pub const colourAxes=[3][]const u8{"red","green","blue"};
/// one rule: a path, or its first segments, and the words it is shown as
pub const Rule=struct{
  /// the path's first segments (`arms.1.root`)
  path:[]const u8,
  /// the words for them (`right shoulder`)
  word:[]const u8,
  /// what an axis after them (x, y, z) is called
  axes:?[3][]const u8=null,
};
/// path `path` in words by the rule with the longest path it starts
/// with: an axis after it named by the rule's `axes`, an index counted
/// from one, any other segment as it is (a path no rule fits, spaced)
pub fn label(comptime rules:[]const Rule,comptime path:[]const u8)[]const u8{
  @setEvalBranchQuota(1_000_000);
  // the rule that fits best, and how much of the path it covers
  var best:?Rule=null;
  for(rules)|r|{
    // whether the rule covers the whole path, or its first segments
    const fits=eql(u8,r.path,path) or (startsWith(u8,path,r.path) and path.len>r.path.len and path[r.path.len]=='.');
    if(fits and (best==null or r.path.len>best.?.path.len))best=r;
  }
  // the words so far, and what of the path is left to put into them
  var out:[]const u8=if(best)|b|b.word else"";
  const rest=if(best)|b|(if(path.len>b.path.len)path[b.path.len+1..]else"")else path;
  if(rest.len==0)return out;
  // the rest, a segment at a time
  var it=splitScalar(u8,rest,'.');
  while(it.next())|seg|{
    // the segment's words: an axis, an index or itself
    const axis:?usize=if(seg.len==1)switch(seg[0]){'x'=>0,'y'=>1,'z'=>2,else=>null}else null;
    const word=if(best!=null and best.?.axes!=null and axis!=null)best.?.axes.?[axis.?]
      else if(isDigit(seg[0]))comptimePrint("{d}",.{(parseInt(usize,seg,10) catch unreachable)+1})
      else seg;
    out=if(out.len==0)word else out++" "++word;
  }
  return out;
}
/// every path of `names` in words, in the same order
pub fn all(comptime rules:[]const Rule,comptime names:[]const[]const u8)[names.len][]const u8{
  @setEvalBranchQuota(10_000_000);
  // the words, filled path by path
  var out:[names.len][]const u8=undefined;
  inline for(names,0..)|n,i|out[i]=comptime label(rules,n);
  return out;
}
/// each side's word, left then right
const sideWords=[2][]const u8{"left","right"};
/// the rules for the wolf's pose: each joint by its body part and side
pub const poseRules=blk:{
  // the rules so far
  var r:[]const Rule=&.{
    .{.path="hip",.word="hips place",.axes=placeAxes},
    .{.path="pelvis",.word="pelvis",.axes=turnAxes},
    .{.path="waist",.word="waist",.axes=turnAxes},
    .{.path="chest",.word="chest",.axes=turnAxes},
    .{.path="neck",.word="neck",.axes=turnAxes},
    .{.path="head",.word="head",.axes=turnAxes},
    .{.path="jaw",.word="jaw open"},
    .{.path="gut",.word="belly fullness"},
    .{.path="breath",.word="breath"},
  };
  for(0..skel.tailCount)|i|r=r++&[_]Rule{.{.path=comptimePrint("tail.{d}",.{i}),.word=comptimePrint("tail {d}",.{i+1}),.axes=turnAxes}};
  for(sideWords,0..)|sw,i|r=r++&[_]Rule{
    .{.path=comptimePrint("ears.{d}",.{i}),.word=sw++" ear",.axes=turnAxes},
    .{.path=comptimePrint("arms.{d}.root",.{i}),.word=sw++" shoulder",.axes=turnAxes},
    .{.path=comptimePrint("arms.{d}.mid",.{i}),.word=sw++" elbow"},
    .{.path=comptimePrint("arms.{d}.low",.{i}),.word=sw++" wrist",.axes=turnAxes},
    .{.path=comptimePrint("arms.{d}.foot",.{i}),.word=sw++" arm (unused) foot"},
    .{.path=comptimePrint("arms.{d}.roll",.{i}),.word=sw++" arm (unused) roll"},
    .{.path=comptimePrint("legs.{d}.root",.{i}),.word=sw++" thigh",.axes=turnAxes},
    .{.path=comptimePrint("legs.{d}.mid",.{i}),.word=sw++" knee"},
    .{.path=comptimePrint("legs.{d}.low",.{i}),.word=sw++" hock",.axes=turnAxes},
    .{.path=comptimePrint("legs.{d}.foot",.{i}),.word=sw++" toes"},
    .{.path=comptimePrint("legs.{d}.roll",.{i}),.word=sw++" foot roll"},
    .{.path=comptimePrint("hands.{d}.curl",.{i}),.word=sw++" finger curl"},
    .{.path=comptimePrint("hands.{d}.tip",.{i}),.word=sw++" fingertip curl"},
    .{.path=comptimePrint("hands.{d}.spread",.{i}),.word=sw++" finger spread"},
  };
  break:blk r;
};
/// the rules for a plant's or structure's look
pub const lookRules=[_]Rule{
  .{.path="growth",.word="growth"},
  .{.path="mana",.word="mana"},
  .{.path="flow",.word="sap flow"},
  .{.path="health",.word="health"},
  .{.path="ripe",.word="ripeness"},
};
/// the most bytes a typed name holds
pub const nameCap=24;
/// a name being typed: the characters a garden's name may hold
pub const Typed=textInput.TextInput(nameCap,ps.save.nameChar);
/// a name kept by value (a form's)
pub const Name=struct{
  /// its bytes; the first `len` are real
  buf:[nameCap]u8=undefined,
  /// how many bytes it holds
  len:u8=0,
  /// the name's text
  pub fn slice(n:*const Name)[]const u8{return n.buf[0..n.len];}
  /// `text` as a name, cut to fit
  pub fn of(text:[]const u8)Name{
    // the name being filled
    var n=Name{};
    n.len=@intCast(@min(text.len,nameCap));
    @memcpy(n.buf[0..n.len],text[0..n.len]);
    return n;
  }
};
/// `text` ready to be typed into: all of it there, the caret at its end
pub fn typing(text:[]const u8)Typed{
  // the input, filled with the text
  var t=Typed{.alignment=.left};
  for(text)|c|t.put(c);
  return t;
}
/// what a frame of the keyboard does to a name being typed: the characters
/// typed, backspace and delete (held, repeating), the arrows, home and end
/// (shift marking), ctrl+a all, ctrl+v pasted
pub fn keys(in:*const Input)textInput.Keys{
  // whether shift or ctrl is held
  const shift=in.down(.{.key=.left_shift}) or in.down(.{.key=.right_shift});
  const ctrl=in.down(.{.key=.left_control}) or in.down(.{.key=.right_control});
  // whether key `k` went down or repeated this frame
  const rep=struct{
    /// whether key `k` went down or repeated this frame
    fn f(i:*const Input,k:Key)bool{return i.repeated(.{.key=k});}
  }.f;
  return.{
    .typed=if(ctrl)&.{}else in.typed(),
    .erase=rep(in,.backspace),
    .eraseAhead=rep(in,.delete),
    .move=if(rep(in,.left)).left else if(rep(in,.right)).right else if(rep(in,.home)).home else if(rep(in,.end)).end else null,
    .extend=shift,
    .selectAll=ctrl and in.pressed(.{.key=.a}),
    .paste=if(ctrl and in.pressed(.{.key=.v}))in.clipboard()else"",
  };
}
/// draws `t` at (`x`,`y`) in the panel's small text, as the HUD's fields
/// do it smaller: its selection a sheath of sap behind its letters, a bud
/// at its caret where the next letter goes
pub fn drawTyped(d:*Draw,x:f32,y:f32,t:*const Typed)Allocator.Error!void{
  // the text, and its selection's ends
  const text=t.slice();
  const sel=t.selection();
  if(sel[1]>sel[0]){
    // where the selection starts and ends across the text
    const xa=x+Draw.width(text[0..sel[0]],small);
    const xb=x+Draw.width(text[0..sel[1]],small);
    try d.limb(.{xa,y+7},.{xb,y+7},8,8,s.selection,0);
  }
  _=try d.text(x,y,small,s.white,text);
  // where the caret is
  const cx=x+Draw.width(text[0..t.caret],small);
  try d.leaf(.{cx+1,y+14},-m.halfPi,13,6,s.leaf,0.8,0.2);
}
/// whether naming is done this frame: enter or escape went down
pub fn named(in:*const Input)bool{
  return in.pressed(.{.key=.enter}) or in.pressed(.{.key=.kp_enter}) or in.pressed(.{.key=.escape});
}
/// the test helpers
const testing=std.testing;
test"a path is put into words by the rule that fits it best"{
  // the pose's channels, and their words
  const PoseCh=clip.Channels(skel.Pose);
  const pose=comptime all(poseRules,&PoseCh.names);
  try testing.expectEqualStrings("right shoulder lean",pose[comptime PoseCh.find("arms.1.root.z").?]);
  try testing.expectEqualStrings("left finger curl 3",pose[comptime PoseCh.find("hands.0.curl.2").?]);
  try testing.expectEqualStrings("tail 4 twist",pose[comptime PoseCh.find("tail.3.y").?]);
  try testing.expectEqualStrings("hips place up",pose[comptime PoseCh.find("hip.y").?]);
  try testing.expectEqualStrings("colour green",comptime label(&.{.{.path="col",.word="colour",.axes=colourAxes}},"col.y"));
  try testing.expectEqualStrings("odd thing",comptime label(&.{},"odd.thing"));
  // every pose channel has words, none left as a bare path
  for(pose)|w|try testing.expect(indexOfScalar(u8,w,'.')==null);
}
test"a typed name keeps what a name may hold and cuts to fit"{
  // a name typed in, then kept
  var t=typing("snout");
  _=t.feed(.{.typed=&.{' ','2','/'}});
  try testing.expectEqualStrings("snout 2",t.slice());
  try testing.expectEqualStrings("abc",Name.of("abc").slice());
  try testing.expectEqual(@as(usize,nameCap),Name.of("a name far too long to be kept whole").len);
}
