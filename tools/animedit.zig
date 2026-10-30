//! a rudimentary animation editor: keys a clip (engine anim/clip.zig) for
//! the wolf's skeleton, or for one plant or structure alone, shown live on
//! the game's own renderer, and keeps it as text in `src/anim/<name>.anim`.
//! The game does not play clips back yet. From the repo root:
//!   zig build animedit -- --wolf | --plant=<species> | --structure=<kind> [--clip=<name>]
//! (a name not yet kept starts a new clip, written there at once)
//! (`--at=<s>` starts the playhead there, `--channel=<name>` on that
//! channel; `--shot` saves one frame to `shots/animedit.png` and closes,
//! for checking it headless.)
//! Every f32 of the wolf's `Pose` (or a specimen's `Look`) is a channel;
//! dragging a channel's value keys it at the playhead. On the wolf each
//! joint is a dot on its skeleton: a click selects it (again, the next
//! joint under the mouse), and its gizmo (tools/gizmo.zig) keys it as it
//! is dragged: rings for a joint's turns, one ring for a hinge, arrows
//! (and the centre, across the view) for the hips' place.
//! The camera orbits as the mesh editor's does (tools/orbit.zig): freely,
//! over the top and under alike (middle drag; the wheel zooms); `.` eases
//! it onto the selected joint (else back onto the whole subject).
//!
//! decision: a developer's tool, not the game: its few words and keys are
//! written here, not in the strings or controls files (the camera's orbit
//! still follows the game's binding).
const engine=ps.engine;
const clip=engine.anim.clip;
const ps=@import("parasymi");
const skel=ps.skeleton;
const specimen=ps.specimen;
const PoseCh=clip.Channels(skel.Pose);
const LookCh=clip.Channels(specimen.Look);
pub const settings=@import("animedit/settings.zig");
pub const rigging=@import("animedit/rigging.zig");
pub const editor=@import("animedit/editor.zig");
pub const editing=@import("animedit/editing.zig");
pub const panel=@import("animedit/panel.zig");
pub const run=@import("animedit/run.zig");
pub const main=run.main;
test{
  _=settings;
  _=rigging;
  _=editor;
  _=editing;
  _=panel;
  _=run;
}
