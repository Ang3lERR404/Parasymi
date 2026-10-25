//! mesh: ROOT-DIGGER. the central knot: a sap gourd at 40%, sunk into a
//! woody collar the roots (`root`, emitted per root) grow out of.
//! It grows on a hidden stem rising through the collar into the gourd
//! (gfx/growth.zig): the collar swells round its foot, then the gourd fills
//! and its basket wraps up it as the sap cache's does; the roots spread
//! out of the collar meanwhile, over the first share of its growth.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const sap_cache = @import("sap_cache.zig");
const growth = @import("../growth.zig");

const v3 = m.v3;

/// the gourd's size, and how far up it sits
const GOURD:f32 = 0.4;
const GOURD_LIFT:f32 = 0.06;
/// the collar, in the knot's own space
const COLLAR_AT = v3(0, 0.05, 0);
const COLLAR_R = v3(0.17, 0.09, 0.17);
/// where along the stem the collar has swelled round it
const COLLAR_U:f32 = 0.2;

/// a point of the knot's space in the gourd's (built at full size, then
/// shrunk into place with everything on it)
fn local(p:m.V3) m.V3 { return (p - v3(0, GOURD_LIFT, 0)) / m.splat3(GOURD); }

pub fn build(b:*mg.Builder) Allocator.Error!void {
  const start = b.mark();
  var k = growth.Skeleton.begin(b);
  // the stem: up from the ground through the collar to the gourd's neck
  const stem = k.trunk(&.{local(v3(0, -0.02, 0)), local(COLLAR_AT), v3(0.01, sap_cache.POD_AT[1], -0.01), sap_cache.NECK}, .{.pace = sap_cache.STEM_PACE});
  const c = b.mark();
  try mg.ellipsoid(b, .{.center = local(COLLAR_AT), .radii = COLLAR_R / m.splat3(GOURD), .col = pal.core, .rings = 6, .segs = 10, .t = 0.2});
  try k.on(b, c, stem, 0, .{.from = local(COLLAR_AT), .span = k.get(stem).time * COLLAR_U});
  try sap_cache.gourd(b, 1, .{.k = &k, .id = stem, .u = 1});
  k.finish(b);
  b.xform(start, m.chain(&.{m.translate(v3(0, GOURD_LIFT, 0)), m.scale3(m.splat3(GOURD))}));
}

/// mesh: DIGGER ROOT. one thick grown root from the knot outward along +X,
/// arching down into the ground; instances fan around the knot and stretch
/// along X toward the node being worked. It grows out along its own spline
/// over the first `1 - TAIL` of the digger's growth (emitted with it).
pub const root = struct {
  /// the share of the digger's growth after its roots are out
  const TAIL:f32 = 0.35;
  pub fn build(b:*mg.Builder) Allocator.Error!void {
    var k = growth.Skeleton.begin(b);
    k.tail = TAIL;
    const g:mg.Growth = .{
      .start = v3(0.06, 0.1, 0), .direction = m.norm(v3(1, -0.32, 0)), .length = 0.46,
      .wobble = 0.1, .curl = 0, .taper = 0.4, .seed = 0xD16,
    };
    const r = k.vine(null, 0, g, 6, .{});
    const s = b.mark();
    try mg.vine(b, g, 6, 16, 0.065, pal.core, .stem, 6, 0.2, 1);
    try k.along(b, s, r);
    k.finish(b);
  }
};
