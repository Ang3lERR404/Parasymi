//! the player: an anthropomorphic wolf woven from vines, leaves and sap.
//! Movement is tile-aware (no wading, one terrace step at a time) and every
//! motion is procedural: a digitigrade gait, counter-swinging arms, a spring
//! driven tail, breathing, and a sap belly that swells with what it carries.
const std = @import("std");
const Allocator = std.mem.Allocator;
const m = @import("../core/math.zig");
const items = @import("../sim/items.zig");
const World = @import("../world/world.zig").World;
const parts = @import("parts.zig");
const Parts = parts.Parts;

pub const SLOTS = 24;
pub const REACH:f32 = 2.4;
const STEP_UP:f32 = 0.45;
/// leg segment lengths: upper leg (thigh + shin, hip to hock) 0.32, lower
/// leg (metatarsal + paw, hock to toe) ~0.66, about twice as long.
const THIGH:f32 = 0.18;
const SHIN:f32 = 0.14;
const META:f32 = 0.56;
/// the belly's sap at its centre lets the body behind show through faintly
const SAP_OPACITY:f32 = 0.72;

const V3 = m.V3;
const v3 = m.v3;
const T = m.translate;
const S = m.scale3;

pub const Player = struct {
  /// feet position (y follows the terrain)
  pos:V3,
  vel:V3 = v3(0, 0, 0),
  y_v:f32 = 0,
  facing:f32 = 0,
  turn:f32 = 0,
  inv:items.Inventory(SLOTS) = .{},

  // animation state
  t:f32 = 0,
  phase:f32 = 0,
  stride:f32 = 0,
  belly:f32 = 0,
  belly_v:f32 = 0,
  jig:f32 = 0,
  jig_v:f32 = 0,
  tail:[3]f32 = @splat(0),
  tail_v:[3]f32 = @splat(0),
  /// 0..1 blend toward the work gesture (gathering, planting, harvesting)
  reach:f32 = 0,
  reach_v:f32 = 0,
  /// where the hands are busy (gathering, weaving, ...); null while idle
  work:?V3 = null,

  /// tile-aware: no wading, one terrace step at a time.
  pub fn move(p:*Player, wish:[2]f32, sprint:bool, ground:*const World, dt:f32) void {
    const speed:f32 = if (sprint) 6.5 else 4.0;
    const target = v3(wish[0] * speed, 0, wish[1] * speed);
    const k = @min(1, dt * 12);
    p.vel += (target - p.vel) * m.splat(k);
    if (p.work != null) p.vel *= m.splat(0.85);

    const here = ground.walkable(m.tileOf(p.pos[0]), m.tileOf(p.pos[2])) orelse p.pos[1];
    // resolve each axis separately so the wolf slides along cliffs and shores
    inline for (.{0, 2}) |axis| {
      var next = p.pos;
      next[axis] += p.vel[axis] * dt;
      // probe a little ahead so the body does not clip into terrace walls
      var probe = next;
      probe[axis] += if (p.vel[axis] > 0) @as(f32, 0.25) else -0.25;
      const ok = if (ground.walkable(m.tileOf(probe[0]), m.tileOf(probe[2]))) |h| h - here <= STEP_UP else false;
      if (ok) p.pos[axis] = next[axis] else p.vel[axis] = 0;
    }
    const h = ground.walkable(m.tileOf(p.pos[0]), m.tileOf(p.pos[2])) orelse here;
    m.spring(&p.pos[1], &p.y_v, h, 18, dt);

    // face where we move, or what we work on
    var want = p.facing;
    if (p.work) |w| {
      want = m.atan2(w[0] - p.pos[0], w[2] - p.pos[2]);
    } else if (@abs(p.vel[0]) + @abs(p.vel[2]) > 0.3) {
      want = m.atan2(p.vel[0], p.vel[2]);
    }
    const diff = m.angleDiff(p.facing, want);
    const turn = diff * @min(1, dt * 10);
    p.facing += turn;
    p.turn = turn / @max(dt, 1e-4);
  }

  pub fn animate(p:*Player, dt:f32) void {
    p.t += dt;
    const spd = @sqrt(p.vel[0] * p.vel[0] + p.vel[2] * p.vel[2]);
    const prev = p.phase;
    p.phase += spd * dt * 2.6;
    p.stride += (m.clamp01(spd / 4.0) - p.stride) * @min(1, dt * 8);
    // a footfall every half cycle kicks the belly
    if (@floor(prev / m.pi) != @floor(p.phase / m.pi)) p.jig_v -= 2.2 * p.stride;

    const fill = @sqrt(p.inv.fill());
    m.spring(&p.belly, &p.belly_v, fill, 4, dt);
    m.spring(&p.jig, &p.jig_v, 0, 9, dt);
    m.spring(&p.reach, &p.reach_v, if (p.work != null) 1 else 0, 10, dt);

    // tail: each segment chases the one before it, steered by turning and gait
    var target = m.clamp(-p.turn * 0.12, -0.8, 0.8) + @sin(p.t * 2.3) * 0.25 * (1 - p.stride) + @sin(p.phase) * 0.15 * p.stride;
    for (0..3) |i| {
      m.spring(&p.tail[i], &p.tail_v[i], target, 7 - m.f(i) * 1.5, dt);
      target = p.tail[i];
    }
  }

  /// emit every part; returns where each paw (left, right) touches down.
  pub fn rig(p:*const Player, out:*Parts) Allocator.Error![2]V3 {
    var feet:[2]V3 = undefined;
    const t = p.t;
    const st = p.stride;
    const lean = 0.14 * st + 0.35 * p.reach;
    const hip_y = 0.7 - 0.035 * st * @abs(@cos(p.phase)) - 0.06 * p.reach;
    const root = m.chain(.{T(p.pos), m.rotY(p.facing)});
    const hips = m.chain(.{root, T(v3(0, hip_y, 0))});
    const torso = m.chain(.{hips, m.rotY(@sin(p.phase) * 0.08 * st), m.rotX(lean)});
    const breath = 1 + 0.025 * @sin(t * 1.7);
    const vine_look:parts.Look = .{.glow = 0.25, .phase = 0.1};

    try out.emit(.wolf_torso, m.chain(.{torso, S(v3(breath, 1, breath))}), vine_look);

    // the belly: a sap sac that swells forward with the inventory and jiggles
    const b = p.belly;
    const bs = (0.75 + 0.95 * b);
    try out.emit(.wolf_belly, m.chain(.{
      torso, T(v3(0, 0.16 - 0.02 * b, 0.05 + 0.07 * b)),
      S(v3(0.1 * bs * (1 - p.jig * 0.08), 0.095 * bs * (1 + p.jig * 0.1), 0.095 * bs * (1 - p.jig * 0.05))),
    }), .{.glow = 0.35 + 0.65 * b, .phase = 0.3, .fade = SAP_OPACITY});

    // head looks down into the work, nods with breath
    const nod = @sin(t * 1.7) * 0.03 + p.reach * 0.35 - lean * 0.8;
    const neck = m.chain(.{torso, T(v3(0, 0.5, 0.05)), m.rotX(nod)});
    try joint(out, neck, 0.075);
    try out.emit(.wolf_head, m.chain(.{neck, T(v3(0, 0.0, 0.02))}), .{.glow = 0.9, .flutter = 1, .phase = 0.5});

    for ([_]f32{-1, 1}) |side| {
      try out.emit(.leaf_tuft, m.chain(.{torso, T(v3(side * 0.17, 0.47, -0.01)), m.rotZ(-side * 0.5)}), .{.flutter = 1, .phase = 0.2 + side * 0.1});

      // arms swing against the legs; while working they reach and dig
      const swing = @sin(p.phase + (if (side > 0) @as(f32, 0) else m.pi)) * 0.6 * st;
      const dig = -1.15 + @sin(t * 9 + side) * 0.25;
      const a = m.lerp(swing, dig, p.reach);
      const shoulder = m.chain(.{torso, T(v3(side * 0.19, 0.43, 0)), m.rotZ(side * 0.15), m.rotX(a)});
      try joint(out, shoulder, 0.075);
      try out.emit(.wolf_limb, m.chain(.{shoulder, m.rotX(m.pi), S(v3(0.13, 0.25, 0.13))}), vine_look);
      const elbow = m.chain(.{shoulder, T(v3(0, -0.25, 0)), m.rotX(-(0.3 + 0.35 * st * @max(0, -swing)) - p.reach * 0.7)});
      try joint(out, elbow, 0.058);
      try out.emit(.wolf_limb, m.chain(.{elbow, m.rotX(m.pi), S(v3(0.1, 0.23, 0.1))}), vine_look);
      const wrist = m.chain(.{elbow, T(v3(0, -0.24, 0))});
      try joint(out, wrist, 0.042);
      try out.emit(.wolf_paw, m.chain(.{wrist, m.rotX(1.2)}), vine_look);

      // digitigrade legs: a short upper leg (thigh forward, shin back to the
      // hock, which bends backward) over a lower leg (long metatarsal + paw)
      // about twice its length. At rest the paw lands under the hip.
      const lp = p.phase + (if (side > 0) m.pi else @as(f32, 0));
      const lift = @max(0, @cos(lp)) * st;
      const th = -0.65 - @sin(lp) * 0.45 * st + 0.25 * p.reach;
      const kn = 1.85 + 0.55 * lift + 0.3 * p.reach;
      const mt = -1.6 - 0.4 * lift - 0.25 * p.reach;
      const thigh = m.chain(.{hips, T(v3(side * 0.1, 0, 0)), m.rotX(th)});
      try joint(out, thigh, 0.095);
      try out.emit(.wolf_limb, m.chain(.{thigh, m.rotX(m.pi), S(v3(0.18, THIGH, 0.18))}), vine_look);
      const knee = m.chain(.{thigh, T(v3(0, -THIGH, 0)), m.rotX(kn)});
      try joint(out, knee, 0.075);
      try out.emit(.wolf_limb, m.chain(.{knee, m.rotX(m.pi), S(v3(0.13, SHIN, 0.13))}), vine_look);
      const hock = m.chain(.{knee, T(v3(0, -SHIN, 0)), m.rotX(mt)});
      try joint(out, hock, 0.058);
      try out.emit(.wolf_limb, m.chain(.{hock, m.rotX(m.pi), S(v3(0.095, META, 0.095))}), vine_look);
      const heel = m.chain(.{hock, T(v3(0, -META, 0))});
      try joint(out, heel, 0.038);
      const paw = m.chain(.{heel, m.rotX(-(th + kn + mt))});
      try out.emit(.wolf_paw, paw, vine_look);
      const c = m.mulV(paw, .{0, 0, 0.03, 1});
      feet[if (side > 0) 1 else 0] = v3(c[0], c[1], c[2]);
    }

    // tail: three segments, each bending by its spring, ending in a leaf tuft
    var seg = m.chain(.{hips, T(v3(0, 0.03, -0.1)), m.rotX(-1.25 + 0.15 * st)});
    for (0..3) |i| {
      const fi = m.f(i);
      seg = m.chain(.{seg, m.rotZ(p.tail[i]), m.rotX(-0.18)});
      try joint(out, seg, 0.065 - 0.014 * fi);
      try out.emit(.wolf_limb, m.chain(.{seg, S(v3(0.12 - 0.025 * fi, 0.17, 0.12 - 0.025 * fi))}), vine_look);
      seg = m.chain(.{seg, T(v3(0, 0.16, 0))});
    }
    try out.emit(.leaf_tuft, m.chain(.{seg, m.rotX(-0.6), S(v3(1.3, 1.3, 1.3))}), .{.flutter = 1.5, .phase = 0.7});
    return feet;
  }

  pub fn chest(p:*const Player) V3 { return p.pos + v3(0, 1.0, 0); }

  pub fn inReach(p:*const Player, wx:i32, wz:i32) bool {
    const c = m.tileCentre(wx, wz, 0);
    const dx = c[0] - p.pos[0];
    const dz = c[2] - p.pos[2];
    return dx * dx + dz * dz <= REACH * REACH;
  }
};

/// a woven knot where two parts meet, so bent joints never show a seam.
fn joint(out:*Parts, at:m.M4, r:f32) Allocator.Error!void {
  try out.emit(.wolf_joint, m.chain(.{at, S(m.splat(r))}), .{.glow = 0.25, .phase = 0.1});
}
