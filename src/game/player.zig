//! the player: an anthropomorphic wolf woven from vines, leaves and sap.
//! Movement is tile-aware (no wading, one terrace step at a time) and every
//! motion is procedural, posing one skeleton (gfx/meshes/wolf_skeleton.zig)
//! that the GPU skins the wolf's single body over:
//! - feet are planted in the world and stay there through their stance;
//!   each swings on an arc to where it will be needed, the gait's phase
//!   choosing when, or, standing, whenever a foot is left behind;
//! - the plantigrade legs reach them by inverse kinematics;
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
/// the hub every game module is reached through
const lib=@import("../lib.zig");
/// how many slots the wolf's sap belly has: its carried inventory size
pub const slots=24;
/// the wolf's numbers: gait, stride, belly, gathering timings
pub const tuning=@import("player/tuning.zig");
/// the wolf's look numbers: how its springs, ears and tail move and settle
pub const tuningLook=@import("player/tuning_look.zig");
/// the wolf itself: its state, and the frame step that moves it
pub const player=@import("player/player.zig");
/// how it walks: the gait's phase, the planted feet and their swings
pub const motion=@import("player/motion.zig");
/// the springs everything loose follows on: arms, lean, head, ears, tail
pub const springs=@import("player/springs.zig");
/// how the skeleton is posed from all of it, each frame
pub const posing=@import("player/posing.zig");
/// the limbs reached by inverse kinematics: legs to feet, arms to wrists
pub const ik=@import("player/ik.zig");
/// the wolf's headless tests
pub const tests=@import("player/tests.zig");
/// the wolf, as the rest of the game knows it
pub const Player=player.Player;
/// one foot coming down, for the footstep sound
pub const Footfall=player.Footfall;
/// where a gathering wolf crouches over a node
pub const gatherAt=tuning.gatherAt;
/// a leg reaching its foot (inverse kinematics)
pub const solveLeg=ik.solveLeg;
/// an arm reaching its wrist (inverse kinematics)
pub const solveArm=ik.solveArm;
/// an arm reaching its wrist with the elbow swung round
pub const solveArmTurned=ik.solveArmTurned;
/// an arm reaching its wrist, its elbow toward a pole
pub const solveArmPole=ik.solveArmPole;
/// the wrist's turn laying a hand along fingers and palm
pub const handTo=ik.handTo;
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
