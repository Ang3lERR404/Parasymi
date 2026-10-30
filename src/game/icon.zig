//! item icons for the HUD: what sits in a belly slot, a hotbar pod or on the
//! cursor. A structure's bulb or a plant's seed is a seed broken open, its
//! sprout or two showing what it will grow into (the structure's `icon`
//! hook, or its module in `seeds.zig`, drawn with the kit below); anything
//! else is its colour, for now.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: lerps, ratios, angles
const m=lib.engine.core.math;
/// the UI's draw batch the icons go into
const Draw=lib.engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=lib.engine.ui.draw.Color;
/// what can be held: items and their colours
const items=lib.items;
/// the structures registry, whose `icon` hooks draw bulbs
const st=lib.structures;
/// the seed icons, one module per plant's seed
const seeds=lib.seeds;
/// the HUD's shared sizes and colours
const s=lib.style;
/// every player-facing string, for an item's short name
const txt=lib.txt;
/// a point in icon units: x right, y up, origin at the slot's centre, 1 = its radius.
pub const P=[2]f32;
/// the seed sits low in the slot: its centre, where sprouts rise from its split tip at `topAt`
const seedC:P=.{0,-0.38};
/// how wide the seed coat is (icon units)
const seedW:f32=0.62;
/// how tall the seed coat is (icon units)
const seedH:f32=0.92;
/// how high the coat's split tip sits, where stems start (icon units)
pub const topAt:f32=0.06;
/// how far the coat is cracked open, 0..1
const crack:f32=0.8;
/// stems: how many segments along their curve
const stemSegs=6;
/// how thin a stem's tip is, as a share of its base
const stemTip:f32=0.35;
/// how far the breeze bends a sprout, radians-ish per unit of height squared
const swayAmount:f32=0.1;
/// how fast the breeze sways the sprouts (radians a second)
const swayRate:f32=1.3;
/// an item that is not a bulb: a filled pod this share of the slot, its
/// short name on it
const fillR:f32=0.95;
/// a sprout's leaves: fresh green
pub const sprout:Color=.{110,190,95,255};
/// a sprout's stem: the young bark green
pub const stemCol:Color=s.barkYoung;
/// a woven root (conduit arches, a digger's roots)
pub const rootCol:Color=.{150,112,72,255};
/// an anther's pollen (as meshgen's `pollen`)
pub const pollen:Color=.{235,185,80,255};
/// one icon being drawn: where its slot is, its clock and its fade, with
/// the kit (coat, stems, leaves, buds) the bulbs and seeds are drawn with
pub const Icon=struct{
  /// the draw batch it goes into
  d:*Draw,
  /// the slot's centre, in pixels
  c:[2]f32,
  /// the slot's radius, in pixels
  r:f32,
  /// UI seconds, so the sprouts sway
  t:f32,
  /// a per-slot phase, 0..1, so neighbours sway apart
  phase:f32,
  /// faded (not understood yet, or lifted out of its slot)
  alpha:u8=255,
  /// a colour at this icon's fade.
  pub fn col(ic:Icon,c:Color)Color{
    return.{c[0],c[1],c[2],@intCast(@as(u32,c[3])*ic.alpha/255)};
  }
  /// how far the breeze leans the sprouts at height `y`.
  fn lean(ic:Icon,y:f32)f32{
    // the height above the split tip, never below it
    const h=@max(y-topAt,0);
    return swayAmount*@sin(ic.t*swayRate+ic.phase*6)*h*h;
  }
  /// pixel position of icon point `p`, leaning with the breeze.
  pub fn px(ic:Icon,p:P)[2]f32{
    return.{ic.c[0]+(p[0]+ic.lean(p[1]))*ic.r,ic.c[1]-p[1]*ic.r};
  }
  /// the seed coat, split open at its tip.
  pub fn coat(ic:Icon,c:Color)Allocator.Error!void{
    // the coat's centre, in pixels
    const q=ic.px(seedC);
    try ic.d.grain(q[0],q[1],seedW*ic.r,seedH*ic.r,ic.col(c),crack,ic.phase);
  }
  /// a stem along the cubic Bézier `p` (icon units), `w` thick at its
  /// base, thinning toward its tip.
  pub fn stem(ic:Icon,p:[4]P,w:f32,c:Color)Allocator.Error!void{
    // the segment's start, and the arc length drawn so far
    var prev=ic.px(p[0]);
    var arc:f32=0;
    for(1..stemSegs+1)|i|{
      // how far along the curve the segment starts and ends, 0..1
      const k0=m.ratio(i-1,stemSegs);
      const k=m.ratio(i,stemSegs);
      // the segment's end, in pixels
      const next=ic.px(curve(p,k));
      // its radius at its start and end, thinning toward the tip
      const r0=w*ic.r*0.5*m.lerp(1,stemTip,k0);
      const r1=w*ic.r*0.5*m.lerp(1,stemTip,k);
      try ic.d.limb(prev,next,r0,r1,ic.col(c),arc);
      arc+=@sqrt((next[0]-prev[0])*(next[0]-prev[0])+(next[1]-prev[1])*(next[1]-prev[1]));
      prev=next;
    }
  }
  /// a leaf from `base`, pointing `ang` radians (0 right, counter-clockwise),
  /// `len` long and `wid` wide (icon units); it flutters a little.
  pub fn leaf(ic:Icon,base:P,ang:f32,len:f32,wid:f32,c:Color,open:f32)Allocator.Error!void{
    // a small flutter of its angle, its own per leaf
    const flutter=0.08*@sin(ic.t*2.1+ic.phase*5+base[0]*7);
    try ic.d.leaf(ic.px(base),-(ang+flutter),len*ic.r,wid*ic.r,ic.col(c),open,ic.phase+base[1]);
  }
  /// a small round pod (a bud, a bead of sap, a stone).
  pub fn bud(ic:Icon,at:P,r:f32,c:Color,lit:f32)Allocator.Error!void{
    // the bud's centre, in pixels
    const q=ic.px(at);
    try ic.d.pod(q[0],q[1],r*ic.r,ic.col(c),lit,ic.phase+at[0]);
  }
  /// a soft glow of radius `r` (icon units) round `at`
  pub fn glow(ic:Icon,at:P,r:f32,c:Color)Allocator.Error!void{
    // the glow's centre, in pixels
    const q=ic.px(at);
    try ic.d.glow(q[0],q[1],r*ic.r,ic.col(c));
  }
  /// a faceted gem of radius `r` (icon units) at `at`, catching the light
  pub fn gem(ic:Icon,at:P,r:f32,c:Color)Allocator.Error!void{
    // the gem's centre, in pixels
    const q=ic.px(at);
    try ic.d.gem(q[0],q[1],r*ic.r,ic.col(c),1,ic.phase);
  }
  /// a flower's stamens: `n` thin filaments fanning `spread` radians either
  /// side of `ang` from its heart `at`, `len` long, each tipped with a
  /// grain of pollen; they sway with the flower.
  pub fn stamens(ic:Icon,at:P,ang:f32,spread:f32,n:u32,len:f32,c:Color)Allocator.Error!void{
    for(0..n)|i|{
      // where this filament sits in the fan, -1..1
      const k=if(n>1)m.ratio(i,n-1)*2-1 else 0;
      // its angle, swaying a touch
      const a=ang+k*spread+0.05*@sin(ic.t*1.9+ic.phase*5+m.f(i));
      // the outer ones shorter, as they lean away
      const l=len*(1-0.25*k*k);
      // its pollen-tipped end
      const tip:P=.{at[0]+@cos(a)*l,at[1]+@sin(a)*l};
      // the bend its stem passes through, halfway
      const mid:P=.{at[0]+@cos(ang+k*spread*0.6)*l*0.5,at[1]+@sin(ang+k*spread*0.6)*l*0.5};
      try ic.stem(.{at,mid,mid,tip},0.025,c);
      try ic.bud(tip,0.028,pollen,1);
    }
  }
  /// a hair-thin thread hanging from `from` straight down `len`, waving
  /// `waves` times across its length, the swing `amp` widening toward its
  /// free tip and a wave running down it; it tapers from `w` to nothing.
  pub fn thread(ic:Icon,from:P,len:f32,waves:f32,amp:f32,w:f32,ph:f32,c:Color)Allocator.Error!void{
    // how many segments the thread is drawn in
    const stamenCount=14;
    // the segment's start, and the arc length drawn so far
    var prev=ic.px(from);
    var arc:f32=0;
    for(1..stamenCount+1)|i|{
      // how far down the thread the segment starts and ends, 0..1
      const k0=m.ratio(i-1,stamenCount);
      const k=m.ratio(i,stamenCount);
      // how far it swings out here: wider toward the tip, a wave running down
      const swing=amp*k*@sin(k*waves*m.tau-ic.t*2.2+ph);
      // the segment's end, in pixels
      const next=ic.px(.{from[0]+swing,from[1]-len*k});
      try ic.d.limb(prev,next,w*ic.r*0.5*(1-k0)+0.3,w*ic.r*0.5*(1-k)+0.3,ic.col(c),arc);
      arc+=@sqrt((next[0]-prev[0])*(next[0]-prev[0])+(next[1]-prev[1])*(next[1]-prev[1]));
      prev=next;
    }
  }
  /// a small seed of its own (what a germinator makes).
  pub fn kernel(ic:Icon,at:P,h:f32,c:Color)Allocator.Error!void{
    // the seed's centre, in pixels
    const q=ic.px(at);
    try ic.d.grain(q[0],q[1],h*0.66*ic.r,h*ic.r,ic.col(c),0,ic.phase+0.5);
  }
};
/// the point `k` (0..1) along the cubic Bézier `p`.
pub fn curve(p:[4]P,k:f32)P{
  // the point being built, one axis at a time
  var o:P=undefined;
  for(0..2)|a|{
    // de Casteljau: the three first-level lerps on this axis
    const ab=m.lerp(p[0][a],p[1][a],k);
    const bc=m.lerp(p[1][a],p[2][a],k);
    const cd=m.lerp(p[2][a],p[3][a],k);
    o[a]=m.lerp(m.lerp(ab,bc,k),m.lerp(bc,cd,k),k);
  }
  return o;
}
/// draws `item` in a slot of radius `r` at `c`: a bulb's seed and sprouts,
/// else its colour. `alpha` fades it; `phase` keeps neighbours apart.
pub fn draw(d:*Draw,item:items.Item,c:[2]f32,r:f32,t:f32,phase:f32,lit:f32,alpha:u8)Allocator.Error!void{
  // the icon, and the item's table entry (its colour)
  const ic:Icon=.{.d=d,.c=c,.r=r,.t=t,.phase=phase,.alpha=alpha};
  const info=item.info();
  if(st.kindOf(item))|k|{
    try st.icon(k,ic,info.col);
    return;
  }
  if(try seeds.icon(item,ic,info.col))return;
  try d.pod(c[0],c[1],r*fillR,ic.col(info.col),lit,phase);
  // the item's short name, and its text size scaled to the slot
  const short=txt.item(item).short;
  const size=s.textHeading*r/24;
  _=try d.text(c[0]-Draw.width(short,size)/2,c[1]-r*0.5,size,ic.col(s.dark),short);
}
/// how many, low on the right of a slot, over a shadow so it reads on any icon.
pub fn count(d:*Draw,c:[2]f32,r:f32,n:u32)Allocator.Error!void{
  // the count's text size, scaled to the slot
  const size=s.textNote*r/24;
  // where it sits, low on the right
  const x=c[0]+r*0.2;
  const y=c[1]+r*0.3;
  _=try d.number(x+1,y+1,size,s.countShadow,n);
  _=try d.number(x,y,size,if(n>0)s.white else s.dim,n);
}
/// a plain bulb: the seed and a pair of leaves (a structure with no `icon`).
pub fn plain(ic:Icon,c:Color)Allocator.Error!void{
  try ic.stem(.{.{0,topAt},.{0,0.3},.{0.02,0.45},.{0,0.6}},0.1,stemCol);
  try ic.leaf(.{0,0.55},0.5,0.4,0.22,sprout,0.9);
  try ic.leaf(.{0,0.5},m.pi-0.5,0.36,0.2,sprout,0.9);
  try ic.coat(c);
}
