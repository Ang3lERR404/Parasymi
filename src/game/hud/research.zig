//! the research tree (T) as a living sapling growing out of the soil.
//! Leaves are small studies; branches are big ones (`Research.branch`: new
//! structures, species, an event). Nothing is placed by hand: the shape
//! follows from the prerequisites alone, so a new technology needs no layout.
//!   - host: a node grows on the nearest branch up its first-prerequisite
//!     chain, else on the trunk.
//!   - a host's children sit one slot apart along it, by depth (longest
//!     prerequisite chain, a discovery counts one), then declaration order;
//!     leaves and branches each alternate sides. A stem is one slot longer
//!     than it has children, and bends toward the light.
//!   - the fully grown tree is fitted to the panel, so nothing ever moves:
//!     the sapling starts small at the soil and fills the panel as it grows.
//! Known: grown (a leaf, or a branch with a violet bloom at its tip). Open:
//! a gold bud (a shoot growing with progress while studied). Locked: a dim
//! dormant bud where its host has grown; beyond that, nothing yet. The trunk
//! reaches just past the highest open or known node and thickens with all
//! that is known. Hover a node for its card below; click it to study it.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const indexOfScalar=std.mem.indexOfScalar;
const testing=std.testing;
const play=lib.play;
const prog=lib.progression;
const Draw=lib.engine.ui.draw.Draw;
const Color=lib.engine.ui.draw.Color;
const s=lib.style;
const txt=lib.txt;
const m=lib.engine.core.math;
const color=lib.engine.core.color;
const hud=lib.hud;
const Input=lib.engine.platform.input.Input;
const Id=prog.Id;
const V3=m.V3;
const nodeCount=prog.tree.values.len;
const pw:f32=600;
const margin:f32=24;
const maxH:f32=900;
const headerH:f32=84;
const cardH:f32=132;
const treePad:f32=36;
const tendrilW:f32=150;
const tendrilH=s.barH;
/// a slot never draws larger than this many pixels, however few nodes
const maxSlot:f32=80;
/// hit area around a node, at least this many pixels across
const minHit:f32=26;
// ---- the shape, in slots (one slot = the spacing between nodes on a stem) ----
const seg=10;
const upAxis:f32=m.halfPi;
/// angles off the host's heading
const branchAngle=m.rad(60);
const twigAngle=m.rad(40);
const leafAngle=m.rad(56);
/// how far toward straight up a stem turns over its length
const bendAmount:f32=0.4;
/// a branch is at least this long, so even a bare one reaches out
const branchMin:f32=2.5;
const petiole:f32=0.16;
const leafLen:f32=0.7;
const leafW:f32=0.34;
const budLen:f32=0.3;
const budW:f32=0.2;
/// a branch's closed bud is this much larger than a leaf's
const branchBud:f32=1.4;
const bloomR:f32=0.13;
/// the trunk reaches this far past its highest open or known node
const trunkLead:f32=0.55;
const trunkEase:f32=1.5;
/// trunk radius: a seedling's, and how it thickens with what is known (sqrt)
const trunkR0:f32=0.06;
const trunkRk:f32=0.025;
/// a branch starts this thick relative to its host where it leaves it
const branchR:f32=0.7;
/// stems narrow to this fraction of their base radius at the tip
const taper:f32=0.85;
/// bark turns old (brown) at this radius
const oldR:f32=0.13;
const rootLen:f32=0.45;
const rootSpread:f32=0.7;
/// wind: stems sway (the trunk by `TRUNK_SWAY` of it), leaves flutter, each
/// at its own rate
const swayAmount:f32=0.05;
const swayRate:f32=0.8;
const trunkSway:f32=0.4;
const flutterAmount:f32=0.08;
const flutterRate:f32=1.3;
/// the sapling's clock wraps after this many seconds (keeps f32 precise)
const timeWrap:f64=1000;
/// a frame's trunk easing steps at most this many seconds
const easeDtMax:f64=0.1;
fn isBranch(i:usize)bool{return prog.tree.values[i].branch;}
/// stem index of a host: 0 the trunk, 1 + id a branch.
fn stemOf(h:?Id)usize{return if(h)|id|1+@as(usize,@intFromEnum(id))else 0;}
fn firstPrereq(id:Id)?Id{
  const r=prog.tree.get(id);
  return if(r.prereq.len>0)r.prereq[0]else null;
}
/// the static shape of the tree, worked out from the prerequisites.
const Plan=struct{
  host:[nodeCount]?Id,
  /// where along its host a node grows, in slots from the host's base
  at:[nodeCount]f32,
  /// +1 to the left of the host's heading, -1 to the right
  side:[nodeCount]f32,
  /// children per stem
  kids:[nodeCount+1]u32,
  /// branches, each after the stem it grows on
  order:[nodeCount]Id,
  branches:usize,
};
const plan:Plan=blk:{
  @setEvalBranchQuota(100_000);
  var p:Plan=undefined;
  var depth:[nodeCount]u32=@splat(0);
  for(0..nodeCount)|_|for(prog.tree.values,0..)|r,i|{
    var dd:u32=if(r.needs!=null)1 else 0;
    for(r.prereq)|q|dd=@max(dd,depth[@intFromEnum(q)]+1);
    depth[i]=dd;
  };
  for(0..nodeCount)|i|{
    var h=firstPrereq(@enumFromInt(i));
    while(h)|q|:(h=firstPrereq(q))if(prog.tree.get(q).branch)break;
    p.host[i]=h;
  }
  // stable by depth, so everything grows above what it needs
  var sorted:[nodeCount]usize=undefined;
  for(&sorted,0..)|*o,i|o.*=i;
  for(1..nodeCount)|i|{
    var j=i;
    while(j>0 and depth[sorted[j-1]]>depth[sorted[j]]):(j-=1){
      const t=sorted[j];
      sorted[j]=sorted[j-1];
      sorted[j-1]=t;
    }
  }
  p.kids=@splat(0);
  var leaves:[nodeCount+1]u32=@splat(0);
  var twigs:[nodeCount+1]u32=@splat(0);
  p.branches=0;
  for(sorted)|i|{
    const h=stemOf(p.host[i]);
    p.kids[h]+=1;
    p.at[i]=m.f(p.kids[h]);
    // leaves start on the left, branches on the right, so the crown balances
    const nth=if(isBranch(i))&twigs[h]else&leaves[h];
    p.side[i]=if((nth.*%2==0)!=isBranch(i))1 else-1;
    nth.*+=1;
    if(isBranch(i)){
      p.order[p.branches]=@enumFromInt(i);
      p.branches+=1;
    }
  }
  break:blk p;
};
/// a stem's full length: one slot past its last child (a branch's at least
/// BRANCH_MIN).
fn stemLen(k:usize)f32{
  const n=m.f(plan.kids[k]+1);
  return if(k==0)n else@max(n,branchMin);
}
fn heading(a:f32)V3{return m.v3(@cos(a),@sin(a),0);}
/// a stem's centreline: SEG even steps whose heading turns by `bend` of the
/// way to straight up, plus `curl` (sway) growing toward the tip.
const Stem=struct{
  pts:[seg+1]V3=undefined,
  ang:[seg+1]f32=undefined,
  len:f32=0,
  fn build(base:V3,a0:f32,len:f32,bend:f32,curl:f32)Stem{
    var st:Stem=.{.len=len};
    st.pts[0]=base;
    st.ang[0]=a0;
    for(1..seg+1)|j|{
      const u=m.ratio(j,seg);
      st.ang[j]=a0+(upAxis-a0)*bend*u+curl*u*u;
      st.pts[j]=st.pts[j-1]+heading((st.ang[j-1]+st.ang[j])/2)*m.splat3(len/seg);
    }
    return st;
  }
  fn point(st:*const Stem,at:f32)V3{return m.alongPath(&st.pts,m.clamp01(at/st.len));}
  fn angle(st:*const Stem,at:f32)f32{
    const k=m.clamp01(at/st.len)*seg;
    const i=@min(m.floorTo(usize,k),seg-1);
    return m.lerp(st.ang[i],st.ang[i+1],k-m.f(i));
  }
};
const Layout=struct{
  stems:[nodeCount+1]Stem,
  /// where each node leaves its host, and its heading there
  base:[nodeCount]V3,
  ang:[nodeCount]f32,
};
/// the whole tree at time `t`; `amp` scales the wind (0: still).
fn layout(t:f32,amp:f32)Layout{
  var l:Layout=undefined;
  l.stems[0]=.build(m.splat3(0),upAxis,stemLen(0),bendAmount,amp*sway(0,t)*trunkSway);
  place(&l,null,t,amp);
  for(plan.order[0..plan.branches])|b|{
    const i:usize=@intFromEnum(b);
    l.stems[1+i]=.build(l.base[i],l.ang[i],stemLen(1+i),bendAmount,amp*sway(1+i,t));
    place(&l,b,t,amp);
  }
  return l;
}
fn place(l:*Layout,h:?Id,t:f32,amp:f32)void{
  const st=&l.stems[stemOf(h)];
  for(0..nodeCount)|i|if(stemOf(plan.host[i])==stemOf(h)){
    const off=if(!isBranch(i))leafAngle else if(h==null)branchAngle else twigAngle;
    const flutter=if(isBranch(i))0 else flutterAmount*@sin(t*flutterRate+m.f(i)*2.3);
    l.base[i]=st.point(plan.at[i]);
    l.ang[i]=st.angle(plan.at[i])+plan.side[i]*off+amp*flutter;
  };
}
fn sway(k:usize,t:f32)f32{return swayAmount*@sin(t*swayRate+m.f(k)*1.9);}
/// a leaf's tip, fully open.
fn leafTip(l:*const Layout,i:usize)V3{return l.base[i]+heading(l.ang[i])*m.splat3(petiole+leafLen);}
/// slots to screen pixels: y up becomes y down.
const Fit=struct{
  o:[2]f32,
  k:f32,
  fn at(f:Fit,p:V3)[2]f32{return.{f.o[0]+p[0]*f.k,f.o[1]-p[1]*f.k};}
  fn angle(a:f32)f32{return-a;}
};
/// the fully grown, still tree fitted into the area, standing on its floor.
fn fit(x:f32,y:f32,w:f32,h:f32)Fit{
  const l=layout(0,0);
  var lo=m.v3(0,-rootLen,0);
  var hi=lo;
  const grow=struct{
    fn by(a:*V3,b:*V3,p:V3)void{a.*=@min(a.*,p);b.*=@max(b.*,p);}
  };
  for(0..nodeCount+1)|k|if(k==0 or isBranch(k-1))for(l.stems[k].pts)|p|grow.by(&lo,&hi,p);
  for(0..nodeCount)|i|if(!isBranch(i))grow.by(&lo,&hi,leafTip(&l,i));
  lo-=m.splat3(leafW);
  hi+=m.splat3(leafW);
  const k=@min(@min(w/(hi[0]-lo[0]),h/(hi[1]-lo[1])),maxSlot);
  return.{.o=.{x+w/2-(lo[0]+hi[0])/2*k,y+h+lo[1]*k},.k=k};
}
/// how far the trunk has grown, eased toward what is known (kept in play.Game).
pub const Sapling=struct{
  trunk:f32=0,
  /// ui time of the last draw; negative until the first, which snaps
  t:f64=-1,
};
fn trunkTarget(g:*const play.Game)f32{
  var top:f32=0;
  for(0..nodeCount)|i|if(plan.host[i]==null and g.prog.status(@enumFromInt(i))!=.locked){top=@max(top,plan.at[i]);};
  return top+trunkLead;
}
fn frac(g:*const play.Game,id:Id)f32{
  if(g.prog.done.contains(id))return 1;
  return m.ratio(g.prog.progress.get(id),prog.tree.get(id).units);
}
fn mix(a:Color,b:Color,t:f32)Color{
  const c=color.mix(.of(a),.of(b),m.clamp01(t));
  return.{c.r,c.g,c.b,c.a};
}
pub fn visible(g:*const play.Game)bool{return g.mode==.research;}
/// a research node
pub const Pick=union(enum){node:Id};
/// a click chooses what is studied (carrying something, it just puts it down)
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  if(press!=.use)return;
  if(g.held!=null)return g.drop();
  switch(p){.node=>|id|g.prog.select(id)}
}
pub fn draw(g:*play.Game,d:*Draw,screenW:f32,screenH:f32)Allocator.Error!void{
  const ph=@min(screenH-2*margin,maxH);
  const px=screenW-pw-margin;
  const py=(screenH-ph)/2;
  try d.trellis(px,py,pw,ph,s.researchPanel,0.77);
  g.rows.add(.{.x=px,.y=py,.w=pw,.h=ph},.panel);
  _=try d.text(px+56,py+s.titleY,s.textTitle,s.gold,txt.s.hud.researchTitle);
  _=try d.text(px+56,py+58,s.textSmall,s.dim,txt.s.hud.researchHint);
  const sp=&g.sapling;
  const target=trunkTarget(g);
  if(sp.t<0)sp.trunk=target else{
    const dt:f32=@floatCast(m.clamp(g.uiTime-sp.t,0,easeDtMax));
    sp.trunk+=(target-sp.trunk)*@min(1,dt*trunkEase);
  }
  sp.t=g.uiTime;
  const areaY=py+headerH;
  const f=fit(px+treePad,areaY,pw-2*treePad,ph-headerH-cardH);
  const t:f32=@floatCast(@mod(g.uiTime,timeWrap));
  const l=layout(t,1);
  // how far each stem has grown, and how thick it is at its base
  var grown:[nodeCount+1]f32=@splat(0);
  var rad:[nodeCount+1]f32=@splat(0);
  grown[0]=@min(sp.trunk,l.stems[0].len);
  rad[0]=trunkR0+trunkRk*@sqrt(m.f(g.prog.done.count()));
  for(plan.order[0..plan.branches])|b|{
    const i:usize=@intFromEnum(b);
    const h=stemOf(plan.host[i]);
    if(!shown(&grown,i))continue;
    const st=g.prog.status(b);
    grown[1+i]=if(st==.done)l.stems[1+i].len else if(g.prog.current==b)frac(g,b)*l.stems[1+i].len else 0;
    rad[1+i]=branchR*radiusAt(rad[h],grown[h],plan.at[i]);
  }
  // soil, roots, then the trunk and branches (each after its host)
  const foot=f.at(m.splat3(0));
  try d.glow(foot[0],foot[1],@max(0.9*f.k,24),s.soil);
  for([_]f32{-1,0,1})|side|{
    const root:Stem=.build(m.splat3(0),-upAxis+side*rootSpread,rootLen,0,-side*0.5);
    try stem(d,f,&root,rootLen,rad[0]*0.8);
  }
  try stem(d,f,&l.stems[0],grown[0],rad[0]);
  for(plan.order[0..plan.branches])|b|{
    const k=1+@as(usize,@intFromEnum(b));
    try stem(d,f,&l.stems[k],grown[k],rad[k]);
  }
  // each shown node's look: where it is hit, and what it grows into
  const hover:?Id=if(hud.own(.research,g.pointed))|p|switch(p){.node=>|id|id}else null;
  var mark:[nodeCount]?[2]f32=@splat(null);
  for(0..nodeCount)|i|if(shown(&grown,i)){
    const id:Id=@enumFromInt(i);
    const st=g.prog.status(id);
    const along=heading(l.ang[i]);
    const reach:f32=if(st==.done)0.5 else 0.25;
    mark[i]=if(!isBranch(i))f.at(l.base[i]+along*m.splat3(petiole+leafLen*reach))
      else if(st==.done)f.at(l.stems[1+i].point(l.stems[1+i].len))
      else f.at(l.stems[1+i].point(grown[1+i])+heading(l.stems[1+i].angle(grown[1+i]))*m.splat3(budLen*branchBud*0.5));
  };
  // glows beneath: what is studied, what is pointed at, what can be chosen
  for(mark,0..)|mk,i|if(mk)|c|{
    const id:Id=@enumFromInt(i);
    const r=@max(0.4*f.k,14);
    if(g.prog.current==id)try d.glow(c[0],c[1],r*1.3,s.researchActive)
    else if(hover==id)try d.glow(c[0],c[1],r,s.researchHover)
    else if(g.prog.status(id)==.open)try d.glow(c[0],c[1],r*0.8,s.researchInvite);
  };
  for(mark,0..)|mk,i|if(mk)|c|{
    const id:Id=@enumFromInt(i);
    try node(d,f,&l,g,id,grown[1+i],rad[0]);
    const hit=@max(0.7*f.k,minHit);
    g.rows.add(.{.x=c[0]-hit/2,.y=c[1]-hit/2,.w=hit,.h=hit},hud.row(.research,.{.node=id}));
  };
  try card(g,d,px,py+ph-cardH,hover orelse g.prog.current);
}
/// is node i drawn? Its host must be grown (the trunk always is) up to it.
fn shown(grown:*const[nodeCount+1]f32,i:usize)bool{
  const h=stemOf(plan.host[i]);
  return(h==0 or grown[h]>0) and plan.at[i]<=grown[h]+0.01;
}
/// a stem of base radius r0 grown to `at`, narrowing toward the growing tip.
fn radiusAt(r0:f32,gl:f32,at:f32)f32{return r0*(1-taper*m.clamp01(at/@max(gl,m.eps)));}
fn bark(r:f32)Color{return mix(s.barkYoung,s.barkOld,r/oldR);}
/// draw a stem grown `gl` slots along, tapering to a point.
fn stem(d:*Draw,f:Fit,st:*const Stem,gl:f32,r0:f32)Allocator.Error!void{
  if(gl<=0.01)return;
  const petalCount=8;
  var a0:f32=0;
  var p0=f.at(st.point(0));
  var q0=r0;
  for(1..petalCount+1)|j|{
    const a1=gl*m.ratio(j,petalCount);
    const p1=f.at(st.point(a1));
    const q1=radiusAt(r0,gl,a1);
    try d.limb(p0,p1,@max(q0*f.k,1.2),@max(q1*f.k,0.6),bark(q0),a0*f.k);
    a0=a1;
    p0=p1;
    q0=q1;
  }
}
/// one node: a leaf (petiole and blade) or a branch's bloom or bud.
fn node(d:*Draw,f:Fit,l:*const Layout,g:*const play.Game,id:Id,gl:f32,trunkR:f32)Allocator.Error!void{
  const i:usize=@intFromEnum(id);
  const st=g.prog.status(id);
  const cur=g.prog.current==id;
  const seed=m.f(i)*0.37;
  const fr=frac(g,id);
  if(isBranch(i)){
    const stm=&l.stems[1+i];
    if(st==.done){
      const tip=f.at(stm.point(stm.len));
      return d.pod(tip[0],tip[1],@max(bloomR*f.k,4),s.researchTendril,0.8,seed);
    }
    const at=if(cur)gl else 0;
    const base=f.at(stm.point(at));
    const k:f32=if(st==.locked)branchBud*0.8 else branchBud;
    return d.leaf(base,Fit.angle(stm.angle(at)),budLen*k*f.k,budW*k*f.k,budColor(st),0,seed);
  }
  // a stalk thin as the youngest twig, then the blade (or bud) at its end
  const a=l.ang[i];
  const p0=f.at(l.base[i]);
  const p1=f.at(l.base[i]+heading(a)*m.splat3(petiole));
  try d.limb(p0,p1,@max(trunkR*0.35*f.k,1),@max(trunkR*0.25*f.k,0.8),s.barkYoung,0);
  const open:f32=if(st==.done)1 else if(cur)fr else 0;
  const k:f32=if(st==.locked)0.8 else 1;
  const len=m.lerp(budLen*k,leafLen,open);
  const wid=m.lerp(budW*k,leafW,open);
  const col=if(st==.done)s.leaf else mix(budColor(st),s.leaf,open);
  try d.leaf(p1,Fit.angle(a),len*f.k,wid*f.k,col,open,seed);
}
fn budColor(st:prog.Status)Color{
  return switch(st){.locked=>s.budDormant,.open,.done=>s.bud};
}
/// what the hovered (or studied) node is: name, description, what each unit
/// eats and how long, its progress; or what it still waits for.
fn card(g:*const play.Game,d:*Draw,px:f32,y:f32,focus:?Id)Allocator.Error!void{
  const id=focus orelse return;
  const r=prog.tree.get(id);
  const st=g.prog.status(id);
  const col=if(g.prog.current==id)s.gold else switch(st){
    .done=>s.researchDone,
    .open=>s.white,
    .locked=>s.researchLocked,
  };
  const x=px+56;
  _=try d.text(x,y,s.textRow,col,txt.research(id).name);
  _=try d.text(x,y+24,s.textFine,s.dim,txt.research(id).desc);
  if(st==.locked){
    for(r.prereq)|q|if(!g.prog.done.contains(q)){
      _=try d.print(x,y+46,s.textFine,s.researchLocked,txt.s.hud.researchDormant,.{txt.research(q).name});
      return;
    };
    _=try d.text(x,y+46,s.textFine,s.researchLocked,txt.s.hud.researchUnwitnessed);
    return;
  }
  var cx=x;
  for(r.perUnit,0..)|ing,j|{
    try d.grain(cx+6,y+51,9,13,ing.item.info().col,0.6,m.f(j)*0.3);
    cx=try d.print(cx+14,y+46,s.textFine,s.dim,txt.s.hud.ingredient,.{ing.n,txt.item(ing.item).short})+10;
  }
  _=try d.print(cx+8,y+46,s.textFine,s.dim,txt.s.hud.researchCost,.{r.units,r.unitTime});
  try d.tendril(x,y+70,tendrilW,tendrilH,col,frac(g,id),m.f(@intFromEnum(id))*0.21);
}
test"the sapling lays itself out: hosts grow first, nodes keep apart"{
  // every branch's host is the trunk or a branch earlier in the order
  for(plan.order[0..plan.branches],0..)|b,n|if(plan.host[@intFromEnum(b)])|h|{
    const before=indexOfScalar(Id,plan.order[0..n],h);
    try testing.expect(before!=null);
  };
  // no two nodes (leaf middles, branch tips) crowd each other
  const l=layout(0,0);
  var at:[nodeCount]V3=undefined;
  for(0..nodeCount)|i|at[i]=if(isBranch(i))l.stems[1+i].point(l.stems[1+i].len)
    else l.base[i]+heading(l.ang[i])*m.splat3(petiole+leafLen/2);
  for(0..nodeCount)|i|for(i+1..nodeCount)|j|try testing.expect(m.len(at[i]-at[j])>0.5);
}
