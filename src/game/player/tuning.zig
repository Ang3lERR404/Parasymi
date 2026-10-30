//! how the wolf moves: speeds, gaits, stride, lean, arms, breath and head.
const lib=@import("../../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const v3=m.v3;
pub const reachDistance:f32=3.5;
pub const stepUp:f32=0.45;
pub const walkSpeed:f32=4.0;
pub const sprintSpeed:f32=6.5;
pub const accelResponse:f32=12; // how quickly velocity matches the wish
pub const probeRadius:f32=0.25; // body radius probed ahead of the centre
pub const strideResponse:f32=6; // how quickly stride eases in/out
pub const turnResponse:f32=10; // how quickly facing matches the target
pub const groundFreq:f32=18; // spring frequency for following terrain height
pub const workDrag:f32=0.85; // velocity kept each frame while the hands work
pub const faceMinSpeed:f32=0.3; // slower than this, the wolf keeps its facing
pub const minDt:f32=1e-4; // guards rates divided by the frame time
pub const fullnessResponse:f32=2; // how quickly the belly's look follows its fill
/// the belly answers every item carried: it is (1 - 1/e) of the way to
/// full with this many held, and keeps swelling toward full past it
pub const bellyItems:f32=250;
/// a full belly pushes the arms out round it (radians) and the feet apart
/// (metres each side)
pub const bellyArms:f32=0.42;
pub const bellyStance:f32=0.07;
/// stretched thin, the full sac lets more show through it
pub const sapStretch:f32=0.14;
pub const reachFreq:f32=6; // spring frequency into and out of the work gesture
/// gathering: the squat (how far the hips drop, the body leans in, the feet
/// step out), where the paws grip the node (above its ground, either side
/// of it), and the pry once a unit: pulled back and up over the first
/// `PULL_END` of it, wrenched (twisting at the wrists) until `WRENCH_END`,
/// back to the grip after; the body rocks back with the pull. A paw
/// pressing a loose unit into the belly takes `STOW_TIME`.
pub const squatDrop:f32=0.24;
pub const squatLean:f32=0.95;
pub const squatStance:f32=0.06;
pub const squatFreq:f32=5;
pub const gripUp:f32=0.11;
pub const gripSide:f32=0.085;
pub const pryBack:f32=0.07;
pub const pryUp:f32=0.04;
pub const pryRock:f32=0.16;
pub const pryTwist:f32=0.55;
pub const pullEnd:f32=0.55;
pub const wrenchEnd:f32=0.72;
pub const stowTime:f32=0.3;
pub const handFreq:f32=14;
pub const handDamp:f32=0.75;
/// the gripping paws are closed this far; a stowing paw cups
pub const pryGrip:f32=1.2;
pub const stowCup:f32=0.6;
/// the wolf steps up to a node it gathers from, until it is this far ahead
/// of its feet (and the paws can reach it)
pub const gatherAt:f32=0.45;
/// what the wolf works on or carries sits this high above its feet
pub const chestHeight:f32=1.0;
/// how the belly's load tells on the gait, in three stages: light (up to a
/// third full), heavy, full (past two thirds), each blending into the next
/// over `STAGE_BLEND` of fullness about its threshold. Per stage: top walk
/// and sprint speed (a share of the light ones: a little slower, never
/// slow), stride length (a share of the cycle), how high a foot lifts, the
/// pelvis's sway over the planted foot and roll with the stride (the full
/// waddle), how low it sinks and bobs, and how far the body leans back to
/// carry the weight before it.
pub const Gait=struct{walk:f32,sprint:f32,stride:f32,lift:f32,sway:f32,roll:f32,sink:f32,bob:f32,lean:f32};
pub const gaits=[3]Gait{
  .{.walk=1,.sprint=1,.stride=1,.lift=1,.sway=1,.roll=1,.sink=1,.bob=1.15,.lean=0},
  .{.walk=0.93,.sprint=0.9,.stride=0.88,.lift=0.8,.sway=2.2,.roll=1.8,.sink=1.4,.bob=1.3,.lean=0.05},
  .{.walk=0.86,.sprint=0.8,.stride=0.76,.lift=0.6,.sway=3.6,.roll=3.2,.sink=1.8,.bob=1.5,.lean=0.11},
};
pub const stageAt=[2]f32{1.0/3.0,2.0/3.0};
pub const stageBlend:f32=0.08;
/// the belly-rest idle: standing still this long with the belly at least
/// `REST_FULL` full (fully in by `REST_FULL_IN`), the right paw rests on top
/// of the belly (at `REST_ON`, the sac's upper half's frame, in its own
/// shares: its radii and height) and the left leans on the hip (at
/// `REST_HIP`, the pelvis's frame, x outward), its knuckles curled, the
/// elbow out; the two ease in on a slow spring
pub const restAfter:f32=1.2;
pub const restFull:f32=1.0/3.0;
pub const restFullIn:f32=0.45;
pub const restFreq:f32=2.2;
pub const restOn=v3(0.1,0.92,0.45);
/// the wrist sits this far off the sac, the paw lying on it
pub const restLift:f32=0.045;
pub const restHip=v3(0.22,0.08,-0.01);
pub const restElbowOut:f32=1.0;
pub const restFlat:f32=0.12;
pub const restFist:f32=1.1;
/// the paw on the belly turns palm down and bends onto it this far
pub const restPronate:f32=1.4;
pub const restDrape:f32=0.7;
/// the gait: a full cycle (both feet) covers `CYCLE + CYCLE_PER_SPEED *
/// speed` metres; a foot is planted for `duty` of it, more of it walking
/// slowly than running
pub const cycle:f32=1.2;
pub const cyclePerSpeed:f32=0.2;
pub const dutySlow:f32=0.6;
pub const dutyFast:f32=0.38;
/// below this stride the wolf stands: feet only step to stay under it
pub const standing:f32=0.15;
/// a standing foot further than this from where it rests steps back under
pub const settle:f32=0.06;
pub const settleTime:f32=0.26;
/// a striding foot's swing lasts its share of the cycle, as if walking at
/// least `SWING_SPEED_MIN`, held within these seconds
pub const swingSpeedMin:f32=0.5;
pub const swingMin:f32=0.12;
pub const swingMax:f32=0.4;
/// a planted foot never trails the hip by more than this before it lifts
pub const trailMax:f32=0.5;
/// a foot this far from the body (a load, a teleport) is put straight back
pub const lost:f32=1.2;
/// how high a swinging foot lifts (standing, and more at full stride), and
/// how far its toes hang as it swings
pub const liftAmount:f32=0.05;
pub const liftStride:f32=0.08;
pub const toeHang:f32=0.55;
/// the lift's arc over the swing (sin^this: under 1 rises fast, hangs high)
pub const liftArc:f32=0.8;
/// the metatarsal folds this much more under the leg mid-swing
pub const swingFold:f32=0.45;
/// the pelvis: how far it sinks with stride and bobs at each footfall,
/// sways over the planted foot, turns and rolls with the stride
pub const sinkAmount:f32=0.045;
pub const bobAmount:f32=0.028;
pub const swayAmount:f32=0.018;
pub const hipTurn:f32=0.13;
pub const hipRoll:f32=0.05;
/// the chest turns against the hips by this share
pub const counter:f32=1.4;
/// lean: forward with stride, more into acceleration (radians per m/s^2),
/// into turns (radians per rad/s), and down into the work
pub const leanStride:f32=0.14;
pub const leanAccel:f32=0.018;
pub const leanMax:f32=0.3;
pub const bank:f32=0.05;
pub const bankMax:f32=0.2;
pub const leanWork:f32=0.38;
pub const leanFreq:f32=5;
pub const leanDamp:f32=0.7;
pub const bankDamp:f32=0.8;
/// arms: swing against the legs, hang out a little, bend at the elbow
/// (more as they come forward); their springs make them lag and carry
pub const armSwing:f32=0.62;
pub const armOut:f32=0.13;
pub const elbowRest:f32=0.3;
pub const elbowSwing:f32=0.55;
pub const armFreq:f32=9;
pub const armDamp:f32=0.55;
/// the work gesture: reach forward and dig
pub const digAmount:f32=-1.1;
pub const digRate:f32=9;
pub const digDepth:f32=0.22;
/// breathing: a tempo that quickens with effort, the chest swelling and
/// panting with the jaw a little open at a run
pub const breathRate:f32=1.7;
pub const breathRateRun:f32=4.2;
pub const breathAmount:f32=0.02;
pub const breathRun:f32=0.03;
pub const pant:f32=0.09;
/// the head: steadied against the bob and lean, turning into turns,
/// looking about when idle, down into the work
pub const headFreq:f32=7;
pub const headDamp:f32=0.8;
pub const lookTurn:f32=0.18;
pub const lookMax:f32=0.6;
pub const lookIdle:f32=0.28;
pub const lookIdleRate:f32=0.23;
pub const lookWork:f32=0.45;
/// seen from its own eyes: the head nods this share of how far they look
/// up or down, within these limits (down +)
pub const gazeNod:f32=0.6;
pub const gazeNodUp:f32=-0.5;
pub const gazeNodDown:f32=0.7;
