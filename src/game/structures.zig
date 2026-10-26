//! grown structures: the first steps from hand work toward automation.
//!
//! Each kind is its own module under `structures/` declaring:
//!   def:Def                     name, bulb item, footprint, mesh   (required)
//!   State                       per-kind data (optional, see `State` union)
//!   tick(ctx, id, dt) [!]bool   advance; returns whether it is active
//!                               (`Ctx`: the garden, and in the game the
//!                               wolf, the sky and this tick's events)
//!   link(ctx, id)               notice its neighbours, every tick, grown or not
//!   wants(s, g, item) u32       how many of `item` it will still take in
//!   output(s) ?Item             what may leave it first (pulled by conduits)
//!   gives(s, item) bool         whether `item` may leave it (default: it is
//!                               its `output`); a braided conduit's lanes
//!                               pull a different item each. `outputs` walks
//!                               all that may leave (`handOff` offers each)
//!   receive(s, g, item, edge) bool  a carrier taking an item handed in at
//!                               `edge` (counted from the way it faces)
//!   release(s) ?Item            hand back anything it holds outside `inv`
//!   configure(ss, id, g)        the player's "C" interaction (it may reach
//!                               another structure: `Structures.pairing`)
//!   recipes() []const u8        what its panel offers to weave (indices into
//!                               `craft.hand`); `chosen(s)` is the one it
//!                               weaves, `choose(s, g, r)` sets it
//!   emit(s, out, ctr, tf)       extra visuals beyond its mesh (placed as it is:
//!                               `place(s, ctr)`)
//!   describe(s, d, g, x, y)     one line of hover text
//!   ground(kind) bool           which tiles it may stand on (default: any tile)
//!   field(s) ?Field             a field of celestial energy it holds
//!   hold(s, x, y) ?Hold         how it draws the floater at a tile toward itself
//!   size(s) f32                 how much larger than its mesh it has grown
//!                               (by research), its growing in aside
//!   icon(ic, col)               its bulb in the HUD: the seed (`ic.coat`) and a
//!                               sprout or two showing what it does (`icon.zig`)
//!   meets:Meeting               the other lineage's structure that, grown
//!                               beside it, is a discovery (`Structures.meetings`)
//!   adopts(s, kind, have) bool  whether it takes on one more child of `kind`
//!                               beyond the `have` it has (`dependOn`;
//!                               default: none). A child depends on its
//!                               parent: `getParent`, `getChildren`,
//!                               `getChild`; `spawnChild` puts one down
//!                               already its child (no `adopts` asked)
//!   pairs:Pairs                 how it pairs with partners (`.most` at once),
//!                               one way (it sends there) or both ways
//!                               (`pairWith`, `pairStep`, `getPartner`,
//!                               `getPartners`, `pairedTo`, `unpair`;
//!                               default: never)
//!   meshes                      the library meshes it draws beyond `mesh` and
//!                               `preview` (a tuple: `.{ .item_pod, ... }`);
//!                               `--structure` builds only these (tested)
//! Missing hooks fall back to doing nothing. A new structure is one new file
//! plus one line in `kinds`.
const lib = @import("../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const activeTag = std.meta.activeTag;
const testing = std.testing;
const engine = lib.engine;
const m = engine.core.math;
const registry = engine.core.registry;
const ck = lib.ck;
const World = lib.world.World;
const items = lib.items;
const species = lib.species;
const Plants = lib.plants.Plants;
const Field = lib.ecology.Field;
const Events = lib.ecology.Events;
const Player = lib.player.Player;
const Sky = lib.sky.Sky;
const meshlib = lib.meshlib;
const prog = lib.progression;
const Parts = lib.parts.Parts;
const Draw = engine.ui.draw.Draw;
const Color = engine.ui.draw.Color;
const icon_kit = lib.icon;
const turn = lib.turn;

const kinds = struct {
  pub const conduit = @import("structures/conduit.zig");
  pub const sap_cache = @import("structures/sap_cache.zig");
  pub const germinator = @import("structures/germinator.zig");
  pub const arsthraxia = @import("structures/arsthraxia.zig");
  pub const root_digger = @import("structures/root_digger.zig");
  pub const polyp = @import("structures/polyp.zig");
  pub const diamond = @import("structures/diamond.zig");
  pub const loomfern = @import("structures/loomfern.zig");
  pub const lithophage = @import("structures/lithophage.zig");
  pub const braided_conduit = @import("structures/braided_conduit.zig");
  pub const ganglion = @import("structures/ganglion.zig");
  pub const gathering_crown = @import("structures/gathering_crown.zig");
  pub const sporecaster = @import("structures/sporecaster.zig");
  pub const weftstone = @import("structures/weftstone.zig");
  pub const driftbraid = @import("structures/driftbraid.zig");
  pub const monfris = @import("structures/monfris.zig");
  pub const vultrixi = @import("structures/vultrixi.zig");
};
const reg = registry.Registry(kinds);
const Occ = ck.Occ;
const PlantId = ck.PlantId;

pub const Kind = reg.Id;
/// a placed structure's slot in `Structures.list`.
pub const Id = ck.StructId;

pub const Def = struct {
  item:items.Item,
  size:u8,
  mesh:meshlib.Id,
  /// how see-through its sap (resin pods, sap beads) is at its thinnest;
  /// like the wolf's, it has no light of its own
  sap:f32 = SAP,
  /// grown structures that stand up move like plants: how far they bend in
  /// the wind (0 rigid) and over what height
  sway:f32 = 0,
  tall:f32 = 1,
  /// seconds it takes to grow from a sprout once the gardener puts it down
  /// (0: there at once); it does no work until grown. Its mesh is built
  /// along growth splines (gfx/growth.zig) and grows along them on the
  /// GPU, branch after branch (`PartInstance` `grown`)
  grow:f32 = 0,
  /// carries items tile to tile the way it faces (R turns it): carriers
  /// chain into one line, and producers leave them to pull through `output`
  carrier:bool = false,
  /// keeps items in its slots: a click on it opens its panel, where they
  /// are lifted and put down as in the belly (hud/structure.zig)
  store:bool = false,
  /// floats over its tile, `hover` over the ground, instead of standing on
  /// it: it takes no room there, so it may float over a structure or a
  /// plant (never over another floating one)
  floating:bool = false,
  hover:f32 = 0,
  /// its mesh is drawn by its own `emit` (a diamond: it forms on the GPU),
  /// not breathing and growing in as the others do; `mesh` is its preview
  bare:bool = false,
  /// does not breathe: what it emits hangs on its mesh and must stay put
  /// on it (a germinator's cups and core)
  still:bool = false,
  /// what the gardener sees before putting it down, if not `mesh` (a
  /// germinator's emitted pieces at rest with it)
  preview:?meshlib.Id = null,
  /// what it emits travels far from it (a sporecaster's spores): it is
  /// emitted however far it stands from the view
  far:bool = false,
  /// a parasite's: the roots it turns on (R) are pale, not bark
  pale:bool = false,
};

pub const defs = reg.table(Def, "def");

/// a structure of the other lineage that, both grown within `MEET` tiles of
/// each other, is witnessed as `found`
pub const Meeting = struct { kind:Kind, found:prog.Discovery };
/// tiles apart (between footprints) that still count as side by side
pub const MEET = 3;
/// per-kind state; the active tag is the structure's kind.
pub const State = reg.Union("State");

/// every library mesh kind `k` draws: its mesh, its preview and what it
/// emits (its `meshes`)
pub fn meshes(k:Kind) []const meshlib.Id {
  return switch (k) {
    inline else => |t| comptime blk: {
      const d:Def = reg.module(t).def;
      const extra = if (reg.has(t, "meshes")) reg.module(t).meshes else .{};
      const own:usize = if (d.preview != null) 2 else 1;
      var out:[own + extra.len]meshlib.Id = undefined;
      out[0] = d.mesh;
      if (d.preview) |p| out[1] = p;
      for (extra, own..) |e, i| out[i] = e;
      const all = out;
      break :blk &all;
    },
  };
}

pub fn kindOf(item:items.Item) ?Kind {
  inline for (reg.ids) |k| if (defs.get(k).item == item) return k;
  return null;
}

pub const SLOTS = 16;
/// how quickly a structure's activity glow eases toward its target
const ACTIVITY_EASE:f32 = 3;
/// how see-through structures' sap is at its thinnest, unless a def says otherwise
pub const SAP:f32 = 0.78;

/// a structure as another holds on to it: by tile (an `Id` shifts when
/// another is uprooted) and whether it floats (a floater and what it
/// floats over share a tile)
pub const Ref = struct {
  x:i32,
  y:i32,
  floating:bool,

  pub fn eql(a:Ref, b:Ref) bool { return a.x == b.x and a.y == b.y and a.floating == b.floating; }
  pub fn tile(r:Ref) [2]i32 { return .{r.x, r.y}; }
};

/// what `spawnChild` puts down
pub const Spawn = struct { x:i32, y:i32, kind:Kind, dir:m.Dir = 0, seed:f32 = 0 };

/// how a kind pairs (its `pairs`): with a structure of kind `with` (its
/// own if null), one way (its partner is where it sends) or both ways
/// (each is the other's), with up to `most` partners at once: paired with
/// one more, it lets go of its oldest (both ways, that one lets go of it)
pub const Pairs = struct { way:Way = .one_way, with:?Kind = null, most:u8 = 1 };
/// the most partners any structure keeps
pub const PARTNERS = 4;
pub const Way = enum { one_way, both_ways };

fn pairsOf(k:Kind) ?Pairs {
  return switch (k) {
    inline else => |t| if (comptime reg.has(t, "pairs")) blk: {
      const p:Pairs = reg.module(t).pairs;
      if (comptime p.most < 1 or p.most > PARTNERS) @compileError(@tagName(t) ++ ": pairs.most must be 1..PARTNERS");
      break :blk p;
    } else null,
  };
}

/// where configuring a structure that pairs leaves it (`pairStep`)
pub const PairStep = enum {
  /// it waits for the next one configured
  waiting,
  /// configured twice over: it is cut loose
  cut,
  /// the one waiting is paired with it
  paired,
};

pub const Structure = struct {
  x:i32,
  y:i32,
  dir:m.Dir = 0,
  seed:f32,
  inv:items.Inventory(SLOTS) = .{},
  state:State,
  /// the structure it depends on (`dependOn`, `spawnChild`), if any
  parent:?Ref = null,
  /// the structures it is paired with (`pairWith`), oldest first, the
  /// empty slots last
  partners:[PARTNERS]?Ref = @splat(null),
  /// smoothed 0..1, drives glow and motion
  activity:f32 = 0,
  /// 0 a sprout .. 1 grown (see `Def.grow`)
  grown:f32 = 1,
  /// how it got to face `dir` (R turns it)
  turn:turn.Turn = .{},

  pub fn kind(s:*const Structure) Kind { return activeTag(s.state); }
  /// how big it is drawn: the size research has grown it to (`size`);
  /// growing in is its growth splines' alone
  pub fn grownScale(s:*const Structure) m.V3 { return m.splat3(s.size()); }
  pub fn size(s:*const Structure) f32 {
    return switch (s.kind()) {
      inline else => |k| if (comptime reg.has(k, "size")) reg.module(k).size(s) else 1,
    };
  }
  pub fn def(s:*const Structure) Def { return defs.get(s.kind()); }
  pub fn ref(s:*const Structure) Ref { return .{ .x = s.x, .y = s.y, .floating = s.def().floating }; }
  /// the first it was paired with, if any
  pub fn partner(s:*const Structure) ?Ref { return s.partners[0]; }
  pub fn partnerCount(s:*const Structure) usize {
    for (s.partners, 0..) |p, k| if (p == null) return k;
    return PARTNERS;
  }
  pub fn pairedWith(s:*const Structure, r:Ref) bool {
    for (s.partners) |p| if (p) |q| if (q.eql(r)) return true;
    return false;
  }
  /// pair it with `r` (once), letting go of the oldest when it already has
  /// `most`; returns the one let go
  fn addPartner(s:*Structure, r:Ref, most:u8) ?Ref {
    if (s.pairedWith(r)) return null;
    var old:?Ref = null;
    if (s.partnerCount() >= most) {
      old = s.partners[0];
      _ = s.dropPartner(old.?);
    }
    s.partners[s.partnerCount()] = r;
    return old;
  }
  /// cut it from `r`, the later ones moving up; returns whether they were paired
  fn dropPartner(s:*Structure, r:Ref) bool {
    const n = s.partnerCount();
    for (0..n) |k| if (s.partners[k].?.eql(r)) {
      std.mem.copyForwards(?Ref, s.partners[k .. n - 1], s.partners[k + 1 .. n]);
      s.partners[n - 1] = null;
      return true;
    };
    return false;
  }
  /// where its mesh is drawn from, at its centre `ctr`: turned its way,
  /// at the size it has grown to (breathing aside)
  pub fn place(s:*const Structure, ctr:m.V3) m.M4 {
    return m.chain(&.{m.translate(ctr), m.rotY(m.dirYaw(s.dir)), m.scale3(s.grownScale())});
  }
};

/// everything a structure's behaviour may touch.
pub const Ctx = struct {
  /// for a structure that puts another down (a polyp, its diamond)
  gpa:Allocator,
  w:*World,
  plants:*Plants,
  g:*prog.Progression,
  ss:*Structures,
  // decision: the world beyond the garden is read-only to structures and
  // left out by headless callers (tests), so each is optional
  /// the wolf, for a structure that answers it coming near
  player:?*const Player = null,
  /// the time of day (`daylight`, `tod`), for one that works by day or night
  sky:?*const Sky = null,
  /// what befell the garden this tick (plants withered)
  events:Events = .{},
};

fn freshState(k:Kind) State {
  return switch (k) {
    inline else => |t| blk: {
      const T = @FieldType(State, @tagName(t));
      break :blk @unionInit(State, @tagName(t), if (T == void) {} else .{});
    },
  };
}

fn anyTile(_:ck.Kind) bool { return true; }

/// empty tiles between two structures' footprints (0: touching)
fn gap(a:*const Structure, b:*const Structure) i32 {
  const sa:i32 = a.def().size;
  const sb:i32 = b.def().size;
  const dx = @max(b.x - (a.x + sa), a.x - (b.x + sb), -1);
  const dy = @max(b.y - (a.y + sa), a.y - (b.y + sb), -1);
  return @max(dx, dy, 0);
}

/// `o` once the slot at `gone` is taken out of the list
fn slotDown(o:?Id, gone:usize) ?Id {
  const i = o orelse return null;
  return if (i.idx() > gone) Id.of(i.idx() - 1) else i;
}

/// a hook result that may be an error union, as one
fn orFail(r:anytype) Allocator.Error!bool { return r; }

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
  /// depends on); once all are back, `relink`. Returns whether it fit.
  pub fn restore(ss:*Structures, gpa:Allocator, w:*World, s:Structure) Allocator.Error!bool {
    if (!try ss.place(gpa, w, s.x, s.y, s.kind(), s.dir, s.seed)) return false;
    ss.list.items[ss.list.items.len - 1] = s;
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
  /// structure so its contents can be refunded.
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

  // ---- partners: paired one way or both ways (`pairs`) ----

  /// pair `a` with `b` as `a`'s kind pairs (`pairs`): one way, `a` sends to
  /// `b`; both ways, each is the other's. One already holding its `most`
  /// lets go of its oldest. Returns whether they are paired now.
  pub fn pairWith(ss:*Structures, a:Id, b:Id) bool {
    if (a == b) return false;
    const ka = ss.get(a).kind();
    const pa = pairsOf(ka) orelse return false;
    const kb = ss.get(b).kind();
    if (kb != (pa.with orelse ka)) return false;
    const ra = ss.get(a).ref();
    const rb = ss.get(b).ref();
    const old = ss.get(a).addPartner(rb, pa.most);
    if (pa.way == .both_ways) {
      if (old) |o| ss.letGo(o, ra);
      const mb = if (pairsOf(kb)) |pb| pb.most else pa.most;
      if (ss.get(b).addPartner(ra, mb)) |o| ss.letGo(o, rb);
    }
    return true;
  }

  /// the structure at `r`, if one stands there, is cut from `from`
  fn letGo(ss:*Structures, r:Ref, from:Ref) void {
    if (ss.find(r)) |o| _ = ss.get(o).dropPartner(from);
  }

  /// cut `id` from its partners; paired both ways, every pairing that
  /// reaches it is cut too.
  pub fn unpair(ss:*Structures, id:Id) void {
    const s = ss.get(id);
    s.partners = @splat(null);
    const p = pairsOf(s.kind()) orelse return;
    if (p.way != .both_ways) return;
    const here = s.ref();
    for (ss.list.items) |*o| _ = o.dropPartner(here);
  }

  /// the configure handshake of a structure that pairs: the first
  /// configured waits, the next is paired with it (`pairWith`, from the
  /// one waiting); configured twice over, it is cut loose (`unpair`).
  pub fn pairStep(ss:*Structures, id:Id) PairStep {
    const here = ss.get(id).ref();
    if (ss.pairing) |p| {
      ss.pairing = null;
      if (p.eql(here)) {
        ss.unpair(id);
        return .cut;
      }
      if (ss.find(p)) |o| if (ss.pairWith(o, id)) return .paired;
    }
    ss.pairing = here;
    return .waiting;
  }

  /// the first `id` was paired with
  pub fn getPartner(ss:*const Structures, id:Id) ?Id {
    const r = ss.list.items[id.idx()].partner() orelse return null;
    return ss.find(r);
  }

  /// every structure `id` is paired with, oldest first.
  pub fn getPartners(ss:*const Structures, id:Id) Partners {
    return .{ .ss = ss, .of = &ss.list.items[id.idx()].partners };
  }

  /// every structure paired with `id` (one of its partners is `id`), in
  /// list order.
  pub fn pairedTo(ss:*const Structures, id:Id) Paired {
    return .{ .ss = ss, .of = ss.list.items[id.idx()].ref() };
  }

  // ---- parents and children: a child depends on its parent ----

  /// the structure `r` names, if one still stands there
  pub fn find(ss:*const Structures, r:Ref) ?Id { return ss.where.get(r); }

  /// `child` now depends on `parent` (or on nothing), leaving whatever it
  /// depended on before
  fn setParent(ss:*Structures, child:Id, parent:?Id) void {
    if (ss.getParent(child)) |old| ss.leave(child, old);
    ss.get(child).parent = if (parent) |p| ss.get(p).ref() else null;
    if (parent) |p| ss.join(child, p);
  }

  /// put `c` among `p`'s children, in list order
  fn join(ss:*Structures, c:Id, p:Id) void {
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
  fn leave(ss:*Structures, c:Id, p:Id) void {
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

  /// walks a structure's partners (`partners`)
  pub const Partners = struct {
    ss:*const Structures,
    of:*const [PARTNERS]?Ref,
    k:usize = 0,

    pub fn next(it:*Partners) ?Id {
      while (it.k < PARTNERS) {
        const r = it.of[it.k] orelse return null;
        it.k += 1;
        if (it.ss.find(r)) |id| return id;
      }
      return null;
    }
  };

  /// walks every structure one of whose partners is `of`
  pub const Paired = struct {
    ss:*const Structures,
    of:Ref,
    i:usize = 0,

    pub fn next(it:*Paired) ?Id {
      while (it.i < it.ss.list.items.len) {
        const i = it.i;
        it.i += 1;
        if (it.ss.list.items[i].pairedWith(it.of)) return Id.of(i);
      }
      return null;
    }
  };

  // ---- hook dispatch: one comptime switch each, no per-kind code here ----

  pub fn wants(ss:*Structures, g:*const prog.Progression, id:Id, item:items.Item) u32 {
    const s = ss.get(id);
    return switch (s.kind()) {
      inline else => |k| if (comptime reg.has(k, "wants")) reg.module(k).wants(s, g, item) else 0,
    };
  }

  pub fn output(ss:*Structures, id:Id) ?items.Item {
    const s = ss.get(id);
    return switch (s.kind()) {
      inline else => |k| if (comptime reg.has(k, "output")) reg.module(k).output(s) else null,
    };
  }

  /// hand one `item` to structure `id`, coming in at `edge` (counted from
  /// the way it faces): a carrier takes it into its core or a lane
  /// (`receive`), anything else as `insert` does. Returns whether it went.
  pub fn handIn(ss:*Structures, g:*const prog.Progression, id:Id, item:items.Item, edge:m.Dir) bool {
    const s = ss.get(id);
    return switch (s.kind()) {
      inline else => |k| if (comptime reg.has(k, "receive")) reg.module(k).receive(s, g, item, edge) else ss.insert(g, id, item, 1) == 1,
    };
  }

  /// everything that may leave structure `id`: its `output` first, then
  /// each other kind it holds that it `gives`, in slot order
  pub fn outputs(ss:*Structures, id:Id) Outputs {
    return .{ .ss = ss, .id = id, .first = ss.output(id) };
  }

  pub const Outputs = struct {
    ss:*Structures,
    id:Id,
    first:?items.Item,
    /// -1: `first` not yet given
    k:i32 = -1,

    pub fn next(it:*Outputs) ?items.Item {
      if (it.k < 0) {
        it.k = 0;
        if (it.first) |f| return f;
      }
      const slot = &it.ss.get(it.id).inv.slot;
      while (it.k < SLOTS) {
        const k:usize = @intCast(it.k);
        it.k += 1;
        const item = (slot[k] orelse continue).item;
        if (item == it.first) continue;
        // once per kind: the first slot holding it
        const again = for (slot[0..k]) |o| {
          if (o) |e| if (e.item == item) break true;
        } else false;
        if (!again and it.ss.gives(it.id, item)) return item;
      }
      return null;
    }
  };

  pub fn gives(ss:*Structures, id:Id, item:items.Item) bool {
    const s = ss.get(id);
    return switch (s.kind()) {
      inline else => |k| if (comptime reg.has(k, "gives")) reg.module(k).gives(s, item) else ss.output(id) == item,
    };
  }

  /// insert up to `n` of `item` (capped by what the structure still wants).
  /// Returns how many were actually inserted.
  pub fn insert(ss:*Structures, g:*const prog.Progression, id:Id, item:items.Item, n:u16) u16 {
    const k:u16 = @intCast(@min(n, ss.wants(g, id, item)));
    if (k == 0) return 0;
    return ss.get(id).inv.add(item, k);
  }

  /// witness every pair of grown structures that `meets` the other (once
  /// each: a discovery found is never looked for again)
  pub fn meetings(ss:*const Structures, g:*prog.Progression) void {
    for (ss.list.items) |*a| {
      if (a.grown < 1) continue;
      const mt:Meeting = switch (a.kind()) {
        inline else => |k| if (comptime reg.has(k, "meets")) reg.module(k).meets else continue,
      };
      if (g.found.contains(mt.found)) continue;
      for (ss.list.items) |*b| {
        if (b.kind() != mt.kind or b.grown < 1) continue;
        if (gap(a, b) <= MEET) {
          g.discover(mt.found);
          break;
        }
      }
    }
  }

  /// every structure notices its neighbours (`link`) without working
  /// (`--structure` holding one still)
  pub fn link(ss:*Structures, gpa:Allocator, w:*World, plants:*Plants, g:*prog.Progression) void {
    linkWith(.{ .gpa = gpa, .w = w, .plants = plants, .g = g, .ss = ss });
  }

  /// `link`, with the whole of `ctx` (the wolf, the sky) as the game has it
  pub fn linkWith(ctx:Ctx) void {
    const ss = ctx.ss;
    for (0..ss.list.items.len) |idx| switch (ss.get(Id.of(idx)).kind()) {
      inline else => |k| if (comptime reg.has(k, "link")) reg.module(k).link(ctx, Id.of(idx)),
    };
  }

  /// a tick with only the garden: no wolf, no sky, nothing befallen
  pub fn tick(ss:*Structures, gpa:Allocator, w:*World, plants:*Plants, g:*prog.Progression, dt:f32) Allocator.Error!void {
    return tickWith(.{ .gpa = gpa, .w = w, .plants = plants, .g = g, .ss = ss }, dt);
  }

  /// `tick`, with the whole of `ctx` (the wolf, the sky, this tick's
  /// events) as the game has it
  pub fn tickWith(ctx:Ctx, dt:f32) Allocator.Error!void {
    const ss = ctx.ss;
    for (0..ss.list.items.len) |idx| {
      const id = Id.of(idx);
      switch (ss.get(id).kind()) {
        inline else => |k| if (comptime reg.has(k, "link")) reg.module(k).link(ctx, id),
      }
      const g0 = ss.get(id);
      const active = if (g0.grown < 1) blk: {
        g0.grown = @min(1, g0.grown + dt / g0.def().grow);
        break :blk false;
      } else switch (g0.kind()) {
        // a tick that may put something down can fail for room
        inline else => |k| if (comptime reg.has(k, "tick")) try orFail(reg.module(k).tick(ctx, id, dt)) else false,
      };
      const s = ss.get(id);
      s.activity += ((if (active) @as(f32, 1) else 0) - s.activity) * @min(1, dt * ACTIVITY_EASE);
    }
  }
};

/// how far and how much `handOffWith` hands on
pub const HandOff = struct {
  /// steps out from its footprint (four ways) it reaches; 1 is the tiles
  /// beside it
  range:u8 = 1,
  /// at most how many it hands on, to one neighbour or several
  amount:u16 = 1,
};

/// hand one of what structure `i` lets go (`outputs`) to a neighbour beside
/// it that wants it; returns whether one went.
pub fn handOff(ctx:Ctx, i:Id) bool { return handOffWith(ctx, i, .{}) > 0; }

/// hand up to `h.amount` of what structure `i` lets go (`outputs`, asked
/// again for each neighbour) to those within `h.range` of its footprint
/// that want it, nearest first; returns how many went. Carriers are left
/// alone: one behind it pulls through `output` itself.
// decision: a footprint's every side hands on (a 2×2 monfris once handed
// only from its corner tile's neighbours)
pub fn handOffWith(ctx:Ctx, i:Id, h:HandOff) u16 {
  const self = ctx.ss.get(i);
  const n:i32 = self.def().size;
  var left = h.amount;
  for (1..@as(usize, h.range) + 1) |d| {
    var r:Ring = .{ .x0 = self.x, .y0 = self.y, .x1 = self.x + n - 1, .y1 = self.y + n - 1, .d = @intCast(d) };
    while (r.next()) |t| {
      const j = ctx.ss.at(ctx.w, t[0], t[1]) orelse continue;
      if (j == i or ctx.ss.get(j).def().carrier) continue;
      var out = ctx.ss.outputs(i);
      while (out.next()) |item| {
        const have:u16 = @intCast(@min(left, self.inv.count(item)));
        const k = ctx.ss.insert(ctx.g, j, item, have);
        if (k == 0) continue;
        _ = self.inv.take(item, k);
        left -= k;
        if (left == 0) return h.amount;
      }
    }
  }
  return h.amount - left;
}

/// the tiles exactly `d` steps (four ways) out from a footprint
/// `x0..x1` × `y0..y1`, clockwise from its east side: each side, then the
/// corner after it (a 1×1's ring 1 is its neighbours in `m.dirs` order)
const Ring = struct {
  x0:i32,
  y0:i32,
  x1:i32,
  y1:i32,
  d:i32,
  /// east, south-east, south, south-west, west, north-west, north, north-east
  seg:u4 = 0,
  k:i32 = 0,

  fn len(r:*const Ring) i32 {
    return switch (r.seg) {
      0, 4 => r.y1 - r.y0 + 1,
      2, 6 => r.x1 - r.x0 + 1,
      else => r.d - 1,
    };
  }

  fn next(r:*Ring) ?[2]i32 {
    while (r.seg < 8 and r.k >= r.len()) {
      r.seg += 1;
      r.k = 0;
    }
    if (r.seg == 8) return null;
    const k = r.k;
    const d = r.d;
    r.k += 1;
    return switch (r.seg) {
      0 => .{ r.x1 + d, r.y0 + k },
      1 => .{ r.x1 + d - 1 - k, r.y1 + 1 + k },
      2 => .{ r.x1 - k, r.y1 + d },
      3 => .{ r.x0 - 1 - k, r.y1 + d - 1 - k },
      4 => .{ r.x0 - d, r.y1 - k },
      5 => .{ r.x0 - d + 1 + k, r.y0 - 1 - k },
      6 => .{ r.x0 + k, r.y0 - d },
      7 => .{ r.x1 + 1 + k, r.y0 - d + 1 + k },
      else => unreachable,
    };
  }
};

/// a floating plant a structure draws in toward itself: how far along the
/// way it is (0 leaving its tile .. 1 there; the GPU moves it, see
/// common.glsl `haloSpiral`) and how high over the structure's ground it
/// is drawn to.
pub const Hold = struct { k:f32, seat:f32 };

/// every field of celestial energy a structure holds, into `out`.
pub fn fields(ss:*const Structures, gpa:Allocator, out:*std.ArrayList(Field)) Allocator.Error!void {
  out.clearRetainingCapacity();
  for (ss.list.items) |*s| switch (s.kind()) {
    inline else => |k| if (comptime reg.has(k, "field")) if (reg.module(k).field(s)) |f| try out.append(gpa, f),
  };
}

/// the structure drawing the floater at a tile toward itself, if any.
pub fn hold(ss:*const Structures, wx:i32, wy:i32) ?struct { s:*const Structure, h:Hold } {
  for (ss.list.items) |*s| switch (s.kind()) {
    inline else => |k| if (comptime reg.has(k, "hold")) if (reg.module(k).hold(s, wx, wy)) |h| return .{ .s = s, .h = h },
  };
  return null;
}

pub fn release(s:*Structure) ?items.Item {
  return switch (s.kind()) {
    inline else => |k| if (comptime reg.has(k, "release")) reg.module(k).release(s) else null,
  };
}

/// does kind `k` do anything when configured?
pub fn configurable(k:Kind) bool {
  return switch (k) {
    inline else => |t| comptime reg.has(t, "configure"),
  };
}

pub fn configure(ss:*Structures, id:Id, g:*prog.Progression) void {
  switch (ss.get(id).kind()) {
    inline else => |k| if (comptime reg.has(k, "configure")) reg.module(k).configure(ss, id, g),
  }
}

pub fn recipes(k:Kind) []const u8 {
  return switch (k) {
    inline else => |t| if (comptime reg.has(t, "recipes")) reg.module(t).recipes() else &.{},
  };
}

pub fn chosen(s:*const Structure) ?u8 {
  return switch (s.kind()) {
    inline else => |k| if (comptime reg.has(k, "chosen")) reg.module(k).chosen(s) else null,
  };
}

pub fn choose(s:*Structure, g:*prog.Progression, r:u8) void {
  switch (s.kind()) {
    inline else => |k| if (comptime reg.has(k, "choose")) reg.module(k).choose(s, g, r),
  }
}

pub fn emit(s:*const Structure, out:*Parts, ctr:m.V3, tf:f32) Allocator.Error!void {
  switch (s.kind()) {
    inline else => |k| if (comptime reg.has(k, "emit")) try reg.module(k).emit(s, out, ctr, tf),
  }
}

pub fn describe(s:*const Structure, d:*Draw, g:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  switch (s.kind()) {
    inline else => |k| if (comptime reg.has(k, "describe")) try reg.module(k).describe(s, d, g, x, y),
  }
}

/// draws kind `k`'s bulb in the HUD, its seed tinted `col`.
pub fn icon(k:Kind, ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  switch (k) {
    inline else => |t| if (comptime reg.has(t, "icon")) try reg.module(t).icon(ic, col) else try icon_kit.plain(ic, col),
  }
}

/// take one ripe unit of a mature plant's yield (plants never set seed).
pub fn harvestOne(plants:*Plants, id:PlantId) ?items.Item {
  const p = id.idx();
  const s = plants.list.slice();
  if (s.items(.growth)[p] < 1 or s.items(.essence)[p] < 1) return null;
  s.items(.essence)[p] -= 1;
  return species.get(s.items(.sp)[p]).yields;
}

test "conduits harvest plants into a cache" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..4) |x| { c.kind[x] = .soil; c.height[x] = 1; c.res[x] = 0; }
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  // plant -> conduit -> conduit -> cache, left to right
  try testing.expect(try plants.placeEx(gpa, &w, 0, 0, .{ .x = 0, .y = 0, .chunk = undefined, .tile = undefined, .sp = .lumenroot, .seed = 0, .growth = 1, .essence = 3 }));
  try testing.expect(try ss.place(gpa, &w, 1, 0, .conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 0, .conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 3, 0, .sap_cache, 0, 0));
  for (0..200) |_| try ss.tick(gpa, &w, &plants, &g, 0.05);
  const cache = ss.at(&w, 3, 0).?;
  try testing.expectEqual(@as(u32, 3), ss.get(cache).inv.count(.essence));
  // removing the middle conduit keeps the others addressable
  _ = ss.remove(&w, ss.at(&w, 1, 0).?);
  try testing.expect(ss.get(ss.at(&w, 3, 0).?).kind() == .sap_cache);
}
test "a conduit's side root reaches a plant beside it and harvests it" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..3) |x| for (0..2) |y| { const t = y * ck.SIZE + x; c.kind[t] = .soil; c.height[t] = 1; c.res[t] = 0; };
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  // conduit -> cache along +x, a mature plant beside the conduit (+y)
  try testing.expect(try plants.placeEx(gpa, &w, 1, 1, .{ .x = 1, .y = 1, .chunk = undefined, .tile = undefined, .sp = .lumenroot, .seed = 0, .growth = 1, .essence = 2 }));
  try testing.expect(try ss.place(gpa, &w, 1, 0, .conduit, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 0, .sap_cache, 0, 0));
  // nothing moves until the root has grown out to it
  try ss.tick(gpa, &w, &plants, &g, 0.05);
  try testing.expect(ss.get(ss.at(&w, 1, 0).?).state.conduit.held == null);
  for (0..200) |_| try ss.tick(gpa, &w, &plants, &g, 0.05);
  try testing.expectEqual(@as(u32, 2), ss.get(ss.at(&w, 2, 0).?).inv.count(.essence));
}

test "a footprint's ring holds every tile that many steps out, once, beside ones first in `m.dirs` order" {
  var one:Ring = .{ .x0 = 0, .y0 = 0, .x1 = 0, .y1 = 0, .d = 1 };
  for (m.dirs) |d| {
    const v = m.dirVec(d);
    try testing.expectEqual([2]i32{ v.x, v.z }, one.next().?);
  }
  try testing.expect(one.next() == null);
  for ([_]i32{ 1, 2 }) |n| for ([_]i32{ 1, 2, 3 }) |d| {
    var r:Ring = .{ .x0 = 0, .y0 = 0, .x1 = n - 1, .y1 = n - 1, .d = d };
    var seen:[64][2]i32 = undefined;
    var c:usize = 0;
    while (r.next()) |t| : (c += 1) {
      const dx = @max(0 - t[0], 0, t[0] - (n - 1));
      const dy = @max(0 - t[1], 0, t[1] - (n - 1));
      try testing.expectEqual(d, dx + dy);
      for (seen[0..c]) |s| try testing.expect(!(s[0] == t[0] and s[1] == t[1]));
      seen[c] = t;
    }
    try testing.expectEqual(@as(usize, @intCast(4 * n + 4 * (d - 1))), c);
  };
}

test "handing off reaches further and hands more when asked, the nearest first" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..4) |x| { c.kind[x] = .soil; c.height[x] = 1; c.res[x] = 0; }
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  const ctx:Ctx = .{ .gpa = gpa, .w = &w, .plants = &plants, .g = &g, .ss = &ss };
  // loomfern, a gap, a cache two steps out
  try testing.expect(try ss.place(gpa, &w, 0, 0, .loomfern, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 2, 0, .sap_cache, 0, 0));
  const fern = ss.at(&w, 0, 0).?;
  const cache = ss.at(&w, 2, 0).?;
  _ = ss.get(fern).inv.add(.fibre, 6);
  try testing.expect(!handOff(ctx, fern));
  try testing.expectEqual(@as(u16, 4), handOffWith(ctx, fern, .{ .range = 2, .amount = 4 }));
  try testing.expectEqual(@as(u32, 4), ss.get(cache).inv.count(.fibre));
  // a cache beside it now comes first; asked for more than it has, all go
  try testing.expect(try ss.place(gpa, &w, 1, 0, .sap_cache, 0, 0));
  const near = ss.at(&w, 1, 0).?;
  try testing.expectEqual(@as(u16, 2), handOffWith(ctx, fern, .{ .range = 2, .amount = 9 }));
  try testing.expectEqual(@as(u32, 2), ss.get(near).inv.count(.fibre));
  try testing.expectEqual(@as(u32, 0), ss.get(fern).inv.count(.fibre));
}

/// `find` and `getChildren` as walking the whole list answers them
fn expectIndexed(ss:*const Structures) !void {
  try testing.expectEqual(ss.list.items.len, ss.where.count());
  try testing.expectEqual(ss.list.items.len, ss.kin.items.len);
  for (ss.list.items, 0..) |*s, i| {
    try testing.expectEqual(Id.of(i), ss.find(s.ref()).?);
    var it = ss.getChildren(Id.of(i));
    for (ss.list.items, 0..) |*o, j| if (o.parent) |p| if (p.eql(s.ref())) {
      try testing.expectEqual(Id.of(j), it.next().?);
    };
    try testing.expect(it.next() == null);
  }
}

test "the tile index and the children agree with the list through placing, adopting, uprooting and a reload" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..10) |x| for (0..10) |y| { const t = y * ck.SIZE + x; c.kind[t] = .soil; c.height[t] = 1; c.res[t] = 0; };
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  var rng = engine.core.rng.Rng.init(7);
  const ks = [_]Kind{ .sap_cache, .monfris, .vultrixi, .vultrixi };
  for (0..400) |_| {
    const n = ss.list.items.len;
    switch (rng.below(4)) {
      0, 1 => _ = try ss.place(gpa, &w, @intCast(rng.below(10)), @intCast(rng.below(10)), ks[rng.below(ks.len)], 0, 0),
      2 => if (n > 0) { _ = ss.dependOn(Id.of(rng.below(@intCast(n))), Id.of(rng.below(@intCast(n)))); },
      else => if (n > 0) {
        if (rng.below(3) == 0) ss.detach(Id.of(rng.below(@intCast(n)))) else _ = ss.remove(&w, Id.of(rng.below(@intCast(n))));
      },
    }
    try expectIndexed(&ss);
  }
  // put back as saved, in the same order
  var again:Structures = .{};
  defer again.deinit(gpa);
  var w2 = World.init(gpa, 5);
  defer w2.deinit();
  try w2.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c2 = w2.chunkOfTile(0, 0).?;
  for (0..10) |x| for (0..10) |y| { const t = y * ck.SIZE + x; c2.kind[t] = .soil; c2.height[t] = 1; c2.res[t] = 0; };
  for (ss.list.items) |s| try testing.expect(try again.restore(gpa, &w2, s));
  again.relink();
  try expectIndexed(&again);
  for (0..ss.list.items.len) |i| try testing.expectEqual(ss.childCount(Id.of(i)), again.childCount(Id.of(i)));
}

test "uprooting keeps the others in the order they were put down, each found on its own tiles" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..12) |x| for (0..2) |y| { const t = y * ck.SIZE + x; c.kind[t] = .soil; c.height[t] = 1; c.res[t] = 0; };
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  const put = [_]struct { x:i32, k:Kind }{ .{ .x = 0, .k = .sap_cache }, .{ .x = 1, .k = .monfris }, .{ .x = 3, .k = .sap_cache }, .{ .x = 4, .k = .monfris }, .{ .x = 6, .k = .loomfern } };
  for (put) |p| try testing.expect(try ss.place(gpa, &w, p.x, 0, p.k, 0, 0));
  _ = ss.remove(&w, ss.at(&w, 0, 0).?);
  _ = ss.remove(&w, ss.at(&w, 3, 0).?);
  const left = [_]i32{ 1, 4, 6 };
  try testing.expectEqual(left.len, ss.list.items.len);
  for (ss.list.items, left, 0..) |*s, x, i| {
    try testing.expectEqual(x, s.x);
    var it = m.footprint(s.x, s.y, s.def().size);
    while (it.next()) |t| try testing.expectEqual(Id.of(i), w.occAt(t[0], t[1]).asStructure().?);
  }
  try testing.expect(w.occAt(0, 0).asStructure() == null and w.occAt(3, 0).asStructure() == null);
  try expectIndexed(&ss);
}

test "several partners: each once, oldest first, the oldest let go past `most`" {
  var s:Structure = .{ .x = 0, .y = 0, .seed = 0, .state = freshState(.driftbraid) };
  const r = [_]Ref{ .{ .x = 1, .y = 0, .floating = false }, .{ .x = 2, .y = 0, .floating = false }, .{ .x = 3, .y = 0, .floating = false } };
  try testing.expect(s.addPartner(r[0], 2) == null);
  try testing.expect(s.addPartner(r[0], 2) == null);
  try testing.expect(s.addPartner(r[1], 2) == null);
  try testing.expectEqual(@as(usize, 2), s.partnerCount());
  try testing.expect(s.addPartner(r[2], 2).?.eql(r[0]));
  try testing.expect(s.partner().?.eql(r[1]) and s.pairedWith(r[2]) and !s.pairedWith(r[0]));
  try testing.expect(s.dropPartner(r[1]) and !s.dropPartner(r[1]));
  try testing.expect(s.partner().?.eql(r[2]) and s.partnerCount() == 1);
}

test "several outputs: what a neighbour wants goes, even when it is not the first" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..4) |x| { c.kind[x] = .soil; c.height[x] = 1; c.res[x] = 0; }
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  const ctx:Ctx = .{ .gpa = gpa, .w = &w, .plants = &plants, .g = &g, .ss = &ss };
  try testing.expect(try ss.place(gpa, &w, 0, 0, .sap_cache, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 1, 0, .loomfern, 0, 0));
  const cache = ss.at(&w, 0, 0).?;
  _ = ss.get(cache).inv.add(.essence, 2);
  _ = ss.get(cache).inv.add(.fibre, 3);
  // the newest stack first, then the rest it gives
  var out = ss.outputs(cache);
  try testing.expect(out.next() == .fibre and out.next() == .essence and out.next() == null);
  // a loomfern takes no fibre, only essence
  try testing.expect(handOff(ctx, cache));
  try testing.expectEqual(@as(u32, 1), ss.get(ss.at(&w, 1, 0).?).inv.count(.essence));
  try testing.expectEqual(@as(u32, 3), ss.get(cache).inv.count(.fibre));
}

test "a structure put down grows before it works" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..2) |x| for (0..2) |y| { const t = y * ck.SIZE + x; c.kind[t] = .soil; c.height[t] = 1; c.res[t] = 0; };
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 0, 0, .germinator, 0, 0));
  const id = ss.at(&w, 0, 0).?;
  ss.sprout(id);
  try testing.expectEqual(@as(f32, 0), ss.get(id).grown);
  const secs = defs.get(.germinator).grow;
  var t:f32 = 0;
  while (t < secs * 0.5) : (t += 0.05) try ss.tick(gpa, &w, &plants, &g, 0.05);
  try testing.expect(ss.get(id).grown > 0.4 and ss.get(id).grown < 0.6);
  try testing.expect(ss.get(id).activity < 0.01);
  while (t < secs + 0.1) : (t += 0.05) try ss.tick(gpa, &w, &plants, &g, 0.05);
  try testing.expectEqual(@as(f32, 1), ss.get(id).grown);
}

test "a germinator weaves structure bulbs as well as seeds, and lets go only what it wove" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..2) |x| for (0..2) |y| { const t = y * ck.SIZE + x; c.kind[t] = .soil; c.height[t] = 1; c.res[t] = 0; };
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  var g:prog.Progression = .{};
  try testing.expect(try ss.place(gpa, &w, 0, 0, .germinator, 0, 0));
  const id = ss.at(&w, 0, 0).?;
  const craft = lib.craft;
  // every weave is on offer, the bulbs too, but the advanced tier, which
  // only a monfris weaves
  try testing.expectEqual(craft.hand.len - craft.advanced.len, recipes(.germinator).len);
  for (recipes(.monfris)) |r| try testing.expect(craft.hand[r].advanced);
  const conduit = for (recipes(.germinator)) |r| {
    if (craft.hand[r].out == .conduit) break r;
  } else unreachable;
  choose(ss.get(id), &g, conduit);
  try testing.expectEqual(@as(u16, 5), ss.insert(&g, id, .fibre, 5));
  try testing.expectEqual(@as(u16, 2), ss.insert(&g, id, .grit, 2));
  // what it weaves from never leaves it
  try testing.expect(ss.output(id) == null);
  for (0..400) |_| try ss.tick(gpa, &w, &plants, &g, 0.05);
  try testing.expectEqual(@as(u32, 4), ss.get(id).inv.count(.conduit));
  try testing.expectEqual(@as(u32, 1), ss.get(id).inv.count(.fibre));
  try testing.expect(ss.output(id) == .conduit);
}

test "parents and children: spawned, adopted, found again after a shift, cut loose when the parent goes" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..8) |x| for (0..8) |y| { const t = y * ck.SIZE + x; c.kind[t] = .soil; c.height[t] = 1; c.res[t] = 0; };
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  try testing.expect(try ss.place(gpa, &w, 0, 0, .sap_cache, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 4, 4, .monfris, 0, 0));
  const loom = ss.at(&w, 4, 4).?;
  // a child put down by its parent, over the parent's own tile
  const v0 = (try ss.spawnChild(gpa, &w, loom, .{ .x = 4, .y = 4, .kind = .vultrixi })).?;
  try testing.expectEqual(loom, ss.getParent(v0).?);
  try testing.expect(try ss.spawnChild(gpa, &w, loom, .{ .x = 4, .y = 4, .kind = .vultrixi }) == null);
  // adopted: only what the parent takes on (`adopts`), never in a loop
  try testing.expect(try ss.place(gpa, &w, 1, 1, .vultrixi, 0, 0));
  const v1 = ss.floaterAt(1, 1).?;
  const cache = ss.at(&w, 0, 0).?;
  try testing.expect(!ss.dependOn(v1, cache));
  try testing.expect(!ss.dependOn(loom, v1));
  try testing.expect(!ss.dependOn(v1, v1));
  try testing.expect(ss.dependOn(v1, loom));
  try testing.expectEqual(@as(u32, 2), ss.childCount(loom));
  try testing.expectEqual(v0, ss.getChild(loom, 0).?);
  try testing.expectEqual(v1, ss.getChild(loom, 1).?);
  try testing.expect(ss.getChild(loom, 2) == null);
  try testing.expectEqual(@as(u32, 0), ss.childCount(cache));
  // uprooting the cache shifts the others' ids; they still find each other
  _ = ss.remove(&w, cache);
  const loom2 = w.occAt(4, 4).asStructure().?;
  try testing.expectEqual(@as(u32, 2), ss.childCount(loom2));
  try testing.expectEqual(loom2, ss.getParent(ss.floaterAt(1, 1).?).?);
  ss.detach(ss.floaterAt(1, 1).?);
  try testing.expectEqual(@as(u32, 1), ss.childCount(loom2));
  // uprooting the parent cuts its children loose
  _ = ss.remove(&w, loom2);
  try testing.expect(ss.get(ss.floaterAt(4, 4).?).parent == null);
}

test "partners: one way or both ways, re-pairing leaves the old one, uprooting cuts it" {
  const gpa = testing.allocator;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..8) |x| { c.kind[x] = .soil; c.height[x] = 1; c.res[x] = 0; }
  var ss:Structures = .{};
  defer ss.deinit(gpa);
  for (0..3) |x| try testing.expect(try ss.place(gpa, &w, @intCast(x), 0, .driftbraid, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 4, 0, .sporecaster, 0, 0));
  try testing.expect(try ss.place(gpa, &w, 5, 0, .sap_cache, 0, 0));
  const a = ss.at(&w, 0, 0).?;
  const b = ss.at(&w, 1, 0).?;
  const d = ss.at(&w, 2, 0).?;
  // only with its own kind, never with itself, never what does not pair
  try testing.expect(!ss.pairWith(a, ss.at(&w, 4, 0).?));
  try testing.expect(!ss.pairWith(a, a));
  try testing.expect(!ss.pairWith(ss.at(&w, 5, 0).?, a));
  try testing.expect(ss.pairWith(a, b));
  try testing.expectEqual(a, ss.getPartner(b).?);
  // both ways: d pairing with b leaves a alone
  try testing.expect(ss.pairWith(d, b));
  try testing.expect(ss.get(a).partner() == null);
  try testing.expectEqual(d, ss.getPartner(b).?);
  _ = ss.remove(&w, b);
  try testing.expect(ss.get(ss.at(&w, 2, 0).?).partner() == null);
}
