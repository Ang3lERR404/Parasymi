//! a value as a record of named fields (structures in saves): each field is
//! written with its name's hash and its length, so a record read back into
//! a type that has since gained, lost or changed a field keeps what still
//! matches and the defaults for the rest. Stores numbers, bools, enums (by
//! tag name), optionals, arrays, vectors, structs, tagged unions (by tag
//! name) and `ArrayList`s; anything else (a pointer) is refused at compile
//! time.
//!
//! A value's bytes: a number or packed struct raw; an enum its tag name's
//! hash (u32; a non-exhaustive one its integer); an optional a 0/1 byte and
//! the value; an array, vector or list its count (u32) and each element
//! framed; a struct its field count (u16) and per field its name's hash
//! (u32) and the field framed; a union its tag name's hash and the payload
//! framed. Framed: its length (u32), then its bytes.
const lib = @import("../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const asBytes = std.mem.asBytes;
const activeTag = std.meta.activeTag;
const Fnv = std.hash.Fnv1a_32;
const testing = std.testing;

pub const Error = error{CorruptSave} || Allocator.Error;

/// what a name (a field's, a tag's) is stored as
pub fn nameHash(name:[]const u8) u32 { return Fnv.hash(name); }

fn isList(comptime T:type) bool {
  return @typeInfo(T) == .@"struct" and @hasField(T, "items") and @hasField(T, "capacity") and @hasDecl(T, "Slice");
}
fn ListItem(comptime T:type) type { return @typeInfo(@FieldType(T, "items")).pointer.child; }

/// a fresh `T`: its fields' defaults, else zero, false, null or the first tag
pub fn fresh(comptime T:type) T {
  if (comptime isList(T)) return .empty;
  return switch (@typeInfo(T)) {
    .void => {},
    .bool => false,
    .int, .float => 0,
    .@"enum" => |e| if (e.fields.len > 0) @enumFromInt(e.fields[0].value) else @enumFromInt(0),
    .optional => null,
    .array => |a| @splat(fresh(a.child)),
    .vector => |v| @splat(fresh(v.child)),
    .@"struct" => |s| blk: {
      var v:T = undefined;
      inline for (s.fields) |f| {
        if (f.is_comptime) continue;
        @field(v, f.name) = f.defaultValue() orelse fresh(f.type);
      }
      break :blk v;
    },
    .@"union" => |u| @unionInit(T, u.fields[0].name, fresh(u.fields[0].type)),
    else => @compileError("record: cannot store " ++ @typeName(T)),
  };
}

fn put(gpa:Allocator, out:*ArrayList(u8), comptime T:type, v:T) Allocator.Error!void {
  try out.appendSlice(gpa, asBytes(&v));
}

/// `v`, framed (its length, then its bytes), onto `out`
pub fn writeFramed(comptime T:type, gpa:Allocator, out:*ArrayList(u8), v:*const T) Allocator.Error!void {
  const at = out.items.len;
  try put(gpa, out, u32, 0);
  try write(T, gpa, out, v);
  const n:u32 = @intCast(out.items.len - at - 4);
  @memcpy(out.items[at..][0..4], asBytes(&n));
}

/// `v`'s bytes onto `out`
pub fn write(comptime T:type, gpa:Allocator, out:*ArrayList(u8), v:*const T) Allocator.Error!void {
  if (comptime isList(T)) {
    try put(gpa, out, u32, @intCast(v.items.len));
    for (v.items) |*e| try writeFramed(ListItem(T), gpa, out, e);
    return;
  }
  switch (@typeInfo(T)) {
    .void => {},
    .bool, .int, .float => try out.appendSlice(gpa, asBytes(v)),
    .@"enum" => |e| if (e.is_exhaustive) {
      try put(gpa, out, u32, nameHash(@tagName(v.*)));
    } else try put(gpa, out, e.tag_type, @intFromEnum(v.*)),
    .optional => |o| if (v.*) |*c| {
      try put(gpa, out, u8, 1);
      try write(o.child, gpa, out, c);
    } else try put(gpa, out, u8, 0),
    .array => |a| {
      try put(gpa, out, u32, a.len);
      for (v) |*e| try writeFramed(a.child, gpa, out, e);
    },
    .vector => |vi| {
      const arr:[vi.len]vi.child = v.*;
      try write([vi.len]vi.child, gpa, out, &arr);
    },
    .@"struct" => |s| if (s.layout == .@"packed") try out.appendSlice(gpa, asBytes(v)) else {
      comptime uniqueNames(T);
      var n:u16 = 0;
      inline for (s.fields) |f| {
        if (!f.is_comptime) n += 1;
      }
      try put(gpa, out, u16, n);
      inline for (s.fields) |f| {
        if (f.is_comptime) continue;
        try put(gpa, out, u32, comptime nameHash(f.name));
        try writeFramed(f.type, gpa, out, &@field(v.*, f.name));
      }
    },
    .@"union" => |u| {
      if (u.tag_type == null) @compileError("record: an untagged union cannot be stored: " ++ @typeName(T));
      comptime uniqueNames(T);
      switch (v.*) {
        inline else => |*p, tag| {
          try put(gpa, out, u32, comptime nameHash(@tagName(tag)));
          try writeFramed(@TypeOf(p.*), gpa, out, p);
        },
      }
    },
    else => @compileError("record: cannot store " ++ @typeName(T)),
  }
}

fn uniqueNames(comptime T:type) void {
  @setEvalBranchQuota(200_000);
  const fs = switch (@typeInfo(T)) {
    inline .@"struct", .@"union" => |i| i.fields,
    else => unreachable,
  };
  for (fs, 0..) |a, i| for (fs[0..i]) |b| {
    if (nameHash(a.name) == nameHash(b.name)) @compileError("record: " ++ a.name ++ " and " ++ b.name ++ " hash alike in " ++ @typeName(T));
  };
}

/// reading bytes in turn
pub const In = struct {
  b:[]const u8,
  pos:usize = 0,

  pub fn int(r:*In, comptime T:type) Error!T {
    if (@sizeOf(T) > r.b.len - r.pos) return error.CorruptSave;
    var v:T = undefined;
    @memcpy(asBytes(&v), r.b[r.pos..][0..@sizeOf(T)]);
    r.pos += @sizeOf(T);
    return v;
  }

  /// the next framed bytes
  pub fn frame(r:*In) Error![]const u8 {
    const n = try r.int(u32);
    if (n > r.b.len - r.pos) return error.CorruptSave;
    defer r.pos += n;
    return r.b[r.pos..][0..n];
  }
};

/// read `b` (one value's bytes) over `out`: what it holds that `T` still
/// has is set, the rest of `out` is left as it was
pub fn read(comptime T:type, gpa:Allocator, b:[]const u8, out:*T) Error!void {
  var r:In = .{ .b = b };
  if (comptime isList(T)) {
    const n = try r.int(u32);
    // each element takes at least its length
    if (n > (b.len - r.pos) / 4) return error.CorruptSave;
    out.clearRetainingCapacity();
    try out.ensureTotalCapacity(gpa, n);
    for (0..n) |_| {
      var e = fresh(ListItem(T));
      try read(ListItem(T), gpa, try r.frame(), &e);
      out.appendAssumeCapacity(e);
    }
    return;
  }
  switch (@typeInfo(T)) {
    .void => {},
    .bool => if (b.len == 1) {
      out.* = b[0] != 0;
    },
    .int, .float => if (b.len == @sizeOf(T)) @memcpy(asBytes(out), b),
    .@"enum" => |e| if (e.is_exhaustive) {
      if (b.len != 4) return;
      const h = try r.int(u32);
      inline for (e.fields) |f| if ((comptime nameHash(f.name)) == h) {
        out.* = @enumFromInt(f.value);
      };
    } else if (b.len == @sizeOf(e.tag_type)) {
      out.* = @enumFromInt(try r.int(e.tag_type));
    },
    .optional => |o| {
      if (b.len == 0) return;
      if (b[0] == 0) {
        out.* = null;
        return;
      }
      var c = out.* orelse fresh(o.child);
      try read(o.child, gpa, b[1..], &c);
      out.* = c;
    },
    .array => |a| {
      const n = try r.int(u32);
      for (0..n) |i| {
        const e = try r.frame();
        if (i < a.len) try read(a.child, gpa, e, &out[i]);
      }
    },
    .vector => |vi| {
      var arr:[vi.len]vi.child = out.*;
      try read([vi.len]vi.child, gpa, b, &arr);
      out.* = arr;
    },
    .@"struct" => |s| if (s.layout == .@"packed") {
      if (b.len == @sizeOf(T)) @memcpy(asBytes(out), b);
    } else {
      const n = try r.int(u16);
      for (0..n) |_| {
        const h = try r.int(u32);
        const e = try r.frame();
        inline for (s.fields) |f| {
          if (f.is_comptime) continue;
          if ((comptime nameHash(f.name)) == h) try read(f.type, gpa, e, &@field(out.*, f.name));
        }
      }
    },
    .@"union" => |u| {
      const h = try r.int(u32);
      const e = try r.frame();
      inline for (u.fields) |f| if ((comptime nameHash(f.name)) == h) {
        if (@field(u.tag_type.?, f.name) != activeTag(out.*)) out.* = @unionInit(T, f.name, fresh(f.type));
        try read(f.type, gpa, e, &@field(out.*, f.name));
      };
    },
    else => @compileError("record: cannot store " ++ @typeName(T)),
  }
}

/// `v` written and read back into `T` over `start`
fn again(comptime V:type, comptime T:type, v:V, start:T) !T {
  var buf:ArrayList(u8) = .empty;
  defer buf.deinit(testing.allocator);
  try write(V, testing.allocator, &buf, &v);
  var out = start;
  try read(T, testing.allocator, buf.items, &out);
  return out;
}

test "a record keeps what still matches and the defaults for the rest" {
  const Kind = enum { moss, soil, sand };
  const Old = struct { a:u32 = 1, b:f32 = 2, k:Kind = .sand, gone:u8 = 9, opt:?u16 = null, arr:[3]u8 = .{ 1, 2, 3 } };
  // `a` became a u8 (kept at its default), `gone` went, `c` came, the
  // array shrank, the enum's tags moved
  const Kind2 = enum { sand, moss };
  const New = struct { c:u16 = 7, b:f32 = 0, a:u8 = 5, k:Kind2 = .moss, opt:?u16 = 3, arr:[2]u8 = .{ 0, 0 } };
  const got = try again(Old, New, .{ .a = 40, .b = 2.5, .k = .sand, .opt = null }, .{});
  try testing.expectEqual(New{ .c = 7, .b = 2.5, .a = 5, .k = .sand, .opt = null, .arr = .{ 1, 2 } }, got);
}

test "unions by tag name, lists grown back, nested records" {
  const gpa = testing.allocator;
  const Inner = struct { n:u16 = 0, v:@Vector(3, f32) = @splat(0) };
  const U = union(enum) { none, one:Inner, many:ArrayList(Inner) };
  var list:ArrayList(Inner) = .empty;
  defer list.deinit(gpa);
  try list.append(gpa, .{ .n = 4, .v = .{ 1, 2, 3 } });
  try list.append(gpa, .{ .n = 5 });
  var got = try again(U, U, .{ .many = list }, .none);
  defer got.many.deinit(gpa);
  try testing.expectEqual(@as(usize, 2), got.many.items.len);
  try testing.expectEqual(@as(u16, 5), got.many.items[1].n);
  try testing.expectEqual(@as(f32, 3), got.many.items[0].v[2]);
  // a tag it no longer has: left as it was
  const V = union(enum) { none, other:u8 };
  try testing.expectEqual(V.none, try again(U, V, .{ .one = .{} }, .none));
}

test "a cut-short record is corrupt, never misread" {
  const S = struct { a:u32 = 0, l:ArrayList(u32) = .empty };
  var buf:ArrayList(u8) = .empty;
  defer buf.deinit(testing.allocator);
  var l:ArrayList(u32) = .empty;
  defer l.deinit(testing.allocator);
  try l.appendSlice(testing.allocator, &.{ 1, 2, 3 });
  try write(S, testing.allocator, &buf, &.{ .a = 1, .l = l });
  for (0..buf.items.len) |n| {
    var out:S = .{};
    defer out.l.deinit(testing.allocator);
    read(S, testing.allocator, buf.items[0..n], &out) catch |e| {
      try testing.expectEqual(error.CorruptSave, e);
      continue;
    };
  }
}
