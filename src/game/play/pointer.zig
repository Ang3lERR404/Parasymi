//! the HUD under the mouse, the keys and the pad: a row clicks as mouse1
//! goes down on it, or (a button) as mouse1 is let go over the row it went
//! down on; a row held is dragged (a scroll stem, a slider); in the frozen
//! world's menus the arrows, tab and the pad move between the top panel's
//! rows and confirm chooses one; the row being typed into takes the typing,
//! its caret moved, its text selected, cut, copied and pasted.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// deep equality, to find a row by its pick
const eqlDeep=std.meta.eql;
/// the engine package
const engine=lib.engine;
/// the keys and buttons down this frame
const Input=engine.platform.input.Input;
/// the bindings: which action each key is
const ctl=lib.controls;
/// the HUD: clicks, picks, rows and their hooks
const hud=lib.hud;
/// a screen rectangle
const Box=hud.Box;
/// which box focus goes to next
const focus=engine.ui.focus;
/// what a text input is fed a frame
const Keys=engine.ui.textInput.Keys;
/// where a text input's caret moves
const Move=engine.ui.textInput.Move;
/// the game, which these act on
const Game=lib.play.game.Game;
// decision: the keys reach at most this many rows of the top panel (a
// menu holds a few dozen); rows past it are left to the mouse.
/// the most rows the keys and the pad move between
const maxFocus=128;
/// the arrows' actions, each with the way it moves focus
const arrows=[_]struct{ctl.Action,focus.Dir}{
  .{.focusUp,.up},.{.focusDown,.down},.{.focusLeft,.left},.{.focusRight,.right},
};
/// this frame's pointer: the cursor at `cursor` and mouse1; the mouse moved
/// takes the lead back from the keys
pub fn point(g:*Game,in:*const Input,cursor:[2]f32)void{
  g.mouse=cursor;
  g.pointer=.{.at=cursor,.down=ctl.down(in,.use),.went=ctl.pressed(in,.use),.up=ctl.released(in,.use)};
  if(in.mouseDelta[0]!=0 or in.mouseDelta[1]!=0)g.keyFocus=null;
}
/// the HUD's clicks this frame on the row `hit` under the cursor (null:
/// none): a row firing on press clicks as mouse1 goes down, one firing on
/// release as it is let go over the row it went down on; the row held is
/// dragged; the other button clicks as it goes down
pub fn clicks(g:*Game,in:*const Input,hit:?hud.Pick)void{
  // the row let go over that mouse1 went down on, if any
  const let=g.press.track(g.pointer,hit);
  if(g.pointer.went)if(hit)|p|if(hud.fire(p)==.press)hud.click(g,p,.use,in);
  if(let)|p|if(hud.fire(p)==.release)hud.click(g,p,.use,in);
  if(g.pointer.down)if(g.press.on)|p|if(g.rows.find(p))|b|hud.drag(g,p,b,g.pointer.at);
  if(ctl.pressed(in,.remove))if(hit)|p|hud.click(g,p,.remove,in);
}
/// whether `a` and `b` are the same row
fn same(a:?hud.Pick,b:hud.Pick)bool{return if(a)|x|eqlDeep(x,b)else false;}
/// whether mouse1 went down on the row `p` and is held (a stem or slider
/// being dragged)
pub fn grips(g:*const Game,p:hud.Pick)bool{return same(g.press.on,p);}
/// the frozen world's menus by the keys and the pad: the arrows move to the
/// nearest of the top panel's rows that way (left and right turn a setting
/// instead, or move the caret while typing), tab steps through them, and
/// confirm chooses the one the keys are on. The row the keys are on is
/// pointed at, as the mouse would.
pub fn steer(g:*Game,in:*const Input)void{
  // the rows the keys can reach, their boxes, and how many
  var picks:[maxFocus]hud.Pick=undefined;
  var boxes:[maxFocus]Box=undefined;
  var n:usize=0;
  for(g.rows.top())|a|if(hud.focusable(a.pick) and n<maxFocus){
    picks[n]=a.pick;
    boxes[n]=a.box;
    n+=1;
  };
  // where the keys are now among them (gone with its row)
  var from:?usize=null;
  for(picks[0..n],0..)|p,i|if(same(g.keyFocus,p)){from=i;};
  if(from==null)g.keyFocus=null;
  if(n==0)return;
  // whether the arrows move the caret (typing, the keys on the field or
  // nowhere else)
  const caret=if(g.typing)|t|g.keyFocus==null or same(g.keyFocus,t)else false;
  for(arrows)|ad|if(ctl.repeated(in,ad[0])){
    // which way, and as a turn of a setting
    const d=ad[1];
    const dir:i32=switch(d){.left=>-1,.right=>1,.up,.down=>0};
    if(dir!=0){
      if(caret)continue;
      if(g.keyFocus)|p|if(hud.nudge(g,p,dir))continue;
    }
    // the row moved to: the nearest that way, the first when none was on
    const to=if(from)|i|focus.toward(boxes[0..n],i,d)else 0;
    if(to)|j|{
      from=j;
      g.keyFocus=picks[j];
    }
  };
  if(ctl.repeated(in,.focusNext))if(focus.step(n,from,if(ctl.down(in,.extend)).back else.on))|j|{
    from=j;
    g.keyFocus=picks[j];
  };
  if(g.keyFocus)|p|{
    g.pointed=p;
    if(ctl.pressed(in,.confirm)and!caret)hud.click(g,p,.use,in);
  }
}
/// the row being typed into takes this frame's typing: characters, erase
/// (held, repeating), the caret moved (selecting with extend held) unless
/// the keys are on another row, and with chord held select all, copy, cut
/// and paste; confirm hands its text on. A row that types no more is let go.
pub fn typeInto(g:*Game,in:*const Input)void{
  // the row typed into, and its input
  const p=g.typing orelse return;
  const e=hud.edit(g,p) orelse {
    g.typing=null;
    return;
  };
  // whether the keys are on this row (or none), and chord held
  const here=g.keyFocus==null or same(g.keyFocus,p);
  const chord=ctl.down(in,.chord);
  // where the caret moves, if anywhere
  const mv:?Move=if(!here)null else if(ctl.repeated(in,.caretLeft)).left else if(ctl.repeated(in,.caretRight)).right else if(ctl.pressed(in,.caretHome)).home else if(ctl.pressed(in,.caretEnd)).end else null;
  const k:Keys=.{
    .typed=if(chord)&.{}else in.typed(),
    .erase=ctl.repeated(in,.erase),
    .eraseAhead=ctl.repeated(in,.eraseAhead),
    .move=mv,
    .extend=ctl.down(in,.extend),
    .selectAll=chord and ctl.pressed(in,.selectAll),
    .cut=chord and ctl.pressed(in,.cut),
    .paste=if(chord and ctl.pressed(in,.paste))in.clipboard()else"",
    .confirm=here and ctl.pressed(in,.confirm),
  };
  if(chord and (ctl.pressed(in,.copy) or ctl.pressed(in,.cut)))in.setClipboard(e.selected());
  hud.typed(g,p,e.feed(k));
}
