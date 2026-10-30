//! per-structure hooks the HUD, the renderer and the garden ask through.
const lib = @import("../../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const engine = lib.engine;
const m = engine.core.math;
const items = lib.items;
const species = lib.species;
const Plants = lib.plants.Plants;
const Field = lib.ecology.Field;
const prog = lib.progression;
const Parts = lib.parts.Parts;
const Draw = engine.ui.draw.Draw;
const Color = engine.ui.draw.Color;
const icon_kit = lib.icon;
const Id = lib.structures.Id;
const Kind = lib.structures.Kind;
const PlantId = lib.structures.PlantId;
const Structure = lib.structures.structure.Structure;
const Structures = lib.structures.list.Structures;
const reg = lib.structures.reg;

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
