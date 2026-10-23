//! chunk -> smooth ground mesh. Each tile is a 3x3 grid of points: its
//! centre at the tile's own height (where everything on it stands), its
//! edges and corners shared with its neighbours (the average of the tiles
//! that meet there), so the ground rolls from one terrace to the next with
//! no walls or hard ramps, and its colour blends across tile borders. Land
//! dips under the water at the shore. On top: thin grass blades on every
//! tile but water and soil (coloured by the tile, swayed by the shader), and
//! clods and small stones on soil. Border neighbours come from the generator
//! directly, so a chunk can be meshed without its neighbours being loaded.
const std = @import("std");
const m = @import("../core/math.zig");
const Allocator = std.mem.Allocator;
const ck = @import("../world/chunk.zig");
const gen = @import("../world/gen.zig");
const rng = @import("../core/rng.zig");
const color = @import("../core/color.zig");
const TV = @import("../gfx/vertex.zig").Terrain;

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

/// how many grass blades grow on a tile of each kind
fn blades(k:ck.Kind) u32 {
  return switch (k) {
    .water, .soil => 0,
    .moss => 10,
    .ley => 7,
    .stone => 3,
  };
}

/// where the land meets the water it dips just under the surface
const SHORE = gen.WATER_H - 0.14;
/// info.w on grass blades: 1 at the base .. 255 at the tip (0: not grass)
const GRASS_BASE:u8 = 1;
const GRASS_TIP:u8 = 255;

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
        r.ley[i] = m.clamp(c.ley_cap[t] / 4.2, 0, 1);
      } else {
        const s = gen.sample(seed, wx, wy);
        r.h[i] = s.height;
        r.kind[i] = s.kind;
        r.ley[i] = m.clamp(s.ley / 4.2, 0, 1);
      }
      const jitter = 0.9 + 0.2 * rng.unit(rng.hash2(seed ^ 0xC0101, wx, wy));
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

fn tri(out:*std.ArrayList(TV), gpa:Allocator, p:[3]V3, c:[3]color.Rgba8, info:[4]u8) Allocator.Error!void {
  var n = m.norm(m.cross(p[2] - p[0], p[1] - p[0]));
  if (n[1] < 0) n = -n;
  for (0..3) |i| try put(out, gpa, p[i], n, c[i], info);
}

pub fn build(gpa:Allocator, seed:u64, c:*const ck.Chunk, out:*std.ArrayList(TV)) Allocator.Error!void {
  out.clearRetainingCapacity();
  var r:Ring = .{};
  fill(&r, seed, c);
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
    const ley:u8 = @intFromFloat(m.clamp(c.ley_cap[t] / 4.2, 0, 1) * 255);
    // info.z: 255 marks the ground's top surface (read back as 1.0)
    const info:[4]u8 = .{@intFromEnum(k), ley, 255, 0};

    // the tile's 3x3 grid: water stays flat at its own level; land takes
    // the shared points, lit by the ground's smooth slope there
    var gh:[3][3]f32 = undefined;
    var gc:[3][3]color.Rgba8 = undefined;
    var gn:[3][3]V3 = undefined;
    var gl:[3][3]u8 = undefined;
    for (0..3) |gy| for (0..3) |gx| {
      const px = 2 * lx + @as(i32, @intCast(gx));
      const py = 2 * ly + @as(i32, @intCast(gy));
      if (k == .water) {
        gh[gy][gx] = r.h[i];
        gc[gy][gx] = r.col[i].toRgba8(255);
        gn[gy][gx] = v3(0, 1, 0);
        gl[gy][gx] = ley;
        continue;
      }
      const s = point(&r, px, py);
      // ley fades across tile borders like the colour does
      gl[gy][gx] = @intFromFloat(s.ley * 255);
      gh[gy][gx] = s.h;
      gc[gy][gx] = s.col.toRgba8(255);
      // central differences over half-tile steps
      const dx = point(&r, px + 1, py).h - point(&r, px - 1, py).h;
      const dz = point(&r, px, py + 1).h - point(&r, px, py - 1).h;
      gn[gy][gx] = m.norm(v3(-dx, 1, -dz));
    };
    const x0 = m.f(wx);
    const z0 = m.f(wy);
    for (0..2) |qy| for (0..2) |qx| {
      var p:[4]V3 = undefined;
      var q:[4]color.Rgba8 = undefined;
      var nn:[4]V3 = undefined;
      var ll:[4]u8 = undefined;
      const corners = [4][2]usize{.{qx, qy}, .{qx, qy + 1}, .{qx + 1, qy + 1}, .{qx + 1, qy}};
      for (corners, 0..) |cn, j| {
        p[j] = v3(x0 + 0.5 * m.f(cn[0]), gh[cn[1]][cn[0]], z0 + 0.5 * m.f(cn[1]));
        q[j] = gc[cn[1]][cn[0]];
        nn[j] = gn[cn[1]][cn[0]];
        ll[j] = gl[cn[1]][cn[0]];
      }
      for ([_]usize{0, 1, 2, 0, 2, 3}) |j| try put(out, gpa, p[j], nn[j], q[j], .{info[0], ll[j], info[2], info[3]});
    };
    if (k == .water) continue;

    const height = struct {
      /// the ground's height at (fx, fz) within the tile (0..1 each)
      fn at(g:*const [3][3]f32, fx:f32, fz:f32) f32 {
        const gx = @min(fx * 2, 1.999);
        const gz = @min(fz * 2, 1.999);
        const ix = m.floorTo(usize, gx);
        const iz = m.floorTo(usize, gz);
        const u = gx - m.f(ix);
        const w = gz - m.f(iz);
        return m.lerp(m.lerp(g[iz][ix], g[iz][ix + 1], u), m.lerp(g[iz + 1][ix], g[iz + 1][ix + 1], u), w);
      }
    };
    var rr = rng.Rng.init(rng.hash2(seed ^ 0x6A55, wx, wy));
    const tile = r.col[i];

    // grass: thin blades, darker at the root, the tile's own colour lighter
    // at the tip; the shader sways them by height (info.w)
    for (0..blades(k)) |_| {
      const fx = rr.range(0.06, 0.94);
      const fz = rr.range(0.06, 0.94);
      const len = rr.range(0.09, 0.23);
      const ang = rr.range(0, m.tau);
      const lean = rr.range(0, 0.25);
      const base = v3(x0 + fx, height.at(&gh, fx, fz) - 0.01, z0 + fz);
      const side = v3(@cos(ang), 0, @sin(ang)) * m.splat3(0.014);
      const tip = base + v3(-@sin(ang) * lean * len, len, @cos(ang) * lean * len);
      const root = color.rgb(tile.r * 0.7, tile.g * 0.75, tile.b * 0.7).toRgba8(255);
      const top = color.rgb(@min(tile.r * 1.35, 1), @min(tile.g * 1.45, 1), @min(tile.b * 1.3, 1)).toRgba8(255);
      const n = v3(0, 1, 0);
      try put(out, gpa, base - side, n, root, .{info[0], info[1], 0, GRASS_BASE});
      try put(out, gpa, base + side, n, root, .{info[0], info[1], 0, GRASS_BASE});
      try put(out, gpa, tip, n, top, .{info[0], info[1], 0, GRASS_TIP});
    }

    // rich soil: clods heaped up out of it and small stones half sunk in it
    if (k == .soil) {
      for (0..5) |j| {
        const fx = rr.range(0.12, 0.88);
        const fz = rr.range(0.12, 0.88);
        const stone = j >= 3;
        const rad = if (stone) rr.range(0.025, 0.055) else rr.range(0.05, 0.1);
        const col = if (stone)
          color.shade(color.rgb(0.42, 0.4, 0.38), rr.range(0.75, 1.15))
        else
          color.rgb(tile.r * 0.78, tile.g * 0.72, tile.b * 0.68).toRgba8(255);
        const at = v3(x0 + fx, height.at(&gh, fx, fz), z0 + fz);
        try lump(out, gpa, at, rad, if (stone) 0.7 else 0.35, &rr, col, .{info[0], info[1], 0, 0});
      }
    }
  };
}

/// a small faceted lump sitting in the ground: an irregular octahedron-ish
/// stone, `flat` its height relative to its width, the lower half sunk.
fn lump(out:*std.ArrayList(TV), gpa:Allocator, at:V3, r:f32, flat:f32, rr:*rng.Rng, col:color.Rgba8, info:[4]u8) Allocator.Error!void {
  const S = 6;
  var ring:[S]V3 = undefined;
  const turn = rr.range(0, m.tau);
  for (&ring, 0..) |*p, j| {
    const a = turn + m.tau * m.ratio(j, S);
    const d = r * rr.range(0.75, 1.25);
    p.* = at + v3(@cos(a) * d, r * flat * rr.range(0, 0.25), @sin(a) * d);
  }
  const top = at + v3(r * rr.range(-0.08, 0.08), r * flat, r * rr.range(-0.08, 0.08));
  const below = at - v3(0, r * flat * 0.6, 0);
  for (0..S) |j| {
    const a = ring[j];
    const b = ring[(j + 1) % S];
    try tri(out, gpa, .{top, b, a}, .{col, col, col}, info);
    try tri(out, gpa, .{below, a, b}, .{col, col, col}, info);
  }
}
