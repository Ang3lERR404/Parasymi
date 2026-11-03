//! how the wolf moves: speeds, gaits, stride, lean, arms, breath and head.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, easing, lerps
const m=engine.core.math;
/// builds a 3D vector from its three parts
const v3=m.v3;
/// how far the wolf can reach to work or gather (m)
pub const reachDistance:f32=3.5;
/// the highest terrace step it climbs in one go (m); higher is a wall
pub const stepUp:f32=0.45;
/// its top walking speed (m/s)
pub const walkSpeed:f32=4.0;
/// its top sprinting speed (m/s)
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
/// (this one: how far the arms are pushed out, radians)
pub const bellyArms:f32=0.42;
/// how far a full belly sets each foot out to the side (m)
pub const bellyStance:f32=0.07;
/// stretched thin, the full sac lets more show through it
pub const sapStretch:f32=0.14;
pub const reachFreq:f32=6; // spring frequency into and out of the work gesture
/// gathering: the squat (how far the hips drop, the body leans in, the feet
/// step out), where the paws grip the node (above its ground, either side
/// of it), and the pry once a unit: pulled back and up over the first
/// `pullEnd` of it, wrenched (twisting at the wrists) until `wrenchEnd`,
/// back to the grip after; the body rocks back with the pull. A paw
/// pressing a loose unit into the belly takes `stowTime`.
/// (this one: how far the hips drop, m)
pub const squatDrop:f32=0.24;
/// how far the body leans in over the node (radians)
pub const squatLean:f32=0.95;
/// how far the feet step out to each side in the squat (m)
pub const squatStance:f32=0.06;
/// how stiffly the squat eases in and out (spring frequency)
pub const squatFreq:f32=5;
/// how high above the node's ground the paws grip (m)
pub const gripUp:f32=0.11;
/// how far either side of the node each paw grips (m)
pub const gripSide:f32=0.085;
/// how far back the pull draws the paws (m)
pub const pryBack:f32=0.07;
/// how far up the pull lifts the paws (m)
pub const pryUp:f32=0.04;
/// how far the body rocks back with the pull (radians)
pub const pryRock:f32=0.16;
/// how far the wrists twist in the wrench (radians)
pub const pryTwist:f32=0.55;
/// where in a unit's pry the pull ends (0..1)
pub const pullEnd:f32=0.55;
/// where in a unit's pry the wrench ends (0..1); after it, back to the grip
pub const wrenchEnd:f32=0.72;
/// how long a paw takes to press a loose unit into the belly (s)
pub const stowTime:f32=0.3;
/// how stiffly the gripping wrists chase where they are wanted (spring frequency)
pub const handFreq:f32=14;
/// how damped that wrist spring is (1: no overshoot)
pub const handDamp:f32=0.75;
/// the gripping paws are closed this far; a stowing paw cups
/// (this one: how far the gripping fingers close)
pub const pryGrip:f32=1.2;
/// how far a stowing paw cups round its unit
pub const stowCup:f32=0.6;
/// plucking a plant: the paws close either side of its ripe yield and
/// draw it back toward the wolf, bending the plant after them, until it
/// comes loose. The squat goes only as deep as the yield is low: its full
/// depth for one at `lowFrom` over the feet or under, none `lowSpan`
/// higher; past `riseFrom` the wolf stretches up, leaning back by up to
/// `riseLean`. (This one: how far either side of the yield each paw closes, m)
pub const pluckSide:f32=0.06;
/// the wolf steps up to a plant it plucks until its yield is this far
/// ahead of its feet (clear of the leaves, the paws still reaching it)
pub const pluckAt:f32=0.62;
/// how long a paw takes to carry a plucked unit to the belly (s)
pub const pluckStow:f32=0.7;
/// how far the pull draws a plucked yield back toward the wolf (m)
pub const pluckBack:f32=0.16;
/// the squat is at its full depth for work this high over the feet (m)
pub const lowFrom:f32=0.15;
/// and gone this much higher (m)
pub const lowSpan:f32=0.75;
/// past this height over the feet the wolf stretches up to its work (m)
pub const riseFrom:f32=1.0;
/// and is stretched in full this much higher (m)
pub const riseSpan:f32=0.45;
/// how far it leans back, stretched up in full (radians)
pub const riseLean:f32=0.22;
/// how far its hips lift, stretched up in full (m)
pub const riseUp:f32=0.05;
/// how far down the hand from the wrist a plucked bead is held (m)
pub const beadOut:f32=0.085;
/// a plucked bead's radius (m)
pub const beadR:f32=0.045;
/// how brightly a plucked bead glows
pub const beadGlow:f32=0.7;
/// the wolf steps up to a node it gathers from, until it is this far ahead
/// of its feet (and the paws can reach it)
pub const gatherAt:f32=0.45;
/// what the wolf works on or carries sits this high above its feet
/// (m)
pub const chestHeight:f32=1.0;
/// how the belly's load tells on the gait, in three stages: light (up to a
/// third full), heavy, full (past two thirds), each blending into the next
/// over `stageBlend` of fullness about its threshold. Per stage: top walk
/// and sprint speed (a share of the light ones: a little slower, never
/// slow), stride length (a share of the cycle), how high a foot lifts, the
/// pelvis's sway over the planted foot and roll with the stride (the full
/// waddle), how low it sinks and bobs, and how far the body leans back to
/// carry the weight before it.
/// (fields: walk and sprint shares, stride share, lift, sway, roll, sink,
/// bob, lean, in that order)
pub const Gait=struct{walk:f32,sprint:f32,stride:f32,lift:f32,sway:f32,roll:f32,sink:f32,bob:f32,lean:f32};
/// the three stages' gaits: light, heavy, full
pub const gaits=[3]Gait{
  .{.walk=1,.sprint=1,.stride=1,.lift=1,.sway=1,.roll=1,.sink=1,.bob=1.15,.lean=0},
  .{.walk=0.93,.sprint=0.9,.stride=0.88,.lift=0.8,.sway=2.2,.roll=1.8,.sink=1.4,.bob=1.3,.lean=0.05},
  .{.walk=0.86,.sprint=0.8,.stride=0.76,.lift=0.6,.sway=3.6,.roll=3.2,.sink=1.8,.bob=1.5,.lean=0.11},
};
/// where the heavy and full stages begin, as shares of fullness
pub const stageAt=m.Vice(f32,2){1.0/3.0,2.0/3.0};
/// how much fullness each stage blends over about its threshold
pub const stageBlend:f32=0.08;
/// the belly-rest idle: standing still this long with the belly at least
/// `restFull` full (fully in by `restFullIn`), the right palm lies on the
/// belly's upper front (at `restOn`, on its skinned surface) and the left leans on the hip (at
/// `restHip`, the pelvis's frame, x outward), its knuckles curled, the
/// elbow out; the two ease in on a slow spring
/// (this one: how long it stands still first, s)
pub const restAfter:f32=1.2;
/// how full the belly must be before the rest begins (0..1)
pub const restFull:f32=1.0/3.0;
/// how full it is when the rest is fully in (0..1)
pub const restFullIn:f32=0.45;
/// how stiffly the rest pose eases in (spring frequency)
pub const restFreq:f32=2.2;
/// where on the sac the right palm lies, in the sac's own angles: how far
/// up it from the bottom and how far round from its right side (radians);
/// found on the skinned surface, so it lies there at every fill
pub const restOn=m.Vice(f32,2){m.pi*0.66,m.halfPi-0.42};
/// the palm's middle sits this far off the sac (half the paw's thickness, m)
pub const restPalm:f32=0.03;
/// how far down the hand from the wrist the palm's middle is (m)
pub const restHeel:f32=0.048;
/// the resting fingers point down the sac and this much in toward its middle
pub const restInward:f32=0.35;
/// a full belly swells past the arm's easy reach; the paw slides up the
/// sac until the wrist is this share of the arm's length from the shoulder
pub const restReach:f32=0.9;
/// how high up the sac it may slide (radians from the bottom)
pub const restTop:f32=m.pi*0.9;
/// how many halvings find where up the sac it is in reach
pub const restSteps:usize=14;
/// where the left paw leans on the hip (pelvis frame, m, x outward)
pub const restHip=v3(0.22,0.08,-0.01);
/// how far the hip-leaning elbow swings out (radians)
pub const restElbowOut:f32=1.0;
/// how flat the belly-resting (right) paw lays its fingers
pub const restFlat:f32=0.12;
/// how tight the hip-leaning (left) paw curls its knuckles
pub const restFist:f32=1.1;
/// the gait: a full cycle (both feet) covers `cycle + cyclePerSpeed *
/// speed` metres; a foot is planted for `duty` of it, more of it walking
/// slowly than running
/// (this one: the cycle's length standing still, m)
pub const cycle:f32=1.2;
/// how much longer the cycle grows per m/s of speed (m)
pub const cyclePerSpeed:f32=0.2;
/// the share of the cycle a foot is planted, walking slowly
pub const dutySlow:f32=0.6;
/// the share of the cycle a foot is planted, at a sprint
pub const dutyFast:f32=0.38;
/// below this stride the wolf stands: feet only step to stay under it
pub const standing:f32=0.15;
/// a standing foot further than this from where it rests steps back under
pub const settle:f32=0.06;
/// how long that settling step takes (s)
pub const settleTime:f32=0.26;
/// a striding foot's swing lasts its share of the cycle, as if walking at
/// least `swingSpeedMin`, held within these seconds
/// (this one: the slowest speed a swing is timed for, m/s)
pub const swingSpeedMin:f32=0.5;
/// the shortest a striding swing lasts (s)
pub const swingMin:f32=0.12;
/// the longest a striding swing lasts (s)
pub const swingMax:f32=0.4;
/// the fastest a swinging paw moves over the ground (m/s): about twice a
/// sprint, as a running paw passes the body
pub const swingSpeedMax:f32=15;
/// a planted foot never trails the hip by more than this before it lifts
pub const trailMax:f32=0.5;
/// a planted foot trailing this far lifts even while the other swings (a
/// sprint's flight, a sudden turn), so it is never left to be put back
pub const trailHard:f32=0.7;
/// a foot this far from the body (a load, a teleport) is put straight back
pub const lost:f32=1.2;
/// how high a swinging foot lifts (standing, and more at full stride), and
/// how far its toes hang as it swings
/// (this one: the lift standing, m)
pub const liftAmount:f32=0.05;
/// how much higher it lifts at full stride (m)
pub const liftStride:f32=0.08;
/// how far the toes hang as the foot swings (radians)
pub const toeHang:f32=0.55;
/// the lift's arc over the swing (sin^this: under 1 rises fast, hangs high)
pub const liftArc:f32=0.8;
/// the metatarsal folds this much more under the leg mid-swing
pub const swingFold:f32=0.45;
/// how much of the leg's swing toward its foot the metatarsal follows (the
/// rest of the reach taken up by thigh and shin)
pub const metaFollow:f32=0.5;
/// how fast a foot's sense of the ground under it settles to a new slope (1/s)
pub const slopeRate:f32=14;
/// how far the ground is felt round a foot to read its slope (m)
pub const slopeSpan:f32=0.15;
/// the share of thigh and shin's full length the hock is reached with
/// before the hips drop to let a foot reach the ground below
pub const reachShare:f32=0.97;
/// the furthest the hips drop for a foot out of reach (m): a foot further
/// off is reached by a straightening leg, never by the body sinking to it
pub const dropMax:f32=0.12;
/// the pelvis: how far it sinks with stride and bobs at each footfall,
/// sways over the planted foot, turns and rolls with the stride
/// (this one: how far it sinks at full stride, m)
pub const sinkAmount:f32=0.045;
/// how far it bobs down at each footfall (m)
pub const bobAmount:f32=0.028;
/// how far it sways over the planted foot (m)
pub const swayAmount:f32=0.018;
/// how far it turns with the stride (radians)
pub const hipTurn:f32=0.13;
/// how far it rolls with the stride (radians)
pub const hipRoll:f32=0.05;
/// the chest turns against the hips by this share
pub const counter:f32=1.4;
/// lean: forward with stride, more into acceleration (radians per m/s^2),
/// into turns (radians per rad/s), and down into the work
/// (this one: forward lean at full stride, radians)
pub const leanStride:f32=0.14;
/// how far it leans into acceleration (radians per m/s^2)
pub const leanAccel:f32=0.018;
/// the most it ever leans forward or back (radians)
pub const leanMax:f32=0.3;
/// how far it banks into turns (radians per rad/s)
pub const bank:f32=0.05;
/// the most it ever banks (radians)
pub const bankMax:f32=0.2;
/// how far it leans down into the work (radians)
pub const leanWork:f32=0.38;
/// how stiffly the lean follows (spring frequency)
pub const leanFreq:f32=5;
/// how damped the lean's spring is (1: no overshoot)
pub const leanDamp:f32=0.7;
/// how damped the bank's spring is
pub const bankDamp:f32=0.8;
/// arms: swing against the legs, hang out a little, bend at the elbow
/// (more as they come forward); their springs make them lag and carry
/// (this one: how far they swing, radians)
pub const armSwing:f32=0.62;
/// how far they hang out from the body (radians)
pub const armOut:f32=0.13;
/// how far the elbows bend at rest (radians)
pub const elbowRest:f32=0.3;
/// how much more they bend swinging forward (radians)
pub const elbowSwing:f32=0.55;
/// how stiffly the arms follow (spring frequency)
pub const armFreq:f32=9;
/// how damped the arms' springs are (under 1: they carry and overshoot)
pub const armDamp:f32=0.55;
/// the work gesture: reach forward and dig
/// (this one: how far the arms swing down into the dig, radians)
pub const digAmount:f32=-1.1;
/// how fast the dig strikes (radians a second)
pub const digRate:f32=9;
/// how deep the paws dig into the work (m)
pub const digDepth:f32=0.22;
/// breathing: a tempo that quickens with effort, the chest swelling and
/// panting with the jaw a little open at a run
/// (this one: the breath's tempo at rest, radians a second)
pub const breathRate:f32=1.7;
/// the breath's tempo at a full sprint (radians a second)
pub const breathRateRun:f32=4.2;
/// how far the chest swells with each breath at rest
pub const breathAmount:f32=0.02;
/// how far it swells at a run
pub const breathRun:f32=0.03;
/// how far the jaw drops open, panting at a run (radians)
pub const pant:f32=0.09;
/// the head: steadied against the bob and lean, turning into turns,
/// looking about when idle, down into the work
/// (this one: how stiffly it follows, spring frequency)
pub const headFreq:f32=7;
/// how damped the head's spring is
pub const headDamp:f32=0.8;
/// how far it turns into turns (radians per rad/s)
pub const lookTurn:f32=0.18;
/// the most it turns to look (radians)
pub const lookMax:f32=0.6;
/// how far it looks about when idle (radians)
pub const lookIdle:f32=0.28;
/// how fast its idle look wanders (per second)
pub const lookIdleRate:f32=0.23;
/// how far it looks down into the work (radians)
pub const lookWork:f32=0.45;
/// seen from its own eyes: the head nods this share of how far they look
/// up or down, within these limits (down +)
/// (this one: the nod's share)
pub const gazeNod:f32=0.6;
/// the furthest it nods up (radians)
pub const gazeNodUp:f32=-0.5;
/// the furthest it nods down (radians)
pub const gazeNodDown:f32=0.7;
