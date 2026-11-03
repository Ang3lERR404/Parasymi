//! the research tree (T): a living tree over the whole screen, the world
//! frozen behind it, painted on the main menu's dark with petals, seeds,
//! leaves and pollen drifting down. It starts as a sprout in the soil and
//! every study known grows it, crown and roots alike. Nothing is placed by
//! hand: the shape follows from the prerequisites alone, so a new technology
//! needs no layout.
//!   - host: a study grows from its deepest prerequisite (the first among
//!     equals), or off the trunk; its ring is how many limbs out it is.
//!   - the crown is a dome over the trunk's top; each study fills a sector
//!     of it as wide as the tips it carries, its children splitting it, and
//!     stands at its ring's distance out. Limbs leave their host part way
//!     along it, curving out of its heading to their tips, twisting a little.
//!   - roots mirror the crown under the soil: every study grown sends one
//!     down, as far below as its limb reaches above.
//!   - the whole tree scales with how much is known, from a sprout to full
//!     size; limbs thicken with all they carry (the pipe rule), bark ageing
//!     from green to brown, the trunk flaring into its roots.
//! Each study is drawn as its lineage: a symbiotic flower, a parasitic gall,
//! radiant crystal gathered, a convergent braided ring. Known: fully grown.
//! Studied: its limb grows out with progress, its node opening at the tip.
//! Open: a glowing bud where its limb will come out. Locked: a dormant bud
//! in mist once its host is known; beyond that, nothing yet. The view fits
//! the tree as it grows until it is dragged (the orbit button anywhere, or
//! the use button on the backdrop) or zoomed (the wheel, the zoom keys);
//! clicking a study studies it and flies the view to it, its card beside it.
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
/// the species registry, for the lineages a study is drawn as
const species=lib.species;
/// the weaves, which tell what a study lets be woven and so its lineage
const craft=lib.craft;
/// what can be held: the item a study lets be woven, for its card's icon
const items=lib.items;
/// the item icons, for what a study lets be woven
const icon=lib.icon;
/// the UI's draw batch
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// the HUD's shared sizes and colours
const s=lib.style;
/// the HUD's panel component, for the card
const Panel=lib.hudPanel.Panel;
/// every player-facing string
const txt=lib.txt;
/// all the maths: vectors, easing, angles
const m=lib.engine.core.math;
/// colour mixing, for bark ageing and dormant buds
const color=lib.engine.core.color;
/// the HUD: picks, presses, rows and boxes
const hud=lib.hud;
/// a screen rectangle
const Box=hud.Box;
/// the bindings: which action each key is
const ctl=lib.controls;
/// the keys and buttons down this frame
const Input=lib.engine.platform.input.Input;
/// a research's id
const Id=prog.Id;
/// which path a study walks
const Lineage=species.Lineage;
/// a point in the tree's space (slots; y up, the soil at 0; z unused)
const V3=m.V3;
/// a point on screen (pixels, y down)
const P2=m.Vice(f32,2);
/// how many studies the tree holds
const nodeCount=prog.tree.values.len;
// ---- the shape, in slots (one slot = a node's spacing on the inner ring) ----
/// how many even steps a limb's centreline is drawn in
const seg=12;
/// the fully grown trunk's height (slots)
const trunkH:f32=4.2;
/// the crown's sectors run between these angles (radians; 0 right)
const crownLo=m.rad(6);
/// (the left end)
const crownHi=m.rad(174);
/// how far out the first ring of the crown stands from the trunk's top (slots)
const ringR0:f32=3.2;
/// how much further out each ring after it stands (slots)
const ringStep:f32=1.75;
/// the crown is this much wider than its rings...
const crownWide:f32=1.15;
/// ...and this much shorter, a dome
const crownTall:f32=0.88;
/// a limb off the trunk leaves it this far up at the dome's sides, rising
/// to the top for the leader straight up (a share of the trunk's height)
const trunkAlong:f32=0.42;
/// a limb off a limb leaves it between these shares of the host's length
const alongLo:f32=0.42;
/// (the far end)
const alongHi:f32=0.8;
/// a limb heads out along its host's heading for this share of its length
/// before curving to its tip
const lead:f32=0.42;
/// a limb off the trunk sets out this much of the way from straight up
/// toward its tip
const trunkLean:f32=0.55;
/// how far a limb twists off its line (a share of its length)
const twist:f32=0.05;
/// the smallest growth: a sprout knowing nothing (a share of full size)
const sproutMin:f32=0.32;
/// growth rises with the share known to this power (faster early)
const growPow:f32=0.7;
/// how fast the tree eases toward its growth (share a second)
const growEase:f32=1.2;
/// roots spread this much wider than the crown...
const rootWide:f32=1.05;
/// ...and reach this much as deep as the crown rises over its lowest limbs
const rootDeep:f32=0.48;
/// roots start under the trunk's foot, the crown's height below this
/// share of the trunk mirrored to nothing
const rootFrom:f32=0.42;
/// how far under the soil the roots leave the trunk (slots, fully grown)
const rootTop:f32=0.08;
/// roots twist this much more than limbs
const rootTwist:f32=1.8;
/// roots are this thick beside the limbs they mirror
const rootThick:f32=0.62;
/// a trunk's radius knowing nothing (slots)
const trunkR:f32=0.075;
/// a limb's base radius carrying one study (slots); more by the square
/// root of all it carries
const limbR:f32=0.05;
/// limbs narrow to this share of their base radius at the tip
const tipShare:f32=0.45;
/// the trunk's foot flares this much wider...
const flare:f32=0.85;
/// ...over this share of its height
const flareTo:f32=0.13;
/// bark turns old (brown) at this radius (slots)
const oldR:f32=0.22;
/// a node's radius (slots, grown fully; it grows with the tree); a big
/// study's is `bigNode` times it
const nodeR:f32=0.3;
/// (a big study's)
const bigNode:f32=1.3;
/// a node is never drawn smaller than this many pixels across its radius...
const nodeMinPx:f32=15;
/// ...nor larger
const nodeMaxPx:f32=96;
/// an open or dormant study puts out a faint shoot all the way to where
/// its tip will be, its bud there: this thick beside its limb...
const shootThick:f32=0.4;
/// ...and this see-through (alpha)
const shootAlpha:u8=130;
/// hit area round a node, at least this many pixels across
const minHit:f32=26;
/// wind: how far limbs sway at their tips (a share of their length)
const swayAmount:f32=0.025;
/// how fast they sway (radians a second)
const swayRate:f32=0.8;
/// the trunk sways this much of a limb's
const trunkSway:f32=0.4;
/// the clock wraps after this many seconds (keeps f32 precise)
const timeWrap:f64=1000;
/// a frame's easing steps at most this many seconds
const easeDtMax:f64=0.1;
/// a gap this long (seconds) between draws means the tree was closed and
/// is opened afresh: the view fits it again
const reopenGap:f64=0.25;
// ---- the view ----
/// the view never shows less than this many slots high, so a sprout stands small
const minView:f32=5;
/// the fitted tree fills this share of the screen
const fitFill:f32=0.86;
/// how fast the view eases to where it is going (share a second)
const viewEase:f32=3.5;
/// zoomed in, a slot spans at most this many pixels
const maxZoom:f32=260;
/// zoomed out, the whole grown tree fits at least this share of the screen
const minZoomShare:f32=0.45;
/// a wheel notch zooms by this factor
const notchZoom:f32=1.15;
/// the zoom keys held double the zoom in this many seconds
const keyZoomRate:f32=1.0;
/// the left stick leant all the way pans this many screen heights a second
const stickPan:f32=0.8;
/// a press on the backdrop moved this many pixels is a drag, not a click
const dragSlop:f32=5;
/// flying to a study zooms in to at least this many pixels a slot
const focusZoom:f32=110;
/// the card beside a study: its width, height (pixels)
const cardW:f32=600;
/// (its height)
const cardH:f32=154;
/// how far (pixels) the card stands off its node, and the screen's edges
const cardGap:f32=26;
/// the card's progress tendril's length (pixels)
const tendrilW:f32=150;
/// its thickness (pixels)
const tendrilH=s.barH;
/// the icon of what a study lets be woven: its radius on the card (pixels)
const iconR:f32=30;
/// the card's lines under its name (pixels down): the description...
const descDown:f32=24;
/// ...the cost, or what it waits for...
const costDown:f32=46;
/// ...and the progress tendril
const barDown:f32=70;
/// the title and hint stand this far (pixels) in from the top left
const headX:f32=40;
/// the band (pixels) the title and hint take across the top, kept clear of
/// the fitted tree
const headH:f32=100;
/// whether study `i` is a big one (new structures, species, an event)
fn isBig(i:usize)bool{return prog.tree.values[i].branch;}
/// the static shape of the tree, worked out from the prerequisites.
const Plan=struct{
  /// the study each grows from (its deepest prerequisite); null: the trunk
  host:[nodeCount]?Id,
  /// how many limbs out from the trunk it grows (1: off the trunk)
  ring:[nodeCount]u32,
  /// the middle of the crown's sector it fills (radians; 0 right)
  angle:[nodeCount]f32,
  /// where along its host it leaves it (a share of the host's limb, or of
  /// the trunk's height)
  along:[nodeCount]f32,
  /// +1 or -1: which way its limb twists
  turn:[nodeCount]f32,
  /// the lineage its node is drawn as
  lineage:[nodeCount]Lineage,
  /// every study, each after its host
  order:[nodeCount]Id,
};
/// the lineage of what study `id` lets be woven, if it lets anything be
fn wovenLineage(id:Id)?Lineage{
  for(craft.hand)|rc|if(rc.needs)|nd|if(nd==id)if(rc.lineage())|l|return l;
  return null;
}
/// the item study `id` lets be woven first, if any: its card's icon
fn wovenItem(id:Id)?items.Item{
  for(craft.hand)|rc|if(rc.needs)|nd|if(nd==id)return rc.out;
  return null;
}
/// the plan, worked out once at build time
const plan:Plan=blk:{
  @setEvalBranchQuota(400_000);
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
    // its host so far: the deepest prerequisite, the first among equals
    var h:?Id=null;
    for(prog.tree.values[i].prereq)|q|{
      if(h)|cur|{
        if(depth[@intFromEnum(q)]>depth[@intFromEnum(cur)])h=q;
      }else h=q;
    }
    p.host[i]=h;
  }
  for(0..nodeCount)|_|for(0..nodeCount)|i|{
    p.ring[i]=if(p.host[i])|h|p.ring[@intFromEnum(h)]+1 else 1;
  };
  // the studies by ring, declaration order kept among equals
  var sorted:[nodeCount]usize=undefined;
  for(&sorted,0..)|*o,i|o.*=i;
  for(1..nodeCount)|i|{
    // where the study being sorted has got to
    var j=i;
    while(j>0 and p.ring[sorted[j-1]]>p.ring[sorted[j]]):(j-=1){
      // the one being swapped down
      const t=sorted[j];
      sorted[j]=sorted[j-1];
      sorted[j-1]=t;
    }
  }
  for(sorted,0..)|i,n|p.order[n]=@enumFromInt(i);
  // the tips each carries (itself, with none above it), summed outward in
  var tips:[nodeCount]f32=@splat(0);
  var above:[nodeCount]f32=@splat(0);
  var kids:[nodeCount]u32=@splat(0);
  // the trunk's tips, all of its limbs'
  var trunkTips:f32=0;
  var n=nodeCount;
  while(n>0){
    n-=1;
    // the study, from the outermost in
    const i=sorted[n];
    tips[i]=if(above[i]>0)above[i]else 1;
    if(p.host[i])|h|{
      above[@intFromEnum(h)]+=tips[i];
      kids[@intFromEnum(h)]+=1;
    }else trunkTips+=tips[i];
  }
  // each one's sector, its children splitting it left to right
  var lo:[nodeCount]f32=undefined;
  var hi:[nodeCount]f32=undefined;
  // where the next sector starts in each host (the trunk last)
  var cursor:[nodeCount+1]f32=undefined;
  cursor[nodeCount]=crownHi;
  for(sorted)|i|{
    // the host's index (the trunk: nodeCount), its sector and the tips it splits
    const hk=if(p.host[i])|h|@as(usize,@intFromEnum(h))else nodeCount;
    const span=if(hk==nodeCount)crownHi-crownLo else hi[hk]-lo[hk];
    const share=if(hk==nodeCount)trunkTips else above[hk];
    hi[i]=cursor[hk];
    lo[i]=cursor[hk]-span*tips[i]/share;
    cursor[hk]=lo[i];
    cursor[i]=hi[i];
    p.angle[i]=(lo[i]+hi[i])/2;
    p.along[i]=trunkAlong+(1-trunkAlong)*@sin(p.angle[i]);
    p.turn[i]=if(i%2==0)1 else-1;
    // its lineage as its def gives it, else as what it lets be woven
    const own:?Lineage=prog.tree.values[i].lineage orelse wovenLineage(@enumFromInt(i));
    p.lineage[i]=if(own)|l|l else if(p.host[i])|h|p.lineage[@intFromEnum(h)]else.symbiotic;
  }
  // a limb's children leave it in turn, the one nearest upright lowest, so
  // none crosses another
  for(0..nodeCount)|i|if(p.host[i])|h|{
    // how far it leans off upright, and how many siblings lean less
    const lean=@abs(p.angle[i]-m.halfPi);
    var rank:u32=0;
    for(0..nodeCount)|j|if(j!=i and p.host[j]==h){
      // the sibling's lean
      const lj=@abs(p.angle[j]-m.halfPi);
      if(lj<lean or (lj==lean and j<i))rank+=1;
    };
    p.along[i]=alongLo+(alongHi-alongLo)*(m.f(rank)+0.5)/m.f(kids[@intFromEnum(h)]);
  };
  break:blk p;
};
/// the unit vector at angle `a` in the tree's plane
fn heading(a:f32)V3{return m.v3(@cos(a),@sin(a),0);}
/// `v` turned a quarter left in the tree's plane
fn perp(v:V3)V3{return m.v3(-v[1],v[0],0);}
/// a centreline of `seg` even steps, base to tip
const Line=[seg+1]V3;
/// the point `u` (0..1) along line `l`
fn on(l:*const Line,u:f32)V3{return m.alongPath(l,m.clamp01(u));}
/// the heading (unit) of line `l` at `u` along it
fn tangentOf(l:*const Line,u:f32)V3{
  // a little before and after, kept on the line
  const a=on(l,u-0.03);
  const b=on(l,u+0.03);
  return m.norm(b-a);
}
/// where study `i`'s tip stands with the tree grown to `grow`
fn tipOf(i:usize,grow:f32)V3{
  // how far out its ring stands
  const r=ringR0+m.f(plan.ring[i]-1)*ringStep;
  const a=plan.angle[i];
  return m.v3(@cos(a)*r*crownWide,trunkH+@sin(a)*r*crownTall,0)*m.splat3(grow);
}
/// where crown point `p` is mirrored under the soil, with the tree grown to `grow`
fn rootOf(p:V3,grow:f32)V3{return m.v3(p[0]*rootWide,-@max(p[1]-grow*trunkH*rootFrom,0)*rootDeep-rootTop*grow,0);}
/// a curve from `a` heading `h0` to `b`, twisting `tw` (signed share of its
/// length) off its line, its far end swayed `sw` (a share of its length)
fn curve(a:V3,h0:V3,b:V3,tw:f32,sw:f32)Line{
  // the curve being built, its length, the control point it heads out by,
  // and the side it twists and sways toward
  var l:Line=undefined;
  const len=m.dist(a,b);
  const c=a+h0*m.splat3(len*lead);
  const side=perp(m.norm(b-a));
  for(0..seg+1)|j|{
    // how far along this step is, and the quadratic's weights there
    const u=m.ratio(j,seg);
    const w0=(1-u)*(1-u);
    const w1=2*u*(1-u);
    const w2=u*u;
    // how far off its line it stands here: the twist, and the sway growing to the tip
    const off=len*(tw*@sin(m.tau*u)+sw*u*u);
    l[j]=a*m.splat3(w0)+c*m.splat3(w1)+b*m.splat3(w2)+side*m.splat3(off);
  }
  return l;
}
/// the tree laid out at one moment: the trunk, each study's limb and root
const Layout=struct{
  /// the trunk's centreline, from where its roots leave under the soil to its top
  trunk:Line,
  /// each study's limb, from where it leaves its host to its tip
  limb:[nodeCount]Line,
  /// each study's root, mirroring its limb under the soil
  root:[nodeCount]Line,
};
/// the whole tree grown to `grow` at time `t`; `amp` scales the wind (0: still).
fn layout(grow:f32,t:f32,amp:f32)Layout{
  // the layout being filled
  var l:Layout=undefined;
  // the trunk, from just under the soil, swaying a little at its top
  const top=m.v3(0,trunkH*grow,0);
  l.trunk=curve(m.v3(0,-rootTop*grow,0),heading(m.halfPi),top,0,amp*trunkSway*swayAmount*@sin(t*swayRate));
  for(plan.order)|id|{
    // the study, where its limb leaves its host and heads out, and its tip
    const i:usize=@intFromEnum(id);
    const b=tipOf(i,grow);
    var a:V3=undefined;
    var h0:V3=undefined;
    var ra:V3=undefined;
    var rh:V3=undefined;
    if(plan.host[i])|h|{
      // its host's lines
      const hk:usize=@intFromEnum(h);
      a=on(&l.limb[hk],plan.along[i]);
      h0=tangentOf(&l.limb[hk],plan.along[i]);
      ra=on(&l.root[hk],plan.along[i]);
      rh=tangentOf(&l.root[hk],plan.along[i]);
    }else{
      a=on(&l.trunk,plan.along[i]);
      h0=m.norm(m.lerpV(heading(m.halfPi),m.norm(b-a),trunkLean));
      ra=m.v3(0,-rootTop*grow,0);
      rh=m.norm(m.lerpV(heading(-m.halfPi),m.norm(rootOf(b,grow)-ra),trunkLean));
    }
    // the wind on it now
    const sw=amp*swayAmount*@sin(t*swayRate+m.f(i)*1.9);
    l.limb[i]=curve(a,h0,b,twist*plan.turn[i],sw);
    l.root[i]=curve(ra,rh,rootOf(b,grow),-twist*rootTwist*plan.turn[i],0);
  }
  return l;
}
/// slots to screen pixels: y up becomes y down.
const Fit=struct{
  /// where the tree's origin falls on screen (pixels)
  o:P2,
  /// how many pixels one slot spans
  k:f32,
  /// a point of the tree on screen (pixels)
  fn at(f:Fit,p:V3)P2{return.{f.o[0]+p[0]*f.k,f.o[1]-p[1]*f.k};}
};
/// the view centred on `at` (slots), `k` pixels a slot, on a `w` x `h` screen
fn view(at:V3,k:f32,w:f32,h:f32)Fit{return.{.o=.{w/2-at[0]*k,h/2+at[1]*k},.k=k};}
/// where screen point `p` falls in the tree, the view centred on `at`, `k` pixels a slot
fn unview(at:V3,k:f32,w:f32,h:f32,p:P2)V3{return m.v3(at[0]+(p[0]-w/2)/k,at[1]-(p[1]-h/2)/k,0);}
/// the centre that keeps tree point `p` under screen point `q`, `k` pixels a slot
fn keepUnder(p:V3,k:f32,w:f32,h:f32,q:P2)V3{return m.v3(p[0]-(q[0]-w/2)/k,p[1]+(q[1]-h/2)/k,0);}
/// a box in the tree (slots) taking in all it is grown to
const Bounds=struct{
  /// its lower corner
  lo:V3=m.splat3(m.inf(f32)),
  /// its upper corner
  hi:V3=m.splat3(-m.inf(f32)),
  /// widens it to take in `p`, `r` round
  fn take(b:*Bounds,p:V3,r:f32)void{
    b.lo=@min(b.lo,p-m.splat3(r));
    b.hi=@max(b.hi,p+m.splat3(r));
  }
  /// widens it to take in line `l`
  fn line(b:*Bounds,l:*const Line,r:f32)void{for(l)|p|b.take(p,r);}
  /// the view (centre, pixels a slot) fitting it into a `w` x `h` screen,
  /// never showing less than `minView` slots high
  fn fit(b:Bounds,w:f32,h:f32)struct{V3,f32}{
    // its size, at least the least view, and the scale fitting it both
    // ways under the title band
    const bw=@max(b.hi[0]-b.lo[0],minView*w/h);
    const bh=@max(b.hi[1]-b.lo[1],minView);
    const k=@min(w*fitFill/bw,(h-headH)*fitFill/bh);
    return.{(b.lo+b.hi)*m.splat3(0.5)+m.v3(0,headH/2/k,0),k};
  }
};
/// the tree's growth and its view, kept between frames (in play.Game).
pub const Sapling=struct{
  /// how far grown it is (a share of full size), eased toward what is known
  grow:f32=sproutMin,
  /// ui time of the last draw; negative until the first
  t:f64=-1,
  /// the view's centre (slots)
  at:V3=m.splat3(0),
  /// how many pixels a slot spans
  zoom:f32=1,
  /// where the view is easing to: its centre...
  toAt:V3=m.splat3(0),
  /// ...and zoom
  toZoom:f32=1,
  /// moved by hand: it no longer fits itself to the tree
  free:bool=false,
  /// the study whose card is shown, the view following it
  focus:?Id=null,
  /// while true the view flies after the focused study
  follow:bool=false,
  /// where the card was last drawn, so a click on it is not on the backdrop
  card:?Box=null,
  /// where a press on the backdrop went down, while it is held
  down:?P2=null,
  /// whether that press has moved far enough to be a drag
  dragged:bool=false,
  /// the screen's size (pixels) when last drawn
  screen:P2=.{1,1},
  /// the least zoom: the whole grown tree at `minZoomShare` of the screen
  least:f32=1,
  /// the grown tree's box (slots), the view's centre kept within it
  bounds:Bounds=.{},
  /// the view stops easing and stands where it is
  fn hold(sp:*Sapling)void{
    sp.toAt=sp.at;
    sp.toZoom=sp.zoom;
    sp.free=true;
    sp.follow=false;
  }
  /// zooms by `by` about screen point `q`, keeping what is under it there
  fn zoomAbout(sp:*Sapling,q:P2,by:f32)void{
    // the tree point under it, and the new zoom
    const w=sp.screen[0];
    const h=sp.screen[1];
    const p=unview(sp.at,sp.zoom,w,h,q);
    sp.zoom=m.clamp(sp.zoom*by,sp.least,maxZoom);
    sp.at=keepUnder(p,sp.zoom,w,h,q);
    sp.hold();
  }
  /// pans the view by screen pixels `d` (the tree moving with them)
  fn pan(sp:*Sapling,d:P2)void{
    sp.at+=m.v3(-d[0]/sp.zoom,d[1]/sp.zoom,0);
    sp.hold();
  }
};
/// each frame the tree is open: drags pan it (the orbit button anywhere, or
/// the use button from a press on the backdrop), the wheel and zoom keys
/// zoom it, the left stick pans it; a click on the backdrop (not dragged)
/// lets the card go. `hit` is what the cursor is over.
pub fn tick(g:*play.Game,in:*const Input,hit:?hud.Pick,dt:f32)void{
  // the sapling, and the cursor
  const sp=&g.sapling;
  const at:P2=in.mouse;
  // whether the cursor is on the backdrop: on nothing, or a bare panel that is not the card
  const onCard=if(sp.card)|b|b.contains(at)else false;
  const backdrop=if(hit)|p|p==.panel and !onCard else true;
  if(ctl.pressed(in,.use) and backdrop){
    sp.down=at;
    sp.dragged=false;
  }
  if(sp.down)|d0|if(!sp.dragged and m.dist(m.v3(at[0],at[1],0),m.v3(d0[0],d0[1],0))>dragSlop){sp.dragged=true;};
  // how far the mouse moved this frame (pixels)
  const md:P2=in.mouseDelta;
  if(ctl.down(in,.orbit) or (sp.dragged and ctl.down(in,.use))){
    if(md[0]!=0 or md[1]!=0)sp.pan(md);
  }
  if(!ctl.down(in,.use)){
    if(sp.down!=null and !sp.dragged)sp.focus=null;
    sp.down=null;
    sp.dragged=false;
  }
  if(in.scroll!=0)sp.zoomAbout(at,m.pow(f32,notchZoom,in.scroll));
  // the zoom keys held: in, out, or both (still)
  const keys=(if(ctl.down(in,.zoomIn))@as(f32,1)else 0)-(if(ctl.down(in,.zoomOut))@as(f32,1)else 0);
  if(keys!=0)sp.zoomAbout(.{sp.screen[0]/2,sp.screen[1]/2},m.pow(f32,2,keys*keyZoomRate*dt));
  // the left stick, panning as far as it leans (+y up)
  const ls=in.stick(.left);
  if(ls[0]!=0 or ls[1]!=0)sp.pan(.{-ls[0]*stickPan*sp.screen[1]*dt,ls[1]*stickPan*sp.screen[1]*dt});
}
/// how far grown the tree should be: a sprout knowing nothing, full size
/// knowing all
fn growTarget(g:*const play.Game)f32{return sproutMin+(1-sproutMin)*m.pow(f32,m.ratio(g.prog.done.count(),nodeCount),growPow);}
/// how far study `id` has come, 0..1 (1: known)
fn frac(g:*const play.Game,id:Id)f32{
  if(g.prog.done.contains(id))return 1;
  return m.ratio(g.prog.progress.get(id),prog.tree.get(id).units);
}
/// how much of study `i`'s limb is grown: all once known, with progress
/// while studied, else none
fn grownOf(g:*const play.Game,i:usize)f32{
  // the study
  const id:Id=@enumFromInt(i);
  if(g.prog.done.contains(id))return 1;
  return if(g.prog.current==id)frac(g,id)else 0;
}
/// study `i`'s node's radius on screen (pixels), the tree grown to `grow`
/// and drawn `k` pixels a slot
fn radiusOf(i:usize,grow:f32,k:f32)f32{return m.clamp(nodeR*grow*(if(isBig(i))bigNode else 1)*k,nodeMinPx,nodeMaxPx);}
/// whether study `i` shows at all: its host is known (the trunk always is)
fn shown(g:*const play.Game,i:usize)bool{
  return if(plan.host[i])|h|g.prog.done.contains(h)else true;
}
/// `a` blended toward `b` by `t`, 0..1
fn mix(a:Color,b:Color,t:f32)Color{
  // the blend, as a colour to unpack
  const c=color.mix(.of(a),.of(b),m.clamp01(t));
  return.{c.r,c.g,c.b,c.a};
}
/// bark's colour at radius `r` (slots): young green turning old brown
fn bark(r:f32)Color{return mix(s.barkYoung,s.barkOld,r/oldR);}
/// shown while the research tree is open.
pub fn visible(g:*const play.Game)bool{return g.mode==.research;}
/// a research node
pub const Pick=union(enum){
  /// the study at this node
  node:Id
};
/// a node clicks as mouse1 is let go over it
pub fn fire(_:Pick)hud.Fire{return.release;}
/// a click chooses what is studied and flies the view to it, its card beside it
pub fn click(g:*play.Game,p:Pick,press:hud.Press,_:*const Input)void{
  if(press!=.use)return;
  switch(p){.node=>|id|{
    g.prog.select(id);
    g.sapling.focus=id;
    g.sapling.follow=true;
    g.sapling.free=true;
  }}
}
/// the radii (slots) the tree is drawn with: the trunk's, each limb's at its base
const Thick=struct{
  /// the trunk's, above its flare
  trunk:f32,
  /// each limb's at its base
  limb:[nodeCount]f32,
};
/// the pipe rule: a limb is as thick as the square root of all it carries
/// (known, or as far studied), the trunk of everything
fn thickness(g:*const play.Game)Thick{
  // the radii being found, and what each limb carries, summed outward in
  var th:Thick=undefined;
  var carry:[nodeCount]f32=@splat(0);
  // all the trunk carries
  var all:f32=0;
  var n=nodeCount;
  while(n>0){
    n-=1;
    // the study, from the outermost in
    const i:usize=@intFromEnum(plan.order[n]);
    carry[i]+=grownOf(g,i);
    th.limb[i]=limbR*@sqrt(@max(carry[i],0.25));
    if(plan.host[i])|h|{carry[@intFromEnum(h)]+=carry[i];}else all+=carry[i];
  }
  th.trunk=trunkR*@sqrt(1+all);
  return th;
}
/// draws the tree over the whole screen: the painting, the light round the
/// tree, roots, trunk and limbs grown as far as they are, each shown node
/// (registered to be clicked), the title and hint, and the focused card.
pub fn draw(g:*play.Game,d:*Draw,screenW:f32,screenH:f32)Allocator.Error!void{
  // the sapling, and the time since it was last drawn (s)
  const sp=&g.sapling;
  const reopened=sp.t<0 or g.uiTime-sp.t>reopenGap;
  const dt:f32=if(reopened)0 else@floatCast(m.clamp(g.uiTime-sp.t,0,easeDtMax));
  sp.t=g.uiTime;
  sp.screen=.{screenW,screenH};
  // the growth, eased toward what is known (snapped on opening)
  const target=growTarget(g);
  sp.grow=if(reopened)target else m.damp(sp.grow,target,growEase,dt);
  // the clock, wrapped, and the tree swaying at that moment
  const t:f32=@floatCast(@mod(g.uiTime,timeWrap));
  const l=layout(sp.grow,t,1);
  const th=thickness(g);
  // the box of all that shows now, and of the whole tree grown
  var shownBox:Bounds=.{};
  shownBox.take(m.splat3(0),0);
  shownBox.line(&l.trunk,th.trunk);
  for(0..nodeCount)|i|if(shown(g,i)){
    // how far its limb is grown
    const gl=grownOf(g,i);
    shownBox.take(l.limb[i][seg],nodeR*bigNode*sp.grow);
    if(gl>0)shownBox.take(on(&l.root[i],gl),0);
  };
  // (the whole grown tree never changes: found once each time it opens)
  if(reopened){
    // the tree grown fully and still
    const full=layout(1,0,0);
    sp.bounds=.{};
    sp.bounds.take(m.splat3(0),0);
    for(0..nodeCount)|i|{
      sp.bounds.line(&full.limb[i],nodeR*bigNode);
      sp.bounds.line(&full.root[i],0);
    }
  }
  sp.least=sp.bounds.fit(screenW,screenH)[1]*minZoomShare/fitFill;
  // where the view goes: fitted to what shows, or after the focused study
  const fitted=shownBox.fit(screenW,screenH);
  if(reopened){
    sp.free=false;
    sp.focus=null;
    sp.follow=false;
    sp.at=fitted[0];
    sp.zoom=fitted[1];
  }
  if(!sp.free){
    sp.toAt=fitted[0];
    sp.toZoom=fitted[1];
  }
  if(sp.focus)|fid|if(sp.follow){
    // the study, its node now, and the view's zoom flown to
    const fi:usize=@intFromEnum(fid);
    const z=@max(sp.zoom,focusZoom);
    sp.toZoom=z;
    sp.toAt=nodeAt(&l,fi)+m.v3((cardW/2+cardGap)/z,0,0);
  };
  sp.at=m.dampV(sp.at,sp.toAt,viewEase,dt);
  sp.zoom=m.damp(sp.zoom,sp.toZoom,viewEase,dt);
  sp.at=@min(@max(sp.at,sp.bounds.lo),sp.bounds.hi);
  const f=view(sp.at,sp.zoom,screenW,screenH);
  // the painting (its warm light pooled over the soil), and the backdrop
  // that keeps clicks out of what is behind
  const foot=f.at(m.splat3(0));
  try d.dusk(screenW,screenH,foot[1],s.dusk,0.31);
  try g.rows.add(.{.x=0,.y=0,.w=screenW,.h=screenH},.panel);
  // roots, each after its host, then the trunk, then the limbs
  for(plan.order)|id|{
    // the study's index, how far grown
    const i:usize=@intFromEnum(id);
    const gl=grownOf(g,i);
    if(gl>0 and shown(g,i))try line(d,f,&l.root[i],gl,th.limb[i]*rootThick,s.rootBark);
  }
  try trunk(d,f,&l.trunk,th.trunk);
  for(plan.order)|id|{
    // the study's index
    const i:usize=@intFromEnum(id);
    if(!shown(g,i))continue;
    // how far it is grown: not yet whole, a faint shoot shows the way first
    const gl=grownOf(g,i);
    if(gl<1)try line(d,f,&l.limb[i],1,th.limb[i]*shootThick,.{s.barkYoung[0],s.barkYoung[1],s.barkYoung[2],shootAlpha});
    if(gl>0)try line(d,f,&l.limb[i],gl,th.limb[i],null);
  }
  // each shown node: its glow beneath, then the node, registered to be clicked
  const hover:?Id=if(hud.own(.research,g.pointed))|p|switch(p){.node=>|id|id}else null;
  for(0..nodeCount)|i|if(shown(g,i)){
    // the study, where its node is on screen, and its radius there (pixels)
    const id:Id=@enumFromInt(i);
    const c=f.at(nodeAt(&l,i));
    const r=radiusOf(i,sp.grow,f.k);
    const pulse=1+0.12*@sin(t*2.2+m.f(i));
    if(g.prog.current==id)try d.glow(c[0],c[1],r*2.2,s.researchActive)
    else if(hover==id or sp.focus==id)try d.glow(c[0],c[1],r*1.9,s.researchHover)
    else switch(g.prog.status(id)){
      .open=>try d.glow(c[0],c[1],r*1.9*pulse,s.researchInvite),
      .locked=>try d.glow(c[0],c[1],r*1.7,s.mist),
      .done=>{},
    }
    try node(d,g,i,c,r);
    // its hit area's side (pixels)
    const hit=@max(2*r,minHit);
    try g.rows.add(.{.x=c[0]-hit/2,.y=c[1]-hit/2,.w=hit,.h=hit},hud.row(.research,.{.node=id}));
    if(hover==id and sp.focus!=id)_=try d.text(c[0]+r+10,c[1]-8,s.textSmall,nameColor(g,id),txt.research(id).name);
  };
  _=try d.text(headX,s.titleY,s.textTitle,s.gold,txt.s.hud.researchTitle);
  _=try d.text(headX,s.titleY+30,s.textSmall,s.dim,txt.s.hud.researchHint);
  sp.card=null;
  if(sp.focus)|fid|{
    // the study's node on screen, and the card beside it: right of it, else left
    const fi:usize=@intFromEnum(fid);
    const c=f.at(nodeAt(&l,fi));
    const r=radiusOf(fi,sp.grow,f.k);
    const right=c[0]+r+cardGap;
    const x=if(right+cardW<=screenW-cardGap)right else@max(c[0]-r-cardGap-cardW,cardGap);
    const y=m.clamp(c[1]-cardH/2,cardGap,@max(screenH-cardH-cardGap,cardGap));
    const b:Box=.{.x=x,.y=y,.w=cardW,.h=cardH};
    sp.card=b;
    try card(g,d,b,fid);
  }
}
/// where study `i`'s node stands now: at its limb's tip, where its shoot
/// leads before it has grown
fn nodeAt(l:*const Layout,i:usize)V3{return l.limb[i][seg];}
/// the trunk: flaring at its foot into the roots, narrowing to its top
fn trunk(d:*Draw,f:Fit,l:*const Line,r0:f32)Allocator.Error!void{
  for(0..seg)|j|{
    // the piece's ends: how far up, where on screen, and the radius there
    const a0=m.ratio(j,seg);
    const a1=m.ratio(j+1,seg);
    const q0=trunkRadius(r0,a0);
    const q1=trunkRadius(r0,a1);
    try d.limb(f.at(l[j]),f.at(l[j+1]),@max(q0*f.k,1.2),@max(q1*f.k,0.8),bark(q0),a0*m.dist(l[0],l[seg])*f.k);
  }
}
/// the trunk's radius `u` (0..1) up it: flared at the foot, narrowing above
fn trunkRadius(r0:f32,u:f32)f32{
  // how much of the flare is left this far up: swept in, a buttress, not a bulb
  const fl=m.pow(f32,1-m.clamp01(u/flareTo),2.5);
  return r0*(1+flare*fl)*m.lerp(1,0.7,u);
}
/// a limb or root along `l` grown `gl` (0..1) of its length, base radius
/// `r0` tapering toward its tip, in `col` (null: bark by its thickness)
fn line(d:*Draw,f:Fit,l:*const Line,gl:f32,r0:f32,col:?Color)Allocator.Error!void{
  // how many pieces it is drawn in, and where the last one ended
  const pieces=seg;
  var p0=f.at(on(l,0));
  var q0=r0;
  var s0:f32=0;
  for(1..pieces+1)|j|{
    // where this piece ends: how far along, on screen, and its radius
    const u=gl*m.ratio(j,pieces);
    const p1=f.at(on(l,u));
    const q1=r0*m.lerp(1,tipShare,u);
    try d.limb(p0,p1,@max(q0*f.k,1),@max(q1*f.k,0.6),col orelse bark(q0),s0);
    s0+=m.dist(m.v3(p0[0],p0[1],0),m.v3(p1[0],p1[1],0));
    p0=p1;
    q0=q1;
  }
}
/// study `i`'s node at `c`, radius `r` pixels, drawn as its lineage: open as
/// far as it has come, a dormant bud dimmed
fn node(d:*Draw,g:*const play.Game,i:usize,c:P2,r:f32)Allocator.Error!void{
  // the study, its status, how far open, and its seed
  const id:Id=@enumFromInt(i);
  const st=g.prog.status(id);
  const open=grownOf(g,i);
  const seed=m.f(i)*0.37;
  // its colour by lineage, dimmed while dormant
  const base:Color=switch(plan.lineage[i]){
    .symbiotic=>s.symbioticBloom,
    .parasitic=>s.parasiticGall,
    .radiant=>s.radiantLight,
    .convergent=>s.convergentBloom,
  };
  const col=if(st==.locked)mix(base,s.budDormant,0.6)else base;
  switch(plan.lineage[i]){
    .symbiotic=>try d.blossom(c[0],c[1],r,col,open,seed),
    .parasitic=>try d.gall(c[0],c[1],r,col,open,seed),
    .radiant=>try d.shard(c[0],c[1],r,col,open,seed),
    .convergent=>try d.knot(c[0],c[1],r,col,open,seed),
  }
}
/// a study's name's colour: gold while studied, else by status
fn nameColor(g:*const play.Game,id:Id)Color{
  if(g.prog.current==id)return s.gold;
  return switch(g.prog.status(id)){
    .done=>s.researchDone,
    .open=>s.white,
    .locked=>s.researchLocked,
  };
}
/// study `id`'s card in box `b`: the icon of what it lets be woven, its
/// name, description, what each unit eats and how long, its progress; or
/// what it still waits for.
fn card(g:*play.Game,d:*Draw,b:Box,id:Id)Allocator.Error!void{
  try(Panel{.box=b,.col=s.researchPanel,.seed=0.77}).draw(g,d,g.sapling.screen);
  // the study's definition and status, its name's colour, and where its text starts
  const r=prog.tree.get(id);
  const st=g.prog.status(id);
  const col=nameColor(g,id);
  const x=b.x+2*iconR+36;
  const y=b.y+26;
  if(wovenItem(id))|it|try icon.draw(d,it,.{b.x+iconR+22,b.y+b.h/2},iconR,@floatCast(g.uiTime),m.f(@intFromEnum(id))*0.21,if(st==.done)1 else 0.4,if(st==.locked)140 else 255);
  _=try d.text(x,y,s.textRow,col,txt.research(id).name);
  _=try d.text(x,y+descDown,s.textFine,s.dim,txt.research(id).desc);
  if(st==.locked){
    for(r.prereq)|q|if(!g.prog.done.contains(q)){
      _=try d.print(x,y+costDown,s.textFine,s.researchLocked,txt.s.hud.researchDormant,.{txt.research(q).name});
      return;
    };
    _=try d.text(x,y+costDown,s.textFine,s.researchLocked,txt.s.hud.researchUnwitnessed);
    return;
  }
  // where the next ingredient is written (pixels from the left)
  var cx=x;
  for(r.perUnit,0..)|ing,j|{
    try d.grain(cx+6,y+costDown+5,9,13,ing.item.info().col,0.6,m.f(j)*0.3);
    cx=try d.print(cx+14,y+costDown,s.textFine,s.dim,txt.s.hud.ingredient,.{ing.n,txt.item(ing.item).short})+10;
  }
  _=try d.print(cx+8,y+costDown,s.textFine,s.dim,txt.s.hud.researchCost,.{r.units,r.unitTime});
  try d.tendril(x,y+barDown,tendrilW,tendrilH,col,frac(g,id),m.f(@intFromEnum(id))*0.21);
}
test"the tree lays itself out: hosts first, every study a lineage, tips apart and above the soil"{
  // every host comes before what grows from it, one ring nearer the trunk
  for(plan.order,0..)|id,n|if(plan.host[@intFromEnum(id)])|h|{
    // where its host stands in the order
    const before=indexOfScalar(Id,plan.order[0..n],h);
    try testing.expect(before!=null);
    try testing.expectEqual(plan.ring[@intFromEnum(h)]+1,plan.ring[@intFromEnum(id)]);
  };
  // a lineage set by a study's own def wins
  try testing.expectEqual(Lineage.parasitic,plan.lineage[@intFromEnum(Id.hungeringTendrils)]);
  try testing.expectEqual(Lineage.convergent,plan.lineage[@intFromEnum(Id.convergenceTheory)]);
  // grown fully and still (or a sprout: it grows as one), every tip stands
  // above the soil and every root under it, and no two nodes crowd
  const l=layout(1,0,0);
  for(0..nodeCount)|i|{
    try testing.expect(l.limb[i][seg][1]>0);
    try testing.expect(l.root[i][seg][1]<0);
    for(i+1..nodeCount)|j|try testing.expect(m.dist(nodeAt(&l,i),nodeAt(&l,j))>2*nodeR);
  }
}
test"zooming about a point keeps what is under it there"{
  // a view, and the tree point under a screen point
  var sp:Sapling=.{.at=m.v3(1,3,0),.zoom=40,.least=1,.screen=.{800,600}};
  const q=P2{620,150};
  const p=unview(sp.at,sp.zoom,800,600,q);
  sp.zoomAbout(q,1.8);
  // where that point lands now
  const now=view(sp.at,sp.zoom,800,600).at(p);
  try testing.expectApproxEqAbs(q[0],now[0],1e-3);
  try testing.expectApproxEqAbs(q[1],now[1],1e-3);
  try testing.expect(sp.free);
}
