//! plant storage: one struct-of-arrays for every living plant in the world.
//! Neighbour links are cached as plain indices and rebuilt only when the
//! topology changes, so the per-tick ecology loop never touches a hash map.
const std = @import("std");
const ck = @import("../world/chunk.zig");
const World = @import("../world/world.zig").World;
const species = @import("species.zig");

pub const NONE = ck.NONE;
/// adjacent ring (8) and second ring (16) of neighbours.
pub const R1 = 8;
pub const R2 = 16;

pub const Plant = struct {
  x:i32, y:i32,
  chunk:*ck.Chunk,
  tile:u16,
  sp:species.Id,
  growth:f32 = 0,
  mana:f32 = 1,
  health:f32 = 1,
  /// 0..1 random, drives animation phase and mesh variation.
  seed:f32,
  /// smoothed magnitude of mana moving through the plant (animation/glow).
  flow:f32 = 0,
  n1:[R1]u32 = @splat(NONE),
  n2:[R2]u32 = @splat(NONE),
};

pub const Plants = struct {
  list:std.MultiArrayList(Plant) = .empty,
  topology_dirty:bool = false,

  pub fn deinit(p:*Plants, gpa:std.mem.Allocator) void { p.list.deinit(gpa); }
  pub fn len(p:*const Plants) usize { return p.list.len; }

  pub fn place(p:*Plants, gpa:std.mem.Allocator, w:*World, wx:i32, wy:i32, sp:species.Id, seed:f32) !bool {
    const c = w.chunkOfTile(wx, wy) orelse return false;
    const t = ck.localIndex(wx, wy);
    if (c.plant[t] != NONE or !c.kind[t].fertile()) return false;
    const idx:u32 = @intCast(p.list.len);
    try p.list.append(gpa, .{.x = wx, .y = wy, .chunk = c, .tile = @intCast(t), .sp = sp, .seed = seed});
    c.plant[t] = idx;
    c.plants += 1;
    p.topology_dirty = true;
    return true;
  }

  pub fn removeAt(p:*Plants, w:*World, wx:i32, wy:i32) bool {
    const c = w.chunkOfTile(wx, wy) orelse return false;
    const i = c.plant[ck.localIndex(wx, wy)];
    if (i == NONE) return false;
    p.remove(i);
    return true;
  }

  /// swap-remove; fixes the tile index of the plant that moved into slot `i`.
  pub fn remove(p:*Plants, i:u32) void {
    const s = p.list.slice();
    const c = s.items(.chunk)[i];
    c.plant[s.items(.tile)[i]] = NONE;
    c.plants -= 1;
    const last:u32 = @intCast(p.list.len - 1);
    if (i != last) {
      const mc = s.items(.chunk)[last];
      mc.plant[s.items(.tile)[last]] = i;
    }
    p.list.swapRemove(i);
    p.topology_dirty = true;
  }

  pub fn rebuildLinks(p:*Plants, w:*World) void {
    const s = p.list.slice();
    const xs = s.items(.x);
    const ys = s.items(.y);
    const n1 = s.items(.n1);
    const n2 = s.items(.n2);
    for (0..p.list.len) |i| {
      var a:usize = 0;
      var b:usize = 0;
      n1[i] = @splat(NONE);
      n2[i] = @splat(NONE);
      var dy:i32 = -2;
      while (dy <= 2) : (dy += 1) {
        var dx:i32 = -2;
        while (dx <= 2) : (dx += 1) {
          if (dx == 0 and dy == 0) continue;
          const wx = xs[i] + dx;
          const wy = ys[i] + dy;
          const c = w.chunkOfTile(wx, wy) orelse continue;
          const j = c.plant[ck.localIndex(wx, wy)];
          if (j == NONE) continue;
          if (@max(@abs(dx), @abs(dy)) == 1) { n1[i][a] = j; a += 1; }
          else { n2[i][b] = j; b += 1; }
        }
      }
    }
    p.topology_dirty = false;
  }
};
