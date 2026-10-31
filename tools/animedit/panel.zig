//! the animation editor's panel: channels, values, the timeline and help.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the allocator type drawing may fail with
const Allocator=std.mem.Allocator;
/// formats text into a fixed buffer (values, times, the path)
const bufPrint=std.fmt.bufPrint;
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// all the maths: casts, rounding, projecting
const m=engine.core.math;
/// keyframed clips: channels, keys and sampling
const clip=engine.anim.clip;
/// the UI's draw batch, which the panel goes into
const Draw=engine.ui.draw.Draw;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the wolf's skeleton and its `Pose`
const skel=ps.skeleton;
/// one plant or structure standing alone, and its `Look`
const specimen=ps.specimen;
/// the HUD's shared colours and type sizes
const s=ps.style;
/// every f32 of the wolf's `Pose`, each a channel a clip can key
const PoseCh=clip.Channels(skel.Pose);
/// every f32 of a specimen's `Look`, each a channel a clip can key
const LookCh=clip.Channels(specimen.Look);
/// the editor's root, through which its other files are reached
const animedit=@import("../animedit.zig");
/// the colour of a channel with no keys, and of the help
const bare=animedit.settings.bare;
/// the editor's state
const Editor=animedit.editor.Editor;
/// the frame rate the playhead counts frames by
const fps=animedit.settings.fps;
/// the playhead's colour
const head=animedit.settings.head;
/// the toolbar, and the backed text the path, the note and the help are written on
const toolbar=@import("../toolbar.zig");
/// every act, the toolbar's buttons, and the help
const buttons=animedit.buttons;
/// the help, as backed lines
const helpLines=toolbar.lines(&buttons.help);
/// how far down a row its glow sits (px), level with its words
const glowY=animedit.settings.glowY;
/// a joint's dot colour
const joint=animedit.settings.joint;
/// how lit a joint's dot is
const jointLit=animedit.settings.jointLit;
/// a joint's dot radius (px)
const jointR=animedit.settings.jointR;
/// the colour of a channel that has keys, and of the note
const keyedColor=animedit.settings.keyedColor;
/// a key's dot colour on the timeline
const keyDim=animedit.settings.keyDim;
/// a key's dot radius (px)
const keyR=animedit.settings.keyR;
/// how wide the channel list is (px)
const listW=animedit.settings.listW;
/// how far down the window the channel list starts (px)
const listY=animedit.settings.listY;
/// the gap round the panel's edges (px)
const pad=animedit.settings.pad;
/// the panels' colour
const panel=animedit.settings.panel;
/// the height of one channel's row (px)
const row=animedit.settings.row;
/// what the gizmo needs of the wolf this frame
const Rig=animedit.rigging.Rig;
/// the selected colour
const sel=animedit.settings.sel;
/// the selected joint's dot radius (px)
const selJointR=animedit.settings.selJointR;
/// the selected key's dot radius (px)
const selKeyR=animedit.settings.selKeyR;
/// the panel's text size
const text=animedit.settings.text;
/// how far above the window's bottom the timeline sits (px)
const tlBottom=animedit.settings.tlBottom;
/// the timeline's height (px)
const tlH=animedit.settings.tlH;
/// how far in from the list's left a value is written (px)
const valueX=animedit.settings.valueX;
/// a mark's stem up the timeline
const markStem=animedit.settings.markStem;
/// a mark's bud and its name
const markBud=animedit.settings.markBud;
/// a name as it is typed, its caret in it
const typed=@import("../labels.zig").drawTyped;
/// the joint a pose channel belongs to
const jointOf=animedit.rigging.jointOf;
/// every joint a gizmo turns
const joints=animedit.rigging.joints;
/// how many rows of the channel list fit between the help and the timeline
/// (at least one)
pub fn fits(_:*const Editor,screen:[2]f32)usize{
  // the height the list may fill (px)
  const h=screen[1]-listY-tlBottom-tlH-3*pad;
  return@intFromFloat(@max(1,@floor(h/row)));
}
/// draws the editor over the scene: the wolf's joints and the selected
/// one's gizmo, the clip's path and note, the toolbar and the help, the
/// channel list with each value, and the timeline with its keys and playhead
pub fn draw(e:*Editor,d:*Draw,screen:[2]f32,rg:*const Rig)Allocator.Error!void{
  // the window's width and height (px)
  const screenW=screen[0];
  const screenH=screen[1];
  // the wolf's joints, the selected one's gizmo over them
  if(e.wolf()){
    // the selected joint
    const cur=jointOf(e.shown[e.sel]);
    for(joints,0..)|j,i|if(cur==null or i!=cur.?){
      if(rg.view.project(m.origin(rg.bones[@intFromEnum(j.bone)])))|at|try d.pod(at[0],at[1],jointR,joint,jointLit,m.f(i));
    };
    if(e.gizmoAt(rg))|z|{
      if(rg.view.project(z.g.at))|at|try d.glow(at[0],at[1],selJointR*2,s.menuHover);
      try z.g.draw(d,rg.view,e.hot);
    }
  }
  // a buffer for the clip's path, starred when unsaved
  var pb:[160]u8=undefined;
  _=try toolbar.backed(d,pad,pad,&.{
    .{.words=bufPrint(&pb,"{s}{s}",.{e.path,if(e.dirty)" *"else""}) catch e.path,.col=sel},
    .{.words=e.note[0..e.noteLen],.col=s.dim},
  });
  // the toolbar, and the help beside the list
  e.bar.lay(buttons.all(),screen,animedit.settings.barBottom(screen));
  try e.bar.draw(d,buttons.lit(e),buttons.live(e));
  if(e.helpShown)_=try toolbar.backed(d,pad+listW+3*pad,pad,&helpLines);
  // the channel list
  // how many rows of the list fit
  const rows=e.fits(screen);
  try d.trellis(pad,listY-6,listW,m.f(@min(rows,e.shown.len))*row+12,panel,0.3);
  for(0..rows)|r|{
    // this row's channel, and where it sits (px)
    const i=e.top+r;
    if(i>=e.shown.len)break;
    const ry=listY+m.f(r)*row;
    // whether the channel has keys, and the colour it is written in
    const keyed=e.clip.track(e.chName(i))!=null and e.clip.track(e.chName(i)).?.keys.items.len>0;
    const col=if(i==e.sel)sel else if(keyed)keyedColor else bare;
    if(i==e.sel)try d.glow(pad+8,ry+glowY,12,s.menuHover);
    _=try d.text(pad+18,ry,text,col,e.chLabel(i));
    // the channel's value, written to three places
    var vb:[24]u8=undefined;
    const vs=bufPrint(&vb,"{d:.3}",.{e.value(i)})catch"?";
    _=try d.text(pad+valueX,ry,text,col,vs);
    if(keyed and e.clip.track(e.chName(i)).?.at(e.t)!=null)try d.pod(pad+listW-14,ry+glowY,4,col,1,0);
  }
  if(e.top>0)_=try d.text(pad+listW-30,listY-20,text,bare,"...");
  if(e.top+rows<e.shown.len)_=try d.text(pad+listW-30,listY+m.f(rows)*row,text,bare,"...");
  // the timeline: every key dim, the selected channel's bright, the playhead
  // the timeline's left, width and top (px)
  const tx=pad;
  const tw=screenW-2*pad;
  const ty=screenH-tlBottom-tlH;
  try d.trellis(tx,ty,tw,tlH,panel,0.7);
  // where time `t` falls along the timeline (px)
  const at=struct{
    /// where time `t` of a clip `len` long falls along a timeline `w` wide from `x0`
    fn f(x0:f32,w:f32,len:f32,t:f32)f32{return x0+w*t/len;}
  }.f;
  // each half second along the timeline is marked with its time
  var sec:f32=0;
  while(sec<=e.clip.length+clip.same):(sec+=0.5){
    // the mark's text
    var sb:[16]u8=undefined;
    _=try d.text(at(tx,tw,e.clip.length,sec)-4,ty+tlH+6,text,keyedColor,bufPrint(&sb,"{d}",.{sec})catch"?");
  }
  for(e.clip.tracks.items)|tr|for(tr.keys.items)|k|{
    try d.pod(at(tx,tw,e.clip.length,k.t),ty+tlH/2,keyR,keyDim,0,0);
  };
  if(e.clip.track(e.chName(e.sel)))|tr|for(tr.keys.items)|k|{
    try d.pod(at(tx,tw,e.clip.length,k.t),ty+tlH/2,selKeyR,sel,1,0);
  };
  // each mark: a young stem up the timeline, a bud on top, its name beside
  for(e.clip.marks.items)|mk|{
    // where the mark stands (px), and whether its name is being typed
    const mx=at(tx,tw,e.clip.length,mk.t);
    const typing=e.naming!=null and @abs(e.namingAt-mk.t)<clip.same;
    try d.limb(.{mx,ty+tlH},.{mx,ty+2},2,1.2,markStem,mk.t);
    try d.pod(mx,ty+2,3.5,markBud,0.6,mk.t);
    if(typing)try typed(d,mx+6,ty+3,&e.naming.?)
    else _=try d.text(mx+6,ty+3,text,markBud,mk.name);
  }
  // where the playhead stands (px)
  const hx=at(tx,tw,e.clip.length,e.t);
  try d.limb(.{hx,ty-6},.{hx,ty+tlH+2},3,2,head,0);
  // the playhead's caption: playing or paused, the time, the frame, the
  // channel, its key's ease if it is keyed here, and the mark it stands on
  var hb:[200]u8=undefined;
  // the selected channel's key at the playhead, if it has one
  const here=e.clip.keyAt(e.chName(e.sel),e.t);
  _=try toolbar.backed(d,tx,ty-34,&.{.{.col=head,.words=bufPrint(&hb,"{s} {d:.2} / {d:.2} s   frame {d}   channel {s}{s}{s}{s}{s}",.{
    if(e.playing)"playing"else"paused",e.t,e.clip.length,@as(u32,@intFromFloat(@round(e.t*fps))),e.chLabel(e.sel),
    if(here!=null)"   ease "else"",if(here)|k|@tagName(k.ease)else"",
    if(e.markHere()!=null)"   mark "else"",e.markHere() orelse "",
  })catch"?"}});
}
