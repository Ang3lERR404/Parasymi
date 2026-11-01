//! angled top-down camera: pans over the ground plane, zooms along its view
//! ray, and orbits its target: turns (yaw) freely and tilts (pitch) from
//! just over the horizon to just short of overhead.
//! For close inspection it can also fly free, then ease back to following.
//! Zoomed all the way in, it goes on into the eyes of what it follows (first
//! person) and back out when zoomed out again.
/// the standard library
const std=@import("std");
/// the test helpers
const testing=std.testing;
/// all the maths: vectors, matrices, angles, easing
const m=@import("../core/math.zig");
/// pitch limits and resting angle, radians above the horizon: never fully
/// level, never straight down (looking along `upAxis` has no up).
/// (the lowest it tilts: 8° over the horizon)
pub const minPitch:f32=m.rad(8.0);
/// (the highest it tilts: 89°, just short of overhead)
pub const maxPitch:f32=m.rad(89.0);
/// (where it rests: 55°)
pub const restPitch:f32=m.rad(55.0);
/// below rest the view widens and lifts toward the horizon, fully by this
/// pitch (and no further below it)
const lowPitch:f32=m.rad(30.0);
/// orbiting: radians turned per pixel dragged
pub const orbitSpeed:f32=0.006;
/// field of view at the lowest pitch (radians, vertical)
const wideFovy:f32=1.0;
/// the free camera: its field of view, how long it takes to ease back to
/// following, and how fast it flies, looks and rolls
const freeFovy:f32=0.8;
/// (seconds to ease back to following)
const returnTime:f32=0.3;
/// (world units a second it flies)
pub const flySpeed:f32=3;
/// (radians turned per pixel of mouse)
pub const lookSpeed:f32=0.0025;
/// (radians a second it rolls)
pub const rollSpeed:f32=1.2;
/// the resting view: distance, vertical field of view, aspect
/// (world units from the target at rest)
const restDist:f32=32;
/// (radians, vertical, at rest)
const restFovy:f32=0.6;
/// (width over height, until the window says otherwise)
const restAspect:f32=16.0/9.0;
/// clip planes: near for following and free flight; far grows with distance
/// (the near plane while following)
const near:f32=0.1;
/// (the near plane in free flight)
const freeNear:f32=0.05;
/// (the far plane grows this much per unit of distance)
const farPerDist:f32=6;
/// (the far plane is never nearer than this)
const farMin:f32=120;
/// below rest the gaze lifts by this share of half the field of view
const liftAmount:f32=0.45;
/// draw reach: distance times this (plus more as the camera lowers), plus a margin
const reachHigh:f32=2.2;
/// (the extra distance factor at the lowest pitch)
const reachLow:f32=3.5;
/// (world units always added)
const reachMargin:f32=12;
/// each wheel notch scales the distance by this, within these bounds
const zoomStep:f32=0.88;
/// (the nearest it zooms in before going into the eyes)
const minDist:f32=4;
/// the first-person view: its field of view and near plane, how long it
/// takes to ease in from following (and back out), and how far it looks up
/// and down (radians from level)
const eyesFovy:f32=1.1;
/// (the near plane in the eyes)
const eyesNear:f32=0.03;
/// (seconds to ease in or out)
const eyesTime:f32=0.35;
/// (the most the eyes look up)
pub const eyesUp:f32=m.rad(75.0);
/// (the most the eyes look down)
pub const eyesDown:f32=m.rad(-70.0);
/// the farthest it zooms out, in world units
const maxDist:f32=120;
/// world up: the axis the camera keeps upright about
const upAxis=m.v3(0,1,0);
/// a free-flying view: anywhere, any orientation (no limits on pitch or yaw)
pub const Free=struct{
  /// where it is
  pos:m.V3,
  /// which way it is turned about the vertical (radians)
  yaw:f32,
  /// how far it is tilted up (+) or down (radians, unlimited)
  pitch:f32,
  /// how far it is rolled about its own forward (radians)
  roll:f32=0,
  /// the window holds the cursor for mouse look
  captured:bool=false,
  /// which way it looks (unit)
  pub fn forward(f:*const Free)m.V3{return toward(f.yaw,f.pitch);}
  /// independent of pitch, so looking past straight up or down never flips
  pub fn right(f:*const Free)m.V3{return m.v3(@cos(f.yaw),0,-@sin(f.yaw));}
  /// its up: square to right and forward, then rolled
  pub fn up(f:*const Free)m.V3{
    // the unrolled up
    const u=m.cross(f.right(),f.forward());
    return u*m.splat3(@cos(f.roll))+f.right()*m.splat3(@sin(f.roll));
  }
};
/// which way a view turned by `yaw` and tilted by `pitch` (up +) looks
fn toward(yaw:f32,pitch:f32)m.V3{
  // how much of the look runs level
  const cp=@cos(pitch);
  return m.v3(-@sin(yaw)*cp,@sin(pitch),-@cos(yaw)*cp);
}
/// the first-person view, from the eyes of what is followed: where they are
/// (`see`, every frame), how far they look up or down (they turn with the
/// camera's own yaw, so moving and following stay as they were), and how far
/// the view has eased in from following (0) to them (1)
pub const Eyes=struct{
  /// where the eyes are, as `see` set them this frame
  pos:m.V3,
  /// how far they look up (+) or down (radians)
  pitch:f32=0,
  /// how far in from following the view has eased, 0..1
  k:f32=0,
  /// easing back out to following
  leaving:bool=false,
};
/// how the camera is looking: following, flying free, easing home, or
/// out of the eyes
pub const View=union(enum){
  /// following the target (the normal game camera)
  follow,
  /// flying free
  free:Free,
  /// easing from a free view back to following
  returning:struct{from:Free,t:f32=0},
  /// first person (and easing into it or out of it)
  eyes:Eyes,
};
/// the 2.5D camera orbiting what it follows: its target, distance, turn,
/// tilt and lens, and how it is looking (`view`)
pub const Camera=struct{
  /// the point it orbits and looks at (the followed thing's position)
  target:m.V3=m.v3(0,1,0),
  /// how far the orbit eye is from the target
  dist:f32=restDist,
  /// how far it is turned about the target (radians)
  yaw:f32=0,
  /// how far above the horizon it looks down from (radians)
  pitch:f32=restPitch,
  /// its vertical field of view at rest and above (radians)
  fovy:f32=restFovy,
  /// the window's width over its height
  aspect:f32=restAspect,
  /// how it is looking now
  view:View=.follow,
  /// where the orbit eye sits: `dist` out from the target, turned and tilted
  pub fn eye(c:*const Camera)m.V3{
    // how much of the distance runs level
    const cp=@cos(c.pitch);
    return c.target+m.v3(@sin(c.yaw)*cp,@sin(c.pitch),@cos(c.yaw)*cp)*m.splat3(c.dist);
  }
  /// the view and projection, as one matrix, for whichever way it is looking
  pub fn viewProj(c:*const Camera)m.M4{
    // the far plane, further the further out it is
    const far=c.dist*farPerDist+farMin;
    // the following view's direction, which the eased views blend from
    const followDir=m.norm(c.aim()-c.eye());
    return switch(c.view){
      .follow=>m.mul(m.perspective(c.fov(),c.aspect,near,far),m.lookAt(c.eye(),c.aim(),upAxis)),
      .free=>|f|m.mul(m.perspective(freeFovy,c.aspect,freeNear,far),m.lookAt(f.pos,f.pos+f.forward(),f.up())),
      .eyes=>|y|blk:{
        // how far into the eyes, eased
        const k=m.smooth(y.k);
        // where the view is
        const e=c.viewEye();
        // which way it looks, blended from following to the eyes' gaze
        const dir=m.norm(m.lerpV(followDir,toward(c.yaw,y.pitch),k));
        break:blk m.mul(m.perspective(m.lerp(c.fov(),eyesFovy,k),c.aspect,m.lerp(near,eyesNear,k),far),m.lookAt(e,e+dir,upAxis));
      },
      .returning=>|r|blk:{
        // how much of the free view is left, eased
        const w=1-m.smooth(m.clamp01(r.t/returnTime));
        // where the view is
        const e=c.viewEye();
        // which way it looks and its up, blended from the free view's
        const dir=m.norm(m.lerpV(followDir,r.from.forward(),w));
        const up=m.norm(m.lerpV(upAxis,r.from.up(),w));
        break:blk m.mul(m.perspective(m.lerp(c.fov(),freeFovy,w),c.aspect,freeNear,far),m.lookAt(e,e+dir,up));
      },
    };
  }
  /// where the view actually is (the orbit eye, or wherever it flies).
  pub fn viewEye(c:*const Camera)m.V3{
    return switch(c.view){
      .follow=>c.eye(),
      .free=>|f|f.pos,
      .returning=>|r|m.lerpV(c.eye(),r.from.pos,1-m.smooth(m.clamp01(r.t/returnTime))),
      .eyes=>|y|m.lerpV(c.eye(),y.pos,m.smooth(y.k)),
    };
  }
  /// looking out of the eyes (or easing in), not on the way back out.
  pub fn inEyes(c:*const Camera)bool{
    return switch(c.view){
      .eyes=>|y|!y.leaving,
      .follow,.free,.returning=>false,
    };
  }
  /// how far up (+) or down the eyes look; level outside them.
  pub fn gaze(c:*const Camera)f32{
    return switch(c.view){
      .eyes=>|y|y.pitch,
      .follow,.free,.returning=>0,
    };
  }
  /// where the eyes are this frame (first person follows them).
  pub fn see(c:*Camera,at:m.V3)void{
    switch(c.view){
      .eyes=>|*y|y.pos=at,
      .follow,.free,.returning=>{},
    }
  }
  /// turn the eyes by `px` pixels of mouse (x turns, y looks up and down).
  pub fn look(c:*Camera,px:m.Vice(f32,2))void{
    switch(c.view){
      .eyes=>|*y|{
        c.yaw=@mod(c.yaw-px[0]*lookSpeed,m.tau);
        y.pitch=m.clamp(y.pitch-px[1]*lookSpeed,eyesDown,eyesUp);
      },
      .follow,.free,.returning=>{},
    }
  }
  /// leave following: fly from exactly where the camera is, looking the same way.
  pub fn startFree(c:*Camera)void{
    // the orbit eye and the way it looks
    const e=c.eye();
    const d=m.norm(c.aim()-e);
    c.view=.{.free=.{.pos=e,.yaw=m.atan2(-d[0],-d[2]),.pitch=m.asin(d[1])}};
  }
  /// ease back to following from wherever it flew.
  pub fn endFree(c:*Camera)void{
    switch(c.view){
      .free=>|f|c.view=.{.returning=.{.from=f}},
      .follow,.returning,.eyes=>{},
    }
  }
  /// move the clock on by `dt` seconds: ease home from a free view, or into
  /// or out of the eyes, settling back to following when done
  pub fn tick(c:*Camera,dt:f32)void{
    switch(c.view){
      .returning=>|*r|{
        r.t+=dt;
        if(r.t>=returnTime)c.view=.follow;
      },
      .eyes=>|*y|{
        y.k=m.clamp01(y.k+(if(y.leaving)-dt else dt)/eyesTime);
        if(y.leaving and y.k==0)c.view=.follow;
      },
      .follow,.free=>{},
    }
  }
  /// steer a free view: turn by `turn` (radians), move by `move` (right,
  /// up, forward, world units), roll, and dolly along the view.
  pub fn fly(c:*Camera,turn:m.Vice(f32,2),move:m.V3,roll:f32,dolly:f32)void{
    switch(c.view){
      .free=>|*f|{
        f.yaw+=turn[0];
        f.pitch+=turn[1];
        f.roll+=roll;
        f.pos+=f.right()*m.splat3(move[0])+f.up()*m.splat3(move[1])+f.forward()*m.splat3(move[2]+dolly);
      },
      .follow,.returning,.eyes=>{},
    }
  }
  /// 0 at the resting pitch and above, 1 at the lowest.
  fn lowness(c:*const Camera)f32{return m.clamp01((restPitch-c.pitch)/(restPitch-lowPitch));}
  /// vertical field of view: it widens as the camera drops, so the wolf and
  /// the horizon fit in one frame.
  pub fn fov(c:*const Camera)f32{return m.lerp(c.fovy,wideFovy,c.lowness());}
  /// where the camera looks: the target from rest upward; below rest the
  /// gaze lifts toward the horizon, keeping the target in the lower frame,
  /// so the sky opens up as it drops (about a third of the view at 30).
  fn aim(c:*const Camera)m.V3{
    // the gaze's angle under level: the pitch, less the lift
    const down=c.pitch-liftAmount*(c.fov()/2)*@sqrt(c.lowness());
    // the camera's level forward
    const fwd=m.v3(-@sin(c.yaw),0,-@cos(c.yaw));
    return c.eye()+fwd*m.splat3(@cos(down))-m.v3(0,@sin(down),0);
  }
  /// screen-space pan direction mapped onto the ground plane.
  pub fn pan(c:*Camera,right:f32,fwd:f32)void{
    // the camera's level right and forward
    const r=m.v3(@cos(c.yaw),0,-@sin(c.yaw));
    const f=m.v3(-@sin(c.yaw),0,-@cos(c.yaw));
    c.target+=r*m.splat3(right)+f*m.splat3(fwd);
  }
  /// tilt by `by` radians, kept within `minPitch..maxPitch`
  pub fn tilt(c:*Camera,by:f32)void{c.pitch=m.clamp(c.pitch+by,minPitch,maxPitch);}
  /// drag round the target by `px` pixels (x turns, y tilts): the world is
  /// grabbed and turned with the cursor
  pub fn orbit(c:*Camera,px:m.Vice(f32,2))void{
    c.yaw=@mod(c.yaw-px[0]*orbitSpeed,m.tau);
    c.tilt(px[1]*orbitSpeed);
  }
  /// how far around the target the world is worth drawing: further the
  /// lower the camera looks, never beyond what is streamed in.
  pub fn reach(c:*const Camera,limit:f32)f32{
    // the reach while following: further the lower it looks, within `limit`
    const r=@min(c.dist*(reachHigh+reachLow*(1-@sin(c.pitch)))+reachMargin,limit);
    // (out of the eyes it looks out level, as far as anything is drawn)
    return switch(c.view){
      .eyes=>|y|m.lerp(r,limit,m.smooth(y.k)),
      .follow,.free,.returning=>r,
    };
  }
  /// the wheel: following, in (+) and out by `steps` notches; zoomed all
  /// the way in, a notch further goes into the eyes (from `at`), and a
  /// notch out of them comes back out (a notch in turns back again).
  pub fn zoom(c:*Camera,steps:f32,at:m.V3)void{
    switch(c.view){
      .follow=>if(steps>0 and c.dist<=minDist){
        c.view=.{.eyes=.{.pos=at}};
      }else{
        c.dist=m.clamp(c.dist*m.pow(f32,zoomStep,steps),minDist,maxDist);
      },
      .eyes=>|*y|if(steps!=0){
        y.leaving=steps<0;
      },
      .free,.returning=>{},
    }
  }
  /// where the world point `p` lands on a screen `w` by `h` pixels, or
  /// null behind the eye (the inverse of `ray`)
  pub fn screenOf(c:*const Camera,p:m.V3,w:f32,h:f32)?m.Vice(f32,2){
    // the point in clip space, before the divide
    const q=m.mulV(c.viewProj(),.{p[0],p[1],p[2],1});
    if(q[3]<=1e-4)return null;
    return.{(q[0]/q[3]+1)/2*w,(q[1]/q[3]+1)/2*h};
  }
  /// world-space ray through a pixel.
  pub fn ray(c:*const Camera,px:f32,py:f32,w:f32,h:f32)struct{o:m.V3,d:m.V3}{
    // back from clip space to the world
    const inv=m.inverse(c.viewProj());
    // the pixel in clip space, -1..1 across and down
    const nx=px/w*2-1;
    const ny=py/h*2-1;
    // the pixel on the near and far planes, before the divide
    const a=m.mulV(inv,.{nx,ny,0,1});
    const b=m.mulV(inv,.{nx,ny,1,1});
    // those two points in the world
    const pa=m.v3(a[0]/a[3],a[1]/a[3],a[2]/a[3]);
    const pb=m.v3(b[0]/b[3],b[1]/b[3],b[2]/b[3]);
    return.{.o=pa,.d=m.norm(pb-pa)};
  }
};
test"the free camera starts where the follow view is and eases home"{
  // a camera following a point off the origin
  var c:Camera=.{.target=m.v3(3,1,-2)};
  // where its eye is, and the way it looks
  const e=c.eye();
  const d=m.norm(c.aim()-e);
  c.startFree();
  try testing.expect(m.len(c.viewEye()-e)<1e-5);
  try testing.expect(m.len(c.view.free.forward()-d)<1e-4);
  // fly up and over the top: pitch is not clamped and nothing degenerates
  c.fly(.{0,3},m.v3(0.5,0,1),0.3,0);
  try testing.expect(c.view.free.pitch>m.halfPi);
  try testing.expect(m.len(c.view.free.up())>0.99);
  c.endFree();
  c.tick(0.15);
  try testing.expect(c.view==.returning);
  c.tick(0.2);
  try testing.expect(c.view==.follow);
  try testing.expect(m.len(c.viewEye()-e)<1e-5);
}
test"zoomed all the way in, the camera goes into the eyes and back out"{
  // a camera zoomed in a little past the nearest
  var c:Camera=.{.target=m.v3(3,1,-2),.dist=minDist*1.5};
  // where its eyes are
  const eyes=m.v3(3,1.3,-1.9);
  c.zoom(10,eyes);
  try testing.expect(c.view==.follow and c.dist==minDist);
  c.zoom(1,eyes);
  try testing.expect(c.inEyes());
  // easing in, it starts where following left off
  try testing.expect(m.len(c.viewEye()-c.eye())<1e-5);
  c.tick(eyesTime);
  try testing.expect(m.len(c.viewEye()-eyes)<1e-5);
  // the eyes look the way the camera faced, level; turning them turns it
  // the yaw before the eyes turn
  const yaw=c.yaw;
  c.look(.{-100,1e6});
  try testing.expectApproxEqAbs(@mod(yaw+100*lookSpeed,m.tau),c.yaw,1e-4);
  try testing.expectEqual(eyesDown,c.gaze());
  c.look(.{0,-1e7});
  try testing.expectEqual(eyesUp,c.gaze());
  try testing.expect(c.reach(50)==50);
  try testing.expect(m.len(c.ray(800,450,1600,900).d-toward(c.yaw,eyesUp))<1e-3);
  // a notch out leaves, easing back to following
  c.zoom(-1,eyes);
  try testing.expect(!c.inEyes() and c.view==.eyes);
  c.tick(eyesTime*0.5);
  try testing.expect(c.view==.eyes);
  c.tick(eyesTime);
  try testing.expect(c.view==.follow);
  try testing.expect(m.len(c.viewEye()-c.eye())<1e-5);
}
test"orbiting turns freely and tilts only within its limits"{
  // a camera at rest
  var c:Camera=.{};
  c.orbit(.{-m.tau/orbitSpeed*3.5,0});
  try testing.expect(c.yaw>=0 and c.yaw<m.tau);
  c.orbit(.{0,1e6});
  try testing.expectEqual(maxPitch,c.pitch);
  c.orbit(.{0,-1e6});
  try testing.expectEqual(minPitch,c.pitch);
  // nothing degenerates at either end
  for([_]f32{minPitch,maxPitch})|p|{
    c.pitch=p;
    // a ray through the screen's middle
    const r=c.ray(800,450,1600,900);
    try testing.expect(m.len(r.d)>0.99);
  }
}
test"a point along a pixel's ray lands back on that pixel, and one behind the eye on none"{
  // a camera following a point off the origin
  const c:Camera=.{.target=m.v3(3,1,-2)};
  // a ray through a pixel, and a point some way along it
  const r=c.ray(400,300,1600,900);
  const p=r.o+r.d*m.splat3(7);
  const q=c.screenOf(p,1600,900).?;
  try testing.expect(@abs(q[0]-400)<0.05 and @abs(q[1]-300)<0.05);
  try testing.expectEqual(null,c.screenOf(c.eye()-r.d*m.splat3(3),1600,900));
}
