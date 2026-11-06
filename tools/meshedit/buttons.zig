//! the mesh editor's acts: every one a key does and a button on the
//! toolbar does the same, which are lit and which would do anything now.
/// the toolbar: buttons, binds, a bar
const toolbar=@import("../toolbar.zig");
/// the editor's root, through which its other files are reached
const meshedit=@import("../meshedit.zig");
/// the editor's state
const Editor=meshedit.editor.Editor;
/// everything the editor does at a key or a button; what some do depends
/// on the mode (`make` a form, or in rig mode a bone)
pub const Act=enum{
  /// the mesh written to its file
  save,
  /// a step back (with shift, forward)
  undo,
  /// a step forward
  redo,
  /// the file's version taken, when it changed on disk while the mesh had changes too
  fromDisk,
  /// a new form from the selected (rig mode: a new bone on the selected)
  make,
  /// the selected form (bone) taken out
  remove,
  /// the next form (bone) selected
  next,
  /// the selected form moved up the list, drawn sooner
  raise,
  /// moved down the list
  lower,
  /// the selected form (bone) named, typed
  name,
  /// the selected form's shape stepped on
  shape,
  /// carving or not
  carve,
  /// inking or not
  ink,
  /// twinned across the middle or not (rig mode: the bone)
  twin,
  /// its shader stepped on (with shift, back)
  shader,
  /// a nest's sculpt stepped on (with shift, back)
  part,
  /// the bone it rides stepped on (with shift, back)
  bone,
  /// it and its group snapped
  snap,
  /// the selected value at rest (rig mode: the test turn; with shift, every bone's)
  rest,
  /// the camera onto the selected form (joint)
  focus,
  /// the forms' handles shown or hidden, to see the surface bare
  dots,
  /// the value above selected
  prevValue,
  /// the value below
  nextValue,
  /// the gizmo moves
  move,
  /// the gizmo turns
  turn,
  /// the gizmo sizes
  size,
  /// finer cells
  finer,
  /// coarser cells
  coarser,
  /// rig mode on or off
  rig,
  /// the help on or off
  help,
};
/// the toolbar's own type for these acts
pub const Bar=toolbar.Bar(Act);
/// which acts are lit or live
const Set=Bar.Set;
/// every key and the act it does
pub const binds=[_]toolbar.Bind(Act){
  .{.key=.s,.ctrl=true,.act=.save},
  .{.key=.z,.ctrl=true,.act=.undo},
  .{.key=.y,.ctrl=true,.act=.redo},
  .{.key=.F5,.act=.fromDisk},
  .{.key=.j,.act=.rig},
  .{.key=.h,.act=.help},
  .{.key=.v,.act=.dots},
  .{.key=.o,.act=.bone},
  .{.key=.n,.act=.make},
  .{.key=.delete,.act=.remove},
  .{.key=.tab,.act=.next},
  .{.key=.page_up,.act=.raise},
  .{.key=.page_down,.act=.lower},
  .{.key=.t,.act=.shape},
  .{.key=.c,.act=.carve},
  .{.key=.p,.act=.part},
  .{.key=.i,.act=.ink},
  .{.key=.g,.act=.snap},
  .{.key=.x,.act=.twin},
  .{.key=.m,.act=.shader},
  .{.key=.up,.act=.prevValue},
  .{.key=.down,.act=.nextValue},
  .{.key=.r,.act=.rest},
  .{.key=.period,.act=.focus},
  .{.key=.F2,.act=.name},
  .{.key=.one,.act=.move},
  .{.key=.two,.act=.turn},
  .{.key=.three,.act=.size},
  .{.key=.left_bracket,.act=.finer},
  .{.key=.right_bracket,.act=.coarser},
};
/// the buttons shown with the forms
const formItems=[_]Bar.Entry{
  .{.act=.save,.label="save",.key="ctrl+s"},
  .{.act=.undo,.label="undo",.key="ctrl+z"},
  .{.act=.redo,.label="redo",.key="ctrl+y"},
  .{.act=.fromDisk,.label="take file's",.key="f5"},
  .{.act=.make,.label="new form",.key="n",.gap=true},
  .{.act=.remove,.label="remove",.key="del"},
  .{.act=.next,.label="next form",.key="tab"},
  .{.act=.raise,.label="move up",.key="pgup"},
  .{.act=.lower,.label="move down",.key="pgdn"},
  .{.act=.name,.label="name it",.key="f2"},
  .{.act=.shape,.label="shape",.key="t",.gap=true},
  .{.act=.carve,.label="carve",.key="c"},
  .{.act=.ink,.label="ink only",.key="i"},
  .{.act=.twin,.label="twin",.key="x"},
  .{.act=.shader,.label="shader",.key="m"},
  .{.act=.part,.label="nest sculpt",.key="p"},
  .{.act=.bone,.label="bone",.key="o"},
  .{.act=.snap,.label="snap",.key="g"},
  .{.act=.rest,.label="value at rest",.key="r"},
  .{.act=.focus,.label="focus",.key="."},
  .{.act=.move,.label="move",.key="1",.gap=true},
  .{.act=.turn,.label="turn",.key="2"},
  .{.act=.size,.label="size",.key="3"},
  .{.act=.finer,.label="finer cells",.key="[",.gap=true},
  .{.act=.coarser,.label="coarser cells",.key="]"},
  .{.act=.rig,.label="rig mode",.key="j",.gap=true},
  .{.act=.dots,.label="hide dots",.key="v"},
  .{.act=.help,.label="help",.key="h"},
};
/// the buttons shown in rig mode
const rigItems=[_]Bar.Entry{
  .{.act=.save,.label="save",.key="ctrl+s"},
  .{.act=.undo,.label="undo",.key="ctrl+z"},
  .{.act=.redo,.label="redo",.key="ctrl+y"},
  .{.act=.fromDisk,.label="take file's",.key="f5"},
  .{.act=.make,.label="new bone",.key="n",.gap=true},
  .{.act=.remove,.label="remove",.key="del"},
  .{.act=.next,.label="next bone",.key="tab"},
  .{.act=.name,.label="name it",.key="f2"},
  .{.act=.twin,.label="twin",.key="x"},
  .{.act=.rest,.label="turn at rest",.key="r",.gap=true},
  .{.act=.focus,.label="focus",.key="."},
  .{.act=.move,.label="move joint",.key="1",.gap=true},
  .{.act=.turn,.label="test turn",.key="2"},
  .{.act=.rig,.label="rig mode",.key="j",.gap=true},
  .{.act=.dots,.label="hide dots",.key="v"},
  .{.act=.help,.label="help",.key="h"},
};
/// the buttons for the mode the editor is in
pub fn items(e:*const Editor)[]const Bar.Entry{return if(e.rigMode)&rigItems else&formItems;}
/// the help with the forms: what the mouse does, and the keys' other ways
pub const help=[_][]const u8{
  "click a form's handle or its row: select it   ctrl+click: gather it into the group",
  "drag a value row left and right (shift: fine)   up/down: the value above or below",
  "drag the gizmo's handles (shift: fine)   middle drag: orbit   wheel: zoom",
  "shift with m, p or o (or a shift+click on its button): step back",
  "a tube curls by its curl; a nest places another sculpt, sized by its scale",
};
/// the help in rig mode
pub const rigHelp=[_][]const u8{
  "click a joint or its row: select it   drag a value row (shift: fine)",
  "the gizmo moves the joint (1) or test-turns its bone (2: never kept)",
  "shift+r: every bone back to rest   middle drag: orbit   wheel: zoom",
  "with the forms, o steps the bone a form rides",
};
/// the acts lit now: what the selected form is, the gizmo's mode, rig mode, the help
pub fn lit(e:*Editor)Set{
  // the lit ones so far
  var on=Set.initEmpty();
  on.setPresent(.rig,e.rigMode);
  on.setPresent(.help,e.helpShown);
  on.setPresent(.dots,e.dotsHidden);
  on.setPresent(.move,e.mode==.move);
  on.setPresent(.turn,e.mode==.turn);
  on.setPresent(.size,e.mode==.size);
  if(e.rigMode){
    if(e.doc.bones.items.len>0)on.setPresent(.twin,e.doc.bones.items[e.bsel].twin);
  }else if(e.pieces().len>0){
    // the selected form
    const p=e.pieces()[e.sel];
    on.setPresent(.carve,p.carve);
    on.setPresent(.ink,p.ink);
    on.setPresent(.twin,p.twin);
  }
  return on;
}
/// the acts that would do anything now
pub fn live(e:*Editor)Set{
  // all of them, then the ones that would do nothing taken out
  var on=Set.initFull();
  on.setPresent(.save,e.dirty);
  on.setPresent(.undo,e.history.back.items.len>0);
  on.setPresent(.redo,e.history.ahead.items.len>0);
  on.setPresent(.fromDisk,e.disk.clash);
  // how many things are listed (bones in rig mode, else forms), and the selected one
  const n=if(e.rigMode)e.doc.bones.items.len else e.pieces().len;
  const at=if(e.rigMode)e.bsel else e.sel;
  if(n==0)for([_]Act{.remove,.next,.raise,.lower,.name,.shape,.carve,.ink,.twin,.shader,.part,.bone,.snap,.rest,.focus})|a|on.remove(a);
  if(n<2)on.remove(.next);
  if(at==0)on.remove(.raise);
  if(at+1>=n)on.remove(.lower);
  if(!e.rigMode and n>0){
    on.setPresent(.part,e.pieces()[e.sel].kind==.nest);
    on.setPresent(.bone,e.doc.bones.items.len>0);
  }
  return on;
}
