//! how the wolf looks as it moves: eyes, ears, fingers, glow, sap, belly and tail.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, easing, lerps
const m=engine.core.math;
/// the wolf's body mesh: where its eyes sit
const bodyMesh=lib.wolfBody;
/// a point or direction in 3D
const V3=m.V3;
/// builds a 3D vector from its three parts
const v3=m.v3;
/// a bone's bit in a mask of bones
const bit=lib.player.ik.bit;
/// the eyes, between the two (head frame), a little forward of their sockets
pub const eyesAt=v3(0,bodyMesh.eye[1],bodyMesh.eye[2]+0.01);
/// what is hidden from its own eyes: the bones of the head (its muzzle,
/// eyes, hair, jaw and ears)
pub const headBones:u64=bit(.head)|bit(.jaw)|bit(.earL)|bit(.earR);
/// ears: lie back with speed, flick now and then
/// (this one: how far they lie back at full speed, radians)
pub const earBack:f32=0.45;
/// how stiffly the ears follow (spring frequency)
pub const earFreq:f32=14;
/// how damped the ears' springs are (low: they wobble)
pub const earDamp:f32=0.35;
/// how hard a flick kicks an ear (radians a second)
pub const earFlick:f32=9;
/// how often an ear may flick (s between chances)
pub const earFlickEvery:f32=3.5;
/// fingers: a loose curl at rest (radians at the knuckle), curling more as
/// the arm swings forward; idle, now and then they flex in a ripple one
/// after the next; digging, they open and rake shut with each stroke, a
/// beat apart. The tip joint follows the knuckle. Open fingers fan out.
/// (this one: the curl at rest)
pub const curlRest:f32=0.42;
/// how much more they curl as the arm swings forward (radians)
pub const curlSwing:f32=0.45;
/// how far an idle flex curls them (radians)
pub const curlFlex:f32=0.7;
/// how fast the noise wanders that decides when they flex
pub const flexRate:f32=0.35;
/// how fast the flexing ripple runs (radians a second)
pub const flexWave:f32=5.5;
/// how far behind its neighbour each finger flexes (radians of the ripple)
pub const flexLag:f32=0.75;
/// how far the fingers open between dig strokes (radians)
pub const gripOpen:f32=0.05;
/// how far they rake shut with each stroke (radians)
pub const gripClose:f32=1.35;
/// how far behind its neighbour each finger rakes (radians of the stroke)
pub const gripLag:f32=0.3;
/// how much of the knuckle's curl the tip joint follows (0..1)
pub const tipShare:f32=0.9;
/// how far the tip joint is bent at rest (radians)
pub const tipRest:f32=0.15;
/// how far open fingers fan apart (radians)
pub const spreadOpen:f32=0.6;
/// how far closed fingers draw together (radians)
pub const spreadShut:f32=-0.35;
/// how stiffly the fingers follow (spring frequency)
pub const fingerFreq:f32=10;
/// how damped the fingers' springs are
pub const fingerDamp:f32=0.5;
/// the fingers' spread springs this damped
pub const spreadDamp:f32=0.7;
/// paw beans and the nose: sap made denser (80%) and browner than the belly
pub const beanOpacity:f32=0.8;
/// how much the beans, nose, inner ears and belly lumps glow; the belly's
/// sap glows from `bellyGlow` up by `bellyGlowFull` as it fills
/// (this one: the paw beans' glow)
pub const beanGlow:f32=0.15;
/// the nose's glow
pub const noseGlow:f32=0.1;
/// the inner ears' glow
pub const earGlow:f32=0.3;
/// the belly lumps' glow
pub const lumpGlow:f32=0.25;
/// the belly sap's glow when empty
pub const bellyGlow:f32=0.35;
/// how much more the belly sap glows once full
pub const bellyGlowFull:f32=0.65;
/// the paw beans' colour (rgba, 0..1)
pub const beanTint=[4]f32{0.72,0.5,0.38,1};
/// the nose's colour (rgba, 0..1)
pub const noseTint=[4]f32{0.3,0.22,0.2,1};
/// a planted foot's central pad flattens by this fraction
pub const padFlatten:f32=0.1;
/// how stiffly a pad squashes and springs back (spring frequency)
pub const padFreq:f32=14;
/// the inner ears' sap
pub const earOpacity:f32=0.5;
/// the belly's sap at its centre lets the body behind show through faintly;
/// the pectorals are solidified sap, 30% less see-through; the rear's
/// resin is a little denser again
/// (this one: the belly sap's opacity at its centre, 0..1)
pub const sapOpacity:f32=0.72;
/// the pectorals' opacity: 30% less see-through than the belly's sap
pub const pecOpacity:f32=1-(1-sapOpacity)*0.7;
/// the rear's opacity: 40% less see-through than the belly's sap
pub const rumpOpacity:f32=1-(1-sapOpacity)*0.6;
/// how strongly the wolf's acceleration is felt by what hangs in and on its
/// body (m/s^2 down to a few centimetres of lag)
pub const sloshAmount:f32=0.05;
/// a footfall drops the belly's contents a little
pub const stepKick:f32=0.18;
/// the body's glow (the eyes carry it; the hide barely), how much its fur
/// leaves stir
/// (this one: the body's glow)
pub const bodyGlow:f32=0.6;
/// how much its fur leaves stir
pub const bodyFlutter:f32=0.3;
/// a body this large is culled and detailed about its middle
pub const bodyMid:f32=0.8;
/// one of the heavier things carried, hanging in the sap on its own spring.
const Lump=struct{
  /// rest place within the belly (unit ball, scaled by the room inside)
  rest:V3,
  /// how stiff its spring is
  k:f32,
  /// how damped its spring is
  c:f32,
  /// how heavy it is: heavier lags and swings further
  mass:f32,
};
/// the five lumps, each with its own rest place, spring and weight
pub const lumps=[_]Lump{
  .{.rest=v3(0.35,-0.3,0.3),.k=55,.c=5,.mass=0.7},
  .{.rest=v3(-0.4,-0.35,0.15),.k=70,.c=6,.mass=0.9},
  .{.rest=v3(0.05,-0.6,-0.1),.k=40,.c=4,.mass=1.0},
  .{.rest=v3(0.4,0.15,-0.2),.k=80,.c=7,.mass=0.5},
  .{.rest=v3(-0.25,0.05,0.45),.k=62,.c=5.5,.mass=0.6},
};
/// how large each lump is (m)
pub const lumpR:f32=0.055;
/// the pectorals: dense gel on a spring each (left, right)
/// (this one: each spring's stiffness)
pub const pecK=[2]f32{60,55};
/// how damped their springs are
pub const pecC:f32=6;
/// how heavy each pectoral is
pub const pecMass:f32=0.8;
/// the furthest either strays from rest (m)
pub const pecMax:f32=0.02;
/// the rear: resin a little firmer than the chest, bouncing with each step
/// (this one: its spring's stiffness)
pub const rumpK:f32=70;
/// how damped its spring is
pub const rumpC:f32=5;
/// the furthest it strays from rest (m)
pub const rumpMax:f32=0.02;
/// how hard each footfall bounces it (m/s at full stride)
pub const rumpKick:f32=0.12;
/// a lump keeps within this share of the sac, and at least this much room
/// (this one: the share of the sac a lump keeps within)
pub const bellyRoomSize:f32=0.8;
/// the least room a lump always has (m)
pub const bellyRoomMin:f32=0.01;
/// the tail's steering: turning swings it out (capped), an idle sway at rest
/// gives way to the gait's swing in stride; it lifts with stride; each
/// joint's spring is softer than the one before
/// (this one: how far a turn swings it, radians per rad/s)
pub const tailTurn:f32=0.1;
/// the furthest a turn swings it (radians)
pub const tailTurnMax:f32=0.6;
/// how fast the idle sway swings (radians a second)
pub const tailIdleRate:f32=1.3;
/// how far the idle sway swings (radians)
pub const tailIdle:f32=0.16;
/// how far it swings with the gait (radians)
pub const tailGait:f32=0.12;
/// how far its root lifts at full stride (radians)
pub const tailLift:f32=0.25;
/// how far each joint past the root droops at rest (radians)
pub const tailDroop:f32=0.16;
/// how stiff the root joint's spring is (spring frequency)
pub const tailFreq:f32=7;
/// how much softer each joint's spring is than the one before
pub const tailFreqStep:f32=1.2;
/// the share of the turn toward the gaze the neck takes (the skull the rest)
pub const neckShare:f32=0.4;
/// how strongly each point of the tail is drawn back to its swinging rest
/// shape (per second, at its root; its tip half as strongly)
pub const tailStiff:f32=11;
/// how much of its own motion each point of the tail keeps from one
/// sixtieth of a second to the next (how far it follows through)
pub const tailKeep:f32=0.86;
/// how damped the tail's springs are (low: it swishes)
pub const tailDamp:f32=0.45;
