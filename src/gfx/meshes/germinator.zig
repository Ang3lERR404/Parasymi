//! mesh: GERMINATOR. a small tree that weaves: a fine woven trunk
//! buttressed into its roots, its crown splitting into five boughs that rise round a core
//! of resin sap held up in a calyx, then arch over it and hold their flower
//! cups out above it. Each bough strays its own way and carries twigs at
//! uneven heights, so its crown is crowded and uneven, as a tree's is. The structure tips the cups to pour the essences it
//! weaves from into the core (`cup`, `pool`, `pour`), spins them round the
//! sapwood spindle running up through it (`core`, `vortex`) and winds a
//! seed of them on the spindle (`thread`, `seed`, `winding`); those pieces
//! are emitted by it, each built here in its own space. `whole` is all of
//! it at rest: the placement preview.
//! It grows on hidden growth splines (gfx/growth.zig): the trunk with its
//! roots spreading, the foot leaves unfolding as it passes, then the
//! boughs, calyx and spindle off its crown, the twigs off the boughs, and
//! last (`form`) the cups and core, which carry that window themselves.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error a mesh build may fail with
const Allocator=std.mem.Allocator;
/// the engine package: maths, colours, rng, the builder underneath
const engine=lib.engine;
/// all the maths: vectors, matrices, easing
const m=engine.core.math;
/// the plant-piece mesher: braids, petals, lofts, the builder itself
const mg=lib.meshgen;
/// the garden's palette: vine, core, leaves, sapwood
const pal=lib.palette;
/// the structure kit: root mats, foot leaves, leafy vines and resin pods
const kit=lib.structureKit;
/// colour conversions, for the cups' greens and creams
const color=engine.core.color;
/// the seeded random stream each bough's leaf fan is splayed by
const Rng=engine.core.rng.Rng;
/// the garden's growth timing: the hidden splines the tree grows along
const growth=lib.growth;
/// a point or direction in space
const V3=m.V3;
/// makes a point in space from three numbers
const v3=m.v3;
/// how tall the tree stands (to the top of its cups)
pub const tall:f32=1.8;
/// how many boughs rise off the crown, each holding one cup
pub const boughs=5;
/// where the trunk splits into its boughs
const trunkH:f32=0.62;
/// the core of resin sap the boughs rise round, held in the calyx
pub const coreAt=v3(0,1.0,0);
/// the core's half-sizes along x, y and z
pub const coreRadius=v3(0.27,0.29,0.27);
/// where the streams fall into the core: its crown
pub const coreTop=coreAt+v3(0,coreRadius[1]*0.8,0);
/// the bough tips the cups stand on: this far out from the trunk's axis
/// (tiles)
const tipOut:f32=0.38;
/// how high the bough tips stand (tiles)
const tipY:f32=1.64;
/// a cup's lip, where it pours from (in its own space: its spout toward
/// +x, opening up +y)
pub const cupLip=v3(0.11,0.095,0);
/// the seed spun on the spindle: its radius at its fullest
pub const seedR:f32=0.08;
/// the seed's shape: how much taller than wide it is
const seedTall:f32=1.28;
/// how much it is drawn in toward a point at its crown (0 round, 1 a point)
const seedPoint:f32=0.35;
/// the cup's green heart
const cupHeart=color.rgb(0.34,0.5,0.24);
/// the cream its petals' rims turn to
const cupRim=color.rgb(0.86,0.8,0.52);
/// the pale cream of its stamens
const cupStamen=color.rgb(0.82,0.78,0.6);
/// essence is coloured per instance (the item it is): white under its tint
const essenceWhite=color.rgb(1,1,1).toRgba8(255);
/// the last share of its growth, once the tree is grown, over which its
/// cups and core form (they are emitted, so carry it in their vertices)
pub const form:f32=0.2;
/// the trunk grows this slowly per unit of its length (a growth spline's pace)
const trunkPace:f32=1.4;
/// where up the trunk the boughs leave it (0..1)
const boughFrom:f32=0.92;
/// where up the trunk the foot leaves unfold (0..1)
const footAt:f32=0.1;
/// how much later each sepal of the calyx opens than the one before
const sepalStagger:f32=0.03;
/// bough `k`'s heading round the trunk
pub fn boughAngle(k:usize)f32{return m.ratio(k,boughs)*m.tau+0.3;}
/// where bough `k`'s cup stands
pub fn tip(k:usize)V3{
  // the bough's heading round the trunk (radians)
  const a=boughAngle(k);
  return v3(@cos(a)*tipOut,tipY,@sin(a)*tipOut);
}
/// turns a cup's own space so its spout faces in, toward the core, from bough `k`
pub fn cupFacing(k:usize)f32{return-(boughAngle(k)+m.pi);}
/// builds the tree alone: what the structure grows; cups and core are its own
pub fn build(b:*mg.Builder)Allocator.Error!void{try tree(b);}
/// lays the whole grown tree on one growth skeleton: trunk, roots, foot
/// leaves, the five boughs, the calyx and the spindle, leaving the last
/// `form` of the growth for the emitted cups and core
fn tree(b:*mg.Builder)Allocator.Error!void{
  // the growth skeleton the whole tree is hung on
  var sk=growth.Skeleton.begin(b);
  sk.tail=form;
  // the trunk's spline, which roots, boughs, calyx and spindle all leave
  const stem=try trunk(b,&sk);
  try kit.rootMat(b,11,1.15,0.07,0x6E41,.{.k=&sk,.id=stem});
  try kit.footLeaves(b,10,0.32,0.52,0.2,0x6E42,.{.k=&sk,.id=stem,.u=footAt});
  for(0..boughs)|k|try bough(b,&sk,stem,k);
  try calyx(b,&sk,stem);
  try spindle(b,&sk,stem);
  sk.finish(b);
}
/// the trunk: strands woven round a dark core, flared where it roots,
/// leaning a little as anything grown does; its growth spline
fn trunk(b:*mg.Builder,sk:*growth.Skeleton)Allocator.Error!growth.Id{
  // how many rings run up the trunk
  const steps=growth.res;
  // the trunk's control points: a wobbling rise, its top set straight over its foot
  var ctrl:[5]V3=undefined;
  mg.growthPath(.{.start=v3(0,0,0),.direction=v3(0,1,0),.length=trunkH+0.06,.wobble=0.45,.seed=0x6E43},&ctrl);
  ctrl[ctrl.len-1]=v3(0,trunkH+0.06,0);
  // the trunk's spline, and its resampled points
  const stem=sk.trunk(&ctrl,.{.pace=trunkPace});
  // the trunk's resampled points, ring by ring
  const spine=&sk.get(stem).pts;
  // each ring's growth timing (by height) and radius
  var ts:[steps]f32=undefined;
  var rs:[steps]f32=undefined;
  for(&ts,&rs,spine,0..)|*t,*r,p,i|{
    // how far up the trunk this ring is (0..1)
    const k=m.ratio(i,steps-1);
    t.*=p[1]/tall;
    r.*=0.08+0.13*@exp(-k*7)-0.012*k;
  }
  // where the braid's vertices begin, so it rises along the trunk
  const s=b.mark();
  try mg.braid(b,spine,&ts,&rs,6,2.6,pal.strandWobble,0x6E44,pal.core,pal.vine);
  try sk.along(b,s,stem);
  return stem;
}
/// bough `k`: out of the trunk's crown, twisting a little as it rises
/// round the core (clear of it), out and up, then arching over to hold its
/// cup up above the core. Leaves along it and a leafy twig off its back.
fn bough(b:*mg.Builder,sk:*growth.Skeleton,stem:growth.Id,k:usize)Allocator.Error!void{
  // this bough's own seeded rng: its strays, its twigs, its leaf fan
  var rng=Rng.init(0x6E90+%k);
  // the bough's heading round the trunk (radians)
  const a=boughAngle(k);
  // (out from the axis, height) at each control point
  const at=[_]m.Vice(f32,2){
    .{0.04,trunkH-0.02},.{0.17,0.72},.{0.32,0.87},.{0.39,1.04},
    .{0.43,1.26},.{0.47,1.47},.{0.47,1.6},.{tipOut,tipY},
  };
  // the bough's control points, laid from `at` round its heading
  var ctrl:[at.len]V3=undefined;
  for(&ctrl,at,0..)|*c,p,j|{
    // it winds a little round the core on its way up, ending at its heading
    const ph=a-0.4*(1-m.ratio(j,at.len-1));
    c.*=v3(@cos(ph)*p[0],p[1],@sin(ph)*p[0]);
    // each bough strays from the others between its ends
    if(j>0 and j<at.len-1)c.*+=v3(rng.range(-0.05,0.05),rng.range(-0.06,0.06),rng.range(-0.05,0.05));
  }
  mg.grow(&ctrl,.{.start=ctrl[0],.direction=m.norm(ctrl[at.len-1]-ctrl[0]),.length=m.dist(ctrl[at.len-1],ctrl[0]),.wobble=0.22,.seed=0x6E50+%k*31});
  // the tip stays where the cup stands
  ctrl[at.len-1]=tip(k);
  // the bough's own spline, leaving the trunk near its top
  const id=sk.branch(stem,boughFrom,&ctrl,.{});
  // how many rings run along the bough
  const steps=growth.res;
  // the bough's resampled points
  const path=&sk.get(id).pts;
  // each ring's growth timing (by height) and radius, tapering
  var ts:[steps]f32=undefined;
  var rs:[steps]f32=undefined;
  mg.taperRadii(0.044,0.3,&rs);
  for(&ts,path)|*t,p|t.*=p[1]/tall;
  // where the braid's vertices begin, so it rises along the bough
  const s=b.mark();
  try mg.braid(b,path,&ts,&rs,3,3.2,pal.strandWobble,0x6E60+%k*7,pal.core,pal.vine);
  try sk.along(b,s,id);
  try sk.leaves(b,id,.{.n=11,.len=0.24,.width=0.08,.from=0.2,.to=0.95,.t0=ts[0],.t1=ts[steps-1],.col=pal.leafDark,.tip=pal.leafLite,.seed=0x6E70+%k*11});
  // the crown: a twig off the bough's back, leaning out and up, and a
  // fan of leaves behind the cup
  // the way out from the trunk along this bough's heading, flat
  const out=v3(@cos(a),0,@sin(a));
  // twigs off the bough at uneven heights, each leaning its own way
  for(0..3)|j|{
    // where this twig leaves the bough, which side it leans to, and how far it reaches
    const u=m.lerp(0.3,0.72,m.ratio(j,2))+rng.range(-0.05,0.05);
    const from=m.alongPath(path,u);
    const lean=v3(-out[2],0,out[0])*m.splat3(rng.range(-0.45,0.45));
    const reach=rng.range(0.28,0.42);
    try kit.leafyVine(b,from,from+(out+lean)*m.splat3(reach)+v3(0,rng.range(0.08,0.3),0),rng.range(0.014,0.02),rng.range(0.15,0.3),7,from[1]/tall,m.lerp(0.8,1,u),0x6E80+%k*13+%j*101,.{.k=sk,.id=id,.u=u});
  }
  // where the fan of leaves sits, just behind the cup
  const behind=m.alongPath(path,0.9);
  // how many leaves fan out behind it
  const fan:usize=5;
  for(0..fan)|i|{
    // how far this leaf leans to one side: left, centre, right, jittered
    const side=v3(-out[2],0,out[0])*m.splat3((m.f(i)-0.5*m.f(fan-1))*1.4/m.f(fan-1)+rng.range(-0.1,0.1));
    // which way the leaf points: out, to its side and up
    const dir=m.norm(out+side+v3(0,0.7,0));
    // where its vertices begin, so it unfolds as the bough passes
    const s1=b.mark();
    try mg.natural(b,behind,dir,0.27*rng.range(0.85,1.1),0.1,0.55,pal.leafDark,pal.leafLite,behind[1]/tall,.stalked);
    try sk.on(b,s1,id,0.9,.{.from=behind});
  }
}
/// the calyx on the trunk's crown: broad sepals cupped up round the
/// core's lower half, holding it
fn calyx(b:*mg.Builder,sk:*growth.Skeleton,stem:growth.Id)Allocator.Error!void{
  // the sepals' own stream: a natural calyx's are each their own length
  var rng=Rng.init(0x6EC0);
  // where the sepals spring from, just above the trunk's top
  const heart=v3(0,trunkH+0.03,0);
  for(0..6)|i|{
    // this sepal's angle round the heart, and the way out along it
    const a=(m.f(i)+0.5)/6*m.tau;
    // the way out along this sepal, flat
    const out=v3(@cos(a),0,@sin(a));
    // where its vertices begin, so it opens in its turn
    const s=b.mark();
    try mg.petal(b,.{
      .base=heart+out*m.splat3(0.05),.out=out,.len=0.3*rng.range(0.85,1.15),.width=0.14,
      .rise=0.85,.flare=0.25,.cup=0.5,
      .col=pal.leafDark,.tip=pal.leafLite,.t=heart[1]/tall,.part=.leaf,
    });
    try sk.on(b,s,stem,1,.{.from=heart+out*m.splat3(0.05),.delay=sepalStagger*m.f(i)});
  }
}
/// the spindle: a sapwood needle up through the core, from the calyx's
/// heart to just over the core's crown, tapering to a point at both ends
fn spindle(b:*mg.Builder,sk:*growth.Skeleton,stem:growth.Id)Allocator.Error!void{
  // how many rings run along the spindle
  const steps=growth.res;
  // the spindle's top: just over the core's crown
  const y1=coreAt[1]+coreRadius[1]+0.1;
  // the spindle's own spline, straight up off the trunk's crown
  const id=sk.branch(stem,1,&.{v3(0,trunkH,0),v3(0,y1,0)},.{});
  // its resampled points
  const path=&sk.get(id).pts;
  // each ring's growth timing (by height) and radius, pointed at both ends
  var ts:[steps]f32=undefined;
  var rs:[steps]f32=undefined;
  for(&ts,&rs,path,0..)|*t,*r,p,i|{
    // how far up the spindle this ring is (0..1)
    const k=m.ratio(i,steps-1);
    t.*=p[1]/tall;
    r.*=@max(0.014*@sqrt(@sin(m.pi*k)),2e-4);
  }
  // where the spindle's vertices begin, so it rises along its spline
  const s=b.mark();
  try b.tubeR(path,&ts,&rs,pal.sapwood,.stem,6);
  try sk.along(b,s,id);
}
/// mesh: GERMINATOR CUP. a flower cup on a bough's tip, opening up +y, its
/// spout petal reaching out along +x (where it pours from, `cupLip`),
/// stamens rising from its heart.
pub const cup=struct{
  /// builds the cup: a small green bulb, seven petals cupped round it (the
  /// first the longer spout), stamens rising, all tagged to open in `form`
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // where the cup's vertices begin, so it all opens together
    const s=b.mark();
    try mg.ellipsoid(b,.{.center=v3(0,0.012,0),.radii=v3(0.036,0.03,0.036),.col=pal.vine,.rings=5,.segs=8,.t=0.95});
    // how many petals ring the cup
    const n=7;
    for(0..n)|i|{
      // this petal's angle round the cup (radians), and the way out along it
      const a=m.ratio(i,n)*m.tau;
      // the way out along this petal, flat
      const out=v3(@cos(a),0,@sin(a));
      // whether this is the spout petal, longer and more flared
      const spout=i==0;
      try mg.petal(b,.{
        .base=v3(0,0.01,0)+out*m.splat3(0.02),.out=out,
        .len=if(spout)0.14 else 0.12,.width=if(spout)0.05 else 0.06,
        .rise=1.15,.flare=if(spout)0.9 else 0.45,.cup=0.55,
        .col=cupHeart.toRgba8(255),.tip=cupRim.toRgba8(255),.t=0.97,.part=.leaf,
      });
    }
    try mg.stamens(b,.{
      .heart=v3(0,0.02,0),.axis=v3(0,1,0),.n=6,.len=0.075,.r=0.004,.anther=0.016,
      .lean=0.22,.arch=0.3,.col=cupStamen.toRgba8(255),.t=0.97,.seed=0x6EA0,
    });
    // it opens on its bough's tip as the tree finishes
    try growth.tag(b,s,v3(0,0,0),growth.tailWindow(form));
  }
};
/// mesh: GERMINATOR POOL. the essence standing in a cup: a lens of it, a
/// unit across (scaled by how much there is). Still (tu.x < 0).
pub const pool=struct{
  /// builds the pool: a flat white lens of still essence, tagged to form in `form`
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // where the pool's vertices begin, so it forms with the cup
    const s=b.mark();
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(1,0.22,1),.col=essenceWhite,.part=.essence,.rings=5,.segs=10,.t=-1});
    try growth.tag(b,s,v3(0,0,0),growth.tailWindow(form));
  }
};
/// mesh: GERMINATOR POUR. a stream of essence poured from a cup into the
/// core, running straight up +y over 0..1 (tu.x the way it flows); placed
/// along its fall as a curve (part.vert). It leaves the lip full, narrows
/// as it falls, and closes to a point at both ends.
pub const pour=struct{
  /// builds the stream: a tube up +y from 0 to 1, thinning as it falls and
  /// pointed at both ends, white essence the instance tints
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // how many rings run along the stream
    const steps=24;
    // the stream's path, its flow (tu.x) and its radius, ring by ring
    var path:[steps]V3=undefined;
    var ts:[steps]f32=undefined;
    var rs:[steps]f32=undefined;
    for(&path,&ts,&rs,0..)|*p,*t,*r,i|{
      // how far along the stream this ring is (0..1)
      const k=m.ratio(i,steps-1);
      p.*=v3(0,k,0);
      t.*=k;
      r.*=@max(0.017*(1-0.45*k)*m.pow(f32,@sin(m.pi*k),0.3),2e-4);
    }
    try b.tubeR(&path,&ts,&rs,essenceWhite,.essence,6);
  }
};
/// mesh: GERMINATOR VORTEX. one arm of the whirl spun in the core: a
/// standing ribbon of essence spiralling in from the core's wall to the
/// spindle, sinking as it goes as a whirlpool does (tu.x 0 at the wall ..
/// 1 at the spindle). The structure turns one per essence round the axis.
pub const vortex=struct{
  /// builds the arm: a lofted ribbon spiralling 1.3 turns from the wall in to
  /// the spindle, sinking and narrowing as it goes, white essence
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // how many rings run along the arm
    const steps=28;
    // the arm's path, its flow, its width and its height, ring by ring
    var path:[steps]V3=undefined;
    var ts:[steps]f32=undefined;
    var ws:[steps]f32=undefined;
    var hs:[steps]f32=undefined;
    for(&path,&ts,&ws,&hs,0..)|*p,*t,*w,*h,i|{
      // how far in along the arm this ring is (0..1)
      const u=m.ratio(i,steps-1);
      // its distance from the axis, closing in toward the spindle
      const r=m.lerp(0.225,0.03,m.pow(f32,u,0.75));
      // its angle round the axis (radians)
      const a=u*1.3*m.tau;
      p.*=v3(@cos(a)*r,m.lerp(0.06,-0.07,u),@sin(a)*r);
      t.*=u;
      // how much its ends are drawn in to a point
      const ends=@sqrt(@sin(m.pi*m.lerp(0.04,0.96,u)));
      w.*=0.011*ends;
      h.*=m.lerp(0.075,0.03,u)*ends;
    }
    try mg.loft(b,&path,&ts,&ws,&hs,v3(0,1,0),ring,essenceWhite,.essence,8);
  }
  /// the ribbon's cross-section: a plain circle, which the width and height
  /// stretch into an upright oval
  fn ring(a:f32)m.Vice(f32,2){return.{@cos(a),@sin(a)};}
};
/// mesh: GERMINATOR THREAD. a thread of essence drawn off the whirl and
/// wound in onto the seed: spiralling from the core's wall in to the
/// spindle (tu.x 0 .. 1), tapering to a point at both ends.
pub const thread=struct{
  /// builds the thread: a fine tube spiralling 1.6 turns from the wall in to
  /// the seed, dipping a little, white essence pointed at both ends
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // how many rings run along the thread
    const steps=32;
    // the thread's path, its flow and its radius, ring by ring
    var path:[steps]V3=undefined;
    var ts:[steps]f32=undefined;
    var rs:[steps]f32=undefined;
    for(&path,&ts,&rs,0..)|*p,*t,*r,i|{
      // how far along the thread this ring is (0..1)
      const u=m.ratio(i,steps-1);
      // its distance from the axis, closing in to the seed's girth
      const rad=m.lerp(0.2,seedR*0.75,m.smooth(u));
      // its angle round the axis (radians)
      const a=u*1.6*m.tau;
      p.*=v3(@cos(a)*rad,0.05*(1-u)+0.025*@sin(m.pi*u),@sin(a)*rad);
      t.*=u;
      r.*=@max(0.0055*@sqrt(@sin(m.pi*u)),2e-4);
    }
    try b.tubeR(&path,&ts,&rs,essenceWhite,.essence,5);
  }
};
/// the seed's surface, its unit size: a point at `th` down from its crown,
/// `ph` round it
fn seedAt(th:f32,ph:f32,out:f32)V3{
  // the height at that angle, on the seed's stretched egg
  const y=@cos(th)*seedTall;
  // how much it is drawn in here: more toward the crown
  const narrow=1-seedPoint*m.smooth(m.clamp01(y/seedTall));
  return v3(@sin(th)*@cos(ph)*narrow*out,y*out,@sin(th)*@sin(ph)*narrow*out);
}
/// mesh: GERMINATOR SEED. the kernel spun on the spindle, a unit across:
/// an egg drawn to a point at its crown. Still essence (tu.x < 0),
/// coloured as the seed being woven.
pub const seed=struct{
  /// builds the seed: a tall white egg of still essence, its upper half
  /// drawn in toward a point at its crown
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // where the seed's vertices begin, so only they are drawn in
    const start=b.mark();
    try mg.ellipsoid(b,.{.center=v3(0,0,0),.radii=v3(1,seedTall,1),.col=essenceWhite,.part=.essence,.rings=8,.segs=10,.t=-1});
    // drawn to its point: a smooth field of height, so shared vertices move alike
    for(b.v.items[start..])|*vx|{
      // how much this vertex is drawn in, by its height
      const narrow=1-seedPoint*m.smooth(m.clamp01(vx.pos[1]/seedTall));
      vx.pos[0]*=narrow;
      vx.pos[2]*=narrow;
    }
  }
};
/// mesh: GERMINATOR WINDING. one essence's thread wound round the seed,
/// crown to foot, as on a spindle (tu.x the way it is wound on), the seed's
/// unit size; the structure tilts one per essence so they cross.
pub const winding=struct{
  /// builds the winding: a tube wound 3.5 turns round the seed's surface
  /// from near its crown to near its foot, white essence, pointed at both ends
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // how many rings run along the winding
    const steps=48;
    // the winding's path, its flow and its radius, ring by ring
    var path:[steps]V3=undefined;
    var ts:[steps]f32=undefined;
    var rs:[steps]f32=undefined;
    for(&path,&ts,&rs,0..)|*p,*t,*r,i|{
      // how far along the winding this ring is (0..1)
      const u=m.ratio(i,steps-1);
      p.*=seedAt(m.lerp(0.3,m.pi-0.25,u),u*3.5*m.tau,1.05);
      t.*=u;
      r.*=@max(0.075*@sqrt(@sin(m.pi*u)),2e-4);
    }
    try b.tubeR(&path,&ts,&rs,essenceWhite,.essence,5);
  }
};
/// mesh: GERMINATOR CORE. the core of resin sap at its own origin; the
/// structure turns it with what spins inside it, so its bubbles swirl too.
/// Thinner than a pod's resin (it never thickens past `coreThin` toward
/// its base), so what spins in it shows through.
pub const core=struct{
  /// how thin the resin is at its thinnest: its base's thickness (0..1)
  const coreThin:f32=0.55;
  /// builds the core: a resin pod at its origin, thinned throughout, tagged
  /// to swell up out of the calyx in `form`
  pub fn build(b:*mg.Builder)Allocator.Error!void{
    // where the core's vertices begin, so only they are thinned and tagged
    const start=b.mark();
    try kit.resinPod(b,v3(0,0,0),coreRadius,12,16);
    for(b.v.items[start..])|*vx|vx.tu[1]=m.lerp(coreThin,1,vx.tu[1]);
    // it swells up out of the calyx as the tree finishes
    try growth.tag(b,start,v3(0,-coreRadius[1],0),growth.tailWindow(form));
  }
};
/// mesh: GERMINATOR (whole). the tree with its core and cups at rest: what
/// the gardener sees before putting one down.
pub const whole=struct{
  /// builds the whole tree, then sets the core in it and a cup on each bough's
  /// tip, turned so each spout faces in
  pub fn build(b:*mg.Builder)Allocator.Error!void{try wholeOf(b);}
};
/// the whole tree, its core set in it and a cup on each
/// bough's tip, turned so each spout faces in
fn wholeOf(b:*mg.Builder)Allocator.Error!void{
  try tree(b);
  // where the next piece's vertices begin, so it alone is moved into place
  var s=b.mark();
  try core.build(b);
  b.xform(s,m.translate(coreAt));
  for(0..boughs)|k|{
    s=b.mark();
    try cup.build(b);
    b.xform(s,m.chain(&.{m.translate(tip(k)),m.rotY(cupFacing(k))}));
  }
}
