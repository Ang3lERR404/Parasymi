//! DIAMOND: where a halo's four blooms became one, floating high over the
//! polyp at its ring's heart; or, once Celestial Defragmentation is known,
//! woven and put down over any dry tile. Small and still, a cut crystal that
//! only catches light. It fragments that light into the halo's ring around
//! it (see `halo.zig`), and holds a field of celestial energy wider than it.
//! Put down by hand, it gathers from its shards as it grows in; grown, or
//! born of a halo, it forms with a flash of light. Blooms sown on the
//! ring's four points brighten the arcs beside them. (The world event will
//! start from it.)
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const Field = @import("../../sim/ecology.zig").Field;
const st = @import("../structures.zig");
const icon_kit = @import("../icon.zig");
const txt = @import("../text.zig");
const prog = @import("../progression.zig");
const style = @import("../style.zig");
const Parts = @import("../parts.zig").Parts;
const Draw = @import("../../ui/draw.zig").Draw;
const Color = @import("../../ui/draw.zig").Color;
const halo = @import("halo.zig");

// it floats as high as the blooms hang, at the heart of its ring, over
// whatever is under it
pub const def:st.Def = .{ .item = .diamond, .size = 1, .mesh = .halo_diamond, .floating = true, .hover = halo.HOVER, .bare = true, .grow = 8 };

pub const State = struct {
  /// seconds since it formed (grown)
  t:f32 = 0,
  /// per point of its ring: how brightly the arcs beside it shine
  light:[4]f32 = @splat(halo.DIM),
};

pub fn tick(ctx:st.Ctx, i:st.Id, dt:f32) bool {
  const self = ctx.ss.get(i);
  const d = &self.state.diamond;
  d.t = @min(d.t + dt, halo.FORM + halo.FLASH);
  halo.relight(&d.light, ctx.plants, ctx.w, self.x, self.y, dt);
  return false;
}

pub fn field(s:*const st.Structure) ?Field {
  if (s.grown < 1) return null;
  return .{ .x = s.x, .y = s.y, .radius = halo.DIAMOND_R };
}

/// how far along its halo is: growing in, it gathers as the halo's blooms
/// would bring it together; formed, past 1
fn along(s:*const st.Structure) f32 {
  return if (s.grown < 1) s.grown else 1 + s.state.diamond.t / halo.FORM;
}

pub fn emit(s:*const st.Structure, out:*Parts, ctr:m.V3, _:f32) Allocator.Error!void {
  try halo.draw(out, s.seed, ctr + m.v3(0, def.hover, 0), ctr, along(s), s.state.diamond.light);
}

pub fn describe(s:*const st.Structure, d:*Draw, _:*const prog.Progression, x:f32, y:f32) Allocator.Error!void {
  _ = try d.print(x, y, style.text_body, style.gold, txt.s.describe.diamond, .{halo.lit(s.state.diamond.light)});
}

/// its bulb: a low sprout, and over it, floating free on a thread of light,
/// the cut diamond: shards spiral in to it, and it splits light into needle
/// rays out to a tilted ring, a spectrum across its width (red inside),
/// motes running round it (it gathers, floats, and projects the halo).
pub fn icon(ic:icon_kit.Icon, col:Color) Allocator.Error!void {
  const bob = ICON_BOB * @sin(ic.t * 1.3 + ic.phase * 6);
  const heart:icon_kit.P = .{0, 0.52 + bob};
  const tip:icon_kit.P = .{0, 0.24};
  try ic.stem(.{.{0, icon_kit.TOP}, .{-0.04, 0.16}, .{0.04, 0.24}, tip}, 0.09, icon_kit.stem_col);
  try ic.leaf(tip, 0.75, 0.24, 0.14, icon_kit.sprout, 0.9);
  try ic.leaf(tip, m.pi - 0.75, 0.22, 0.13, icon_kit.sprout, 0.9);
  try ic.stem(.{tip, .{0.03, 0.4}, .{-0.03, 0.46}, .{0, heart[1] - 0.1}}, 0.03, icon_thread);
  try ring(ic, heart, true);
  // needle rays of split light running level out to the ring
  for (0..ICON_RAYS) |i| {
    const a = ic.t * ICON_TURN + m.tau * m.ratio(i, ICON_RAYS);
    const out = ringAt(heart, a, ICON_RING_R);
    const pulse = 0.5 + 0.5 * @sin(ic.t * 3 + m.f(i) * 2.1 + ic.phase * 5);
    try ic.stem(.{heart, heart, out, out}, 0.025, fade(icon_band[i % icon_band.len], pulse));
  }
  // shards gathering into it from a spiral, one after another
  for (0..ICON_SHARDS) |i| {
    const k = @mod(ic.t * ICON_GATHER + ic.phase + m.ratio(i, ICON_SHARDS), 1);
    const a = m.tau * (m.ratio(i, ICON_SHARDS) + 1.25 * k);
    const r = 0.5 * (1 - k) * (1 - k);
    const at:icon_kit.P = .{heart[0] + r * @cos(a), heart[1] + r * @sin(a) * 0.7};
    try ic.gem(at, 0.07 * (1 - 0.5 * k), fade(icon_gem, @sin(k * m.pi)));
  }
  const flare = 0.85 + 0.15 * @sin(ic.t * 2.6 + ic.phase * 3);
  try ic.glow(heart, 0.3 * flare, icon_glow);
  try ic.gem(heart, 0.24, icon_gem);
  try ring(ic, heart, false);
  try ic.coat(col);
}

/// the point at bearing `a` on a ring of radius `r` round `c`, tilted away
/// (squashed in y; its far half is the upper one).
fn ringAt(c:icon_kit.P, a:f32, r:f32) icon_kit.P {
  return .{c[0] + r * @cos(a), c[1] + r * @sin(a) * ICON_TILT};
}

/// the halo's ring round `c`, its far half (behind the diamond) or near
/// half: a band per colour, red innermost, and motes running round.
fn ring(ic:icon_kit.Icon, c:icon_kit.P, far:bool) Allocator.Error!void {
  for (icon_band, 0..) |band, b| {
    const r = ICON_RING_R + ICON_BAND_W * (m.f(b) - 1);
    for (0..ICON_SEGS) |i| {
      const a0 = m.tau * m.ratio(i, ICON_SEGS);
      const a1 = m.tau * m.ratio(i + 1, ICON_SEGS);
      if ((@sin((a0 + a1) / 2) > 0) != far) continue;
      const p = ringAt(c, a0, r);
      const q = ringAt(c, a1, r);
      try ic.stem(.{p, p, q, q}, ICON_BAND_W, band);
    }
  }
  for (0..ICON_MOTES) |i| {
    const a = ic.t * ICON_RUN + m.tau * m.ratio(i, ICON_MOTES) + ic.phase;
    if ((@sin(a) > 0) != far) continue;
    try ic.bud(ringAt(c, a, ICON_RING_R), 0.035, icon_mote, 1);
  }
}

fn fade(c:Color, k:f32) Color {
  return .{c[0], c[1], c[2], m.unorm8(m.ratio(c[3], 255) * k)};
}

const ICON_RING_R:f32 = 0.42;
const ICON_BAND_W:f32 = 0.05;
const ICON_TILT:f32 = 0.5;
const ICON_SEGS = 24;
const ICON_RAYS = 6;
const ICON_SHARDS = 3;
const ICON_MOTES = 2;
const ICON_BOB:f32 = 0.03;
/// radians a second the rays and motes turn, shards gathered a second
const ICON_TURN:f32 = 0.4;
const ICON_RUN:f32 = 1.1;
const ICON_GATHER:f32 = 0.35;
/// the ring's spectrum, inside out
const icon_band = [3]Color{.{255, 110, 100, 190}, .{240, 230, 120, 170}, .{120, 170, 255, 160}};
const icon_gem:Color = .{255, 245, 235, 255};
const icon_glow:Color = .{255, 240, 220, 45};
const icon_thread:Color = .{255, 240, 215, 140};
const icon_mote:Color = .{255, 255, 245, 255};
