//! the mesh editor's settings: files, steps, the camera, the panel's layout and a form's values.
const engine=ps.engine;
const m=engine.core.math;
const clip=engine.anim.clip;
const Color=engine.ui.draw.Color;
const ps=@import("parasymi");
const meshlib=ps.meshlib;
const s=ps.style;
const Part=ps.vertex.Part;
const V3=m.V3;
const v3=m.v3;
/// meshes are kept here (from the repo root)
pub const dir="src/mesh";
pub const ext=".mesh";
/// a mesh's name is a plain file name: none of these
pub const notInName="/\\:.*?\"<>|";
/// the first line of a mesh's text
pub const header="# mesh";
/// `--shot` writes here, this many frames in (the world settled)
pub const shotPath="shots/meshedit.png";
pub const shotFrames=30;
/// a stalled frame counts as at most this long (s)
pub const maxDt:f64=0.1;
/// the surface's cells (m): to start, the step `[`/`]` take, the least,
/// and the most cells across the whole sculpt (past that they widen)
pub const cell:f32=0.01;
pub const cellStep:f32=0.0025;
pub const cellMin:f32=0.0025;
pub const maxCells:f32=256;
/// the least a form's size may be (m)
pub const sizeMin:f32=0.005;
/// while a value is dragged the surface is meshed again at most this often
/// (s), its cells this many times wider (full detail once it is let go)
pub const remesh:f32=0.08;
pub const dragCoarse:f32=2;
/// a drag changes a length this much per pixel, a turn (degrees) and a
/// colour these (shift: `FINE` of it)
pub const dragLen:f32=0.002;
pub const dragDeg:f32=0.5;
pub const dragCol:f32=0.004;
pub const fine:f32=0.2;
/// where the gizmo's values start among a form's channels
pub const pos=Ch.find("pos.x").?;
pub const rot=Ch.find("rot.x").?;
pub const sizeTiles=Ch.find("size.x").?;
/// a new form stands this far from the one it was made from
pub const newOff=v3(0.1,0,0);
/// the camera looks at this height over the sculpt's ground, from this far
/// and this high (rad) to start
pub const lookUp:f32=0.3;
pub const camDist:f32=1.6;
pub const camPitch:f32=m.rad(20);
/// the library slot the sculpt is drawn from: nothing else is drawn
pub const slotId:meshlib.Id=meshlib.ids[0];
/// no wolf: its paws' contact shadows far off any tile
pub const noFeet:f32=1e9;
/// layout (px): the form list, the selected form's values under it
pub const pad:f32=16;
pub const text:f32=s.textSmall;
pub const row:f32=18;
pub const listY:f32=100;
pub const listW:f32=300;
pub const listRowCount=12;
pub const valueX:f32=150;
/// where a form's shader shows in its row
pub const shadeX:f32=190;
pub const lineH:f32=20;
const gap:f32=14;
/// a form's handle in view (the selected one shows its gizmo instead): its
/// radius, and how near a click picks it (px)
pub const handleR:f32=4;
pub const pickRadius:f32=14;
/// colours: selected, set, dim, carving, panels
pub const sel:Color=s.gold;
pub const plain:Color=s.white;
pub const bare:Color=s.dim;
pub const carve:Color=s.growth;
pub const panel:Color=s.panel;
pub const help=[_][]const u8{
  "n new form (from the selected)   del remove   pgup/pgdn move in the list   t shape   c carve   m shader (shift back)   tab next form",
  "up/down value   drag value (shift fine)   r value at rest   [ ] cells   click a handle: select   ctrl+s save",
  "gizmo: 1 move   2 turn   3 size   drag its handles (shift fine)   middle drag orbit   wheel zoom   . focus the form",
};
pub const Kind=enum{ellipsoid,cone,box};
/// a form's numbers, every one a value the editor shows and keeps
pub const Vals=struct{
  pos:V3=.{0,0.3,0},
  rot:V3=.{0,0,0},
  size:V3=.{0.15,0.15,0.15},
  round:f32=0.02,
  melt:f32=0.03,
  col:V3=.{0.45,0.42,0.3},
};
pub const Ch=clip.Channels(Vals);
const Way=enum{on,back};
/// the shader after `p` (before it, `.back`), round the roles
pub fn nextShade(p:Part,way:Way)Part{
  const n=@typeInfo(Part).@"enum".fields.len;
  const i:usize=@intFromEnum(p);
  return@enumFromInt(switch(way){.on=>(i+1)%n,.back=>(i+n-1)%n});
}
/// how many form rows show (at least one, at most `LIST_ROWS`)
pub fn listRows(n:usize)usize{return m.clamp(n,1,listRowCount);}
/// where the values start, under `rows` form rows
pub fn valuesY(rows:usize)f32{return listY+m.f(rows)*row+12+gap;}
pub fn overUi(rows:usize,x:f32,y:f32)bool{
  return x<pad+listW and y>=listY-6 and y<valuesY(rows)+m.f(Ch.count)*row+6;
}
