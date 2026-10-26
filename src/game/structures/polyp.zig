//! POLYP: where a halo forms. When four grown celestial blooms stand on the
//! four points `halo.R` tiles out east, south, west and north of it, the
//! halo forms (checked each tick until it does, then never again): the
//! blooms spiral in to the heart of the ring, where their cross of beams
//! meets, slowly and then exponentially faster, while a diamond gathers
//! there from shards of light and projects the halo's ring through the
//! points they left. Where they meet they become one: the diamond, a
//! structure of its own (`diamond.zig`), is put down floating high over
//! the polyp, with a flash of light. The polyp is left as it was. While the
//! halo forms, its ring is already a field of celestial energy (see
//! `halo.zig`).
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const m = lib.engine.core.math;
const species = lib.species;
const Field = lib.ecology.Field;
const st = lib.structures;
const icon_kit = lib.icon;
const txt = lib.txt;
const prog = lib.progression;
const style = lib.style;
const Parts = lib.parts.Parts;
const Draw = lib.engine.ui.draw.Draw;
const Color = lib.engine.ui.draw.Color;
const halo = lib.halo_structure;

/// the library meshes it draws beyond its own (`meshes`: what `--structure` builds)
pub const meshes = .{ .halo_diamond, .halo_flash, .halo_projection, .halo_ring };

pub const def:st.Def = .{ .item = .polyp, .size = 1, .mesh = .polyp, .sway = 0.4, .tall = 0.9, .grow = 6, .sap = 0.6 };

pub const Phase = enum(u8) { open, forming, formed };

pub const State = struct {
  phase:Phase = .open,
  /// seconds since the halo began forming
  t:f32 = 0,
};

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) Allocator.Error!bool {
  const self = ctx.ss.get(i);
  const h = &self.state.polyp;
  switch (h.phase) {
    .open => {
      for (0..4) |k| if (!halo.active(ctx.plants, ctx.w, halo.pointAt(self.x, self.y, k))) return false;
      h.phase = .forming;
      h.t = 0;
      ctx.g.say(txt.s.msg.halo_forms, .{});
      return true;
    },
    .forming => {
      h.t += dt;
      if (h.t < halo.FORM) return true;
      h.phase = .formed;
      // they meet: the blooms are consumed into the diamond
      const x = self.x;
      const y = self.y;
      const seed = self.seed;
      for (0..4) |k| {
        const at = halo.pointAt(x, y, k);
        const id = ctx.plants.at(ctx.w, at[0], at[1]) orelse continue;
        if (species.get(ctx.plants.list.items(.sp)[id.idx()]).radiance > 0) ctx.plants.remove(ctx.w, id);
      }
      // decision: a diamond already floating over the polyp (put there by
      // hand) takes the halo's place; no second one is formed
      if (try ctx.ss.spawnChild(ctx.gpa, ctx.w, i, .{ .x = x, .y = y, .kind = .diamond, .seed = seed })) |d| {
        // it is born whole (no growing in), its light still the blooms'
        ctx.ss.get(d).state.diamond.light = @splat(1);
      }
      ctx.g.say(txt.s.msg.diamond_forms, .{});
      ctx.g.discover(.diamond);
      return true;
    },
    .formed => return false,
  }
}

/// the ring's disc while the halo forms (the diamond holds it after).
pub fn field(s:*const st.Structure) ?Field {
  if (s.state.polyp.phase != .forming) return null;
  return .{ .x = s.x, .y = s.y, .radius = m.f(halo.R) };
}

/// a bloom on one of a forming halo's points is drawn in to the ring's heart,
/// where the blooms' cross of beams meets (the GPU spirals it there).
pub fn hold(s:*const st.Structure, wx:i32, wy:i32) ?st.Hold {
  const h = &s.state.polyp;
  if (h.phase != .forming) return null;
  for (0..4) |k| {
    const at = halo.pointAt(s.x, s.y, k);
    if (at[0] == wx and at[1] == wy) return .{ .k = h.t / halo.FORM, .seat = halo.HOVER };
  }
  return null;
}

/// while the halo forms: the diamond gathering at the ring's heart, its
/// projection and ring.
pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, _:f32) Allocator.Error!void {
  const h = &s.state.polyp;
  if (h.phase != .forming) return;
  try halo.draw(out, s.seed, ctr + m.v3(0, halo.HOVER, 0), ctr, h.t / halo.FORM, @splat(1));
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  switch (s.state.polyp.phase) {
    .open => _ = try d.print(x, y, style.text_body, style.dim, txt.s.describe.halo_open, .{halo.R}),
    .forming => _ = try d.text(x, y, style.text_body, style.gold, txt.s.describe.halo_forming),
    .formed => _ = try d.text(x, y, style.text_body, style.dim, txt.s.describe.halo_formed),
  }
}

test "four grown blooms on a polyp's points form a halo; the diamond it leaves powers further and can be studied" {
  const testing = std.testing;
  const gpa = testing.allocator;
  const ck = lib.ck;
  const World = lib.world.World;
  const Plants = lib.plants.Plants;
  const Ecology = lib.ecology.Ecology;
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
  // a vesper inside the ring and one outside it (inside the diamond's
  // reach), both beyond every point's bloom field
  try testing.expect(try plants.place(gpa, &w, px - 1, py - 1, .vesper, 0.1));
  try testing.expect(try plants.place(gpa, &w, px + 4, py + 4, .vesper, 0.2));
  const run = struct {
    fn for_(e:*Ecology, p:*Plants, ww:*World, s:*st.Structures, gg:*prog.Progression, f:*std.ArrayList(Field), secs:f32) !void {
      const dt:f32 = 1.0 / 60.0;
      var t:f32 = 0;
      while (t < secs) : (t += dt) {
        try st.fields(s, testing.allocator, f);
        _ = try e.tick(testing.allocator, p, ww, .{ .fields = f.items }, dt);
        try s.tick(testing.allocator, ww, p, gg, dt);
      }
    }
  };
  const bloom = struct {
    fn at(p:*Plants, ww:*World, x:i32, y:i32) !void {
      try testing.expect(try p.placeEx(testing.allocator, ww, x, y, .{ .x = x, .y = y, .chunk = undefined, .tile = undefined, .sp = .bloom, .seed = 0, .growth = 1, .mana = 10 }));
    }
  };
  const powered = struct {
    fn at(e:*const Ecology, p:*const Plants, ww:*const World, x:i32, y:i32) bool {
      return e.radiance.powered.items[p.at(ww, x, y).?.idx()];
    }
  };
  const id = ss.at(&w, px, py).?;
  // three points: nothing happens, and the vesper inside has no radiance
  for (halo.POINTS[0..3]) |k| try bloom.at(&plants, &w, px + k[0] * halo.R, py + k[1] * halo.R);
  try run.for_(&eco, &plants, &w, &ss, &g, &fl, 0.5);
  try testing.expectEqual(Phase.open, ss.get(id).state.polyp.phase);
  try testing.expect(!powered.at(&eco, &plants, &w, px - 1, py - 1));
  // the fourth: the halo forms, and its ring powers its disc at once
  try bloom.at(&plants, &w, px + halo.POINTS[3][0] * halo.R, py + halo.POINTS[3][1] * halo.R);
  try run.for_(&eco, &plants, &w, &ss, &g, &fl, 0.1);
  try testing.expectEqual(Phase.forming, ss.get(id).state.polyp.phase);
  try testing.expect(powered.at(&eco, &plants, &w, px - 1, py - 1));
  try testing.expect(!powered.at(&eco, &plants, &w, px + 4, py + 4));
  const early = hold(ss.get(id), px + halo.R, py).?;
  try testing.expect(early.k > 0 and early.k < 0.05);
  try testing.expectEqual(prog.Status.locked, g.status(.celestial_defragmentation));
  // they meet: consumed into a diamond, a structure of its own floating over
  // the polyp, which stays as it was; its field reaches further
  try run.for_(&eco, &plants, &w, &ss, &g, &fl, halo.FORM + 0.5);
  try testing.expectEqual(Phase.formed, ss.get(id).state.polyp.phase);
  try testing.expectEqual(st.Kind.polyp, ss.get(w.occAt(px, py).asStructure().?).kind());
  const dia = ss.at(&w, px, py).?;
  try testing.expectEqual(st.Kind.diamond, ss.get(dia).kind());
  try testing.expectEqual(id, ss.getParent(dia).?);
  for (halo.POINTS) |k| try testing.expect(plants.at(&w, px + k[0] * halo.R, py + k[1] * halo.R) == null);
  try testing.expect(powered.at(&eco, &plants, &w, px - 1, py - 1));
  try testing.expect(powered.at(&eco, &plants, &w, px + 4, py + 4));
  // and the diamond's lattice can now be studied
  try testing.expectEqual(prog.Status.open, g.status(.celestial_defragmentation));
  // it never forms again; the empty points' arcs dim but stay
  try run.for_(&eco, &plants, &w, &ss, &g, &fl, 10);
  try testing.expectEqual(@as(usize, 2), ss.list.items.len);
  for (ss.get(dia).state.diamond.light) |l| try testing.expect(l < 0.5 and l >= halo.DIM);
  // uprooting the diamond leaves the polyp
  _ = ss.remove(&w, dia);
  try testing.expectEqual(st.Kind.polyp, ss.get(ss.at(&w, px, py).?).kind());
}

/// its bulb: a pearl bud on a sprout, threads of light running out to four
/// blooms on a ring round it (it calls the halo).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const heart:icon_kit.P = .{0, 0.6};
  const points = [_]icon_kit.P{.{-0.5, 0.6}, .{0, 0.86}, .{0.5, 0.6}, .{0, 0.38}};
  for (points) |q| try ic.stem(.{heart, heart, q, q}, 0.06, icon_thread);
  try ic.stem(.{.{0, icon_kit.TOP}, .{0.08, 0.3}, .{-0.06, 0.45}, heart}, 0.1, icon_kit.stem_col);
  try ic.glow(heart, 0.25, icon_glow);
  try ic.bud(heart, 0.12, icon_pearl, 0.6);
  for (points, 0..) |q, i| {
    const lit = 0.5 + 0.5 * @sin(ic.t * 2 + m.f(i) * 1.6);
    try ic.bud(q, 0.11, icon_bloom, lit);
  }
  try ic.coat(col);
}
const icon_thread:Color = .{255, 236, 180, 200};
const icon_pearl:Color = .{235, 205, 230, 255};
const icon_bloom:Color = .{140, 255, 215, 255};
const icon_glow:Color = .{255, 236, 200, 80};
