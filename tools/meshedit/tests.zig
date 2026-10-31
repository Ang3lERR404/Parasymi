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
