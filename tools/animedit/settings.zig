//! the animation editor's settings: files, timing, the camera and the panel's layout.
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// all the maths: vectors, angles, easing
const m=engine.core.math;
/// keyframed clips: channels, keys and sampling
const clip=engine.anim.clip;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=engine.ui.draw.Color;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the wolf's skeleton and its `Pose`
const skel=ps.skeleton;
/// one plant or structure standing alone, and its `Look`
const specimen=ps.specimen;
/// the HUD's shared colours and type sizes, borrowed for the panel
const s=ps.style;
/// every f32 of the wolf's `Pose`, each a channel a clip can key
const PoseCh=clip.Channels(skel.Pose);
/// every f32 of a specimen's `Look`, each a channel a clip can key
const LookCh=clip.Channels(specimen.Look);
/// the editors' words for values, and typed names
const labels=@import("../labels.zig");
/// each pose channel in words (`right shoulder lean`)
pub const poseLabels=labels.all(labels.poseRules,&PoseCh.names);
/// each look channel in words (`sap flow`)
pub const lookLabels=labels.all(&labels.lookRules,&LookCh.names);
/// clips are kept here (from the repo root)
pub const dir="src/anim";
/// `--shot` writes its one frame here
pub const shotPath="shots/animedit.png";
/// how many frames `--shot` waits first, so the world has settled
pub const shotFrames=30;
/// the file ending every kept clip carries
pub const ext=".anim";
/// a clip's name is a plain file name: none of these
pub const notInName="/\\:.*?\"<>|";
/// a stalled frame counts as at most this long (s)
pub const maxDt:f64=0.1;
/// the playhead snaps to frames of this rate
pub const fps:f32=30;
/// a new clip runs this long (s)
pub const length:f32=2;
/// how much `pgup`/`pgdn` lengthen or shorten a clip (s)
pub const lengthStep:f32=0.25;
/// the shortest a clip may be (s)
pub const lengthMin:f32=0.25;
/// a drag changes a value this much per pixel
pub const dragRate:f32=0.005;
/// and held with shift, this share of that, for fine work
pub const fine:f32=0.2;
/// the camera looks at this height (m) over the wolf's feet to start
pub const lookUp:f32=0.6;
/// from this far away (m)
pub const camDist:f32=3.2;
/// and this high over it (rad)
pub const camPitch:f32=m.rad(18);
/// a plant or structure is seen from this far (m), plus `camPer` a tile of its size
pub const camThing:f32=1.6;
/// how much farther (m) the camera stands for each tile of the thing's size
pub const camPer:f32=2.4;
/// `.` frames a joint as a thing this big (m)
pub const jointSize:f32=0.12;
/// layout (px): the gap round the panel's edges
pub const pad:f32=16;
/// the size of the panel's text
pub const text:f32=s.textSub;
/// how far down a row its glow sits, level with its words
pub const glowY:f32=5;
/// the height of one channel's row in the list
pub const row:f32=22;
/// how far down the window the channel list starts
pub const listY:f32=80;
/// how wide the channel list is
pub const listW:f32=470;
/// how far in from the list's left a channel's value is written
pub const valueX:f32=340;
/// the timeline's height along the bottom
pub const tlH:f32=44;
/// how far above the window's bottom the timeline sits
pub const tlBottom:f32=40;
/// the radius of a key's dot on the timeline
pub const keyR:f32=5;
/// the radius of the selected key's dot
pub const selKeyR:f32=8;
/// the radius of a joint's dot on the skeleton (px)
pub const jointR:f32=3.5;
/// the radius of the selected joint's dot (px)
pub const selJointR:f32=5.5;
/// how near (px) a click must land to pick a joint
pub const jointPick:f32=10;
/// how lit a joint's dot is
pub const jointLit:f32=0.25;
/// colours: the selected channel, joint and key
pub const sel:Color=s.gold;
/// a channel that has keys
pub const keyedColor:Color=s.white;
/// a channel with none
pub const bare:Color=s.dim;
/// the playhead on the timeline
pub const head:Color=s.growth;
/// a key's dot on the timeline
pub const keyDim:Color=.{190,210,190,220};
/// a joint's dot on the skeleton
pub const joint:Color=.{190,210,190,200};
/// the panels behind the list and the timeline
pub const panel:Color=s.panel;
/// a mark's stem up the timeline
pub const markStem:Color=s.barkYoung;
/// a mark's bud and its name
pub const markBud:Color=s.bud;
/// where the toolbar must end, above the timeline and the playhead's caption (px)
pub fn barBottom(screen:m.Vice(f32,2))f32{return screen[1]-tlBottom-tlH-36;}
