//! a rudimentary mesh editor: sculpts one seamless surface out of forms
//! (engine gfx/sculpt.zig: ellipsoids, rounded cones, rounded boxes, each
//! melted into the ones before it or carved out of them), meshed again as
//! it is edited and shown on the game's own renderer, alone on the
//! generated ground (no wolf, plants or structures), and keeps it as text
//! in `src/mesh/<name>.mesh`. The game does not read these yet. From the
//! repo root:
//!   zig build meshedit -- [--mesh=<name>]
//! (a name not yet kept starts a new mesh, written there at once)
//! (`--gizmo=move|turn|size` starts the gizmo so; `--shot` saves one frame
//! to `shots/meshedit.png` and closes, for checking it headless.)
//! Each form is placed by `pos`, turned by `rot` (degrees, y then x then
//! z) and sized by `size` (radii; a cone's x and z its radii at its foot
//! and its tip, y half its length; a box's half extents); `round` rounds a
//! box, `melt` is how far it melts into what is before it, `col` its colour.
//! Each form also picks the shader its part of the surface is drawn with
//! (`m`, shift `m` back): one of the game's part roles (vertex.Part:
//! stem, leaf, bloom, resin, ...), as part.vert/part.frag shade it; where
//! forms meet, each vertex takes the role of the form it lies nearest.
//! The selected form carries a gizmo (tools/gizmo.zig): `1` moves it
//! (arrows along each axis, the centre across the view), `2` turns it
//! (a ring for each of its turns), `3` sizes it (along its own axes).
//! The camera orbits the sculpt freely (middle drag, over the top and
//! under it alike; the wheel zooms); `.` eases it onto the selected form.
//!
//! decision: a developer's tool, not the game: its few words and keys are
//! written here, not in the strings or controls files (the camera's orbit
//! still follows the game's binding).
const gizmo=@import("gizmo.zig");
pub const settings=@import("meshedit/settings.zig");
pub const doc=@import("meshedit/doc.zig");
pub const editor=@import("meshedit/editor.zig");
pub const editing=@import("meshedit/editing.zig");
pub const panel=@import("meshedit/panel.zig");
pub const run=@import("meshedit/run.zig");
pub const tests=@import("meshedit/tests.zig");
pub const main=run.main;
test{
  _=gizmo;
  _=@import("orbit.zig");
}
test{
  _=settings;
  _=doc;
  _=editor;
  _=editing;
  _=panel;
  _=run;
  _=tests;
}
