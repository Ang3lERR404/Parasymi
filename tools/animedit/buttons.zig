//! the animation editor's acts: every one a key does and a button on the
//! toolbar does the same, which are lit and which would do anything now.
/// the toolbar: buttons, binds, a bar
const toolbar=@import("../toolbar.zig");
/// the editor's root, through which its other files are reached
const animedit=@import("../animedit.zig");
/// the editor's state
const Editor=animedit.editor.Editor;
/// everything the editor does at a key or a button
pub const Act=enum{
  /// playing or paused
  play,
  /// the playhead to the start
  start,
  /// the playhead a frame back
  frameBack,
  /// a frame on
  frameOn,
  /// to the key before
  keyBack,
  /// to the key after
  keyOn,
  /// the clip longer
  longer,
  /// shorter
  shorter,
  /// the channel above selected
  prevChannel,
  /// the channel below
  nextChannel,
  /// the selected channel keyed at the playhead
  key,
  /// every channel keyed there
  keyAll,
  /// the selected channel's key there taken out
  unkey,
  /// the selected channel at rest (keyed, if it has keys)
  rest,
  /// the key there given the next ease (with shift, the one before)
  ease,
  /// the keys there copied
  copy,
  /// pasted
  paste,
  /// pasted mirrored across the wolf's middle
  pasteMirrored,
  /// a mark at the playhead, named as it is typed
  mark,
  /// the mark there taken out
  unmark,
  /// the clip written to its file
  save,
  /// a step back (with shift, forward)
  undo,
  /// a step forward
  redo,
  /// the camera onto the selected joint
  focus,
  /// the help on or off
  help,
};
/// the toolbar's own type for these acts
pub const Bar=toolbar.Bar(Act);
/// which acts are lit or live
const Set=Bar.Set;
/// every key and the act it does
pub const binds=[_]toolbar.Bind(Act){
  .{.key=.space,.act=.play},
  .{.key=.left,.shift=false,.act=.frameBack},
  .{.key=.right,.shift=false,.act=.frameOn},
  .{.key=.left,.shift=true,.act=.keyBack},
  .{.key=.right,.shift=true,.act=.keyOn},
  .{.key=.home,.act=.start},
  .{.key=.page_up,.act=.longer},
  .{.key=.page_down,.act=.shorter},
  .{.key=.up,.act=.prevChannel},
  .{.key=.down,.act=.nextChannel},
  .{.key=.k,.act=.key},
  .{.key=.a,.act=.keyAll},
  .{.key=.x,.act=.unkey},
  .{.key=.delete,.act=.unkey},
  .{.key=.r,.act=.rest},
  .{.key=.s,.ctrl=true,.act=.save},
  .{.key=.z,.ctrl=true,.act=.undo},
  .{.key=.y,.ctrl=true,.act=.redo},
  .{.key=.c,.ctrl=true,.act=.copy},
  .{.key=.v,.ctrl=true,.shift=false,.act=.paste},
  .{.key=.v,.ctrl=true,.shift=true,.act=.pasteMirrored},
  .{.key=.e,.act=.ease},
  .{.key=.period,.act=.focus},
  .{.key=.m,.shift=false,.act=.mark},
  .{.key=.m,.shift=true,.act=.unmark},
  .{.key=.h,.act=.help},
};
/// the buttons, top to bottom
const items=[_]Bar.Entry{
  .{.act=.play,.label="play",.key="space"},
  .{.act=.start,.label="to start",.key="home"},
  .{.act=.frameBack,.label="frame back",.key="left"},
  .{.act=.frameOn,.label="frame on",.key="right"},
  .{.act=.keyBack,.label="key back",.key="shift+left"},
  .{.act=.keyOn,.label="key on",.key="shift+right"},
  .{.act=.longer,.label="longer",.key="pgup"},
  .{.act=.shorter,.label="shorter",.key="pgdn"},
  .{.act=.key,.label="key",.key="k",.gap=true},
  .{.act=.keyAll,.label="key all",.key="a"},
  .{.act=.unkey,.label="unkey",.key="x"},
  .{.act=.rest,.label="at rest",.key="r"},
  .{.act=.ease,.label="ease",.key="e"},
  .{.act=.copy,.label="copy keys",.key="ctrl+c",.gap=true},
  .{.act=.paste,.label="paste",.key="ctrl+v"},
  .{.act=.pasteMirrored,.label="paste mirrored",.key="ctrl+shift+v"},
  .{.act=.mark,.label="mark",.key="m",.gap=true},
  .{.act=.unmark,.label="unmark",.key="shift+m"},
  .{.act=.save,.label="save",.key="ctrl+s",.gap=true},
  .{.act=.undo,.label="undo",.key="ctrl+z"},
  .{.act=.redo,.label="redo",.key="ctrl+y"},
  .{.act=.focus,.label="focus",.key=".",.gap=true},
  .{.act=.help,.label="help",.key="h"},
};
/// the buttons
pub fn all()[]const Bar.Entry{return&items;}
/// the help: what the mouse does, and the keys' other ways
pub const help=[_][]const u8{
  "click a channel row: select it   drag it left and right: key its value (shift: fine)",
  "the wolf: click a joint, drag its gizmo (shift: fine)",
  "drag along the timeline: scrub   wheel over the list: scroll   up/down: the channel",
  "middle drag: orbit   wheel: zoom   shift+e (or shift+click ease): the ease before",
  "a mark is named as you type (enter: done); on a mark, mark renames it",
};
/// the acts lit now: playing, the help
pub fn lit(e:*const Editor)Set{
  // the lit ones so far
  var on=Set.initEmpty();
  on.setPresent(.play,e.playing);
  on.setPresent(.help,e.helpShown);
  return on;
}
/// the acts that would do anything now
pub fn live(e:*const Editor)Set{
  // all of them, then the ones that would do nothing taken out
  var on=Set.initFull();
  on.setPresent(.save,e.dirty);
  on.setPresent(.undo,e.history.back.items.len>0);
  on.setPresent(.redo,e.history.ahead.items.len>0);
  on.setPresent(.paste,e.copiedLen>0);
  on.setPresent(.pasteMirrored,e.copiedLen>0 and e.wolf());
  on.setPresent(.unmark,e.markHere()!=null);
  on.setPresent(.ease,e.clip.keyAt(e.chName(e.sel),e.t)!=null);
  on.setPresent(.unkey,e.clip.keyAt(e.chName(e.sel),e.t)!=null);
  return on;
}
