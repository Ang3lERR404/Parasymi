//! the mesh editor's state: the selected form and value, saving and the gizmo.
const std=ps.std;
const Allocator=std.mem.Allocator;
const Io=std.Io;
const Dir=Io.Dir;
const Writer=Io.Writer;
const eql=std.mem.eql;
const startsWith=std.mem.startsWith;
const bufPrint=std.fmt.bufPrint;
const engine=ps.engine;
const m=engine.core.math;
const ps=@import("parasymi");
const gizmo=@import("../gizmo.zig");
const V3=m.V3;
const v3=m.v3;
const meshedit=@import("../meshedit.zig");
const Ch=meshedit.settings.Ch;
const dir=meshedit.settings.dir;
const dragCol=meshedit.settings.dragCol;
const dragDeg=meshedit.settings.dragDeg;
const dragLen=meshedit.settings.dragLen;
const Doc=meshedit.doc.Doc;
const Drag=meshedit.doc.Drag;
const pos=meshedit.settings.pos;
const Piece=meshedit.doc.Piece;
const rot=meshedit.settings.rot;
const sizeTiles=meshedit.settings.sizeTiles;
const sizeMin=meshedit.settings.sizeMin;
pub const Editor=struct{
  gpa:Allocator,
  io:Io,
  path:[]const u8,
  doc:Doc,
  /// the form selected, the value selected in it, the first form row in view
  sel:usize=0,
  ch:usize=0,
  top:usize=0,
  drag:Drag=.none,
  /// what the gizmo does, the handle held, and the one under the mouse
  mode:gizmo.Mode=.move,
  part:?gizmo.Part=null,
  hot:?gizmo.Part=null,
  dirty:bool=false,
  /// the surface wants meshing again, and how long since it last was
  stale:bool=true,
  since:f32=0,
  /// what is shown was meshed coarser, while dragging
  coarse:bool=false,
  note:[96]u8=undefined,
  noteLen:usize=0,
  /// the camera is asked onto the selected form
  focus:bool=false,
  pub fn pieces(e:*Editor)[]Piece{return e.doc.pieces.items;}
  pub fn say(e:*Editor,comptime fmt:[]const u8,args:anytype)void{
    e.noteLen=if(bufPrint(&e.note,fmt,args))|w|w.len else|_|e.note.len;
  }
  pub fn changed(e:*Editor)void{
    e.dirty=true;
    e.stale=true;
  }
  pub fn save(e:*Editor)void{
    const io=e.io;
    var out:Writer.Allocating=.init(e.gpa);
    defer out.deinit();
    e.doc.write(&out.writer) catch return e.say("save failed: out of memory",.{});
    Dir.cwd().createDirPath(io,dir)catch|er|return e.say("save failed: {t}",.{er});
    Dir.cwd().writeFile(io,.{.sub_path=e.path,.data=out.written()})catch|er|return e.say("save failed: {t}",.{er});
    e.dirty=false;
    e.say("saved {s}",.{e.path});
  }
  /// the selected value set to `v`, kept where it makes sense
  pub fn set(e:*Editor,v:f32)void{e.setCh(e.ch,v);}
  /// the selected form's value `ch` set to `v`, kept where it makes sense
  pub fn setCh(e:*Editor,ch:usize,v:f32)void{
    const p=&e.pieces()[e.sel];
    const name=Ch.names[ch];
    const kept=if(startsWith(u8,name,"size"))@max(sizeMin,v)else if(startsWith(u8,name,"col"))m.clamp01(v)else if(eql(u8,name,"melt") or eql(u8,name,"round"))@max(0,v)else v;
    Ch.set(&p.v,ch,kept);
    e.changed();
  }
  /// the selected form's value `ch` changed by `by`
  pub fn nudge(e:*Editor,ch:usize,by:f32)void{e.setCh(ch,Ch.get(&e.pieces()[e.sel].v,ch)+by);}
  /// the selected form's gizmo where it stands (`origin` the sculpt's
  /// place), none without forms
  pub fn gizmoAt(e:*Editor,origin:V3)?gizmo.Gizmo{
    if(e.pieces().len==0)return null;
    const v=e.pieces()[e.sel].v;
    const ry=m.rotY(m.rad(v.rot[1]));
    const rx=m.mul(ry,m.rotX(m.rad(v.rot[0])));
    const full=m.mul(rx,m.rotZ(m.rad(v.rot[2])));
    const xAxis=v3(1,0,0);
    const y=v3(0,1,0);
    const zAxis=v3(0,0,1);
    return.{.at=origin+v.pos,.mode=e.mode,.axes=switch(e.mode){
      .move=>.{xAxis,y,zAxis},
      // each turn about the axis it turns round: y the world's, x after
      // y, z after both
      .turn=>.{m.mulDir(ry,xAxis),y,m.mulDir(rx,zAxis)},
      .size=>.{m.mulDir(full,xAxis),m.mulDir(full,y),m.mulDir(full,zAxis)},
    }};
  }
  /// a drag of the gizmo's held handle from `from` to `to` (px), `k` of it
  pub fn dragGizmo(e:*Editor,g:gizmo.Gizmo,view:gizmo.View,from:[2]f32,to:[2]f32,k:f32)void{
    const part=e.part orelse return;
    switch(part){
      .free=>{
        const by:[3]f32=g.across(view,from,to)*m.splat3(k);
        for(0..3)|i|e.nudge(pos+i,by[i]);
        e.ch=pos;
      },
      .x,.y,.z=>{
        const i=@intFromEnum(part);
        const by=g.along(view,i,from,to)*k;
        e.ch=i+switch(e.mode){.move=>pos,.turn=>rot,.size=>sizeTiles};
        e.nudge(e.ch,if(e.mode==.turn)by/m.rad(1)else by);
      },
    }
  }
  pub fn rate(e:*const Editor)f32{
    const name=Ch.names[e.ch];
    return if(startsWith(u8,name,"rot"))dragDeg else if(startsWith(u8,name,"col"))dragCol else dragLen;
  }
  pub const handle=meshedit.editing.handle;
  pub const draw=meshedit.panel.draw;
};
