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
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// finding one value in a list, for the layout test
const indexOfScalar=std.mem.indexOfScalar;
/// the test helpers
const testing=std.testing;
/// the game itself: progression, the sapling, what is pointed at
const play=lib.play;
/// what the gardener has understood: the research tree, its statuses
const prog=lib.progression;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the HUD's shared sizes and colours
const s=lib.style;
/// the HUD's panel component
const Panel=lib.hudPanel.Panel;
/// every player-facing string
const txt=lib.txt;
/// all the maths: vectors, easing, angles
const m=lib.engine.core.math;
/// colour mixing, for bark ageing and buds opening into leaves
const color=lib.engine.core.color;
/// the HUD: picks, presses, rows and bullets
const hud=lib.hud;
/// the keys and buttons down this frame
const Input=lib.engine.platform.input.Input;
/// a research's id
const Id=prog.Id;
/// a point in the tree's space (slots; y up)
const V3=m.V3;
/// how many studies the tree holds
const nodeCount=prog.tree.values.len;
/// the panel's width (pixels)
const pw:f32=600;
/// how far (pixels) the panel stands off the screen's edges
const margin:f32=24;
/// the panel's greatest height (pixels)
const maxH:f32=900;
/// the height (pixels) of its title band
const headerH:f32=84;
/// the height (pixels) of the card along the bottom
const cardH:f32=132;
/// how far (pixels) the tree stands in from the panel's sides
const treePad:f32=36;
/// the card's progress tendril's length (pixels)
const tendrilW:f32=150;
/// its thickness (pixels)
const tendrilH=s.barH;
/// a slot never draws larger than this many pixels, however few nodes
const maxSlot:f32=80;
/// hit area around a node, at least this many pixels across
const minHit:f32=26;
// ---- the shape, in slots (one slot = the spacing between nodes on a stem) ----
/// how many even steps a stem's centreline is drawn in
const seg=10;
/// straight up, the way the trunk grows (radians)
const upAngle:f32=m.halfPi;
/// how far off the host's heading a branch leaves the trunk (radians)
const branchAngle=m.rad(60);
/// how far off its host's heading a branch leaves a branch (radians)
const twigAngle=m.rad(40);
/// how far off its host's heading a leaf stands (radians)
const leafAngle=m.rad(56);
/// how far toward straight up a stem turns over its length
const bendAmount:f32=0.4;
/// a branch is at least this long, so even a bare one reaches out
const branchMin:f32=2.5;
/// a leaf's stalk length (slots)
const petiole:f32=0.16;
/// a fully open leaf's length (slots)
const leafLen:f32=0.7;
/// a fully open leaf's width (slots)
const leafW:f32=0.34;
/// a closed bud's length (slots)
const budLen:f32=0.3;
/// a closed bud's width (slots)
const budW:f32=0.2;
/// a branch's closed bud is this much larger than a leaf's
const branchBud:f32=1.4;
/// the radius (slots) of the violet bloom at a known branch's tip
const bloomR:f32=0.13;
/// the trunk reaches this far past its highest open or known node
const trunkLead:f32=0.55;
/// how fast the trunk eases toward its target (share a second)
const trunkEase:f32=1.5;
/// trunk radius: a seedling's (slots)
const trunkR0:f32=0.06;
/// how much the trunk thickens with what is known (slots, by the square root of the count)
const trunkRk:f32=0.025;
/// a branch starts this thick relative to its host where it leaves it
const branchR:f32=0.7;
/// stems narrow to this fraction of their base radius at the tip
const taper:f32=0.85;
/// bark turns old (brown) at this radius
const oldR:f32=0.13;
/// how long (slots) each of the three roots reaches
const rootLen:f32=0.45;
/// how far apart (radians) the roots spread
const rootSpread:f32=0.7;
/// wind: how far stems sway (radians at the tip)
const swayAmount:f32=0.05;
/// how fast stems sway (radians a second)
const swayRate:f32=0.8;
/// how much of that sway the trunk takes, 0..1
const trunkSway:f32=0.4;
/// how far leaves flutter (radians)
const flutterAmount:f32=0.08;
/// how fast leaves flutter (radians a second)
const flutterRate:f32=1.3;
/// the sapling's clock wraps after this many seconds (keeps f32 precise)
const timeWrap:f64=1000;
/// a frame's trunk easing steps at most this many seconds
const easeDtMax:f64=0.1;
/// whether study `i` is a big one, grown as a branch
fn isBranch(i:usize)bool{return prog.tree.values[i].branch;}
/// stem index of a host: 0 the trunk, 1 + id a branch.
fn stemOf(h:?Id)usize{return if(h)|id|1+@as(usize,@intFromEnum(id))else 0;}
/// a study's first prerequisite, which it grows nearest to; null for a root
fn firstPrereq(id:Id)?Id{
  // the study's definition
  const r=prog.tree.get(id);
  return if(r.prereq.len>0)r.prereq[0]else null;
}
/// the static shape of the tree, worked out from the prerequisites.
const Plan=struct{
  /// the branch a node grows on, or null for the trunk
  host:[nodeCount]?Id,
  /// where along its host a node grows, in slots from the host's base
  at:[nodeCount]f32,
  /// +1 to the left of the host's heading, -1 to the right
  side:[nodeCount]f32,
  /// children per stem
  kids:[nodeCount+1]u32,
  /// branches, each after the stem it grows on
  order:[nodeCount]Id,
  /// how many branches `order` holds
  branches:usize,
};
/// the plan, worked out once at build time: hosts, depths, places along
/// stems, sides, and the order branches grow in
const plan:Plan=blk:{
  @setEvalBranchQuota(100_000);
  // the plan being filled, and each study's depth (its longest prerequisite chain)
  var p:Plan=undefined;
  var depth:[nodeCount]u32=@splat(0);
  for(0..nodeCount)|_|for(prog.tree.values,0..)|r,i|{
    // the depth so far: one for a discovery, else one past its deepest prerequisite
    var dd:u32=if(r.needs!=null)1 else 0;
    for(r.prereq)|q|dd=@max(dd,depth[@intFromEnum(q)]+1);
    depth[i]=dd;
  };
  for(0..nodeCount)|i|{
    // walking up the first-prerequisite chain to the nearest branch
    var h=firstPrereq(@enumFromInt(i));
    while(h)|q|:(h=firstPrereq(q))if(prog.tree.get(q).branch)break;
    p.host[i]=h;
  }
  // stable by depth, so everything grows above what it needs
  // the studies in order of depth, sorted in place
  var sorted:[nodeCount]usize=undefined;
  for(&sorted,0..)|*o,i|o.*=i;
  for(1..nodeCount)|i|{
    // where the study being sorted has got to
    var j=i;
    while(j>0 and depth[sorted[j-1]]>depth[sorted[j]]):(j-=1){
      // the one being swapped down
      const t=sorted[j];
      sorted[j]=sorted[j-1];
      sorted[j-1]=t;
    }
  }
  p.kids=@splat(0);
  // how many leaves, and how many branches, each stem carries so far
  var leaves:[nodeCount+1]u32=@splat(0);
  var twigs:[nodeCount+1]u32=@splat(0);
  p.branches=0;
  for(sorted)|i|{
    // the stem this study grows on
    const h=stemOf(p.host[i]);
    p.kids[h]+=1;
    p.at[i]=m.f(p.kids[h]);
    // leaves start on the left, branches on the right, so the crown balances
    // the count of its kind on that stem, to alternate sides
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
/// `branchMin`).
fn stemLen(k:usize)f32{
  // one slot past its children
  const n=m.f(plan.kids[k]+1);
  return if(k==0)n else@max(n,branchMin);
}
/// the unit vector at angle `a` in the tree's plane
fn heading(a:f32)V3{return m.v3(@cos(a),@sin(a),0);}
/// a stem's centreline: `seg` even steps whose heading turns by `bend` of the
/// way to straight up, plus `curl` (sway) growing toward the tip.
const Stem=struct{
  /// the points along it, base to tip
  pts:[seg+1]V3=undefined,
  /// its heading (radians) at each point
  ang:[seg+1]f32=undefined,
  /// its length (slots)
  len:f32=0,
  /// builds a stem from `base` heading `a0`, `len` slots long, turning `bend`
  /// of the way to straight up and curling by `curl` toward its tip.
  fn build(base:V3,a0:f32,len:f32,bend:f32,curl:f32)Stem{
    // the stem being built
    var st:Stem=.{.len=len};
    st.pts[0]=base;
    st.ang[0]=a0;
    for(1..seg+1)|j|{
      // how far along it this step is, 0..1
      const u=m.ratio(j,seg);
      st.ang[j]=a0+(upAngle-a0)*bend*u+curl*u*u;
      st.pts[j]=st.pts[j-1]+heading((st.ang[j-1]+st.ang[j])/2)*m.splat3(len/seg);
    }
    return st;
  }
  /// the point `at` slots along it (clamped to its length)
  fn point(st:*const Stem,at:f32)V3{return m.alongPath(&st.pts,m.clamp01(at/st.len));}
  /// its heading (radians) `at` slots along it
  fn angle(st:*const Stem,at:f32)f32{
    // how far along it `at` is, in steps, and the step it falls in
    const k=m.clamp01(at/st.len)*seg;
    const i=@min(m.floorTo(usize,k),seg-1);
    return m.lerp(st.ang[i],st.ang[i+1],k-m.f(i));
  }
};
/// the tree laid out at one moment: every stem's line, and where each node sits
const Layout=struct{
  /// every stem: the trunk first, then one per study (used by branches)
  stems:[nodeCount+1]Stem,
  /// where each node leaves its host
  base:[nodeCount]V3,
  /// each node's heading where it leaves its host (radians)
  ang:[nodeCount]f32,
};
/// the whole tree at time `t`; `amp` scales the wind (0: still).
fn layout(t:f32,amp:f32)Layout{
  // the layout being filled
  var l:Layout=undefined;
  l.stems[0]=.build(m.splat3(0),upAngle,stemLen(0),bendAmount,amp*sway(0,t)*trunkSway);
  place(&l,null,t,amp);
  for(plan.order[0..plan.branches])|b|{
    // the branch's index
    const i:usize=@intFromEnum(b);
    l.stems[1+i]=.build(l.base[i],l.ang[i],stemLen(1+i),bendAmount,amp*sway(1+i,t));
    place(&l,b,t,amp);
  }
  return l;
}
/// lays out the nodes growing on host `h` (null: the trunk) along its stem,
/// each turned off to its side, leaves fluttering with time `t`.
fn place(l:*Layout,h:?Id,t:f32,amp:f32)void{
  // the stem they grow on
  const st=&l.stems[stemOf(h)];
  for(0..nodeCount)|i|if(stemOf(plan.host[i])==stemOf(h)){
    // how far off its stem's heading it stands, and how far it flutters now
    const off=if(!isBranch(i))leafAngle else if(h==null)branchAngle else twigAngle;
    const flutter=if(isBranch(i))0 else flutterAmount*@sin(t*flutterRate+m.f(i)*2.3);
    l.base[i]=st.point(plan.at[i]);
    l.ang[i]=st.angle(plan.at[i])+plan.side[i]*off+amp*flutter;
  };
}
/// how far stem `k` sways at time `t` (radians)
fn sway(k:usize,t:f32)f32{return swayAmount*@sin(t*swayRate+m.f(k)*1.9);}
/// a leaf's tip, fully open.
fn leafTip(l:*const Layout,i:usize)V3{return l.base[i]+heading(l.ang[i])*m.splat3(petiole+leafLen);}
/// slots to screen pixels: y up becomes y down.
const Fit=struct{
  /// where the tree's origin falls on screen (pixels)
  o:m.Vice(f32,2),
  /// how many pixels one slot spans
  k:f32,
  /// a point of the tree on screen (pixels)
  fn at(f:Fit,p:V3)m.Vice(f32,2){return.{f.o[0]+p[0]*f.k,f.o[1]-p[1]*f.k};}
  /// a heading of the tree on screen, y flipped
  fn angle(a:f32)f32{return-a;}
};
/// the fully grown, still tree fitted into the area, standing on its floor.
fn fit(x:f32,y:f32,w:f32,h:f32)Fit{
  // the still, fully grown tree
  const l=layout(0,0);
  // the lower and upper corners of all it covers
  var lo=m.v3(0,-rootLen,0);
  var hi=lo;
  // a helper widening those corners to take in a point
  const grow=struct{
    /// widens `a`..`b` to take in `p`
    fn by(a:*V3,b:*V3,p:V3)void{a.*=@min(a.*,p);b.*=@max(b.*,p);}
  };
  for(0..nodeCount+1)|k|if(k==0 or isBranch(k-1))for(l.stems[k].pts)|p|grow.by(&lo,&hi,p);
  for(0..nodeCount)|i|if(!isBranch(i))grow.by(&lo,&hi,leafTip(&l,i));
  lo-=m.splat3(leafW);
  hi+=m.splat3(leafW);
  // the scale: fitting both ways, never larger than `maxSlot`
  const k=@min(@min(w/(hi[0]-lo[0]),h/(hi[1]-lo[1])),maxSlot);
  return.{.o=.{x+w/2-(lo[0]+hi[0])/2*k,y+h+lo[1]*k},.k=k};
}
/// how far the trunk has grown, eased toward what is known (kept in play.Game).
pub const Sapling=struct{
  /// how far up the trunk has grown (slots)
  trunk:f32=0,
  /// ui time of the last draw; negative until the first, which snaps
  t:f64=-1,
};
/// how far the trunk should reach: just past its highest open or known node
fn trunkTarget(g:*const play.Game)f32{
  // the highest open or known node on the trunk so far (slots)
  var top:f32=0;
  for(0..nodeCount)|i|if(plan.host[i]==null and g.prog.status(@enumFromInt(i))!=.locked){top=@max(top,plan.at[i]);};
  return top+trunkLead;
}
/// how far study `id` has come, 0..1 (1: known)
fn frac(g:*const play.Game,id:Id)f32{
  if(g.prog.done.contains(id))return 1;
  return m.ratio(g.prog.progress.get(id),prog.tree.get(id).units);
}
/// `a` blended toward `b` by `t`, 0..1
fn mix(a:Color,b:Color,t:f32)Color{
  // the blend, as a colour to unpack
  const c=color.mix(.of(a),.of(b),m.clamp01(t));
  return.{c.r,c.g,c.b,c.a};
}
/// shown while the research sapling is open.
pub fn visible(g:*const play.Game)bool{return g.mode==.research;}
/// a research node
pub const Pick=union(enum){
  /// the study at this node
  node:Id
};
/// a node clicks as mouse1 is let go over it
pub fn fire(_:Pick)hud.Fire{return.release;}
/// a click chooses what is studied (carrying something, it just puts it down)
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  if(press!=.use)return;
  if(g.held!=null)return g.drop();
  switch(p){.node=>|id|g.prog.select(id)}
}
/// draws the panel: the title and hint, the sapling (soil, roots, trunk and
/// branches grown as far as they are, each shown node's glow, leaf or bud,
/// registered to be clicked), and the card of the node hovered or studied.
pub fn draw(g:*play.Game,d:*Draw,screenW:f32,screenH:f32)Allocator.Error!void{
  // the panel's height, and its top-left corner
  const ph=@min(screenH-2*margin,maxH);
  const px=screenW-pw-margin;
  const py=(screenH-ph)/2;
  try(Panel{.box=.{.x=px,.y=py,.w=pw,.h=ph},.col=s.researchPanel,.seed=0.77}).draw(g,d,.{screenW,screenH});
  _=try d.text(px+56,py+s.titleY,s.textTitle,s.gold,txt.s.hud.researchTitle);
  _=try d.text(px+56,py+58,s.textSmall,s.dim,txt.s.hud.researchHint);
  // the sapling's growth, and how far its trunk should reach
  const sp=&g.sapling;
  const target=trunkTarget(g);
  if(sp.t<0)sp.trunk=target else{
    // the time since the last draw (s), clamped so a long pause eases gently
    const dt:f32=@floatCast(m.clamp(g.uiTime-sp.t,0,easeDtMax));
    sp.trunk+=(target-sp.trunk)*@min(1,dt*trunkEase);
  }
  sp.t=g.uiTime;
  // the tree's area's top, and how the grown tree fits into it
  const areaY=py+headerH;
  const f=fit(px+treePad,areaY,pw-2*treePad,ph-headerH-cardH);
  // the sapling's clock, wrapped, and the tree swaying at that moment
  const t:f32=@floatCast(@mod(g.uiTime,timeWrap));
  const l=layout(t,1);
  // how far each stem has grown, and how thick it is at its base
  var grown:[nodeCount+1]f32=@splat(0);
  var rad:[nodeCount+1]f32=@splat(0);
  grown[0]=@min(sp.trunk,l.stems[0].len);
  rad[0]=trunkR0+trunkRk*@sqrt(m.f(g.prog.done.count()));
  for(plan.order[0..plan.branches])|b|{
    // the branch's index, and the stem it grows on
    const i:usize=@intFromEnum(b);
    const h=stemOf(plan.host[i]);
    if(!shown(&grown,i))continue;
    // how far the branch is studied
    const st=g.prog.status(b);
    grown[1+i]=if(st==.done)l.stems[1+i].len else if(g.prog.current==b)frac(g,b)*l.stems[1+i].len else 0;
    rad[1+i]=branchR*radiusAt(rad[h],grown[h],plan.at[i]);
  }
  // soil, roots, then the trunk and branches (each after its host)
  // where the trunk meets the soil, on screen
  const foot=f.at(m.splat3(0));
  try d.glow(foot[0],foot[1],@max(0.9*f.k,24),s.soil);
  for([_]f32{-1,0,1})|side|{
    // this root, curling outward
    const root:Stem=.build(m.splat3(0),-upAngle+side*rootSpread,rootLen,0,-side*0.5);
    try stem(d,f,&root,rootLen,rad[0]*0.8);
  }
  try stem(d,f,&l.stems[0],grown[0],rad[0]);
  for(plan.order[0..plan.branches])|b|{
    // the branch's stem index
    const k=1+@as(usize,@intFromEnum(b));
    try stem(d,f,&l.stems[k],grown[k],rad[k]);
  }
  // each shown node's look: where it is hit, and what it grows into
  // the node under the mouse, and where each shown node is marked on screen
  const hover:?Id=if(hud.own(.research,g.pointed))|p|switch(p){.node=>|id|id}else null;
  var mark:[nodeCount]?m.Vice(f32,2)=@splat(null);
  for(0..nodeCount)|i|if(shown(&grown,i)){
    // the node, its status, and its heading
    const id:Id=@enumFromInt(i);
    const st=g.prog.status(id);
    const along=heading(l.ang[i]);
    // how far out along its leaf the mark sits
    const reach:f32=if(st==.done)0.5 else 0.25;
    mark[i]=if(!isBranch(i))f.at(l.base[i]+along*m.splat3(petiole+leafLen*reach))
      else if(st==.done)f.at(l.stems[1+i].point(l.stems[1+i].len))
      else f.at(l.stems[1+i].point(grown[1+i])+heading(l.stems[1+i].angle(grown[1+i]))*m.splat3(budLen*branchBud*0.5));
  };
  // glows beneath: what is studied, what is pointed at, what can be chosen
  for(mark,0..)|mk,i|if(mk)|c|{
    // the node, and its glow's radius (pixels)
    const id:Id=@enumFromInt(i);
    const r=@max(0.4*f.k,14);
    if(g.prog.current==id)try d.glow(c[0],c[1],r*1.3,s.researchActive)
    else if(hover==id)try d.glow(c[0],c[1],r,s.researchHover)
    else if(g.prog.status(id)==.open)try d.glow(c[0],c[1],r*0.8,s.researchInvite);
  };
  for(mark,0..)|mk,i|if(mk)|c|{
    // the node
    const id:Id=@enumFromInt(i);
    try node(d,f,&l,g,id,grown[1+i],rad[0]);
    // its hit area's side (pixels)
    const hit=@max(0.7*f.k,minHit);
    try g.rows.add(.{.x=c[0]-hit/2,.y=c[1]-hit/2,.w=hit,.h=hit},hud.row(.research,.{.node=id}));
  };
  try card(g,d,px,py+ph-cardH,hover orelse g.prog.current);
}
/// is node i drawn? Its host must be grown (the trunk always is) up to it.
fn shown(grown:*const[nodeCount+1]f32,i:usize)bool{
  // the stem it grows on
  const h=stemOf(plan.host[i]);
  return(h==0 or grown[h]>0) and plan.at[i]<=grown[h]+0.01;
}
/// a stem of base radius r0 grown to `at`, narrowing toward the growing tip.
fn radiusAt(r0:f32,gl:f32,at:f32)f32{return r0*(1-taper*m.clamp01(at/@max(gl,m.eps)));}
/// bark's colour at radius `r`: young green turning old brown at `oldR`
fn bark(r:f32)Color{return mix(s.barkYoung,s.barkOld,r/oldR);}
/// draw a stem grown `gl` slots along, tapering to a point.
fn stem(d:*Draw,f:Fit,st:*const Stem,gl:f32,r0:f32)Allocator.Error!void{
  if(gl<=0.01)return;
  // how many pieces the stem is drawn in
  const petalCount=8;
  // where the last piece ended: how far along, on screen, and its radius
  var a0:f32=0;
  var p0=f.at(st.point(0));
  var q0=r0;
  for(1..petalCount+1)|j|{
    // where this piece ends: how far along, on screen, and its radius
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
  // its index, status, whether it is studied, its sway seed, and its progress
  const i:usize=@intFromEnum(id);
  const st=g.prog.status(id);
  const cur=g.prog.current==id;
  const seed=m.f(i)*0.37;
  const fr=frac(g,id);
  if(isBranch(i)){
    // its stem
    const stm=&l.stems[1+i];
    if(st==.done){
      // its tip, where the bloom opens
      const tip=f.at(stm.point(stm.len));
      return d.pod(tip[0],tip[1],@max(bloomR*f.k,4),s.researchTendril,0.8,seed);
    }
    // where the bud sits: at the growing tip while studied, else at its base
    const at=if(cur)gl else 0;
    const base=f.at(stm.point(at));
    // its size: a dormant bud smaller
    const k:f32=if(st==.locked)branchBud*0.8 else branchBud;
    return d.leaf(base,Fit.angle(stm.angle(at)),budLen*k*f.k,budW*k*f.k,budColor(st),0,seed);
  }
  // a stalk thin as the youngest twig, then the blade (or bud) at its end
  // its heading, where it leaves its host, and the stalk's end
  const a=l.ang[i];
  const p0=f.at(l.base[i]);
  const p1=f.at(l.base[i]+heading(a)*m.splat3(petiole));
  try d.limb(p0,p1,@max(trunkR*0.35*f.k,1),@max(trunkR*0.25*f.k,0.8),s.barkYoung,0);
  // how far it has opened, 0..1, and a dormant bud's smaller size
  const open:f32=if(st==.done)1 else if(cur)fr else 0;
  const k:f32=if(st==.locked)0.8 else 1;
  // the blade's length and width, from bud to leaf
  const len=m.lerp(budLen*k,leafLen,open);
  const wid=m.lerp(budW*k,leafW,open);
  // its colour, from bud to leaf
  const col=if(st==.done)s.leaf else mix(budColor(st),s.leaf,open);
  try d.leaf(p1,Fit.angle(a),len*f.k,wid*f.k,col,open,seed);
}
/// a bud's colour by status: dormant while locked, else gold
fn budColor(st:prog.Status)Color{
  return switch(st){.locked=>s.budDormant,.open,.done=>s.bud};
}
/// what the hovered (or studied) node is: name, description, what each unit
/// eats and how long, its progress; or what it still waits for.
fn card(g:*const play.Game,d:*Draw,px:f32,y:f32,focus:?Id)Allocator.Error!void{
  // the study, its definition and status
  const id=focus orelse return;
  const r=prog.tree.get(id);
  const st=g.prog.status(id);
  // its name's colour: gold while studied, else by status
  const col=if(g.prog.current==id)s.gold else switch(st){
    .done=>s.researchDone,
    .open=>s.white,
    .locked=>s.researchLocked,
  };
  // the card's left edge
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
  // where the next ingredient is written (pixels from the left)
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
    // where its host stands in the order
    const before=indexOfScalar(Id,plan.order[0..n],h);
    try testing.expect(before!=null);
  };
  // no two nodes (leaf middles, branch tips) crowd each other
  const l=layout(0,0);
  // each node's middle: a branch's tip, a leaf's middle
  var at:[nodeCount]V3=undefined;
  for(0..nodeCount)|i|at[i]=if(isBranch(i))l.stems[1+i].point(l.stems[1+i].len)
    else l.base[i]+heading(l.ang[i])*m.splat3(petiole+leafLen/2);
  for(0..nodeCount)|i|for(i+1..nodeCount)|j|try testing.expect(m.len(at[i]-at[j])>0.5);
}
