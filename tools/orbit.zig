//! the tools' editors' camera (tools/meshedit.zig, tools/animedit.zig): a
//! free view turning round a target with no limit on its pitch (over the
//! top and under it alike), dragged round as the game's camera turns;
//! zooms and focusing ease it to where it is sent.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the test helpers
const testing=std.testing;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the engine package
const engine=ps.engine;
/// all the maths: vectors, easing, clamps
const m=engine.core.math;
/// the engine's camera, which the orbit places each frame
const camera=engine.render.camera;
/// a point or direction in the world (m)
const V3=m.V3;
/// makes a `V3` from its three parts
const v3=m.v3;
/// how much nearer each notch of the wheel brings the view (a share of its distance)
const zoomStep:f32=0.88;
/// the nearest the view may come to its target (m)
const distMin:f32=0.08;
/// the farthest the view may draw back from its target (m)
const distMax:f32=40;
/// how long (s) the view takes to ease half way to where it is sent
const ease:f32=0.06;
/// focusing frames a thing from this many times its largest size
pub const focusFit:f32=4;
/// and from no nearer than this (m)
pub const focusMin:f32=0.15;
/// turning round `target` from `dist` away; easing to `goal` and `goalDist`
pub const Orbit=struct{
  /// the point looked at now
  target:V3,
  /// the point being eased toward
  goal:V3,
  /// how far (m) the view is from its target now
  dist:f32,
  /// how far (m) the view is easing toward
  goalDist:f32,
  /// the turn round the target (rad), 0 looking down -z
  yaw:f32=0,
  /// how high over the target the view is (rad); it may pass straight up
  /// and on round, under it alike
  pitch:f32,
  /// looking at `at` from `dist` away, `pitch` (rad) over it
  pub fn init(at:V3,dist:f32,pitch:f32)Orbit{
    return.{.target=at,.goal=at,.dist=dist,.goalDist=dist,.pitch=pitch};
  }
  /// drag round by `px` pixels, as the game's camera turns
  pub fn turn(o:*Orbit,px:m.Vice(f32,2))void{
    o.yaw=@mod(o.yaw-px[0]*camera.orbitSpeed,m.tau);
    o.pitch=@mod(o.pitch+px[1]*camera.orbitSpeed,m.tau);
  }
  /// draw nearer or farther by `steps` notches of the wheel (negative draws
  /// back), kept between `distMin` and `distMax`
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
    // how far this step eases: half way every `ease` seconds
    const k=1-m.pow(f32,0.5,dt/ease);
    o.target=m.lerpV(o.target,o.goal,k);
    o.dist=m.lerp(o.dist,o.goalDist,k);
    c.target=o.target;
    c.dist=o.dist;
    c.yaw=o.yaw;
    // the pitch's cosine, and the way out from the target to the eye
    const cp=@cos(o.pitch);
    const out=v3(@sin(o.yaw)*cp,@sin(o.pitch),@cos(o.yaw)*cp);
    c.view=.{.free=.{.pos=o.target+out*m.splat3(o.dist),.yaw=o.yaw,.pitch=-o.pitch}};
  }
};
test"the camera eases onto a focused thing and turns past straight up"{
  // an orbit round the origin, and the camera it places
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
