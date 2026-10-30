//! every structure in the garden: the list, its tile index, placing and uprooting.
const lib = @import("../../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const engine = lib.engine;
const m = engine.core.math;
const World = lib.world.World;
const Id = lib.structures.Id;
const Kind = lib.structures.Kind;
const Occ = lib.structures.Occ;
const Ref = lib.structures.Ref;
const Structure = lib.structures.structure.Structure;
const anyTile = lib.structures.structure.anyTile;
const defs = lib.structures.defs;
const freshState = lib.structures.structure.freshState;
const reg = lib.structures.reg;
const slotDown = lib.structures.structure.slotDown;

pub const Structures = struct {
  list:std.ArrayList(Structure) = .empty,
  /// a structure waiting to be paired with another (a sporecaster
  /// choosing where it sends): the next one configured
  pairing:?Ref = null,
  /// every structure by where it stands (`find`, `floaterAt`), kept on
  /// `place`/`remove`
  where:std.AutoHashMapUnmanaged(Ref, Id) = .empty,
  /// beside `list`: each structure's first child and next sibling, in list
  /// order (`getChildren`); never saved, `relink` rebuilds it
  kin:std.ArrayList(Kin) = .empty,

  pub const Kin = struct { first:?Id = null, next:?Id = null };

  pub fn deinit(ss:*Structures, gpa:Allocator) void {
    for (ss.list.items) |*s| s.deinit(gpa);
    ss.list.deinit(gpa);
    ss.where.deinit(gpa);
    ss.kin.deinit(gpa);
  }

  pub fn get(ss:*Structures, id:Id) *Structure { return &ss.list.items[id.idx()]; }

  pub fn canPlace(ss:*const Structures, w:*const World, wx:i32, wy:i32, k:Kind) bool {
    if (defs.get(k).floating) {
      // over any tile, whatever stands on it, but not over another
      _ = w.chunkOfTile(wx, wy) orelse return false;
      return ss.floaterAt(wx, wy) == null;
    }
    return switch (k) {
      inline else => |t| w.footprintFree(wx, wy, defs.get(t).size, if (comptime reg.has(t, "ground")) reg.module(t).ground else anyTile),
    };
  }

  pub fn place(ss:*Structures, gpa:Allocator, w:*World, wx:i32, wy:i32, k:Kind, dir:m.Dir, seed:f32) Allocator.Error!bool {
    if (!ss.canPlace(w, wx, wy, k)) return false;
    const idx = Id.of(ss.list.items.len);
    try ss.list.ensureUnusedCapacity(gpa, 1);
    try ss.kin.ensureUnusedCapacity(gpa, 1);
    try ss.where.ensureUnusedCapacity(gpa, 1);
    ss.list.appendAssumeCapacity(.{ .x = wx, .y = wy, .dir = dir, .seed = seed, .state = freshState(k) });
    ss.kin.appendAssumeCapacity(.{});
    ss.where.putAssumeCapacityNoClobber(ss.get(idx).ref(), idx);
    if (!defs.get(k).floating) w.setFootprint(wx, wy, defs.get(k).size, Occ.structure(idx));
    return true;
  }

  /// put a saved structure back as it was (inventory, state, whom it
  /// depends on), owning what its state holds; once all are back,
  /// `relink`. Returns whether it fit (if not, `s` is still the caller's).
  pub fn restore(ss:*Structures, gpa:Allocator, w:*World, s:Structure) Allocator.Error!bool {
    if (!try ss.place(gpa, w, s.x, s.y, s.kind(), s.dir, s.seed)) return false;
    const put = &ss.list.items[ss.list.items.len - 1];
    put.deinit(gpa);
    put.* = s;
    return true;
  }

  /// rebuild who is whose child from each structure's `parent`
  pub fn relink(ss:*Structures) void {
    @memset(ss.kin.items, .{});
    for (0..ss.list.items.len) |i| if (ss.getParent(Id.of(i))) |p| ss.join(Id.of(i), p);
  }

  /// a structure the gardener has just put down starts as a sprout.
  pub fn sprout(ss:*Structures, id:Id) void {
    const s = ss.get(id);
    if (s.def().grow > 0) s.grown = 0;
  }

  /// what stands at a tile: what floats over it first (it is drawn over
  /// whatever is under it), else what stands on it.
  pub fn at(ss:*const Structures, w:*const World, wx:i32, wy:i32) ?Id {
    return ss.floaterAt(wx, wy) orelse w.occAt(wx, wy).asStructure();
  }

  /// what the gardener reaches at a tile: the structure standing there, else
  /// the one floating over it
  pub fn touched(ss:*const Structures, w:*const World, wx:i32, wy:i32) ?Id {
    return ss.at(w, wx, wy) orelse ss.floaterAt(wx, wy);
  }

  /// the floating structure over a tile
  pub fn floaterAt(ss:*const Structures, wx:i32, wy:i32) ?Id {
    return ss.where.get(.{ .x = wx, .y = wy, .floating = true });
  }

  /// ordered remove: the others keep the order they were put down in (the
  /// order they tick in), each after it one slot down. Returns the removed
  /// structure so its contents can be refunded; the caller `deinit`s it.
  /// note to CLAUDE, I changed the code, it is bad to do repeated get calls.
  pub fn remove(ss:*Structures, w:*World, id:Id) Structure {
    const s = ss.get(id).*;
    // calls should always be at the top;
    const stct = s.def();
    const idx = id.idx();
    // it leaves its parent, and what depended on it is cut loose
    ss.setParent(id, null);
    var c = ss.kin.items[idx].first;
    while (c) |k| {
      c = ss.kin.items[k.idx()].next;
      ss.kin.items[k.idx()].next = null;
      ss.get(k).parent = null;
    }
    ss.kin.items[idx].first = null;
    if (!stct.floating) w.setFootprint(s.x, s.y, stct.size, .none);
    _ = ss.where.remove(s.ref());
    _ = ss.list.orderedRemove(idx);
    _ = ss.kin.orderedRemove(idx);
    // each after it is one slot down: its tiles, where it is found, and the
    // child lists naming it (still in list order, as all move alike)
    for (ss.list.items[idx..], idx..) |*l, k| {
      const lstct = l.def();
      if (!lstct.floating) w.moveFootprint(l.x, l.y, lstct.size, Occ.structure(Id.of(k)));
      ss.where.getPtr(l.ref()).?.* = Id.of(k);
    }
    for (ss.kin.items) |*e| {
      e.first = slotDown(e.first, idx);
      e.next = slotDown(e.next, idx);
    }
    // what was paired with it is cut loose
    const gone = s.ref();
    for (ss.list.items) |*o| _ = o.dropPartner(gone);
    if (ss.pairing) |p| if (p.eql(gone)) { ss.pairing = null; };
    return s;
  }

  pub const pairWith = lib.structures.partners.pairWith;
  pub const letGo = lib.structures.partners.letGo;
  pub const unpair = lib.structures.partners.unpair;
  pub const pairStep = lib.structures.partners.pairStep;
  pub const getPartner = lib.structures.partners.getPartner;
  pub const getPartners = lib.structures.partners.getPartners;
  pub const pairedTo = lib.structures.partners.pairedTo;
  pub const Partners = lib.structures.partners.Partners;
  pub const Paired = lib.structures.partners.Paired;
  pub const find = lib.structures.kin.find;
  pub const setParent = lib.structures.kin.setParent;
  pub const join = lib.structures.kin.join;
  pub const leave = lib.structures.kin.leave;
  pub const spawnChild = lib.structures.kin.spawnChild;
  pub const dependOn = lib.structures.kin.dependOn;
  pub const detach = lib.structures.kin.detach;
  pub const getParent = lib.structures.kin.getParent;
  pub const getChildren = lib.structures.kin.getChildren;
  pub const getChild = lib.structures.kin.getChild;
  pub const childCount = lib.structures.kin.childCount;
  pub const Children = lib.structures.kin.Children;
  pub const wants = lib.structures.dispatch.wants;
  pub const output = lib.structures.dispatch.output;
  pub const handIn = lib.structures.dispatch.handIn;
  pub const send = lib.structures.dispatch.send;
  pub const outputs = lib.structures.dispatch.outputs;
  pub const Outputs = lib.structures.dispatch.Outputs;
  pub const gives = lib.structures.dispatch.gives;
  pub const insert = lib.structures.dispatch.insert;
  pub const meetings = lib.structures.dispatch.meetings;
  pub const link = lib.structures.dispatch.link;
  pub const linkWith = lib.structures.dispatch.linkWith;
  pub const tick = lib.structures.dispatch.tick;
  pub const tickWith = lib.structures.dispatch.tickWith;
};
