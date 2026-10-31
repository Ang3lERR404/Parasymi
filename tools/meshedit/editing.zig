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
/// a keyboard key, named as the window library names it
const Key=engine.platform.input.Key;
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
/// whether key `k` went down this frame
fn hit(i:*const Input,k:Key)bool{return i.pressed(.{.key=k});}
/// one frame's keys and mouse; `handles` where each form's handle is on
/// screen (null behind the eye), the gizmo seen through `view` with the
/// sculpt at `origin`. While a form is being named the keys type its name
/// (enter or escape done), the mouse still answering.
pub fn handle(e:*Editor,in:*const Input,handles:[]const?[2]f32,view:gizmo.View,origin:V3)Allocator.Error!void{
  // whether shift is held (fine drags)
  const shift=in.down(.{.key=.left_shift}) or in.down(.{.key=.right_shift});
  // whether a name was being typed as the frame began
  const typing=e.naming!=null;
  if(e.naming)|*t|{
    if(e.pieces().len==0)e.naming=null else{
      if(t.feed(labels.keys(in))!=.same){
        e.pieces()[e.sel].name=.of(t.slice());
        e.dirty=true;
      }
      if(labels.named(in))e.naming=null;
    }
  }
  if(!typing)try answerKeys(e,in);
  try answerMouse(e,in,handles,view,origin,shift);
}
/// one frame's keys: forms made, removed, moved, reshaped, carved, shaded
/// and named; values stepped and set at rest; the gizmo's mode; the cells;
/// saving
fn answerKeys(e:*Editor,in:*const Input)Allocator.Error!void{
  // whether shift is held (shader back), and whether ctrl is
  const shift=in.down(.{.key=.left_shift}) or in.down(.{.key=.right_shift});
  const ctrl=in.down(.{.key=.left_control}) or in.down(.{.key=.right_control});
  // the allocator new forms are kept with
  const gpa=e.gpa;
  if(hit(in,.n)){
    // the new form: a copy of the selected one, a little off, else a fresh one
    var p:Piece=if(e.pieces().len>0)e.pieces()[e.sel]else.{};
    if(e.pieces().len>0)p.v.pos+=newOff;
    // where in the list it goes: just after the selected form
    const at=if(e.pieces().len>0)e.sel+1 else 0;
    try e.doc.pieces.insert(gpa,at,p);
    e.sel=at;
    e.changed();
  }
  if(e.pieces().len>0){
    if(hit(in,.delete)){
      _=e.doc.pieces.orderedRemove(e.sel);
      e.sel-|=@intFromBool(e.sel>=e.pieces().len);
      e.changed();
    }
  }
  if(e.pieces().len>0){
    // the forms, in order
    const pieceList=e.pieces();
    if(hit(in,.tab))e.sel=(e.sel+1)%pieceList.len;
    if(hit(in,.page_up) and e.sel>0){
      std.mem.swap(Piece,&pieceList[e.sel],&pieceList[e.sel-1]);
      e.sel-=1;
      e.changed();
    }
    if(hit(in,.page_down) and e.sel+1<pieceList.len){
      std.mem.swap(Piece,&pieceList[e.sel],&pieceList[e.sel+1]);
      e.sel+=1;
      e.changed();
    }
    // the selected form
    const p=&pieceList[e.sel];
    if(hit(in,.t)){
      p.kind=switch(p.kind){.ellipsoid=>.cone,.cone=>.box,.box=>.ellipsoid};
      e.changed();
    }
    if(hit(in,.c)){
      p.carve=!p.carve;
      e.changed();
    }
    if(hit(in,.m)){
      p.shade=nextShade(p.shade,if(shift).back else.on);
      e.changed();
    }
    if(hit(in,.up) and e.ch>0)e.ch-=1;
    if(hit(in,.down) and e.ch+1<Ch.count)e.ch+=1;
    if(hit(in,.r))e.set(Ch.get(&Vals{},e.ch));
    if(hit(in,.period))e.focus=true;
    if(hit(in,.enter) or hit(in,.kp_enter))e.naming=labels.typing(p.name.slice());
  }
  if(hit(in,.one))e.mode=.move;
  if(hit(in,.two))e.mode=.turn;
  if(hit(in,.three))e.mode=.size;
  if(hit(in,.left_bracket)){
    e.doc.cell=@max(cellMin,e.doc.cell-cellStep);
    e.changed();
  }
  if(hit(in,.right_bracket)){
    e.doc.cell+=cellStep;
    e.changed();
  }
  if(ctrl and hit(in,.s))e.save();
}
/// one frame's mouse: a press on a form row selects it, on a value row
/// selects it and drags it, on the gizmo drags its handle, on a handle in
/// view selects its form; any press ends naming
fn answerMouse(e:*Editor,in:*const Input,handles:[]const?[2]f32,view:gizmo.View,origin:V3,shift:bool)Allocator.Error!void{
  if(in.pressed(.{.button=.left}))e.naming=null;
  // the mouse (px)
  const mx=in.mouse[0];
  const my=in.mouse[1];
  // where the values start (px)
  const vy=valuesY(listRows(e.pieces().len));
  // the selected form's gizmo
  const g=e.gizmoAt(origin);
  // whether the mouse is over the panel, where the gizmo doesn't answer
  const ui=overUi(listRows(e.pieces().len),mx,my);
  e.hot=if(e.drag==.gizmo)e.part else if(g!=null and !ui)g.?.pick(view,in.mouse)else null;
  if(in.pressed(.{.button=.left})){
    if(mx<pad+listW and my>=listY and my<vy){
      // the form row pressed on, counted from the first in view
      const r:usize=@intFromFloat(@floor((my-listY)/row));
      if(e.top+r<e.pieces().len)e.sel=e.top+r;
    }else if(mx<pad+listW and my>=vy and my<vy+m.f(Ch.count)*row and e.pieces().len>0){
      e.ch=@intFromFloat(@floor((my-vy)/row));
      e.drag=.value;
    }else if(e.hot)|part|{
      e.part=part;
      e.drag=.gizmo;
    }else{
      // the nearest handle so far (px)
      var best:f32=pickRadius;
      for(handles,0..)|h,i|if(h)|at|{
        // how far this form's handle is from the mouse (px)
        const d=m.len(v3(at[0]-mx,at[1]-my,0));
        if(d<best){
          best=d;
          e.sel=i;
        }
      };
    }
  }
  if(!in.down(.{.button=.left}))e.drag=.none;
  if(e.pieces().len==0)e.drag=.none;
  if(e.drag==.value and in.mouseDelta[0]!=0){
    e.set(Ch.get(&e.pieces()[e.sel].v,e.ch)+in.mouseDelta[0]*e.rate()*(if(shift)fine else 1));
  }
  if(e.drag==.gizmo and (in.mouseDelta[0]!=0 or in.mouseDelta[1]!=0))if(g)|gz|{
    // where the mouse was last frame (px)
    const from=[2]f32{mx-in.mouseDelta[0],my-in.mouseDelta[1]};
    e.dragGizmo(gz,view,from,in.mouse,if(shift)fine else 1);
  };
  if(e.drag!=.gizmo)e.part=null;
  // the selection kept in view
  if(e.sel<e.top)e.top=e.sel;
  if(e.sel>=e.top+listRowCount)e.top=e.sel+1-listRowCount;
}
