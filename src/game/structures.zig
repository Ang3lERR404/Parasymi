//! grown structures: the first steps from hand work toward automation.
//!
//! Each kind is its own module under `structures/` declaring:
//!   def:Def                     name, bulb item, footprint, mesh   (required)
//!   State                       per-kind data (optional, see `State` union)
//!   tick(ctx, id, dt) [!]bool   advance; returns whether it is active
//!   link(ctx, id)               notice its neighbours, every tick, grown or not
//!   wants(s, g, item) u32       how many of `item` it will still take in
//!   output(s) ?Item             what may leave it (pulled by conduits)
//!   gives(s, item) bool         whether `item` may leave it (default: it is
//!                               its `output`); a braided conduit's lanes
//!                               pull a different item each
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
//!   pairs:Pairs                 how it pairs with a partner, one way (it sends
//!                               there) or both ways (`pairWith`, `pairStep`,
//!                               `getPartner`, `pairedTo`, `unpair`;
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
/// (each is the other's, and either leaves whatever it had before)
pub const Pairs = struct { way:Way = .one_way, with:?Kind = null };
pub const Way = enum { one_way, both_ways };

fn pairsOf(k:Kind) ?Pairs {
  return switch (k) {
    inline else => |t| if (comptime reg.has(t, "pairs")) reg.module(t).pairs else null,
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
  /// the structure it is paired with (`pairWith`), if any
  partner:?Ref = null,
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

/// a hook result that may be an error union, as one
fn orFail(r:anytype) Allocator.Error!bool { return r; }

pub const Structures = struct {
  list:std.ArrayList(Structure) = .empty,
  /// a structure waiting to be paired with another (a sporecaster
  /// choosing where it sends): the next one configured
  pairing:?Ref = null,

  pub fn deinit(ss:*Structures, gpa:Allocator) void { ss.list.deinit(gpa); }

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
    try ss.list.append(gpa, .{ .x = wx, .y = wy, .dir = dir, .seed = seed, .state = freshState(k) });
    if (!defs.get(k).floating) w.setFootprint(wx, wy, defs.get(k).size, Occ.structure(idx));
    return true;
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

  /// the floating structure over a tile; they are few, so the list is walked
  pub fn floaterAt(ss:*const Structures, wx:i32, wy:i32) ?Id {
    for (ss.list.items, 0..) |*s, i| if (s.def().floating and s.x == wx and s.y == wy) return Id.of(i);
    return null;
  }

  /// swap-remove; returns the removed structure so its contents can be refunded.
  /// note to CLAUDE, I changed the code, it is bad to do repeated get calls.
  pub fn remove(ss:*Structures, w:*World, id:Id) Structure {
    const s = ss.get(id).*;
    // calls should always be at the top;
    const stct = s.def();
    const idx = id.idx();
    if (!stct.floating) w.setFootprint(s.x, s.y, stct.size, .none);
    const last = ss.list.items.len - 1;
    if (idx != last) {
      const l = ss.list.items[last];
      const lstct = l.def();
      if (!lstct.floating) w.moveFootprint(l.x, l.y, lstct.size, Occ.structure(id));
    }
    _ = ss.list.swapRemove(idx);
    // what depended on it, or was paired with it, is cut loose
    const gone = s.ref();
    for (ss.list.items) |*o| {
      if (o.parent) |p| if (p.eql(gone)) { o.parent = null; };
      if (o.partner) |p| if (p.eql(gone)) { o.partner = null; };
    }
    if (ss.pairing) |p| if (p.eql(gone)) { ss.pairing = null; };
    return s;
  }

  // ---- partners: paired one way or both ways (`pairs`) ----

  /// pair `a` with `b` as `a`'s kind pairs (`pairs`): one way, `a` sends to
  /// `b`; both ways, each leaves whatever it was paired with and is the
  /// other's. Returns whether they are paired now.
  pub fn pairWith(ss:*Structures, a:Id, b:Id) bool {
    if (a == b) return false;
    const ka = ss.get(a).kind();
    const pa = pairsOf(ka) orelse return false;
    if (ss.get(b).kind() != (pa.with orelse ka)) return false;
    switch (pa.way) {
      .one_way => ss.get(a).partner = ss.get(b).ref(),
      .both_ways => {
        ss.unpair(a);
        ss.unpair(b);
        ss.get(a).partner = ss.get(b).ref();
        ss.get(b).partner = ss.get(a).ref();
      },
    }
    return true;
  }

  /// cut `id` from its partner; paired both ways, every pairing that
  /// reaches it is cut too.
  pub fn unpair(ss:*Structures, id:Id) void {
    const s = ss.get(id);
    s.partner = null;
    const p = pairsOf(s.kind()) orelse return;
    if (p.way != .both_ways) return;
    const here = s.ref();
    for (ss.list.items) |*o| if (o.partner) |r| if (r.eql(here)) { o.partner = null; };
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

  pub fn getPartner(ss:*const Structures, id:Id) ?Id {
    const r = ss.list.items[id.idx()].partner orelse return null;
    return ss.find(r);
  }

  /// every structure whose partner is `id`, in list order.
  pub fn pairedTo(ss:*const Structures, id:Id) Paired {
    return .{ .ss = ss, .of = ss.list.items[id.idx()].ref() };
  }

  // ---- parents and children: a child depends on its parent ----

  /// the structure `r` names, if one still stands there
  pub fn find(ss:*const Structures, r:Ref) ?Id {
    for (ss.list.items, 0..) |*s, i| if (s.ref().eql(r)) return Id.of(i);
    return null;
  }

  /// put a structure down already depending on `parent` (its parent
  /// chooses to: no `adopts` is asked). Returns it, or null if there is
  /// no room.
  pub fn spawnChild(ss:*Structures, gpa:Allocator, w:*World, parent:Id, sp:Spawn) Allocator.Error!?Id {
    const up = ss.get(parent).ref();
    if (!try ss.place(gpa, w, sp.x, sp.y, sp.kind, sp.dir, sp.seed)) return null;
    const id = Id.of(ss.list.items.len - 1);
    ss.get(id).parent = up;
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
    if (ok) ss.get(child).parent = p.ref();
    return ok;
  }

  /// cut `child` loose from its parent.
  pub fn detach(ss:*Structures, child:Id) void { ss.get(child).parent = null; }

  pub fn getParent(ss:*const Structures, child:Id) ?Id {
    const r = ss.list.items[child.idx()].parent orelse return null;
    return ss.find(r);
  }

  /// every structure depending on `parent`, in list order.
  pub fn getChildren(ss:*const Structures, parent:Id) Children {
    return .{ .ss = ss, .of = ss.list.items[parent.idx()].ref() };
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

  pub const Children = Linked("parent");
  pub const Paired = Linked("partner");

  /// walks every structure whose `field` (a `?Ref`) names `of`
  fn Linked(comptime field:[]const u8) type {
    return struct {
      ss:*const Structures,
      of:Ref,
      i:usize = 0,

      pub fn next(it:*@This()) ?Id {
        while (it.i < it.ss.list.items.len) {
          const i = it.i;
          it.i += 1;
          if (@field(it.ss.list.items[i], field)) |p| if (p.eql(it.of)) return Id.of(i);
        }
        return null;
      }
    };
  }

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
    const ctx:Ctx = .{ .gpa = gpa, .w = w, .plants = plants, .g = g, .ss = ss };
    for (0..ss.list.items.len) |idx| switch (ss.get(Id.of(idx)).kind()) {
      inline else => |k| if (comptime reg.has(k, "link")) reg.module(k).link(ctx, Id.of(idx)),
    };
  }

  pub fn tick(ss:*Structures, gpa:Allocator, w:*World, plants:*Plants, g:*prog.Progression, dt:f32) Allocator.Error!void {
    const ctx:Ctx = .{ .gpa = gpa, .w = w, .plants = plants, .g = g, .ss = ss };
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

/// hand one of what structure `i` lets go (`output`) to a neighbour that
/// wants it; returns whether one went. Carriers are left alone: one behind
/// it pulls through `output` itself.
pub fn handOff(ctx:Ctx, i:Id) bool {
  const self = ctx.ss.get(i);
  const item = ctx.ss.output(i) orelse return false;
  for (m.dirs) |d| {
    const v = m.dirVec(d);
    const j = ctx.ss.at(ctx.w, self.x + v.x, self.y + v.z) orelse continue;
    if (j == i or ctx.ss.get(j).def().carrier) continue;
    if (ctx.ss.insert(ctx.g, j, item, 1) == 1) {
      _ = self.inv.take(item, 1);
      return true;
    }
  }
  return false;
}

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
  try testing.expect(ss.get(a).partner == null);
  try testing.expectEqual(d, ss.getPartner(b).?);
  _ = ss.remove(&w, b);
  try testing.expect(ss.get(ss.at(&w, 2, 0).?).partner == null);
}
