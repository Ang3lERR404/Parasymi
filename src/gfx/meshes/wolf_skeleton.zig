//! the vine-wolf's skeleton: its bones, how they hang together and the pose
//! they take. The wolf is one skinned surface (`wolf_body`) built around
//! this skeleton in its bind pose (`bind`); the rig (game/player.zig) poses
//! it every frame and the GPU carries each vertex with its bones. Wolf
//! space: the ground under the hips at the origin, +Y up, +Z forward.
//!
//! Every limb bone runs down its local -Y from the joint it turns at to the
//! next; the spine, neck and tail run up +Y.
const std = @import("std");
const testing = std.testing;
const m = @import("../../core/math.zig");

const V3 = m.V3;
const v3 = m.v3;
const M4 = m.M4;
const T = m.translate;

pub const Bone = enum(u8) {
  pelvis, waist, chest, neck, head, jaw, gut,
  tail0, tail1, tail2, tail3,
  arm_l, forearm_l, hand_l, thigh_l, shin_l, meta_l, foot_l, ear_l,
  arm_r, forearm_r, hand_r, thigh_r, shin_r, meta_r, foot_r, ear_r,
  // each hand's four fingers: the knuckle's segment, then the tip's
  finger0_l, finger1_l, finger2_l, finger3_l, tip0_l, tip1_l, tip2_l, tip3_l,
  finger0_r, finger1_r, finger2_r, finger3_r, tip0_r, tip1_r, tip2_r, tip3_r,
  // the gut's upper half (see `GUT_GROW_TOP`)
  gut_top,
};
pub const COUNT = @typeInfo(Bone).@"enum".fields.len;
pub const TAIL = 4;
pub const FINGERS = 4;

/// a side's bones: left (-X) and right (+X)
pub const Side = struct { arm:Bone, forearm:Bone, hand:Bone, thigh:Bone, shin:Bone, meta:Bone, foot:Bone, ear:Bone, fingers:[FINGERS]Bone, tips:[FINGERS]Bone };
pub const sides = [2]Side{
  .{ .arm = .arm_l, .forearm = .forearm_l, .hand = .hand_l, .thigh = .thigh_l, .shin = .shin_l, .meta = .meta_l, .foot = .foot_l, .ear = .ear_l,
     .fingers = .{ .finger0_l, .finger1_l, .finger2_l, .finger3_l }, .tips = .{ .tip0_l, .tip1_l, .tip2_l, .tip3_l } },
  .{ .arm = .arm_r, .forearm = .forearm_r, .hand = .hand_r, .thigh = .thigh_r, .shin = .shin_r, .meta = .meta_r, .foot = .foot_r, .ear = .ear_r,
     .fingers = .{ .finger0_r, .finger1_r, .finger2_r, .finger3_r }, .tips = .{ .tip0_r, .tip1_r, .tip2_r, .tip3_r } },
};
/// -1 left, 1 right
pub fn sign(s:usize) f32 { return if (s == 0) -1 else 1; }

pub fn parent(b:Bone) ?Bone {
  return switch (b) {
    .pelvis => null,
    .waist, .tail0, .thigh_l, .thigh_r => .pelvis,
    .chest, .gut, .gut_top => .waist,
    .neck, .arm_l, .arm_r => .chest,
    .head => .neck,
    .jaw, .ear_l, .ear_r => .head,
    .tail1 => .tail0,
    .tail2 => .tail1,
    .tail3 => .tail2,
    .forearm_l => .arm_l,
    .forearm_r => .arm_r,
    .hand_l => .forearm_l,
    .hand_r => .forearm_r,
    .shin_l => .thigh_l,
    .shin_r => .thigh_r,
    .meta_l => .shin_l,
    .meta_r => .shin_r,
    .foot_l => .meta_l,
    .foot_r => .meta_r,
    .finger0_l, .finger1_l, .finger2_l, .finger3_l => .hand_l,
    .finger0_r, .finger1_r, .finger2_r, .finger3_r => .hand_r,
    .tip0_l => .finger0_l,
    .tip1_l => .finger1_l,
    .tip2_l => .finger2_l,
    .tip3_l => .finger3_l,
    .tip0_r => .finger0_r,
    .tip1_r => .finger1_r,
    .tip2_r => .finger2_r,
    .tip3_r => .finger3_r,
  };
}

/// lengths and joint places (metres)
pub const HIP_Y:f32 = 0.7;
pub const WAIST_AT = v3(0, 0.1, 0);
pub const CHEST_AT = v3(0, 0.16, 0);
pub const NECK_AT = v3(0, 0.21, 0.02);
pub const HEAD_AT = v3(0, 0.09, 0.025);
pub const JAW_AT = v3(0, -0.012, 0.012);
/// the belly's gut, in the waist's frame, and the sac's radii about it
/// (across, down, forward). As it fills it rounds out toward a ball
/// `GUT_FULL` across (far past anything a body would hold), its back held
/// to the body so it swells forward, and drops (per unit of fill)
pub const GUT_AT = v3(0, -0.035, 0.058);
pub const GUT_R = v3(0.11, 0.095, 0.086);
pub const GUT_FULL:f32 = 0.3;
pub const GUT_DROP:f32 = 0.11;
pub const GUT_GROW = m.splat3(GUT_FULL) / GUT_R - m.splat3(1);
pub const GUT_SHIFT = v3(0, -GUT_DROP, GUT_FULL - GUT_R[2]);
/// how far the sac reaches up from the gut's centre toward the ribs
pub const GUT_UP:f32 = 0.21;
/// the sac's upper half swells on its own bone (`gut_top`): as wide as the
/// gut, but its height grows only by the drop, so its top stays where it
/// hangs from the ribs while the half below rounds out, and nothing above
/// is lifted past where the waist holds it (so blending the two never
/// folds the sac over)
pub const GUT_GROW_TOP = v3(GUT_GROW[0], GUT_DROP / GUT_UP, GUT_GROW[2]);
pub const SHOULDER = v3(0.185, 0.17, -0.01);
pub const UPPER_ARM:f32 = 0.25;
pub const FOREARM:f32 = 0.24;
/// the fingers: knuckles this far down the hand, spread across it (z);
/// each fans out from the middle by `SPLAY` at its edge; the segments'
/// lengths (the middle two longer)
pub const KNUCKLE_Y:f32 = 0.08;
pub const KNUCKLES = [FINGERS]f32{ -0.0465, -0.0155, 0.0155, 0.0465 };
pub const SPLAY:f32 = 0.16;
pub const PROXIMAL = [FINGERS]f32{ 0.03, 0.036, 0.036, 0.03 };
pub const DISTAL = [FINGERS]f32{ 0.026, 0.03, 0.03, 0.026 };
pub const HIP_X:f32 = 0.105;
pub const THIGH:f32 = 0.22;
pub const SHIN:f32 = 0.26;
pub const META:f32 = 0.335;
pub const TAIL_AT = v3(0, 0.12, -0.13);
pub const TAIL_SEG:f32 = 0.12;
/// the tail leaves the rear up and back, this far (radians) from straight up
pub const TAIL_TILT:f32 = -(m.pi / 2.0 - m.pi / 6.0);
/// where an ear roots on the skull (x for the right one)
pub const EAR_AT = v3(0.05, 0.092, -0.012);
/// ears lean forward and out by this much at rest
pub const EAR_TILT:f32 = m.rad(12);

/// a joint's turn: about X (pitch: + tips a limb's -Y backward, a spine's +Y
/// forward), then Y (twist), then Z (roll), applied as Y * X * Z
pub const Turn = struct {
  x:f32 = 0,
  y:f32 = 0,
  z:f32 = 0,
  pub fn m4(t:Turn) M4 { return m.chain(&.{ m.rotY(t.y), m.rotX(t.x), m.rotZ(t.z) }); }
};

pub const Limb = struct {
  /// the arm's shoulder or the leg's hip
  root:Turn = .{},
  /// elbow (+ bends the forearm forward) or knee (+ folds the shin back)
  mid:f32 = 0,
  /// wrist, or the hock (- swings the metatarsal forward)
  low:Turn = .{},
  /// the foot's turn at the ball (legs only)
  foot:f32 = 0,
};

/// a hand's fingers: how far each curls in toward the palm at its knuckle
/// and at its tip joint (radians), and how far they fan apart beyond
/// their rest (0 rest, 1 twice as wide, -1 together)
pub const Hand = struct {
  curl:[FINGERS]f32 = @splat(0),
  tip:[FINGERS]f32 = @splat(0),
  spread:f32 = 0,
};

/// everything the rig decides about the body's shape this frame
pub const Pose = struct {
  /// the pelvis's place in wolf space and its turn
  hip:V3 = v3(0, HIP_Y, 0),
  pelvis:Turn = .{},
  waist:Turn = .{},
  chest:Turn = .{},
  neck:Turn = .{},
  head:Turn = .{},
  jaw:f32 = 0,
  /// how full the belly is (0..1)
  gut:f32 = 0,
  arms:[2]Limb = .{ restArm(0), restArm(1) },
  legs:[2]Limb = .{ restLeg(0), restLeg(1) },
  hands:[2]Hand = @splat(.{}),
  tail:[TAIL]Turn = @splat(.{}),
  ears:[2]Turn = @splat(.{}),
  /// the chest's breath (x and z swell)
  breath:f32 = 1,
};

/// the arms of the bind pose hang out from the body, clear of it
pub const BIND_ARM_OUT:f32 = 0.42;
fn restArm(s:usize) Limb { return .{ .root = .{ .z = sign(s) * BIND_ARM_OUT }, .mid = 0.25, .low = .{} }; }
/// a digitigrade leg at rest: the thigh a little forward, the shin folded
/// back to a high hock, the metatarsal forward to the ball, the foot level
pub const REST_THIGH:f32 = -0.25;
pub const REST_KNEE:f32 = 0.87;
pub const REST_HOCK:f32 = -1.23;
/// the legs stand a little apart
pub const LEG_OUT:f32 = 0.05;
fn restLeg(s:usize) Limb { return .{ .root = .{ .x = REST_THIGH, .z = sign(s) * LEG_OUT }, .mid = REST_KNEE, .low = .{ .x = REST_HOCK }, .foot = -(REST_THIGH + REST_KNEE + REST_HOCK) }; }

/// each bone's frame in wolf space for `p` (its joint at the origin)
pub fn fk(p:Pose) [COUNT]M4 {
  var w:[COUNT]M4 = undefined;
  const set = struct {
    fn f(out:*[COUNT]M4, b:Bone, mat:M4) void { out[@intFromEnum(b)] = mat; }
  }.f;
  const at = struct {
    fn f(out:*const [COUNT]M4, b:Bone) M4 { return out[@intFromEnum(b)]; }
  }.f;
  set(&w, .pelvis, m.chain(&.{ T(p.hip), p.pelvis.m4() }));
  set(&w, .waist, m.chain(&.{ at(&w, .pelvis), T(WAIST_AT), p.waist.m4() }));
  set(&w, .chest, m.chain(&.{ at(&w, .waist), T(CHEST_AT), p.chest.m4() }));
  set(&w, .neck, m.chain(&.{ at(&w, .chest), T(NECK_AT), p.neck.m4() }));
  set(&w, .head, m.chain(&.{ at(&w, .neck), T(HEAD_AT), p.head.m4() }));
  set(&w, .jaw, m.chain(&.{ at(&w, .head), T(JAW_AT), m.rotX(p.jaw) }));
  set(&w, .gut, m.chain(&.{ at(&w, .waist), T(GUT_AT + GUT_SHIFT * m.splat3(p.gut)), m.scale3(m.splat3(1) + GUT_GROW * m.splat3(p.gut)) }));
  set(&w, .gut_top, m.chain(&.{ at(&w, .waist), T(GUT_AT + GUT_SHIFT * m.splat3(p.gut)), m.scale3(m.splat3(1) + GUT_GROW_TOP * m.splat3(p.gut)) }));
  var tail = m.chain(&.{ at(&w, .pelvis), T(TAIL_AT), m.rotX(TAIL_TILT) });
  inline for (.{ Bone.tail0, Bone.tail1, Bone.tail2, Bone.tail3 }, 0..) |b, i| {
    if (i > 0) tail = m.chain(&.{ tail, T(v3(0, TAIL_SEG, 0)) });
    tail = m.chain(&.{ tail, p.tail[i].m4() });
    set(&w, b, tail);
  }
  for (sides, 0..) |sd, s| {
    const x = sign(s);
    const arm = p.arms[s];
    set(&w, sd.arm, m.chain(&.{ at(&w, .chest), T(SHOULDER * v3(x, 1, 1)), arm.root.m4() }));
    set(&w, sd.forearm, m.chain(&.{ at(&w, sd.arm), T(v3(0, -UPPER_ARM, 0)), m.rotX(-arm.mid) }));
    set(&w, sd.hand, m.chain(&.{ at(&w, sd.forearm), T(v3(0, -FOREARM, 0)), arm.low.m4() }));
    // fingers hang down the hand, fanned across it, and curl in toward the
    // palm, which faces the body (-x on the right hand)
    const hd = p.hands[s];
    for (sd.fingers, sd.tips, 0..) |fb, tb, i| {
      const fan = -SPLAY * (KNUCKLES[i] / KNUCKLES[FINGERS - 1]) * (1 + hd.spread);
      set(&w, fb, m.chain(&.{ at(&w, sd.hand), T(v3(0, -KNUCKLE_Y, KNUCKLES[i])), m.rotX(fan), m.rotZ(-x * hd.curl[i]) }));
      set(&w, tb, m.chain(&.{ at(&w, fb), T(v3(0, -PROXIMAL[i], 0)), m.rotZ(-x * hd.tip[i]) }));
    }
    const leg = p.legs[s];
    set(&w, sd.thigh, m.chain(&.{ at(&w, .pelvis), T(v3(x * HIP_X, 0, 0)), leg.root.m4() }));
    set(&w, sd.shin, m.chain(&.{ at(&w, sd.thigh), T(v3(0, -THIGH, 0)), m.rotX(leg.mid) }));
    set(&w, sd.meta, m.chain(&.{ at(&w, sd.shin), T(v3(0, -SHIN, 0)), leg.low.m4() }));
    set(&w, sd.foot, m.chain(&.{ at(&w, sd.meta), T(v3(0, -META, 0)), m.rotX(leg.foot) }));
    set(&w, sd.ear, m.chain(&.{ at(&w, .head), T(EAR_AT * v3(x, 1, 1)), m.rotZ(-x * EAR_TILT), m.rotX(EAR_TILT), p.ears[s].m4() }));
  }
  return w;
}

/// the pose the wolf's meshes are built in
pub fn bind() [COUNT]M4 { return fk(.{}); }

/// the matrices the GPU skins with: each carries a vertex from the bind
/// pose to `world` (`bind_inv` from `inverses(bind())`); the chest's
/// breath swells it about its own axis
pub fn skin(world:[COUNT]M4, bind_inv:*const [COUNT]M4, breath:f32) [COUNT]M4 {
  var out:[COUNT]M4 = undefined;
  for (&out, world, bind_inv, 0..) |*o, wm, inv, i| {
    const swell = if (i == @intFromEnum(Bone.chest)) m.scale3(v3(breath, 1, breath)) else m.identity;
    o.* = m.chain(&.{ wm, swell, inv });
  }
  return out;
}

pub fn inverses(mats:[COUNT]M4) [COUNT]M4 {
  var out:[COUNT]M4 = undefined;
  for (&out, mats) |*o, mat| o.* = m.inverseRigid(mat);
  return out;
}

test "the bind pose stands on the ground, the arms clear of the body" {
  const w = bind();
  for (sides) |sd| {
    const foot = m.origin(w[@intFromEnum(sd.foot)]);
    try testing.expectApproxEqAbs(@as(f32, 0), foot[1], 0.02);
    const hand = m.origin(w[@intFromEnum(sd.hand)]);
    try testing.expect(@abs(hand[0]) > 0.3);
  }
  // the skin of the bind pose is the identity
  const s = skin(w, &inverses(w), 1);
  for (s) |mat| inline for (0..4) |c| inline for (0..4) |r| {
    try testing.expectApproxEqAbs(m.identity[c][r], mat[c][r], 1e-5);
  };
}
