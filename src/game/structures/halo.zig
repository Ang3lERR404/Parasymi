//! the halo a diamond projects: not a structure itself, but what a diamond
//! shows and holds, while its four blooms are drawn in and once it has
//! formed. `seek` finds four grown blooms in a cross and puts a diamond
//! down forming at its heart. The diamond fragments light into a
//! ring floating `reachTiles` tiles around it at a bloom's hover: a
//! projection of light rays thrown up and out from the crystal
//! (`haloProjection`) and the ring they make (`haloRing`), its light split
//! into a spectrum across its width, red at its inner edge, as an ice
//! halo's is, with swells and motes of light running round it as along the
//! blooms' beams. The ring passes through the four points (east, south,
//! west, north) the blooms stood on; an arc is as bright as the points at
//! its ends, a point dimming to `dim` without a grown bloom on it. The ring
//! is a field of celestial energy over its disc; a formed diamond holds a
//! wider one.
//!
//! How far the halo has come, `k` (0 the blooms leave their points .. 1
//! they meet; past 1, `form`s since), goes to the GPU with each instance:
//! the blooms' spiral, the crystal gathering from its shards and the
//! projection reaching out all follow it there (common.glsl `haloSpiral`).
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type every drawing call may fail with
const Allocator=std.mem.Allocator;
/// all the maths: vectors, matrices, easing
const m=lib.engine.core.math;
/// the garden's tile world, where the blooms stand
const World=lib.world.World;
/// the species registry, for the bloom's hover and radiance
const species=lib.species;
/// the garden's plants, among them the blooms on the points
const Plants=lib.plants.Plants;
/// the scene's list of moving parts the halo adds to each frame
const Parts=lib.parts.Parts;
/// the structures registry: the diamond a halo puts down, the hooks' context
const st=lib.structures;
/// every player-facing string
const txt=lib.txt;
/// the ring's radius, tiles: the blooms' points lie this far out along the
/// axes, on it
pub const reachTiles:i32=5;
/// the points in order around the ring (east, south, west, north); arc k
/// runs from point k to k+1
pub const points=[4]m.Vice(i32,2){.{1,0},.{0,1},.{-1,0},.{0,-1}};
/// a bloom holds a point when grown and healthier than this (0..1)
const activeHealth:f32=0.5;
/// seconds the blooms take to reach the centre
pub const form:f32=5;
/// the flash where they meet spreads and fades over this many seconds
pub const flash:f32=1.4;
/// a formed diamond's field reaches this far, tiles (the ring's is `reachTiles`)
pub const diamondR:f32=7;
/// how sharply the blooms' spiral rushes in at its end (common.glsl `HALO_RUSH`)
const rush:f32=4;
/// how many times round they wind on the way in (common.glsl `HALO_TURNS`)
const turns:f32=1.25;
/// the last share of the way over which a bloom folds shut (common.glsl `HALO_FOLD`)
const fold:f32=0.3;
/// the diamond's point of light: warm, reaching past the ring as it forms
const diamondLight=m.V3{1.0,0.93,0.82};
/// how far that light reaches, tiles
const diamondReach:f32=6;
/// the flash's point of light: a burst, fading as it spreads
const flashLight=m.V3{6.0,5.6,5.0};
/// how far that burst reaches, tiles
const flashReach:f32=16;
/// the diamond floats at the centre of the ring, where the blooms' cross
/// of beams meets: as high as they hang, the ring with it
pub const hover:f32=species.get(.bloom).hover;
/// the projection's least rise (level, its cone would be flat)
const level:f32=0.02;
/// how bright a point's arcs are without a bloom (1 with one)
pub const dim:f32=0.3;
/// how quickly a point's light follows whether a bloom holds it (per second)
const lightEase:f32=0.4;
/// where a forming halo (`halo`: its centre xyz, how far along w; w < 0
/// none) has drawn a point riding with one of its blooms, and how far that
/// bloom is still open: the CPU's twin of common.glsl `haloSpiral` and
/// `haloFold`
pub fn spiral(p:m.V3,halo:m.Vice(f32,4))struct{at:m.V3,open:f32}{
  if(halo[3]<0)return.{.at=p,.open=1};
  // how far along it is, and how far it has pulled in (rushing at the end)
  const k=m.clamp01(halo[3]);
  const pull=(@exp(rush*k)-1)/(@exp(rush)-1);
  // how far round it has wound, and the halo's centre
  const a=turns*m.tau*pull;
  const ctr=m.v3(halo[0],halo[1],halo[2]);
  // the point's offset from the centre, and that winding's cosine and sine
  const d=p-ctr;
  const c=@cos(a);
  const s=@sin(a);
  // the point turned round the centre and drawn in toward it
  const at=ctr+m.v3(d[0]*c-d[2]*s,d[1],d[0]*s+d[2]*c)*m.splat3(1-pull);
  return.{.at=at,.open=1-m.smooth(m.clamp01((k-(1-fold))/fold))};
}
/// the tile of the ring's point `k` round a centre at (x, y)
pub fn pointAt(x:i32,y:i32,k:usize)m.Vice(i32,2){
  return.{x+points[k][0]*reachTiles,y+points[k][1]*reachTiles};
}
/// finds four grown blooms on the points of a ring round a tile no diamond
/// hangs over yet, and puts a diamond down there, born of the halo they
/// form: they spiral in to it. Returns whether one began.
pub fn seek(ctx:st.Ctx)Allocator.Error!bool{
  // the plants' columns
  const s=ctx.plants.list.slice();
  for(s.items(.sp),s.items(.x),s.items(.y),0..)|sp,x,y,i|{
    if(species.get(sp).radiance<=0 or s.items(.growth)[i]<1)continue;
    // taken as the ring's east point: the heart west of it
    const cx=x-points[0][0]*reachTiles;
    const cy=y-points[0][1]*reachTiles;
    if(ctx.ss.floaterAt(cx,cy)!=null)continue;
    // whether every point holds a grown bloom
    var all=true;
    for(0..4)|k|all=all and active(ctx.plants,ctx.w,pointAt(cx,cy,k));
    if(!all)continue;
    if(!try ctx.ss.place(ctx.gpa,ctx.w,cx,cy,.diamond,0,0.45))continue;
    // the diamond just put down: born whole, its blooms coming in
    const d=ctx.ss.get(.of(ctx.ss.list.items.len-1));
    d.grown=1;
    d.state.diamond.born=.halo;
    ctx.g.say(txt.s.msg.haloForms,.{});
    return true;
  }
  return false;
}
/// whether a grown, unwithered celestial bloom stands at a tile
pub fn active(p:*const Plants,w:*const World,at:m.Vice(i32,2))bool{
  // the plant there, its index, and the plant list
  const id=p.at(w,at[0],at[1]) orelse return false;
  const i=id.idx();
  const s=p.list.slice();
  return species.get(s.items(.sp)[i]).radiance>0 and s.items(.growth)[i]>=1 and s.items(.health)[i]>activeHealth;
}
/// ease each point's light toward whether a grown bloom holds it (1) or
/// not (`dim`).
pub fn relight(light:*m.Vice(f32,4),p:*const Plants,w:*const World,x:i32,y:i32,dt:f32)void{
  for(light,0..)|*l,k|{
    // where this point's light is heading
    const want:f32=if(active(p,w,pointAt(x,y,k)))1 else dim;
    l.*+=(want-l.*)*@min(1,dt*lightEase);
  }
}
/// how many points shine as with a bloom (brighter than halfway from `dim` to 1)
pub fn lit(light:m.Vice(f32,4))u32{
  // the count so far
  var n:u32=0;
  for(light)|l|{if(l>(1+dim)/2)n+=1;}
  return n;
}
/// the diamond at `at`, its projection and ring (over the ground at
/// `ground`) and, just as it forms, the flash, for a halo `k` along (see
/// the module notes). The diamond is still: it never sways.
pub fn draw(out:*Parts,seed:f32,at:m.V3,ground:m.V3,k:f32,light:m.Vice(f32,4))Allocator.Error!void{
  // the halo passed to the GPU: its centre and how far along
  const halo=m.Vice(f32,4){at[0],at[1],at[2],k};
  try out.emit(.haloDiamond,m.chain(&.{m.translate(at),m.rotY(seed*m.tau)}),.{.phase=seed,.halo=halo});
  // the ring floats at a bloom's hover over the ground at the centre, the
  // diamond at its heart, so its rays run level out to it
  const ring=ground+m.v3(0,hover,0);
  // the ring's radius, tiles
  const r=m.f(reachTiles);
  try out.emit(.haloProjection,m.chain(&.{m.translate(at),m.scale3(m.v3(r,@max(ring[1]-at[1],level),r))}),.{.glow=1,.phase=seed,.halo=halo});
  try out.emit(.haloRing,m.chain(&.{m.translate(ring),m.scale3(m.v3(r,1,r))}),.{.glow=1,.phase=seed,.tint=light,.halo=halo});
  // how far the flash has spread, 0..1 (outside that, no flash)
  const age=(k-1)*form/flash;
  if(age>=0 and age<1)try out.emit(.haloFlash,m.translate(at),.{.glow=1,.flutter=age});
  // the diamond holds the light it gathers, more as it forms; as it does,
  // the flash bursts out over the garden
  const formed=@sqrt((@exp(rush*m.clamp01(k))-1)/(@exp(rush)-1));
  try out.light(at,diamondLight*m.splat3(formed),diamondReach);
  if(age>=0 and age<1)try out.light(at,flashLight*m.splat3((1-age)*(1-age)),flashReach);
}
