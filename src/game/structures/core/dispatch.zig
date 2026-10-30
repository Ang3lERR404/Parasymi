//! the hook dispatch over every structure: one comptime switch each, no per-kind code.
const lib = @import("../../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const engine = lib.engine;
const m = engine.core.math;
const World = lib.world.World;
const items = lib.items;
const Plants = lib.plants.Plants;
const prog = lib.progression;
const ACTIVITY_EASE = lib.structures.ACTIVITY_EASE;
const Ctx = lib.structures.structure.Ctx;
const Id = lib.structures.Id;
const MEET = lib.structures.MEET;
const Meeting = lib.structures.Meeting;
const Msg = lib.structures.messages.Msg;
const Reply = lib.structures.messages.Reply;
const SLOTS = lib.structures.SLOTS;
const Structures = lib.structures.list.Structures;
const gap = lib.structures.structure.gap;
const orFail = lib.structures.structure.orFail;
const reg = lib.structures.reg;

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

/// tell structure `to` something (`Msg`): its `message` hook takes it at
/// once, else the message's default does (`arrived`: `insert`)
pub fn send(ss:*Structures, ctx:Ctx, to:Id, msg:Msg) Reply {
  const r:Reply = switch (ss.get(to).kind()) {
    inline else => |k| if (comptime reg.has(k, "message")) reg.module(k).message(ctx, to, msg) else .ignored,
  };
  if (r != .ignored) return r;
  return switch (msg) {
    .lit => .ignored,
    .arrived => |a| .{ .took = ss.insert(ctx.g, to, a.item, a.n) },
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
