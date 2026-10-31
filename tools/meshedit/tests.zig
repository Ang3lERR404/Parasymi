//! the mesh editor tested: its text, shaders, meshing, undo and redo.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the I/O interface
const Io=std.Io;
/// a text writer, which a mesh is written into
const Writer=Io.Writer;
/// the test helpers
const testing=std.testing;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the game's mesh builder, which the surface is meshed into
const meshgen=ps.meshgen;
/// a part role: the shader a part of the surface is drawn with
const Part=ps.vertex.Part;
/// the editor's root, through which its other files are reached
const meshedit=@import("../meshedit.zig");
/// every value of a form, each a named channel
const Ch=meshedit.settings.Ch;
/// the mesh as kept: its cells and its forms
const Doc=meshedit.doc.Doc;
/// the editor's state, its undo and redo tested
const Editor=meshedit.editor.Editor;
/// a form's numbers
const Vals=meshedit.settings.Vals;
/// a form's turns as a matrix, and back
const turnOf=meshedit.editor.turnOf;
const anglesOf=meshedit.editor.anglesOf;
/// all the maths: angles
const m=ps.engine.core.math;
/// a point or turn (three numbers)
const V3=m.V3;
/// the shader after (or before) a form's
const nextShade=meshedit.settings.nextShade;
test"a mesh's text reads back as written"{
  // the testing allocator, and a mesh of two forms (a plain one, a carved resin box)
  const gpa=testing.allocator;
  var d:Doc=.{.cell=0.02};
  defer d.deinit(gpa);
  try d.pieces.append(gpa,.{});
  try d.pieces.append(gpa,.{.name=.of("left ear tip"),.kind=.box,.carve=true,.shade=.resin,.v=.{.pos=.{0.1,0.2,-0.3},.round=0.01}});
  // the mesh's text
  var out:Writer.Allocating=.init(gpa);
  defer out.deinit();
  try d.write(&out.writer);
  // the mesh read back from it
  var back=try Doc.parse(gpa,out.written());
  defer back.deinit(gpa);
  try testing.expectEqual(d.cell,back.cell);
  try testing.expectEqual(d.pieces.items.len,back.pieces.items.len);
  for(d.pieces.items,back.pieces.items)|*a,*z|{
    try testing.expectEqualStrings(a.name.slice(),z.name.slice());
    try testing.expectEqual(a.kind,z.kind);
    try testing.expectEqual(a.carve,z.carve);
    try testing.expectEqual(a.shade,z.shade);
    for(0..Ch.count)|i|try testing.expectEqual(Ch.get(&a.v,i),Ch.get(&z.v,i));
  }
}
test"a form's shader shades its part of the surface, and the list wraps round"{
  // the testing allocator, a mesh, and the builder it is meshed into
  const gpa=testing.allocator;
  var d:Doc=.{.cell=0.02};
  defer d.deinit(gpa);
  var b:meshgen.Builder=.{.gpa=gpa};
  defer b.deinit();
  try d.pieces.append(gpa,.{.shade=.leaf});
  try d.mesh(gpa,null,false,&b);
  try testing.expect(b.v.items.len>0);
  for(b.v.items)|v|try testing.expectEqual(@intFromEnum(Part.leaf),v.part);
  // the last role, which steps on round to the first
  const last:Part=@enumFromInt(@typeInfo(Part).@"enum".fields.len-1);
  try testing.expectEqual(Part.stem,nextShade(last,.on));
  try testing.expectEqual(last,nextShade(.stem,.back));
}
test"carving alone makes no surface, a form makes a closed one"{
  // the testing allocator, a mesh, and the builder it is meshed into
  const gpa=testing.allocator;
  var d:Doc=.{.cell=0.02};
  defer d.deinit(gpa);
  var b:meshgen.Builder=.{.gpa=gpa};
  defer b.deinit();
  try d.pieces.append(gpa,.{.carve=true});
  try d.mesh(gpa,null,false,&b);
  try testing.expectEqual(@as(usize,0),b.v.items.len);
  try d.pieces.append(gpa,.{.kind=.cone});
  try d.mesh(gpa,null,false,&b);
  try testing.expect(b.v.items.len>0);
  try testing.expectEqual(@as(usize,0),b.v.items.len%3);
}
test"a whole drag undoes in one step and redoes again"{
  // the testing allocator, a mesh of one form, and the editor on it
  const gpa=testing.allocator;
  var d:Doc=.{};
  try d.pieces.append(gpa,.{});
  // the mesh's text as it starts
  const first=try meshedit.editor.text(gpa,&d);
  defer gpa.free(first);
  var e:Editor=.{.gpa=gpa,.io=testing.io,.path="unused",.doc=d,.history=try .init(gpa,first)};
  defer e.doc.deinit(gpa);
  defer e.history.deinit();
  // a drag held over several frames: nothing settles until it ends
  e.drag=.value;
  for(0..5)|_|{
    e.nudge(Ch.find("pos.x").?,0.1);
    try e.settle();
  }
  try testing.expectEqual(@as(usize,0),e.history.back.items.len);
  e.drag=.none;
  try e.settle();
  try testing.expectEqual(@as(usize,1),e.history.back.items.len);
  // a form made after it, then both undone one at a time
  try e.doc.pieces.append(gpa,.{});
  try e.settle();
  try e.undo();
  try testing.expectEqual(@as(usize,1),e.pieces().len);
  try testing.expectApproxEqAbs(@as(f32,0.5),e.pieces()[0].v.pos[0],1e-5);
  try e.undo();
  try testing.expectEqual(@as(f32,0),e.pieces()[0].v.pos[0]);
  try e.redo();
  try testing.expectApproxEqAbs(@as(f32,0.5),e.pieces()[0].v.pos[0],1e-5);
}
test"a twinned form reads back so, and its surface is mirrored across the middle"{
  // the testing allocator, a mesh of one turned box off to one side with a twin
  const gpa=testing.allocator;
  var d:Doc=.{.cell=0.02};
  defer d.deinit(gpa);
  try d.pieces.append(gpa,.{.kind=.box,.carve=false,.twin=true,.v=.{.pos=.{0.3,0.2,0.05},.rot=.{10,25,-15},.size=.{0.08,0.05,0.12}}});
  // the mesh's text, and the mesh read back from it
  var out:Writer.Allocating=.init(gpa);
  defer out.deinit();
  try d.write(&out.writer);
  var back=try Doc.parse(gpa,out.written());
  defer back.deinit(gpa);
  try testing.expect(back.pieces.items[0].twin);
  try testing.expect(!back.pieces.items[0].carve);
  // the surface, which reaches as far to one side as to the other
  var b:meshgen.Builder=.{.gpa=gpa};
  defer b.deinit();
  try d.mesh(gpa,null,false,&b);
  try testing.expect(b.v.items.len>0);
  // the farthest the surface reaches to either side (m)
  var lo:f32=0;
  var hi:f32=0;
  for(b.v.items)|v|{
    lo=@min(lo,v.pos[0]);
    hi=@max(hi,v.pos[0]);
  }
  try testing.expectApproxEqAbs(hi,-lo,0.02);
  // the twin's turn is the form's, mirrored: as far below the middle as the form is above it
  const t=d.pieces.items[0].mirrored();
  try testing.expectEqual(@as(f32,-0.3),t.v.pos[0]);
  try testing.expectEqual(@as(f32,10),t.v.rot[0]);
  try testing.expectEqual(@as(f32,-25),t.v.rot[1]);
  try testing.expectEqual(@as(f32,15),t.v.rot[2]);
}
test"a turn read back into its angles makes the same turn"{
  for([_]V3{.{0,0,0},.{30,-50,20},.{-80,170,-120},.{89.9,10,-5},.{90,40,0},.{-45,0,135}})|r|{
    // the turn, and the turn its angles make again
    const a=turnOf(r);
    const b=turnOf(anglesOf(a));
    for(0..3)|c|inline for(0..3)|k|try testing.expectApproxEqAbs(a[c][k],b[c][k],1e-4);
  }
}
test"a tube curls round its circle, an ink form adds nothing, and both read back"{
  // a quarter turn of curl over a metre: the tip a radius over and up
  const v:Vals=.{.size=.{0.05,1,0.02},.curl=90};
  const c=meshedit.doc.arc(v);
  // the circle's radius (m)
  const rad=1/m.rad(90);
  try testing.expectApproxEqAbs(rad,c.pts[c.n][0],1e-4);
  try testing.expectApproxEqAbs(rad,c.pts[c.n][1],1e-4);
  try testing.expectEqual(@as(f32,0.02),c.r[c.n]);
  // a straight tube is one segment
  try testing.expectEqual(@as(u8,1),meshedit.doc.arc(.{}).n);
  // a mesh of an inked tube alone, then with a ball under it
  const gpa=testing.allocator;
  var d:Doc=.{.cell=0.02};
  defer d.deinit(gpa);
  try d.pieces.append(gpa,.{.kind=.tube,.ink=true,.twin=true,.v=.{.curl=-40}});
  var b:meshgen.Builder=.{.gpa=gpa};
  defer b.deinit();
  try d.mesh(gpa,null,false,&b);
  try testing.expectEqual(@as(usize,0),b.v.items.len);
  try d.pieces.insert(gpa,0,.{});
  try d.mesh(gpa,null,false,&b);
  try testing.expect(b.v.items.len>0);
  // the text read back keeps the tube, its ink, its twin and its curl
  var out:Writer.Allocating=.init(gpa);
  defer out.deinit();
  try d.write(&out.writer);
  var back=try Doc.parse(gpa,out.written());
  defer back.deinit(gpa);
  const p=back.pieces.items[1];
  try testing.expect(p.kind==.tube and p.ink and p.twin and !p.carve);
  try testing.expectEqual(@as(f32,-40),p.v.curl);
  // a twin's tube curls the other way
  try testing.expectEqual(@as(f32,40),p.mirrored().v.curl);
}
test"a group moves and turns with the selected form, round where it stands"{
  // a mesh of two forms, the second gathered into the first's group
  const gpa=testing.allocator;
  var d:Doc=.{};
  try d.pieces.append(gpa,.{.v=.{.pos=.{0,0.3,0}}});
  try d.pieces.append(gpa,.{.v=.{.pos=.{0.2,0.3,0}}});
  const first=try meshedit.editor.text(gpa,&d);
  defer gpa.free(first);
  var e:Editor=.{.gpa=gpa,.io=testing.io,.path="unused",.doc=d,.history=try .init(gpa,first)};
  defer e.doc.deinit(gpa);
  defer e.history.deinit();
  e.pick(1,true);
  try testing.expect(e.pieces()[1].grouped);
  // the selected form turned a quarter about y, then moved up
  var was=e.pieces()[0].v;
  e.pieces()[0].v.rot[1]=90;
  e.follow(was);
  // the gathered form swung round to stand before it, turned as it was
  const g=e.pieces()[1].v;
  try testing.expectApproxEqAbs(@as(f32,0),g.pos[0],1e-5);
  try testing.expectApproxEqAbs(@as(f32,-0.2),g.pos[2],1e-5);
  try testing.expectApproxEqAbs(@as(f32,90),g.rot[1],1e-3);
  was=e.pieces()[0].v;
  e.pieces()[0].v.pos[1]+=0.1;
  e.follow(was);
  try testing.expectApproxEqAbs(@as(f32,0.4),e.pieces()[1].v.pos[1],1e-5);
  // snapping lays them on the grid
  e.pieces()[1].v.pos[0]=0.0123;
  e.snap();
  try testing.expectApproxEqAbs(@as(f32,0.01),e.pieces()[1].v.pos[0],1e-6);
}
