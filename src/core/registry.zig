//! enum-keyed registries of modules.
//!
//! A domain (species, structures, meshes, ...) lists its parts in a namespace,
//! one line per part:
//!
//!   const parts = struct {
//!     pub const conduit = @import("structures/conduit.zig");
//!     pub const sap_cache = @import("structures/sap_cache.zig");
//!   };
//!   const reg = Registry(parts);
//!
//! The enum is derived from that namespace (so it can never drift out of
//! sync), data tables are gathered from each module, and behaviour is
//! dispatched with a comptime switch:
//!
//!   switch (id) { inline else => |k| reg.module(k).tick(...) }
const std = @import("std");
const EnumArray = std.enums.EnumArray;
const values = std.enums.values;
const DeclEnum = std.meta.DeclEnum;
const activeTag = std.meta.activeTag;
const declarations = std.meta.declarations;
const testing = std.testing;

pub fn Registry(comptime ns:type) type {
  return struct {
    pub const Id = DeclEnum(ns);
    pub const count = declarations(ns).len;
    pub const ids = values(Id);

    pub fn module(comptime id:Id) type { return @field(ns, @tagName(id)); }

    /// gather declaration `decl` (e.g. "def") from every module into an Id-indexed table.
    pub fn table(comptime T:type, comptime decl:[]const u8) EnumArray(Id, T) {
      return comptime blk: {
        var t:EnumArray(Id, T) = undefined;
        for (ids) |id| t.set(id, @field(module(id), decl));
        break :blk t;
      };
    }

    /// a tagged union over Id whose payloads are each module's `decl` type
    /// (void when a module does not declare one).
    pub fn Union(comptime decl:[]const u8) type {
      return comptime blk: {
        var names:[count][]const u8 = undefined;
        var types:[count]type = undefined;
        for (ids, 0..) |id, i| {
          names[i] = @tagName(id);
          types[i] = if (@hasDecl(module(id), decl)) @field(module(id), decl) else void;
        }
        break :blk @Union(.auto, Id, &names, &types, &@splat(.{}));
      };
    }

    /// a struct with one field per module, typed by that module's `decl`
    /// (void when absent): e.g. per-pass resources living side by side.
    pub fn Struct(comptime decl:[]const u8) type {
      return comptime blk: {
        var names:[count][]const u8 = undefined;
        var types:[count]type = undefined;
        for (ids, 0..) |id, i| {
          names[i] = @tagName(id);
          types[i] = if (@hasDecl(module(id), decl)) @field(module(id), decl) else void;
        }
        break :blk @Struct(.auto, null, &names, &types, &@splat(.{}));
      };
    }

    /// does a module implement an optional hook?
    pub fn has(comptime id:Id, comptime decl:[]const u8) bool { return @hasDecl(module(id), decl); }
  };
}

test "registry derives enum, tables and unions" {
  const ns = struct {
    pub const alpha = struct { pub const def:u32 = 1; pub const State = struct { n:u8 = 0 }; };
    pub const beta = struct { pub const def:u32 = 2; };
  };
  const R = Registry(ns);
  try testing.expectEqual(@as(usize, 2), R.count);
  const t = R.table(u32, "def");
  try testing.expectEqual(@as(u32, 2), t.get(.beta));
  const U = R.Union("State");
  const u:U = .{.alpha = .{.n = 3}};
  try testing.expectEqual(R.Id.alpha, activeTag(u));
  try testing.expect(R.has(.alpha, "State") and !R.has(.beta, "State"));
}
