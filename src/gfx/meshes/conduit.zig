//! mesh: CONDUIT. a living root crossing its tile along +X ("forward"):
//! it surfaces in a gnarled hump, sinks half into the soil and comes up
//! again at the far edge, where the next conduit's root carries on (every
//! conduit's ends meet at the same height, girth and heading). Rootlets
//! fork off it into the ground, and a sap knot swells on the hump.
//! Nothing on it moves, so a chain of conduits stays one root.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");
const noise = @import("../../core/noise.zig");
const kit = @import("structure_kit.zig");

const V3 = m.V3;
const v3 = m.v3;

/// the root's girth where it meets its neighbours
pub const END_R:f32 = 0.048;
const RES = 28;

/// the root's height above the ground at `u` (0 its back edge .. 1 its
/// front edge): a hump, then a dip under the soil. Level and half buried
/// at both ends, so chained roots join without a kink.
pub fn rise(u:f32) f32 { return 0.035 + 0.11 * wave(u); }

/// sin(2 pi u) eased to a flat start and end: rises over the first half,
/// dips over the second
fn wave(u:f32) f32 { return @sin(m.tau * u) * 0.5 * (1 - @cos(m.tau * u)); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var spine:[RES]V3 = undefined;
  var ts:[RES]f32 = undefined;
  var rs:[RES]f32 = undefined;
  var cols:[RES]color.Rgba8 = undefined;
  for (&spine, &ts, &rs, &cols, 0..) |*p, *t, *r, *c, i| {
    const u = m.ratio(i, RES - 1);
    p.* = v3(u - 0.5, rise(u), 0.2 * wave(u) * @sin(m.pi * u));
    t.* = u;
    // gnarled: swelling over the hump, pinched in the soil, knotted here
    // and there; the same girth at both ends
    const swell = 0.25 * @max(wave(u), 0) - 0.12 * @max(-wave(u), 0);
    const gnarl = 0.2 * noise.grad(0xC0D, u * 7, 0.5) * @sin(m.pi * u);
    r.* = END_R * (1 + swell + gnarl);
    // bark in rough bands, darker where it is pinched
    c.* = color.mix(pal.root_bark, pal.root_lite, m.clamp01(0.5 + 3 * noise.grad(0xC0E, u * 11, 2.5) + swell));
  }
  try b.tubeC(&spine, &ts, &rs, &cols, null, .stem, 7);

  // rootlets: forking off the main root and down into the soil, on
  // alternating sides
  const roots = [_]struct { u:f32, side:f32, len:f32 }{
    .{.u = 0.16, .side = 1, .len = 0.3}, .{.u = 0.36, .side = -1, .len = 0.36},
    .{.u = 0.62, .side = 1, .len = 0.26}, .{.u = 0.84, .side = -1, .len = 0.32},
  };
  for (roots, 0..) |rt, i| {
    const k = m.floorTo(usize, rt.u * (RES - 1));
    const from = spine[k];
    try kit.rootlet(b, from, m.norm(v3(0.35, -0.55, rt.side)), rt.len, rs[k] * 0.5, 0xC0D0 +% i * 37);
  }

  // the sap knot swelling on the hump
  const kk = m.floorTo(usize, 0.27 * (RES - 1));
  try mg.ellipsoid(b, .{.center = spine[kk] + v3(0, rs[kk] * 0.75, 0), .radii = v3(0.05, 0.035, 0.045), .col = pal.sap, .part = .bloom, .rings = 5, .segs = 8, .t = 0.3});
}
