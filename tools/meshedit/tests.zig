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
/// the sculpt's bones
const rig=meshedit.rig;
/// makes a `V3` from its three parts
const v3=m.v3;
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
test"bones read back, twins hang mirrored off their parents' twins, and the skin rides them"{
  // the mesh of the rig check: a root, a shoulder and an elbow, both twinned
  const gpa=testing.allocator;
  var d:Doc=.{.cell=0.02};
  defer d.deinit(gpa);
  try d.bones.append(gpa,.{.name=.of("root")});
  try d.bones.append(gpa,.{.name=.of("shoulder"),.parent=0,.at=.{0.12,0.45,0},.twin=true});
  try d.bones.append(gpa,.{.name=.of("elbow"),.parent=1,.at=.{0.3,0.45,0},.twin=true});
  try d.pieces.append(gpa,.{.v=.{.pos=.{0,0.35,0},.size=.{0.12,0.2,0.1}}});
  try d.pieces.append(gpa,.{.kind=.cone,.twin=true,.bone=2,.v=.{.pos=.{0.39,0.45,0},.rot=.{0,0,90},.size=.{0.04,0.09,0.025}}});
  // read back from its text
  var out:Writer.Allocating=.init(gpa);
  defer out.deinit();
  try d.write(&out.writer);
  var back=try Doc.parse(gpa,out.written());
  defer back.deinit(gpa);
  try testing.expectEqual(@as(usize,3),back.bones.items.len);
  try testing.expectEqualStrings("elbow",back.bones.items[2].name.slice());
  try testing.expectEqual(@as(?u8,1),back.bones.items[2].parent);
  try testing.expect(back.bones.items[2].twin);
  try testing.expectEqual(@as(u8,2),back.pieces.items[1].bone);
  // the skeleton: the twins after the kept, the elbow's twin off the shoulder's
  const k=rig.skeleton(back.bones.items);
  try testing.expectEqual(@as(usize,5),k.count);
  try testing.expectEqual(@as(?u8,3),k.twinOf[1]);
  try testing.expectEqual(@as(?u8,4),k.twinOf[2]);
  try testing.expectEqual(@as(?u8,3),k.parents[4]);
  try testing.expectEqual(@as(f32,-0.3),k.at[4][0]);
  // at rest every bone carries the sculpt only where it is placed
  var bones:[rig.maxBones]m.M4=undefined;
  const turns=[_]V3{.{0,0,0}}**5;
  rig.pose(&k,&turns,v3(0,0,0),m.translate(v3(1,0,0)),bones[0..5]);
  for(bones[0..5])|b|try testing.expectApproxEqAbs(@as(f32,1.3),m.mulPoint(b,v3(0.3,0,0))[0],1e-5);
  // the elbow turned a quarter about z: its joint stays, a point past it swings up
  var bent=turns;
  bent[2]=.{0,0,90};
  rig.pose(&k,&bent,v3(0,0,0),m.identity,bones[0..5]);
  const j=m.mulPoint(bones[2],v3(0.3,0.45,0));
  try testing.expectApproxEqAbs(@as(f32,0.3),j[0],1e-5);
  const tip=m.mulPoint(bones[2],v3(0.4,0.45,0));
  try testing.expectApproxEqAbs(@as(f32,0.55),tip[1],1e-5);
  // the mesh's vertices ride more than one bone, the forearms' their elbows
  var b:meshgen.Builder=.{.gpa=gpa};
  defer b.deinit();
  try back.mesh(gpa,null,false,&b);
  // whether some vertex rides the elbow, and some its twin
  var elbow=false;
  var twin=false;
  for(b.v.items,b.skin.items)|v,sk|{
    if(sk.weights[0]<200)continue;
    // the bone it rides most
    const first=sk.bones&255;
    elbow=elbow or (first==2 and v.pos[0]>0.35);
    twin=twin or (first==4 and v.pos[0] < -0.35);
  }
  try testing.expect(elbow and twin);
}
test"a bone taken out hands its children and its forms to its parent"{
  // a mesh of three bones in a line and a form on each
  const gpa=testing.allocator;
  var d:Doc=.{};
  try d.bones.append(gpa,.{.name=.of("root")});
  try d.bones.append(gpa,.{.name=.of("mid"),.parent=0});
  try d.bones.append(gpa,.{.name=.of("tip"),.parent=1});
  for(0..3)|i|try d.pieces.append(gpa,.{.bone=@intCast(i)});
  const first=try meshedit.editor.text(gpa,&d);
  defer gpa.free(first);
  var e:Editor=.{.gpa=gpa,.io=testing.io,.path="unused",.doc=d,.history=try .init(gpa,first)};
  defer e.doc.deinit(gpa);
  defer e.history.deinit();
  // the middle bone taken out
  e.bsel=1;
  meshedit.rigging.remove(&e);
  try testing.expectEqual(@as(usize,2),e.doc.bones.items.len);
  try testing.expectEqual(@as(?u8,0),e.doc.bones.items[1].parent);
  try testing.expectEqual(@as(u8,0),e.pieces()[1].bone);
  try testing.expectEqual(@as(u8,1),e.pieces()[2].bone);
  // the root stays while other bones hang off it
  e.bsel=0;
  meshedit.rigging.remove(&e);
  try testing.expectEqual(@as(usize,2),e.doc.bones.items.len);
  // a new bone hangs off the selected one, named the first free
  e.bsel=1;
  try meshedit.rigging.add(&e);
  try testing.expectEqual(@as(?u8,1),e.doc.bones.items[2].parent);
  try testing.expectEqualStrings("bone 3",e.doc.bones.items[2].name.slice());
}
