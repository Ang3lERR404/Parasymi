//! the garden's meshes: every plant grown from its species genome out of the
//! engine's primitives (engine gfx/meshgen.zig: tubes, lofts, vines, braids)
//! and the garden's own (blades, laminae, petals, stamens, flowers).
const lib = @import("../lib.zig");
const std = lib.std;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const engine = lib.engine;
const m = engine.core.math;
const Rng = engine.core.rng.Rng;
const vertex = lib.vertex;
const species = lib.species;
const color = engine.core.color;
const noise = engine.core.noise;
const parasite_kit = lib.parasite_kit;
const convergence_kit = lib.convergence_kit;
const radiant_kit = lib.radiant_kit;
const structure_kit = lib.structure_kit;

const V3 = m.V3;
const PV = vertex.Mesh;
pub const BLADE_SEGS = 8;
/// mesh variants grown per species, so neighbouring plants differ in shape.
pub const VARIANTS = 4;

/// the engine's builder and primitives, writing the garden's vertex roles
pub const gen = engine.gfx.meshgen.Mesher(vertex.Part, .stem);
pub const Builder = gen.Builder;
pub const vine = gen.vine;
pub const braid = gen.braid;
pub const braidTurned = gen.braidTurned;
pub const braidAround = gen.braidAround;
pub const loft = gen.loft;
pub const patch = gen.patch;
pub const bands = gen.bands;
pub const Ellipsoid = gen.Ellipsoid;
pub const ellipsoid = gen.ellipsoid;
pub const bundle = gen.bundle;
const eg = engine.gfx.meshgen;
pub const LODS = eg.LODS;
pub const LOD_AT = eg.LOD_AT;
pub const lodAt = eg.lodAt;
pub const stride = eg.stride;
pub const BRAID_CORE = eg.BRAID_CORE;
pub const BRAID_STRAND = eg.BRAID_STRAND;
pub const BRAID_OFF = eg.BRAID_OFF;
pub const STRAND_SALT = eg.STRAND_SALT;
pub const strandTurn = eg.strandTurn;
pub const strandSwell = eg.strandSwell;
pub const transport = eg.transport;
pub const Growth = eg.Growth;
pub const grow = eg.grow;
pub const growthPath = eg.growthPath;
pub const taperRadii = eg.taperRadii;
const MAX_SPINE = m.MAX_SPLINE;

/// curved blade (leaf/petal). `dir` horizontal outward, droops along its length.
pub fn blade(b:*Builder, base:V3, dir:V3, len:f32, width:f32, droop:f32, col:color.Rgba8, tip:color.Rgba8, t:f32, part:vertex.Part) Allocator.Error!void {
  var cs:[BLADE_SEGS + 1]V3 = undefined;
  bladeSpine(&cs, base, dir, len, droop);
  try sheet(b, &cs, m.norm(m.cross(dir, m.v3(0, 1, 0))), width, col, tip, t, part);
}

/// a blade whose midrib follows the smooth spline through `path`, its
/// width lying along `side`.
pub fn bladeAlong(b:*Builder, path:[]const V3, side:V3, width:f32, col:color.Rgba8, tip:color.Rgba8, t:f32, part:vertex.Part) Allocator.Error!void {
  var cs:[BLADE_SEGS + 1]V3 = undefined;
  m.splineResample(path, &cs);
  try sheet(b, &cs, side, width, col, tip, t, part);
}

/// the leaf along a midrib: a `lamina` (thin, bevelled at its edges,
/// a vein along its middle) with one row per point of `cs`.
fn sheet(b:*Builder, cs:*const [BLADE_SEGS + 1]V3, side:V3, width:f32, col:color.Rgba8, tip:color.Rgba8, t:f32, part:vertex.Part) Allocator.Error!void {
  const segs = BLADE_SEGS;
  var ws:[segs + 1]f32 = undefined;
  for (0..segs + 1) |i| {
    const k = m.f(i) / segs;
    ws[i] = width * @sin(k * m.pi) * (1 - 0.3 * k);
  }
  var ns:[segs + 1]V3 = undefined;
  for (0..segs + 1) |i| {
    const tan = cs[@min(i + 1, segs)] - cs[if (i == 0) 0 else i - 1];
    ns[i] = m.norm(m.cross(tan, side));
  }
  // folded along its midrib (its halves dipping to it, so it never reads
  // as a flat card), the vein running in the fold and fading to the tip
  var spine:[segs + 1]V3 = undefined;
  var sides:[segs + 1]V3 = undefined;
  var face:[segs + 1]V3 = undefined;
  var dish:[segs + 1]f32 = undefined;
  var vein:[segs + 1]f32 = undefined;
  var cols:[segs + 1]color.Rgba8 = undefined;
  for (0..segs + 1) |i| {
    const k = m.f(i) / segs;
    spine[i] = cs[i] + ns[i] * m.splat3(ws[i] * 0.25);
    sides[i] = side;
    face[i] = -ns[i];
    dish[i] = ws[i] * 0.25;
    vein[i] = LAMINA_THICK * width * 0.8 * (1 - 0.7 * k);
    cols[i] = color.mix(col, tip, k);
  }
  try lamina(b, .{.spine = &spine, .side = &sides, .face = &face, .width = &ws, .dish = &dish, .bow = 1, .broad = width, .vein = &vein, .col = &cols, .t = t, .part = part});
}

/// the midrib of a drooping blade: out along `dir`, curving by `droop`.
pub fn bladeSpine(cs:*[BLADE_SEGS + 1]V3, base:V3, dir:V3, len:f32, droop:f32) void {
  for (cs, 0..) |*c, i| {
    const k = m.ratio(i, BLADE_SEGS);
    c.* = base + dir * m.splat3(len * k) + m.v3(0, len * (0.35 * k - droop * k * k), 0);
  }
}

/// half a leaf's or petal's thickness, as a share of its broadest half-width
pub const LAMINA_THICK:f32 = 0.055;
/// most rows a lamina may have
const MAX_LAMINA = 12;
/// a lamina's cross-section, once round: the face (its cupped side) edge to
/// edge with the vein's crest at its middle, round the right edge, the
/// back, round the left edge
const FACE_U = [_]f32{-1, -0.5, -0.07, 0, 0.07, 0.5, 1};
const BACK_U = [_]f32{1, 0.5, 0, -0.5, -1};
/// the edge's bevel: the angles (off the midplane) it is rounded over at
const BEVEL = [_]f32{0.9, -0.9};
const LAMINA_RING = FACE_U.len + BACK_U.len + 2 * BEVEL.len;
/// how much thinner a lamina is at its edge than along its midrib
const EDGE_THIN:f32 = 0.35;
/// the vein's colour: paler than the blade it runs through
const VEIN_PALE = color.rgb(0.9, 0.92, 0.72);

/// a leaf or petal with a body to it: its mid-surface (row i at `spine[i]`,
/// `width[i]` out each way along `side[i]`, its edges rising `dish[i]`
/// toward `face[i]`, the side it cups to; `bow` 1 folds it along the
/// midrib, 2 cups it smoothly) given a thin thickness that rounds over at
/// the edges, a small bevel catching the light. `vein` raises a midrib along
/// the face, in the fold. Rows run base to tip (tu.y); where a row closes to
/// a point the shell closes with it, so it is watertight.
pub const Lamina = struct {
  spine:[]const V3,
  side:[]const V3,
  face:[]const V3,
  width:[]const f32,
  dish:[]const f32,
  bow:f32 = 2,
  /// its broadest half-width (the thickness follows it)
  broad:f32,
  /// how far the vein rises off the face, per row
  vein:?[]const f32 = null,
  col:[]const color.Rgba8,
  t:f32,
  part:vertex.Part,
};

pub fn lamina(b:*Builder, l:Lamina) Allocator.Error!void {
  const R = l.spine.len;
  const C = LAMINA_RING;
  assert(R >= 2 and R <= MAX_LAMINA);
  var pts:[MAX_LAMINA][C]V3 = undefined;
  // each point's normal as the cross-section alone would have it: it orients
  // the sheet's own, and stands in where a row closes to a point
  var tpl:[MAX_LAMINA][C]V3 = undefined;
  var cs:[MAX_LAMINA][C]color.Rgba8 = undefined;
  const pale = VEIN_PALE.toRgba8(255);
  for (0..R) |i| {
    const w = l.width[i];
    const fc = l.face[i];
    const sd = l.side[i];
    // thin everywhere, closing to nothing where the row narrows to a point
    const half = @min(LAMINA_THICK * l.broad, 0.4 * w);
    const mid = struct {
      fn at(lm:Lamina, i_:usize, u:f32) V3 {
        return lm.spine[i_] + lm.side[i_] * m.splat3(lm.width[i_] * u) + lm.face[i_] * m.splat3(lm.dish[i_] * m.pow(f32, @abs(u), lm.bow));
      }
    }.at;
    var j:usize = 0;
    for (FACE_U) |u| {
      const rise:f32 = if (u != 0) 0 else if (l.vein) |v| @min(v[i], 0.3 * w) else 0;
      pts[i][j] = mid(l, i, u) + fc * m.splat3(half * (1 - EDGE_THIN * u * u) + rise);
      tpl[i][j] = fc;
      cs[i][j] = if (rise > 0) color.mix(l.col[i], pale, 0.35) else l.col[i];
      j += 1;
    }
    const rim = half * (1 - EDGE_THIN);
    for ([_]f32{1, -1}, 0..) |e, ei| {
      // round the right edge face to back, then the left edge back to face
      for (0..BEVEL.len) |q| {
        const a = if (ei == 0) BEVEL[q] else BEVEL[BEVEL.len - 1 - q];
        const out = sd * m.splat3(e * @cos(a)) + fc * m.splat3(@sin(a));
        pts[i][j] = mid(l, i, e) + out * m.splat3(rim);
        tpl[i][j] = out;
        cs[i][j] = l.col[i];
        j += 1;
      }
      if (ei == 1) break;
      for (BACK_U) |u| {
        pts[i][j] = mid(l, i, u) - fc * m.splat3(half * (1 - EDGE_THIN * u * u));
        tpl[i][j] = -fc;
        cs[i][j] = l.col[i];
        j += 1;
      }
    }
    assert(j == C);
  }
  // normals from the shell itself, across its rows and round its section
  var ns:[MAX_LAMINA][C]V3 = undefined;
  for (0..R) |i| for (0..C) |j| {
    const dk = pts[@min(i + 1, R - 1)][j] - pts[if (i == 0) 0 else i - 1][j];
    const du = pts[i][(j + 1) % C] - pts[i][(j + C - 1) % C];
    var n = m.cross(du, dk);
    if (m.len(n) < 1e-12) n = tpl[i][j];
    if (m.dot(n, tpl[i][j]) < 0) n = -n;
    ns[i][j] = m.norm(n);
  };
  // rows and points round the section kept at this level of detail (the
  // section closes on itself: its last kept point joins back to the first)
  var kr:[MAX_LAMINA]usize = undefined;
  var kc:[C + 1]usize = undefined;
  const nr = stride(R, b.step(), &kr);
  const nc = stride(C + 1, b.step(), &kc);
  for (0..nr - 1) |ri| for (0..nc - 1) |ci| {
    const r = [4]usize{kr[ri], kr[ri], kr[ri + 1], kr[ri + 1]};
    const c = [4]usize{kc[ci] % C, kc[ci + 1] % C, kc[ci + 1] % C, kc[ci] % C};
    for ([2][3]usize{.{0, 1, 2}, .{0, 2, 3}}) |tri| {
      var p:[3]V3 = undefined;
      var n = m.v3(0, 0, 0);
      for (tri, 0..) |v, q| {
        p[q] = pts[r[v]][c[v]];
        n += ns[r[v]][c[v]];
      }
      // front faces wind counter-clockwise seen from outside
      const order = if (m.dot(m.cross(p[1] - p[0], p[2] - p[0]), n) < 0) [3]usize{tri[0], tri[2], tri[1]} else tri;
      for (order) |v| try b.put(pts[r[v]][c[v]], ns[r[v]][c[v]], cs[r[v]][c[v]], l.t, m.ratio(r[v], R - 1), l.part);
    }
  };
}

pub const Petal = struct {
  base:V3,
  /// horizontal direction the petal faces out along (unit)
  out:V3,
  len:f32,
  /// widest half-width
  width:f32,
  /// angle above horizontal at the base, and how much it bends outward by
  /// the tip (a petal rises from the bloom's heart and flares open)
  rise:f32,
  flare:f32,
  /// how far its edges lift toward the bloom's heart (a cupped petal)
  cup:f32 = 0.4,
  col:color.Rgba8,
  tip:color.Rgba8,
  t:f32 = 1,
  part:vertex.Part = .bloom,
};

/// a flower petal: narrow at its claw, broadest past the middle and closing
/// in a rounded tip, cupped across its width, curving from upright at the
/// base to open at the tip. A `lamina` (thin, bevelled at its edges); tu.y
/// runs base to tip.
pub fn petal(b:*Builder, p:Petal) Allocator.Error!void {
  const R = 7;
  const up = m.v3(0, 1, 0);
  const side = m.norm(m.cross(up, p.out));
  var spine:[R]V3 = undefined;
  var nrm:[R]V3 = undefined;
  spine[0] = p.base;
  for (0..R) |i| {
    const k = m.ratio(i, R - 1);
    const h = p.rise - p.flare * k * k;
    const dir = p.out * m.splat3(@cos(h)) + up * m.splat3(@sin(h));
    if (i > 0) spine[i] = spine[i - 1] + dir * m.splat3(p.len / (R - 1));
    // the face toward the bloom's heart and the sky
    nrm[i] = m.norm(m.cross(side, dir));
  }
  var sides:[R]V3 = undefined;
  var ws:[R]f32 = undefined;
  var dish:[R]f32 = undefined;
  var cs:[R]color.Rgba8 = undefined;
  for (0..R) |i| {
    const k = m.ratio(i, R - 1);
    // obovate: zero at the claw, widest near two thirds, a rounded tip
    ws[i] = p.width * @sqrt(@max(@sin(m.pi * m.pow(f32, k, 1.6)), 0));
    sides[i] = side;
    dish[i] = p.cup * ws[i];
    cs[i] = color.mix(p.col, p.tip, k);
  }
  try lamina(b, .{.spine = &spine, .side = &sides, .face = &nrm, .width = &ws, .dish = &dish, .broad = p.width, .col = &cs, .t = p.t, .part = p.part});
}

/// pollen: the warm gold of an anther
pub const POLLEN = color.rgb(0.92, 0.72, 0.3);

pub const Stamens = struct {
  /// the bloom's heart and the way it faces (unit)
  heart:V3,
  axis:V3,
  n:u32,
  /// filament length and its thickest radius
  len:f32,
  r:f32,
  /// angle the filaments leave the axis at, and how much further out they
  /// arch by the tip
  lean:f32 = 0.35,
  arch:f32 = 0.55,
  /// each anther's length
  anther:f32,
  col:color.Rgba8,
  tip:color.Rgba8 = POLLEN.toRgba8(255),
  /// turns the ring of them about the axis
  spin:f32 = 0,
  t:f32 = 1,
  part:vertex.Part = .leaf,
  seed:u64 = 0,
};

/// the stamens at a flower's heart: a ring of slender filaments grown out
/// of it (Catmull-Rom, tapering to a point at both ends), leaving the
/// bloom's axis at `lean` and arching further out toward the tip, each
/// carrying a plump two-lobed anther heading on along it. tu.y runs from 0
/// at the heart to 1 at the anther, so they fold into the bud with the
/// petals and open with them. The vertex layout never depends on the sizes
/// (a confluence's growth keys pass smaller ones).
pub fn stamens(b:*Builder, s:Stamens) Allocator.Error!void {
  const N = 6;
  const RES = 10;
  const ref = if (@abs(s.axis[1]) < m.NEAR_PARALLEL) m.v3(0, 1, 0) else m.v3(1, 0, 0);
  const e1 = m.norm(m.cross(s.axis, ref));
  const e2 = m.cross(s.axis, e1);
  var rng = Rng.init(s.seed ^ 0x57A3);
  for (0..s.n) |i| {
    const a = m.ratio(i, s.n) * m.tau + s.spin + rng.range(-0.15, 0.15);
    const out = e1 * m.splat3(@cos(a)) + e2 * m.splat3(@sin(a));
    const len = s.len * rng.range(0.85, 1.1);
    const lean = s.lean + rng.range(-0.08, 0.08);
    var ctrl:[N]V3 = undefined;
    ctrl[0] = s.heart + out * m.splat3(s.r);
    for (1..N) |j| {
      const k = m.ratio(j, N - 1);
      const h = lean + s.arch * k * k;
      ctrl[j] = ctrl[j - 1] + (s.axis * m.splat3(@cos(h)) + out * m.splat3(@sin(h))) * m.splat3(len / (N - 1));
    }
    grow(&ctrl, .{.start = ctrl[0], .direction = m.norm(ctrl[N - 1] - ctrl[0]), .length = len, .wobble = 0.1, .seed = s.seed +% i * 29});
    var path:[RES]V3 = undefined;
    m.splineResample(&ctrl, &path);
    var ts:[RES]f32 = undefined;
    var rs:[RES]f32 = undefined;
    var us:[RES]f32 = undefined;
    var cs:[RES]color.Rgba8 = undefined;
    for (&ts, &rs, &us, &cs, 0..) |*t, *r, *u, *c, j| {
      const k = m.ratio(j, RES - 1);
      t.* = s.t;
      u.* = k;
      // (never below the cap threshold, so every size keeps one layout)
      r.* = @max(s.r * @sqrt(@sin(m.pi * k)), 2e-4);
      c.* = color.mix(s.col, s.tip, k * k * 0.35);
    }
    try b.tubeC(&path, &ts, &rs, &cs, &us, s.part, 4);
    // the anther: two lobes side by side, sitting on the tip and heading on
    const dir = m.norm(path[RES - 1] - path[RES - 3]);
    const lobe = s.anther * 0.2;
    const st = b.mark();
    for ([_]f32{-1, 1}) |side| {
      try ellipsoid(b, .{
        .center = m.v3(side * lobe * 0.8, s.anther * 0.25, 0), .radii = m.v3(lobe, s.anther * 0.5, lobe * 0.9),
        .col = s.tip, .part = s.part, .rings = 5, .segs = 6, .t = s.t,
      });
    }
    b.xform(st, m.chain(&.{m.translate(path[RES - 1]), m.alignY(dir), m.rotY(a)}));
    for (b.v.items[st..]) |*v| v.tu[1] = 1;
  }
}

/// grow one of a species' mesh variants from its genome. Deterministic per
/// (species, variant): the stem and tendrils are grown vines, so every
/// variant leans, wobbles and curls a little differently. A confluence's
/// variants are instead its growth keys (see `KEYS`).
pub fn plant(b:*Builder, id:species.Id, variant:u32) Allocator.Error!void {
  const def = species.get(id);
  const g = def.genome;
  const seed = @as(u64, @intFromEnum(id)) * 977 + 77;
  switch (g.form) {
    .herb => try structure_kit.plant(b, g, seed + @as(u64, variant) * 131, variant, !def.floating),
    .coil => try parasite_kit.plant(b, g, seed + @as(u64, variant) * 131),
    .drift => try drift(b, g, seed + @as(u64, variant) * 131, variant),
    .radiant => try radiant_kit.plant(b, g, seed + @as(u64, variant) * 131, variant),
    .star => try radiant_kit.star(b, g, seed + @as(u64, variant) * 131, variant),
    // a confluence's variants are its growth keys, all grown from one seed
    .confluence => try convergence_kit.confluence(b, g, seed, m.ratio(variant, KEYS - 1)),
  }
}

/// how many offshoots a variant grows, between the genome's two counts.
pub fn shootCount(g:species.Genome, rng:*Rng) u32 {
  const lo = g.shoots[0];
  const hi = @max(g.shoots[1], lo);
  return lo + rng.below(hi - lo + 1);
}

/// where an offshoot ends: its tip and heading, its smoothed path, its
/// tu.x at the stem and the tip, and the first vertex after its stem
/// (for whatever grows along it).
pub const Shoot = struct { at:V3, axis:V3, path:[SHOOT_RES]V3, t0:f32, t1:f32, leaves:usize };
pub const SHOOT_RES = 16;

/// an offshoot: a side stem grown from `k` along `spine`, leaving it toward
/// bearing `ang` at elevation `rise` and curving up toward the light as it
/// goes, tapering but never to nothing (a bud or bloom sits on its tip).
/// Its root is inside the main stem, at that stem's tu.x there (`t0`), so the two bend
/// alike; each ring is marked for `shootFold` by how far out it is.
pub fn offshoot(b:*Builder, spine:[]const V3, k:f32, t0:f32, ang:f32, len:f32, r0:f32, rise:f32, col:color.Rgba8, part:vertex.Part, seed:u64) Allocator.Error!Shoot {
  const RES = SHOOT_RES;
  var sh = shootPath(spine, k, t0, ang, len, rise, seed);
  var ts:[RES]f32 = undefined;
  var rs:[RES]f32 = undefined;
  var cs:[RES]color.Rgba8 = undefined;
  for (&ts, &rs, &cs, 0..) |*t, *r, *c, j| {
    const s = m.ratio(j, RES - 1);
    t.* = m.lerp(sh.t0, sh.t1, s);
    r.* = r0 * m.lerp(1, 0.55, s);
    c.* = col;
    c.a = m.unorm8(1 - s);
  }
  try b.tubeC(&sh.path, &ts, &rs, &cs, null, part, 5);
  sh.leaves = b.mark();
  return sh;
}

/// where an `offshoot` runs, built by the caller: its smoothed path, tip
/// and heading, its tu.x at the stem (`t0`) and the tip.
pub fn shootPath(spine:[]const V3, k:f32, t0:f32, ang:f32, len:f32, rise:f32, seed:u64) Shoot {
  const N = 8;
  const RES = SHOOT_RES;
  const root = m.alongPath(spine, k);
  const out = m.v3(@cos(ang), 0, @sin(ang));
  var ctrl:[N]V3 = undefined;
  ctrl[0] = root;
  for (1..N) |j| {
    const s = m.ratio(j, N - 1);
    // heading turns from `rise` toward upright, mostly in its outer half
    const h = m.lerp(rise, 1.35, s * s);
    ctrl[j] = ctrl[j - 1] + (out * m.splat3(@cos(h)) + m.v3(0, @sin(h), 0)) * m.splat3(len / (N - 1));
  }
  grow(&ctrl, .{.start = root, .direction = m.norm(ctrl[N - 1] - root), .length = len, .wobble = 0.12, .curl = 0.03, .seed = seed});
  var sh:Shoot = .{.at = undefined, .axis = undefined, .path = undefined, .t0 = t0, .t1 = @min(t0 + 0.15 + len * 0.2, 1), .leaves = 0};
  m.splineResample(&ctrl, &sh.path);
  sh.at = sh.path[RES - 1];
  sh.axis = m.norm(sh.path[RES - 1] - sh.path[RES - 4]);
  return sh;
}

/// `shootFold` for a stem built along an offshoot's `path` by its caller
/// (a braid): each vertex takes the weight of its nearest point of it.
pub fn shootFoldNearest(b:*Builder, start:usize, path:[]const V3) void {
  for (b.v.items[start..]) |*v| {
    var best:usize = 0;
    for (path, 0..) |p, j| {
      if (m.len(p - v.pos) < m.len(path[best] - v.pos)) best = j;
    }
    v.col.a = m.unorm8(1 - m.ratio(best, path.len - 1));
  }
}

/// mark every vertex since `start` as `w` of the way out along an offshoot
/// (colour alpha 1 - w; 1 everywhere else): until growth reaches it,
/// plant.vert folds an offshoot in against its stem by that much, so it
/// grows out of the stem, a bloom on it opening as it goes.
pub fn shootFold(b:*Builder, start:usize, w:f32) void {
  shootFoldRange(b, start, b.v.items.len, w);
}

/// `shootFold` for what grows along an offshoot (its leaves): each vertex
/// takes the weight of the point of `path` it grows from, so a leaf folds
/// in with the stem beneath it.
pub fn shootFoldAlong(b:*Builder, start:usize, path:[]const V3) void {
  var s = start;
  while (s < b.v.items.len) {
    // the vertices of one leaf share its tu.x; weigh them by its base (tu.y 0)
    var e = s;
    var base = b.v.items[s].pos;
    while (e < b.v.items.len and b.v.items[e].tu[0] == b.v.items[s].tu[0]) : (e += 1) {
      if (b.v.items[e].tu[1] < 1e-4) base = b.v.items[e].pos;
    }
    var best:usize = 0;
    for (path, 0..) |p, j| {
      if (m.len(p - base) < m.len(path[best] - base)) best = j;
    }
    shootFoldRange(b, s, e, m.ratio(best, path.len - 1));
    s = e;
  }
}

fn shootFoldRange(b:*Builder, start:usize, end:usize, w:f32) void {
  for (b.v.items[start..end]) |*v| v.col.a = m.unorm8(1 - w);
}

/// what a bloom sits on: a calyx of skin with its sepals folded back, or a
/// bead of resin sap (this colour) held up in a cup of sepals
pub const Calyx = union(enum) { skin, resin:color.Rgba8 };

/// how many sepals cup a bloom's bead of resin
const BEAD_SEPALS = 5;

/// a bloom at `top` heading along `axis`, `sc` the size of the species'
/// own: a calyx at the tip (`cx`), and two overlapping whorls of petals
/// rising from its crown into a cup.
pub fn flower(b:*Builder, g:species.Genome, top:V3, axis:V3, sc:f32, spin:f32, t:f32, cx:Calyx) Allocator.Error!void {
  const calyx = (g.bloom_r * 0.12 + g.stem_r * 0.6) * sc;
  var heart = top + axis * m.splat3(calyx * 0.5);
  switch (cx) {
    .skin => {
      try ellipsoid(b, .{
        .center = top + axis * m.splat3(calyx * 0.4), .radii = m.v3(calyx, calyx * 0.85, calyx),
        .col = g.stem_col.toRgba8(255), .part = .stem, .rings = 6, .segs = 8, .t = t,
      });
      for (0..4) |i| {
        const a = (m.f(i) + 0.5) / 4 * m.tau + spin;
        try blade(b, top, m.norm(m.v3(@cos(a), -0.1, @sin(a))), g.bloom_r * 0.55 * sc, g.bloom_r * 0.22 * sc, 0.5, color.shade(g.leaf_col, 0.55), g.leaf_col.toRgba8(255), t - 0.03, .leaf);
      }
    },
    .resin => |sap| {
      // the bead: dense at its base, thin at its crown (tu.y, the resin
      // shading reads it), the sepals cupped up round its lower half
      const r = calyx * 1.15;
      const c = top + axis * m.splat3(r * 0.8);
      const s = b.mark();
      try ellipsoid(b, .{.center = c, .radii = m.v3(r, r * 1.12, r), .col = sap, .part = .resin, .rings = 8, .segs = 10, .t = t});
      for (b.v.items[s..]) |*v| v.tu[1] = m.clamp01(m.dot(v.pos - c, axis) / (2 * r * 1.12) + 0.5);
      for (0..BEAD_SEPALS) |i| {
        const a = (m.f(i) + 0.5) / BEAD_SEPALS * m.tau + spin;
        const out = m.v3(@cos(a), 0, @sin(a));
        try petal(b, .{
          .base = top + out * m.splat3(r * 0.3), .out = out, .len = r * 1.9, .width = r * 0.85,
          .rise = 0.95, .flare = 0.35, .cup = 0.55,
          .col = color.shade(g.leaf_col, 0.55), .tip = g.leaf_col.toRgba8(255), .t = t - 0.03, .part = .leaf,
        });
      }
      heart = c + axis * m.splat3(r * 0.9);
    },
  }
  // broad outer petals opening out, a smaller inner ring standing more
  // upright between them
  const inner = @max(g.petals / 2, 3);
  for (0..g.petals + inner) |i| {
    const outer = i < g.petals;
    const ang = if (outer) m.ratio(i, g.petals) * m.tau else (m.f(i - g.petals) + 0.5) / m.f(inner) * m.tau;
    try petal(b, .{
      .base = heart, .out = m.v3(@cos(ang + spin * 0.37), 0, @sin(ang + spin * 0.37)),
      .len = g.bloom_r * sc * (if (outer) @as(f32, 1) else 0.72),
      .width = g.bloom_r * sc * (if (outer) @as(f32, 0.62) else 0.5),
      .rise = if (outer) 0.8 else 1.2, .flare = if (outer) 0.95 else 0.55, .cup = if (outer) 0.35 else 0.5,
      .col = color.shade(g.bloom_col, 0.8), .tip = g.bloom_col.toRgba8(255), .t = t,
    });
  }
  // stamens standing up out of the cup
  try stamens(b, .{
    .heart = heart, .axis = axis, .n = @max(g.petals, 5),
    .len = g.bloom_r * sc * 0.55, .r = g.bloom_r * sc * 0.035, .anther = g.bloom_r * sc * 0.2,
    .lean = 0.3, .arch = 0.6, .col = filament(g), .spin = spin, .t = t, .seed = @as(u32, @bitCast(spin)),
  });
}

/// a flower's filaments: its bloom's colour paled almost to white
fn filament(g:species.Genome) color.Rgba8 {
  return color.mix(g.bloom_col.toRgba8(255), color.rgb(1, 0.97, 0.9).toRgba8(255), 0.6);
}

/// a closed bud at `top`: a calyx, sepals clasping up around it, and the
/// petals folded over one another into a teardrop round a coloured heart.
pub fn bud(b:*Builder, g:species.Genome, top:V3, axis:V3, sc:f32, spin:f32, t:f32) Allocator.Error!void {
  const calyx = (g.bloom_r * 0.12 + g.stem_r * 0.6) * sc;
  const len = g.bloom_r * 0.6 * sc;
  try ellipsoid(b, .{
    .center = top + axis * m.splat3(calyx * 0.4), .radii = m.v3(calyx, calyx * 0.85, calyx),
    .col = g.stem_col.toRgba8(255), .part = .stem, .rings = 6, .segs = 8, .t = t,
  });
  const heart = top + axis * m.splat3(calyx * 0.5);
  try ellipsoid(b, .{
    .center = heart + axis * m.splat3(len * 0.42), .radii = m.v3(len * 0.22, len * 0.45, len * 0.22),
    .col = color.shade(g.bloom_col, 0.75), .part = .bloom, .rings = 6, .segs = 8, .t = t,
  });
  const n = @max(g.petals / 2 + 2, 4);
  for (0..n) |i| {
    const a = m.ratio(i, n) * m.tau + spin;
    try petal(b, .{
      .base = heart, .out = m.v3(@cos(a), 0, @sin(a)),
      .len = len, .width = len * 0.5,
      // past upright by the tip: the petals close over the heart
      .rise = 1.3, .flare = -0.55, .cup = 0.7,
      .col = color.shade(g.bloom_col, 0.7), .tip = g.bloom_col.toRgba8(255), .t = t,
    });
  }
  for (0..3) |i| {
    const a = (m.f(i) + 0.5) / 3 * m.tau + spin;
    try blade(b, top, m.norm(m.v3(@cos(a), 1.5, @sin(a))), len * 0.7, len * 0.22, 0.05, color.shade(g.leaf_col, 0.55), g.leaf_col.toRgba8(255), t - 0.03, .leaf);
  }
}

/// `n` small leaves grown along a vine between fractions `k0`..`k1` of
/// `path`: turning around it leaf by leaf, lifting toward the light, smaller
/// toward the tip. `t0`..`t1` is the vine's tu.x over its length.
pub fn leavesAlong(b:*Builder, path:[]const V3, n:u32, len:f32, width:f32, k0:f32, k1:f32, t0:f32, t1:f32, col:color.Rgba8, tip:color.Rgba8, seed:u64) Allocator.Error!void {
  var rng = Rng.init(seed);
  for (0..n) |i| {
    const k = m.lerp(k0, k1, (m.f(i) + 0.5) / m.f(n));
    try leafAt(b, path, k, i, len, width, t0, t1, col, tip, seed, &rng);
  }
}

/// the `i`th of `leavesAlong`'s leaves, `k` along `path` (`rng` its draws,
/// in order): one at a time, for a piece grown on its own (gfx/growth.zig).
pub fn leafAt(b:*Builder, path:[]const V3, k:f32, i:usize, len:f32, width:f32, t0:f32, t1:f32, col:color.Rgba8, tip:color.Rgba8, seed:u64, rng:*Rng) Allocator.Error!void {
  const at = m.alongPath(path, k);
  const tan = m.norm(m.alongPath(path, @min(k + 0.03, 1)) - m.alongPath(path, @max(k - 0.03, 0)));
  const ref = if (@abs(tan[1]) > 0.9) m.v3(1, 0, 0) else m.v3(0, 1, 0);
  const s1 = m.norm(m.cross(tan, ref));
  const s2 = m.cross(tan, s1);
  const a = m.f(i) * 2.4 + rng.range(-0.3, 0.3) + m.f(seed % 7);
  var out = s1 * m.splat3(@cos(a)) + s2 * m.splat3(@sin(a)) + m.v3(0, 0.5, 0) + tan * m.splat3(0.3);
  // a blade needs some sideways lean to find its width
  out[1] = m.clamp(out[1], -0.6, 0.7);
  out = m.norm(out);
  const l = len * m.lerp(1, 0.6, k) * rng.range(0.85, 1.15);
  try blade(b, at, out, l, width * m.lerp(1, 0.7, k), 0.35, col, tip, m.lerp(t0, t1, k), .leaf);
}

/// a floater: nothing reaches the ground. A translucent sap float holds it
/// up; above it a short neck lifts a wide catcher dish open to the sky (it
/// drinks starlight); beneath it long filaments trail down toward the
/// ground, swaying most at their tips, so it hangs in the air rather than
/// standing on it. The origin is the float's centre.
fn drift(b:*Builder, g:species.Genome, seed:u64, variant:u32) Allocator.Error!void {
  var rng = Rng.init(seed);
  const float_r = g.bloom_r * 0.62;

  // the float: a comb-jelly lantern, a spore held inside it
  try lantern(b, g, float_r, seed);
  try ellipsoid(b, .{
    .center = m.v3(0, -float_r * 0.05, 0), .radii = m.v3(float_r * 0.26, float_r * 0.36, float_r * 0.26),
    .col = color.rgb(1.0, 0.92, 0.62).toRgba8(255), .part = .stem, .rings = 6, .segs = 8, .t = 0.95,
  });

  // the neck and the catcher dish: two whorls opening wide and shallow
  const neck = m.v3(rng.range(-0.02, 0.02), float_r * 0.95 + g.stem_h, rng.range(-0.02, 0.02));
  var nc:[4]V3 = undefined;
  growthPath(.{.start = m.v3(0, float_r * 0.75, 0), .direction = m.norm(neck - m.v3(0, float_r * 0.75, 0)), .length = m.len(neck - m.v3(0, float_r * 0.75, 0)), .wobble = g.wobble, .seed = seed ^ 0x57E4}, &nc);
  var np:[8]V3 = undefined;
  m.splineResample(&nc, &np);
  var nt:[8]f32 = undefined;
  var nr:[8]f32 = undefined;
  for (&nt, &nr, 0..) |*t, *r, i| {
    const k = m.ratio(i, 7);
    t.* = m.lerp(0.55, 0.9, k);
    r.* = g.stem_r * m.lerp(1.3, 0.8, k);
  }
  try b.tubeR(&np, &nt, &nr, g.stem_col.toRgba8(255), .stem, 6);
  const inner = @max(g.petals / 2, 3);
  for (0..g.petals + inner) |i| {
    const outer = i < g.petals;
    const ang = if (outer) m.ratio(i, g.petals) * m.tau + m.f(variant) else (m.f(i - g.petals) + 0.5) / m.f(inner) * m.tau;
    try petal(b, .{
      .base = np[7], .out = m.v3(@cos(ang), 0, @sin(ang)),
      .len = g.bloom_r * (if (outer) @as(f32, 1) else 0.6),
      .width = g.bloom_r * (if (outer) @as(f32, 0.5) else 0.42),
      .rise = if (outer) 0.55 else 1.0, .flare = if (outer) 0.35 else 0.4, .cup = 0.45,
      .col = color.shade(g.bloom_col, 0.8), .tip = g.bloom_col.toRgba8(255),
    });
  }
  // stamens fanning out over the dish
  try stamens(b, .{
    .heart = np[7], .axis = m.norm(np[7] - np[5]), .n = @max(g.petals / 2 + 2, 5),
    .len = g.bloom_r * 0.45, .r = g.bloom_r * 0.022, .anther = g.bloom_r * 0.11,
    .lean = 0.45, .arch = 0.5, .col = filament(g), .t = 0.9, .spin = m.f(variant), .seed = seed,
  });

  // offshoots: slender stalks leaning out of the neck beneath the dish,
  // each lifting a bud or a small bloom of its own to the sky
  var srng = Rng.init(seed ^ 0x0FF5);
  const shoots = shootCount(g, &srng);
  for (0..shoots) |i| {
    const k = srng.range(0.05, 0.45);
    const ang = m.ratio(i, @max(shoots, 1)) * m.tau + 0.5 + m.f(variant) * 1.1 + srng.range(-0.4, 0.4);
    const len = g.bloom_r * srng.range(1.0, 1.5);
    const tip = try offshoot(b, &np, k, m.lerp(0.55, 0.9, k), ang, len, g.stem_r * 0.6, srng.range(0.15, 0.45), g.stem_col.toRgba8(255), .stem, seed +% i * 211);
    const s = b.mark();
    if (srng.float() < 0.5)
      try flower(b, g, tip.at, tip.axis, srng.range(0.35, 0.45), m.f(i) * 2.1, tip.t1, .skin)
    else
      try bud(b, g, tip.at, tip.axis, srng.range(0.4, 0.55), m.f(i) * 1.3, tip.t1);
    shootFold(b, s, 1);
  }

  // trailing filaments out of the lantern's mouth: hair-thin threads, each
  // waving in its own plane (and a little across it), the waves widening
  // toward the free tip, which tapers to nothing. plant.vert runs a slow
  // wave down them as well, so they ripple like a jelly's.
  for (0..g.tendrils) |i| {
    const a = m.ratio(i, g.tendrils) * m.tau + rng.range(-0.25, 0.25);
    const out = m.v3(@cos(a), 0, @sin(a));
    const from = out * m.splat3(float_r * 0.22) + m.v3(0, -float_r * 0.55, 0);
    // every other one shorter, so they hang in two lengths
    const len = if (i % 2 == 0) rng.range(0.75, 1.05) else rng.range(0.45, 0.7);
    const to = from + out * m.splat3(rng.range(0.06, 0.14)) + m.v3(0, -len, 0);
    const dir = m.norm(to - from);
    const across = m.norm(m.cross(dir, out));
    const waves = rng.range(2.2, 3.4);
    const ph = rng.range(0, m.tau);
    var fc:[14]V3 = undefined;
    for (&fc, 0..) |*c, j| {
      const k = m.ratio(j, fc.len - 1);
      const amp = TENDRIL_WAVE * m.smooth(@min(1, k * 3)) * (0.5 + 0.5 * k);
      const w = k * waves * m.tau + ph;
      c.* = from + (to - from) * m.splat3(k) + out * m.splat3(@sin(w) * amp) + across * m.splat3(@sin(w * 0.5 + 1.3) * amp * 0.45);
    }
    grow(&fc, .{.start = from, .direction = dir, .length = m.len(to - from), .wobble = g.tendril_wobble, .seed = seed +% i * 31});
    var fp:[40]V3 = undefined;
    m.splineResample(&fc, &fp);
    var ft:[40]f32 = undefined;
    var fr:[40]f32 = undefined;
    for (&ft, &fr, 0..) |*t, *r, j| {
      const k = m.ratio(j, fp.len - 1);
      // tu.x rises toward the tips so they sway most, like a pendulum
      t.* = m.lerp(0.3, 1, k);
      r.* = TENDRIL_R * (1 - k) * (0.4 + 0.6 * (1 - k));
    }
    try b.tubeR(&fp, &ft, &fr, g.leaf_col.toRgba8(255), .tendril, 4);
  }
}

/// a driftwisp filament's thickness at the mouth, and how far its waves swing
const TENDRIL_R:f32 = 0.0075;
const TENDRIL_WAVE:f32 = 0.045;
/// the lantern: comb rows standing out of it, how sharp their crests, and
/// how far they turn round it from mouth to top
const LANTERN_ROWS = 8;
const LANTERN_RIB:f32 = 0.11;
const LANTERN_CREST:f32 = 4;
const LANTERN_TWIST:f32 = 0.7;

/// a driftwisp's float: a comb-jelly lantern of sap, an egg a little taller
/// than wide, broadest below its middle, with eight comb rows standing out
/// of it from its mouth to its top, turning a little as they go. The rows
/// carry the light split into colours (pale rainbow along each one); the
/// skin between them is clear sap. One shared-vertex sheet closed at both
/// poles, so it is watertight.
fn lantern(b:*Builder, g:species.Genome, R:f32, seed:u64) Allocator.Error!void {
  const ROWS = 17;
  const COLS = 49;
  var pts:[ROWS * COLS]V3 = undefined;
  var nrms:[ROWS * COLS]V3 = undefined;
  var cols:[ROWS * COLS]color.Rgba8 = undefined;
  var us:[ROWS * COLS]f32 = undefined;
  const skin = color.shade(g.bloom_col, 0.8);
  const hue0 = m.f(seed % 97) / 97;
  for (0..ROWS) |i| for (0..COLS) |j| {
    const s = m.ratio(i, ROWS - 1);
    const ph = m.ratio(j, COLS - 1) * m.tau;
    const at = i * COLS + j;
    pts[at] = lanternAt(R, s, ph);
    // the poles' normals point straight out of them; elsewhere, across the
    // sheet's two directions
    nrms[at] = if (i == 0) m.v3(0, -1, 0) else if (i == ROWS - 1) m.v3(0, 1, 0) else n: {
      const e:f32 = 0.002;
      const ds = lanternAt(R, s + e, ph) - lanternAt(R, s - e, ph);
      const dp = lanternAt(R, s, ph + e) - lanternAt(R, s, ph - e);
      break :n m.norm(m.cross(ds, dp));
    };
    const crest = lanternCrest(s, ph);
    const x = hue0 + s * 1.3 + m.f(j) / COLS * 0.5;
    const film = color.rgb(0.5 + 0.5 * @cos(m.tau * x), 0.5 + 0.5 * @cos(m.tau * (x + 0.33)), 0.5 + 0.5 * @cos(m.tau * (x + 0.67))).toRgba8(255);
    cols[at] = color.mix(skin, color.mix(film, color.rgb(1, 1, 1).toRgba8(255), 0.35), crest * 0.8);
    us[at] = 0;
  };
  try patch(b, ROWS, COLS, &pts, &nrms, &cols, &us, 0.5, .bloom);
}

/// how much of a comb row's crest lies at height `s` (0 mouth .. 1 top) and
/// bearing `ph`
fn lanternCrest(s:f32, ph:f32) f32 {
  return m.pow(f32, 0.5 + 0.5 * @cos(LANTERN_ROWS * ph + LANTERN_TWIST * s * m.tau), LANTERN_CREST);
}

/// a point on the lantern at height `s` (0 its mouth .. 1 its top) and bearing `ph`
fn lanternAt(R:f32, s:f32, ph:f32) V3 {
  const k = m.clamp01(s);
  const r = R * m.pow(f32, @sin(k * m.pi), 0.7) * (1.08 - 0.22 * k) * (1 + LANTERN_RIB * lanternCrest(k, ph));
  return m.v3(@cos(ph) * r, R * m.lerp(-0.85, 1.0, k), @sin(ph) * r);
}

/// growth keys a confluence is built at, evenly from sprout (0) to bloom (1).
/// Every key has the same vertices in the same order, so the plant shader
/// blends between the two around a plant's growth: it grows, never jumps.
pub const KEYS = 8;

/// how many meshes a species is built as: shapes picked by tile, or for a
/// confluence its growth keys.
pub fn variants(id:species.Id) u32 {
  return switch (species.get(id).genome.form) {
    .herb, .coil, .drift, .radiant, .star => VARIANTS,
    .confluence => KEYS,
  };
}

/// for a species grown through keys, the key below `growth` and how far
/// toward the next one it is; null for a species of fixed shapes.
pub const Key = struct { v:u32, f:f32 };
pub fn growthKey(id:species.Id, growth:f32) ?Key {
  switch (species.get(id).genome.form) {
    .herb, .coil, .drift, .radiant, .star => return null,
    .confluence => {
      const x = m.clamp01(growth) * (KEYS - 1);
      const v = @min(m.floorTo(u32, x), KEYS - 2);
      return .{.v = v, .f = x - m.f(v)};
    },
  }
}

/// slots per species in per-variant tables (the most any species uses).
pub const MAX_VARIANTS = @max(VARIANTS, KEYS);

/// where a (species, variant, level of detail) mesh sits in per-variant tables.
pub fn plantSlot(id:species.Id, variant:u32, lod:u32) usize { return (@as(usize, @intFromEnum(id)) * MAX_VARIANTS + variant) * LODS + lod; }

test "a blade has a body: both faces, wound outward, its vein on the cupped face" {
  var b:Builder = .{.gpa = testing.allocator};
  defer b.deinit();
  const c = color.rgb(0.3, 0.6, 0.2).toRgba8(255);
  try blade(&b, m.v3(0, 0, 0), m.v3(1, 0, 0), 1, 0.2, 0.3, c, c, 1, .leaf);
  var up:usize = 0;
  var down:usize = 0;
  var tri:usize = 0;
  while (tri < b.v.items.len) : (tri += 3) {
    const v = b.v.items[tri .. tri + 3];
    const p:[3]V3 = .{v[0].pos, v[1].pos, v[2].pos};
    const n:V3 = @as(V3, v[0].nrm) + @as(V3, v[1].nrm) + @as(V3, v[2].nrm);
    const g = m.cross(p[1] - p[0], p[2] - p[0]);
    if (m.len(g) < 1e-9) continue;
    try testing.expect(m.dot(g, n) > 0);
    if (m.norm(g)[1] > 0.5) up += 1;
    if (m.norm(g)[1] < -0.5) down += 1;
  }
  try testing.expect(up > 0 and down > 0);
  // the vein's crest is paler than the blade, and stands on the face looking up
  var pale = false;
  for (b.v.items) |vx| if (vx.col.r > c.r + 10) {
    pale = true;
    try testing.expect(vx.nrm[1] > 0);
  };
  try testing.expect(pale);
}

test "a confluence's growth keys share one vertex layout and grow taller" {
  var b:Builder = .{.gpa = testing.allocator};
  defer b.deinit();
  var counts:[KEYS]usize = undefined;
  var tops:[KEYS]f32 = undefined;
  for (0..KEYS) |v| {
    b.v.clearRetainingCapacity();
    try plant(&b, .confluence, @intCast(v));
    counts[v] = b.v.items.len;
    var hi:f32 = 0;
    for (b.v.items) |x| hi = @max(hi, x.pos[1]);
    tops[v] = hi;
  }
  for (counts[1..]) |c| try testing.expectEqual(counts[0], c);
  for (tops[1..], tops[0 .. KEYS - 1]) |t, prev| try testing.expect(t >= prev);
  // keys cover growth end to end; between keys the blend is the fraction
  try testing.expectEqual(Key{.v = 0, .f = 0}, growthKey(.confluence, 0).?);
  const end = growthKey(.confluence, 1).?;
  try testing.expect(end.v == KEYS - 2 and end.f == 1);
  try testing.expect(growthKey(.lumenroot, 0.5) == null);
}
