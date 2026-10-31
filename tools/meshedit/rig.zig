//! a sculpt's bones: the game's (sculpt_rig.zig), as the mesh editor shapes them.
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the most bones a sculpt may have, twins counted
pub const maxBones=ps.sculptRig.maxBones;
/// one bone: its name, its parent, its joint, whether it has a twin
pub const Bone=ps.sculptRig.Bone;
/// the bones as the sculpt takes them, twins counted
pub const Skeleton=ps.sculptRig.Skeleton;
/// how many bones a list makes, twins counted
pub const count=ps.sculptRig.count;
/// the skeleton a list of bones makes
pub const skeleton=ps.sculptRig.skeleton;
/// a turn (degrees) as a matrix
pub const turnOf=ps.sculptRig.turnOf;
/// every bone posed
pub const pose=ps.sculptRig.pose;
/// where a posed joint stands
pub const joint=ps.sculptRig.joint;
