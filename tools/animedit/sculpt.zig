//! a rigged sculpt as the animation editor moves it (`--mesh=<name>`): the
//! game's own (sculpts.zig): the mesh editor's `.mesh` read, its bones
//! turned to the clip's channels (the root's place, then each bone's
//! pitch, yaw and roll), its skin drawn bent by them.
/// the game, reached through its import hub
const ps=@import("parasymi");
/// a sculpt with its channels and their values
pub const Sculpt=ps.sculpts.Rigged;
/// a mesh as the mesh editor keeps it
pub const Doc=ps.sculptDoc.Doc;
