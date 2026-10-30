//! how the wolf looks as it moves: eyes, ears, fingers, glow, sap, belly and tail.
const lib=@import("../../lib.zig");
const engine=lib.engine;
const m=engine.core.math;
const bodyMesh=lib.wolfBody;
const V3=m.V3;
const v3=m.v3;
const bit=lib.player.ik.bit;
/// the eyes, between the two (head frame), a little forward of their sockets
pub const eyesAt=v3(0,bodyMesh.eye[1],bodyMesh.eye[2]+0.01);
/// what is hidden from its own eyes: the bones of the head (its muzzle,
/// eyes, hair, jaw and ears)
pub const headBones:u64=bit(.head)|bit(.jaw)|bit(.earL)|bit(.earR);
/// ears: lie back with speed, flick now and then
pub const earBack:f32=0.45;
pub const earFreq:f32=14;
pub const earDamp:f32=0.35;
pub const earFlick:f32=9;
pub const earFlickEvery:f32=3.5;
/// fingers: a loose curl at rest (radians at the knuckle), curling more as
/// the arm swings forward; idle, now and then they flex in a ripple one
/// after the next; digging, they open and rake shut with each stroke, a
/// beat apart. The tip joint follows the knuckle. Open fingers fan out.
pub const curlRest:f32=0.42;
pub const curlSwing:f32=0.45;
pub const curlFlex:f32=0.7;
pub const flexRate:f32=0.35;
pub const flexWave:f32=5.5;
pub const flexLag:f32=0.75;
pub const gripOpen:f32=0.05;
pub const gripClose:f32=1.35;
pub const gripLag:f32=0.3;
pub const tipShare:f32=0.9;
pub const tipRest:f32=0.15;
pub const spreadOpen:f32=0.6;
pub const spreadShut:f32=-0.35;
pub const fingerFreq:f32=10;
pub const fingerDamp:f32=0.5;
/// the fingers' spread springs this damped
pub const spreadDamp:f32=0.7;
/// paw beans and the nose: sap made denser (80%) and browner than the belly
pub const beanOpacity:f32=0.8;
/// how much the beans, nose, inner ears and belly lumps glow; the belly's
/// sap glows from `BELLY_GLOW` up by `BELLY_GLOW_FULL` as it fills
pub const beanGlow:f32=0.15;
pub const noseGlow:f32=0.1;
pub const earGlow:f32=0.3;
pub const lumpGlow:f32=0.25;
pub const bellyGlow:f32=0.35;
pub const bellyGlowFull:f32=0.65;
pub const beanTint=[4]f32{0.72,0.5,0.38,1};
pub const noseTint=[4]f32{0.3,0.22,0.2,1};
/// a planted foot's central pad flattens by this fraction
pub const padFlatten:f32=0.1;
pub const padFreq:f32=14;
/// the inner ears' sap
pub const earOpacity:f32=0.5;
/// the belly's sap at its centre lets the body behind show through faintly;
/// the pectorals are solidified sap, 30% less see-through; the rear's
/// resin is a little denser again
pub const sapOpacity:f32=0.72;
pub const pecOpacity:f32=1-(1-sapOpacity)*0.7;
pub const rumpOpacity:f32=1-(1-sapOpacity)*0.6;
/// how strongly the wolf's acceleration is felt by what hangs in and on its
/// body (m/s^2 down to a few centimetres of lag)
pub const sloshAmount:f32=0.05;
/// a footfall drops the belly's contents a little
pub const stepKick:f32=0.18;
/// the body's glow (the eyes carry it; the hide barely), how much its fur
/// leaves stir
pub const bodyGlow:f32=0.6;
pub const bodyFlutter:f32=0.3;
/// a body this large is culled and detailed about its middle
pub const bodyMid:f32=0.8;
/// one of the heavier things carried, hanging in the sap on its own spring.
const Lump=struct{
  /// rest place within the belly (unit ball, scaled by the room inside)
  rest:V3,
  k:f32,
  c:f32,
  mass:f32,
};
pub const lumps=[_]Lump{
  .{.rest=v3(0.35,-0.3,0.3),.k=55,.c=5,.mass=0.7},
  .{.rest=v3(-0.4,-0.35,0.15),.k=70,.c=6,.mass=0.9},
  .{.rest=v3(0.05,-0.6,-0.1),.k=40,.c=4,.mass=1.0},
  .{.rest=v3(0.4,0.15,-0.2),.k=80,.c=7,.mass=0.5},
  .{.rest=v3(-0.25,0.05,0.45),.k=62,.c=5.5,.mass=0.6},
};
pub const lumpR:f32=0.055;
/// the pectorals: dense gel on a spring each (left, right)
pub const pecK=[2]f32{60,55};
pub const pecC:f32=6;
pub const pecMass:f32=0.8;
pub const pecMax:f32=0.02;
/// the rear: resin a little firmer than the chest, bouncing with each step
pub const rumpK:f32=70;
pub const rumpC:f32=5;
pub const rumpMax:f32=0.02;
pub const rumpKick:f32=0.12;
/// a lump keeps within this share of the sac, and at least this much room
pub const bellyRoomSize:f32=0.8;
pub const bellyRoomMin:f32=0.01;
/// the tail's steering: turning swings it out (capped), an idle sway at rest
/// gives way to the gait's swing in stride; it lifts with stride; each
/// joint's spring is softer than the one before
pub const tailTurn:f32=0.1;
pub const tailTurnMax:f32=0.6;
pub const tailIdleRate:f32=1.3;
pub const tailIdle:f32=0.16;
pub const tailGait:f32=0.12;
pub const tailLift:f32=0.25;
pub const tailDroop:f32=0.16;
pub const tailFreq:f32=7;
pub const tailFreqStep:f32=1.2;
pub const tailDamp:f32=0.45;
