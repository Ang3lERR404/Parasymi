//! the mesh editor's panel: the form list, the values and the help.
const std=ps.std;
const Allocator=std.mem.Allocator;
const bufPrint=std.fmt.bufPrint;
const engine=ps.engine;
const m=engine.core.math;
const Draw=engine.ui.draw.Draw;
const ps=@import("parasymi");
const gizmo=@import("../gizmo.zig");
const s=ps.style;
const V3=m.V3;
const meshedit=@import("../meshedit.zig");
const bare=meshedit.settings.bare;
const carve=meshedit.settings.carve;
const Ch=meshedit.settings.Ch;
const Editor=meshedit.editor.Editor;
const handleR=meshedit.settings.handleR;
const help=meshedit.settings.help;
const lineH=meshedit.settings.lineH;
const listRowCount=meshedit.settings.listRowCount;
const listW=meshedit.settings.listW;
const listY=meshedit.settings.listY;
const pad=meshedit.settings.pad;
const panel=meshedit.settings.panel;
const plain=meshedit.settings.plain;
const row=meshedit.settings.row;
const sel=meshedit.settings.sel;
const shadeX=meshedit.settings.shadeX;
const text=meshedit.settings.text;
const valueX=meshedit.settings.valueX;
const listRows=meshedit.settings.listRows;
const valuesY=meshedit.settings.valuesY;
pub fn draw(e:*Editor,d:*Draw,screen:[2]f32,handles:[]const?[2]f32,view:gizmo.View,origin:V3)Allocator.Error!void{
  const w=screen[0];
  var y:f32=pad;
  for(help)|h|{
    _=try d.text(pad,y,text,bare,h);
    y+=lineH;
  }
  var pb:[160]u8=undefined;
  _=try d.text(w-pad-420,pad,s.textLabel,sel,bufPrint(&pb,"{s}{s}",.{e.path,if(e.dirty)" *"else""}) catch e.path);
  var cb:[64]u8=undefined;
  _=try d.text(w-pad-420,pad+lineH+4,text,plain,bufPrint(&cb,"cells {d:.4} m   {d} forms   gizmo {t}",.{e.doc.cell,e.pieces().len,e.mode})catch"?");
  if(e.noteLen>0)_=try d.text(w-pad-420,pad+2*(lineH+4),text,plain,e.note[0..e.noteLen]);
  // the forms
  const rows=listRows(e.pieces().len);
  try d.trellis(pad,listY-6,listW,m.f(rows)*row+12,panel,0.3);
  for(0..rows)|r|{
    const i=e.top+r;
    if(i>=e.pieces().len)break;
    const p=e.pieces()[i];
    const ry=listY+m.f(r)*row;
    if(i==e.sel)try d.glow(pad+8,ry+7,10,s.menuHover);
    var lb:[48]u8=undefined;
    const col=if(i==e.sel)sel else if(p.carve)carve else plain;
    _=try d.text(pad+18,ry,text,col,bufPrint(&lb,"{d}  {t}{s}",.{i+1,p.kind,if(p.carve)"  carve"else""})catch"?");
    _=try d.text(pad+shadeX,ry,text,if(i==e.sel)sel else bare,@tagName(p.shade));
  }
  if(e.top>0)_=try d.text(pad+listW-30,listY-20,text,bare,"...");
  if(e.top+listRowCount<e.pieces().len)_=try d.text(pad+listW-30,listY+listRowCount*row,text,bare,"...");
  // the selected form's values
  const vy=valuesY(rows);
  if(e.pieces().len>0){
    const p=e.pieces()[e.sel];
    try d.trellis(pad,vy-6,listW,m.f(Ch.count)*row+12,panel,0.6);
    for(Ch.names,0..)|n,i|{
      const ry=vy+m.f(i)*row;
      const col=if(i==e.ch)sel else plain;
      if(i==e.ch)try d.glow(pad+8,ry+7,10,s.menuHover);
      _=try d.text(pad+18,ry,text,col,n);
      var vb:[24]u8=undefined;
      _=try d.text(pad+valueX,ry,text,col,bufPrint(&vb,"{d:.3}",.{Ch.get(&p.v,i)})catch"?");
    }
  }else _=try d.text(pad+18,vy,text,bare,"no forms: n makes one");
  // each form's handle where it stands
  for(handles,0..)|h,i|if(h)|at|{
    const p=e.pieces()[i];
    const col=if(i==e.sel)sel else if(p.carve)carve else plain;
    if(i!=e.sel)try d.pod(at[0],at[1],handleR,col,1,0);
  };
  // the selected form's gizmo over everything in view
  if(e.gizmoAt(origin))|g|try g.draw(d,view,e.hot);
}
