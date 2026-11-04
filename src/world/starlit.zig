//! starlit patches: pools of light gathered from the stars, lying on and
//! beside the ley lines. The land is cut into square cells; each cell may
//! hold one patch, near a ley line, at a place, size, shape and richness
//! all drawn from the world's seed, so a patch is the same wherever and
//! whenever it is asked for, loaded or not. A patch never runs dry; the
//! richest gives about ten times the poorest. Most are a semi-ragged
//! splash, now and then a soft round pool.
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, clamps, ramps
const m=engine.core.math;
/// the lattice hash every patch's draws come from
const rng=engine.core.rng;
/// the noise its ragged rim wanders by
const noise=engine.core.noise;
/// the world generator, for where the ley lines run
const gen=lib.gen;
/// the test harness
const testing=std.testing;
/// a point on the ground (tiles, x across and y down)
const P2=m.Vec(f32,2);
/// how many tiles across a cell is
const cellTiles:i32=48;
/// how far in from a cell's edges its patch's line point stays (tiles):
/// with `beside`, two patches never come nearer than 30 m
const margin:i32=18;
/// the step a cell looks for a ley line in (tiles)
const leyStep:i32=3;
/// the share of cells a ley line crosses that hold a patch: the rest leave
/// longer gaps, so patches lie anywhere from about 30 to 120 m apart
const holds:f32=0.65;
/// how far a patch's middle may sit off its ley line (a share of its radius)
const beside:f32=0.5;
/// the smallest and largest radius a patch has (tiles): 3x3 to 10x10
const rMin:f32=1.5;
/// (the largest)
const rMax:f32=5;
/// the share of patches that are a soft round pool, not a splash
const poolShare:f32=0.2;
/// how far a splash's rim wanders in and out (a share of its radius)
const ragged:f32=0.28;
/// the wavelength of a splash's rim noise (tiles)
const raggedL:f32=2.5;
/// how much of a patch's radius fades softly to its rim
const soft:f32=0.35;
/// the yield a patch gives, a multiple of a plain one's: the poorest and
/// the richest (about ten times as much)
pub const yieldPoor:f32=0.3;
/// (the richest)
pub const yieldRich:f32=3;
/// one patch: where its middle lies, how far it reaches, how rich it is
pub const Patch=struct{
  /// its middle (tiles)
  at:P2,
  /// how far it reaches (tiles)
  r:f32,
  /// how rich it is, 0 the poorest .. 1 the richest
  rich:f32,
  /// a soft round pool rather than a splash
  pool:bool,
  /// its own draw 0..1, for what wanders in it
  seed:f32,
  /// how far inside it tile point `q` lies: 1 deep in it, fading to 0 at
  /// its rim, 0 beyond (a splash's rim wandering in and out)
  pub fn field(p:Patch,world:u64,q:P2)f32{
    // how far the point is from its middle, as a share of its radius
    const d=m.lenOf(f32,2,q-p.at)/p.r;
    if(d>1+ragged)return 0;
    // the rim here: round for a pool, wandering for a splash
    const rim=if(p.pool)1 else 1+ragged*noise.fbm(world+%41,q[0]/raggedL+p.seed*97,q[1]/raggedL,2);
    return 1-m.unlerp(rim*(1-soft),rim,d);
  }
  /// the yield it gives, a multiple of a plain one's
  pub fn yield(p:Patch)f32{return m.lerp(yieldPoor,yieldRich,p.rich);}
};
/// the cell holding tile point `q`
fn cellOf(q:P2)m.Vice(i32,2){
  return.{@intFromFloat(@floor(q[0]/m.f(cellTiles))),@intFromFloat(@floor(q[1]/m.f(cellTiles)))};
}
/// a draw 0..1 for cell (cx, cy), the `which`th
fn draw(world:u64,cx:i32,cy:i32,which:u64)f32{return rng.unit(rng.hash2(world+%(0x5a17+which),cx,cy));}
/// the patch cell (cx, cy) holds, if it holds one
pub fn inCell(world:u64,cx:i32,cy:i32)?Patch{
  if(draw(world,cx,cy,0)>holds)return null;
  // the cell's inner square, where its patch's line point may lie
  const x0=cx*cellTiles+margin;
  const y0=cy*cellTiles+margin;
  const span=cellTiles-2*margin;
  // a point in it the patch leans toward, drawn
  const want=P2{m.f(x0)+draw(world,cx,cy,1)*m.f(span),m.f(y0)+draw(world,cx,cy,2)*m.f(span)};
  // the ley tile in the inner square nearest that point, if a line crosses it
  var best:?P2=null;
  var bestD:f32=m.f(span*span*4);
  var y=y0;
  while(y<=y0+span):(y+=leyStep){
    var x=x0;
    while(x<=x0+span):(x+=leyStep){
      // the tile's middle, and how far it is from the wanted point
      const q=P2{m.f(x)+0.5,m.f(y)+0.5};
      const d=m.lenOf(f32,2,q-want);
      if(d>=bestD)continue;
      if(gen.plain(world,x,y).kind!=.ley)continue;
      best=q;
      bestD=d;
    }
  }
  const line=best orelse return null;
  // its size, richness (the rich ones rare) and shape
  const r=m.lerp(rMin,rMax,draw(world,cx,cy,3));
  const u=draw(world,cx,cy,4);
  // its middle: on the line or a little beside it
  const a=draw(world,cx,cy,5)*m.tau;
  const off=draw(world,cx,cy,6)*beside*r;
  return.{.at=line+P2{@cos(a)*off,@sin(a)*off},.r=r,.rich=u*u,.pool=draw(world,cx,cy,7)<poolShare,.seed=draw(world,cx,cy,8)};
}
/// the most patches that ever touch one stretch of ground asked about
pub const maxNear=32;
/// the patches touching a stretch of ground, gathered once so each tile in
/// it is read cheaply
pub const Near=struct{
  /// the world's seed
  world:u64,
  /// the patches gathered
  list:[maxNear]Patch=undefined,
  /// how many there are
  n:usize=0,
  /// the patches touching tiles [x0, x1) across and [y0, y1) down
  pub fn of(world:u64,x0:i32,y0:i32,x1:i32,y1:i32)Near{
    // the patches being gathered
    var out=Near{.world=world};
    // how far past a cell a patch may reach (tiles)
    const reach=rMax*(1+beside+ragged)+1;
    const lo=cellOf(.{m.f(x0)-reach,m.f(y0)-reach});
    const hi=cellOf(.{m.f(x1)+reach,m.f(y1)+reach});
    var cy=lo[1];
    while(cy<=hi[1]):(cy+=1){
      var cx=lo[0];
      while(cx<=hi[0]):(cx+=1){
        // this cell's patch, if it has one and it reaches the stretch
        const p=inCell(world,cx,cy) orelse continue;
        const far=p.r*(1+ragged);
        if(p.at[0]+far<m.f(x0) or p.at[0]-far>m.f(x1) or p.at[1]+far<m.f(y0) or p.at[1]-far>m.f(y1))continue;
        if(out.n==maxNear)return out;
        out.list[out.n]=p;
        out.n+=1;
      }
    }
    return out;
  }
  /// the patches gathered
  pub fn all(nr:*const Near)[]const Patch{return nr.list[0..nr.n];}
  /// how far inside a patch tile (wx, wy) lies (0..1), and that patch,
  /// the deepest of those it lies in
  pub fn at(nr:*const Near,wx:i32,wy:i32)Hit{return nr.atPoint(.{m.f(wx)+0.5,m.f(wy)+0.5});}
  /// how far inside a patch ground point `q` (tiles) lies (0..1), and that
  /// patch, the deepest of those it lies in
  pub fn atPoint(nr:*const Near,q:P2)Hit{
    // the deepest patch so far
    var hit=Hit{};
    for(nr.all())|p|{
      const f=p.field(nr.world,q);
      if(f>hit.field)hit=.{.field=f,.rich=p.rich,.yield=p.yield()};
    }
    return hit;
  }
};
/// what a tile holds of a patch: how far inside it, how rich it is and the
/// yield it gives (all 0 off any patch)
pub const Hit=struct{
  /// how far inside, 0..1
  field:f32=0,
  /// how rich, 0..1
  rich:f32=0,
  /// the yield it gives, a multiple of a plain one's (0 off a patch)
  yield:f32=0,
};
test"a patch lies on or beside a ley line, its size and richness in range"{
  // a wide stretch's patches
  const nr=Near.of(1234,-400,-400,400,400);
  try testing.expect(nr.n>3);
  for(nr.all())|p|{
    try testing.expect(p.r>=rMin and p.r<=rMax);
    try testing.expect(p.rich>=0 and p.rich<=1);
    // a ley tile near its middle
    var found=false;
    const cx:i32=@intFromFloat(@floor(p.at[0]));
    const cy:i32=@intFromFloat(@floor(p.at[1]));
    const s:i32=@intFromFloat(@ceil(p.r*beside)+1);
    var y=cy-s;
    while(y<=cy+s):(y+=1){
      var x=cx-s;
      while(x<=cx+s):(x+=1)if(gen.plain(1234,x,y).kind==.ley){found=true;};
    }
    try testing.expect(found);
    // deep in at its middle, nothing past its rim
    try testing.expectEqual(@as(f32,1),p.field(1234,p.at));
    try testing.expectEqual(@as(f32,0),p.field(1234,p.at+P2{p.r*(1+ragged)+0.01,0}));
  }
}
test"patches lie at least 30 m apart, and the same every time"{
  // two gatherings of the same stretch
  const a=Near.of(77,-300,-300,300,300);
  const b=Near.of(77,-300,-300,300,300);
  try testing.expectEqual(a.n,b.n);
  for(a.all(),0..)|p,i|{
    try testing.expectEqual(p.at,b.list[i].at);
    for(a.all()[0..i])|q|try testing.expect(m.lenOf(f32,2,p.at-q.at)>=30);
  }
}
test"the richest patch gives ten times the poorest"{
  try testing.expectApproxEqAbs(@as(f32,10),yieldRich/yieldPoor,1e-4);
}
