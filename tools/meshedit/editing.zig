//! the mesh editor's input: keys, the value list and gizmo drags.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the allocator type a new form may fail with
const Allocator=std.mem.Allocator;
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// all the maths: vectors, lengths, rounding
const m=engine.core.math;
/// the keys and buttons held this frame
const Input=engine.platform.input.Input;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the move, turn and size handles on the selected form
const gizmo=@import("../gizmo.zig");
/// a point in the sculpt (m)
const V3=m.V3;
/// makes a `V3` from its three parts
const v3=m.v3;
/// the editors' words for values, and typed names
const labels=@import("../labels.zig");
/// the editor's root, through which its other files are reached
const meshedit=@import("../meshedit.zig");
/// the finest the cells may be (m)
const cellMin=meshedit.settings.cellMin;
/// how much `[`/`]` widen or narrow the cells (m)
const cellStep=meshedit.settings.cellStep;
/// every value of a form, each a named channel
const Ch=meshedit.settings.Ch;
/// the editor's state
const Editor=meshedit.editor.Editor;
/// the rig mode: the bones listed, placed and test-turned
const rigging=meshedit.rigging;
/// the share of a drag shift keeps, for fine work
const fine=meshedit.settings.fine;
/// the most form rows shown at once
const listRowCount=meshedit.settings.listRowCount;
/// how wide the form list is (px)
const listW=meshedit.settings.listW;
/// how far down the window the form list starts (px)
const listY=meshedit.settings.listY;
/// how far a new form stands from the one it was made from (m)
const newOff=meshedit.settings.newOff;
/// the gap round the panel's edges (px)
const pad=meshedit.settings.pad;
/// how near (px) a click must land to pick a form's handle
const pickRadius=meshedit.settings.pickRadius;
/// one form of the sculpt
const Piece=meshedit.doc.Piece;
/// the height of one row (px)
const row=meshedit.settings.row;
/// a form's numbers, at rest
const Vals=meshedit.settings.Vals;
/// how many form rows show
const listRows=meshedit.settings.listRows;
/// the shader after (or before) a form's
const nextShade=meshedit.settings.nextShade;
/// whether a point is over the panel
const overUi=meshedit.settings.overUi;
/// where the values start under the form rows
const valuesY=meshedit.settings.valuesY;
/// everything a key or a button does, and the keys that do them
const buttons=meshedit.buttons;
/// everything a key or a button does
const Act=buttons.Act;
/// one frame's keys and mouse; `handles` where each form's handle is on
/// screen (null behind the eye), the gizmo seen through `view` with the
/// sculpt at `origin`. While a form is being named the keys type its name
/// (enter or escape done), the mouse still answering.
pub fn handle(e:*Editor,in:*const Input,handles:[]const?[2]f32,view:gizmo.View,origin:V3)Allocator.Error!void{
  // whether shift is held (fine drags)
  const shift=in.down(.{.key=.left_shift}) or in.down(.{.key=.right_shift});
  // whether a name was being typed as the frame began
  const typing=e.naming!=null or e.renaming!=null;
  if(e.renaming)|*t|{
    _=t.feed(labels.keys(in));
    if(in.pressed(.{.key=.escape}))e.renaming=null
    else if(labels.named(in)){
      // the name typed, kept while the typing ends
      var name:[labels.nameCap]u8=undefined;
      const n=t.slice().len;
      @memcpy(name[0..n],t.slice());
      e.renaming=null;
      try e.renameTo(name[0..n]);
    }
  }
  if(e.naming)|*t|{
    // how many things there are to name: bones in rig mode, else forms
    const nameable=if(e.rigMode)e.doc.bones.items.len else e.pieces().len;
    if(nameable==0)e.naming=null else{
      if(t.feed(labels.keys(in))!=.same){
        if(e.rigMode)rigging.rename(e,t.slice())else{
          e.pieces()[e.sel].name=.of(t.slice());
          e.dirty=true;
        }
      }
      if(labels.named(in))e.naming=null;
    }
  }
  // the selected form's values as the frame began (its group follows
  // whatever this frame does to its place and turn), and which it was
  const was:?Vals=if(e.pieces().len>0 and !e.rigMode)e.pieces()[e.sel].v else null;
  const wasSel=e.sel;
  const wasCount=e.pieces().len;
  if(!typing)for(buttons.binds)|b|if(b.hit(in))try act(e,b.act,in);
  // the toolbar, laid out for the mode as it is, and a button clicked on it
  e.bar.lay(buttons.items(e),view.screen,view.screen[1]-pad);
  if(e.bar.click(in,buttons.live(e)))|a|try act(e,a,in);
  try answerMouse(e,in,handles,view,origin,shift);
  if(was)|w|if(e.sel==wasSel and e.pieces().len==wasCount)e.follow(w);
  try e.settle();
}
/// act `a`, as its key or its button asks (shift, read from `in`, steps
/// back or does every bone): the mode, the help, saving, undo and redo, the
/// gizmo's mode and the cells here; the rest the forms' (or the bones')
pub fn act(e:*Editor,a:Act,in:*const Input)Allocator.Error!void{
  // whether shift is held
  const shift=in.down(.{.key=.left_shift}) or in.down(.{.key=.right_shift});
  switch(a){
    .rig=>{
      e.rigMode=!e.rigMode;
      e.ch=0;
      if(e.mode==.size)e.mode=.move;
      e.say("{s}",.{if(e.rigMode)"rig mode: the bones"else"the forms"});
    },
    .help=>e.helpShown=!e.helpShown,
    .save=>e.save(),
    .undo=>if(shift)try e.redo()else try e.undo(),
    .redo=>try e.redo(),
    .move=>e.mode=.move,
    .turn=>e.mode=.turn,
    .size=>if(!e.rigMode){e.mode=.size;},
    .finer=>{
      e.doc.cell=@max(cellMin,e.doc.cell-cellStep);
      e.changed();
    },
    .coarser=>{
      e.doc.cell+=cellStep;
      e.changed();
    },
    else=>if(e.rigMode)try rigging.act(e,a,shift)else try formAct(e,a,shift),
  }
}
/// an act on the forms (`shift` held with it): forms made, removed, moved,
/// reshaped, carved, inked, twinned, shaded, snapped, put on a bone and
/// named; values stepped and set at rest
fn formAct(e:*Editor,a:Act,shift:bool)Allocator.Error!void{
  // the allocator new forms are kept with
  const gpa=e.gpa;
  if(a==.make){
    // the new form: a copy of the selected one, a little off, else a fresh one
    var p:Piece=if(e.pieces().len>0)e.pieces()[e.sel]else.{};
    if(e.pieces().len>0)p.v.pos+=newOff;
    // where in the list it goes: just after the selected form
    const at=if(e.pieces().len>0)e.sel+1 else 0;
    try e.doc.pieces.insert(gpa,at,p);
    e.sel=at;
    return e.changed();
  }
  if(e.pieces().len==0)return;
  // the forms, in order, and the selected one
  const pieceList=e.pieces();
  const p=&pieceList[e.sel];
  switch(a){
    .remove=>{
      _=e.doc.pieces.orderedRemove(e.sel);
      e.sel-|=@intFromBool(e.sel>=e.pieces().len);
      e.changed();
    },
    .next=>e.sel=(e.sel+1)%pieceList.len,
    .raise=>if(e.sel>0){
      std.mem.swap(Piece,&pieceList[e.sel],&pieceList[e.sel-1]);
      e.sel-=1;
      e.changed();
    },
    .lower=>if(e.sel+1<pieceList.len){
      std.mem.swap(Piece,&pieceList[e.sel],&pieceList[e.sel+1]);
      e.sel+=1;
      e.changed();
    },
    .shape=>{
      p.kind=switch(p.kind){.ellipsoid=>.cone,.cone=>.box,.box=>.tube,.tube=>.nest,.nest=>.ellipsoid};
      // a nest starts at its sculpt's own size, using the first other sculpt
      if(p.kind==.nest){
        p.v.size=.{1,1,1};
        if(p.use.len==0)e.stepPart(p,false);
      }else if(p.kind==.ellipsoid)p.v.size=(Vals{}).size;
      e.changed();
    },
    .carve=>{
      p.carve=!p.carve;
      p.ink=false;
      e.changed();
    },
    .part=>if(p.kind==.nest)e.stepPart(p,shift),
    .ink=>{
      p.ink=!p.ink;
      p.carve=false;
      e.changed();
    },
    .snap=>e.snap(),
    .twin=>{
      p.twin=!p.twin;
      e.changed();
    },
    .shader=>{
      p.shade=nextShade(p.shade,if(shift).back else.on);
      e.changed();
    },
    .bone=>rigging.stepBone(e,shift),
    .prevValue=>e.ch-|=1,
    .nextValue=>if(e.ch+1<Ch.count){e.ch+=1;},
    .rest=>e.set(Ch.get(&Vals{},e.ch)),
    .focus=>e.focus=true,
    .name=>e.naming=labels.typing(p.name.slice()),
    else=>{},
  }
}
/// one frame's mouse: a press on a form row selects it, on a value row
/// selects it and drags it, on the gizmo drags its handle, on a handle in
/// view selects its form; any press ends naming
fn answerMouse(e:*Editor,in:*const Input,handles:[]const?[2]f32,view:gizmo.View,origin:V3,shift:bool)Allocator.Error!void{
  if(in.pressed(.{.button=.left})){
    e.naming=null;
    e.renaming=null;
  }
  // whether ctrl is held: a click then gathers a form into the group (or lets it go)
  const ctrl=in.down(.{.key=.left_control}) or in.down(.{.key=.right_control});
  // the mouse (px)
  const mx=in.mouse[0];
  const my=in.mouse[1];
  // what the list holds (bones in rig mode, else forms), and how many values each shows
  const inRig=e.rigMode;
  const listed=if(inRig)e.doc.bones.items.len else e.pieces().len;
  const valueCount:usize=if(inRig)rigging.valueRows else Ch.count;
  // where the values start (px)
  const vy=valuesY(listRows(listed));
  // the selected form's (or bone's) gizmo
  const g=if(inRig)rigging.gizmoAt(e,origin)else e.gizmoAt(origin);
  // whether the mouse is over the toolbar, and over any panel, where the gizmo doesn't answer
  const onBar=e.bar.over(in.mouse);
  const onName=e.overName(in.mouse);
  const ui=onBar or onName or overUi(listRows(listed),mx,my);
  e.hot=if(e.drag==.gizmo)e.part else if(g!=null and !ui)g.?.pick(view,in.mouse)else null;
  if(in.pressed(.{.button=.left})){
    if(onBar){
      // the toolbar's own: its click comes as the button is let go
    }else if(onName){
      e.renaming=labels.typing(e.ownName());
    }else if(mx<pad+listW and my>=listY and my<vy){
      // the row pressed on, counted from the first in view
      const r:usize=@intFromFloat(@floor((my-listY)/row));
      if(inRig){
        if(r<listed)e.bsel=r;
      }else if(e.top+r<listed)e.pick(e.top+r,ctrl);
    }else if(mx<pad+listW and my>=vy and my<vy+m.f(valueCount)*row and listed>0){
      e.ch=@intFromFloat(@floor((my-vy)/row));
      e.drag=.value;
    }else if(e.hot)|part|{
      e.part=part;
      e.drag=.gizmo;
    }else{
      // the nearest handle so far (px), and its form
      var best:f32=pickRadius;
      var near:?usize=null;
      for(handles,0..)|h,i|if(h)|at|{
        // how far this form's handle is from the mouse (px)
        const d=m.len(v3(at[0]-mx,at[1]-my,0));
        if(d<best){
          best=d;
          near=i;
        }
      };
      if(near)|i|{
        if(inRig)e.bsel=i else e.pick(i,ctrl);
      }
    }
  }
  if(!in.down(.{.button=.left}))e.drag=.none;
  if(listed==0)e.drag=.none;
  // the share of a drag kept: all, or with shift a little for fine work
  const k:f32=if(shift)fine else 1;
  if(e.drag==.value and in.mouseDelta[0]!=0){
    if(inRig)rigging.setValue(e,e.ch,rigging.value(e,e.ch)+in.mouseDelta[0]*rigging.rate(e.ch)*k)
    else e.set(Ch.get(&e.pieces()[e.sel].v,e.ch)+in.mouseDelta[0]*e.rate()*k);
  }
  if(e.drag==.gizmo and (in.mouseDelta[0]!=0 or in.mouseDelta[1]!=0))if(g)|gz|{
    // where the mouse was last frame (px)
    const from=[2]f32{mx-in.mouseDelta[0],my-in.mouseDelta[1]};
    if(inRig)rigging.dragGizmo(e,gz,view,from,in.mouse,k)else e.dragGizmo(gz,view,from,in.mouse,k);
  };
  if(e.drag!=.gizmo)e.part=null;
  // the selection kept in view
  if(e.sel<e.top)e.top=e.sel;
  if(e.sel>=e.top+listRowCount)e.top=e.sel+1-listRowCount;
}
