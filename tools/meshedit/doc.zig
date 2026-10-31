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
/// the shape a form takes
const Kind=meshedit.settings.Kind;
/// the most cells across the whole sculpt
const maxCells=meshedit.settings.maxCells;
/// a form's numbers
const Vals=meshedit.settings.Vals;
/// a form's name, kept by value
const Name=@import("../labels.zig").Name;
/// one form of the sculpt: its name, its shape, whether it carves, its
/// shader and values
pub const Piece=struct{
  /// what the gardener calls it (`snout`, `left ear`); may be empty
  name:Name=.{},
  /// an ellipsoid, a rounded cone or a rounded box
  kind:Kind=.ellipsoid,
  /// whether it is carved out of what is before it (else melted in)
  carve:bool=false,
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
      },
      .at=at,
      .bone=0,
      .col=color.rgb(v.col[0],v.col[1],v.col[2]).toRgba8(255),
      .k=v.melt,
      .carve=p.carve,
      .part=@intFromEnum(p.shade),
    };
  }
  /// its twin: mirrored across the sculpt's middle (x=0), so its place
  /// across flips, and so do its turns about y and z (a mirror leaves the
  /// turn about x alone); every shape is even across its own x, so the
  /// shape itself is its own mirror
  pub fn mirrored(p:Piece)Piece{
    // the twin, its values flipped
    var t=p;
    t.v.pos[0]=-p.v.pos[0];
    t.v.rot[1]=-p.v.rot[1];
    t.v.rot[2]=-p.v.rot[2];
    return t;
  }
  /// the farthest it reaches from the sculpt's origin (m)
  pub fn reach(p:Piece)f32{
    return m.len(p.v.pos)+m.len(p.v.size)+p.v.melt;
  }
};
/// what a mesh's text holds: its cells and its forms, in order
pub const Doc=struct{
  /// how fine the surface is meshed: the cell size (m)
  cell:f32=cell,
  /// its forms, in the order they melt into one another
  pieces:std.ArrayList(Piece)=.empty,
  /// lets the forms go
  pub fn deinit(d:*Doc,gpa:Allocator)void{d.pieces.deinit(gpa);}
  /// writes the mesh as text: the header, the cell size, then each form's
  /// kind (and `carve`, `twin`), name (if it has one), shader and every value, one to a line
  pub fn write(d:*const Doc,w:*Writer)Writer.Error!void{
    try w.print(header++"\ncell {d}\n",.{d.cell});
    for(d.pieces.items)|*p|{
      try w.print("form {t}{s}{s}\n",.{p.kind,if(p.carve)" carve"else"",if(p.twin)" twin"else""});
      if(p.name.len>0)try w.print("name {s}\n",.{p.name.slice()});
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
      }else if(eql(u8,word,"form")){
        // the new form's shape, then whether it carves and has a twin
        const kind=stringToEnum(Kind,it.next() orelse return error.BadMesh) orelse return error.BadMesh;
        var p:Piece=.{.kind=kind};
        while(it.next())|flag|{
          if(eql(u8,flag,"carve"))p.carve=true else if(eql(u8,flag,"twin"))p.twin=true else return error.BadMesh;
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
    // whether any form adds (else there is nothing to mesh), and the farthest reach
    var solid=false;
    var far:f32=0;
    for(d.pieces.items)|p|{
      solid=solid or !p.carve;
      far=@max(far,p.reach());
    }
    if(!solid)return;
    // the sculpt the forms are melted into
    var sc:sculpt.Sculpt=.{.gpa=gpa,.parents=&.{null},.io=io};
    defer sc.deinit();
    // each form, then its twin right after it (so the two melt or carve
    // as one into what came before)
    for(d.pieces.items)|p|{
      try sc.add(p.form());
      if(p.twin)try sc.add(p.mirrored().form());
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
