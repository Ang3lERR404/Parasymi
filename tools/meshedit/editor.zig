//! the mesh editor's state: the selected form and value, saving and the gizmo.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the allocator type the forms are kept with
const Allocator=std.mem.Allocator;
/// the I/O interface, for saving meshes
const Io=std.Io;
/// a directory, for writing a mesh under the repo
const Dir=Io.Dir;
/// a text writer, which a mesh is written into
const Writer=Io.Writer;
/// whether two byte strings are the same
const eql=std.mem.eql;
/// whether a value's name begins with a word (`size`, `col`, `rot`)
const startsWith=std.mem.startsWith;
/// formats text into a fixed buffer (the note)
const bufPrint=std.fmt.bufPrint;
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// all the maths: vectors, matrices, angles
const m=engine.core.math;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the move, turn and size handles on the selected form
const gizmo=@import("../gizmo.zig");
/// a point or direction in the sculpt (m)
const V3=m.V3;
/// makes a `V3` from its three parts
const v3=m.v3;
/// the editor's root, through which its other files are reached
const meshedit=@import("../meshedit.zig");
/// every value of a form, each a named channel
const Ch=meshedit.settings.Ch;
/// where meshes are kept
const dir=meshedit.settings.dir;
/// how much a drag changes a colour channel per pixel
const dragCol=meshedit.settings.dragCol;
/// how much a drag changes a turn per pixel (degrees)
const dragDeg=meshedit.settings.dragDeg;
/// how much a drag changes a length per pixel (m)
const dragLen=meshedit.settings.dragLen;
/// the mesh as kept: its cells and its forms
const Doc=meshedit.doc.Doc;
/// what is being dragged
const Drag=meshedit.doc.Drag;
/// the first of a form's place channels
const pos=meshedit.settings.pos;
/// one form of the sculpt
const Piece=meshedit.doc.Piece;
/// the first of a form's turn channels
const rot=meshedit.settings.rot;
/// the first of a form's size channels
const sizeTiles=meshedit.settings.sizeTiles;
/// the least a form's size may be (m)
const sizeMin=meshedit.settings.sizeMin;
/// the editor: the mesh being sculpted, the selection, the gizmo, and
/// whether the surface must be meshed again
pub const Editor=struct{
  /// the allocator the forms and the save keep memory with
  gpa:Allocator,
  /// the I/O the mesh is saved through
  io:Io,
  /// where the mesh is kept (`src/mesh/<name>.mesh`)
  path:[]const u8,
  /// the mesh being sculpted
  doc:Doc,
  /// the form selected, the value selected in it, the first form row in view
  sel:usize=0,
  ch:usize=0,
  top:usize=0,
  /// what the mouse is dragging
  drag:Drag=.none,
  /// what the gizmo does, the handle held, and the one under the mouse
  mode:gizmo.Mode=.move,
  part:?gizmo.Part=null,
  hot:?gizmo.Part=null,
  /// whether the mesh has changed since it was last saved
  dirty:bool=false,
  /// the surface wants meshing again, and how long since it last was
  stale:bool=true,
  since:f32=0,
  /// what is shown was meshed coarser, while dragging
  coarse:bool=false,
  /// the last note shown under the help (saved, failed, ...)
  note:[96]u8=undefined,
  /// how much of `note` is written
  noteLen:usize=0,
  /// the camera is asked onto the selected form
  focus:bool=false,
  /// the forms, in order
  pub fn pieces(e:*Editor)[]Piece{return e.doc.pieces.items;}
  /// show a note under the help, cut to fit its buffer
  pub fn say(e:*Editor,comptime fmt:[]const u8,args:anytype)void{
    e.noteLen=if(bufPrint(&e.note,fmt,args))|w|w.len else|_|e.note.len;
  }
  /// marks the mesh unsaved and its surface to be meshed again
  pub fn changed(e:*Editor)void{
    e.dirty=true;
    e.stale=true;
  }
  /// write the mesh to its file, making `src/mesh` if need be, and say how
  /// that went
  pub fn save(e:*Editor)void{
    // the I/O the save goes through
    const io=e.io;
    // the mesh's text, written into memory first
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
    // the selected form, and the name of its value `ch`
    const p=&e.pieces()[e.sel];
    const name=Ch.names[ch];
    // the value kept within bounds: sizes above `sizeMin`, colours 0..1,
    // melt and round never below zero
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
    // the selected form's values
    const v=e.pieces()[e.sel].v;
    // its turn as matrices: y alone, then x after y, then all three
    const ry=m.rotY(m.rad(v.rot[1]));
    const rx=m.mul(ry,m.rotX(m.rad(v.rot[0])));
    const full=m.mul(rx,m.rotZ(m.rad(v.rot[2])));
    // the three axes of the sculpt's frame
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
    // the handle held, if any
    const part=e.part orelse return;
    switch(part){
      .free=>{
        // the drag across the view, in the sculpt, `k` of it
        const by:[3]f32=g.across(view,from,to)*m.splat3(k);
        for(0..3)|i|e.nudge(pos+i,by[i]);
        e.ch=pos;
      },
      .x,.y,.z=>{
        // the handle's axis, and how far the drag carried along or about it
        const i=@intFromEnum(part);
        const by=g.along(view,i,from,to)*k;
        e.ch=i+switch(e.mode){.move=>pos,.turn=>rot,.size=>sizeTiles};
        e.nudge(e.ch,if(e.mode==.turn)by/m.rad(1)else by);
      },
    }
  }
  /// how much a pixel of drag changes the selected value: by degrees,
  /// colour or length
  pub fn rate(e:*const Editor)f32{
    // the selected value's name
    const name=Ch.names[e.ch];
    return if(startsWith(u8,name,"rot"))dragDeg else if(startsWith(u8,name,"col"))dragCol else dragLen;
  }
  /// answers the keys and mouse each frame
  pub const handle=meshedit.editing.handle;
  /// draws the panel and the forms' handles
  pub const draw=meshedit.panel.draw;
};
