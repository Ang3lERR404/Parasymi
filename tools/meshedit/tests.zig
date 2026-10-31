//! the mesh editor tested: its text, shaders and meshing.
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
