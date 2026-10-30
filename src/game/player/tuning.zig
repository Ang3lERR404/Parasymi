//! how the wolf moves: speeds, gaits, stride, lean, arms, breath and head.
const lib = @import("../../lib.zig");
const engine = lib.engine;
const m = engine.core.math;
const v3 = m.v3;

pub const REACH:f32 = 3.5;
pub const STEP_UP:f32 = 0.45;
pub const WALK_SPEED:f32 = 4.0;
pub const SPRINT_SPEED:f32 = 6.5;
pub const ACCEL_RESPONSE:f32 = 12; // how quickly velocity matches the wish
pub const PROBE:f32 = 0.25; // body radius probed ahead of the centre
pub const STRIDE_RESPONSE:f32 = 6; // how quickly stride eases in/out
pub const TURN_RESPONSE:f32 = 10; // how quickly facing matches the target
pub const GROUND_FREQ:f32 = 18; // spring frequency for following terrain height
pub const WORK_DRAG:f32 = 0.85; // velocity kept each frame while the hands work
pub const FACE_MIN_SPEED:f32 = 0.3; // slower than this, the wolf keeps its facing
pub const MIN_DT:f32 = 1e-4; // guards rates divided by the frame time
pub const FULLNESS_RESPONSE:f32 = 2; // how quickly the belly's look follows its fill
/// the belly answers every item carried: it is (1 - 1/e) of the way to
/// full with this many held, and keeps swelling toward full past it
pub const BELLY_ITEMS:f32 = 250;
/// a full belly pushes the arms out round it (radians) and the feet apart
/// (metres each side)
pub const BELLY_ARMS:f32 = 0.42;
pub const BELLY_STANCE:f32 = 0.07;
/// stretched thin, the full sac lets more show through it
pub const SAP_STRETCH:f32 = 0.14;
pub const REACH_FREQ:f32 = 6; // spring frequency into and out of the work gesture
/// gathering: the squat (how far the hips drop, the body leans in, the feet
/// step out), where the paws grip the node (above its ground, either side
/// of it), and the pry once a unit: pulled back and up over the first
/// `PULL_END` of it, wrenched (twisting at the wrists) until `WRENCH_END`,
/// back to the grip after; the body rocks back with the pull. A paw
/// pressing a loose unit into the belly takes `STOW_TIME`.
pub const SQUAT_DROP:f32 = 0.24;
pub const SQUAT_LEAN:f32 = 0.95;
pub const SQUAT_STANCE:f32 = 0.06;
pub const SQUAT_FREQ:f32 = 5;
pub const GRIP_UP:f32 = 0.11;
pub const GRIP_SIDE:f32 = 0.085;
pub const PRY_BACK:f32 = 0.07;
pub const PRY_UP:f32 = 0.04;
pub const PRY_ROCK:f32 = 0.16;
pub const PRY_TWIST:f32 = 0.55;
pub const PULL_END:f32 = 0.55;
pub const WRENCH_END:f32 = 0.72;
pub const STOW_TIME:f32 = 0.3;
pub const HAND_FREQ:f32 = 14;
pub const HAND_DAMP:f32 = 0.75;
/// the gripping paws are closed this far; a stowing paw cups
pub const PRY_GRIP:f32 = 1.2;
pub const STOW_CUP:f32 = 0.6;
/// the wolf steps up to a node it gathers from, until it is this far ahead
/// of its feet (and the paws can reach it)
pub const GATHER_AT:f32 = 0.45;
/// what the wolf works on or carries sits this high above its feet
pub const CHEST_HEIGHT:f32 = 1.0;

/// how the belly's load tells on the gait, in three stages: light (up to a
/// third full), heavy, full (past two thirds), each blending into the next
/// over `STAGE_BLEND` of fullness about its threshold. Per stage: top walk
/// and sprint speed (a share of the light ones: a little slower, never
/// slow), stride length (a share of the cycle), how high a foot lifts, the
/// pelvis's sway over the planted foot and roll with the stride (the full
/// waddle), how low it sinks and bobs, and how far the body leans back to
/// carry the weight before it.
pub const Gait = struct { walk:f32, sprint:f32, stride:f32, lift:f32, sway:f32, roll:f32, sink:f32, bob:f32, lean:f32 };
pub const GAITS = [3]Gait{
  .{ .walk = 1, .sprint = 1, .stride = 1, .lift = 1, .sway = 1, .roll = 1, .sink = 1, .bob = 1.15, .lean = 0 },
  .{ .walk = 0.93, .sprint = 0.9, .stride = 0.88, .lift = 0.8, .sway = 2.2, .roll = 1.8, .sink = 1.4, .bob = 1.3, .lean = 0.05 },
  .{ .walk = 0.86, .sprint = 0.8, .stride = 0.76, .lift = 0.6, .sway = 3.6, .roll = 3.2, .sink = 1.8, .bob = 1.5, .lean = 0.11 },
};
pub const STAGE_AT = [2]f32{ 1.0 / 3.0, 2.0 / 3.0 };
pub const STAGE_BLEND:f32 = 0.08;
/// the belly-rest idle: standing still this long with the belly at least
/// `REST_FULL` full (fully in by `REST_FULL_IN`), the right paw rests on top
/// of the belly (at `REST_ON`, the sac's upper half's frame, in its own
/// shares: its radii and height) and the left leans on the hip (at
/// `REST_HIP`, the pelvis's frame, x outward), its knuckles curled, the
/// elbow out; the two ease in on a slow spring
pub const REST_AFTER:f32 = 1.2;
pub const REST_FULL:f32 = 1.0 / 3.0;
pub const REST_FULL_IN:f32 = 0.45;
pub const REST_FREQ:f32 = 2.2;
pub const REST_ON = v3(0.1, 0.92, 0.45);
/// the wrist sits this far off the sac, the paw lying on it
pub const REST_LIFT:f32 = 0.045;
pub const REST_HIP = v3(0.22, 0.08, -0.01);
pub const REST_ELBOW_OUT:f32 = 1.0;
pub const REST_FLAT:f32 = 0.12;
pub const REST_FIST:f32 = 1.1;
/// the paw on the belly turns palm down and bends onto it this far
pub const REST_PRONATE:f32 = 1.4;
pub const REST_DRAPE:f32 = 0.7;
/// the gait: a full cycle (both feet) covers `CYCLE + CYCLE_PER_SPEED *
/// speed` metres; a foot is planted for `duty` of it, more of it walking
/// slowly than running
pub const CYCLE:f32 = 1.2;
pub const CYCLE_PER_SPEED:f32 = 0.2;
pub const DUTY_SLOW:f32 = 0.6;
pub const DUTY_FAST:f32 = 0.38;
/// below this stride the wolf stands: feet only step to stay under it
pub const STANDING:f32 = 0.15;
/// a standing foot further than this from where it rests steps back under
pub const SETTLE:f32 = 0.06;
pub const SETTLE_TIME:f32 = 0.26;
/// a striding foot's swing lasts its share of the cycle, as if walking at
/// least `SWING_SPEED_MIN`, held within these seconds
pub const SWING_SPEED_MIN:f32 = 0.5;
pub const SWING_MIN:f32 = 0.12;
pub const SWING_MAX:f32 = 0.4;
/// a planted foot never trails the hip by more than this before it lifts
pub const TRAIL_MAX:f32 = 0.5;
/// a foot this far from the body (a load, a teleport) is put straight back
pub const LOST:f32 = 1.2;
/// how high a swinging foot lifts (standing, and more at full stride), and
/// how far its toes hang as it swings
pub const LIFT:f32 = 0.05;
pub const LIFT_STRIDE:f32 = 0.08;
pub const TOE_HANG:f32 = 0.55;
/// the lift's arc over the swing (sin^this: under 1 rises fast, hangs high)
pub const LIFT_ARC:f32 = 0.8;
/// the metatarsal folds this much more under the leg mid-swing
pub const SWING_FOLD:f32 = 0.45;
/// the pelvis: how far it sinks with stride and bobs at each footfall,
/// sways over the planted foot, turns and rolls with the stride
pub const SINK:f32 = 0.045;
pub const BOB:f32 = 0.028;
pub const SWAY:f32 = 0.018;
pub const HIP_TURN:f32 = 0.13;
pub const HIP_ROLL:f32 = 0.05;
/// the chest turns against the hips by this share
pub const COUNTER:f32 = 1.4;
/// lean: forward with stride, more into acceleration (radians per m/s^2),
/// into turns (radians per rad/s), and down into the work
pub const LEAN_STRIDE:f32 = 0.14;
pub const LEAN_ACCEL:f32 = 0.018;
pub const LEAN_MAX:f32 = 0.3;
pub const BANK:f32 = 0.05;
pub const BANK_MAX:f32 = 0.2;
pub const LEAN_WORK:f32 = 0.38;
pub const LEAN_FREQ:f32 = 5;
pub const LEAN_DAMP:f32 = 0.7;
pub const BANK_DAMP:f32 = 0.8;
/// arms: swing against the legs, hang out a little, bend at the elbow
/// (more as they come forward); their springs make them lag and carry
pub const ARM_SWING:f32 = 0.62;
pub const ARM_OUT:f32 = 0.13;
pub const ELBOW_REST:f32 = 0.3;
pub const ELBOW_SWING:f32 = 0.55;
pub const ARM_FREQ:f32 = 9;
pub const ARM_DAMP:f32 = 0.55;
/// the work gesture: reach forward and dig
pub const DIG:f32 = -1.1;
pub const DIG_RATE:f32 = 9;
pub const DIG_DEPTH:f32 = 0.22;
/// breathing: a tempo that quickens with effort, the chest swelling and
/// panting with the jaw a little open at a run
pub const BREATH_RATE:f32 = 1.7;
pub const BREATH_RATE_RUN:f32 = 4.2;
pub const BREATH:f32 = 0.02;
pub const BREATH_RUN:f32 = 0.03;
pub const PANT:f32 = 0.09;
/// the head: steadied against the bob and lean, turning into turns,
/// looking about when idle, down into the work
pub const HEAD_FREQ:f32 = 7;
pub const HEAD_DAMP:f32 = 0.8;
pub const LOOK_TURN:f32 = 0.18;
pub const LOOK_MAX:f32 = 0.6;
pub const LOOK_IDLE:f32 = 0.28;
pub const LOOK_IDLE_RATE:f32 = 0.23;
pub const LOOK_WORK:f32 = 0.45;
/// seen from its own eyes: the head nods this share of how far they look
/// up or down, within these limits (down +)
pub const GAZE_NOD:f32 = 0.6;
pub const GAZE_NOD_UP:f32 = -0.5;
pub const GAZE_NOD_DOWN:f32 = 0.7;
