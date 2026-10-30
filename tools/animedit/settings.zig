//! the animation editor's settings: files, timing, the camera and the panel's layout.
const engine = ps.engine;
const m = engine.core.math;
const clip = engine.anim.clip;
const Color = engine.ui.draw.Color;
const ps = @import("parasymi");
const skel = ps.skeleton;
const specimen = ps.specimen;
const s = ps.style;

const PoseCh = clip.Channels(skel.Pose);
const LookCh = clip.Channels(specimen.Look);

/// clips are kept here (from the repo root)
pub const DIR = "src/anim";
/// `--shot` writes here, this many frames in (the world settled)
pub const SHOT = "shots/animedit.png";
pub const SHOT_FRAMES = 30;
pub const EXT = ".anim";
/// a clip's name is a plain file name: none of these
pub const NOT_IN_NAME = "/\\:.*?\"<>|";
/// a stalled frame counts as at most this long (s)
pub const MAX_DT:f64 = 0.1;
/// the playhead snaps to frames of this rate
pub const FPS:f32 = 30;
/// a new clip runs this long (s); the length changes by `LENGTH_STEP`
/// down to `LENGTH_MIN`
pub const LENGTH:f32 = 2;
pub const LENGTH_STEP:f32 = 0.25;
pub const LENGTH_MIN:f32 = 0.25;
/// a drag changes a value this much per pixel (shift: `FINE` of it)
pub const DRAG_RATE:f32 = 0.005;
pub const FINE:f32 = 0.2;
/// the camera looks at this height over the wolf's feet, from this far
/// and this high (rad) to start
pub const LOOK_UP:f32 = 0.6;
pub const CAM_DIST:f32 = 3.2;
pub const CAM_PITCH:f32 = m.rad(18);
/// a plant or structure is seen from this far plus `CAM_PER` a tile of its size
pub const CAM_THING:f32 = 1.6;
pub const CAM_PER:f32 = 2.4;
/// `.` frames a joint as a thing this big (m)
pub const JOINT_SIZE:f32 = 0.12;
/// layout (px): the channel list, the timeline along the bottom
pub const PAD:f32 = 16;
pub const TEXT:f32 = s.text_small;
pub const ROW:f32 = 18;
pub const LIST_Y:f32 = 100;
pub const LIST_W:f32 = 380;
pub const VALUE_X:f32 = 270;
pub const LINE_H:f32 = 20;
pub const TL_H:f32 = 44;
pub const TL_BOTTOM:f32 = 40;
pub const KEY_R:f32 = 5;
pub const SEL_KEY_R:f32 = 8;
/// a joint's dot, the selected one's, and how near a click picks one (px)
pub const JOINT_R:f32 = 3.5;
pub const SEL_JOINT_R:f32 = 5.5;
pub const JOINT_PICK:f32 = 10;
/// how lit a joint's dot is
pub const JOINT_LIT:f32 = 0.25;
/// colours: selected, keyed, unkeyed, the playhead, keys, panels
pub const SEL:Color = s.gold;
pub const KEYED:Color = s.white;
pub const BARE:Color = s.dim;
pub const HEAD:Color = s.growth;
pub const KEY_DIM:Color = .{190, 210, 190, 220};
pub const JOINT:Color = .{190, 210, 190, 200};
pub const PANEL:Color = s.panel;

pub const HELP = [_][]const u8{
  "space play   left/right frame (shift: key to key)   home start   pgup/pgdn length",
  "up/down channel   drag value: key it (shift fine)   k key   a key all   x unkey   r rest",
  "ctrl+s save   middle drag orbit   wheel zoom (over the list: scroll)   . focus   wolf: click a joint, drag its gizmo (shift fine)",
};
