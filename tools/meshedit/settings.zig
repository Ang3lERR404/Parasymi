//! the mesh editor's settings: files, steps, the camera, the panel's layout and a form's values.
const engine = ps.engine;
const m = engine.core.math;
const clip = engine.anim.clip;
const Color = engine.ui.draw.Color;
const ps = @import("parasymi");
const meshlib = ps.meshlib;
const s = ps.style;
const Part = ps.vertex.Part;

const V3 = m.V3;
const v3 = m.v3;

/// meshes are kept here (from the repo root)
pub const DIR = "src/mesh";
pub const EXT = ".mesh";
/// a mesh's name is a plain file name: none of these
pub const NOT_IN_NAME = "/\\:.*?\"<>|";
/// the first line of a mesh's text
pub const HEADER = "# mesh";
/// `--shot` writes here, this many frames in (the world settled)
pub const SHOT = "shots/meshedit.png";
pub const SHOT_FRAMES = 30;
/// a stalled frame counts as at most this long (s)
pub const MAX_DT:f64 = 0.1;
/// the surface's cells (m): to start, the step `[`/`]` take, the least,
/// and the most cells across the whole sculpt (past that they widen)
pub const CELL:f32 = 0.01;
pub const CELL_STEP:f32 = 0.0025;
pub const CELL_MIN:f32 = 0.0025;
pub const MAX_CELLS:f32 = 256;
/// the least a form's size may be (m)
pub const SIZE_MIN:f32 = 0.005;
/// while a value is dragged the surface is meshed again at most this often
/// (s), its cells this many times wider (full detail once it is let go)
pub const REMESH:f32 = 0.08;
pub const DRAG_COARSE:f32 = 2;
/// a drag changes a length this much per pixel, a turn (degrees) and a
/// colour these (shift: `FINE` of it)
pub const DRAG_LEN:f32 = 0.002;
pub const DRAG_DEG:f32 = 0.5;
pub const DRAG_COL:f32 = 0.004;
pub const FINE:f32 = 0.2;
/// where the gizmo's values start among a form's channels
pub const POS = Ch.find("pos.x").?;
pub const ROT = Ch.find("rot.x").?;
pub const SIZE = Ch.find("size.x").?;
/// a new form stands this far from the one it was made from
pub const NEW_OFF = v3(0.1, 0, 0);
/// the camera looks at this height over the sculpt's ground, from this far
/// and this high (rad) to start
pub const LOOK_UP:f32 = 0.3;
pub const CAM_DIST:f32 = 1.6;
pub const CAM_PITCH:f32 = m.rad(20);
/// the library slot the sculpt is drawn from: nothing else is drawn
pub const SLOT_ID:meshlib.Id = meshlib.ids[0];
/// no wolf: its paws' contact shadows far off any tile
pub const NO_FEET:f32 = 1e9;
/// layout (px): the form list, the selected form's values under it
pub const PAD:f32 = 16;
pub const TEXT:f32 = s.text_small;
pub const ROW:f32 = 18;
pub const LIST_Y:f32 = 100;
pub const LIST_W:f32 = 300;
pub const LIST_ROWS = 12;
pub const VALUE_X:f32 = 150;
/// where a form's shader shows in its row
pub const SHADE_X:f32 = 190;
pub const LINE_H:f32 = 20;
const GAP:f32 = 14;
/// a form's handle in view (the selected one shows its gizmo instead): its
/// radius, and how near a click picks it (px)
pub const HANDLE_R:f32 = 4;
pub const PICK:f32 = 14;
/// colours: selected, set, dim, carving, panels
pub const SEL:Color = s.gold;
pub const PLAIN:Color = s.white;
pub const BARE:Color = s.dim;
pub const CARVE:Color = s.growth;
pub const PANEL:Color = s.panel;

pub const HELP = [_][]const u8{
  "n new form (from the selected)   del remove   pgup/pgdn move in the list   t shape   c carve   m shader (shift back)   tab next form",
  "up/down value   drag value (shift fine)   r value at rest   [ ] cells   click a handle: select   ctrl+s save",
  "gizmo: 1 move   2 turn   3 size   drag its handles (shift fine)   middle drag orbit   wheel zoom   . focus the form",
};

pub const Kind = enum { ellipsoid, cone, box };

/// a form's numbers, every one a value the editor shows and keeps
pub const Vals = struct {
  pos:V3 = .{ 0, 0.3, 0 },
  rot:V3 = .{ 0, 0, 0 },
  size:V3 = .{ 0.15, 0.15, 0.15 },
  round:f32 = 0.02,
  melt:f32 = 0.03,
  col:V3 = .{ 0.45, 0.42, 0.3 },
};
pub const Ch = clip.Channels(Vals);

const Way = enum { on, back };

/// the shader after `p` (before it, `.back`), round the roles
pub fn nextShade(p:Part, way:Way) Part {
  const n = @typeInfo(Part).@"enum".fields.len;
  const i:usize = @intFromEnum(p);
  return @enumFromInt(switch (way) { .on => (i + 1) % n, .back => (i + n - 1) % n });
}

/// how many form rows show (at least one, at most `LIST_ROWS`)
pub fn listRows(n:usize) usize { return m.clamp(n, 1, LIST_ROWS); }
/// where the values start, under `rows` form rows
pub fn valuesY(rows:usize) f32 { return LIST_Y + m.f(rows) * ROW + 12 + GAP; }

pub fn overUi(rows:usize, x:f32, y:f32) bool {
  return x < PAD + LIST_W and y >= LIST_Y - 6 and y < valuesY(rows) + m.f(Ch.count) * ROW + 6;
}
