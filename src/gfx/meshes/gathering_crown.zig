//! mesh: GATHERING CROWN. a symbiote that gathers for the garden: a rosette
//! of broad leaves on a woven root mat, a short woven stalk opening into a
//! crown of cupped petals round a pod of resin sap where what it gathers
//! hangs (emitted, `belly_lump`s), stamens standing round the pod's crown.
//! Its roots out to the plants round it are its own (`Root(n)`, emitted
//! one per plant, by how far away the plant stands).
//! It grows on a hidden stalk (gfx/growth.zig): the roots spread with it,
//! the rosette unfolds leaf by leaf, the stalk rises, the pod swells and
//! the crown opens petal by petal round it, the stamens last.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const engine = lib.engine;
const m = engine.core.math;
const mg = lib.meshgen;
const pal = lib.palette;
const color = engine.core.color;
const kit = lib.structure_kit;
const growth = lib.growth;
const conduit = lib.conduit;

const V3 = m.V3;
const v3 = m.v3;

pub const CROWN = v3(0, 0.3, 0);
/// the pod at the crown's heart, where what it gathers hangs
pub const POD_AT = CROWN + v3(0, 0.07, 0);
pub const POD_R = v3(0.1, 0.09, 0.1);
const PETALS = 8;
const PETAL_STAGGER:f32 = 0.025;
/// the distances its roots reach to (tiles), each a mesh of its own: the
/// plants on the 5x5 tiles round it
pub const REACHES = [_]f32{1, m.sqrt2, 2, 2.2360680, 2 * m.sqrt2};
const warm = color.rgb(0.95, 0.72, 0.36).toRgba8(255);
const blush = color.rgb(0.98, 0.86, 0.6).toRgba8(255);

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var k = growth.Skeleton.begin(b);
  const stalk = k.trunk(&.{v3(0, -0.03, 0), v3(0.01, 0.12, -0.008), v3(-0.006, 0.22, 0.004), CROWN}, .{.pace = 1.6});
  try kit.rootMat(b, 6, 0.45, 0.045, 0x6C01, .{.k = &k, .id = stalk});
  try kit.footLeaves(b, 7, 0.12, 0.36, 0.15, 0x6C02, .{.k = &k, .id = stalk, .u = 0.08});
  {
    var sp:[growth.RES]V3 = undefined;
    var ts:[growth.RES]f32 = undefined;
    var rs:[growth.RES]f32 = undefined;
    k.path(stalk, 0, 1, &sp);
    for (&ts, &rs, 0..) |*t, *r, i| {
      const u = m.ratio(i, growth.RES - 1);
      t.* = u * 0.6;
      r.* = 0.045 * (0.8 + 0.45 * @exp(-u * 6) + 0.35 * @exp(-(1 - u) * 6));
    }
    const s = b.mark();
    try mg.braid(b, &sp, &ts, &rs, 4, 2.4, pal.STRAND_WOBBLE, 0x6C03, pal.core, pal.vine);
    try k.along(b, s, stalk);
  }
  // the pod, swelling out of the stalk's top, the crown opening round it
  const pod = b.mark();
  try kit.resinPod(b, POD_AT, POD_R, 10, 14);
  try k.on(b, pod, stalk, 1, .{.from = CROWN});
  for (0..PETALS) |i| {
    const a = (m.f(i) + 0.5 * m.f(i % 2)) / PETALS * m.tau;
    const s = b.mark();
    try mg.petal(b, .{
      .base = CROWN, .out = v3(@cos(a), 0, @sin(a)), .len = 0.2, .width = 0.085,
      .rise = 1.15, .flare = 0.9, .cup = 0.5, .col = pal.leaf_dark, .tip = if (i % 2 == 0) warm else blush, .part = .leaf,
    });
    try k.on(b, s, stalk, 1, .{.from = CROWN, .delay = 0.03 + PETAL_STAGGER * m.f(i)});
  }
  const sta = b.mark();
  try mg.stamens(b, .{
    .heart = POD_AT + v3(0, POD_R[1] * 0.6, 0), .axis = v3(0, 1, 0), .n = 9, .len = 0.11, .r = 0.004, .anther = 0.022,
    .lean = 0.55, .arch = 0.5, .col = pal.leaf_lite, .seed = 0x6C04,
  });
  try k.on(b, sta, stalk, 1, .{.from = POD_AT, .delay = 0.06 + PETAL_STAGGER * PETALS});
  k.finish(b);
}

/// mesh: GATHERING ROOT. a root from under the crown along +X to a plant
/// `REACHES[n]` tiles out, woven as a conduit's side root (`conduit.arch`):
/// it comes up beside the crown, arches low over the ground and digs in at
/// the plant's foot, splitting into rootlets round it. It grows along its
/// own spline by how far it has reached (emitted with that as `grown`), the
/// rootlets last, and withers back down it.
pub fn Root(comptime n:usize) type {
  return struct {
    const REACH = REACHES[n] - 0.22;
    pub fn build(b:*mg.Builder) Allocator.Error!void {
      var k = growth.Skeleton.begin(b);
      const spine = try conduit.arch(b, &k, .{
        .from = 0.06, .to = REACH, .peak = 0.07 + 0.025 * m.f(n), .depth = 0.06, .core_r = 0.017, .strands = 2,
        .turns = 1.2 + 0.5 * REACHES[n], .core = .stem, .leaves = if (n < 2) &.{2} else &.{2, 3}, .runners = false, .seed = 0x6C10 +% n * 7,
      });
      const end = v3(REACH, -0.02, 0);
      for ([_]f32{-0.9, -0.1, 0.8}, 0..) |a, i| {
        const s = b.mark();
        try kit.rootlet(b, end, m.norm(v3(@cos(a) * 0.8, -0.45, @sin(a) * 0.8)), 0.2, 0.012, 0x6C20 +% n * 11 +% i * 29);
        try k.on(b, s, spine, 1, .{.from = end, .delay = 0.04 * m.f(i)});
      }
      k.finish(b);
    }
  };
}
