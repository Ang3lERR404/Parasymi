//! the tools' editors' camera (tools/meshedit.zig, tools/animedit.zig): a
//! free view turning round a target with no limit on its pitch (over the
//! top and under it alike), dragged round as the game's camera turns;
//! zooms and focusing ease it to where it is sent.
const std=ps.std;
const testing=std.testing;
const ps=@import("parasymi");
const engine=ps.engine;
const m=engine.core.math;
const camera=engine.render.camera;
const V3=m.V3;
const v3=m.v3;
/// the wheel zooms this much a notch, between these (m); the view eases
/// half way to where it is sent in this (s)
const zoomStep:f32=0.88;
const distMin:f32=0.08;
const distMax:f32=40;
const ease:f32=0.06;
/// focusing frames a thing from this many times its largest size, at least this
pub const focusFit:f32=4;
pub const focusMin:f32=0.15;
/// turning round `target` from `dist` away; easing to `goal` and `goal_dist`
pub const Orbit=struct{
  target:V3,
  goal:V3,
  dist:f32,
  goalDist:f32,
  yaw:f32=0,
  pitch:f32,
  /// looking at `at` from `dist` away, `pitch` (rad) over it
  pub fn init(at:V3,dist:f32,pitch:f32)Orbit{
    return.{.target=at,.goal=at,.dist=dist,.goalDist=dist,.pitch=pitch};
  }
  /// drag round by `px` pixels, as the game's camera turns
  pub fn turn(o:*Orbit,px:[2]f32)void{
    o.yaw=@mod(o.yaw-px[0]*camera.orbitSpeed,m.tau);
    o.pitch=@mod(o.pitch+px[1]*camera.orbitSpeed,m.tau);
  }
  pub fn zoom(o:*Orbit,steps:f32)void{
    o.goalDist=m.clamp(o.goalDist*m.pow(f32,zoomStep,steps),distMin,distMax);
  }
  /// ease toward looking at `at` from `dist` away
  pub fn send(o:*Orbit,at:V3,dist:f32)void{
    o.goal=at;
    o.goalDist=m.clamp(dist,distMin,distMax);
  }
  /// look at `at`, near enough that something `size` across fills the view
  pub fn focus(o:*Orbit,at:V3,size:f32)void{
    o.send(at,@max(size*focusFit,focusMin));
  }
  /// ease on by `dt` and place `c` (a free view aimed at the target)
  pub fn step(o:*Orbit,c:*camera.Camera,dt:f32)void{
    const k=1-m.pow(f32,0.5,dt/ease);
    o.target=m.lerpV(o.target,o.goal,k);
    o.dist=m.lerp(o.dist,o.goalDist,k);
    c.target=o.target;
    c.dist=o.dist;
    c.yaw=o.yaw;
    const cp=@cos(o.pitch);
    const out=v3(@sin(o.yaw)*cp,@sin(o.pitch),@cos(o.yaw)*cp);
    c.view=.{.free=.{.pos=o.target+out*m.splat3(o.dist),.yaw=o.yaw,.pitch=-o.pitch}};
  }
};
test"the camera eases onto a focused thing and turns past straight up"{
  var o=Orbit.init(v3(0,0,0),1.6,m.rad(20));
  var c:camera.Camera=.{};
  o.focus(v3(1,2,3),0.1);
  for(0..200)|_|o.step(&c,0.02);
  try testing.expect(m.len(o.target-v3(1,2,3))<1e-3);
  try testing.expectApproxEqAbs(@max(0.1*focusFit,focusMin),o.dist,1e-3);
  try testing.expectApproxEqAbs(o.dist,m.len(c.view.free.pos-o.target),1e-3);
  // dragged over the top, the view still looks at the target
  o.pitch=m.rad(120);
  o.step(&c,0);
  try testing.expect(m.len(c.view.free.pos+c.view.free.forward()*m.splat3(o.dist)-o.target)<1e-3);
}
