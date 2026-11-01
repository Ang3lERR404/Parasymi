//! the animation editor's input: the timeline, the channel list and joint drags.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the allocator type keying may fail with
const Allocator=std.mem.Allocator;
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// all the maths: clamps, rounding
const m=engine.core.math;
/// keyframed clips: channels, keys and sampling
const clip=engine.anim.clip;
/// the keys and buttons held this frame
const Input=engine.platform.input.Input;
/// the game, reached through its import hub
const ps=@import("parasymi");
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
/// the editor's root, through which its other files are reached
const animedit=@import("../animedit.zig");
/// how much a drag changes a value per pixel
const dragRate=animedit.settings.dragRate;
/// the editor's state
const Editor=animedit.editor.Editor;
/// a time snapped to the nearest frame
const snap=Editor.snap;
/// the share of a drag shift keeps, for fine work
const fine=animedit.settings.fine;
/// the frame rate the playhead steps by
const fps=animedit.settings.fps;
/// the shortest a clip may be (s)
const lengthMin=animedit.settings.lengthMin;
/// how much `pgup`/`pgdn` lengthen or shorten a clip (s)
const lengthStep=animedit.settings.lengthStep;
/// how wide the channel list is (px)
const listW=animedit.settings.listW;
/// how far down the window the channel list starts (px)
const listY=animedit.settings.listY;
/// the gap round the panel's edges (px)
const pad=animedit.settings.pad;
/// the height of one channel's row (px)
const row=animedit.settings.row;
/// what the gizmo needs of the wolf this frame
const Rig=animedit.rigging.Rig;
/// whether a point is on the timeline
const inTimeline=animedit.editor.inTimeline;
/// every joint a gizmo turns
const joints=animedit.rigging.joints;
/// whether a point is over the channel list
const overList=animedit.editor.overList;
/// everything a key or a button does, and the keys that do them
const buttons=animedit.buttons;
/// everything a key or a button does
const Act=buttons.Act;
/// where the toolbar must end above the timeline and its caption (px)
const barBottom=animedit.settings.barBottom;
/// one frame's keys and mouse (`over` the list or the timeline), the
/// wolf's joints as `rg` sees them. While a mark is being named the keys
/// type its name (enter or escape done), the mouse still answering.
pub fn handle(e:*Editor,in:*const Input,screen:m.Vice(f32,2),dt:f32,rg:*const Rig)Allocator.Error!void{
  // whether shift is held (fine drags)
  const shift=in.down(.{.key=.left_shift}) or in.down(.{.key=.right_shift});
  // whether a name was being typed as the frame began
  const typing=e.naming!=null;
  if(e.naming)|*t|{
    if(t.feed(labels.keys(in))!=.same){
      try e.clip.mark(e.namingAt,t.slice());
      e.dirty=true;
    }
    if(labels.named(in))e.naming=null;
  }
  if(!typing)for(buttons.binds)|b|if(b.hit(in))try act(e,b.act,in);
  // the toolbar, and a button clicked on it
  e.bar.lay(buttons.all(),screen,barBottom(screen));
  if(e.bar.click(in,buttons.live(e)))|a|try act(e,a,in);
  if(e.playing){
    e.t+=dt;
    if(e.t>=e.clip.length)e.t=@mod(e.t,e.clip.length);
  }
  try answerMouse(e,in,screen,rg,shift);
  try e.settle();
}
/// act `a`, as its key or its button asks (shift, read from `in`, turns
/// the ease back and undo forward): playing, the playhead, the clip's
/// length, the channel, keying, eases, marks, copying and pasting, saving,
/// undo and redo
pub fn act(e:*Editor,a:Act,in:*const Input)Allocator.Error!void{
  // whether shift is held
  const shift=in.down(.{.key=.left_shift}) or in.down(.{.key=.right_shift});
  switch(a){
    .play=>e.playing=!e.playing,
    .frameBack,.frameOn=>{
      e.playing=false;
      // which way the playhead steps
      const dir:f32=if(a==.frameOn)1 else -1;
      e.t=m.clamp(snap(e.t)+dir/fps,0,e.clip.length);
    },
    .keyBack,.keyOn=>{
      e.playing=false;
      e.t=e.clip.nextKey(e.t,if(a==.keyOn)1 else -1) orelse e.t;
    },
    .start=>e.t=0,
    .longer,.shorter=>{
      e.clip.length=if(a==.longer)e.clip.length+lengthStep else@max(lengthMin,e.clip.length-lengthStep);
      e.t=@min(e.t,e.clip.length);
      e.dirty=true;
    },
    .prevChannel=>e.sel-|=1,
    .nextChannel=>if(e.sel+1<e.shown.len){e.sel+=1;},
    .key=>try e.key(e.sel),
    .keyAll=>for(0..e.shown.len)|i|try e.key(i),
    .unkey=>if(e.clip.remove(e.chName(e.sel),e.t)){e.dirty=true;},
    .rest=>{
      e.setValue(e.sel,e.rest(e.sel));
      if(e.clip.track(e.chName(e.sel))!=null)try e.key(e.sel);
    },
    .save=>e.save(),
    .undo=>if(shift)try e.redo()else try e.undo(),
    .redo=>try e.redo(),
    .copy=>e.copy(),
    .paste=>try e.paste(.plain),
    .pasteMirrored=>try e.paste(.mirrored),
    .ease=>e.turnEase(if(shift)-1 else 1),
    .focus=>e.focus=true,
    .mark=>try e.startMark(),
    .unmark=>if(e.clip.unmark(e.t)){e.dirty=true;},
    .help=>e.helpShown=!e.helpShown,
  }
}
/// one frame's mouse: a press on the timeline scrubs, on a row selects it
/// and drags its value, on the gizmo drags its handle, on a joint selects
/// it; any press ends naming
fn answerMouse(e:*Editor,in:*const Input,screen:m.Vice(f32,2),rg:*const Rig,shift:bool)Allocator.Error!void{
  if(in.pressed(.{.button=.left}))e.naming=null;
  // how many rows of the list fit the window
  const rows=e.fits(screen);
  // the mouse (px)
  const mx=in.mouse[0];
  const my=in.mouse[1];
  // the selected joint and its gizmo, if the wolf's
  const gz=e.gizmoAt(rg);
  // whether the mouse is over the toolbar, and over any panel, where gizmos don't answer
  const onBar=e.bar.over(in.mouse);
  const ui=onBar or overList(screen,mx,my) or inTimeline(screen,mx,my);
  e.hot=if(e.drag==.gizmo)e.part else if(gz!=null and !ui)gz.?.g.pick(rg.view,in.mouse)else null;
  if(in.pressed(.{.button=.left})){
    if(onBar){
      // the toolbar's own: its click comes as the button is let go
    }else if(inTimeline(screen,mx,my)){
      e.drag=.timeline;
      e.playing=false;
    }else if(mx<pad+listW and my>=listY){
      // the row pressed on, counted from the first in view
      const r:usize=@intFromFloat(@floor((my-listY)/row));
      if(r<rows and e.top+r<e.shown.len){
        e.sel=e.top+r;
        e.drag=.value;
      }
    }else if(e.hot)|part|{
      e.part=part;
      e.drag=.gizmo;
      e.playing=false;
    }else if(e.wolf()){
      if(e.pickJoint(rg,in.mouse))|j|e.sel=joints[j].chans[0].?;
    }
  }
  if(!in.down(.{.button=.left}))e.drag=.none;
  switch(e.drag){
    .none=>{},
    .timeline=>e.t=snap(m.clamp01((mx-pad)/(screen[0]-2*pad))*e.clip.length),
    .value=>if(in.mouseDelta[0]!=0){
      // how far a pixel of drag moves the value
      const rate=dragRate*(if(shift)fine else 1);
      e.setValue(e.sel,e.value(e.sel)+in.mouseDelta[0]*rate);
      try e.key(e.sel);
    },
    .gizmo=>if(gz)|z|if(in.mouseDelta[0]!=0 or in.mouseDelta[1]!=0){
      // where the mouse was last frame (px)
      const from=m.Vice(f32,2){mx-in.mouseDelta[0],my-in.mouseDelta[1]};
      try e.dragGizmo(z.j,z.g,rg,from,in.mouse,if(shift)fine else 1);
    },
  }
  if(e.drag!=.gizmo)e.part=null;
  if(overList(screen,mx,my) and in.scroll!=0){
    // the farthest the list may scroll, and this frame's scroll in rows
    const most=e.shown.len-|rows;
    const step:i32=@intFromFloat(-in.scroll*3);
    e.top=@intCast(m.clamp(@as(i32,@intCast(e.top))+step,0,@as(i32,@intCast(most))));
  }
  // the selection kept in view
  if(e.sel<e.top)e.top=e.sel;
  if(e.sel>=e.top+rows)e.top=e.sel+1-rows;
}
