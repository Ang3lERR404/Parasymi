//! the animation editor's panel: channels, values, the timeline and help.
const std=ps.std;
const Allocator=std.mem.Allocator;
const bufPrint=std.fmt.bufPrint;
const engine=ps.engine;
const m=engine.core.math;
const clip=engine.anim.clip;
const Draw=engine.ui.draw.Draw;
const ps=@import("parasymi");
const skel=ps.skeleton;
const specimen=ps.specimen;
const s=ps.style;
const PoseCh=clip.Channels(skel.Pose);
const LookCh=clip.Channels(specimen.Look);
const animedit=@import("../animedit.zig");
const bare=animedit.settings.bare;
const Editor=animedit.editor.Editor;
const fps=animedit.settings.fps;
const head=animedit.settings.head;
const help=animedit.settings.help;
const joint=animedit.settings.joint;
const jointLit=animedit.settings.jointLit;
const jointR=animedit.settings.jointR;
const keyedColor=animedit.settings.keyedColor;
const keyDim=animedit.settings.keyDim;
const keyR=animedit.settings.keyR;
const lineH=animedit.settings.lineH;
const listW=animedit.settings.listW;
const listY=animedit.settings.listY;
const pad=animedit.settings.pad;
const panel=animedit.settings.panel;
const row=animedit.settings.row;
const Rig=animedit.rigging.Rig;
const sel=animedit.settings.sel;
const selJointR=animedit.settings.selJointR;
const selKeyR=animedit.settings.selKeyR;
const text=animedit.settings.text;
const tlBottom=animedit.settings.tlBottom;
const tlH=animedit.settings.tlH;
const valueX=animedit.settings.valueX;
const jointOf=animedit.rigging.jointOf;
const joints=animedit.rigging.joints;
/// how many rows fit
pub fn fits(_:*const Editor,screen:[2]f32)usize{
  const h=screen[1]-listY-tlBottom-tlH-3*pad;
  return@intFromFloat(@max(1,@floor(h/row)));
}
pub fn draw(e:*const Editor,d:*Draw,screen:[2]f32,rg:*const Rig)Allocator.Error!void{
  const screenW=screen[0];
  const screenH=screen[1];
  // the wolf's joints, the selected one's gizmo over them
  if(e.wolf()){
    const cur=jointOf(e.shown[e.sel]);
    for(joints,0..)|j,i|if(cur==null or i!=cur.?){
      if(rg.view.project(m.origin(rg.bones[@intFromEnum(j.bone)])))|at|try d.pod(at[0],at[1],jointR,joint,jointLit,m.f(i));
    };
    if(e.gizmoAt(rg))|z|{
      if(rg.view.project(z.g.at))|at|try d.glow(at[0],at[1],selJointR*2,s.menuHover);
      try z.g.draw(d,rg.view,e.hot);
    }
  }
  var y:f32=pad;
  for(help)|h|{
    _=try d.text(pad,y,text,bare,h);
    y+=lineH;
  }
  var pb:[160]u8=undefined;
  _=try d.text(screenW-pad-420,pad,s.textLabel,sel,bufPrint(&pb,"{s}{s}",.{e.path,if(e.dirty)" *"else""}) catch e.path);
  if(e.noteLen>0)_=try d.text(screenW-pad-420,pad+lineH+4,text,keyedColor,e.note[0..e.noteLen]);
  // the channel list
  const rows=e.fits(screen);
  try d.trellis(pad,listY-6,listW,m.f(@min(rows,e.shown.len))*row+12,panel,0.3);
  for(0..rows)|r|{
    const i=e.top+r;
    if(i>=e.shown.len)break;
    const ry=listY+m.f(r)*row;
    const keyed=e.clip.track(e.chName(i))!=null and e.clip.track(e.chName(i)).?.keys.items.len>0;
    const col=if(i==e.sel)sel else if(keyed)keyedColor else bare;
    if(i==e.sel)try d.glow(pad+8,ry+7,10,s.menuHover);
    _=try d.text(pad+18,ry,text,col,e.chName(i));
    var vb:[24]u8=undefined;
    const vs=bufPrint(&vb,"{d:.3}",.{e.value(i)})catch"?";
    _=try d.text(pad+valueX,ry,text,col,vs);
    if(keyed and e.clip.track(e.chName(i)).?.at(e.t)!=null)try d.pod(pad+listW-14,ry+7,4,col,1,0);
  }
  if(e.top>0)_=try d.text(pad+listW-30,listY-20,text,bare,"...");
  if(e.top+rows<e.shown.len)_=try d.text(pad+listW-30,listY+m.f(rows)*row,text,bare,"...");
  // the timeline: every key dim, the selected channel's bright, the playhead
  const tx=pad;
  const tw=screenW-2*pad;
  const ty=screenH-tlBottom-tlH;
  try d.trellis(tx,ty,tw,tlH,panel,0.7);
  const at=struct{
    fn f(x0:f32,w:f32,len:f32,t:f32)f32{return x0+w*t/len;}
  }.f;
  var sec:f32=0;
  while(sec<=e.clip.length+clip.same):(sec+=0.5){
    var sb:[16]u8=undefined;
    _=try d.text(at(tx,tw,e.clip.length,sec)-4,ty+tlH+6,text,bare,bufPrint(&sb,"{d}",.{sec})catch"?");
  }
  for(e.clip.tracks.items)|tr|for(tr.keys.items)|k|{
    try d.pod(at(tx,tw,e.clip.length,k.t),ty+tlH/2,keyR,keyDim,0,0);
  };
  if(e.clip.track(e.chName(e.sel)))|tr|for(tr.keys.items)|k|{
    try d.pod(at(tx,tw,e.clip.length,k.t),ty+tlH/2,selKeyR,sel,1,0);
  };
  const hx=at(tx,tw,e.clip.length,e.t);
  try d.limb(.{hx,ty-6},.{hx,ty+tlH+2},3,2,head,0);
  var hb:[96]u8=undefined;
  _=try d.text(tx,ty-26,text,head,bufPrint(&hb,"{s} {d:.2} / {d:.2} s   frame {d}   channel {s}",.{
    if(e.playing)"playing"else"paused",e.t,e.clip.length,@as(u32,@intFromFloat(@round(e.t*fps))),e.chName(e.sel),
  })catch"?");
}
