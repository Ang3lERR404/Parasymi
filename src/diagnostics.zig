//! This module is built for the sole purpose of finding any bugs in the code
//! or silent errors that are hard to pin down.
//! any and all of these functions should not be touched unless it is absolutely necessary.
//! changing the behavior of these functions is prohibited unless stated otherwise.
//! changing the functionality will always result in erroneous bugs or confusing results.
//! these should be kept as is.
//! never optimize them.
//! never "clean" them.
//! only improve upon/add to them.
//! do not change any imports.
//! do not remove any imports.
//! do not do x
//! do not do y
//! simply, do not.
//! only use them.
//! STRICT RULE ENFORCED BY USER.
//! ANY VIOLATION WILL RESULT IN AN IMMEDIATE REPORT OR TERMINATION.
const lib = @import("lib.zig");
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
const record = lib.record;
const structures = lib.structures;

const Structures = structures.Structures;
const Kind = structures.Kind;
const defs = structures.defs;

pub fn whyNot(ss:*const Structures, w:*const World, wx:i32, wy:i32, k:Kind) void {
  const d = defs.get(k);
  if (d.floating) {
    std.debug.print("floating {s}\n", .{if (ss.floaterAt(wx, wy) != null) "occupied" else "ok"});
    return;
  }
  const c0 = w.chunkOfTile(wx, wy) orelse {std.debug.print("chunk not loaded\n",.{}); return;};
  const h0 = c0.height[ck.localIndex(wx, wy)];
  std.debug.print("anchor h={d}\n", .{h0});
  var it = m.footprint(wx, wy, d.size);
  while (it.next()) |p| {
    const c = w.chunkOfTile(p[0], p[1]) orelse {std.debug.print("tile ({d},{d}) chunk missing\n",.{p[0],p[1]});continue;};
    const t = ck.localIndex(p[0], p[1]);
    std.debug.print("Tile ({d},{d}): occ={any} kind={any} h={d}\n", .{p[0],p[1],c.occ[t],c.kind[t],c.height[t]});
  }
  std.debug.print("canPlace={any}\n", .{ss.canPlace(w, wx, wy, k)});
}