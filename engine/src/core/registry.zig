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
//!
//! NOTE: every `pub const` in the namespace is treated as a module.
//! Don't put helper constants or types in the namespace; put them in
//! the modules themselves.
const std=@import("std");
/// a table indexed by an enum, one value per tag
const EnumArray=std.enums.EnumArray;
/// every tag of an enum, as an array
const values=std.enums.values;
/// an enum made from a namespace's declarations, one tag per one
const DeclEnum=std.meta.DeclEnum;
/// which tag a tagged union holds
const activeTag=std.meta.activeTag;
/// a namespace's declarations, listed
const declarations=std.meta.declarations;
/// the test helpers
const testing=std.testing;
/// a registry over the namespace `ns`, whose every `pub const` is one
/// module: its enum of ids, its tables and the unions and structs drawn
/// from the modules' declarations
pub fn Registry(comptime ns:type)type{
  return struct{
    /// one tag per module, named as the namespace names it
    pub const Id=DeclEnum(ns);
    /// how many modules there are
    pub const count=declarations(ns).len;
    /// every id, in declaration order
    pub const ids=values(Id);
    /// the module an id names, at compile time, to call its hooks
    pub fn module(comptime id:Id)type{return@field(ns,@tagName(id));}
    /// gather declaration `decl` (e.g. "def") from every module into an Id-indexed table.
    pub fn table(comptime T:type,comptime decl:[]const u8)EnumArray(Id,T){
      return comptime blk:{
        // the table being filled
        var t:EnumArray(Id,T)=undefined;
        for(ids)|id|t.set(id,@field(module(id),decl));
        break:blk t;
      };
    }
    /// each module's name and its `decl` type (void when it declares none).
    fn fields(comptime decl:[]const u8)struct{names:[count][]const u8,types:[count]type}{
      // each module's name, and the type of its `decl`
      var names:[count][]const u8=undefined;
      var types:[count]type=undefined;
      for(ids,0..)|id,i|{
        names[i]=@tagName(id);
        types[i]=if(@hasDecl(module(id),decl))@field(module(id),decl)else void;
      }
      return.{.names=names,.types=types};
    }
    /// a tagged union over Id whose payloads are each module's `decl` type
    /// (void when a module does not declare one).
    pub fn Union(comptime decl:[]const u8)type{
      // the modules' names and `decl` types
      const f=comptime fields(decl);
      return@Union(.auto,Id,&f.names,&f.types,&@splat(.{}));
    }
    /// a struct with one field per module, typed by that module's `decl`
    /// (void when absent): e.g. per-pass resources living side by side.
    pub fn Struct(comptime decl:[]const u8)type{
      // the modules' names and `decl` types
      const f=comptime fields(decl);
      return@Struct(.auto,null,&f.names,&f.types,&@splat(.{}));
    }
    /// does a module implement an optional hook?
    pub fn has(comptime id:Id,comptime decl:[]const u8)bool{return@hasDecl(module(id),decl);}
  };
}
test"registry derives enum, tables and unions"{
  // two modules: one with a `State`, one without
  const ns=struct{
    /// one module, with a `def` and a `State`
    pub const alpha=struct{pub const def:u32=1;pub const State=struct{n:u8=0};};
    /// another, with only a `def`
    pub const beta=struct{pub const def:u32=2;};
  };
  // the registry over them
  const R=Registry(ns);
  try testing.expectEqual(@as(usize,2),R.count);
  // their `def`s, gathered into a table
  const t=R.table(u32,"def");
  try testing.expectEqual(@as(u32,2),t.get(.beta));
  // their states as a union, and one holding alpha's
  const U=R.Union("State");
  const u:U=.{.alpha=.{.n=3}};
  try testing.expectEqual(R.Id.alpha,activeTag(u));
  try testing.expect(R.has(.alpha,"State")and!R.has(.beta,"State"));
  // their states side by side, beta's empty
  const S=R.Struct("State");
  const s:S=.{.alpha=.{.n=5},.beta={}};
  try testing.expectEqual(@as(u8,5),s.alpha.n);
}
