//! the halo a diamond projects: not a structure itself, but what the polyp
//! (while its blooms are drawn in and the diamond forms) and the diamond
//! (once it has) both show and hold. The diamond fragments light into a
//! ring floating `R` tiles around it at a bloom's hover: a projection of
//! light rays thrown up and out from the crystal (`halo_projection`) and
//! the ring they make (`halo_ring`), its light split into a spectrum
//! across its width, red at its inner edge, as an ice halo's is, with
//! swells and motes of light running round it as along the blooms' beams.
//! The ring passes through the four points (east, south, west, north) the
//! blooms stood on; an arc is as bright as the points at its ends, a point
//! dimming to `DIM` without a grown bloom on it. The ring is a field of
//! celestial energy over its disc; a formed diamond holds a wider one.
//!
//! How far the halo has come, `k` (0 the blooms leave their points .. 1
//! they meet; past 1, `FORM`s since), goes to the GPU with each instance:
//! the blooms' spiral, the crystal gathering from its shards and the
//! projection reaching out all follow it there (common.glsl `haloSpiral`).
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const m=lib.engine.core.math;
const World=lib.world.World;
const species=lib.species;
const Plants=lib.plants.Plants;
const Parts=lib.parts.Parts;
/// the ring's radius, tiles: the blooms' points lie this far out along the
/// axes, on it
pub const reachTiles:i32=5;
/// the points in order around the ring (east, south, west, north); arc k
/// runs from point k to k+1
pub const points=[4][2]i32{.{1,0},.{0,1},.{-1,0},.{0,-1}};
/// a bloom holds a point when grown and healthier than this
const activeHealth:f32=0.5;
/// seconds the blooms take to reach the centre
pub const form:f32=5;
/// the flash where they meet spreads and fades over this many seconds
pub const flash:f32=1.4;
/// a formed diamond's field reaches this far (the ring's, `R`)
pub const diamondR:f32=7;
/// the blooms' spiral in (common.glsl `HALO_RUSH`, `HALO_TURNS`, `HALO_FOLD`)
const rush:f32=4;
const turns:f32=1.25;
const fold:f32=0.3;
/// points of light: the diamond's (warm, reaching past the ring as it
/// forms) and the flash's (a burst, fading as it spreads)
const diamondLight=m.V3{1.0,0.93,0.82};
const diamondReach:f32=6;
const flashLight=m.V3{6.0,5.6,5.0};
const flashReach:f32=16;
/// the diamond floats at the centre of the ring, where the blooms' cross
/// of beams meets: as high as they hang, the ring with it
pub const hover:f32=species.get(.bloom).hover;
/// the projection's least rise (level, its cone would be flat)
const level:f32=0.02;
/// how bright a point's arcs are without a bloom (1 with one), and how
/// quickly they follow
pub const dim:f32=0.3;
const lightEase:f32=0.4;
/// where a forming halo (`halo`: its centre xyz, how far along w; w < 0
/// none) has drawn a point riding with one of its blooms, and how far that
/// bloom is still open: the CPU's twin of common.glsl `haloSpiral` and
/// `haloFold`
pub fn spiral(p:m.V3,halo:[4]f32)struct{at:m.V3,open:f32}{
  if(halo[3]<0)return.{.at=p,.open=1};
  const k=m.clamp01(halo[3]);
  const pull=(@exp(rush*k)-1)/(@exp(rush)-1);
  const a=turns*m.tau*pull;
  const ctr=m.v3(halo[0],halo[1],halo[2]);
  const d=p-ctr;
  const c=@cos(a);
  const s=@sin(a);
  const at=ctr+m.v3(d[0]*c-d[2]*s,d[1],d[0]*s+d[2]*c)*m.splat3(1-pull);
  return.{.at=at,.open=1-m.smooth(m.clamp01((k-(1-fold))/fold))};
}
pub fn pointAt(x:i32,y:i32,k:usize)[2]i32{
  return.{x+points[k][0]*reachTiles,y+points[k][1]*reachTiles};
}
/// a grown, unwithered celestial bloom at a tile
pub fn active(p:*const Plants,w:*const World,at:[2]i32)bool{
  const id=p.at(w,at[0],at[1]) orelse return false;
  const i=id.idx();
  const s=p.list.slice();
  return species.get(s.items(.sp)[i]).radiance>0 and s.items(.growth)[i]>=1 and s.items(.health)[i]>activeHealth;
}
/// ease each point's light toward whether a grown bloom holds it.
pub fn relight(light:*[4]f32,p:*const Plants,w:*const World,x:i32,y:i32,dt:f32)void{
  for(light,0..)|*l,k|{
    const want:f32=if(active(p,w,pointAt(x,y,k)))1 else dim;
    l.*+=(want-l.*)*@min(1,dt*lightEase);
  }
}
/// how many points shine as with a bloom
pub fn lit(light:[4]f32)u32{
  var n:u32=0;
  for(light)|l|{if(l>(1+dim)/2)n+=1;}
  return n;
}
/// the diamond at `at`, its projection and ring (over the ground at
/// `ground`) and, just as it forms, the flash, for a halo `k` along (see
/// the module notes). The diamond is still: it never sways.
pub fn draw(out:*Parts,seed:f32,at:m.V3,ground:m.V3,k:f32,light:[4]f32)Allocator.Error!void{
  const halo=[4]f32{at[0],at[1],at[2],k};
  try out.emit(.haloDiamond,m.chain(&.{m.translate(at),m.rotY(seed*m.tau)}),.{.phase=seed,.halo=halo});
  // the ring floats at a bloom's hover over the ground at the centre, the
  // diamond at its heart, so its rays run level out to it
  const ring=ground+m.v3(0,hover,0);
  const r=m.f(reachTiles);
  try out.emit(.haloProjection,m.chain(&.{m.translate(at),m.scale3(m.v3(r,@max(ring[1]-at[1],level),r))}),.{.glow=1,.phase=seed,.halo=halo});
  try out.emit(.haloRing,m.chain(&.{m.translate(ring),m.scale3(m.v3(r,1,r))}),.{.glow=1,.phase=seed,.tint=light,.halo=halo});
  const age=(k-1)*form/flash;
  if(age>=0 and age<1)try out.emit(.haloFlash,m.translate(at),.{.glow=1,.flutter=age});
  // the diamond holds the light it gathers, more as it forms; as it does,
  // the flash bursts out over the garden
  const formed=@sqrt((@exp(rush*m.clamp01(k))-1)/(@exp(rush)-1));
  try out.light(at,diamondLight*m.splat3(formed),diamondReach);
  if(age>=0 and age<1)try out.light(at,flashLight*m.splat3((1-age)*(1-age)),flashReach);
}
