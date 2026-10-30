//! the player: an anthropomorphic wolf woven from vines, leaves and sap.
//! Movement is tile-aware (no wading, one terrace step at a time) and every
//! motion is procedural, posing one skeleton (gfx/meshes/wolf_skeleton.zig)
//! that the GPU skins the wolf's single body over:
//! - feet are planted in the world and stay there through their stance;
//!   each swings on an arc to where it will be needed, the gait's phase
//!   choosing when, or, standing, whenever a foot is left behind;
//! - the digitigrade legs reach them by inverse kinematics;
//! - the pelvis bobs low at each footfall, sways over the planted foot,
//!   rolls and turns with the stride, and the chest turns against it;
//! - arms, lean, head and ears follow on springs, so motion carries,
//!   overshoots a little and settles; the head steadies against the bob;
//! - a spring-driven tail, breathing that quickens with effort, panting,
//!   and a sap belly that swells with what it carries; the fuller it is the
//!   heavier the gait, in three stages (light, heavy, full: a waddle), and a
//!   little slower; standing idle with a heavy belly, one paw rests on top
//!   of it and the other leans on the hip;
//! - gathering, it drops into a deep squat over the node, both paws grip it
//!   (arms by inverse kinematics) and wrench it back once a unit, and each
//!   unit that comes loose is pressed into the belly by one paw, in turn.
const lib=@import("../lib.zig");
pub const slots=24;
pub const tuning=@import("player/tuning.zig");
pub const tuningLook=@import("player/tuning_look.zig");
pub const player=@import("player/player.zig");
pub const motion=@import("player/motion.zig");
pub const springs=@import("player/springs.zig");
pub const posing=@import("player/posing.zig");
pub const ik=@import("player/ik.zig");
pub const tests=@import("player/tests.zig");
pub const Player=player.Player;
pub const Footfall=player.Footfall;
pub const gatherAt=tuning.gatherAt;
pub const solveLeg=ik.solveLeg;
pub const solveArm=ik.solveArm;
pub const solveArmTurned=ik.solveArmTurned;
test{
  _=tuning;
  _=tuningLook;
  _=player;
  _=motion;
  _=springs;
  _=posing;
  _=ik;
  _=tests;
}
