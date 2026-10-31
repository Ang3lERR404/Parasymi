//! a sculpt as the mesh editor keeps it (`src/mesh/<name>.mesh`): its
//! forms (ellipsoids, rounded cones, rounded boxes, curling tubes, each
//! melted in, carved out or only inking), its bones (sculpt_rig.zig), read
//! from and written to text, and meshed as one seamless skinned surface
//! (engine gfx/sculpt.zig). The game reads these at startup (sculpts.zig);
//! the mesh editor shapes them.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
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
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, matrices, angles
const m=engine.core.math;
/// colour conversions: a form's colour into bytes
const color=engine.core.color;
/// SDF sculpting: forms melted into one surface and meshed
const sculpt=engine.gfx.sculpt;
/// clip channels, borrowed to name every value of a form
const clip=engine.anim.clip;
/// the game's mesh builder, which the surface is meshed into
const meshgen=lib.meshgen;
/// a part role: the shader a part of the surface is drawn with
const Part=lib.vertex.Part;
/// a point or size in the sculpt (m)
const V3=m.V3;
/// makes a vector from its three parts
const v3=m.v3;
/// the sculpt's bones: joints, parents, twins
const rig=lib.sculptRig;
/// a 4×4 matrix: where a form stands
const M4=m.M4;
/// whether a file name ends so
const endsWith=std.mem.endsWith;
/// one bone of the sculpt
const Bone=rig.Bone;
/// sculpts are kept here (from the repo root)
pub const dir="src/mesh";
/// the file ending every kept sculpt carries
pub const ext=".mesh";
/// the first line of a mesh's text
pub const header="# mesh";
/// the surface's cell size to start (m)
pub const cell:f32=0.01;
/// the finest the cells may be (m)
pub const cellMin:f32=0.0025;
/// the most cells across the whole sculpt (past that they widen)
pub const maxCells:f32=256;
/// and its cells this many times wider then (full detail once let go)
pub const dragCoarse:f32=2;
/// the most bytes a form's or a bone's name holds
pub const nameCap=24;
/// a name kept by value (a form's, a bone's)
pub const Name=struct{
  /// its bytes; the first `len` are real
  buf:[nameCap]u8=undefined,
  /// how many bytes it holds
  len:u8=0,
  /// the name's text
  pub fn slice(n:*const Name)[]const u8{return n.buf[0..n.len];}
  /// `text` as a name, cut to fit
  pub fn of(text:[]const u8)Name{
    // the name being filled
    var n=Name{};
    n.len=@intCast(@min(text.len,nameCap));
    @memcpy(n.buf[0..n.len],text[0..n.len]);
    return n;
  }
};
/// the shape a form takes
pub const Kind=enum{
  /// a round body with three radii
  ellipsoid,
  /// a rounded cone from a foot to a tip
  cone,
  /// a box with rounded edges
  box,
  /// a tube from its foot up along y, curling toward x as it goes: a horn,
  /// a tail, a tendril
  tube,
  /// another whole sculpt (`use`), placed, turned and scaled (`size` x, the
  /// same every way) as one form, its own forms melting in: a part made
  /// once and used in many (a claw, an eye)
  nest,
};
/// the most a tube's curl is cut into segments: one for each this many
/// degrees of it (at least one, at most the sculpt's `chainMax`)
pub const curlStep:f32=12;
/// a form's numbers, every one a value the editor shows and keeps
pub const Vals=struct{
  /// where it stands (m)
  pos:V3=.{0,0.3,0},
  /// how it is turned (degrees: y, then x, then z)
  rot:V3=.{0,0,0},
  /// its radii (an ellipsoid's), foot and tip radii and half length (a
  /// cone's x, z and y), or half extents (a box's) (m)
  size:V3=.{0.15,0.15,0.15},
  /// how much a box's edges are rounded (m)
  round:f32=0.02,
  /// how far it melts into the forms before it (m); an ink form's fade
  melt:f32=0.03,
  /// how far a tube curls toward x from its foot to its tip (degrees)
  curl:f32=0,
  /// its colour, red, green and blue (0..1)
  col:V3=.{0.45,0.42,0.3},
};
/// every value of a form, each a channel the panel shows and the text keeps
pub const Ch=clip.Channels(Vals);
/// one form of the sculpt: its name, its shape, whether it carves, its
/// shader and values
pub const Piece=struct{
  /// what the gardener calls it (`snout`, `left ear`); may be empty
  name:Name=.{},
  /// a nest's sculpt, by name (`claw`: `src/mesh/claw.mesh`)
  use:Name=.{},
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
  /// as the sculpt takes it (a shape: never a nest, which `Doc` opens)
  pub fn form(p:Piece)sculpt.Form{return p.formIn(m.identity,1);}
  /// its place and turn as one matrix, its place `s` times as far out
  pub fn placed(p:Piece,s:f32)M4{
    // its values
    const v=p.v;
    return m.chain(&.{m.translate(v.pos*m.splat3(s)),m.rotY(m.rad(v.rot[1])),m.rotX(m.rad(v.rot[0])),m.rotZ(m.rad(v.rot[2]))});
  }
  /// as the sculpt takes it standing in `at`, everything about it `s`
  /// times as big (a form of a nested sculpt)
  pub fn formIn(p:Piece,at:M4,s:f32)sculpt.Form{
    // its values `s` times as big, and the origin in its frame
    var v=p.v;
    v.size*=m.splat3(s);
    v.round*=s;
    v.melt*=s;
    const z=v3(0,0,0);
    return.{
      .shape=switch(p.kind){
        .ellipsoid=>.{.ellipsoid=.{.c=z,.r=v.size}},
        .cone=>.{.cone=.{.a=v3(0,-v.size[1],0),.b=v3(0,v.size[1],0),.ra=v.size[0],.rb=v.size[2]}},
        .box=>.{.box=.{.c=z,.half=v.size,.round=@min(v.round,@reduce(.Min,v.size))}},
        .tube=>.{.chain=arc(v)},
        .nest=>unreachable,
      },
      .at=m.mul(at,p.placed(s)),
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
      if(p.kind==.nest)try w.print("use {s}\n",.{p.use.slice()});
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
      }else if(eql(u8,word,"use")){
        if(d.pieces.items.len==0)return error.BadMesh;
        d.pieces.items[d.pieces.items.len-1].use=.of(trim(u8,it.rest()," \t"));
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
  /// too big for that many; `dragCoarse` times them while `coarse`), each
  /// nest opened through `lookup` (none: nests are left out); nothing when
  /// no form adds anything
  pub fn mesh(d:*const Doc,gpa:Allocator,io:?Io,coarse:bool,b:*meshgen.Builder,lookup:?Lookup)Allocator.Error!void{
    // the bones the forms ride, twins counted
    const k=rig.skeleton(d.bones.items);
    // the sculpt the forms are melted into, weighted to those bones
    var sc:sculpt.Sculpt=.{.gpa=gpa,.parents=k.parents[0..k.count],.io=io};
    defer sc.deinit();
    if(!try d.addForms(&sc,&k,lookup,.{}))return;
    // the farthest any form reaches from the origin
    var far:f32=0;
    for(sc.forms.items)|pf|far=@max(far,m.len(pf.centre)+pf.reach);
    // the cell size this time (m)
    const h=@max(d.cell,2*far/maxCells)*(if(coarse)dragCoarse else 1);
    try sc.mesh(meshgen.gen,b,h,0.5,.stem);
  }
  /// where a sculpt's forms are being put: in what frame, how big, whether
  /// mirrored, on what bone, and how deep among nests
  const Within=struct{
    /// the frame the forms stand in
    at:M4=m.identity,
    /// how many times as big as kept they are
    s:f32=1,
    /// whether each is mirrored across its sculpt's middle (a twin's nest)
    mirror:bool=false,
    /// the bone every form rides (a nest's), else each its own
    bone:?u8=null,
    /// how many nests deep
    depth:u8=0,
  };
  /// every form (and its twin) put into `sc` within `w`, each nest opened
  /// through `lookup` and its forms put in after the forms before it, so
  /// they melt in where the nest stands; whether any adds to the surface
  fn addForms(d:*const Doc,sc:*sculpt.Sculpt,k:*const rig.Skeleton,lookup:?Lookup,w:Within)Allocator.Error!bool{
    // whether any form adds (neither carving nor inking)
    var solid=false;
    for(d.pieces.items)|p|for([_]bool{false,true})|twin|{
      if(twin and !p.twin)continue;
      // the form as it stands: mirrored once for a twin, once inside a twin's nest
      const q=if(twin!=w.mirror)p.mirrored()else p;
      // the bone it rides: the nest's, else its own (a twin its bone's twin)
      const on:u8=if(d.bones.items.len==0)0 else@min(p.bone,d.bones.items.len-1);
      const bone=w.bone orelse k.ride(on,twin);
      if(q.kind==.nest){
        if(w.depth>=nestDepth)continue;
        // the sculpt it places (unknown: left out)
        const inner=(lookup orelse continue).find(q.use.slice()) orelse continue;
        solid=try inner.addForms(sc,k,lookup,.{.at=m.mul(w.at,q.placed(w.s)),.s=w.s*@max(q.v.size[0],nestScaleMin),.mirror=twin!=w.mirror,.bone=bone,.depth=w.depth+1}) or solid;
        continue;
      }
      // the form as the sculpt takes it, on its bone
      var f=q.formIn(w.at,w.s);
      f.bone=bone;
      try sc.add(f);
      solid=solid or (!q.carve and !q.ink);
    };
    return solid;
  }
};
/// how many nests deep a sculpt is opened (a sculpt nesting itself stops here)
pub const nestDepth=4;
/// the least a nest's scale may be
const nestScaleMin:f32=0.01;
/// finds a sculpt by name, for the nests: `find` on whatever holds them
pub const Lookup=struct{
  /// what holds the sculpts
  ctx:*const anyopaque,
  /// the sculpt in `ctx` named so, if there is one
  findIn:*const fn(ctx:*const anyopaque,name:[]const u8)?*const Doc,
  /// the sculpt named `name`, if there is one
  pub fn find(l:Lookup,name:[]const u8)?*const Doc{return l.findIn(l.ctx,name);}
};
/// every sculpt kept in one folder, read at once, for the nests (the
/// editors read `dir`; a file that will not read is passed over)
pub const Folder=struct{
  /// the allocator the sculpts and names are kept with
  gpa:Allocator,
  /// each sculpt's name, and the sculpt
  names:std.ArrayList([]u8)=.empty,
  docs:std.ArrayList(Doc)=.empty,
  /// every `.mesh` in `path` under `root` (none there: an empty folder)
  pub fn load(gpa:Allocator,io:Io,root:Io.Dir,path:[]const u8)Allocator.Error!Folder{
    // the folder being filled
    var f:Folder=.{.gpa=gpa};
    errdefer f.deinit();
    // the directory, open to be walked
    var dirH=root.openDir(io,path,.{.iterate=true}) catch return f;
    defer dirH.close(io);
    var it=dirH.iterate();
    while(it.next(io) catch return f)|e|{
      if(e.kind!=.file or !endsWith(u8,e.name,ext))continue;
      // its text, read and parsed
      const text=dirH.readFileAlloc(io,e.name,gpa,.limited(1<<22)) catch continue;
      defer gpa.free(text);
      var doc=Doc.parse(gpa,text)catch|er|switch(er){
        error.OutOfMemory=>return error.OutOfMemory,
        error.BadMesh=>continue,
      };
      errdefer doc.deinit(gpa);
      // its name, kept
      const name=try gpa.dupe(u8,e.name[0..e.name.len-ext.len]);
      errdefer gpa.free(name);
      try f.names.append(gpa,name);
      errdefer _=f.names.pop();
      try f.docs.append(gpa,doc);
    }
    return f;
  }
  /// lets every sculpt go
  pub fn deinit(f:*Folder)void{
    for(f.names.items)|n|f.gpa.free(n);
    for(f.docs.items)|*d|d.deinit(f.gpa);
    f.names.deinit(f.gpa);
    f.docs.deinit(f.gpa);
  }
  /// the sculpt named `name`, if it is here
  pub fn find(f:*const Folder,name:[]const u8)?*const Doc{
    for(f.names.items,f.docs.items)|n,*d|if(eql(u8,n,name))return d;
    return null;
  }
  /// a lookup over this folder
  pub fn lookup(f:*const Folder)Lookup{
    return.{.ctx=f,.findIn=struct{
      /// the sculpt named so in the folder `ctx`
      fn findIn(ctx:*const anyopaque,name:[]const u8)?*const Doc{
        return@as(*const Folder,@ptrCast(@alignCast(ctx))).find(name);
      }
    }.findIn};
  }
};
/// the test helpers
const testing=std.testing;
test"a nest places another sculpt's forms, scaled, twinned in mirror, and reads back"{
  const gpa=testing.allocator;
  // a folder of one part: a claw, a tube curling one way off to the side
  var f:Folder=.{.gpa=gpa};
  defer f.deinit();
  try f.names.append(gpa,try gpa.dupe(u8,"claw"));
  try f.docs.append(gpa,.{});
  try f.docs.items[0].pieces.append(gpa,.{.kind=.tube,.v=.{.pos=.{0.05,0,0},.size=.{0.04,0.3,0.01},.curl=60}});
  // a body nesting the claw at half its size, twinned across the middle
  var d:Doc=.{.cell=0.01};
  defer d.deinit(gpa);
  try d.pieces.append(gpa,.{.v=.{.pos=.{0,0.3,0},.size=.{0.1,0.1,0.1}}});
  try d.pieces.append(gpa,.{.kind=.nest,.use=.of("claw"),.twin=true,.v=.{.pos=.{0.2,0.3,0},.size=.{0.5,1,1}}});
  // its text keeps the nest and what it uses
  var out:Writer.Allocating=.init(gpa);
  defer out.deinit();
  try d.write(&out.writer);
  var back=try Doc.parse(gpa,out.written());
  defer back.deinit(gpa);
  try testing.expect(back.pieces.items[1].kind==.nest);
  try testing.expectEqualStrings("claw",back.pieces.items[1].use.slice());
  // meshed: as far to one side as the other, the claws reaching past the body
  var b:meshgen.Builder=.{.gpa=gpa};
  defer b.deinit();
  try back.mesh(gpa,null,false,&b,f.lookup());
  // the farthest the surface reaches to either side (m)
  var lo:f32=0;
  var hi:f32=0;
  for(b.v.items)|v|{
    lo=@min(lo,v.pos[0]);
    hi=@max(hi,v.pos[0]);
  }
  try testing.expect(hi>0.2);
  try testing.expectApproxEqAbs(hi,-lo,0.02);
  // without the folder the nest is left out: only the body
  var bare:meshgen.Builder=.{.gpa=gpa};
  defer bare.deinit();
  try back.mesh(gpa,null,false,&bare,null);
  for(bare.v.items)|v|try testing.expect(@abs(v.pos[0])<0.15);
}
test"a sculpt nesting itself stops at the depth"{
  const gpa=testing.allocator;
  // a folder whose one sculpt nests itself, smaller and off to the side
  var f:Folder=.{.gpa=gpa};
  defer f.deinit();
  try f.names.append(gpa,try gpa.dupe(u8,"self"));
  try f.docs.append(gpa,.{});
  try f.docs.items[0].pieces.append(gpa,.{.v=.{.size=.{0.05,0.05,0.05}}});
  try f.docs.items[0].pieces.append(gpa,.{.kind=.nest,.use=.of("self"),.v=.{.pos=.{0.2,0,0},.size=.{0.5,1,1}}});
  // meshed: one ball for each depth, the last as far as the depth allows
  var b:meshgen.Builder=.{.gpa=gpa};
  defer b.deinit();
  try f.docs.items[0].mesh(gpa,null,false,&b,f.lookup());
  // the farthest it reaches (m): each ball half the last, half as far on
  // (0.2, 0.3, 0.35, 0.375 out), the finest under a cell and so unseen
  var hi:f32=0;
  for(b.v.items)|v|hi=@max(hi,v.pos[0]);
  try testing.expect(hi>0.3 and hi<0.4);
}
