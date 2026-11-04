//! `--record[=S]`: a playback trail. While the gardener plays as usual, a
//! screenshot is asked for every S seconds (5 by default) into a folder of
//! its own under `shots/` (`trail_<time>`), each beside a small note of
//! what the game believed then: the open panel, where back leads, the
//! camera, the wolf's place and the actions pressed since the last shot.
//! Read as they land, it is a semi-live window into a playthrough, for bugs
//! too quick to describe.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// a set of actions, one bit each
const EnumSet=std.EnumSet;
/// where a note is written
const Writer=std.Io.Writer;
/// the test harness
const testing=std.testing;
/// the actions the gardener presses
const ctl=lib.controls;
/// the keys, mouse and pad this frame
const Input=lib.engine.platform.input.Input;
/// the whole running game a note is taken of
const Game=lib.play.Game;
/// a shot is taken this often unless `--record=` says otherwise (s)
pub const every:f32=5;
/// the trail's folder name begins with this (then the time it began)
pub const prefix="trail_";
/// the trail of one play: when the next shot falls due, how many were
/// taken, and what was pressed since the last
pub const Trail=struct{
  /// seconds between shots
  every:f32=every,
  /// seconds since the last shot (the first waits a whole interval)
  since:f32=0,
  /// shots taken so far, numbering the next
  taken:u32=0,
  /// the actions pressed since the last shot
  pressed:EnumSet(ctl.Action)=.initEmpty(),
  /// counts the frame's time and remembers what it pressed; true when a
  /// shot falls due this frame
  pub fn step(t:*Trail,in:*const Input,dt:f32)bool{
    for(std.enums.values(ctl.Action))|a|if(ctl.pressed(in,a))t.pressed.insert(a);
    t.since+=dt;
    if(t.since<t.every)return false;
    t.since=0;
    return true;
  }
  /// writes the note of what the game believes now to `w`, then forgets
  /// the presses and counts the shot taken
  pub fn note(t:*Trail,g:*const Game,w:*Writer)Writer.Error!void{
    defer{
      t.pressed=.initEmpty();
      t.taken+=1;
    }
    try w.print("shot {d}, ",.{t.taken});
    try describe(g,t.pressed,w);
  }
};
/// writes what the game believes now to `w`: the time played, the mode and
/// where back leads, the camera, the wolf's place, the hotbar and what is
/// pointed at, and the actions in `pressed` (the trail's note, the link's state)
pub fn describe(g:*const Game,pressed:EnumSet(ctl.Action),w:*Writer)Writer.Error!void{
  // the wolf's place
  const p=g.player.pos;
  try w.print("played {d:.1}s\n",.{g.uiTime});
  try w.print("mode {t}, back leads to {t}, at title {}\n",.{g.mode,g.menuHome,g.atTitle()});
  try w.print("camera {s}, looking {}, overview {}\n",.{@tagName(g.cam.view),g.looking,g.overview});
  try w.print("wolf at {d:.2} {d:.2} {d:.2}\n",.{p[0],p[1],p[2]});
  try w.print("hotbar slot {d}, holding {}, pointing at {s}\n",.{g.hot,g.held!=null,if(g.pointed)|pk|@tagName(pk)else"nothing"});
  try w.writeAll("pressed lately:");
  // the walk over the presses
  var it=pressed.iterator();
  while(it.next())|a|try w.print(" {t}",.{a});
  try w.writeAll("\n");
}
test"a trail asks for a shot once each interval"{
  // the input, driven by hand (no window), and a trail every second
  var in:Input=.{.win=undefined};
  var t:Trail=.{.every=1};
  try testing.expect(!t.step(&in,0.6));
  try testing.expect(t.step(&in,0.6));
  try testing.expect(!t.step(&in,0.6));
}
