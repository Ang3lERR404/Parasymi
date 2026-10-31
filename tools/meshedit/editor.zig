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
/// the editors' words for values, and typed names
const labels=@import("../labels.zig");
/// undo and redo: each settled mesh kept as its text
const History=@import("../history.zig").History;
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
const sizeX=meshedit.settings.sizeX;
/// the least a form's size may be (m)
const sizeMin=meshedit.settings.sizeMin;
/// what `g` snaps places and sizes to (m)
const snapLen=meshedit.settings.snapLen;
/// and turns to (degrees)
const snapDeg=meshedit.settings.snapDeg;
/// a form's numbers
const Vals=meshedit.settings.Vals;
/// the sculpt's bones
const rig=meshedit.rig;
/// every sculpt kept in one folder, for the nests
const Folder=ps.sculptDoc.Folder;
/// where a path's last part begins
const lastIndexOfScalar=std.mem.lastIndexOfScalar;
/// whether a name ends so
const endsWith=std.mem.endsWith;
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
  /// the selected form's name as it is typed (null: not naming), the
  /// keys answering only it meanwhile
  naming:?labels.Typed=null,
  /// the meshes before and after this one, for undo and redo
  history:History,
  /// rig mode (`j`): the bones listed and placed in place of the forms
  rigMode:bool=false,
  /// the bone selected in rig mode
  bsel:usize=0,
  /// each kept bone's test turn (degrees, as a form's `rot`): how the skin
  /// bends is tried with it, never kept
  turns:[rig.maxBones]V3=@splat(.{0,0,0}),
  /// every other sculpt kept beside this one, read again before each
  /// meshing, for the nests (none read yet: nests are left out)
  parts:?Folder=null,
  /// the toolbar down the right side: a button for every act
  bar:meshedit.buttons.Bar=.{},
  /// the help (`h`): what the mouse does, and the keys' other ways
  helpShown:bool=false,
  /// the forms, in order
  pub fn pieces(e:*Editor)[]Piece{return e.doc.pieces.items;}
  /// this sculpt's own name (its file's, without the folder or ending)
  pub fn ownName(e:*const Editor)[]const u8{
    // the path's last part
    const base=e.path[(lastIndexOfScalar(u8,e.path,'/') orelse return e.path)+1..];
    return if(endsWith(u8,base,meshedit.settings.ext))base[0..base.len-meshedit.settings.ext.len]else base;
  }
  /// every sculpt kept beside this one read again (a part edited elsewhere
  /// shows at once); one that will not read keeps the last read
  pub fn reloadParts(e:*Editor)Allocator.Error!void{
    // the folder read afresh
    const fresh=try Folder.load(e.gpa,e.io,Dir.cwd(),dir);
    if(e.parts)|*old|old.deinit();
    e.parts=fresh;
  }
  /// the nests' lookup: every other sculpt, none before the first reading
  pub fn lookup(e:*const Editor)?ps.sculptDoc.Lookup{
    return if(e.parts)|*f|f.lookup()else null;
  }
  /// nest `p`'s sculpt stepped on to the next kept beside this one (`back`:
  /// the one before), never this one itself
  pub fn stepPart(e:*Editor,p:*Piece,back:bool)void{
    // the sculpts there are
    const f=if(e.parts)|*x|x else return e.say("no other sculpts read yet",.{});
    const names=f.names.items;
    // where the nest's sculpt is among them (none: before the first)
    var at:usize=for(names,0..)|n,i|{
      if(eql(u8,n,p.use.slice()))break i;
    }else names.len;
    for(0..names.len)|_|{
      at=if(back)(at+names.len-1)%names.len else(at+1)%names.len;
      if(at>=names.len)at=0;
      if(!eql(u8,names[at],e.ownName())){
        p.use=.of(names[at]);
        e.changed();
        return e.say("nest uses {s}",.{names[at]});
      }
    }
    e.say("no other sculpts to nest: make one first",.{});
  }
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
  /// the mesh as it is now kept in the history, once the hands let go (no
  /// drag held, no name being typed): a whole drag is one step back
  pub fn settle(e:*Editor)Allocator.Error!void{
    if(e.drag!=.none or e.naming!=null)return;
    // the mesh's text now
    const now=try text(e.gpa,&e.doc);
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
  /// the mesh read back from the history's `kept` text (null: `none` said),
  /// the selection kept within its forms
  fn restore(e:*Editor,kept:?[]const u8,done:[]const u8,none:[]const u8)void{
    // the text to read, if there was a step to take
    const t=kept orelse return e.say("{s}",.{none});
    // the mesh as it was then (the history's own text, which reads back)
    const back=Doc.parse(e.gpa,t)catch|er|return e.say("{s} failed: {t}",.{done,er});
    e.doc.deinit(e.gpa);
    e.doc=back;
    e.sel=@min(e.sel,e.pieces().len-|1);
    e.bsel=@min(e.bsel,e.doc.bones.items.len-|1);
    e.naming=null;
    e.changed();
    e.say("{s}",.{done});
  }
  /// form `i` clicked: selected, or with ctrl (`gather`) gathered into the
  /// group or let go of it (the selected form leads the group, never in it)
  pub fn pick(e:*Editor,i:usize,gather:bool)void{
    if(!gather){
      e.sel=i;
      return;
    }
    if(i==e.sel)return;
    // the form gathered or let go
    const p=&e.pieces()[i];
    p.grouped=!p.grouped;
    e.say("{s} {d}",.{if(p.grouped)"gathered"else"let go",i+1});
  }
  /// how many forms are gathered into the group (the selected one aside)
  pub fn groupCount(e:*Editor)usize{
    // the count so far
    var n:usize=0;
    for(e.pieces(),0..)|p,i|n+=@intFromBool(p.grouped and i!=e.sel);
    return n;
  }
  /// the group carried along with the selected form, which was `was` as
  /// the frame began: moved as far as it moved, and turned as it turned,
  /// round where it stands
  pub fn follow(e:*Editor,was:Vals)void{
    // the selected form now
    const now=e.pieces()[e.sel].v;
    if(@reduce(.And,now.pos==was.pos) and @reduce(.And,now.rot==was.rot))return;
    if(e.groupCount()==0)return;
    // the turn it took this frame: its turn now after undoing its turn before
    const by=m.mul(turnOf(now.rot),m.inverseRigid(turnOf(was.rot)));
    for(e.pieces(),0..)|*p,i|if(p.grouped and i!=e.sel){
      p.v.pos=now.pos+m.mulDir(by,p.v.pos-was.pos);
      p.v.rot=anglesOf(m.mul(by,turnOf(p.v.rot)));
    };
    e.changed();
  }
  /// the selected form and its group snapped: places and sizes to
  /// `snapLen`, turns to `snapDeg`
  pub fn snap(e:*Editor)void{
    for(e.pieces(),0..)|*p,i|if(i==e.sel or p.grouped){
      p.v.pos=@round(p.v.pos/m.splat3(snapLen))*m.splat3(snapLen);
      p.v.size=@max(@round(p.v.size/m.splat3(snapLen))*m.splat3(snapLen),m.splat3(sizeMin));
      p.v.rot=@round(p.v.rot/m.splat3(snapDeg))*m.splat3(snapDeg);
    };
    e.changed();
    e.say("snapped",.{});
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
        e.ch=i+switch(e.mode){.move=>pos,.turn=>rot,.size=>sizeX};
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
/// an angle in radians as degrees, as a form's turns are kept
fn deg(a:f32)f32{return a/m.rad(1);}
/// a form's turns (degrees: y, then x, then z, as `rot` keeps them) as a matrix
pub const turnOf=rig.turnOf;
/// the turns (degrees, kept as `rot` keeps them) a turn matrix `r` is made
/// of; straight up or down (no turn about x left to tell y and z apart)
/// it is all y
pub fn anglesOf(r:m.M4)V3{
  // where the turn carries the x and z axes
  const ax=m.mulDir(r,v3(1,0,0));
  const az=m.mulDir(r,v3(0,0,1));
  // the turn about x, from how far z tips up or down
  const x=m.asin(-az[1]);
  if(@abs(az[1])>1-1e-6)return v3(deg(x),deg(m.atan2(-ax[2],ax[0])),0);
  // the turns about y (z's heading) and z (how far x tips up, against y)
  const ay=m.mulDir(r,v3(0,1,0));
  return v3(deg(x),deg(m.atan2(az[0],az[2])),deg(m.atan2(ax[1],ay[1])));
}
/// mesh `d` as the text its file would hold, the caller's to free
pub fn text(gpa:Allocator,d:*const Doc)Allocator.Error![]u8{
  // the text, written into memory
  var out:Writer.Allocating=.init(gpa);
  defer out.deinit();
  d.write(&out.writer) catch return error.OutOfMemory;
  return out.toOwnedSlice();
}
