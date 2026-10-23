//! mesh: WOLF EAR. base at origin, rising along +Y: tall, wide at the base
//! and tapering to a softly rounded point, cupped toward its inner face
//! (+Z). The inner face is sap (translucent through the instance's fade),
//! the outer face dense vine with a raised cartilage ridge (the antihelix)
//! down its centre. The rig leans it forward and out.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../../core/math.zig");
const mg = @import("../meshgen.zig");
const pal = @import("palette.zig");
const color = @import("../../core/color.zig");

const V3 = m.V3;
const v3 = m.v3;

pub const HEIGHT:f32 = 0.12;
const HALF_BASE:f32 = 0.03;
const CUP:f32 = 0.009;
const ROWS = 12;
const COLS = 7;

/// a point on the ear: k up its height, u across it (-1..1)
fn at(k:f32, u:f32) V3 {
  // wide base, softly rounded tip (the width's slope eases to vertical there)
  const w = HALF_BASE * m.pow(f32, @cos(k * m.pi / 2.0), 0.75);
  const cup = CUP * (1 - u * u) * @sin(k * m.pi * 0.9 + 0.15);
  return v3(-u * w, k * HEIGHT, -cup);
}

pub fn build(b:*mg.Builder) Allocator.Error!void {
  var pts:[ROWS * COLS]V3 = undefined;
  var nrms:[ROWS * COLS]V3 = undefined;
  var cols:[ROWS * COLS]color.Rgba8 = undefined;
  var us:[ROWS * COLS]f32 = undefined;
  for (0..ROWS) |r| for (0..COLS) |c| {
    const k = m.ratio(r, ROWS - 1) * 0.985;
    const u = m.ratio(c, COLS - 1) * 2 - 1;
    const i = r * COLS + c;
    pts[i] = at(k, u);
    // normal toward the outer face (-Z): the inner face is the one opposite
    const e:f32 = 0.01;
    const du = at(k, u + e) - at(k, u - e);
    const dk = at(k + e, u) - at(k - e, u);
    nrms[i] = m.norm(m.cross(dk, du));
    if (nrms[i][2] > 0) nrms[i] = -nrms[i];
    cols[i] = color.mix(pal.wolf_core, pal.wolf_vine, k);
    us[i] = k;
  };
  try mg.patch(b, ROWS, COLS, &pts, &nrms, &cols, &us, 1, .ear);
  // the antihelix: a thin vine raised along the centre of the outer face
  var ridge:[10]V3 = undefined;
  var ts:[10]f32 = undefined;
  var rs:[10]f32 = undefined;
  for (&ridge, &ts, &rs, 0..) |*p, *t, *r, i| {
    const k = 0.08 + 0.72 * m.ratio(i, 9);
    p.* = at(k, 0) - v3(0, 0, 0.003);
    t.* = k;
    r.* = 0.0035 * (1 - 0.5 * k);
  }
  try b.tubeR(&ridge, &ts, &rs, pal.wolf_vine, .stem, 5);
}
