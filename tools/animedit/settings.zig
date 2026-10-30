//! the animation editor's settings: files, timing, the camera and the panel's layout.
const engine=ps.engine;
const m=engine.core.math;
const clip=engine.anim.clip;
const Color=engine.ui.draw.Color;
const ps=@import("parasymi");
const skel=ps.skeleton;
const specimen=ps.specimen;
const s=ps.style;
const PoseCh=clip.Channels(skel.Pose);
const LookCh=clip.Channels(specimen.Look);
/// clips are kept here (from the repo root)
pub const dir="src/anim";
/// `--shot` writes here, this many frames in (the world settled)
pub const shotPath="shots/animedit.png";
pub const shotFrames=30;
pub const ext=".anim";
/// a clip's name is a plain file name: none of these
pub const notInName="/\\:.*?\"<>|";
/// a stalled frame counts as at most this long (s)
pub const maxDt:f64=0.1;
/// the playhead snaps to frames of this rate
pub const fps:f32=30;
/// a new clip runs this long (s); the length changes by `LENGTH_STEP`
/// down to `LENGTH_MIN`
pub const length:f32=2;
pub const lengthStep:f32=0.25;
pub const lengthMin:f32=0.25;
/// a drag changes a value this much per pixel (shift: `FINE` of it)
pub const dragRate:f32=0.005;
pub const fine:f32=0.2;
/// the camera looks at this height over the wolf's feet, from this far
/// and this high (rad) to start
pub const lookUp:f32=0.6;
pub const camDist:f32=3.2;
pub const camPitch:f32=m.rad(18);
/// a plant or structure is seen from this far plus `CAM_PER` a tile of its size
pub const camThing:f32=1.6;
pub const camPer:f32=2.4;
/// `.` frames a joint as a thing this big (m)
pub const jointSize:f32=0.12;
/// layout (px): the channel list, the timeline along the bottom
pub const pad:f32=16;
pub const text:f32=s.textSmall;
pub const row:f32=18;
pub const listY:f32=100;
pub const listW:f32=380;
pub const valueX:f32=270;
pub const lineH:f32=20;
pub const tlH:f32=44;
pub const tlBottom:f32=40;
pub const keyR:f32=5;
pub const selKeyR:f32=8;
/// a joint's dot, the selected one's, and how near a click picks one (px)
pub const jointR:f32=3.5;
pub const selJointR:f32=5.5;
pub const jointPick:f32=10;
/// how lit a joint's dot is
pub const jointLit:f32=0.25;
/// colours: selected, keyed, unkeyed, the playhead, keys, panels
pub const sel:Color=s.gold;
pub const keyedColor:Color=s.white;
pub const bare:Color=s.dim;
pub const head:Color=s.growth;
pub const keyDim:Color=.{190,210,190,220};
pub const joint:Color=.{190,210,190,200};
pub const panel:Color=s.panel;
pub const help=[_][]const u8{
  "space play   left/right frame (shift: key to key)   home start   pgup/pgdn length",
  "up/down channel   drag value: key it (shift fine)   k key   a key all   x unkey   r rest",
  "ctrl+s save   middle drag orbit   wheel zoom (over the list: scroll)   . focus   wolf: click a joint, drag its gizmo (shift fine)",
};
