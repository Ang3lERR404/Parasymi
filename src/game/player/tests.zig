//! the wolf tested: belly lag, legs, eyes, feet, arms, gathering and the belly's stages.
const lib = @import("../../lib.zig");
const std = lib.std;
const testing = std.testing;
const engine = lib.engine;
const m = engine.core.math;
const skel = lib.skeleton;
const belly_mesh = lib.wolf_belly;
const V3 = m.V3;
const v3 = m.v3;
const Bone = skel.Bone;
const GATHER_AT = lib.player.tuning.GATHER_AT;
const GAZE_NOD = lib.player.tuning.GAZE_NOD;
const PEC_MAX = lib.player.tuning_look.PEC_MAX;
const Player = lib.player.player.Player;
const REST_HIP = lib.player.tuning.REST_HIP;
const REST_LIFT = lib.player.tuning.REST_LIFT;
const REST_ON = lib.player.tuning.REST_ON;
const RUMP_MAX = lib.player.tuning_look.RUMP_MAX;
const SQUAT_DROP = lib.player.tuning.SQUAT_DROP;
const TRAIL_MAX = lib.player.tuning.TRAIL_MAX;
const WALK_SPEED = lib.player.tuning.WALK_SPEED;
const solveArm = lib.player.ik.solveArm;
const solveLeg = lib.player.ik.solveLeg;

/// tests step at the 60 Hz tick and allow this much float slack
const TEST_DT:f32 = 1.0 / 60.0;
const TEST_EPS:f32 = 1e-4;

test "belly contents lag a sprint, overshoot a stop, then settle" {
  var p:Player = .{ .pos = v3(0, 0, 0) };
  _ = p.inv.add(.grit, 50);
  const dt:f32 = TEST_DT;
  for (0..120) |_| p.animate(null, dt);
  const rest_at = p.lump[0].pos;
  // a burst of speed forward (+z): the lump swings back
  p.vel = v3(0, 0, 4);
  p.animate(null, dt);
  for (0..3) |_| p.animate(null, dt);
  try testing.expect(p.lump[0].pos[2] < rest_at[2] - 0.005);
  // run steadily, then stop dead: it overshoots forward
  for (0..120) |_| p.animate(null, dt);
  p.vel = v3(0, 0, 0);
  for (0..4) |_| p.animate(null, dt);
  try testing.expect(p.lump[0].pos[2] > rest_at[2] + 0.005);
  // and it never leaves the sac
  for (p.lump) |l| try testing.expect(m.len(l.pos) <= p.bellyRoom() + TEST_EPS);
  for (p.pec) |q| try testing.expect(m.len(q.pos) <= PEC_MAX + TEST_EPS);
  for (p.rump) |q| try testing.expect(m.len(q.pos) <= RUMP_MAX + TEST_EPS);
}

test "the leg reaches its resting foot in its resting pose" {
  const w = skel.fk(.{});
  for (skel.sides, 0..) |sd, s| {
    const foot = m.origin(w[@intFromEnum(sd.foot)]);
    const l = solveLeg(foot - v3(skel.sign(s) * skel.HIP_X, skel.HIP_Y, 0), 0, 0, 0);
    try testing.expectApproxEqAbs(skel.REST_THIGH, l.root.x, 1e-3);
    try testing.expectApproxEqAbs(skel.REST_KNEE, l.mid, 1e-3);
    try testing.expectApproxEqAbs(skel.REST_HOCK, l.low.x, 1e-3);
  }
}

test "seen from its own eyes, the head leads toward where they look and nods with them" {
  var p:Player = .{ .pos = v3(0, 0, 0) };
  const level = p.eyes();
  // the eyes are up in the head, ahead of the chest
  try testing.expect(level[1] > p.chest()[1] and level[2] > 0);
  p.aim = 0.4;
  p.gaze = -0.5;
  for (0..240) |_| p.animate(null, TEST_DT);
  try testing.expectApproxEqAbs(@as(f32, 0.4), p.look.x, 0.02);
  try testing.expectApproxEqAbs(0.5 * GAZE_NOD, p.nod.x, 0.02);
  // looking down and to its right (+x), the eyes go with the head
  const e = p.eyes();
  try testing.expect(e[0] > level[0] and e[1] < level[1]);
}

test "a planted foot stays where it is planted while the wolf walks" {
  var p:Player = .{ .pos = v3(0, 0, 0) };
  p.animate(null, TEST_DT);
  p.vel = v3(0, 0, WALK_SPEED);
  for (0..240) |_| {
    p.pos += p.vel * m.splat3(TEST_DT);
    const before = p.feet;
    p.animate(null, TEST_DT);
    for (before, p.feet) |a, b| if (a.planted() and b.planted()) try testing.expect(m.len(a.at - b.at) < 1e-5);
  }
  // and both feet keep up with it
  for (p.feet, 0..) |f, s| try testing.expect(m.len(f.at - p.rest(null, s)) < TRAIL_MAX + 0.1);
}

test "an arm's wrist reaches what it is solved for" {
  const w0 = skel.fk(.{});
  const chest = w0[@intFromEnum(Bone.chest)];
  for ([_]V3{ v3(0.1, -0.35, 0.2), v3(0.02, -0.25, 0.3), v3(0.15, -0.4, 0.05) }) |d| {
    var q:skel.Pose = .{};
    q.arms[1] = solveArm(d);
    const w = skel.fk(q);
    const got = m.mulPoint(m.inverseRigid(chest), m.origin(w[@intFromEnum(skel.sides[1].hand)])) - skel.SHOULDER;
    try testing.expect(m.len(got - d) < 2e-3);
  }
}

test "gathering, the wolf squats, grips the node and each unit sends a paw to the belly" {
  var p:Player = .{ .pos = v3(0, 0, 0) };
  p.work = v3(0, 0, GATHER_AT);
  var t:f32 = 0;
  var stowed = [2]bool{ false, false };
  while (t < 3) : (t += TEST_DT) {
    p.gather = @mod(t, 0.45) / 0.45;
    p.animate(null, TEST_DT);
    for (p.stow, 0..) |s, i| stowed[i] = stowed[i] or s > 0;
  }
  try testing.expect(p.squat.x > 0.95);
  try testing.expect(p.pose().hip[1] < skel.HIP_Y - SQUAT_DROP * 0.9);
  try testing.expect(stowed[0] and stowed[1]);
  // stopping, it stands back up
  p.gather = null;
  p.work = null;
  t = 0;
  while (t < 2) : (t += TEST_DT) p.animate(null, TEST_DT);
  try testing.expect(p.squat.x < 0.02);
}

test "the belly's stages: light, heavy, full, each a little slower and never slow" {
  var p:Player = .{ .pos = v3(0, 0, 0) };
  const at = [_]f32{ 0.1, 0.5, 0.95 };
  const want = [_]f32{ 0, 1, 2 };
  var last:f32 = 2;
  for (at, want) |f, w| {
    p.fullness = f;
    try testing.expectApproxEqAbs(w, p.stage(), 1e-3);
    const g = p.gait();
    try testing.expect(g.walk <= last and g.sprint <= last);
    try testing.expect(g.walk >= 0.8 and g.sprint >= 0.75);
    last = @min(g.walk, g.sprint);
  }
  // blended across a threshold, never jumping
  var prev:f32 = 0;
  var f:f32 = 0;
  while (f <= 1) : (f += 0.005) {
    p.fullness = f;
    try testing.expect(@abs(p.stage() - prev) < 0.12);
    prev = p.stage();
  }
}

test "standing still with a heavy belly, one paw rests on it and the other on the hip" {
  var p:Player = .{ .pos = v3(0, 0, 0) };
  p.fullness = 0.6;
  p.inv = .{};
  var t:f32 = 0;
  while (t < 4) : (t += TEST_DT) {
    p.animate(null, TEST_DT);
    p.fullness = 0.6;
  }
  try testing.expect(p.rest_pose.x > 0.95);
  const w = skel.fk(p.pose());
  const belly = m.mulPoint(w[@intFromEnum(Bone.gut_top)], REST_ON * v3(belly_mesh.RX, belly_mesh.UP, belly_mesh.RZ)) + v3(0, REST_LIFT, 0);
  const hip = m.mulPoint(w[@intFromEnum(Bone.pelvis)], REST_HIP * v3(-1, 1, 1));
  try testing.expect(m.len(m.origin(w[@intFromEnum(skel.sides[1].hand)]) - belly) < 0.03);
  try testing.expect(m.len(m.origin(w[@intFromEnum(skel.sides[0].hand)]) - hip) < 0.03);
  // a light belly never takes the pose
  var q:Player = .{ .pos = v3(0, 0, 0) };
  t = 0;
  while (t < 4) : (t += TEST_DT) q.animate(null, TEST_DT);
  try testing.expect(q.rest_pose.x < 0.01);
}

test "the arms ease into the gathering and belly-rest poses without swinging round" {
  // the hands travel there smoothly: never far in a frame, and the
  // shoulder never turns more than half a turn
  const Case = struct { full:f32, gather:bool };
  for ([_]Case{ .{ .full = 0.6, .gather = false }, .{ .full = 0, .gather = true } }) |c| {
    var p:Player = .{ .pos = v3(0, 0, 0) };
    var last:?[2]V3 = null;
    var t:f32 = 0;
    while (t < 5) : (t += TEST_DT) {
      if (c.gather and t > 0.5) {
        p.work = v3(0, 0, GATHER_AT);
        p.gather = 0;
      }
      p.animate(null, TEST_DT);
      p.fullness = c.full;
      const q = p.pose();
      const w = skel.fk(q);
      var h:[2]V3 = undefined;
      for (0..2) |s| {
        h[s] = m.origin(w[@intFromEnum(skel.sides[s].hand)]);
        try testing.expect(@abs(q.arms[s].root.x) <= m.pi + TEST_EPS);
        if (last) |l| try testing.expect(m.len(h[s] - l[s]) < 0.03);
      }
      last = h;
    }
  }
}
