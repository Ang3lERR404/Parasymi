//! a mesh as the editor keeps it: its forms, read from and written to text.
const std=ps.std;
const Allocator=std.mem.Allocator;
const Io=std.Io;
const Writer=Io.Writer;
const eql=std.mem.eql;
const stringToEnum=std.meta.stringToEnum;
const splitScalar=std.mem.splitScalar;
const tokenizeScalar=std.mem.tokenizeScalar;
const trim=std.mem.trim;
const parseFloat=std.fmt.parseFloat;
const engine=ps.engine;
const m=engine.core.math;
const color=engine.core.color;
const sculpt=engine.gfx.sculpt;
const ps=@import("parasymi");
const gizmo=@import("../gizmo.zig");
const meshgen=ps.meshgen;
const Part=ps.vertex.Part;
const v3=m.v3;
const meshedit=@import("../meshedit.zig");
const cell=meshedit.settings.cell;
const cellMin=meshedit.settings.cellMin;
const Ch=meshedit.settings.Ch;
const dragCoarse=meshedit.settings.dragCoarse;
const header=meshedit.settings.header;
const Kind=meshedit.settings.Kind;
const maxCells=meshedit.settings.maxCells;
const Vals=meshedit.settings.Vals;
pub const Piece=struct{
  kind:Kind=.ellipsoid,
  carve:bool=false,
  /// the shader (part role) its part of the surface is drawn with
  shade:Part=.stem,
  v:Vals=.{},
  /// as the sculpt takes it
  pub fn form(p:Piece)sculpt.Form{
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
  /// the farthest it reaches from the sculpt's origin (m)
  pub fn reach(p:Piece)f32{
    return m.len(p.v.pos)+m.len(p.v.size)+p.v.melt;
  }
};
/// what a mesh's text holds: its cells and its forms, in order
pub const Doc=struct{
  cell:f32=cell,
  pieces:std.ArrayList(Piece)=.empty,
  pub fn deinit(d:*Doc,gpa:Allocator)void{d.pieces.deinit(gpa);}
  pub fn write(d:*const Doc,w:*Writer)Writer.Error!void{
    try w.print(header++"\ncell {d}\n",.{d.cell});
    for(d.pieces.items)|p|{
      try w.print("form {t}{s}\nshade {t}\n",.{p.kind,if(p.carve)" carve"else"",p.shade});
      for(Ch.names,0..)|n,i|try w.print("{s} {d}\n",.{n,Ch.get(&p.v,i)});
    }
  }
  pub const ParseError=error{BadMesh,OutOfMemory};
  pub fn parse(gpa:Allocator,text:[]const u8)ParseError!Doc{
    var d:Doc=.{};
    errdefer d.deinit(gpa);
    var lines=splitScalar(u8,text,'\n');
    while(lines.next())|raw|{
      const line=trim(u8,raw," \t\r");
      if(line.len==0 or line[0]=='#')continue;
      var it=tokenizeScalar(u8,line,' ');
      const word=it.next() orelse continue;
      if(eql(u8,word,"cell")){
        d.cell=@max(cellMin,parseFloat(f32,it.next() orelse return error.BadMesh) catch return error.BadMesh);
      }else if(eql(u8,word,"form")){
        const kind=stringToEnum(Kind,it.next() orelse return error.BadMesh) orelse return error.BadMesh;
        const carve=if(it.next())|c|eql(u8,c,"carve")else false;
        try d.pieces.append(gpa,.{.kind=kind,.carve=carve});
      }else if(eql(u8,word,"shade")){
        if(d.pieces.items.len==0)return error.BadMesh;
        d.pieces.items[d.pieces.items.len-1].shade=stringToEnum(Part,it.next() orelse return error.BadMesh) orelse return error.BadMesh;
      }else{
        const i=Ch.find(word) orelse return error.BadMesh;
        if(d.pieces.items.len==0)return error.BadMesh;
        const v=parseFloat(f32,it.next() orelse return error.BadMesh) catch return error.BadMesh;
        Ch.set(&d.pieces.items[d.pieces.items.len-1].v,i,v);
      }
    }
    return d;
  }
  /// its surface into `b`, cells `cell` across (wider where the sculpt is
  /// too big for that many; `DRAG_COARSE` times them while `coarse`);
  /// nothing when no form adds anything
  pub fn mesh(d:*const Doc,gpa:Allocator,io:?Io,coarse:bool,b:*meshgen.Builder)Allocator.Error!void{
    var solid=false;
    var far:f32=0;
    for(d.pieces.items)|p|{
      solid=solid or !p.carve;
      far=@max(far,p.reach());
    }
    if(!solid)return;
    var sc:sculpt.Sculpt=.{.gpa=gpa,.parents=&.{null},.io=io};
    defer sc.deinit();
    for(d.pieces.items)|p|try sc.add(p.form());
    const h=@max(d.cell,2*far/maxCells)*(if(coarse)dragCoarse else 1);
    try sc.mesh(meshgen.gen,b,h,0.5,.stem);
  }
};
pub const Drag=enum{none,value,gizmo};
