//! the player: an anthropomorphic wolf woven from vines, leaves and sap.
//! Movement is tile-aware (no wading, one terrace step at a time) and every
//! motion is procedural: a digitigrade gait, counter-swinging arms, a spring
//! driven tail, breathing, and a sap belly that swells with what it carries.
const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const m = @import("../core/math.zig");
const items = @import("../sim/items.zig");
const World = @import("../world/world.zig").World;
const mg = @import("../gfx/meshgen.zig");
const pal = @import("../gfx/meshes/palette.zig");
const torso_mesh = @import("../gfx/meshes/wolf_torso.zig");
const rump_mesh = @import("../gfx/meshes/wolf_rump.zig");
const thigh_mesh = @import("../gfx/meshes/wolf_thigh.zig");
const calf_mesh = @import("../gfx/meshes/wolf_calf.zig");
const tailbone = @import("../gfx/meshes/wolf_tailbone.zig");
const head_mesh = @import("../gfx/meshes/wolf_head.zig");
const upper_arm = @import("../gfx/meshes/wolf_upper_arm.zig");
const forearm = @import("../gfx/meshes/wolf_forearm.zig");
const foot_mesh = @import("../gfx/meshes/wolf_foot.zig");
const meshlib = @import("../gfx/meshlib.zig");
const parts = @import("parts.zig");
const Parts = parts.Parts;

pub const SLOTS = 24;
pub const REACH:f32 = 2.4;
const STEP_UP:f32 = 0.45;
const WALK_SPEED:f32 = 4.0;
const SPRINT_SPEED:f32 = 6.5;
const ACCEL_RESPONSE:f32 = 12; // how quickly velocity matches the wish
const PROBE:f32 = 0.25; // body radius probed ahead of the centre
const GAIT_FREQ:f32 = 2.6; // phase advance per unit of speed
const STRIDE_RESPONSE:f32 = 8; // how quickly stride eases in/out
const TURN_RESPONSE:f32 = 10; // how quickly facing matches the target
const GROUND_FREQ:f32 = 18; // spring frequency for following terrain height

/// leg segments, anthro digitigrade: a near-vertical thigh, a long calf
/// angled back to a high hock, a shorter metatarsal angled forward, and a
/// long flat foot on the ground (side view: a clear Z)
const THIGH = thigh_mesh.LEN;
const SHIN = calf_mesh.LEN;
const META:f32 = 0.335;
/// paw beans and the nose: sap made denser (80%) and browner than the belly
const BEAN_OPACITY:f32 = 0.8;
const BEAN_TINT = [4]f32{ 0.72, 0.5, 0.38, 1 };
const NOSE_TINT = [4]f32{ 0.3, 0.22, 0.2, 1 };
/// the inner ears' sap
const EAR_OPACITY:f32 = 0.5;
/// the belly's sap at its centre lets the body behind show through faintly;
/// the pectorals are solidified sap, 30% less see-through.
const SAP_OPACITY:f32 = 0.72;
const PEC_OPACITY:f32 = 1 - (1 - SAP_OPACITY) * 0.7;
/// the empty belly's radii (torso space); full, it is 35% larger and sags
const BELLY_R = v3(0.13, 0.12, 0.12);
const BELLY_GROW:f32 = 0.35;
const BELLY_SAG:f32 = 0.12;
/// how strongly the wolf's acceleration is felt by what hangs in and on its
/// body (m/s^2 down to a few centimetres of lag)
const SLOSH:f32 = 0.05;
/// a footfall drops the belly's contents a little
const STEP_KICK:f32 = 0.18;

/// one of the heavier things carried, hanging in the sap on its own spring.
const Lump = struct {
  /// rest place within the belly (unit ball, scaled by the room inside)
  rest:V3,
  k:f32,
  c:f32,
  mass:f32,
};
const lumps = [_]Lump{
  .{ .rest = v3(0.35, -0.3, 0.3), .k = 55, .c = 5, .mass = 0.7 },
  .{ .rest = v3(-0.4, -0.35, 0.15), .k = 70, .c = 6, .mass = 0.9 },
  .{ .rest = v3(0.05, -0.6, -0.1), .k = 40, .c = 4, .mass = 1.0 },
  .{ .rest = v3(0.4, 0.15, -0.2), .k = 80, .c = 7, .mass = 0.5 },
  .{ .rest = v3(-0.25, 0.05, 0.45), .k = 62, .c = 5.5, .mass = 0.6 },
};
const LUMP_R:f32 = 0.06;
/// the pectorals: dense gel on a spring each (left, right)
const PEC_K = [2]f32{ 60, 55 };
const PEC_C:f32 = 6;
const PEC_MASS:f32 = 0.8;
const PEC_MAX:f32 = 0.02;
/// the rear: structural vine with a little sap, firmer than the chest and
/// never idly moving
const RUMP_K:f32 = 80;
const RUMP_C:f32 = 7;
const RUMP_MAX:f32 = 0.015;
/// the rear's sap nodes are mostly see-through
const RUMP_SAP_OPACITY:f32 = 0.4;

/// a point mass on a spring: offset from its rest place and velocity.
const Spring3 = struct {
  pos:V3 = v3(0, 0, 0),
  vel:V3 = v3(0, 0, 0),
};
/// the tail: spring-steered joints, each this long, and how finely the vine
/// woven through them is sampled.
const TAIL_JOINTS = 3;
const TAIL_SEG:f32 = 0.16;
const TAIL_RES = 20;
/// the tail leaves the tailbone up and back, 30 degrees above horizontal
/// (the angle that turns +Y onto that direction), lifting a little with stride
const TAIL_ROOT_TILT:f32 = -(m.pi / 2.0 - m.pi / 6.0);
/// the tailbone's sap node is mostly see-through
const TAILBONE_SAP_OPACITY:f32 = 0.3;

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
  /// how full the belly looks, easing toward the inventory's fill
  fullness:f32 = 0,
  /// velocity last frame and the acceleration felt since, in the wolf's own
  /// frame (x right, z forward)
  last_vel:V3 = v3(0, 0, 0),
  accel:V3 = v3(0, 0, 0),
  /// what hangs in the belly (relative to its centre) and the pectorals'
  /// give (relative to their rest)
  lump:[lumps.len]Spring3 = @splat(.{}),
  pec:[2]Spring3 = @splat(.{}),
  rump:[2]Spring3 = @splat(.{}),
  /// each foot's contact with the ground (1 planted .. 0 lifted), eased;
  /// the central pad flattens with it
  pad:[2]f32 = @splat(1),
  pad_v:[2]f32 = @splat(0),
  tail:[3]f32 = @splat(0),
  tail_v:[3]f32 = @splat(0),
  /// 0..1 blend toward the work gesture (gathering, planting, harvesting)
  reach:f32 = 0,
  reach_v:f32 = 0,
  /// where the hands are busy (gathering, weaving, ...); null while idle
  work:?V3 = null,

  /// tile-aware: no wading, one terrace step at a time.
  pub fn move(p:*Player, wish:[2]f32, sprint:bool, ground:*const World, dt:f32) void {
    const speed:f32 = if (sprint) SPRINT_SPEED else WALK_SPEED;
    const target = v3(wish[0] * speed, 0, wish[1] * speed);
    const k = @min(1, dt * ACCEL_RESPONSE);
    p.vel += (target - p.vel) * m.splat3(k);
    if (p.work != null) p.vel *= m.splat3(0.85);

    const here = ground.walkable(m.tileOf(p.pos[0]), m.tileOf(p.pos[2])) orelse p.pos[1];
    // resolve each axis separately so the wolf slides along cliffs and shores
    inline for (.{ 0, 2 }) |axis| {
      var next = p.pos;
      next[axis] += p.vel[axis] * dt;
      // probe a little ahead so the body does not clip into terrace walls
      var probe = next;
      probe[axis] += if (p.vel[axis] > 0) PROBE else -PROBE;
      const ok = if (ground.walkable(m.tileOf(probe[0]), m.tileOf(probe[2]))) |h| h - here <= STEP_UP else false;
      if (ok) p.pos[axis] = next[axis] else p.vel[axis] = 0;
    }
    const h = ground.walkable(m.tileOf(p.pos[0]), m.tileOf(p.pos[2])) orelse here;
    m.spring(&p.pos[1], &p.y_v, h, GROUND_FREQ, dt);

    // face where we move, or what we work on
    var want = p.facing;
    if (p.work) |w| {
      want = m.atan2(w[0] - p.pos[0], w[2] - p.pos[2]);
    } else if (@abs(p.vel[0]) + @abs(p.vel[2]) > 0.3) {
      want = m.atan2(p.vel[0], p.vel[2]);
    }
    const diff = m.angleDiff(p.facing, want);
    const turn = diff * @min(1, dt * TURN_RESPONSE);
    p.facing += turn;
    p.turn = turn / @max(dt, 1e-4);
  }

  pub fn animate(p:*Player, dt:f32) void {
    p.t += dt;
    const spd = @sqrt(p.vel[0] * p.vel[0] + p.vel[2] * p.vel[2]);
    const prev = p.phase;
    p.phase += spd * dt * GAIT_FREQ;
    p.stride += (m.clamp01(spd / WALK_SPEED) - p.stride) * @min(1, dt * STRIDE_RESPONSE);
    // a footfall every half cycle drops what the belly carries
    const step = @floor(prev / m.pi) != @floor(p.phase / m.pi);

    p.fullness += (p.inv.fill() - p.fullness) * @min(1, dt * 2);
    m.spring(&p.reach, &p.reach_v, if (p.work != null) 1 else 0, 10, dt);

    // what the body feels: its acceleration, turned into its own frame
    const a = (p.vel - p.last_vel) / m.splat3(@max(dt, 1e-4));
    p.last_vel = p.vel;
    const al = m.mulV(m.rotY(-p.facing), .{ a[0], a[1], a[2], 0 });
    p.accel = v3(al[0], al[1], al[2]);
    p.slosh(step, dt);
    for (&p.pad, &p.pad_v, [_]f32{ -1, 1 }) |*c, *v, side| m.spring(c, v, 1 - m.clamp01(p.legLift(side) * 6), 14, dt);

    // tail: each segment chases the one before it, steered by turning and gait
    var target = m.clamp(-p.turn * 0.12, -0.8, 0.8) + @sin(p.t * 2.3) * 0.25 * (1 - p.stride) + @sin(p.phase) * 0.15 * p.stride;
    for (0..3) |i| {
      m.spring(&p.tail[i], &p.tail_v[i], target, 7 - m.f(i) * 1.5, dt);
      target = p.tail[i];
    }
  }

  /// the belly's lumps and the pectorals lag behind the body's acceleration
  /// (inertia), overshoot when it stops, and settle back on their springs.
  fn slosh(p:*Player, step:bool, dt:f32) void {
    const room = p.bellyRoom();
    for (&p.lump, lumps) |*s, l| {
      if (step) s.vel[1] -= STEP_KICK * p.stride;
      const force = -p.accel * m.splat3(l.mass * SLOSH);
      m.springDamper(&s.pos, &s.vel, l.rest * m.splat3(room), l.k, l.c, l.mass, force, dt);
      // stay inside the sac; hitting its wall stops the outward motion
      const d = m.len(s.pos);
      if (d > room) {
        const n = s.pos / m.splat3(d);
        s.pos = n * m.splat3(room);
        s.vel -= n * m.splat3(@max(m.dot(s.vel, n), 0));
      }
    }
    for (&p.pec, PEC_K) |*s, k| {
      m.springDamper(&s.pos, &s.vel, v3(0, 0, 0), k, PEC_C, PEC_MASS, -p.accel * m.splat3(PEC_MASS * SLOSH), dt);
      const d = m.len(s.pos);
      if (d > PEC_MAX) s.pos *= m.splat3(PEC_MAX / d);
    }
    for (&p.rump) |*s| {
      m.springDamper(&s.pos, &s.vel, v3(0, 0, 0), RUMP_K, RUMP_C, PEC_MASS, -p.accel * m.splat3(PEC_MASS * SLOSH), dt);
      const d = m.len(s.pos);
      if (d > RUMP_MAX) s.pos *= m.splat3(RUMP_MAX / d);
    }
  }

  /// a leg's place in the gait cycle, and how far it is lifted (0 planted)
  fn legPhase(p:*const Player, side:f32) f32 { return p.phase + (if (side > 0) m.pi else @as(f32, 0)); }
  fn legLift(p:*const Player, side:f32) f32 { return @max(0, @cos(p.legPhase(side))) * p.stride; }

  fn bellyScale(p:*const Player) f32 { return 1 + p.fullness * BELLY_GROW; }
  fn lumpRadius(p:*const Player) f32 { return LUMP_R * p.bellyScale() / (1 + BELLY_GROW); }
  /// how far a lump's centre may stray from the belly's centre: within 80%
  /// of the sac, and never poking through it
  fn bellyRoom(p:*const Player) f32 {
    return @max(@reduce(.Min, BELLY_R) * p.bellyScale() * 0.8 - p.lumpRadius(), 0.01);
  }

  /// emit every part; returns where each paw (left, right) touches down.
  pub fn rig(p:*const Player, out:*Parts) Allocator.Error![2]V3 {
    var feet:[2]V3 = undefined;
    const t = p.t;
    const st = p.stride;
    const lean = 0.14 * st + 0.35 * p.reach;
    const hip_y = 0.7 - 0.035 * st * @abs(@cos(p.phase)) - 0.06 * p.reach;
    const root = m.chain(&.{ T(p.pos), m.rotY(p.facing) });
    const hips = m.chain(&.{ root, T(v3(0, hip_y, 0)) });
    const torso = m.chain(&.{ hips, m.rotY(@sin(p.phase) * 0.08 * st), m.rotX(lean) });
    // the surface breathes: the torso swells 2%, the limbs 1% a beat later
    const breath = 1 + 0.02 * @sin(t * 1.7);
    const lb = 1 + 0.01 * @sin(t * 1.7 + 0.5);
    const vine_look:parts.Look = .{ .glow = 0.25, .phase = 0.1 };

    try out.emit(.wolf_torso, m.chain(&.{ torso, S(v3(breath, 1, breath)) }), vine_look);

    // the belly: a sap sac that inflates with the inventory, drops and sags
    // as it fills, with the heavier things inside showing through as shadows
    const b = p.fullness;
    const belly = m.chain(&.{ torso, T(v3(0, 0.16 - 0.04 * b, 0.05 + 0.05 * b)) });
    var held:usize = 0;
    for (p.inv.slot) |slot| if (slot != null) { held += 1; };
    for (p.lump[0..@min(held, lumps.len)]) |l| {
      try out.emit(.belly_lump, m.chain(&.{ belly, T(l.pos), S(m.splat3(p.lumpRadius())) }), .{ .glow = 0.25, .phase = 0.3 });
    }
    try out.emit(.wolf_belly, m.chain(&.{ belly, S(BELLY_R * m.splat3(p.bellyScale())) }), .{
      .glow = 0.35 + 0.65 * b, .phase = 0.3, .fade = SAP_OPACITY, .sag = BELLY_SAG * b,
    });

    // pectorals: broad dishes of solidified sap. Their bases sit on the
    // chest; the spring (and a slow idle) moves their surface like dense gel
    for ([_]meshlib.Id{ .wolf_pec_l, .wolf_pec_r }, [_]f32{ -1, 1 }, 0..) |id, side, i| {
      const idle = v3(0, 0.003 * @sin(t * m.tau / 3 + side * 1.3), 0);
      const at = torso_mesh.pec_centre * v3(side * breath, 1, breath);
      const give = p.pec[i].pos + idle;
      try out.emit(id, m.chain(&.{ torso, T(at) }), .{ .phase = 0.6, .fade = PEC_OPACITY, .give = .{ give[0], give[1], give[2] } });
    }
    // the rear: two knotted lobes of dense vine behind the hips
    for ([_]meshlib.Id{ .wolf_rump_l, .wolf_rump_r }, [_]f32{ -1, 1 }, 0..) |id, side, i| {
      const at = rump_mesh.centre * v3(side, 1, 1) + p.rump[i].pos;
      try out.emit(id, m.chain(&.{ hips, T(at) }), .{ .glow = 0.25, .phase = 0.15, .fade = RUMP_SAP_OPACITY });
    }

    // head looks down into the work, nods with breath
    const nod = @sin(t * 1.7) * 0.03 + p.reach * 0.35 - lean * 0.8;
    const neck = m.chain(&.{ torso, T(v3(0, 0.5, 0.05)), m.rotX(nod) });
    try joint(out, neck, 0.075);
    const head = m.chain(&.{ neck, T(v3(0, 0.0, 0.02)) });
    // its fur and cheek leaves barely stir: they lie on the head, not wave
    try out.emit(.wolf_head, head, .{ .glow = 0.9, .flutter = 0.15, .phase = 0.5 });
    try out.emit(.paw_bean, m.chain(&.{ head, T(head_mesh.nose), S(v3(0.021, 0.014, 0.013)) }), .{ .glow = 0.1, .fade = BEAN_OPACITY, .tint = NOSE_TINT });
    // ears: rooted in the skull, leaning a little forward and out; heavy,
    // so they do not flutter
    for ([_]f32{ -1, 1 }) |side| {
      const ear = m.chain(&.{ head, T(head_mesh.ear_root * v3(side, 1, 1)), m.rotZ(-side * 12 * m.pi / 180.0), m.rotX(12 * m.pi / 180.0) });
      try out.emit(.wolf_ear, ear, .{ .glow = 0.3, .phase = 0.5 + side * 0.1, .fade = EAR_OPACITY });
    }

    for ([_]f32{ -1, 1 }) |side| {
      try out.emit(.leaf_tuft, m.chain(&.{ torso, T(v3(side * 0.17, 0.47, -0.01)), m.rotZ(-side * 0.5) }), .{ .flutter = 1, .phase = 0.2 + side * 0.1 });

      // arms swing against the legs; while working they reach and dig
      const swing = @sin(p.phase + (if (side > 0) @as(f32, 0) else m.pi)) * 0.6 * st;
      const dig = -1.15 + @sin(t * 9 + side) * 0.25;
      const a = m.lerp(swing, dig, p.reach);
      const shoulder = m.chain(&.{ torso, T(v3(side * 0.19, 0.43, 0)), m.rotZ(side * 0.15), m.rotX(a) });
      // a deltoid caps the joint; bicep and tricep above a tapering forearm
      try out.emit(.wolf_deltoid, m.chain(&.{ shoulder, S(m.splat3(lb)) }), vine_look);
      try out.emit(.wolf_upper_arm, m.chain(&.{ shoulder, m.rotX(m.pi), S(v3(lb, 1, lb)) }), vine_look);
      const elbow = m.chain(&.{ shoulder, T(v3(0, -upper_arm.LEN, 0)), m.rotX(-(0.3 + 0.35 * st * @max(0, -swing)) - p.reach * 0.7) });
      try joint(out, elbow, 0.058);
      try out.emit(.wolf_forearm, m.chain(&.{ elbow, m.rotX(m.pi), S(v3(lb, 1, lb)) }), vine_look);
      const wrist = m.chain(&.{ elbow, T(v3(0, -forearm.LEN, 0)) });
      try joint(out, wrist, 0.042);
      try out.emit(.wolf_paw, m.chain(&.{ wrist, m.rotX(1.2) }), vine_look);

      // digitigrade legs, anthro proportions: near-vertical thigh, knee
      // bending forward, the calf angled back to a high hock, the metatarsal
      // angled forward to a long flat foot. At rest the ball lands under the hip.
      const lp = p.legPhase(side);
      const lift = p.legLift(side);
      const th = -0.25 - @sin(lp) * 0.45 * st + 0.25 * p.reach;
      const kn = 0.87 + 0.55 * lift + 0.3 * p.reach;
      const mt = -1.23 - 0.4 * lift - 0.25 * p.reach;
      const thigh = m.chain(&.{ hips, T(v3(side * 0.1, 0, 0)), m.rotX(th) });
      try joint(out, thigh, 0.095);
      try out.emit(.wolf_thigh, m.chain(&.{ thigh, m.rotX(m.pi), S(v3(lb, 1, lb)) }), vine_look);
      const knee = m.chain(&.{ thigh, T(v3(0, -THIGH, 0)), m.rotX(kn) });
      try joint(out, knee, 0.075);
      try out.emit(.wolf_calf, m.chain(&.{ knee, m.rotX(m.pi), S(v3(lb, 1, lb)) }), vine_look);
      const hock = m.chain(&.{ knee, T(v3(0, -SHIN, 0)), m.rotX(mt) });
      try joint(out, hock, 0.058);
      try out.emit(.wolf_limb, m.chain(&.{ hock, m.rotX(m.pi), S(v3(0.095 * lb, META, 0.095 * lb)) }), vine_look);
      const heel = m.chain(&.{ hock, T(v3(0, -META, 0)) });
      try joint(out, heel, 0.038);
      const foot = m.chain(&.{ heel, m.rotX(-(th + kn + mt)) });
      try out.emit(.wolf_foot, foot, vine_look);
      // the beans: one central pad that flattens 10% while planted, four toe pads
      const fi:usize = if (side > 0) 1 else 0;
      const bean:parts.Look = .{ .glow = 0.15, .fade = BEAN_OPACITY, .tint = BEAN_TINT };
      try out.emit(.paw_pad, m.chain(&.{ foot, T(foot_mesh.pad_at), S(v3(0.021, 0.006 * (1 - 0.1 * p.pad[fi]), 0.02)) }), bean);
      for (foot_mesh.toes) |tp| {
        try out.emit(.paw_bean, m.chain(&.{ foot, T(v3(tp[0], foot_mesh.SOLE_Y + 0.002, tp[1])), S(v3(0.0065, 0.004, 0.008)) }), bean);
      }
      const c = m.mulV(foot, .{ 0, 0, 0.04, 1 });
      feet[fi] = v3(c[0], c[1], c[2]);
    }

    // tail: the spring-steered joint chain gives the control points, and a
    // grown vine is woven through them afresh every frame, so it lags and
    // curves like a living thing instead of a row of rigid rods.
    try out.emit(.wolf_tailbone, m.chain(&.{ hips, T(tailbone.at) }), .{ .glow = 0.25, .phase = 0.15, .fade = TAILBONE_SAP_OPACITY });
    var seg = m.chain(&.{ hips, T(tailbone.at), m.rotX(TAIL_ROOT_TILT + 0.15 * st) });
    var ctrl:[TAIL_JOINTS + 1]V3 = undefined;
    ctrl[0] = m.origin(seg);
    for (0..TAIL_JOINTS) |i| {
      seg = m.chain(&.{ seg, m.rotZ(p.tail[i]), m.rotX(-0.18), T(v3(0, TAIL_SEG, 0)) });
      ctrl[i + 1] = m.origin(seg);
    }
    mg.grow(&ctrl, .{
      .start = ctrl[0], .direction = m.norm(ctrl[TAIL_JOINTS] - ctrl[0]), .length = TAIL_SEG * TAIL_JOINTS,
      .wobble = 0.06, .curl = 0.15, .taper = 0.2, .seed = 0x7A11,
    });
    var path:[TAIL_RES]V3 = undefined;
    m.splineResample(&ctrl, &path);
    var ts:[TAIL_RES]f32 = undefined;
    for (&ts, 0..) |*k, i| k.* = m.ratio(i, TAIL_RES - 1);
    var radii:[TAIL_RES]f32 = undefined;
    mg.taperRadii(0.06, 0.2, &radii);
    try mg.braid(&out.live, &path, &ts, &radii, 3, 4.0, pal.STRAND_WOBBLE, 0x7A11, pal.wolf_core, pal.wolf_vine);
    out.live_look = vine_look;
    // the tuft keeps the last joint's frame (smooth, no roll flips), moved
    // onto the vine's actual tip, which growth shifted slightly off the joint
    const tip = m.chain(&.{ T(path[TAIL_RES - 1] - m.origin(seg)), seg });
    try out.emit(.leaf_tuft, m.chain(&.{ tip, m.rotX(-0.6), S(v3(1.3, 1.3, 1.3)) }), .{ .flutter = 1.5, .phase = 0.7 });
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
  try out.emit(.wolf_joint, m.chain(&.{ at, S(m.splat3(r)) }), .{ .glow = 0.25, .phase = 0.1 });
}

test "belly contents lag a sprint, overshoot a stop, then settle" {
  var p:Player = .{ .pos = v3(0, 0, 0) };
  _ = p.inv.add(.grit, 50);
  const dt:f32 = 1.0 / 60.0;
  for (0..120) |_| p.animate(dt);
  const rest = p.lump[0].pos;
  // a burst of speed forward (+z): the lump swings back
  p.vel = v3(0, 0, 4);
  p.animate(dt);
  for (0..3) |_| p.animate(dt);
  try testing.expect(p.lump[0].pos[2] < rest[2] - 0.005);
  // run steadily, then stop dead: it overshoots forward
  for (0..120) |_| p.animate(dt);
  p.vel = v3(0, 0, 0);
  for (0..4) |_| p.animate(dt);
  try testing.expect(p.lump[0].pos[2] > rest[2] + 0.005);
  // and it never leaves the sac
  for (p.lump) |l| try testing.expect(m.len(l.pos) <= p.bellyRoom() + 1e-4);
  for (p.pec) |q| try testing.expect(m.len(q.pos) <= PEC_MAX + 1e-5);
  for (p.rump) |q| try testing.expect(m.len(q.pos) <= RUMP_MAX + 1e-5);
}

test "the tail's root clears the rear lobes" {
  // its first 0.1 runs straight out of the tailbone along the root tilt,
  // at rest and in full stride
  for ([_]f32{ 0, 1 }) |st| {
    const r = m.rotX(TAIL_ROOT_TILT + 0.15 * st);
    const d4 = m.mulV(r, .{ 0, 1, 0, 0 });
    const dir = v3(d4[0], d4[1], d4[2]);
    for (0..11) |i| {
      const p = tailbone.at + dir * m.splat3(0.01 * m.f(i));
      for ([_]f32{ -1, 1 }) |side| {
        const q = (p - rump_mesh.centre * v3(side, 1, 1)) / rump_mesh.radii;
        try testing.expect(m.dot(q, q) > 1);
      }
    }
  }
}