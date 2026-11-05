//! a rudimentary mesh editor: sculpts one seamless surface out of forms
//! (engine gfx/sculpt.zig: ellipsoids, rounded cones, rounded boxes and
//! curling tubes, each melted into the ones before it, carved out of them
//! or only inking their colour), meshed again as
//! it is edited and shown on the game's own renderer, alone on the
//! generated ground (no wolf, plants or structures), and keeps it as text
//! in `src/mesh/<name>.mesh`, which the game reads at startup
//! (game/sculpts.zig). A toolbar down the window's right side has a button
//! for every key (tools/toolbar.zig, meshedit/buttons.zig), lit while what
//! it toggles is on; `h` shows what the mouse does. From the repo root:
//!   zig build meshedit -- [--mesh=<name>]
//! (a name not yet kept starts a new mesh, written there at once)
//! (`--gizmo=move|turn|size` starts the gizmo so; `--rig` in rig mode,
//! `--try=<pitch>,<yaw>,<roll>` its last bone test-turned so (degrees);
//! `--rename=<name>` renames the sculpt at once, as a click on its path
//! (top left) and a typed name do: its clip and every nest using it follow;
//! `--shot` saves one frame
//! to `shots/meshedit.png` and closes, for checking it headless.)
//! Each form is placed by `pos`, turned by `rot` (degrees, y then x then
//! z) and sized by `size` (radii; a cone's x and z its radii at its foot
//! and its tip, y half its length; a box's half extents; a tube's x and z
//! its radii at its foot and its tip, y its length); `round` rounds a
//! box, `melt` is how far it melts into what is before it (an ink form's
//! fade), `curl` how far a tube turns toward x from its foot to its tip
//! (degrees: a horn, a tail), `col` its colour. `t` steps the shape, `c`
//! carves, `i` inks (colour only, adding nothing: an eye's dark ring).
//! `x` gives the selected form a twin, mirrored across the sculpt's middle
//! (x=0): it follows its form as it is shaped (one ear makes both).
//! ctrl and a click gathers a form into the selected one's group (or lets
//! it go): the group moves and turns with it, round where it stands; `g`
//! snaps the selected form and its group to the grid. A nest (`t` on to it)
//! places another whole sculpt kept beside this one as one form (`p` picks
//! which; its `size` x the scale, the same every way): its forms melt in
//! where it stands, ride its bone, and a twin mirrors all of it; the other
//! sculpts are read again before each meshing, so a part edited elsewhere
//! shows at once.
//! `j` is rig mode (meshedit/rigging.zig): the bones listed in place of the
//! forms, each a joint hung off its parent (the first, the root), `n`
//! hanging a new one off the selected, `x` twinning it across the middle;
//! the gizmo moves a joint (`1`) or test-turns its bone (`2`, never kept)
//! so the skin can be seen to bend. Each form rides one bone (`o` steps
//! it), its twin the bone's twin, and the sculpt weights the skin to them.
//! `f2` names the selected form (`snout`, `left ear`): typed in its row,
//! enter or escape done, kept in the file; the panel shows each value in
//! words (`place up`, `colour red`, a cone's `tip radius`).
//! Each form also picks the shader its part of the surface is drawn with
//! (`m`, shift `m` back): one of the game's part roles (vertex.Part:
//! stem, leaf, bloom, resin, ...), as part.vert/part.frag shade it; where
//! forms meet, each vertex takes the role of the form it lies nearest.
//! The selected form carries a gizmo (tools/gizmo.zig): `1` moves it
//! (arrows along each axis, the centre across the view), `2` turns it
//! (a ring for each of its turns), `3` sizes it (along its own axes).
//! The camera orbits the sculpt freely (middle drag, over the top and
//! under it alike; the wheel zooms); `.` eases it onto the selected form.
//! `ctrl+z` undoes (tools/history.zig), `ctrl+y` or `ctrl+shift+z` redoes:
//! a whole drag, or a whole typed name, is one step.
//! The file is watched (tools/ondisk.zig): changed on disk with nothing
//! unsaved here, it is taken (one undo step); with changes here too, it is
//! never overwritten silently: `ctrl+s` keeps the editor's, `f5` the file's.
//!
//! decision: a developer's tool, not the game: its few words and keys are
//! written here, not in the strings or controls files (the camera's orbit
//! still follows the game's binding).
/// the move, turn and size handles on the selected form
const gizmo=@import("gizmo.zig");
/// the editor's sizes, colours, words and keys
pub const settings=@import("meshedit/settings.zig");
/// the sculpt as text: its forms read from and written to a `.mesh` file
pub const doc=@import("meshedit/doc.zig");
/// the sculpt's bones: joints, parents, twins, and posing them
pub const rig=@import("meshedit/rig.zig");
/// the rig mode: the bones listed, placed and test-turned
pub const rigging=@import("meshedit/rigging.zig");
/// the editor's state: the forms, the selection, the gizmo, the camera
pub const editor=@import("meshedit/editor.zig");
/// every act a key or a button does, and the toolbar's buttons
pub const buttons=@import("meshedit/buttons.zig");
/// what the gardener's hands do to the forms: picking, dragging, saving
pub const editing=@import("meshedit/editing.zig");
/// the side panel: the selected form's fields and the shader it picks
pub const panel=@import("meshedit/panel.zig");
/// the window, the renderer and the frame loop
pub const run=@import("meshedit/run.zig");
/// the editor's tests: its text and its meshing
pub const tests=@import("meshedit/tests.zig");
/// the editor's start: opens the window and runs until it closes
pub const main=run.main;
test{
  _=gizmo;
  _=@import("orbit.zig");
  _=@import("labels.zig");
  _=@import("history.zig");
  _=@import("ondisk.zig");
  _=@import("toolbar.zig");
}
test{
  _=settings;
  _=doc;
  _=rig;
  _=rigging;
  _=editor;
  _=editing;
  _=panel;
  _=run;
  _=tests;
}
