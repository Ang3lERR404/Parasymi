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
//! The list shows each channel in words (`right shoulder lean`; the file
//! keeps its path, `arms.1.root.z`). `m` marks the playhead, a named
//! moment of the clip (`left paw lands`), its name typed on the timeline
//! (enter or escape done; `m` on a mark renames it, shift `m` takes it
//! out); shift and the arrows stop at marks as at keys.
//! The camera orbits as the mesh editor's does (tools/orbit.zig): freely,
//! over the top and under alike (middle drag; the wheel zooms); `.` eases
//! it onto the selected joint (else back onto the whole subject).
//! `ctrl+z` undoes (tools/history.zig), `ctrl+y` or `ctrl+shift+z` redoes:
//! a whole drag, or a whole typed mark name, is one step.
//!
//! decision: a developer's tool, not the game: its few words and keys are
//! written here, not in the strings or controls files (the camera's orbit
//! still follows the game's binding).
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// keyframed clips: channels, keys and sampling
const clip=engine.anim.clip;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the wolf's skeleton and its `Pose`
const skel=ps.skeleton;
/// one plant or structure standing alone, and its `Look`
const specimen=ps.specimen;
/// every f32 of the wolf's `Pose`, each a channel a clip can key
const PoseCh=clip.Channels(skel.Pose);
/// every f32 of a specimen's `Look`, each a channel a clip can key
const LookCh=clip.Channels(specimen.Look);
/// the editor's sizes, colours, words and keys
pub const settings=@import("animedit/settings.zig");
/// the wolf's joints as the editor sees them: dots, picking and gizmos
pub const rigging=@import("animedit/rigging.zig");
/// the editor's state: the clip, the subject, the playhead, the selection
pub const editor=@import("animedit/editor.zig");
/// what the gardener's hands do to the clip: keying, dragging, saving
pub const editing=@import("animedit/editing.zig");
/// the side panel: the channels, their values and the timeline
pub const panel=@import("animedit/panel.zig");
/// the window, the renderer and the frame loop
pub const run=@import("animedit/run.zig");
/// the editor's start: opens the window and runs until it closes
pub const main=run.main;
test{
  _=settings;
  _=rigging;
  _=editor;
  _=editing;
  _=panel;
  _=run;
}
