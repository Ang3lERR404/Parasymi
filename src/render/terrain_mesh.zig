//! chunk -> smooth ground mesh. Each tile is a fan of four triangles: its
//! centre at the tile's own height (where everything on it stands), its
//! corners shared with its neighbours (the average of the tiles that meet
//! there), so the ground rolls from one terrace to the next with no walls
//! or hard ramps, and its colour blends across tile borders. Land dips
//! under the water at the shore. The detail on top (grass on every tile but
//! water and soil, clods and stones on soil) is not meshed here: each such
//! tile gets one `DetailTile` record and the GPU grows the detail from it.
//! Border neighbours come from the generator directly, so a chunk can be
//! meshed without its neighbours being loaded.
const std = @import("std");
const m = @import("../core/math.zig");
const Allocator = std.mem.Allocator;
const ck = @import("../world/chunk.zig");
const gen = @import("../world/gen.zig");
const rng = @import("../core/rng.zig");
const color = @import("../core/color.zig");
const vertex = @import("../gfx/vertex.zig");
const TV = vertex.Terrain;
const DetailTile = vertex.DetailTile;

const V3 = m.V3;
const v3 = m.v3;

fn baseColor(k:ck.Kind) color.Rgb {
  return switch (k) {
    .water => color.rgb(0.10, 0.22, 0.35),
    .soil => color.rgb(0.36, 0.27, 0.19),
    .moss => color.rgb(0.20, 0.36, 0.20),
    .stone => color.rgb(0.42, 0.42, 0.46),
    .ley => color.rgb(0.30, 0.24, 0.45),
  };
}

/// how many grass blades grow on a tile of each kind (detail.vert grows them)
fn blades(k:ck.Kind) u32 {
  return switch (k) {
    .water, .soil => 0,
    .moss => 8,
    .ley => 6,
    .stone => 2,
  };
}

/// where the land meets the water it dips just under the surface
const SHORE = gen.WATER_H - 0.14;
/// each tile's colour varies by `JITTER` about `JITTER_MIN` of its kind's
const JITTER_MIN:f32 = 0.9;
const JITTER:f32 = 0.2;
/// a tile is a fan of four triangles
const VERTS_PER_TILE = 4 * 3;

/// the tiles around a chunk, one ring beyond it, read once
const Ring = struct {
  const W = ck.SIZE + 2;
  h:[W * W]f32 = undefined,
  kind:[W * W]ck.Kind = undefined,
  col:[W * W]color.Rgb = undefined,
  /// ley intensity 0..1
  ley:[W * W]f32 = undefined,

  fn at(_:*const Ring, lx:i32, ly:i32) usize { return @intCast((ly + 1) * W + (lx + 1)); }
};

fn fill(r:*Ring, seed:u64, c:*const ck.Chunk) void {
  const ox = c.originX();
  const oy = c.originY();
  var ly:i32 = -1;
  while (ly <= ck.SIZE) : (ly += 1) {
    var lx:i32 = -1;
    while (lx <= ck.SIZE) : (lx += 1) {
      const wx = ox + lx;
      const wy = oy + ly;
      const inside = lx >= 0 and lx < ck.SIZE and ly >= 0 and ly < ck.SIZE;
      const i = r.at(lx, ly);
      if (inside) {
        const t:usize = @intCast(ly * ck.SIZE + lx);
        r.h[i] = c.height[t];
        r.kind[i] = c.kind[t];
        r.ley[i] = m.clamp01(c.ley_cap[t] / gen.LEY_MAX);
      } else {
        const s = gen.sample(seed, wx, wy);
        r.h[i] = s.height;
        r.kind[i] = s.kind;
        r.ley[i] = m.clamp01(s.ley / gen.LEY_MAX);
      }
      const jitter = JITTER_MIN + JITTER * rng.unit(rng.hash2(seed ^ 0xC0101, wx, wy));
      const b = baseColor(r.kind[i]);
      r.col[i] = color.rgb(b.r * jitter, b.g * jitter, b.b * jitter);
    }
  }
}

/// a point of the half-tile grid (chunk-local, tile lx spans 2lx..2lx+2,
/// its centre at 2lx+1): shared by the tiles that meet there
fn point(r:*const Ring, px:i32, py:i32) Shared {
  var ts:[4]usize = undefined;
  var n:usize = 0;
  const xs = [2]i32{@divFloor(px - 1, 2), @divFloor(px, 2)};
  const ys = [2]i32{@divFloor(py - 1, 2), @divFloor(py, 2)};
  // an odd coordinate is inside one tile, an even one between two
  const nx:usize = if (@mod(px, 2) == 1) 1 else 2;
  const ny:usize = if (@mod(py, 2) == 1) 1 else 2;
  for (0..ny) |j| for (0..nx) |i| {
    const tx = if (nx == 1) @divFloor(px, 2) else xs[i];
    const ty = if (ny == 1) @divFloor(py, 2) else ys[j];
    ts[n] = r.at(@max(-1, @min(ck.SIZE, tx)), @max(-1, @min(ck.SIZE, ty)));
    n += 1;
  };
  return shared(r, ts[0..n]);
}

const Shared = struct { h:f32, col:color.Rgb, ley:f32 };

/// a shared point among the tiles `ts`: the land's average height (or under
/// the water when any of them is water) and the land's average colour
fn shared(r:*const Ring, ts:[]const usize) Shared {
  var h:f32 = 0;
  var cr:f32 = 0;
  var cg:f32 = 0;
  var cb:f32 = 0;
  var land:f32 = 0;
  var wet = false;
  var ley:f32 = 0;
  for (ts) |t| ley += r.ley[t] / m.f(ts.len);
  for (ts) |t| {
    if (r.kind[t] == .water) {
      wet = true;
      continue;
    }
    h += r.h[t];
    cr += r.col[t].r;
    cg += r.col[t].g;
    cb += r.col[t].b;
    land += 1;
  }
  if (land == 0) return .{.h = gen.WATER_H, .col = r.col[ts[0]], .ley = ley};
  return .{.h = if (wet) SHORE else h / land, .col = color.rgb(cr / land, cg / land, cb / land), .ley = ley};
}

fn put(out:*std.ArrayList(TV), gpa:Allocator, p:V3, n:V3, c:color.Rgba8, info:[4]u8) Allocator.Error!void {
  try out.append(gpa, .{.pos = .{p[0], p[1], p[2]}, .nrm = .{n[0], n[1], n[2]}, .col = c, .info = info});
}


/// every shared point of a chunk's half-tile grid (one point beyond it on
/// each side, for slopes at its border), worked out once
const Grid = struct {
  const W = 2 * ck.SIZE + 5;
  p:[W * W]Shared = undefined,

  fn fill(g:*Grid, r:*const Ring) void {
    for (0..W) |y| for (0..W) |x| {
      g.p[y * W + x] = point(r, @as(i32, @intCast(x)) - 2, @as(i32, @intCast(y)) - 2);
    };
  }

  fn at(g:*const Grid, px:i32, py:i32) Shared { return g.p[@intCast((py + 2) * W + (px + 2))]; }
};

/// mesh a chunk's ground into `out`, and into `detail` one record per tile
/// that carries grass, clods or stones (the GPU grows those from it).
pub fn build(gpa:Allocator, seed:u64, c:*const ck.Chunk, out:*std.ArrayList(TV), detail:*std.ArrayList(DetailTile)) Allocator.Error!void {
  out.clearRetainingCapacity();
  detail.clearRetainingCapacity();
  // room for the whole chunk up front: no regrowing mid-build
  try out.ensureTotalCapacity(gpa, ck.N * VERTS_PER_TILE);
  try detail.ensureTotalCapacity(gpa, ck.N);
  var r:Ring = .{};
  fill(&r, seed, c);
  const grid = try gpa.create(Grid);
  defer gpa.destroy(grid);
  grid.fill(&r);
  const ox = c.originX();
  const oy = c.originY();
  for (0..ck.SIZE) |uy| for (0..ck.SIZE) |ux| {
    const lx:i32 = @intCast(ux);
    const ly:i32 = @intCast(uy);
    const i = r.at(lx, ly);
    const t = uy * ck.SIZE + ux;
    const k = r.kind[i];
    const wx = ox + lx;
    const wy = oy + ly;
    const ley:u8 = @intFromFloat(m.clamp01(c.ley_cap[t] / gen.LEY_MAX) * 255);
    // info.z: 255 marks the ground's top surface (read back as 1.0)
    const info:[4]u8 = .{@intFromEnum(k), ley, 255, 0};

    // the tile: a fan of four triangles from its centre (at the tile's own
    // height) to its corners (shared with its neighbours). Water stays flat
    // at its own level; land is lit by the ground's smooth slope.
    var gh:[3][3]f32 = undefined;
    var gc:[3][3]color.Rgba8 = undefined;
    var gn:[3][3]V3 = undefined;
    var gl:[3][3]u8 = undefined;
    for ([_][2]usize{.{0, 0}, .{2, 0}, .{0, 2}, .{2, 2}, .{1, 1}}) |g| {
      const gx = g[0];
      const gy = g[1];
      const px = 2 * lx + @as(i32, @intCast(gx));
      const py = 2 * ly + @as(i32, @intCast(gy));
      if (k == .water) {
        gh[gy][gx] = r.h[i];
        gc[gy][gx] = r.col[i].toRgba8(255);
        gn[gy][gx] = v3(0, 1, 0);
        gl[gy][gx] = ley;
        continue;
      }
      const s = grid.at(px, py);
      // ley fades across tile borders like the colour does
      gl[gy][gx] = @intFromFloat(s.ley * 255);
      gh[gy][gx] = s.h;
      gc[gy][gx] = s.col.toRgba8(255);
      // central differences over half-tile steps
      const dx = grid.at(px + 1, py).h - grid.at(px - 1, py).h;
      const dz = grid.at(px, py + 1).h - grid.at(px, py - 1).h;
      gn[gy][gx] = m.norm(v3(-dx, 1, -dz));
    }
    const x0 = m.f(wx);
    const z0 = m.f(wy);
    const corners = [_][2]usize{.{0, 0}, .{0, 2}, .{2, 2}, .{2, 0}};
    for (0..4) |j| {
      for ([_][2]usize{.{1, 1}, corners[j], corners[(j + 1) % 4]}) |cn| {
        const at = v3(x0 + 0.5 * m.f(cn[0]), gh[cn[1]][cn[0]], z0 + 0.5 * m.f(cn[1]));
        try put(out, gpa, at, gn[cn[1]][cn[0]], gc[cn[1]][cn[0]], .{info[0], gl[cn[1]][cn[0]], info[2], info[3]});
      }
    }
    if (k == .water) continue;

    // the detail on it (grass, or clods and stones on soil) is grown on the
    // GPU from this one record (shaders/detail.vert)
    const n = blades(k);
    if (n == 0 and k != .soil) continue;
    try detail.append(gpa, .{
      .at = .{x0, gh[1][1], z0},
      .corners = .{gh[0][0], gh[2][0], gh[2][2], gh[0][2]},
      .col = r.col[i].toRgba8(255),
      .info = .{@intFromEnum(k), ley, @intCast(n), 0},
    });
  };
}
