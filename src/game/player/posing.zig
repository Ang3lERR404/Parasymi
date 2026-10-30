//! the wolf posed: the skeleton from its state, and its parts for the renderer.
const lib = @import("../../lib.zig");
const std = lib.std;
const Allocator = std.mem.Allocator;
const engine = lib.engine;
const m = engine.core.math;
const skel = lib.skeleton;
const body_mesh = lib.wolf_body;
const belly_mesh = lib.wolf_belly;
const meshlib = lib.meshlib;
const parts = lib.parts;
const Parts = parts.Parts;
const V3 = m.V3;
const v3 = m.v3;
const M4 = m.M4;
const T = m.translate;
const S = m.scale3;
const Bone = skel.Bone;
const ARM_OUT = lib.player.tuning.ARM_OUT;
const BEAN_GLOW = lib.player.tuning_look.BEAN_GLOW;
const BEAN_OPACITY = lib.player.tuning_look.BEAN_OPACITY;
const BEAN_TINT = lib.player.tuning_look.BEAN_TINT;
const BELLY_ARMS = lib.player.tuning.BELLY_ARMS;
const BELLY_GLOW = lib.player.tuning_look.BELLY_GLOW;
const BELLY_GLOW_FULL = lib.player.tuning_look.BELLY_GLOW_FULL;
const BOB = lib.player.tuning.BOB;
const BODY_FLUTTER = lib.player.tuning_look.BODY_FLUTTER;
const BODY_GLOW = lib.player.tuning_look.BODY_GLOW;
const BODY_MID = lib.player.tuning_look.BODY_MID;
const BREATH = lib.player.tuning.BREATH;
const BREATH_RUN = lib.player.tuning.BREATH_RUN;
const COUNTER = lib.player.tuning.COUNTER;
const EAR_GLOW = lib.player.tuning_look.EAR_GLOW;
const EAR_OPACITY = lib.player.tuning_look.EAR_OPACITY;
const EYES_AT = lib.player.tuning_look.EYES_AT;
const HEAD_BONES = lib.player.tuning_look.HEAD_BONES;
const HIP_ROLL = lib.player.tuning.HIP_ROLL;
const HIP_TURN = lib.player.tuning.HIP_TURN;
const LUMP_GLOW = lib.player.tuning_look.LUMP_GLOW;
const LUMP_R = lib.player.tuning_look.LUMP_R;
const NOSE_GLOW = lib.player.tuning_look.NOSE_GLOW;
const NOSE_TINT = lib.player.tuning_look.NOSE_TINT;
const PAD_FLATTEN = lib.player.tuning_look.PAD_FLATTEN;
const PANT = lib.player.tuning.PANT;
const PEC_OPACITY = lib.player.tuning_look.PEC_OPACITY;
const PRY_ROCK = lib.player.tuning.PRY_ROCK;
const PRY_TWIST = lib.player.tuning.PRY_TWIST;
const PULL_END = lib.player.tuning.PULL_END;
const Player = lib.player.player.Player;
const REST_DRAPE = lib.player.tuning.REST_DRAPE;
const REST_ELBOW_OUT = lib.player.tuning.REST_ELBOW_OUT;
const REST_HIP = lib.player.tuning.REST_HIP;
const REST_LIFT = lib.player.tuning.REST_LIFT;
const REST_ON = lib.player.tuning.REST_ON;
const REST_PRONATE = lib.player.tuning.REST_PRONATE;
const RUMP_OPACITY = lib.player.tuning_look.RUMP_OPACITY;
const SAP_OPACITY = lib.player.tuning_look.SAP_OPACITY;
const SAP_STRETCH = lib.player.tuning.SAP_STRETCH;
const SINK = lib.player.tuning.SINK;
const SQUAT_DROP = lib.player.tuning.SQUAT_DROP;
const SQUAT_LEAN = lib.player.tuning.SQUAT_LEAN;
const STOW_TIME = lib.player.tuning.STOW_TIME;
const SWAY = lib.player.tuning.SWAY;
const SWING_FOLD = lib.player.tuning.SWING_FOLD;
const TAIL_DROOP = lib.player.tuning_look.TAIL_DROOP;
const TAIL_LIFT = lib.player.tuning_look.TAIL_LIFT;
const TIP_REST = lib.player.tuning_look.TIP_REST;
const TIP_SHARE = lib.player.tuning_look.TIP_SHARE;
const TOE_HANG = lib.player.tuning.TOE_HANG;
const WRENCH_END = lib.player.tuning.WRENCH_END;
const bindInv = lib.player.ik.bindInv;
const lumps = lib.player.tuning_look.lumps;
const pryPull = lib.player.ik.pryPull;
const solveArm = lib.player.ik.solveArm;
const solveArmTurned = lib.player.ik.solveArmTurned;
const solveLeg = lib.player.ik.solveLeg;

/// the skeleton's pose this frame, in wolf space (see wolf_skeleton)
pub fn pose(p:*const Player) skel.Pose {
  if (p.posed) |q| return q;
  const st = p.stride;
  const work = p.reach.x * (1 - p.squat.x);
  const sq = p.squat.x;
  const ph = p.phase * m.tau;
  var q:skel.Pose = .{};
  // the pelvis: lowest just after each footfall, over the planted foot;
  // gathering, down in a squat, the body leaning in and rocking back
  // with each pull
  const g = p.gait();
  const bob = BOB * g.bob * st * (0.5 + 0.5 * @cos(2 * ph - p.duty * m.tau));
  const rock = PRY_ROCK * pryPull(p.gather orelse 0) * sq;
  const lean = p.lean.x - g.lean * (1 - sq) + (SQUAT_LEAN - rock) * sq;
  q.hip = v3(SWAY * g.sway * st * @sin(ph), skel.HIP_Y - SINK * g.sink * st - bob - 0.07 * work - SQUAT_DROP * sq, -0.04 * sq);
  q.pelvis = .{ .x = 0.25 * lean, .y = HIP_TURN * st * @sin(ph), .z = HIP_ROLL * g.roll * st * @cos(ph) + p.bank.x };
  q.waist = .{ .x = 0.35 * lean, .y = -0.5 * COUNTER * q.pelvis.y, .z = -0.4 * q.pelvis.z };
  q.chest = .{ .x = 0.4 * lean, .y = -0.5 * COUNTER * q.pelvis.y, .z = -0.4 * q.pelvis.z };
  const breath = @sin(p.breath);
  q.breath = 1 + m.lerp(BREATH, BREATH_RUN, st) * breath;
  // the head holds its gaze: it takes back the body's lean and bob
  const body_pitch = q.pelvis.x + q.waist.x + q.chest.x;
  q.neck = .{ .x = -0.4 * body_pitch + 0.5 * p.nod.x, .y = 0.4 * p.look.x - 0.3 * q.chest.y };
  q.head = .{ .x = -0.6 * body_pitch + 0.5 * p.nod.x - bob * 1.5 + 0.02 * breath, .y = 0.6 * p.look.x - 0.3 * q.chest.y, .z = -0.5 * p.bank.x };
  q.jaw = PANT * st * (0.6 + 0.4 * breath);
  q.gut = p.fullness;
  for (0..2) |s| {
    const x = skel.sign(s);
    q.arms[s] = .{
      .root = .{ .x = p.arm[s].x, .z = x * (ARM_OUT + BELLY_ARMS * p.fullness + 0.02 * breath + 0.1 * work), .y = -x * 0.15 * work },
      .mid = p.elbow[s].x,
      .low = .{ .x = 0.2 + 0.3 * work },
    };
    q.ears[s] = .{ .x = p.ear[s].x, .z = 0.15 * x * p.ear[s].x };
    for (&q.hands[s].curl, &q.hands[s].tip, p.curl[s]) |*c, *tp, sp| {
      c.* = sp.x;
      tp.* = TIP_REST + TIP_SHARE * sp.x;
    }
    q.hands[s].spread = p.spread[s].x;
  }
  // the tail lifts with the stride and droops at rest, each joint bending
  // a little further
  // (crouching, it lifts to balance the lean)
  for (&q.tail, p.tail, 0..) |*j, sp, i| j.* = .{ .x = (if (i == 0) -TAIL_LIFT * @max(st, sq) else TAIL_DROOP * (1 - 0.6 * st)), .z = sp.x };
  q.legs = p.legs(q);
  if (sq > 0) p.armsToWrists(&q, sq);
  const resting = p.rest_pose.x * (1 - sq);
  if (resting > 0) restArms(&q, resting);
  return q;
}

/// the belly-rest idle, blended in by `r`: the right wrist onto the top
/// of the belly, the palm laid on it; the left on the hip, the wrist
/// bent back and the elbow turned out
pub fn restArms(q:*skel.Pose, r:f32) void {
  const w = skel.fk(q.*);
  const into = m.inverseRigid(w[@intFromEnum(Bone.chest)]);
  const on = REST_ON * v3(belly_mesh.RX, belly_mesh.UP, belly_mesh.RZ);
  const at = [2]V3{
    m.mulPoint(w[@intFromEnum(Bone.pelvis)], REST_HIP * v3(-1, 1, 1)),
    m.mulPoint(w[@intFromEnum(Bone.gut_top)], on) + v3(0, REST_LIFT, 0),
  };
  for (0..2) |s| {
    const x = skel.sign(s);
    const out:f32 = if (s == 0) REST_ELBOW_OUT else 0;
    const ik = solveArmTurned(m.mulPoint(into, at[s]) - skel.SHOULDER * v3(x, 1, 1), -x * out);
    const a = &q.arms[s];
    a.root = skel.Turn.blend(a.root, ik.root, r);
    a.mid = m.lerp(a.mid, ik.mid, r);
    // (on the belly the paw turns palm down and bends onto the sac; on
    // the hip the wrist cocks back)
    const low:skel.Turn = if (s == 0) .{ .x = -0.5, .z = x * 0.3 } else .{ .y = -x * REST_PRONATE, .z = -x * REST_DRAPE };
    a.low = .{ .x = m.lerp(a.low.x, low.x, r), .y = m.lerp(a.low.y, low.y, r), .z = m.lerp(a.low.z, low.z, r) };
  }
}

/// gathering: each arm blended (by `sq`) toward reaching its wrist's
/// target by inverse kinematics, the wrist twisting with the wrench
pub fn armsToWrists(p:*const Player, q:*skel.Pose, sq:f32) void {
  const w = skel.fk(q.*);
  const into = m.inverseRigid(w[@intFromEnum(Bone.chest)]);
  const k = p.gather orelse 0;
  const twist = PRY_TWIST * m.smooth(m.clamp01((k - PULL_END) / (WRENCH_END - PULL_END))) * (1 - m.smooth(m.clamp01((k - WRENCH_END) / (1 - WRENCH_END))));
  for (0..2) |s| {
    const x = skel.sign(s);
    const at = m.mulPoint(into, p.wrist[s].pos) - skel.SHOULDER * v3(x, 1, 1);
    const ik = solveArm(at);
    const a = &q.arms[s];
    a.root = skel.Turn.blend(a.root, ik.root, sq);
    a.mid = m.lerp(a.mid, ik.mid, sq);
    const stowing = m.clamp01(p.stow[s] / STOW_TIME * 3);
    a.low = .{ .x = m.lerp(a.low.x, 0.35 * (1 - stowing) + 0.9 * stowing, sq), .y = m.lerp(a.low.y, -x * twist * (1 - stowing), sq), .z = a.low.z };
  }
}

/// each leg reaching its foot, by inverse kinematics in the pelvis's frame
pub fn legs(p:*const Player, q:skel.Pose) [2]skel.Limb {
  var out:[2]skel.Limb = undefined;
  const to_wolf = m.inverseRigid(p.heading());
  const pelvis = m.chain(&.{ T(q.hip), q.pelvis.m4() });
  const into = m.inverseRigid(pelvis);
  const pelvis_pitch = q.pelvis.x;
  for (&out, 0..) |*l, s| {
    const f = p.feet[s];
    const fw = m.mulV(to_wolf, .{ f.at[0], f.at[1], f.at[2], 1 });
    const fp = m.mulV(into, fw);
    const swing = if (f.planted()) @as(f32, 0) else @sin(f.t * m.pi);
    l.* = solveLeg(v3(fp[0], fp[1], fp[2]) - v3(skel.sign(s) * skel.HIP_X, 0, 0), SWING_FOLD * swing, pelvis_pitch, TOE_HANG * swing);
  }
  return out;
}

/// where its eyes are in the world this frame
pub fn eyes(p:*const Player) V3 {
  const w = skel.fk(p.pose());
  return m.mulPoint(m.mul(p.heading(), w[@intFromEnum(Bone.head)]), EYES_AT);
}

/// emit every part; returns where each paw (left, right) touches down.
/// Seen from its own eyes (`headless`) its head is not drawn, though it
/// still casts its shadow.
pub fn rig(p:*const Player, out:*Parts, headless:bool) Allocator.Error![2]V3 {
  const q = p.pose();
  const root = p.heading();
  var w = skel.fk(q);
  for (&w) |*b| b.* = m.mul(root, b.*);
  const skin = skel.skin(w, &bindInv(), q.breath);
  const base = try out.pose(&skin);
  const mid = p.pos + v3(0, BODY_MID, 0);
  const at = struct {
    fn f(ws:*const [skel.COUNT]M4, b:Bone) M4 { return ws[@intFromEnum(b)]; }
  }.f;

  const hide:u64 = if (headless) HEAD_BONES else 0;
  try out.emitSkinned(.wolf_body, base, mid, .{ .glow = BODY_GLOW, .flutter = BODY_FLUTTER, .phase = 0.1, .hide = hide });
  try out.emitSkinned(.wolf_ears, base, mid, .{ .glow = EAR_GLOW, .phase = 0.5, .fade = EAR_OPACITY, .hide = hide });
  if (!headless) try out.emit(.paw_bean, m.chain(&.{ at(&w, .head), T(body_mesh.NOSE), m.rotX(-body_mesh.NOSE_TILT), S(v3(0.015, 0.0105, 0.011)) }), .{ .glow = NOSE_GLOW, .fade = BEAN_OPACITY, .tint = NOSE_TINT });

  // the belly: a sap sac that inflates with the inventory, drops and sags
  // as it fills, with the heavier things inside showing through as shadows
  const b = p.fullness;
  const gut = at(&w, .gut);
  var held:usize = 0;
  for (p.inv.slot) |slot| if (slot != null) {
    held += 1;
  };
  for (p.lump[0..@min(held, lumps.len)]) |l| {
    try out.emit(.belly_lump, m.chain(&.{ gut, T(l.pos), S(m.splat3(LUMP_R)) }), .{ .glow = LUMP_GLOW, .phase = 0.3 });
  }
  // (the shader creases it as it fills, the folds crossing at its button)
  const cross = belly_mesh.crossing();
  try out.emitSkinned(.wolf_belly, base, mid, .{
    .glow = BELLY_GLOW + BELLY_GLOW_FULL * b, .phase = 0.3, .fade = SAP_OPACITY - SAP_STRETCH * b, .give = .{ b, cross[1], cross[2] },
  });

  // the pectorals and the rear: resin, its surface given by its spring
  // (and, on the chest, a slow idle) while its base holds
  for ([_]meshlib.Id{ .wolf_pec_l, .wolf_pec_r }, [_]f32{ -1, 1 }, 0..) |id, side, i| {
    const give = p.pec[i].pos + v3(0, 0.003 * @sin(p.t * m.tau / 3 + side * 1.3), 0);
    try out.emitSkinned(id, base, mid, .{ .phase = 0.6, .fade = PEC_OPACITY, .give = .{ give[0], give[1], give[2] } });
  }
  for ([_]meshlib.Id{ .wolf_rump_l, .wolf_rump_r }, 0..) |id, i| {
    const give = p.rump[i].pos;
    try out.emitSkinned(id, base, mid, .{ .phase = 0.15, .fade = RUMP_OPACITY, .give = .{ give[0], give[1], give[2] } });
  }

  var feet:[2]V3 = undefined;
  for (skel.sides, 0..) |sd, s| {
    const x = skel.sign(s);
    // the beans: a palm pad and one under each fingertip; one
    // central pad on each foot that flattens while planted, four toe pads
    const bean:parts.Look = .{ .glow = BEAN_GLOW, .fade = BEAN_OPACITY, .tint = BEAN_TINT };
    const hand = at(&w, sd.hand);
    try out.emit(.paw_pad, m.chain(&.{ hand, T(body_mesh.PALM * v3(x, 1, 1)), m.rotZ(x * m.pi / 2.0), S(v3(0.018, 0.005, 0.016)) }), bean);
    for (sd.tips) |tb| {
      try out.emit(.paw_bean, m.chain(&.{ at(&w, tb), T(body_mesh.TIP_PAD * v3(x, 1, 1)), S(v3(0.0042, 0.0085, 0.0075)) }), bean);
    }
    const foot = at(&w, sd.foot);
    try out.emit(.paw_pad, m.chain(&.{ foot, T(body_mesh.PAD_AT), S(v3(0.021, 0.006 * (1 - PAD_FLATTEN * p.feet[s].pad), 0.02)) }), bean);
    for (body_mesh.TOES) |tp| {
      try out.emit(.paw_bean, m.chain(&.{ foot, T(v3(tp[0], body_mesh.SOLE_Y + 0.002, tp[1])), S(v3(0.0065, 0.004, 0.008)) }), bean);
    }
    feet[s] = m.mulPoint(foot, v3(0, 0, 0.04));
  }
  return feet;
}
