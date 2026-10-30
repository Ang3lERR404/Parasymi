//! parents and children: a child depends on its parent.
const lib = @import("../../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const World = lib.world.World;
const Id = lib.structures.Id;
const Ref = lib.structures.Ref;
const Spawn = lib.structures.Spawn;
const Structures = lib.structures.list.Structures;
const reg = lib.structures.reg;

// ---- parents and children: a child depends on its parent ----

/// the structure `r` names, if one still stands there
pub fn find(ss:*const Structures, r:Ref) ?Id { return ss.where.get(r); }

/// `child` now depends on `parent` (or on nothing), leaving whatever it
/// depended on before
pub fn setParent(ss:*Structures, child:Id, parent:?Id) void {
  if (ss.getParent(child)) |old| ss.leave(child, old);
  ss.get(child).parent = if (parent) |p| ss.get(p).ref() else null;
  if (parent) |p| ss.join(child, p);
}

/// put `c` among `p`'s children, in list order
pub fn join(ss:*Structures, c:Id, p:Id) void {
  const kin = ss.kin.items;
  var slot:*?Id = &kin[p.idx()].first;
  while (slot.*) |o| {
    if (o.idx() > c.idx()) break;
    slot = &kin[o.idx()].next;
  }
  kin[c.idx()].next = slot.*;
  slot.* = c;
}

/// take `c` out of `p`'s children
pub fn leave(ss:*Structures, c:Id, p:Id) void {
  const kin = ss.kin.items;
  var slot:*?Id = &kin[p.idx()].first;
  while (slot.*) |o| {
    if (o == c) {
      slot.* = kin[c.idx()].next;
      kin[c.idx()].next = null;
      return;
    }
    slot = &kin[o.idx()].next;
  }
}

/// put a structure down already depending on `parent` (its parent
/// chooses to: no `adopts` is asked). Returns it, or null if there is
/// no room.
pub fn spawnChild(ss:*Structures, gpa:Allocator, w:*World, parent:Id, sp:Spawn) Allocator.Error!?Id {
  const up = ss.get(parent).ref();
  if (!try ss.place(gpa, w, sp.x, sp.y, sp.kind, sp.dir, sp.seed)) return null;
  const id = Id.of(ss.list.items.len - 1);
  ss.get(id).parent = up;
  ss.join(id, parent);
  return id;
}

/// make `child` depend on `parent`, leaving whatever it depended on
/// before, if the parent takes it on (`adopts`) and it is not the
/// parent's own ancestor. Returns whether it depends on it now.
pub fn dependOn(ss:*Structures, child:Id, parent:Id) bool {
  if (child == parent) return false;
  if (ss.getParent(child) == parent) return true;
  // no loops: the child may not be among the parent's ancestors
  var up = ss.getParent(parent);
  while (up) |a| {
    if (a == child) return false;
    up = ss.getParent(a);
  }
  const p = ss.get(parent);
  const have = ss.childCount(parent);
  const k = ss.get(child).kind();
  const ok = switch (p.kind()) {
    inline else => |t| if (comptime reg.has(t, "adopts")) reg.module(t).adopts(p, k, have) else false,
  };
  if (ok) ss.setParent(child, parent);
  return ok;
}

/// cut `child` loose from its parent.
pub fn detach(ss:*Structures, child:Id) void { ss.setParent(child, null); }

pub fn getParent(ss:*const Structures, child:Id) ?Id {
  const r = ss.list.items[child.idx()].parent orelse return null;
  return ss.find(r);
}

/// every structure depending on `parent`, in list order.
pub fn getChildren(ss:*const Structures, parent:Id) Children {
  return .{ .ss = ss, .at = ss.kin.items[parent.idx()].first };
}

/// the `n`th of `parent`'s children (in list order).
pub fn getChild(ss:*const Structures, parent:Id, n:usize) ?Id {
  var it = ss.getChildren(parent);
  var k:usize = 0;
  while (it.next()) |c| : (k += 1) if (k == n) return c;
  return null;
}

pub fn childCount(ss:*const Structures, parent:Id) u32 {
  var it = ss.getChildren(parent);
  var n:u32 = 0;
  while (it.next()) |_| n += 1;
  return n;
}

/// walks a structure's children (`kin`)
pub const Children = struct {
  ss:*const Structures,
  at:?Id,

  pub fn next(it:*Children) ?Id {
    const c = it.at orelse return null;
    it.at = it.ss.kin.items[c.idx()].next;
    return c;
  }
};
