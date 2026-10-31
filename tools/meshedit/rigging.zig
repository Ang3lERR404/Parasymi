//! the mesh editor's rig mode (`j`): the sculpt's bones listed in place of
//! its forms, each joint placed by the gizmo or its values, and turned to
//! try how the skin bends (a test pose, never kept: `r` sets it back).
/// the standard library, reached through the game's hub
const std=ps.std;
/// the allocator type a new bone may fail with
const Allocator=std.mem.Allocator;
/// formats text into a fixed buffer (rows, values)
const bufPrint=std.fmt.bufPrint;
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// all the maths: vectors, matrices
const m=engine.core.math;
/// the keys and buttons held this frame
const Input=engine.platform.input.Input;
/// a keyboard key, named as the window library names it
const Key=engine.platform.input.Key;
/// the UI's draw batch, which the bones go into
const Draw=engine.ui.draw.Draw;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the HUD's shared colours
const s=ps.style;
/// the move and turn handles on the selected joint
const gizmo=@import("../gizmo.zig");
/// the editors' typed names
const labels=@import("../labels.zig");
/// a point in the sculpt (m)
const V3=m.V3;
/// makes a `V3` from its three parts
const v3=m.v3;
/// a 4×4 matrix: a bone's turn and place
const M4=m.M4;
/// the editor's root, through which its other files are reached
const meshedit=@import("../meshedit.zig");
/// the sculpt's bones
const rig=meshedit.rig;
/// the editor's state
const Editor=meshedit.editor.Editor;
/// the dim colour, the selected one, a plain one, a twinned one
const bare=meshedit.settings.bare;
const sel=meshedit.settings.sel;
const plain=meshedit.settings.plain;
const grouped=meshedit.settings.grouped;
/// layout (px): the list's place, width, rows and columns
const listY=meshedit.settings.listY;
const listW=meshedit.settings.listW;
const pad=meshedit.settings.pad;
const row=meshedit.settings.row;
const kindX=meshedit.settings.kindX;
const valueX=meshedit.settings.valueX;
const text=meshedit.settings.text;
const panel=meshedit.settings.panel;
/// where the values start under the bone rows
const valuesY=meshedit.settings.valuesY;
/// how many rows show
const listRows=meshedit.settings.listRows;
/// how far a new bone's joint stands above its parent's (m)
const newBoneUp=meshedit.settings.newBoneUp;
/// a joint's dot and a bone's stem (px)
const jointR=meshedit.settings.jointR;
/// how many value rows rig mode shows: the joint's place, then the test turn
pub const valueRows=6;
/// the values' words in rig mode
const valueWords=[valueRows][]const u8{"joint across","joint up","joint depth","test pitch","test yaw","test roll"};
/// part `i` of `v` (a vector is read at a runtime part through an array)
fn lane(v:V3,i:usize)f32{
  // the vector as an array
  const a:[3]f32=v;
  return a[i];
}
/// `v` with part `i` set to `x`
fn put(v:V3,i:usize,x:f32)V3{
  // the vector as an array, part `i` set
  var a:[3]f32=v;
  a[i]=x;
  return a;
}
/// `v` with part `i` moved by `by`
fn bump(v:V3,i:usize,by:f32)V3{return put(v,i,lane(v,i)+by);}
/// whether key `k` went down this frame
fn hit(i:*const Input,k:Key)bool{return i.pressed(.{.key=k});}
/// the bones now: every kept bone's test turn (each twin's mirrored from
/// its bone's), posed where the sculpt stands at `origin`; `out` gets
/// each bone's matrix, the skeleton is returned
pub fn posed(e:*const Editor,origin:V3,out:*[rig.maxBones]M4)rig.Skeleton{
  // the skeleton, and each of its bones' turns
  const k=rig.skeleton(e.doc.bones.items);
  var turns:[rig.maxBones]V3=@splat(.{0,0,0});
  for(0..e.doc.bones.items.len)|i|{
    turns[i]=e.turns[i];
    if(k.twinOf[i])|t|turns[t]=v3(e.turns[i][0],-e.turns[i][1],-e.turns[i][2]);
  }
  rig.pose(&k,turns[0..k.count],v3(0,0,0),m.translate(origin),out[0..k.count]);
  return k;
}
/// the selected bone's gizmo where its joint stands now: moving it along
/// the sculpt's axes, or turning it about its parent's turned axes
pub fn gizmoAt(e:*const Editor,origin:V3)?gizmo.Gizmo{
  if(e.doc.bones.items.len==0 or e.mode==.size)return null;
  // the bones now, and the selected one
  var bones:[rig.maxBones]M4=undefined;
  const k=posed(e,origin,&bones);
  const b=e.bsel;
  // its parent's turn now (none: the sculpt's axes), and its own turns
  const up=if(k.parents[b])|p|bones[p]else m.identity;
  const t=e.turns[b];
  const ry=m.mul(up,m.rotY(m.rad(t[1])));
  const rx=m.mul(ry,m.rotX(m.rad(t[0])));
  return.{.at=rig.joint(&k,&bones,b),.mode=e.mode,.axes=switch(e.mode){
    .move=>.{v3(1,0,0),v3(0,1,0),v3(0,0,1)},
    .turn=>.{m.norm(m.mulDir(ry,v3(1,0,0))),m.norm(m.mulDir(up,v3(0,1,0))),m.norm(m.mulDir(rx,v3(0,0,1)))},
    .size=>unreachable,
  }};
}
/// a drag of the selected joint's held handle from `from` to `to` (px), `k` of it
pub fn dragGizmo(e:*Editor,g:gizmo.Gizmo,view:gizmo.View,from:[2]f32,to:[2]f32,k:f32)void{
  // the handle held, if any, and the selected bone
  const part=e.part orelse return;
  const b=&e.doc.bones.items[e.bsel];
  switch(part){
    .free=>{
      if(e.mode!=.move)return;
      b.at+=g.across(view,from,to)*m.splat3(k);
      e.changed();
    },
    .x,.y,.z=>{
      // the axis, and how far the drag carried along or about it
      const i=@intFromEnum(part);
      const by=g.along(view,i,from,to)*k;
      switch(e.mode){
        .move=>{
          b.at=bump(b.at,i,by);
          e.ch=i;
          e.changed();
        },
        .turn=>{
          e.turns[e.bsel]=bump(e.turns[e.bsel],i,by/m.rad(1));
          e.ch=3+i;
        },
        .size=>{},
      }
    },
  }
}
/// value `ch` of the selected bone (its joint's place, then its test turn)
pub fn value(e:*const Editor,ch:usize)f32{
  return if(ch<3)lane(e.doc.bones.items[e.bsel].at,ch)else lane(e.turns[e.bsel],ch-3);
}
/// value `ch` of the selected bone set to `v`
pub fn setValue(e:*Editor,ch:usize,v:f32)void{
  if(ch<3){
    e.doc.bones.items[e.bsel].at=put(e.doc.bones.items[e.bsel].at,ch,v);
    e.changed();
  }else e.turns[e.bsel]=put(e.turns[e.bsel],ch-3,v);
}
/// how much a pixel of drag changes value `ch`: a length, or degrees
pub fn rate(ch:usize)f32{return if(ch<3)meshedit.settings.dragLen else meshedit.settings.dragDeg;}
/// a new bone hung off the selected one, its joint a little above it (the
/// first, a root at the sculpt's origin carrying every form); named
/// `bone N`, the first free
pub fn add(e:*Editor)Allocator.Error!void{
  if(rig.count(e.doc.bones.items)+1>rig.maxBones)return e.say("no room for more bones",.{});
  // the bones so far, and the new one's name
  const bones=&e.doc.bones;
  var nb:[24]u8=undefined;
  var n:usize=bones.items.len+1;
  while(e.doc.boneNamed(bufPrint(&nb,"bone {d}",.{n}) catch unreachable)!=null)n+=1;
  const name=bufPrint(&nb,"bone {d}",.{n}) catch unreachable;
  if(bones.items.len==0){
    try bones.append(e.gpa,.{.name=.of("root")});
    for(e.pieces())|*p|p.bone=0;
  }else{
    // the parent: the selected bone
    const p=bones.items[e.bsel];
    try bones.append(e.gpa,.{.name=.of(name),.parent=@intCast(e.bsel),.at=p.at+v3(0,newBoneUp,0),.twin=p.twin});
  }
  e.bsel=bones.items.len-1;
  e.turns[e.bsel]=.{0,0,0};
  e.changed();
}
/// the selected bone taken out: its children hang off its parent, its
/// forms ride its parent; the root goes only when it is the last bone
pub fn remove(e:*Editor)void{
  // the bones, the one going and what it hangs from
  const bones=&e.doc.bones;
  const gone=e.bsel;
  const up=bones.items[gone].parent;
  if(up==null and bones.items.len>1)return e.say("the root goes last",.{});
  _=bones.orderedRemove(gone);
  // each index past the one gone moves down one
  const down=struct{
    /// index `i` once bone `gone` is out (its own index becomes `to`)
    fn f(i:u8,g:usize,to:u8)u8{return if(i==g)to else if(i>g)i-1 else i;}
  }.f;
  // where what hung from the bone gone now hangs
  const to:u8=if(up)|u|down(u,gone,0)else 0;
  for(bones.items)|*b|if(b.parent)|p|{b.parent=down(p,gone,to);};
  for(e.pieces())|*p|p.bone=if(bones.items.len==0)0 else down(p.bone,gone,to);
  for(gone..rig.maxBones-1)|i|e.turns[i]=e.turns[i+1];
  e.bsel=@min(e.bsel,bones.items.len-|1);
  e.changed();
}
/// one frame's keys in rig mode: bones made, removed, twinned, named,
/// stepped through; values stepped and set back; the gizmo's mode
pub fn keys(e:*Editor,in:*const Input)Allocator.Error!void{
  // whether shift is held (every bone's test turn set back)
  const shift=in.down(.{.key=.left_shift}) or in.down(.{.key=.right_shift});
  if(hit(in,.n))try add(e);
  // the bones kept
  const n=e.doc.bones.items.len;
  if(n==0)return;
  if(hit(in,.delete))remove(e);
  if(e.doc.bones.items.len==0)return;
  if(hit(in,.x)){
    e.doc.bones.items[e.bsel].twin=!e.doc.bones.items[e.bsel].twin;
    if(rig.count(e.doc.bones.items)>rig.maxBones){
      e.doc.bones.items[e.bsel].twin=false;
      e.say("no room for a twin",.{});
    }else e.changed();
  }
  if(hit(in,.tab))e.bsel=(e.bsel+1)%e.doc.bones.items.len;
  if(hit(in,.up) and e.ch>0)e.ch-=1;
  if(hit(in,.down) and e.ch+1<valueRows)e.ch+=1;
  if(hit(in,.r)){
    if(shift)e.turns=@splat(.{0,0,0})else e.turns[e.bsel]=.{0,0,0};
  }
  if(hit(in,.period))e.focus=true;
  if(hit(in,.enter) or hit(in,.kp_enter))e.naming=labels.typing(e.doc.bones.items[e.bsel].name.slice());
  if(hit(in,.one))e.mode=.move;
  if(hit(in,.two))e.mode=.turn;
}
/// the selected bone's name typed as `typed`: kept only while it is
/// neither empty nor another bone's
pub fn rename(e:*Editor,typed:[]const u8)void{
  if(typed.len==0)return;
  if(e.doc.boneNamed(typed))|i|if(i!=e.bsel)return;
  e.doc.bones.items[e.bsel].name=.of(typed);
  e.dirty=true;
}
/// the form `p` rides, stepped on to the next bone (`back`: the one before)
pub fn stepBone(e:*Editor,back:bool)void{
  // how many bones there are
  const n=e.doc.bones.items.len;
  if(n==0)return e.say("no bones yet: j, then n makes the root",.{});
  // the selected form
  const p=&e.pieces()[e.sel];
  p.bone=@intCast(if(back)(p.bone+n-1)%n else(p.bone+1)%n);
  e.changed();
  e.say("on {s}",.{e.doc.bones.items[p.bone].name.slice()});
}
/// the bone list, the selected bone's values, and every joint and bone of
/// the skeleton where it stands, over the scene
pub fn draw(e:*Editor,d:*Draw,view:gizmo.View,origin:V3)Allocator.Error!void{
  // the bones, and how many rows show
  const bones=e.doc.bones.items;
  const rows=listRows(bones.len);
  try d.trellis(pad,listY-6,listW,m.f(rows)*row+12,panel,0.3);
  if(bones.len==0)_=try d.text(pad+18,listY,text,bare,"no bones: n makes the root");
  for(bones,0..)|b,i|{
    if(i>=rows)break;
    // this row (px), its colour, and whether its name is being typed
    const ry=listY+m.f(i)*row;
    const col=if(i==e.bsel)sel else if(b.twin)grouped else plain;
    const typing=i==e.bsel and e.naming!=null;
    if(i==e.bsel)try d.glow(pad+8,ry+7,10,s.menuHover);
    // its number, its name, then what it hangs from and its twin, dim
    var nb:[8]u8=undefined;
    const nx=try d.text(pad+18,ry,text,col,bufPrint(&nb,"{d}  ",.{i+1})catch"?");
    if(typing)try labels.drawTyped(d,nx,ry,&e.naming.?)else _=try d.text(nx,ry,text,col,b.name.slice());
    var pb:[48]u8=undefined;
    _=try d.text(pad+kindX,ry,text,bare,bufPrint(&pb,"{s}{s}{s}",.{if(b.parent!=null)"on "else"root",if(b.parent)|p|bones[p].name.slice()else"",if(b.twin)"  twin"else""})catch"?");
  }
  // the selected bone's values
  const vy=valuesY(rows);
  if(bones.len>0){
    try d.trellis(pad,vy-6,listW,m.f(valueRows)*row+12,panel,0.6);
    for(0..valueRows)|i|{
      // this value's row (px), and its colour
      const ry=vy+m.f(i)*row;
      const col=if(i==e.ch)sel else if(i>=3)bare else plain;
      if(i==e.ch)try d.glow(pad+8,ry+7,10,s.menuHover);
      _=try d.text(pad+18,ry,text,col,valueWords[i]);
      var vb:[24]u8=undefined;
      _=try d.text(pad+valueX,ry,text,col,bufPrint(&vb,"{d:.3}",.{value(e,i)})catch"?");
    }
  }
  // the skeleton where it stands: a stem from each joint to its parent's, a dot at each
  var posedBones:[rig.maxBones]M4=undefined;
  const k=posed(e,origin,&posedBones);
  if(bones.len==0)return;
  for(0..k.count)|i|{
    // this joint on screen, and whether it is the selected bone's (or its twin's)
    const at=view.project(rig.joint(&k,&posedBones,i)) orelse continue;
    const chosen=i==e.bsel or (k.twinOf[e.bsel]!=null and k.twinOf[e.bsel].?==i);
    if(k.parents[i])|p|if(view.project(rig.joint(&k,&posedBones,p)))|pa|try d.limb(pa,at,jointR*0.9,jointR*0.4,if(chosen)sel else bare,m.f(i));
    if(i!=e.bsel)try d.pod(at[0],at[1],jointR,if(chosen)sel else if(i>=bones.len)grouped else plain,1,m.f(i));
  }
}
/// each joint where it stands on screen (null behind the eye), for picking
pub fn handles(e:*const Editor,view:gizmo.View,origin:V3,out:*std.ArrayList(?[2]f32),gpa:Allocator)Allocator.Error!void{
  // the bones now
  var bones:[rig.maxBones]M4=undefined;
  const k=posed(e,origin,&bones);
  for(0..e.doc.bones.items.len)|i|try out.append(gpa,view.project(rig.joint(&k,&bones,i)));
}
