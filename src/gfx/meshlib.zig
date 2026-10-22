//! catalogue of rigid procedural part meshes. Each is built once at startup
//! in its own local space; anything that is "made of parts" (the player,
//! resource nodes, motes, later structures) draws instances of these with a
//! per-instance transform, so procedural animation is just transform math.
const std = @import("std");
const m = @import("../core/math.zig");
const Rng = @import("../core/rng.zig").Rng;
const mg = @import("meshgen.zig");

pub const Id = enum {
  wolf_torso, wolf_belly, wolf_head, wolf_limb, wolf_paw, leaf_tuft,
  node_grit, node_fibre, node_ley, mote,
  conduit, sap_cache, germinator, research_bloom, research_orb, item_pod,
};
pub const count = @typeInfo(Id).@"enum".fields.len;

const V3 = m.V3;
const v3 = m.v3;

// vine-wolf palette: woody cores, living vines, leaves, amber sap.
const core = mg.rgb(.{0.20, 0.26, 0.13}, 255);
const vine = mg.rgb(.{0.36, 0.58, 0.24}, 255);
const leaf_dark = mg.rgb(.{0.16, 0.42, 0.20}, 255);
const leaf_lite = mg.rgb(.{0.40, 0.80, 0.38}, 255);
const sap = mg.rgb(.{1.0, 0.68, 0.22}, 255);

fn torsoProfile(k:f32) f32 {
  // narrow waist at the hips, broad ribcage, tapering into the neck
  return 0.085 + 0.05 * @sin(k * std.math.pi * 0.85) + 0.02 * k;
}
fn limbProfile(k:f32) f32 { return 0.5 * (1 - 0.3 * k); }
fn evenProfile(_:f32) f32 { return 0.5; }
fn stalkProfile(k:f32) f32 { return 0.14 * (1 - 0.45 * k) + 0.05 * @exp(-k * 12); }
fn snoutProfile(k:f32) f32 { return 0.055 * (1 - 0.45 * k); }

pub fn build(b:*mg.Builder, ranges:*[count][2]u32) !void {
  inline for (0..count) |i| {
    const first = b.mark();
    try buildOne(b, @enumFromInt(i));
    ranges[i] = .{@intCast(first), @intCast(b.mark() - first)};
  }
}

fn buildOne(b:*mg.Builder, id:Id) !void {
  var rng = Rng.init(0x9A27 + @as(u64, @intFromEnum(id)));
  switch (id) {
    // hips at origin, chest top at y=0.5, forward is +Z
    .wolf_torso => {
      const s = b.mark();
      try mg.bundle(b, torsoProfile, 7, 2.4, core, vine);
      b.xform(s, m.scale3(v3(1.25, 0.5, 0.95)));
      // pectorals: broad leaf-plated muscles over the ribcage
      for ([_]f32{-1, 1}) |side| {
        try mg.ellipsoid(b, .{.center = v3(side * 0.065, 0.36, 0.075), .radii = v3(0.07, 0.055, 0.04), .col = leaf_dark, .t = 0.7});
        try mg.ellipsoid(b, .{.center = v3(side * 0.07, 0.365, 0.09), .radii = v3(0.055, 0.04, 0.025), .col = leaf_lite, .part = .leaf, .t = 0.7});
      }
      // collarbone vine across the shoulders
      try b.tube(&.{v3(-0.17, 0.46, 0.0), v3(0, 0.44, 0.06), v3(0.17, 0.46, 0.0)}, &.{0.9, 0.9, 0.9}, 0.022, 0.022, vine, .stem, 5);
    },
    // unit sphere of sap wrapped in a vine net; scaled by how full the player is
    .wolf_belly => {
      try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(1, 1, 1), .col = sap, .part = .bloom, .rings = 10, .segs = 14, .t = 0.4});
      for (0..6) |i| {
        const a = @as(f32, @floatFromInt(i)) / 6 * std.math.tau;
        var path:[9]V3 = undefined;
        var ts:[9]f32 = undefined;
        for (0..9) |j| {
          const th = @as(f32, @floatFromInt(j)) / 8 * std.math.pi;
          const tw = a + th * 0.5;
          path[j] = v3(@sin(th) * @cos(tw), @cos(th), @sin(th) * @sin(tw)) * m.splat(1.05);
          ts[j] = 0.4;
        }
        try b.tube(&path, &ts, 0.07, 0.07, vine, .stem, 4);
      }
    },
    // neck joint at origin, snout along +Z
    .wolf_head => {
      try mg.ellipsoid(b, .{.center = v3(0, 0.08, 0.0), .radii = v3(0.1, 0.095, 0.11), .col = core, .t = 1});
      const s = b.mark();
      try mg.bundle(b, snoutProfile, 5, 1.6, core, vine);
      b.xform(s, m.chain(.{m.translate(v3(0, 0.06, 0.05)), m.rotX(std.math.pi / 2.0 - 0.15), m.scale3(v3(1, 0.17, 1))}));
      try mg.ellipsoid(b, .{.center = v3(0, 0.085, 0.225), .radii = v3(0.022, 0.018, 0.018), .col = mg.rgb(.{0.08, 0.06, 0.05}, 255), .t = 1});
      for ([_]f32{-1, 1}) |side| {
        // glowing sap eyes
        try mg.ellipsoid(b, .{.center = v3(side * 0.055, 0.12, 0.085), .radii = v3(0.02, 0.016, 0.014), .col = sap, .part = .bloom, .rings = 5, .segs = 7, .t = 1});
        // ears: upright curled leaves
        try b.blade(v3(side * 0.06, 0.16, -0.01), m.norm(v3(side * 0.35, 0, -0.25)), 0.15, 0.055, -2.2, leaf_dark, leaf_lite, 1, .leaf);
      }
      // mane: leaves sweeping back off the skull
      for (0..6) |i| {
        const a = (@as(f32, @floatFromInt(i)) - 2.5) * 0.35;
        try b.blade(v3(0, 0.15, -0.05), m.norm(v3(@sin(a) * 0.6, 0, -1)), 0.14 * rng.range(0.8, 1.2), 0.035, 0.6, leaf_dark, leaf_lite, 1, .leaf);
      }
    },
    // unit limb along +Y; instances scale (thickness, length, thickness)
    .wolf_limb => try mg.bundle(b, limbProfile, 4, 2.0, core, vine),
    .wolf_paw => {
      try mg.ellipsoid(b, .{.center = v3(0, 0.02, 0.02), .radii = v3(0.045, 0.028, 0.06), .col = core, .rings = 5, .segs = 8});
      for ([_]f32{-0.025, 0, 0.025}) |x| try b.cone(v3(x, 0.015, 0.07), m.norm(v3(x, -0.3, 1)), 0.035, 0.008, mg.rgb(.{0.85, 0.8, 0.6}, 255), 0, .thorn);
    },
    .leaf_tuft => {
      for (0..5) |i| {
        const a = @as(f32, @floatFromInt(i)) / 5 * std.math.tau;
        try b.blade(v3(0, 0, 0), v3(@cos(a), 0, @sin(a)), 0.12 * rng.range(0.8, 1.2), 0.04, -0.4, leaf_dark, leaf_lite, 1, .leaf);
      }
    },
    // resource nodes, in tile space centred on the tile
    .node_grit => {
      for (0..6) |_| {
        const r = rng.range(0.06, 0.14);
        const col = mg.rgb(.{rng.range(0.45, 0.6), rng.range(0.42, 0.52), rng.range(0.4, 0.48)}, 255);
        try mg.ellipsoid(b, .{.center = v3(rng.range(-0.3, 0.3), r * 0.4, rng.range(-0.3, 0.3)), .radii = v3(r, r * 0.7, r * rng.range(0.8, 1.2)), .col = col, .rings = 3, .segs = 5});
      }
    },
    .node_fibre => {
      for (0..7) |_| {
        const a = rng.range(0, std.math.tau);
        const r0 = rng.range(0.05, 0.2);
        const r1 = r0 + rng.range(0.12, 0.25);
        const h = rng.range(0.08, 0.2);
        var path:[6]V3 = undefined;
        var ts:[6]f32 = undefined;
        for (0..6) |j| {
          const k = @as(f32, @floatFromInt(j)) / 5;
          const r = m.lerp(r0, r1, k);
          path[j] = v3(@cos(a + k * 0.6) * r, @sin(k * std.math.pi) * h - 0.02, @sin(a + k * 0.6) * r);
          ts[j] = k;
        }
        try b.tube(&path, &ts, 0.022, 0.012, mg.rgb(.{0.55, 0.45, 0.28}, 255), .tendril, 4);
      }
      try mg.ellipsoid(b, .{.center = v3(0, 0.02, 0), .radii = v3(0.09, 0.05, 0.09), .col = mg.rgb(.{0.3, 0.5, 0.22}, 255), .rings = 4, .segs = 7});
    },
    .node_ley => {
      for (0..5) |_| {
        const base = v3(rng.range(-0.22, 0.22), -0.02, rng.range(-0.22, 0.22));
        const dir = m.norm(v3(rng.range(-0.45, 0.45), 1, rng.range(-0.45, 0.45)));
        try b.cone(base, dir, rng.range(0.25, 0.5), rng.range(0.04, 0.07), mg.rgb(.{0.7, 0.5, 1.0}, 255), 1, .bloom);
      }
    },
    // structures: built around the footprint centre, +X is "forward" for conduits
    .conduit => {
      const s = b.mark();
      try mg.bundle(b, evenProfile, 3, 3.0, core, mg.rgb(.{0.5, 0.38, 0.22}, 255));
      b.xform(s, m.chain(.{m.translate(v3(-0.5, 0.1, 0)), m.rotZ(-std.math.pi / 2.0), m.scale3(v3(0.2, 1, 0.2))}));
      // sap beads that light up as items pass, and a leaf pointing the way
      for ([_]f32{-0.3, 0, 0.3}) |x| try mg.ellipsoid(b, .{.center = v3(x, 0.17, 0), .radii = v3(0.045, 0.04, 0.045), .col = sap, .part = .bloom, .rings = 4, .segs = 6, .t = x + 0.5});
      try b.blade(v3(0.25, 0.14, 0), v3(1, 0, 0), 0.3, 0.1, -0.2, leaf_dark, leaf_lite, 1, .leaf);
      for ([_]f32{-0.35, 0.35}) |x| for ([_]f32{-1, 1}) |z| try b.cone(v3(x, 0.08, z * 0.05), m.norm(v3(0, -1, z * 0.6)), 0.12, 0.025, core, 0, .tendril);
    },
    .sap_cache => {
      try mg.ellipsoid(b, .{.center = v3(0, 0.3, 0), .radii = v3(0.33, 0.32, 0.33), .col = mg.rgb(.{0.55, 0.38, 0.18}, 255), .rings = 9, .segs = 12, .t = 0.4});
      try mg.ellipsoid(b, .{.center = v3(0, 0.3, 0.27), .radii = v3(0.13, 0.15, 0.08), .col = sap, .part = .bloom, .t = 0.4});
      for (0..5) |i| {
        const a = @as(f32, @floatFromInt(i)) / 5 * std.math.tau;
        var path:[7]V3 = undefined;
        var ts:[7]f32 = undefined;
        for (0..7) |j| {
          const th = @as(f32, @floatFromInt(j)) / 6 * std.math.pi;
          path[j] = v3(@sin(th) * @cos(a + th * 0.4) * 0.35, 0.3 + @cos(th) * 0.34, @sin(th) * @sin(a + th * 0.4) * 0.35);
          ts[j] = 0.5;
        }
        try b.tube(&path, &ts, 0.025, 0.025, vine, .stem, 4);
      }
      for (0..5) |i| {
        const a = @as(f32, @floatFromInt(i)) / 5 * std.math.tau;
        try b.blade(v3(0, 0.6, 0), v3(@cos(a), 0, @sin(a)), 0.22, 0.08, -0.5, leaf_dark, leaf_lite, 1, .leaf);
      }
    },
    .germinator => {
      try mg.ellipsoid(b, .{.center = v3(0, 0.05, 0), .radii = v3(0.95, 0.12, 0.95), .col = core, .rings = 5, .segs = 16});
      for (0..9) |i| {
        const a = @as(f32, @floatFromInt(i)) / 9 * std.math.tau;
        try b.blade(v3(@cos(a) * 0.2, 0.12, @sin(a) * 0.2), v3(@cos(a), 0, @sin(a)), 0.8, 0.3, -0.9, leaf_dark, leaf_lite, 0.6, .leaf);
      }
      try mg.ellipsoid(b, .{.center = v3(0, 0.55, 0), .radii = v3(0.38, 0.45, 0.38), .col = mg.rgb(.{0.75, 0.95, 0.5}, 255), .part = .bloom, .rings = 10, .segs = 14, .t = 0.8});
      for (0..4) |i| {
        const a = @as(f32, @floatFromInt(i)) / 4 * std.math.tau + 0.4;
        var path:[8]V3 = undefined;
        var ts:[8]f32 = undefined;
        for (0..8) |j| {
          const k = @as(f32, @floatFromInt(j)) / 7;
          path[j] = v3(@cos(a) * (0.8 - 0.75 * k), 0.1 + @sin(k * std.math.pi) * 0.9 + k * 0.3, @sin(a) * (0.8 - 0.75 * k));
          ts[j] = k;
        }
        try b.tube(&path, &ts, 0.05, 0.02, vine, .stem, 5);
      }
    },
    .research_bloom => {
      try mg.ellipsoid(b, .{.center = v3(0, 0.05, 0), .radii = v3(0.9, 0.12, 0.9), .col = core, .rings = 5, .segs = 16});
      const s = b.mark();
      try mg.bundle(b, stalkProfile, 6, 3.2, core, mg.rgb(.{0.42, 0.3, 0.6}, 255));
      b.xform(s, m.scale3(v3(1.6, 1.5, 1.6)));
      for (0..11) |i| {
        const a = @as(f32, @floatFromInt(i)) * 2.39996;
        const r = 0.15 + 0.02 * @as(f32, @floatFromInt(i));
        try b.blade(v3(@cos(a) * r * 0.3, 1.45, @sin(a) * r * 0.3), v3(@cos(a), 0, @sin(a)), 0.55 + r, 0.22, -0.7, mg.rgb(.{0.35, 0.22, 0.55}, 255), mg.rgb(.{0.8, 0.6, 1.0}, 255), 1, .leaf);
      }
      for (0..4) |i| {
        const a = @as(f32, @floatFromInt(i)) / 4 * std.math.tau;
        try b.cone(v3(@cos(a) * 0.6, 0.1, @sin(a) * 0.6), m.norm(v3(@cos(a) * 0.3, 1, @sin(a) * 0.3)), 0.6, 0.06, mg.rgb(.{0.6, 0.5, 0.9}, 255), 0.3, .bloom);
      }
    },
    // hovers above the research bloom; spun and bobbed per instance
    .research_orb => {
      try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(0.22, 0.22, 0.22), .col = mg.rgb(.{0.85, 0.7, 1.0}, 255), .part = .bloom, .rings = 10, .segs = 14, .t = 1});
      for (0..8) |i| {
        const a = @as(f32, @floatFromInt(i)) / 8 * std.math.tau;
        try b.cone(v3(@cos(a) * 0.32, 0, @sin(a) * 0.32), v3(-@sin(a), 0.2, @cos(a)), 0.14, 0.025, mg.rgb(.{1, 0.85, 0.6}, 255), 1, .bloom);
      }
    },
    // a generic carried item, tinted per item
    .item_pod => try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(0.09, 0.08, 0.09), .col = mg.rgb(.{0.9, 0.9, 0.9}, 255), .part = .bloom, .rings = 5, .segs = 7, .t = 1}),
    .mote => {
      try mg.ellipsoid(b, .{.center = v3(0, 0, 0), .radii = v3(0.06, 0.06, 0.06), .col = mg.rgb(.{1, 0.95, 0.75}, 255), .part = .bloom, .rings = 4, .segs = 6, .t = 1});
      for ([_]V3{v3(1, 0, 0), v3(-1, 0, 0), v3(0, 1, 0), v3(0, -1, 0), v3(0, 0, 1), v3(0, 0, -1)}) |d| {
        try b.cone(d * m.splat(0.03), d, 0.11, 0.018, mg.rgb(.{1, 0.9, 0.6}, 255), 1, .bloom);
      }
    },
  }
}
