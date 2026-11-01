//! the mesh editor's panel: the form list, the values, the toolbar and the help.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the allocator type drawing may fail with
const Allocator=std.mem.Allocator;
/// formats text into a fixed buffer (the path, counts, values)
const bufPrint=std.fmt.bufPrint;
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// all the maths: casts
const m=engine.core.math;
/// the UI's draw batch, which the panel goes into
const Draw=engine.ui.draw.Draw;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the move, turn and size handles on the selected form
const gizmo=@import("../gizmo.zig");
/// the HUD's shared colours and type sizes
const s=ps.style;
/// where sculpts are kept, and their ending
const dir=meshedit.settings.dir;
const ext=meshedit.settings.ext;
/// a point in the sculpt (m)
const V3=m.V3;
/// the editor's root, through which its other files are reached
const meshedit=@import("../meshedit.zig");
/// the dim colour: the help, an unselected shader
const bare=meshedit.settings.bare;
/// the colour of a form that carves
const carve=meshedit.settings.carve;
/// the colour of a form that only inks
const ink=meshedit.settings.ink;
/// the colour of a form gathered into the group
const grouped=meshedit.settings.grouped;
/// every value of a form, each a named channel
const Ch=meshedit.settings.Ch;
/// the editor's state
const Editor=meshedit.editor.Editor;
/// a form's handle radius (px)
const handleR=meshedit.settings.handleR;
/// the toolbar, and the backed text the path, the note and the help are written on
const toolbar=@import("../toolbar.zig");
/// every act, the toolbar's buttons, and the help
const buttons=meshedit.buttons;
/// the help, as backed lines
const helpLines=toolbar.lines(&buttons.help);
const rigHelpLines=toolbar.lines(&buttons.rigHelp);
/// the most form rows shown at once
const listRowCount=meshedit.settings.listRowCount;
/// how wide the form list is (px)
const listW=meshedit.settings.listW;
/// how far down the window the form list starts (px)
const listY=meshedit.settings.listY;
/// the gap round the panel's edges (px)
const pad=meshedit.settings.pad;
/// the panels' colour
const panel=meshedit.settings.panel;
/// the colour of a form that adds, and of a set value
const plain=meshedit.settings.plain;
/// the height of one row (px)
const row=meshedit.settings.row;
/// the selected colour
const sel=meshedit.settings.sel;
/// how far in from the list's left a form's shader is written (px)
const shadeX=meshedit.settings.shadeX;
/// how far in from the list's left a form's shape is written (px)
const kindX=meshedit.settings.kindX;
/// value `i` of a form, in words
const valueLabel=meshedit.settings.valueLabel;
/// a name as it is typed, its caret in it
const typed=@import("../labels.zig").drawTyped;
/// the panel's text size
const text=meshedit.settings.text;
/// how far down a row its glow sits (px), level with its words
const glowY=meshedit.settings.glowY;
/// how far in from the list's left a value is written (px)
const valueX=meshedit.settings.valueX;
/// how many form rows show
const listRows=meshedit.settings.listRows;
/// where the values start under the form rows
const valuesY=meshedit.settings.valuesY;
/// draws the editor over the scene: the mesh's path, cells and note, the
/// toolbar and the help, the form list, the selected form's values, every
/// other form's handle where it stands, and the selected form's gizmo
pub fn draw(e:*Editor,d:*Draw,screen:m.Vice(f32,2),handles:[]const?m.Vice(f32,2),view:gizmo.View,origin:V3)Allocator.Error!void{
  // buffers for the path line and the cells line
  var pb:[160]u8=undefined;
  var cb:[64]u8=undefined;
  // the name as it is typed, if the path was clicked
  const renaming=if(e.renaming)|*t|t.slice()else null;
  _=try toolbar.backed(d,pad,pad,&.{
    .{.words=if(renaming)|r|bufPrint(&pb,"{s}/{s}{s}   enter: rename   esc: keep",.{dir,r,ext})catch"?" else bufPrint(&pb,"{s}{s}",.{e.path,if(e.dirty)" *"else""}) catch e.path,.col=sel},
    .{.words=bufPrint(&cb,"cells {d:.4} m   {d} forms",.{e.doc.cell,e.pieces().len})catch"?",.col=plain},
    .{.words=e.note[0..e.noteLen],.col=s.dim},
  });
  if(e.renaming)|*t|try typed(d,pad+Draw.width(dir++"/",text),pad,t);
  // the toolbar, laid out for the mode as it is now
  e.bar.lay(buttons.items(e),screen,screen[1]-pad);
  try e.bar.draw(d,buttons.lit(e),buttons.live(e));
  if(e.helpShown)_=try toolbar.backed(d,pad+listW+3*pad,pad,if(e.rigMode)&rigHelpLines else&helpLines);
  // rig mode: the bones, their values and the skeleton, and the selected joint's gizmo
  if(e.rigMode){
    try meshedit.rigging.draw(e,d,view,origin);
    if(meshedit.rigging.gizmoAt(e,origin))|g|try g.draw(d,view,e.hot);
    return;
  }
  // the forms
  // how many form rows show
  const rows=listRows(e.pieces().len);
  try d.trellis(pad,listY-6,listW,m.f(rows)*row+12,panel,0.3);
  for(0..rows)|r|{
    // this row's form, and where it sits (px)
    const i=e.top+r;
    if(i>=e.pieces().len)break;
    const p=e.pieces()[i];
    const ry=listY+m.f(r)*row;
    if(i==e.sel)try d.glow(pad+8,ry+glowY,12,s.menuHover);
    // the colour the row is written in, and whether its name is being typed
    const col=if(i==e.sel)sel else if(p.grouped)grouped else if(p.ink)ink else if(p.carve)carve else plain;
    const typing=i==e.sel and e.naming!=null;
    // its number, then its name (as typed, the caret in it), else its shape
    var nb:[8]u8=undefined;
    const nx=try d.text(pad+18,ry,text,col,bufPrint(&nb,"{d}  ",.{i+1})catch"?");
    if(typing)try typed(d,nx,ry,&e.naming.?)
    else _=try d.text(nx,ry,text,if(p.name.len>0)col else bare,if(p.name.len>0)p.name.slice()else@tagName(p.kind));
    // its shape (when named), whether it carves or inks and whether it has a twin, dim
    var kb:[64]u8=undefined;
    _=try d.text(pad+kindX,ry,text,bare,bufPrint(&kb,"{s}{s}{s}{s}{s}{s}",.{if(p.name.len>0 or typing)@tagName(p.kind)else"",if(p.kind==.nest)" "else"",if(p.kind==.nest)p.use.slice()else"",if(p.carve)" carve"else"",if(p.ink)" ink"else"",if(p.twin)" twin"else""})catch"?");
    _=try d.text(pad+shadeX,ry,text,if(i==e.sel)sel else bare,@tagName(p.shade));
  }
  if(e.top>0)_=try d.text(pad+listW-30,listY-20,text,bare,"...");
  if(e.top+listRowCount<e.pieces().len)_=try d.text(pad+listW-30,listY+listRowCount*row,text,bare,"...");
  // the selected form's values
  // where the values start (px)
  const vy=valuesY(rows);
  if(e.pieces().len>0){
    // the selected form
    const p=e.pieces()[e.sel];
    try d.trellis(pad,vy-6,listW,m.f(Ch.count)*row+12,panel,0.6);
    for(0..Ch.count)|i|{
      // this value's row (px), and the colour it is written in
      const ry=vy+m.f(i)*row;
      const col=if(i==e.ch)sel else plain;
      if(i==e.ch)try d.glow(pad+8,ry+glowY,12,s.menuHover);
      _=try d.text(pad+18,ry,text,col,valueLabel(p.kind,i));
      // a buffer for the value, written to three places
      var vb:[24]u8=undefined;
      _=try d.text(pad+valueX,ry,text,col,bufPrint(&vb,"{d:.3}",.{Ch.get(&p.v,i)})catch"?");
    }
    // the bone it rides, under its values (once there are bones)
    if(e.doc.bones.items.len>0){
      var bb:[40]u8=undefined;
      _=try d.text(pad+18,vy+m.f(Ch.count)*row+10,text,bare,bufPrint(&bb,"on {s}",.{e.doc.bones.items[@min(p.bone,e.doc.bones.items.len-1)].name.slice()})catch"?");
    }
  }else _=try d.text(pad+18,vy,text,bare,"no forms: new form (n) makes one");
  // each form's handle where it stands
  for(handles,0..)|h,i|if(h)|at|{
    // this form, and its handle's colour
    const p=e.pieces()[i];
    const col=if(i==e.sel)sel else if(p.grouped)grouped else if(p.ink)ink else if(p.carve)carve else plain;
    if(i!=e.sel)try d.pod(at[0],at[1],handleR,col,1,0);
  };
  // each twin's mark where it stands, dim: it follows its form, never picked itself
  for(e.pieces())|p|if(p.twin){
    if(view.project(origin+p.mirrored().v.pos))|at|try d.pod(at[0],at[1],handleR*0.6,bare,1,0);
  };
  // the selected form's gizmo over everything in view
  if(e.gizmoAt(origin))|g|try g.draw(d,view,e.hot);
}
