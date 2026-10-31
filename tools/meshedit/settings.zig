//! the mesh editor's settings: files, steps, the camera, the panel's layout and a form's values.
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// all the maths: vectors, angles, clamps
const m=engine.core.math;
/// clip channels, borrowed to name every value of a form
const clip=engine.anim.clip;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=engine.ui.draw.Color;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the mesh library, whose first slot the sculpt is drawn into
const meshlib=ps.meshlib;
/// the HUD's shared colours and type sizes, borrowed for the panel
const s=ps.style;
/// a part role: the shader a part of the surface is drawn with
const Part=ps.vertex.Part;
/// the editors' words for values, and typed names
const labels=@import("../labels.zig");
/// a point or size in the sculpt (m)
const V3=m.V3;
/// makes a `V3` from its three parts
const v3=m.v3;
/// meshes are kept here (from the repo root)
pub const dir="src/mesh";
/// the file ending every kept mesh carries
pub const ext=".mesh";
/// a mesh's name is a plain file name: none of these
pub const notInName="/\\:.*?\"<>|";
/// the first line of a mesh's text
pub const header="# mesh";
/// `--shot` writes its one frame here
pub const shotPath="shots/meshedit.png";
/// how many frames `--shot` waits first, so the world has settled
pub const shotFrames=30;
/// a stalled frame counts as at most this long (s)
pub const maxDt:f64=0.1;
/// the surface's cell size to start (m)
pub const cell:f32=0.01;
/// how much `[`/`]` widen or narrow the cells (m)
pub const cellStep:f32=0.0025;
/// the finest the cells may be (m)
pub const cellMin:f32=0.0025;
/// the most cells across the whole sculpt (past that they widen)
pub const maxCells:f32=256;
/// the least a form's size may be (m)
pub const sizeMin:f32=0.005;
/// while a value is dragged the surface is meshed again at most this often (s)
pub const remesh:f32=0.08;
/// and its cells this many times wider then (full detail once let go)
pub const dragCoarse:f32=2;
/// a drag changes a length this much per pixel (m)
pub const dragLen:f32=0.002;
/// a turn this much per pixel (degrees)
pub const dragDeg:f32=0.5;
/// a colour channel this much per pixel
pub const dragCol:f32=0.004;
/// and held with shift, this share of any of them, for fine work
pub const fine:f32=0.2;
/// where the gizmo's values start among a form's channels: its place
pub const pos=Ch.find("pos.x").?;
/// its turn
pub const rot=Ch.find("rot.x").?;
/// its size
pub const sizeX=Ch.find("size.x").?;
/// a new form stands this far from the one it was made from
pub const newOff=v3(0.1,0,0);
/// the camera looks at this height (m) over the sculpt's ground to start
pub const lookUp:f32=0.3;
/// from this far away (m)
pub const camDist:f32=1.6;
/// and this high over it (rad)
pub const camPitch:f32=m.rad(20);
/// the library slot the sculpt is drawn from: nothing else is drawn
pub const slotId:meshlib.Id=meshlib.ids[0];
/// no wolf: its paws' contact shadows far off any tile
pub const noFeet:f32=1e9;
/// layout (px): the gap round the panel's edges
pub const pad:f32=16;
/// the size of the panel's text
pub const text:f32=s.textSmall;
/// the height of one row of the list or the values
pub const row:f32=18;
/// how far down the window the form list starts
pub const listY:f32=100;
/// how wide the form list is
pub const listW:f32=470;
/// the most form rows shown at once
pub const listRowCount=12;
/// how far in from the list's left a value is written
pub const valueX:f32=200;
/// where a form's shape shows in its row, after its name
pub const kindX:f32=190;
/// where a form's shader shows in its row
pub const shadeX:f32=365;
/// the height of one line of the help along the top
pub const lineH:f32=20;
/// the gap between the form list and the values under it
const gap:f32=14;
/// a form's handle in view (the selected one shows its gizmo instead): its radius (px)
pub const handleR:f32=4;
/// how near (px) a click must land to pick a form's handle
pub const pickRadius:f32=14;
/// colours: the selected form and value
pub const sel:Color=s.gold;
/// a value that is set, and a form that adds
pub const plain:Color=s.white;
/// a dim note, and the help
pub const bare:Color=s.dim;
/// a form that carves
pub const carve:Color=s.growth;
/// a form that only inks the surface's colour (a soft violet)
pub const ink:Color=.{205,175,240,255};
/// a form gathered into the selected one's group, moving and turning with it
pub const grouped:Color=s.freecam;
/// `g` snaps the selected forms' places and sizes to this (m)
pub const snapLen:f32=0.005;
/// and their turns to this (degrees)
pub const snapDeg:f32=15;
/// how far a new bone's joint stands above its parent's (m)
pub const newBoneUp:f32=0.1;
/// a joint's dot in rig mode (px)
pub const jointR:f32=5;
/// `.` frames a joint as a thing this big (m)
pub const jointFocus:f32=0.12;
/// the panels behind the list and the values
pub const panel:Color=s.panel;
/// the help along the top: every key the editor answers to
pub const help=[_][]const u8{
  "n new form (from the selected)   del remove   pgup/pgdn move in the list   tab next form   enter name it   m shader (shift back)",
  "t shape (a tube curls by its curl)   c carve   i ink (colour only)   x twin   ctrl+click gather into a group   g snap   o bone   j rig",
  "up/down value   drag value (shift fine)   r value at rest   [ ] cells   click a handle: select   ctrl+s save   ctrl+z undo   ctrl+y redo",
  "gizmo: 1 move   2 turn   3 size   drag its handles (shift fine)   middle drag orbit   wheel zoom   . focus the form",
};
/// the help along the top in rig mode: every key it answers to
pub const rigHelp=[_][]const u8{
  "rig mode (j: back to the forms)   n new bone (on the selected; the first is the root)   del remove   x twin   tab next bone   enter name it",
  "up/down value   drag value (shift fine)   r test turn back to rest (shift: every bone)   click a joint: select   ctrl+s save   ctrl+z undo",
  "gizmo: 1 move the joint   2 test turn (never kept)   middle drag orbit   wheel zoom   . focus the joint   forms: o steps the bone a form rides",
};
/// the shape a form takes
pub const Kind=enum{
  /// a round body with three radii
  ellipsoid,
  /// a rounded cone from a foot to a tip
  cone,
  /// a box with rounded edges
  box,
  /// a tube from its foot up along y, curling toward x as it goes: a horn,
  /// a tail, a tendril
  tube,
};
/// the most a tube's curl is cut into segments: one for each this many
/// degrees of it (at least one, at most the sculpt's `chainMax`)
pub const curlStep:f32=12;
/// a form's numbers, every one a value the editor shows and keeps
pub const Vals=struct{
  /// where it stands (m)
  pos:V3=.{0,0.3,0},
  /// how it is turned (degrees: y, then x, then z)
  rot:V3=.{0,0,0},
  /// its radii (an ellipsoid's), foot and tip radii and half length (a
  /// cone's x, z and y), or half extents (a box's) (m)
  size:V3=.{0.15,0.15,0.15},
  /// how much a box's edges are rounded (m)
  round:f32=0.02,
  /// how far it melts into the forms before it (m); an ink form's fade
  melt:f32=0.03,
  /// how far a tube curls toward x from its foot to its tip (degrees)
  curl:f32=0,
  /// its colour, red, green and blue (0..1)
  col:V3=.{0.45,0.42,0.3},
};
/// every value of a form, each a channel the panel shows and the text keeps
pub const Ch=clip.Channels(Vals);
/// how a form's values read in the panel (a cone's size aside: `valueLabel`)
const valueLabels=labels.all(&.{
  .{.path="pos",.word="place",.axes=.{"across","up","depth"}},
  .{.path="rot",.word="turn",.axes=.{"pitch","yaw","roll"}},
  .{.path="size",.word="size",.axes=.{"width","height","depth"}},
  .{.path="round",.word="edge rounding"},
  .{.path="melt",.word="melt"},
  .{.path="curl",.word="curl (tube)"},
  .{.path="col",.word="colour",.axes=labels.colourAxes},
},&Ch.names);
/// how a cone's size reads: the radius at its foot, half its length, the radius at its tip
const coneSize=[3][]const u8{"foot radius","half length","tip radius"};
/// how a tube's size reads: the radius at its foot, its length, the radius at its tip
const tubeSize=[3][]const u8{"foot radius","length","tip radius"};
/// value `i` of a form shaped `kind`, in words
pub fn valueLabel(kind:Kind,i:usize)[]const u8{
  if(i<sizeX or i>=sizeX+3)return valueLabels[i];
  return switch(kind){
    .cone=>coneSize[i-sizeX],
    .tube=>tubeSize[i-sizeX],
    .ellipsoid,.box=>valueLabels[i],
  };
}
/// which way the shader is stepped through the roles
const Way=enum{
  /// to the next role
  on,
  /// to the one before
  back,
};
/// the shader after `p` (before it, `.back`), round the roles
pub fn nextShade(p:Part,way:Way)Part{
  // how many roles there are, and the one now
  const n=@typeInfo(Part).@"enum".fields.len;
  const i:usize=@intFromEnum(p);
  return@enumFromInt(switch(way){.on=>(i+1)%n,.back=>(i+n-1)%n});
}
/// how many form rows show (at least one, at most `listRowCount`)
pub fn listRows(n:usize)usize{return m.clamp(n,1,listRowCount);}
/// where the values start, under `rows` form rows
pub fn valuesY(rows:usize)f32{return listY+m.f(rows)*row+12+gap;}
/// whether (`x`,`y`) (px) is over the form list or the values under it
pub fn overUi(rows:usize,x:f32,y:f32)bool{
  return x<pad+listW and y>=listY-6 and y<valuesY(rows)+m.f(Ch.count)*row+6;
}
