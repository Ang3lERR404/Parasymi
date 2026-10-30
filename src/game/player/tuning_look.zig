//! how the wolf looks as it moves: eyes, ears, fingers, glow, sap, belly and tail.
const lib = @import("../../lib.zig");
const engine = lib.engine;
const m = engine.core.math;
const body_mesh = lib.wolf_body;
const V3 = m.V3;
const v3 = m.v3;
const bit = lib.player.ik.bit;

/// the eyes, between the two (head frame), a little forward of their sockets
pub const EYES_AT = v3(0, body_mesh.EYE[1], body_mesh.EYE[2] + 0.01);
/// what is hidden from its own eyes: the bones of the head (its muzzle,
/// eyes, hair, jaw and ears)
pub const HEAD_BONES:u64 = bit(.head) | bit(.jaw) | bit(.ear_l) | bit(.ear_r);
/// ears: lie back with speed, flick now and then
pub const EAR_BACK:f32 = 0.45;
pub const EAR_FREQ:f32 = 14;
pub const EAR_DAMP:f32 = 0.35;
pub const EAR_FLICK:f32 = 9;
pub const EAR_FLICK_EVERY:f32 = 3.5;
/// fingers: a loose curl at rest (radians at the knuckle), curling more as
/// the arm swings forward; idle, now and then they flex in a ripple one
/// after the next; digging, they open and rake shut with each stroke, a
/// beat apart. The tip joint follows the knuckle. Open fingers fan out.
pub const CURL_REST:f32 = 0.42;
pub const CURL_SWING:f32 = 0.45;
pub const CURL_FLEX:f32 = 0.7;
pub const FLEX_RATE:f32 = 0.35;
pub const FLEX_WAVE:f32 = 5.5;
pub const FLEX_LAG:f32 = 0.75;
pub const GRIP_OPEN:f32 = 0.05;
pub const GRIP_CLOSE:f32 = 1.35;
pub const GRIP_LAG:f32 = 0.3;
pub const TIP_SHARE:f32 = 0.9;
pub const TIP_REST:f32 = 0.15;
pub const SPREAD_OPEN:f32 = 0.6;
pub const SPREAD_SHUT:f32 = -0.35;
pub const FINGER_FREQ:f32 = 10;
pub const FINGER_DAMP:f32 = 0.5;
/// the fingers' spread springs this damped
pub const SPREAD_DAMP:f32 = 0.7;

/// paw beans and the nose: sap made denser (80%) and browner than the belly
pub const BEAN_OPACITY:f32 = 0.8;
/// how much the beans, nose, inner ears and belly lumps glow; the belly's
/// sap glows from `BELLY_GLOW` up by `BELLY_GLOW_FULL` as it fills
pub const BEAN_GLOW:f32 = 0.15;
pub const NOSE_GLOW:f32 = 0.1;
pub const EAR_GLOW:f32 = 0.3;
pub const LUMP_GLOW:f32 = 0.25;
pub const BELLY_GLOW:f32 = 0.35;
pub const BELLY_GLOW_FULL:f32 = 0.65;
pub const BEAN_TINT = [4]f32{ 0.72, 0.5, 0.38, 1 };
pub const NOSE_TINT = [4]f32{ 0.3, 0.22, 0.2, 1 };
/// a planted foot's central pad flattens by this fraction
pub const PAD_FLATTEN:f32 = 0.1;
pub const PAD_FREQ:f32 = 14;
/// the inner ears' sap
pub const EAR_OPACITY:f32 = 0.5;
/// the belly's sap at its centre lets the body behind show through faintly;
/// the pectorals are solidified sap, 30% less see-through; the rear's
/// resin is a little denser again
pub const SAP_OPACITY:f32 = 0.72;
pub const PEC_OPACITY:f32 = 1 - (1 - SAP_OPACITY) * 0.7;
pub const RUMP_OPACITY:f32 = 1 - (1 - SAP_OPACITY) * 0.6;
/// how strongly the wolf's acceleration is felt by what hangs in and on its
/// body (m/s^2 down to a few centimetres of lag)
pub const SLOSH:f32 = 0.05;
/// a footfall drops the belly's contents a little
pub const STEP_KICK:f32 = 0.18;
/// the body's glow (the eyes carry it; the hide barely), how much its fur
/// leaves stir
pub const BODY_GLOW:f32 = 0.6;
pub const BODY_FLUTTER:f32 = 0.3;
/// a body this large is culled and detailed about its middle
pub const BODY_MID:f32 = 0.8;

/// one of the heavier things carried, hanging in the sap on its own spring.
const Lump = struct {
  /// rest place within the belly (unit ball, scaled by the room inside)
  rest:V3,
  k:f32,
  c:f32,
  mass:f32,
};
pub const lumps = [_]Lump{
  .{ .rest = v3(0.35, -0.3, 0.3), .k = 55, .c = 5, .mass = 0.7 },
  .{ .rest = v3(-0.4, -0.35, 0.15), .k = 70, .c = 6, .mass = 0.9 },
  .{ .rest = v3(0.05, -0.6, -0.1), .k = 40, .c = 4, .mass = 1.0 },
  .{ .rest = v3(0.4, 0.15, -0.2), .k = 80, .c = 7, .mass = 0.5 },
  .{ .rest = v3(-0.25, 0.05, 0.45), .k = 62, .c = 5.5, .mass = 0.6 },
};
pub const LUMP_R:f32 = 0.055;
/// the pectorals: dense gel on a spring each (left, right)
pub const PEC_K = [2]f32{ 60, 55 };
pub const PEC_C:f32 = 6;
pub const PEC_MASS:f32 = 0.8;
pub const PEC_MAX:f32 = 0.02;
/// the rear: resin a little firmer than the chest, bouncing with each step
pub const RUMP_K:f32 = 70;
pub const RUMP_C:f32 = 5;
pub const RUMP_MAX:f32 = 0.02;
pub const RUMP_KICK:f32 = 0.12;
/// a lump keeps within this share of the sac, and at least this much room
pub const BELLY_ROOM:f32 = 0.8;
pub const BELLY_ROOM_MIN:f32 = 0.01;

/// the tail's steering: turning swings it out (capped), an idle sway at rest
/// gives way to the gait's swing in stride; it lifts with stride; each
/// joint's spring is softer than the one before
pub const TAIL_TURN:f32 = 0.1;
pub const TAIL_TURN_MAX:f32 = 0.6;
pub const TAIL_IDLE_RATE:f32 = 1.3;
pub const TAIL_IDLE:f32 = 0.16;
pub const TAIL_GAIT:f32 = 0.12;
pub const TAIL_LIFT:f32 = 0.25;
pub const TAIL_DROOP:f32 = 0.16;
pub const TAIL_FREQ:f32 = 7;
pub const TAIL_FREQ_STEP:f32 = 1.2;
pub const TAIL_DAMP:f32 = 0.45;
