//! the animation editor's state: the clip, the selected channel and key, saving.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the allocator type the clip keeps its keys with
const Allocator=std.mem.Allocator;
/// the I/O interface, for saving clips
const Io=std.Io;
/// a directory, for writing a clip under the repo
const Dir=Io.Dir;
/// a text writer, which a clip is written into
const Writer=Io.Writer;
/// formats text into a fixed buffer (the note)
const bufPrint=std.fmt.bufPrint;
/// trades two values in place (the clip for the one read back)
const swap=std.mem.swap;
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// all the maths: vectors, clamps, lengths
const m=engine.core.math;
/// keyframed clips: channels, keys and sampling
const clip=engine.anim.clip;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the move and turn handles a joint is dragged by
const gizmo=@import("../gizmo.zig");
/// the wolf's skeleton and its `Pose`
const skel=ps.skeleton;
/// one plant or structure standing alone, and its `Look`
const specimen=ps.specimen;
/// every f32 of the wolf's `Pose`, each a channel a clip can key
const PoseCh=clip.Channels(skel.Pose);
/// every f32 of a specimen's `Look`, each a channel a clip can key
const LookCh=clip.Channels(specimen.Look);
/// the editors' words for values, and typed names
const labels=@import("../labels.zig");
/// undo and redo: each settled clip kept as its text
const History=@import("../history.zig").History;
/// the editor's root, through which its other files are reached
const animedit=@import("../animedit.zig");
/// a rigged sculpt the clip may move
const sculptRig=animedit.sculpt;
/// each pose channel in words
const poseLabels=animedit.settings.poseLabels;
/// each look channel in words
const lookLabels=animedit.settings.lookLabels;
/// where clips are kept
const dir=animedit.settings.dir;
/// what is being dragged
const Drag=animedit.rigging.Drag;
/// the frame rate the playhead snaps to
const fps=animedit.settings.fps;
/// how near (px) a click must land to pick a joint
const jointPick=animedit.settings.jointPick;
/// a joint of the wolf's pose
const Joint=animedit.rigging.Joint;
/// how wide the channel list is (px)
const listW=animedit.settings.listW;
/// how far down the window the channel list starts (px)
const listY=animedit.settings.listY;
/// the gap round the panel's edges (px)
const pad=animedit.settings.pad;
/// what the gizmo needs of the wolf this frame
const Rig=animedit.rigging.Rig;
/// who the clip moves: the wolf or one thing alone
const Subject=animedit.rigging.Subject;
/// how far above the window's bottom the timeline sits (px)
const tlBottom=animedit.settings.tlBottom;
/// the timeline's height (px)
const tlH=animedit.settings.tlH;
/// a joint's gizmo, its axes those its channels move it along
const gizmoOf=animedit.rigging.gizmoOf;
/// the joint a pose channel belongs to
const jointOf=animedit.rigging.jointOf;
/// every joint a gizmo turns
const joints=animedit.rigging.joints;
/// where a pose channel goes in the wolf's mirror image
const Mirror=animedit.rigging.Mirror;
/// each pose channel's place in the mirror
const mirrors=animedit.rigging.mirrors;
/// how a key runs on to the next
const Ease=clip.Ease;
/// how many eases there are, which `e` cycles round
const easeCount=@typeInfo(Ease).@"enum".fields.len;
/// the test helpers
const testing=std.testing;
/// the most channels a subject shows, and so the most keys copied at once
const most=@max(PoseCh.count,LookCh.count);
/// one key copied: its row, its value and its ease
pub const Held=struct{
  /// the row (into `shown`) it was keyed on
  row:usize,
  /// the value it held
  v:f32,
  /// how it ran on to its next key
  ease:Ease,
};
/// how copied keys are pasted: as they were, or the wolf's left and right traded
pub const Paste=enum{
  /// each key back on its own channel
  plain,
  /// each key on its channel across the wolf's middle, turned as a mirror turns it
  mirrored,
};
/// the editor: the clip being keyed, what it moves, the playhead, the
/// selection and what is held
pub const Editor=struct{
  /// the allocator the clip and the save keep memory with
  gpa:Allocator,
  /// the I/O the clip is saved through
  io:Io,
  /// who the clip moves
  subject:Subject,
  /// a rigged sculpt's bones and channels, when the clip moves one
  sculpt:?*sculptRig.Sculpt=null,
  /// where the clip is kept (`src/anim/<name>.anim`)
  path:[]const u8,
  /// the clip being keyed
  clip:clip.Clip,
  /// what is shown: the clip sampled at the playhead over the values set
  /// by hand where a channel has no keys
  pose:skel.Pose=.{},
  /// what is shown of a plant or structure alone, as `pose` is the wolf's
  look:specimen.Look=.{},
  /// the playhead (s)
  t:f32=0,
  /// whether the clip is playing on its own
  playing:bool=false,
  /// the channels shown (indices into `PoseCh` or `LookCh`), the one
  /// selected (into `shown`) and the first row in view
  shown:[]const usize,
  sel:usize=0,
  /// the first row of the list in view, as it scrolls
  top:usize=0,
  /// what the mouse is dragging
  drag:Drag=.none,
  /// the gizmo's handle held, and the one under the mouse
  part:?gizmo.Part=null,
  hot:?gizmo.Part=null,
  /// whether the clip has changed since it was last saved
  dirty:bool=false,
  /// the camera is asked onto the selected joint (or the subject)
  focus:bool=false,
  /// the last note shown under the help (saved, failed, ...)
  note:[96]u8=undefined,
  /// how much of `note` is written
  noteLen:usize=0,
  /// a mark's name as it is typed (null: not naming), the keys answering
  /// only it meanwhile
  naming:?labels.Typed=null,
  /// when the mark being named falls (s)
  namingAt:f32=0,
  /// the clips before and after this one, for undo and redo
  history:History,
  /// the keys copied (`ctrl+c`), the first `copiedLen` of them held
  copied:[most]Held=undefined,
  /// how many keys are copied
  copiedLen:usize=0,
  /// the toolbar down the right side: a button for every act
  bar:animedit.buttons.Bar=.{},
  /// the help (`h`): what the mouse does, and the keys' other ways
  helpShown:bool=false,
  /// the selected channel's key at the playhead given the next ease
  /// round (`way` 1) or the one before (-1), saying which
  pub fn turnEase(e:*Editor,way:i32)void{
    // the channel's name, and its key at the playhead
    const name=e.chName(e.sel);
    const k=e.clip.keyAt(name,e.t) orelse return e.say("no key here to ease",.{});
    // the ease round from the key's own
    const ea:Ease=@enumFromInt(@mod(@as(i32,@intFromEnum(k.ease))+way,@as(i32,easeCount)));
    _=e.clip.ease(name,e.t,ea);
    e.dirty=true;
    e.say("ease {t}",.{ea});
  }
  /// every channel's key at the playhead copied, with its ease, saying how many
  pub fn copy(e:*Editor)void{
    e.copiedLen=0;
    for(0..e.shown.len)|i|if(e.clip.keyAt(e.chName(i),e.t))|k|{
      e.copied[e.copiedLen]=.{.row=i,.v=k.v,.ease=k.ease};
      e.copiedLen+=1;
    };
    e.say("copied {d} keys",.{e.copiedLen});
  }
  /// the copied keys keyed at the playhead, `how` says on which channels
  /// (only the wolf has sides to trade; a thing pastes plain either way)
  pub fn paste(e:*Editor,how:Paste)Allocator.Error!void{
    if(e.copiedLen==0)return e.say("nothing copied",.{});
    // whether the keys go across the wolf's middle
    const across=how==.mirrored and e.wolf();
    for(e.copied[0..e.copiedLen])|h|{
      // where the key goes, and the sign its value takes there
      const mr:Mirror=if(across)mirrors[e.shown[h.row]]else.{.ch=e.shown[h.row],.sign=1};
      const r=e.rowOf(mr.ch) orelse continue;
      e.setValue(r,mr.sign*h.v);
      try e.clip.putEased(e.chName(r),e.t,e.value(r),h.ease);
    }
    e.playing=false;
    e.dirty=true;
    e.say("pasted {d} keys{s}",.{e.copiedLen,if(across)" mirrored"else""});
  }
  /// the row showing channel `ch`, if one does
  fn rowOf(e:*const Editor,ch:usize)?usize{
    for(e.shown,0..)|c,i|if(c==ch)return i;
    return null;
  }
  /// the clip as it is now kept in the history, once the hands let go (no
  /// drag held, no mark being named): a whole drag is one step back
  pub fn settle(e:*Editor)Allocator.Error!void{
    if(e.drag!=.none or e.naming!=null)return;
    // the clip's text now
    const now=try text(e.gpa,&e.clip);
    defer e.gpa.free(now);
    _=try e.history.settle(now);
  }
  /// one step back through the history, saying so (nothing while a drag is held)
  pub fn undo(e:*Editor)Allocator.Error!void{
    if(e.drag!=.none)return;
    try e.settle();
    e.restore(try e.history.undo(),"undone","nothing to undo");
  }
  /// one step forward again, saying so (nothing while a drag is held)
  pub fn redo(e:*Editor)Allocator.Error!void{
    if(e.drag!=.none)return;
    try e.settle();
    e.restore(try e.history.redo(),"redone","nothing to redo");
  }
  /// a whole edited clip `t` (Claude's, through the link) taken as one
  /// step of the history, so undo takes it back; what happened, written
  /// into `buf` for Claude (refused while the gardener's hands are on it)
  pub fn adopt(e:*Editor,t:[]const u8,buf:[]u8)Allocator.Error![]const u8{
    if(e.drag!=.none or e.naming!=null)return bufPrint(buf,"not taken: the gardener is dragging or typing; try again",.{})catch"busy";
    try e.settle();
    // the edited clip, read whole before the old one goes
    var back=clip.Clip.parse(e.gpa,t)catch|er|return bufPrint(buf,"not taken: the text does not read ({t})",.{er})catch"not taken";
    for(0..e.shown.len)|i|{
      if(e.clip.track(e.chName(i))!=null and back.track(e.chName(i))==null)e.setValue(i,e.rest(i));
    }
    swap(clip.Clip,&e.clip,&back);
    back.deinit();
    e.t=@min(e.t,e.clip.length);
    e.playing=false;
    e.sample();
    e.dirty=true;
    try e.settle();
    e.say("claude's edit taken (ctrl+z takes it back)",.{});
    return bufPrint(buf,"taken: {d} channels keyed, {d:.2} s long; ctrl+z in the editor undoes it",.{e.clip.tracks.items.len,e.clip.length})catch"taken";
  }
  /// the clip read back from the history's `kept` text (null: `none`
  /// said) and shown at the playhead; a channel whose keys all went back
  /// to its rest
  fn restore(e:*Editor,kept:?[]const u8,done:[]const u8,none:[]const u8)void{
    // the text to read, if there was a step to take
    const t=kept orelse return e.say("{s}",.{none});
    // the clip as it was then (the history's own text, which reads back)
    var back=clip.Clip.parse(e.gpa,t)catch|er|return e.say("{s} failed: {t}",.{done,er});
    for(0..e.shown.len)|i|{
      if(e.clip.track(e.chName(i))!=null and back.track(e.chName(i))==null)e.setValue(i,e.rest(i));
    }
    swap(clip.Clip,&e.clip,&back);
    back.deinit();
    e.t=@min(e.t,e.clip.length);
    e.naming=null;
    e.playing=false;
    e.sample();
    e.dirty=true;
    e.say("{s}",.{done});
  }
  /// the selected channel's joint and its gizmo (the wolf's alone)
  pub fn gizmoAt(e:*const Editor,rg:*const Rig)?struct{j:Joint,g:gizmo.Gizmo}{
    if(!e.wolf())return null;
    // the selected channel's joint
    const j=joints[jointOf(e.shown[e.sel]) orelse return null];
    return.{.j=j,.g=gizmoOf(j,&e.pose,&rg.bones,rg.heading)};
  }
  /// channel `ch` of the pose changed by `by` and keyed (the wolf shows
  /// every channel, so `ch` is its row too)
  pub fn nudge(e:*Editor,ch:usize,by:f32)Allocator.Error!void{
    e.setValue(ch,e.value(ch)+by);
    try e.key(ch);
  }
  /// a drag of the held handle from `from` to `to` (px), `k` of it
  pub fn dragGizmo(e:*Editor,j:Joint,g:gizmo.Gizmo,rg:*const Rig,from:m.Vice(f32,2),to:m.Vice(f32,2),k:f32)Allocator.Error!void{
    // the handle held, if any
    const part=e.part orelse return;
    switch(part){
      // the hips moved across the view: back into wolf space
      .free=>{
        // the drag across the view, in the world, `k` of it
        const by=g.across(rg.view,from,to)*m.splat3(k);
        for(j.chans,g.axes)|c,a|try e.nudge(c.?,m.dot(by,a.?));
      },
      .x,.y,.z=>{
        // the axis the handle turns or moves along, and its channel
        const i=@intFromEnum(part);
        const c=j.chans[i] orelse return;
        try e.nudge(c,g.along(rg.view,i,from,to)*k);
        e.sel=c;
      },
    }
  }
  /// the joint whose dot is under `mouse`; again on the selected one, the
  /// next under it
  pub fn pickJoint(e:*const Editor,rg:*const Rig,mouse:m.Vice(f32,2))?usize{
    // the joint selected now
    const cur=jointOf(e.shown[e.sel]);
    // the nearest joint under the mouse, and how near
    var best:?usize=null;
    var near:f32=jointPick;
    // the first joint under the mouse after the selected one
    var after:?usize=null;
    // whether the selected joint is under the mouse too
    var curUnder=false;
    for(joints,0..)|j,i|{
      // the joint's dot on the screen (px)
      const at=rg.view.project(m.origin(rg.bones[@intFromEnum(j.bone)])) orelse continue;
      // how far it is from the mouse (px)
      const d=m.len(m.v3(at[0]-mouse[0],at[1]-mouse[1],0));
      if(d>=jointPick)continue;
      if(cur!=null and i==cur.?)curUnder=true;
      if(cur!=null and i>cur.? and after==null)after=i;
      if(d<near){
        near=d;
        best=i;
      }
    }
    if(curUnder){
      if(after)|a|return a;
      // round to the first under the mouse
      for(joints,0..)|j,i|{
        // this joint's dot on the screen (px)
        const at=rg.view.project(m.origin(rg.bones[@intFromEnum(j.bone)])) orelse continue;
        if(m.len(m.v3(at[0]-mouse[0],at[1]-mouse[1],0))<jointPick)return i;
      }
    }
    return best;
  }
  /// whether the clip moves the wolf (else one thing alone, or a sculpt)
  pub fn wolf(e:*const Editor)bool{return e.subject==.wolf;}
  /// the name of row `i`'s channel, as the clip keys it
  pub fn chName(e:*const Editor,i:usize)[]const u8{
    if(e.sculpt)|sc|return sc.names[e.shown[i]];
    return if(e.wolf())PoseCh.names[e.shown[i]]else LookCh.names[e.shown[i]];
  }
  /// the name of row `i`'s channel in words, as the panel shows it
  pub fn chLabel(e:*const Editor,i:usize)[]const u8{
    if(e.sculpt)|sc|return sc.words[e.shown[i]];
    return if(e.wolf())poseLabels[e.shown[i]]else lookLabels[e.shown[i]];
  }
  /// the mark at the playhead's name, if one is there
  pub fn markHere(e:*const Editor)?[]const u8{
    return if(e.clip.markAt(e.t))|i|e.clip.marks.items[i].name else null;
  }
  /// a mark at the playhead (made if none is there), its name to be typed
  pub fn startMark(e:*Editor)Allocator.Error!void{
    if(e.markHere()==null){
      try e.clip.mark(e.t,"");
      e.dirty=true;
    }
    e.playing=false;
    e.naming=labels.typing(e.markHere().?);
    e.namingAt=e.t;
  }
  /// row `i`'s value shown now
  pub fn value(e:*const Editor,i:usize)f32{
    if(e.sculpt)|sc|return sc.vals[e.shown[i]];
    return if(e.wolf())PoseCh.get(&e.pose,e.shown[i])else LookCh.get(&e.look,e.shown[i]);
  }
  /// set row `i`'s value (a look's kept within 0..1)
  pub fn setValue(e:*Editor,i:usize,v:f32)void{
    if(e.sculpt)|sc|sc.vals[e.shown[i]]=v
    else if(e.wolf())PoseCh.set(&e.pose,e.shown[i],v)else LookCh.set(&e.look,e.shown[i],m.clamp01(v));
  }
  /// its value at rest (the default pose or look; a sculpt's none)
  pub fn rest(e:*const Editor,i:usize)f32{
    if(e.sculpt!=null)return 0;
    return if(e.wolf())PoseCh.get(&skel.Pose{},e.shown[i])else LookCh.get(&specimen.Look{},e.shown[i]);
  }
  /// every keyed channel set from the clip at the playhead
  pub fn sample(e:*Editor)void{
    for(0..e.shown.len)|i|if(e.clip.sample(e.chName(i),e.t))|v|e.setValue(i,v);
  }
  /// key row `i` at the playhead with its value now
  pub fn key(e:*Editor,i:usize)Allocator.Error!void{
    try e.clip.put(e.chName(i),e.t,e.value(i));
    e.dirty=true;
  }
  /// show a note under the help, cut to fit its buffer
  pub fn say(e:*Editor,comptime fmt:[]const u8,args:anytype)void{
    e.noteLen=if(bufPrint(&e.note,fmt,args))|w|w.len else|_|e.note.len;
  }
  /// write the clip to its file, making `src/anim` if need be, and say how
  /// that went
  pub fn save(e:*Editor)void{
    // the I/O the save goes through
    const io=e.io;
    // the clip's text, written into memory first
    var out:Writer.Allocating=.init(e.gpa);
    defer out.deinit();
    e.clip.write(&out.writer) catch return e.say("save failed: out of memory",.{});
    Dir.cwd().createDirPath(io,dir)catch|er|return e.say("save failed: {t}",.{er});
    Dir.cwd().writeFile(io,.{.sub_path=e.path,.data=out.written()})catch|er|return e.say("save failed: {t}",.{er});
    e.dirty=false;
    e.say("saved {s}",.{e.path});
  }
  /// time `t` (s) snapped to the nearest frame
  pub fn snap(t:f32)f32{return@round(t*fps)/fps;}
  /// answers the keys and mouse each frame
  pub const handle=animedit.editing.handle;
  /// whether the panel fits the window
  pub const fits=animedit.panel.fits;
  /// draws the panel, the timeline and the joints
  pub const draw=animedit.panel.draw;
};
/// clip `c` as the text its file would hold, the caller's to free
pub fn text(gpa:Allocator,c:*const clip.Clip)Allocator.Error![]u8{
  // the text, written into memory
  var out:Writer.Allocating=.init(gpa);
  defer out.deinit();
  c.write(&out.writer) catch return error.OutOfMemory;
  return out.toOwnedSlice();
}
/// whether (`x`,`y`) (px) is on the timeline, with a little slack round it
pub fn inTimeline(screen:m.Vice(f32,2),x:f32,y:f32)bool{
  // the timeline's top edge (px)
  const ty=screen[1]-tlBottom-tlH;
  return y>=ty-8 and y<=ty+tlH+8 and x>=pad-8 and x<=screen[0]-pad+8;
}
/// whether (`x`,`y`) (px) is over the channel list
pub fn overList(screen:m.Vice(f32,2),x:f32,y:f32)bool{
  return x<pad+listW and y>=listY and y<screen[1]-tlBottom-tlH-pad;
}
/// every pose channel's index, in order: the wolf shows them all
pub const allPose=blk:{
  // the indices being filled
  var a:[PoseCh.count]usize=undefined;
  for(&a,0..)|*o,i|o.*=i;
  break:blk a;
};
/// every look channel's index, in order: a plant shows them all
pub const allLook=blk:{
  // the indices being filled
  var a:[LookCh.count]usize=undefined;
  for(&a,0..)|*o,i|o.*=i;
  break:blk a;
};
/// a structure shows only its growth
pub const growthOnly=[_]usize{LookCh.find("growth").?};
test"a key's ease cycles round, keys copy and paste (mirrored across the wolf), and a paste undoes"{
  // the testing allocator, an empty clip of the wolf, and the editor on it
  const gpa=testing.allocator;
  var c=try clip.Clip.init(gpa,"wolf");
  // the clip's text as it starts
  const first=try text(gpa,&c);
  defer gpa.free(first);
  var e:Editor=.{.gpa=gpa,.io=testing.io,.subject=.wolf,.path="unused",.clip=c,.shown=&allPose,.history=try .init(gpa,first)};
  defer e.clip.deinit();
  defer e.history.deinit();
  // the left shoulder's twist and pitch, and the jaw, keyed at the start
  const twist=PoseCh.find("arms.0.root.y").?;
  const pitch=PoseCh.find("arms.0.root.x").?;
  const jaw=PoseCh.find("jaw").?;
  for([_]usize{twist,pitch,jaw},[_]f32{0.4,-0.3,0.2})|ch,v|{
    e.setValue(ch,v);
    try e.key(ch);
  }
  // the twist's key eased round to `back`, the last, and on round to smooth
  e.sel=twist;
  e.turnEase(-1);
  try testing.expectEqual(Ease.back,e.clip.keyAt("arms.0.root.y",0).?.ease);
  e.turnEase(1);
  try testing.expectEqual(Ease.smooth,e.clip.keyAt("arms.0.root.y",0).?.ease);
  e.turnEase(-1);
  try e.settle();
  e.copy();
  try testing.expectEqual(@as(usize,3),e.copiedLen);
  // pasted as they were a second on
  e.t=1;
  try e.paste(.plain);
  try testing.expectEqual(@as(f32,0.4),e.clip.keyAt("arms.0.root.y",1).?.v);
  try testing.expectEqual(Ease.back,e.clip.keyAt("arms.0.root.y",1).?.ease);
  try e.settle();
  // pasted mirrored a second later: onto the right shoulder, the twist turned round
  e.t=2;
  try e.paste(.mirrored);
  try testing.expectEqual(@as(f32,-0.4),e.clip.keyAt("arms.1.root.y",2).?.v);
  try testing.expectEqual(Ease.back,e.clip.keyAt("arms.1.root.y",2).?.ease);
  try testing.expectEqual(@as(f32,-0.3),e.clip.keyAt("arms.1.root.x",2).?.v);
  try testing.expectEqual(@as(f32,0.2),e.clip.keyAt("jaw",2).?.v);
  try testing.expect(e.clip.keyAt("arms.0.root.y",2)==null);
  // the mirrored paste is one step back
  try e.settle();
  try e.undo();
  try testing.expect(e.clip.keyAt("arms.1.root.y",2)==null);
  try testing.expect(e.clip.keyAt("arms.0.root.y",1)!=null);
}
