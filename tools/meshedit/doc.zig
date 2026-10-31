//! a mesh as the editor keeps it: its forms, read from and written to text.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the allocator type the forms are kept with
const Allocator=std.mem.Allocator;
/// the I/O interface, handed to the sculpt for its thread pool
const Io=std.Io;
/// a text writer, which a mesh is written into
const Writer=Io.Writer;
/// whether two byte strings are the same
const eql=std.mem.eql;
/// a name turned into its enum tag, or null if none matches
const stringToEnum=std.meta.stringToEnum;
/// splits text at each newline
const splitScalar=std.mem.splitScalar;
/// splits a line into its words
const tokenizeScalar=std.mem.tokenizeScalar;
/// a line without its margins
const trim=std.mem.trim;
/// reads a decimal number
const parseFloat=std.fmt.parseFloat;
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// all the maths: vectors, matrices, angles
const m=engine.core.math;
/// colour conversions: a form's colour into bytes
const color=engine.core.color;
/// SDF sculpting: forms melted into one surface and meshed
const sculpt=engine.gfx.sculpt;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the move, turn and size handles on the selected form
const gizmo=@import("../gizmo.zig");
/// the game's mesh builder, which the surface is meshed into
const meshgen=ps.meshgen;
/// a part role: the shader a part of the surface is drawn with
const Part=ps.vertex.Part;
/// makes a vector from its three parts
const v3=m.v3;
/// the editor's root, through which its other files are reached
const meshedit=@import("../meshedit.zig");
/// the surface's cell size to start (m)
const cell=meshedit.settings.cell;
/// the finest the cells may be (m)
const cellMin=meshedit.settings.cellMin;
/// every value of a form, each a named channel
const Ch=meshedit.settings.Ch;
/// how many times wider the cells are while a value is dragged
const dragCoarse=meshedit.settings.dragCoarse;
/// the first line of a mesh's text
const header=meshedit.settings.header;
/// how many degrees of a tube's curl each segment takes
const curlStep=meshedit.settings.curlStep;
/// the shape a form takes
const Kind=meshedit.settings.Kind;
/// the most cells across the whole sculpt
const maxCells=meshedit.settings.maxCells;
/// a form's numbers
const Vals=meshedit.settings.Vals;
/// a form's name, kept by value
const Name=@import("../labels.zig").Name;
/// the sculpt's bones: joints, parents, twins
const rig=meshedit.rig;
/// one bone of the sculpt
const Bone=rig.Bone;
/// one form of the sculpt: its name, its shape, whether it carves, its
/// shader and values
pub const Piece=struct{
  /// what the gardener calls it (`snout`, `left ear`); may be empty
  name:Name=.{},
  /// an ellipsoid, a rounded cone, a rounded box or a curling tube
  kind:Kind=.ellipsoid,
  /// whether it is carved out of what is before it (else melted in)
  carve:bool=false,
  /// whether it only inks the colour of the surface where it lies, adding
  /// nothing (its melt the fade round it): the dark round an eye, a stripe
  ink:bool=false,
  /// whether it is gathered into the selected form's group, moving and
  /// turning with it (only while editing: never kept in the file)
  grouped:bool=false,
  /// the bone it rides (an index among the mesh's bones; its twin rides
  /// that bone's twin)
  bone:u8=0,
  /// whether a twin of it stands mirrored across the sculpt's middle (x=0),
  /// following it as it is shaped
  twin:bool=false,
  /// the shader (part role) its part of the surface is drawn with
  shade:Part=.stem,
  /// where it stands, how it is turned and sized, and its colour
  v:Vals=.{},
  /// as the sculpt takes it
  pub fn form(p:Piece)sculpt.Form{
    // its values, its place and turn as one matrix, and the origin in its frame
    const v=p.v;
    const at=m.chain(&.{m.translate(v.pos),m.rotY(m.rad(v.rot[1])),m.rotX(m.rad(v.rot[0])),m.rotZ(m.rad(v.rot[2]))});
    const z=v3(0,0,0);
    return.{
      .shape=switch(p.kind){
        .ellipsoid=>.{.ellipsoid=.{.c=z,.r=v.size}},
        .cone=>.{.cone=.{.a=v3(0,-v.size[1],0),.b=v3(0,v.size[1],0),.ra=v.size[0],.rb=v.size[2]}},
        .box=>.{.box=.{.c=z,.half=v.size,.round=@min(v.round,@reduce(.Min,v.size))}},
        .tube=>.{.chain=arc(v)},
      },
      .at=at,
      .bone=0,
      .col=color.rgb(v.col[0],v.col[1],v.col[2]).toRgba8(255),
      .k=v.melt,
      .carve=p.carve and !p.ink,
      .ink=if(p.ink)@max(v.melt,inkMin)else 0,
      .part=@intFromEnum(p.shade),
    };
  }
  /// its twin: mirrored across the sculpt's middle (x=0), so its place
  /// across flips, and so do its turns about y and z (a mirror leaves the
  /// turn about x alone); every shape is even across its own x but a
  /// tube's curl, so the curl flips too
  pub fn mirrored(p:Piece)Piece{
    // the twin, its values flipped
    var t=p;
    t.v.pos[0]=-p.v.pos[0];
    t.v.rot[1]=-p.v.rot[1];
    t.v.rot[2]=-p.v.rot[2];
    t.v.curl=-p.v.curl;
    return t;
  }
  /// the farthest it reaches from the sculpt's origin (m)
  pub fn reach(p:Piece)f32{
    // how far its shape reaches from its place: a tube its length and its widest radius
    const own=if(p.kind==.tube)p.v.size[1]+@max(p.v.size[0],p.v.size[2])else m.len(p.v.size);
    return m.len(p.v.pos)+own+p.v.melt;
  }
};
/// the least fade an ink form takes (m), so it never inks a hard edge
const inkMin:f32=0.005;
/// a tube's centre line: from its foot at the origin up along y for its
/// length (`size` y), bending toward x round a circle as it goes so that
/// it has turned by `curl` degrees at its tip; its radius eases from its
/// foot's (`size` x) to its tip's (`size` z). One segment for each
/// `curlStep` degrees of curl.
pub fn arc(v:Vals)sculpt.Chain{
  // the curl (rad), the length, and how many segments it is cut into
  const turn=m.rad(v.curl);
  const len=v.size[1];
  const n:usize=m.clamp(@as(usize,@intFromFloat(@ceil(@abs(v.curl)/curlStep))),1,sculpt.chainMax);
  // the chain being laid
  var c:sculpt.Chain=.{.n=@intCast(n)};
  for(0..n+1)|i|{
    // how far along it this point is (0..1), and how far it has turned there (rad)
    const t=m.f(i)/m.f(n);
    const a=turn*t;
    // nearly straight: along y; else round the circle the curl draws
    c.pts[i]=if(@abs(turn)<1e-4)v3(0,len*t,0)else v3(len/turn*(1-@cos(a)),len/turn*@sin(a),0);
    c.r[i]=m.lerp(v.size[0],v.size[2],t);
  }
  return c;
}
/// what a mesh's text holds: its cells and its forms, in order
pub const Doc=struct{
  /// how fine the surface is meshed: the cell size (m)
  cell:f32=cell,
  /// its forms, in the order they melt into one another
  pieces:std.ArrayList(Piece)=.empty,
  /// its bones, each after its parent (none: one root carries it all)
  bones:std.ArrayList(Bone)=.empty,
  /// lets the forms and bones go
  pub fn deinit(d:*Doc,gpa:Allocator)void{
    d.pieces.deinit(gpa);
    d.bones.deinit(gpa);
  }
  /// the bone kept by `name`, if there is one
  pub fn boneNamed(d:*const Doc,name:[]const u8)?u8{
    for(d.bones.items,0..)|b,i|if(eql(u8,b.name.slice(),name))return@intCast(i);
    return null;
  }
  /// writes the mesh as text: the header, the cell size, then each bone's
  /// name, parent, joint and twin, then each form's kind (and `carve`,
  /// `ink`, `twin`), name (if it has one), bone (if there are any), shader
  /// and every value, one to a line
  pub fn write(d:*const Doc,w:*Writer)Writer.Error!void{
    try w.print(header++"\ncell {d}\n",.{d.cell});
    for(d.bones.items)|*b|{
      try w.print("bone {s}\n",.{b.name.slice()});
      if(b.parent)|p|try w.print("parent {s}\n",.{d.bones.items[p].name.slice()});
      try w.print("joint {d} {d} {d}\n",.{b.at[0],b.at[1],b.at[2]});
      if(b.twin)try w.writeAll("twin\n");
    }
    for(d.pieces.items)|*p|{
      try w.print("form {t}{s}{s}{s}\n",.{p.kind,if(p.carve)" carve"else"",if(p.ink)" ink"else"",if(p.twin)" twin"else""});
      if(p.name.len>0)try w.print("name {s}\n",.{p.name.slice()});
      if(d.bones.items.len>0)try w.print("on {s}\n",.{d.bones.items[@min(p.bone,d.bones.items.len-1)].name.slice()});
      try w.print("shade {t}\n",.{p.shade});
      for(Ch.names,0..)|n,i|try w.print("{s} {d}\n",.{n,Ch.get(&p.v,i)});
    }
  }
  /// what a mesh's text can fail to read with
  pub const ParseError=error{BadMesh,OutOfMemory};
  /// reads a mesh from its text, skipping blanks and `#` lines; a line it
  /// does not understand, or a value before any form, is `BadMesh`
  pub fn parse(gpa:Allocator,text:[]const u8)ParseError!Doc{
    // the mesh being read
    var d:Doc=.{};
    errdefer d.deinit(gpa);
    // the text's lines, one at a time
    var lines=splitScalar(u8,text,'\n');
    while(lines.next())|raw|{
      // this line without its margins
      const line=trim(u8,raw," \t\r");
      if(line.len==0 or line[0]=='#')continue;
      // the line's words, and its first
      var it=tokenizeScalar(u8,line,' ');
      const word=it.next() orelse continue;
      if(eql(u8,word,"cell")){
        d.cell=@max(cellMin,parseFloat(f32,it.next() orelse return error.BadMesh) catch return error.BadMesh);
      }else if(eql(u8,word,"bone")){
        // a new bone: its name, the rest of the line (unique, never empty)
        const name=trim(u8,it.rest()," \t");
        if(name.len==0 or d.boneNamed(name)!=null or rig.count(d.bones.items)>=rig.maxBones)return error.BadMesh;
        try d.bones.append(gpa,.{.name=.of(name)});
      }else if(eql(u8,word,"parent") or eql(u8,word,"joint") or (eql(u8,word,"twin") and d.pieces.items.len==0)){
        if(d.bones.items.len==0)return error.BadMesh;
        // the bone last begun
        const b=&d.bones.items[d.bones.items.len-1];
        if(eql(u8,word,"parent")){
          b.parent=d.boneNamed(trim(u8,it.rest()," \t")) orelse return error.BadMesh;
          if(b.parent.?+1>=d.bones.items.len)return error.BadMesh;
        }else if(eql(u8,word,"joint")){
          inline for(0..3)|i|b.at[i]=parseFloat(f32,it.next() orelse return error.BadMesh) catch return error.BadMesh;
        }else{
          b.twin=true;
          if(rig.count(d.bones.items)>rig.maxBones)return error.BadMesh;
        }
      }else if(eql(u8,word,"on")){
        if(d.pieces.items.len==0)return error.BadMesh;
        d.pieces.items[d.pieces.items.len-1].bone=d.boneNamed(trim(u8,it.rest()," \t")) orelse return error.BadMesh;
      }else if(eql(u8,word,"form")){
        // the new form's shape, then whether it carves and has a twin
        const kind=stringToEnum(Kind,it.next() orelse return error.BadMesh) orelse return error.BadMesh;
        var p:Piece=.{.kind=kind};
        while(it.next())|flag|{
          if(eql(u8,flag,"carve"))p.carve=true else if(eql(u8,flag,"ink"))p.ink=true else if(eql(u8,flag,"twin"))p.twin=true else return error.BadMesh;
        }
        try d.pieces.append(gpa,p);
      }else if(eql(u8,word,"name")){
        if(d.pieces.items.len==0)return error.BadMesh;
        // the name: the rest of the line, spaces and all
        d.pieces.items[d.pieces.items.len-1].name=.of(trim(u8,it.rest()," \t"));
      }else if(eql(u8,word,"shade")){
        if(d.pieces.items.len==0)return error.BadMesh;
        d.pieces.items[d.pieces.items.len-1].shade=stringToEnum(Part,it.next() orelse return error.BadMesh) orelse return error.BadMesh;
      }else{
        // the value's channel
        const i=Ch.find(word) orelse return error.BadMesh;
        if(d.pieces.items.len==0)return error.BadMesh;
        // the value
        const v=parseFloat(f32,it.next() orelse return error.BadMesh) catch return error.BadMesh;
        Ch.set(&d.pieces.items[d.pieces.items.len-1].v,i,v);
      }
    }
    return d;
  }
  /// its surface into `b`, cells `cell` across (wider where the sculpt is
  /// too big for that many; `dragCoarse` times them while `coarse`);
  /// nothing when no form adds anything
  pub fn mesh(d:*const Doc,gpa:Allocator,io:?Io,coarse:bool,b:*meshgen.Builder)Allocator.Error!void{
    // whether any form adds (neither carving nor inking; else there is
    // nothing to mesh), and the farthest reach
    var solid=false;
    var far:f32=0;
    for(d.pieces.items)|p|{
      solid=solid or (!p.carve and !p.ink);
      far=@max(far,p.reach());
    }
    if(!solid)return;
    // the bones the forms ride, twins counted
    const k=rig.skeleton(d.bones.items);
    // the sculpt the forms are melted into, weighted to those bones
    var sc:sculpt.Sculpt=.{.gpa=gpa,.parents=k.parents[0..k.count],.io=io};
    defer sc.deinit();
    // each form on its bone, then its twin on the bone's twin, right after
    // it (so the two melt or carve as one into what came before)
    for(d.pieces.items)|p|{
      // the form's bone, kept within the bones there are
      const on:u8=if(d.bones.items.len==0)0 else@min(p.bone,d.bones.items.len-1);
      // the form as the sculpt takes it, then its twin
      var f=p.form();
      f.bone=k.ride(on,false);
      try sc.add(f);
      if(p.twin){
        var t=p.mirrored().form();
        t.bone=k.ride(on,true);
        try sc.add(t);
      }
    }
    // the cell size this time (m)
    const h=@max(d.cell,2*far/maxCells)*(if(coarse)dragCoarse else 1);
    try sc.mesh(meshgen.gen,b,h,0.5,.stem);
  }
};
/// what is being dragged: nothing, a value, or the gizmo
pub const Drag=enum{
  /// nothing held
  none,
  /// the selected value, changing as the mouse moves
  value,
  /// one of the selected form's gizmo handles
  gizmo,
};
