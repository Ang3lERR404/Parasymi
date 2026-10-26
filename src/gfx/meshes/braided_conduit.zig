//! mesh: BRAIDED CONDUIT. a root conduit grown dense: four sapwood cores,
//! one lane each (part `.core`: what a lane carries swells and tints its
//! own core as it passes, part.vert), twisting round one another along the
//! same arch a conduit makes (up out of the soil at its back edge, over,
//! down in at its front), bound in a looser weave of smaller roots with
//! leaves over its top and soil heaped where it breaks the ground.
//! `wrap` (and `wrap_left`/`wrap_right`, turning in from the tile's +Z / -Z
//! edge) is the weave, leaves and soil; `Lane(turn, i)` the cores, each a
//! mesh of its own so each carries its own item; the bare `build` the whole
//! of a straight one, its preview.
//! Every piece grows along one growth spline per arch, the same in each
//! (gfx/growth.zig): the cores and weave dig on together.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const engine = lib.engine;
const m = engine.core.math;
const mg = lib.meshgen;
const pal = lib.palette;
const color = engine.core.color;
const noise = engine.core.noise;
const growth = lib.growth;
const conduit = lib.conduit;

const V3 = m.V3;

pub const LANES = 4;
/// rings along a core
const RES = 48;
/// how far each core lies off the arch's spine, its girth, and how many
/// turns the four make round one another over the arch
const BUNDLE:f32 = 0.034;
const LANE_R:f32 = 0.019;
const TWIST:f32 = 1.1;
/// the binding: so few strands, wound so loosely, that the lanes show
/// between them; its girth clears the cores' however its knots run
const BIND_R:f32 = 0.066;
/// each lane's own grain, so the four read apart
const LANE_TONE = [LANES]f32{0.25, 0.55, 0.8, 0.4};

/// the arch a braided conduit makes turning `turn` (as a conduit's), the
/// weave's alone (no core: the lanes are its cores)
fn archOf(turn:f32) conduit.Arch {
  const seed:u64 = if (turn == 0) 0xB0D else if (turn > 0) 0xB1D else 0xB2D;
  return .{
    .turn = turn, .peak = conduit.PEAK * 1.12, .core_r = BIND_R, .core = null,
    .strands = 2, .turns = 1.4, .leaves = &.{3, 2, 3, 2, 3, 3}, .seed = seed,
  };
}

pub fn build(b:*mg.Builder) Allocator.Error!void {
  try wrapped(b, 0);
  for (0..LANES) |i| try lane(b, 0, i);
}

pub const wrap = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void { try wrapped(b, 0); }
};
pub const wrap_left = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void { try wrapped(b, 1); }
};
pub const wrap_right = struct {
  pub fn build(b:*mg.Builder) Allocator.Error!void { try wrapped(b, -1); }
};

/// lane `i`'s core of the arch turning `turn`
pub fn Lane(comptime turn:f32, comptime i:usize) type {
  return struct {
    pub fn build(b:*mg.Builder) Allocator.Error!void { try lane(b, turn, i); }
  };
}

fn wrapped(b:*mg.Builder, turn:f32) Allocator.Error!void {
  var k = growth.Skeleton.begin(b);
  _ = try conduit.arch(b, &k, archOf(turn));
  k.finish(b);
}

/// one lane's core: round the arch's spine at its own quarter, twisting
/// with the others, flaring with them where they break the ground; tu.x 0
/// where it comes up .. 1 where it goes down, as a conduit's core
fn lane(b:*mg.Builder, turn:f32, i:usize) Allocator.Error!void {
  const a = archOf(turn);
  const ctrl = conduit.spineCtrl(a);
  var k = growth.Skeleton.begin(b);
  const spine = k.trunk(&ctrl, .{});
  var sp:[RES]V3 = undefined;
  m.splineResample(&ctrl, &sp);
  var fn_:[RES]V3 = undefined;
  var fb:[RES]V3 = undefined;
  mg.transport(&sp, &fn_, &fb);
  var path:[RES]V3 = undefined;
  var ts:[RES]f32 = undefined;
  var rs:[RES]f32 = undefined;
  var cols:[RES]color.Rgba8 = undefined;
  const seed = a.seed +% i * 31;
  for (&path, &ts, &rs, &cols, 0..) |*p, *t, *r, *c, j| {
    const u = m.ratio(j, RES - 1);
    const y = sp[j][1];
    const flare = conduit.FLARE * @exp(-y * y / 0.0012);
    const th = m.ratio(i, LANES) * m.tau + TWIST * m.tau * u;
    p.* = sp[j] + (fn_[j] * m.splat3(@cos(th)) + fb[j] * m.splat3(@sin(th))) * m.splat3(BUNDLE * (1 + 0.6 * flare));
    t.* = u;
    r.* = LANE_R * (1 + 0.12 * noise.grad(seed, u * 6, 0.5) + 0.5 * flare);
    c.* = color.mix(pal.sapwood_dark, pal.sapwood, m.clamp01(LANE_TONE[i] + 1.5 * noise.grad(seed +% 1, u * 9, 1.5)));
  }
  const s = b.mark();
  try b.tubeC(&path, &ts, &rs, &cols, null, .core, 7);
  try k.along(b, s, spine);
  k.finish(b);
}
