//! `--link`: the chat to Claude. While the gardener plays, the newest
//! messages hang at the right-hand side for a while and fade; the chat key
//! opens a trellis panel there with the whole conversation (the newest
//! lowest), each message under its speaker's name, and the message being
//! typed growing along a young stem at its foot, wrapped across lines, a
//! bud blinking at its caret. Enter sends it to Claude, Esc closes.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: fades, angles, casts
const m=lib.engine.core.math;
/// the game itself: its mode and the chat
const play=lib.play;
/// the UI's draw batch, and text widths
const Draw=lib.engine.ui.draw.Draw;
/// the HUD's shared sizes and colours
const s=lib.style;
/// every player-facing string
const txt=lib.txt;
/// the HUD: picks and rows
const hud=lib.hud;
/// a screen rectangle
const Box=hud.Box;
/// the keys and buttons down this frame
const Input=lib.engine.platform.input.Input;
/// the HUD's panel component
const Panel=lib.hudPanel.Panel;
/// the chat's messages and its text input
const link=lib.link;
/// the test harness
const testing=std.testing;
/// a colour
const Color=lib.engine.ui.draw.Color;
/// the panel's width (pixels)
const pw:f32=480;
/// how far it stands in from the screen's right-hand side and top (pixels)
const edge:f32=24;
/// its top, from the screen's top (pixels)
const top:f32=96;
/// how much of the screen's foot it leaves for the hotbar and hints (pixels)
const foot:f32=150;
/// how far the text stands in from the panel's sides (pixels)
const inset:f32=28;
/// the messages' text scale
const size=s.textLabel;
/// one line of text, top to top (pixels)
const lineH:f32=21;
/// the space between two messages (pixels)
const gap:f32=8;
/// the title's band at the panel's top (pixels)
const titleBand:f32=70;
/// the hint's band at the panel's foot (pixels)
const hintBand:f32=40;
/// how long a message hangs beside play before it is gone (s)
const shownFor:f32=20;
/// how long it takes to fade out at the end (s)
const fadeFor:f32=5;
/// the most lines one message or the typed text wraps to
const maxLines=16;
/// the young stem under the typed text: how far below a line (pixels)
const stemDrop:f32=16;
/// the bud at the caret: its length and width (pixels)
const budLen:f32=16;
/// (its width)
const budW:f32=7;
/// how often the bud blinks (a second)
const blink:f32=1.2;
/// drawn at the main menu too: no (the chat belongs to a garden)
/// shown while linked: the open chat, or recent messages beside play
pub fn visible(g:*const play.Game)bool{
  if(!g.linked)return false;
  return g.mode==.chat or (g.mode==.roam and recent(g)>0);
}
/// the chat's field
pub const Pick=union(enum){
  /// the message being typed
  field
};
/// a click on the field types into it
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  if(press!=.use)return;
  switch(p){.field=>g.typing=hud.row(.chat,.field)}
}
/// the message typed into, while the chat is open
pub fn edit(g:*play.Game,p:Pick)?hud.Edit{
  if(g.mode!=.chat)return null;
  return switch(p){.field=>g.chat.typed.edit()};
}
/// the message handed on (enter): sent
pub fn typed(g:*play.Game,p:Pick,fed:hud.Fed)void{
  switch(p){.field=>switch(fed){
    .same,.changed=>{},
    .submitted=>g.sendChat(),
  }}
}
/// how many kept messages are still recent enough to hang beside play
fn recent(g:*const play.Game)usize{
  // the count, from the newest back
  var n:usize=0;
  for(g.chat.kept())|*sd|{
    if(g.uiTime-sd.at<shownFor)n+=1;
  }
  return n;
}
/// a run of a text: its first byte and one past its last
pub const Span=struct{
  /// its first byte
  a:usize,
  /// one past its last
  b:usize,
};
/// splits `text` into lines of at most `cols` characters, breaking after a
/// space where one falls in reach, else mid-word; at most `maxLines`
/// (what is left after them is dropped). Returns how many were made.
pub fn wrap(text:[]const u8,cols:usize,out:*[maxLines]Span)usize{
  if(text.len==0){
    out[0]=.{.a=0,.b=0};
    return 1;
  }
  // the lines made, and where the next starts
  var n:usize=0;
  var at:usize=0;
  const c=@max(cols,1);
  while(at<text.len and n<maxLines){
    // where this line would end, at most
    var end=@min(at+c,text.len);
    if(end<text.len){
      // the last space in reach, the line broken after it
      var i=end;
      while(i>at+1 and text[i-1]!=' ')i-=1;
      if(text[i-1]==' ' and i>at+1)end=i;
    }
    out[n]=.{.a=at,.b=end};
    n+=1;
    at=end;
  }
  return n;
}
/// how many characters fit across `w` pixels
fn colsIn(w:f32)usize{return@intFromFloat(@max(1,@floor(w/Draw.width(" ",size))));}
/// draws one message, its speaker's name and its wrapped text, ending at
/// `bottom` (its last line's top); returns where it begins (its name's top)
fn message(d:*Draw,sd:*const link.Said,x:f32,bottom:f32,w:f32,alpha:u8)Allocator.Error!f32{
  // its lines, and where the first sits
  var spans:[maxLines]Span=undefined;
  const n=wrap(sd.text(),colsIn(w),&spans);
  const first=bottom-m.f(n-1)*lineH;
  // the speaker's name and colour
  const name=switch(sd.who){.gardener=>txt.s.hud.chatGardener,.claude=>txt.s.hud.chatClaude};
  var col:Color=switch(sd.who){.gardener=>s.chatGardener,.claude=>s.chatClaude};
  col[3]=alpha;
  _=try d.text(x,first-lineH,s.textSmall,col,name);
  // the text's colour, faded alike
  var tc=s.white;
  tc[3]=alpha;
  for(spans[0..n],0..)|sp,i|_=try d.text(x,first+m.f(i)*lineH,size,tc,sd.text()[sp.a..sp.b]);
  return first-lineH;
}
/// draws the chat: the open panel with the conversation and the typed
/// message, or (playing) the newest messages hanging beside play, fading
pub fn draw(g:*play.Game,d:*Draw,w:f32,h:f32)Allocator.Error!void{
  const t=g.uiT();
  // the panel's box and the text's left-hand side and width
  const box=Box{.x=w-pw-edge,.y=top,.w=pw,.h=@max(h-top-foot,titleBand+hintBand+4*lineH)};
  const x=box.x+inset;
  const tw=pw-2*inset;
  if(g.mode!=.chat){
    // the newest messages, bottom up, fading at the end of their time
    var y=box.y+box.h-hintBand;
    var i=g.chat.count;
    while(i>0){
      i-=1;
      // the message, its age, and how much of it still shows
      const sd=&g.chat.said[i];
      const age:f32=@floatCast(g.uiTime-sd.at);
      if(age>=shownFor)break;
      const a=m.unorm8((shownFor-age)/fadeFor);
      y=try message(d,sd,x,y,tw,a)-gap-lineH;
      if(y<box.y)break;
    }
    // how to answer
    _=try d.text(x,box.y+box.h-hintBand+lineH,s.textFine,s.dim,txt.s.hud.chatOpen);
    return;
  }
  var pn=Panel{.box=box,.col=s.pausePanel,.seed=0.43,.title=txt.s.hud.chatTitle,.titleSize=s.textTitle};
  try pn.draw(g,d,.{w,h});
  // the hint along the foot
  _=try d.text(x,box.y+box.h-hintBand+8,s.textFine,s.dim,txt.s.hud.chatHint);
  // the typed message, wrapped, on its stem above the hint
  const tx=g.chat.typed.slice();
  var spans:[maxLines]Span=undefined;
  const n=wrap(tx,colsIn(tw),&spans);
  const fieldTop=box.y+box.h-hintBand-stemDrop-m.f(n)*lineH;
  const fieldBox=Box{.x=x-8,.y=fieldTop-6,.w=tw+16,.h=m.f(n)*lineH+stemDrop+6};
  const pick=hud.row(.chat,.field);
  try g.rows.add(fieldBox,pick);
  try typedField(g,d,x,fieldTop,tw,&spans,n,t,g.points(pick));
  // the conversation above it, newest lowest, as much as fits
  var y=fieldTop-2*lineH;
  var i=g.chat.count;
  while(i>0){
    i-=1;
    // the message's lines, to know whether it fits
    var ms:[maxLines]Span=undefined;
    const mn=wrap(g.chat.said[i].text(),colsIn(tw),&ms);
    if(y-m.f(mn)*lineH<box.y+titleBand)break;
    y=try message(d,&g.chat.said[i],x,y,tw,255)-gap-lineH;
  }
}
/// the message being typed: its lines (`spans` of the typed text, `n` of
/// them) from `y` down, its selection lit, a stem under the last line and
/// a bud blinking at the caret; `over` lights it under the mouse
fn typedField(g:*play.Game,d:*Draw,x:f32,y:f32,w:f32,spans:*const[maxLines]Span,n:usize,t:f32,over:bool)Allocator.Error!void{
  const tx=g.chat.typed.slice();
  const cw=Draw.width(" ",size);
  // the stem under the last line, swaying a little
  const stemY=y+m.f(n-1)*lineH+stemDrop;
  const sway=1.5*@sin(t*1.3);
  if(over)try d.glow(x+w/2,stemY-8,w*0.35,s.menuHover);
  try d.limb(.{x-6,stemY+sway},.{x+w+6,stemY-sway},2.5,1.5,s.barkYoung,0);
  // the selection's ends, and the caret
  const sel=g.chat.typed.selection();
  const caret=g.chat.typed.caret;
  // where the caret's bud goes (its line and column)
  var cx=x;
  var cy=y;
  for(spans[0..n],0..)|sp,i|{
    // this line's top
    const ly=y+m.f(i)*lineH;
    // the selection lit behind this line's part of it
    const sa=@max(sel[0],sp.a);
    const sb=@min(sel[1],sp.b);
    if(sb>sa)try d.limb(.{x+m.f(sa-sp.a)*cw,ly+6},.{x+m.f(sb-sp.a)*cw,ly+6},7,7,s.selection,t*3);
    _=try d.text(x,ly,size,s.white,tx[sp.a..sp.b]);
    // the caret on this line (the last line takes one at its very end)
    if(caret>=sp.a and (caret<sp.b or i==n-1)){
      cx=x+m.f(caret-sp.a)*cw;
      cy=ly;
    }
  }
  // how far the bud is open now, blinking 0..1
  const open=0.5+0.5*@sin(t*blink*m.tau);
  try d.leaf(.{cx+2,cy+lineH-4},-m.halfPi,budLen,budW,s.leaf,open,0.2);
}
test"wrapping breaks after spaces, else mid-word, and covers the whole text"{
  var sp:[maxLines]Span=undefined;
  // short: one line
  try testing.expectEqual(@as(usize,1),wrap("hi there",20,&sp));
  // broken after the space in reach
  const t1="hello there garden";
  const n1=wrap(t1,12,&sp);
  try testing.expectEqual(@as(usize,2),n1);
  try testing.expectEqualStrings("hello there ",t1[sp[0].a..sp[0].b]);
  try testing.expectEqualStrings("garden",t1[sp[1].a..sp[1].b]);
  // a word longer than a line: cut mid-word
  const t2="abcdefghijklmnop";
  const n2=wrap(t2,5,&sp);
  try testing.expectEqual(@as(usize,4),n2);
  try testing.expectEqual(t2.len,sp[n2-1].b);
  // every byte in exactly one line, in order
  const t3="the quick brown fox jumps over the lazy wolf and keeps going";
  const n3=wrap(t3,7,&sp);
  for(1..n3)|i|try testing.expectEqual(sp[i-1].b,sp[i].a);
  try testing.expectEqual(t3.len,sp[n3-1].b);
  // empty: one empty line (for the caret)
  try testing.expectEqual(@as(usize,1),wrap("",10,&sp));
  // far too long: capped, never past the array
  const long="x"**400;
  try testing.expectEqual(@as(usize,maxLines),wrap(long,10,&sp));
}
