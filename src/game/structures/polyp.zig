//! POLYP: the heart of a halo. When four grown celestial blooms stand at
//! the four corners of the square turned 45° on the grid around it, `HALF`
//! tiles out east, south, west and north, the halo completes (checked each
//! tick until it does, then never again): the blooms spiral in toward the
//! polyp, slowly and then exponentially faster, and a still band of light
//! forms along the square's edges, floating where they hung, as they leave
//! their corners. Where they meet in its cup they become one: a small
//! diamond. The ring stays for good and is a field of celestial energy
//! over the square; the diamond holds a wider one around it. A corner
//! without a grown bloom dims the ring's edges beside it, never below
//! `DIM`. (The diamond is where the world event will start from.)
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const ck = @import("../../world/chunk.zig");
const gen = @import("../../world/gen.zig");
const World = @import("../../world/world.zig").World;
const species = @import("../../sim/species.zig");
const Plants = @import("../../sim/plants.zig").Plants;
const Field = @import("../../sim/ecology.zig").Field;
const st = @import("../structures.zig");
const txt = @import("../text.zig");
const prog = @import("../progression.zig");
const style = @import("../style.zig");
const Parts = @import("../parts.zig").Parts;
const Draw = @import("../../ui/draw.zig").Draw;
const mesh = @import("../../gfx/meshes/polyp.zig");

pub const def:st.Def = .{ .item = .polyp, .size = 1, .mesh = .polyp, .sway = 0.4, .tall = 0.9, .grow = 6, .sap = 0.6 };

/// the square's corners lie this many tiles out along the axes (its side
/// is √2 times this: 7.1 tiles)
pub const HALF:i32 = 5;
/// the corners in order around the square (east, south, west, north); edge
/// k runs from corner k to k+1
pub const CORNERS = [4][2]i32{ .{ 1, 0 }, .{ 0, 1 }, .{ -1, 0 }, .{ 0, -1 } };
/// a bloom holds a corner when grown and healthier than this
const ACTIVE_HEALTH:f32 = 0.5;
/// seconds the blooms take to reach the centre; the ring has formed by
/// `RING_BY` of that
pub const FORM:f32 = 5;
const RING_BY:f32 = 0.75;
// (the way in, the diamond's forming as they close in, and the blooms
// folding are the GPU's: common.glsl `haloSpiral`; it is sent how far the
// halo has come, `t / FORM`)
/// the flash where they meet spreads and fades over this many seconds
const FLASH:f32 = 1.4;
/// the diamond's field reaches this far (the ring's square reaches 5 out
/// at its corners, 3.5 at its edges)
const DIAMOND_R:f32 = 7;
/// how bright a corner's edges are without a bloom (1 with one), and how
/// quickly they follow
const DIM:f32 = 0.3;
const LIGHT_EASE:f32 = 0.4;

pub const Phase = enum(u8) { open, forming, complete };

pub const State = struct {
  phase:Phase = .open,
  /// seconds since the halo began forming
  t:f32 = 0,
  /// per corner: how brightly the edges beside it shine
  light:[4]f32 = @splat(1),
  /// ground height under each edge's four control points (sampled once,
  /// when the halo forms; the terrain never changes); the ring floats a
  /// bloom's hover over it
  ground:[4][4]f32 = @splat(@splat(0)),
};

fn cornerAt(s:*const st.Structure, k:usize) [2]i32 {
  return .{ s.x + CORNERS[k][0] * HALF, s.y + CORNERS[k][1] * HALF };
}

/// a grown, unwithered celestial bloom at a tile
fn active(p:*const Plants, w:*const World, at:[2]i32) bool {
  const id = p.at(w, at[0], at[1]) orelse return false;
  const i = id.idx();
  const s = p.list.slice();
  return species.get(s.items(.sp)[i]).radiance > 0 and s.items(.growth)[i] >= 1 and s.items(.health)[i] > ACTIVE_HEALTH;
}

/// the four control points of edge e, from corner e to the next, tile
/// space (y unset)
fn edgePoints(s:*const st.Structure, e:usize) [4]m.V3 {
  const a = cornerAt(s, e);
  const b = cornerAt(s, (e + 1) % 4);
  var out:[4]m.V3 = undefined;
  for (&out, 0..) |*o, i| o.* = m.lerpV(m.tileCentre(a[0], a[1], 0), m.tileCentre(b[0], b[1], 0), m.ratio(i, 3));
  return out;
}

fn tileHeight(w:*const World, wx:i32, wy:i32) f32 {
  const h = if (w.chunkOfTile(wx, wy)) |c| c.height[ck.localIndex(wx, wy)] else gen.heightAt(w.seed, wx, wy);
  // over water, it lies on the surface
  return @max(h, 0);
}

/// the ground's height at a point (tile centres hold their tile's height;
/// between them it runs straight, as the terrain does)
fn groundAt(w:*const World, p:m.V3) f32 {
  const fx = p[0] - 0.5;
  const fz = p[2] - 0.5;
  const x0 = m.floorTo(i32, fx);
  const z0 = m.floorTo(i32, fz);
  const kx = fx - m.f(x0);
  const kz = fz - m.f(z0);
  const top = m.lerp(tileHeight(w, x0, z0), tileHeight(w, x0 + 1, z0), kx);
  const bot = m.lerp(tileHeight(w, x0, z0 + 1), tileHeight(w, x0 + 1, z0 + 1), kx);
  return m.lerp(top, bot, kz);
}

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  const self = ctx.ss.get(i);
  const h = &self.state.polyp;
  switch (h.phase) {
    .open => {
      for (0..4) |k| if (!active(ctx.plants, ctx.w, cornerAt(self, k))) return false;
      h.phase = .forming;
      h.t = 0;
      h.light = @splat(1);
      for (&h.ground, 0..) |*g, e| for (g, edgePoints(self, e)) |*y, p| {
        y.* = groundAt(ctx.w, p);
      };
      ctx.g.say(txt.s.msg.halo_forms, .{});
      return true;
    },
    .forming => {
      h.t += dt;
      if (h.t < FORM) return true;
      // they meet: the blooms are consumed into the diamond
      for (0..4) |k| {
        const at = cornerAt(self, k);
        const id = ctx.plants.at(ctx.w, at[0], at[1]) orelse continue;
        if (species.get(ctx.plants.list.items(.sp)[id.idx()]).radiance > 0) ctx.plants.remove(ctx.w, id);
      }
      h.phase = .complete;
      ctx.g.say(txt.s.msg.diamond_forms, .{});
      return true;
    },
    .complete => {
      h.t = @min(h.t + dt, FORM + FLASH);
      for (&h.light, 0..) |*l, k| {
        const want:f32 = if (active(ctx.plants, ctx.w, cornerAt(self, k))) 1 else DIM;
        l.* += (want - l.*) * @min(1, dt * LIGHT_EASE);
      }
      return false;
    },
  }
}

/// the ring's square from the moment it starts to form; the diamond's disc
/// once it has.
pub fn field(s:*const st.Structure) ?Field {
  const h = &s.state.polyp;
  return switch (h.phase) {
    .open => null,
    .forming => .{ .x = s.x, .y = s.y, .turned = HALF },
    .complete => .{ .x = s.x, .y = s.y, .turned = HALF, .radius = DIAMOND_R },
  };
}

/// a bloom at one of a forming halo's corners is drawn in to the cup (the
/// GPU spirals it there, see `emit`).
pub fn hold(s:*const st.Structure, wx:i32, wy:i32) ?st.Hold {
  const h = &s.state.polyp;
  if (h.phase != .forming) return null;
  for (0..4) |k| {
    const at = cornerAt(s, k);
    if (at[0] == wx and at[1] == wy) return .{ .k = h.t / FORM, .seat = mesh.SEAT * s.grownScale()[1] };
  }
  return null;
}

/// the ring: four edges of beams of light, as between linked blooms, each
/// reaching from its corner to the next as its bloom leaves it, light
/// running round it from corner to corner; the diamond in the cup, forming
/// as the blooms close in; and, as they meet, a flash of light.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, _:f32) Allocator.Error!void {
  const h = &s.state.polyp;
  if (h.phase == .open) return;
  const reach = m.smooth(m.clamp01(h.t / (FORM * RING_BY)));
  for (0..4) |e| {
    var ctrl = edgePoints(s, e);
    for (&ctrl, h.ground[e]) |*p, y| p[1] = y + species.get(.bloom).hover;
    const span = ctrl[3] - ctrl[0];
    const side = m.norm(m.cross(span, m.v3(0, 1, 0)));
    // as bright as the corners at its ends; flutter 1 marks a halo's edge
    const lit = (h.light[e] + h.light[(e + 1) % 4]) * 0.5;
    try out.emitCurve(.bloom_thread, ctrl, side, 1, reach, .{ .glow = lit, .flutter = 1, .phase = s.seed + m.f(e) * 0.25 });
  }
  const lift = mesh.SEAT * s.grownScale()[1];
  const at = ctr + m.v3(0, lift, 0);
  const halo = [4]f32{ at[0], at[1], at[2], h.t / FORM };
  try out.emit(.halo_diamond, m.chain(&.{ m.translate(at), m.rotY(s.seed * m.tau) }), .{
    .phase = s.seed, .sway = def.sway, .tall = def.tall, .drop = lift, .halo = halo,
  });
  const age = (h.t - FORM) / FLASH;
  if (age >= 0 and age < 1) try out.emit(.halo_flash, m.translate(at), .{ .glow = 1, .flutter = age });
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  const h = &s.state.polyp;
  switch (h.phase) {
    .open => _ = try d.print(x, y, style.text_body, style.dim, txt.s.describe.halo_open, .{HALF}),
    .forming => _ = try d.text(x, y, style.text_body, style.gold, txt.s.describe.halo_forming),
    .complete => {
      var lit:u32 = 0;
      for (h.light) |l| { if (l > (1 + DIM) / 2) lit += 1; }
      _ = try d.print(x, y, style.text_body, style.gold, txt.s.describe.halo_complete, .{lit});
    },
  }
}

test "four grown blooms on a polyp's square form a halo whose ring and diamond power plants" {
  const testing = std.testing;
  const gpa = testing.allocator;
  const Ecology = @import("../../sim/ecology.zig").Ecology;
  var w = World.init(gpa, 5);
  defer w.deinit();
  try w.stream(.{ .x = 0, .y = 0 }, 1, 100);
  const c = w.chunkOfTile(0, 0).?;
  for (0..16) |y| for (0..16) |x| { const t = y * ck.SIZE + x; c.kind[t] = .soil; c.height[t] = 1; c.res[t] = 0; };
  var plants:Plants = .{};
  defer plants.deinit(gpa);
  var ss:st.Structures = .{};
  defer ss.deinit(gpa);
  var eco:Ecology = .{};
  defer eco.deinit(gpa);
  var fl:std.ArrayList(Field) = .empty;
  defer fl.deinit(gpa);
  var g:prog.Progression = .{};
  const px = 7;
  const py = 7;
  try testing.expect(try ss.place(gpa, &w, px, py, .polyp, 0, 0));
  // a vesper inside the square and one outside it (inside the diamond's
  // reach), both beyond every corner bloom's field
  try testing.expect(try plants.place(gpa, &w, px - 1, py - 1, .vesper, 0.1));
  try testing.expect(try plants.place(gpa, &w, px + 4, py + 4, .vesper, 0.2));
  const step = struct {
    fn run(e:*Ecology, p:*Plants, ww:*World, s:*st.Structures, gg:*prog.Progression, f:*std.ArrayList(Field), secs:f32) !void {
      const dt:f32 = 1.0 / 60.0;
      var t:f32 = 0;
      while (t < secs) : (t += dt) {
        try st.fields(s, testing.allocator, f);
        _ = try e.tick(testing.allocator, p, ww, .{ .fields = f.items }, dt);
        s.tick(ww, p, gg, dt);
      }
    }
  };
  const bloom = struct {
    fn at(p:*Plants, ww:*World, x:i32, y:i32) !void {
      try testing.expect(try p.placeEx(testing.allocator, ww, x, y, .{ .x = x, .y = y, .chunk = undefined, .tile = undefined, .sp = .bloom, .seed = 0, .growth = 1, .mana = 10 }));
    }
  };
  // three corners: nothing happens, and the vesper inside has no radiance
  for (CORNERS[0..3]) |k| try bloom.at(&plants, &w, px + k[0] * HALF, py + k[1] * HALF);
  try step.run(&eco, &plants, &w, &ss, &g, &fl, 0.5);
  const id = ss.at(&w, px, py).?;
  try testing.expectEqual(Phase.open, ss.get(id).state.polyp.phase);
  try testing.expect(!eco.radiance.powered.items[plants.at(&w, px - 1, py - 1).?.idx()]);
  // the fourth: the halo forms, and its ring powers the square at once
  try bloom.at(&plants, &w, px + CORNERS[3][0] * HALF, py + CORNERS[3][1] * HALF);
  try step.run(&eco, &plants, &w, &ss, &g, &fl, 0.1);
  try testing.expectEqual(Phase.forming, ss.get(id).state.polyp.phase);
  try testing.expect(eco.radiance.powered.items[plants.at(&w, px - 1, py - 1).?.idx()]);
  try testing.expect(!eco.radiance.powered.items[plants.at(&w, px + 4, py + 4).?.idx()]);
  // the blooms are being drawn in
  const early = hold(ss.get(id), px + HALF, py).?;
  try testing.expect(early.k > 0 and early.k < 0.05);
  // they meet: consumed into the diamond, whose field reaches further
  try step.run(&eco, &plants, &w, &ss, &g, &fl, FORM + 0.5);
  try testing.expectEqual(Phase.complete, ss.get(id).state.polyp.phase);
  for (CORNERS) |k| try testing.expect(plants.at(&w, px + k[0] * HALF, py + k[1] * HALF) == null);
  try testing.expect(eco.radiance.powered.items[plants.at(&w, px - 1, py - 1).?.idx()]);
  try testing.expect(eco.radiance.powered.items[plants.at(&w, px + 4, py + 4).?.idx()]);
  // it never forms again; the empty corners' edges dim but stay
  try step.run(&eco, &plants, &w, &ss, &g, &fl, 10);
  try testing.expectEqual(Phase.complete, ss.get(id).state.polyp.phase);
  for (ss.get(id).state.polyp.light) |l| try testing.expect(l < 0.5 and l >= DIM);
}
