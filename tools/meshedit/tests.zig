//! the mesh editor tested: its text, shaders and meshing.
const std = ps.std;
const Io = std.Io;
const Writer = Io.Writer;
const testing = std.testing;
const ps = @import("parasymi");
const meshgen = ps.meshgen;
const Part = ps.vertex.Part;

const meshedit = @import("../meshedit.zig");
const Ch = meshedit.settings.Ch;
const Doc = meshedit.doc.Doc;
const nextShade = meshedit.settings.nextShade;

test "a mesh's text reads back as written" {
  const gpa = testing.allocator;
  var d:Doc = .{ .cell = 0.02 };
  defer d.deinit(gpa);
  try d.pieces.append(gpa, .{});
  try d.pieces.append(gpa, .{ .kind = .box, .carve = true, .shade = .resin, .v = .{ .pos = .{ 0.1, 0.2, -0.3 }, .round = 0.01 } });
  var out:Writer.Allocating = .init(gpa);
  defer out.deinit();
  try d.write(&out.writer);
  var back = try Doc.parse(gpa, out.written());
  defer back.deinit(gpa);
  try testing.expectEqual(d.cell, back.cell);
  try testing.expectEqual(d.pieces.items.len, back.pieces.items.len);
  for (d.pieces.items, back.pieces.items) |a, z| {
    try testing.expectEqual(a.kind, z.kind);
    try testing.expectEqual(a.carve, z.carve);
    try testing.expectEqual(a.shade, z.shade);
    for (0..Ch.count) |i| try testing.expectEqual(Ch.get(&a.v, i), Ch.get(&z.v, i));
  }
}

test "a form's shader shades its part of the surface, and the list wraps round" {
  const gpa = testing.allocator;
  var d:Doc = .{ .cell = 0.02 };
  defer d.deinit(gpa);
  var b:meshgen.Builder = .{ .gpa = gpa };
  defer b.deinit();
  try d.pieces.append(gpa, .{ .shade = .leaf });
  try d.mesh(gpa, null, false, &b);
  try testing.expect(b.v.items.len > 0);
  for (b.v.items) |v| try testing.expectEqual(@intFromEnum(Part.leaf), v.part);
  const last:Part = @enumFromInt(@typeInfo(Part).@"enum".fields.len - 1);
  try testing.expectEqual(Part.stem, nextShade(last, .on));
  try testing.expectEqual(last, nextShade(.stem, .back));
}

test "carving alone makes no surface, a form makes a closed one" {
  const gpa = testing.allocator;
  var d:Doc = .{ .cell = 0.02 };
  defer d.deinit(gpa);
  var b:meshgen.Builder = .{ .gpa = gpa };
  defer b.deinit();
  try d.pieces.append(gpa, .{ .carve = true });
  try d.mesh(gpa, null, false, &b);
  try testing.expectEqual(@as(usize, 0), b.v.items.len);
  try d.pieces.append(gpa, .{ .kind = .cone });
  try d.mesh(gpa, null, false, &b);
  try testing.expect(b.v.items.len > 0);
  try testing.expectEqual(@as(usize, 0), b.v.items.len % 3);
}
