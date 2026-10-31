//! skeletal animation, the generic half: a joint's turn, blending turns the
//! short way round, a turn read back out of a frame, two-bone inverse
//! kinematics (the triangle, and the middle joint bent toward a pole), a
//! trailing chain (a tail), and the matrices a GPU skins with. A game's skeleton (its bones, their offsets and its forward
//! kinematics) and its limb solvers, built on `twoBone`, are its own.
/// the standard library
const std=@import("std");
/// the test helpers
const testing=std.testing;
/// the engine's maths: matrices, turns, the law of cosines' acos
const m=@import("../core/math.zig");
/// a point or direction in space
const V3=m.V3;
/// a 4x4 matrix: a bone's frame
const M4=m.M4;
/// a joint's turn: about X (pitch), then Y (twist), then Z (roll), applied
/// as Y * X * Z
pub const Turn=struct{
  /// the pitch (radians), about X
  x:f32=0,
  /// the twist (radians), about Y
  y:f32=0,
  /// the roll (radians), about Z
  z:f32=0,
  /// the turn as a rotation matrix, Y * X * Z
  pub fn m4(t:Turn)M4{return m.chain(&.{m.rotY(t.y),m.rotX(t.x),m.rotZ(t.z)});}
  /// `a` turned toward `b` by share `k`, each angle the short way round
  pub fn blend(a:Turn,b:Turn,k:f32)Turn{
    return.{.x=a.x+m.angleDiff(a.x,b.x)*k,.y=a.y+m.angleDiff(a.y,b.y)*k,.z=a.z+m.angleDiff(a.z,b.z)*k};
  }
};
/// how far short of straight, and of folded flat, a two-bone chain is held
/// (so its angles never meet a singular pose)
const slack:f32=1e-3;
/// a two-bone chain (links `a` from the root to the middle joint, `b` from
/// it to the end) reaching a point `reach` from its root, as the triangle
/// the two links and the line to the end make
pub const Triangle=struct{
  /// the distance it reaches: the one asked for, held within what the
  /// links can span
  reach:f32,
  /// the angle at the root between link `a` and the line to the end
  root:f32,
  /// the angle at the end between link `b` and the line back to the root
  end:f32,
  /// how far the middle joint bends from straight (0 straight)
  bend:f32,
};
/// the triangle a two-bone chain makes reaching `reach` (law of cosines)
pub fn twoBone(a:f32,b:f32,reach:f32)Triangle{
  // the reach, held between folded flat and straight, each with slack
  const d=m.clamp(reach,@abs(a-b)+slack,a+b-slack);
  return.{
    .reach=d,
    .root=m.acos((a*a+d*d-b*b)/(2*a*d)),
    .end=m.acos((b*b+d*d-a*a)/(2*b*d)),
    .bend=m.acos((d*d-a*a-b*b)/(2*a*b)),
  };
}
/// the turn (Y * X * Z) whose rotation is `r`'s: its pitch, twist and roll
/// read back out of the frame's axes (pitch held within a quarter turn)
pub fn turnOf(r:M4)Turn{
  return.{.x=m.asin(-r[2][1]),.y=m.atan2(r[2][0],r[2][2]),.z=m.atan2(r[0][1],r[1][1])};
}
/// a rotation whose +Y runs along `y` and whose +X lies as near `x` as it
/// can, square to `y` (if `x` runs along `y`, any square direction serves)
pub fn frame(y:V3,x:V3)M4{
  // the three axes, each square to the others
  const ny=m.norm(y);
  var z=m.cross(x,ny);
  if(m.len(z)<1e-6)z=m.cross(if(@abs(ny[0])<m.nearParallel)m.v3(1,0,0)else m.v3(0,0,1),ny);
  const nz=m.norm(z);
  const nx=m.cross(ny,nz);
  return.{.{nx[0],nx[1],nx[2],0},.{ny[0],ny[1],ny[2],0},.{nz[0],nz[1],nz[2],0},.{0,0,0,1}};
}
/// where the middle joint of a two-bone chain (links `a` then `b`, rooted
/// at the origin) lies as it reaches `target`, bending out toward `pole`
/// (a direction: the knee's forward, the elbow's back)
pub fn middle(a:f32,b:f32,target:V3,pole:V3)V3{
  // the triangle the links make, and the way to the target
  const tri=twoBone(a,b,m.len(target));
  const dir=m.norm(target);
  // the pole's part square to the reach: which way the joint bends out
  var side=pole-dir*m.splat3(m.dot(pole,dir));
  if(m.len(side)<1e-6)side=m.cross(dir,if(@abs(dir[0])<m.nearParallel)m.v3(1,0,0)else m.v3(0,0,1));
  return dir*m.splat3(a*@cos(tri.root))+m.norm(side)*m.splat3(a*@sin(tri.root));
}
/// how a trailing chain moves (`trail`)
pub const Trailing=struct{
  /// how strongly each point is drawn toward its rest place, per second, at
  /// the root (the tip half as strongly)
  stiff:f32,
  /// how much of its own motion each point keeps from one sixtieth of a second to the next
  keep:f32,
  /// the length of each link
  seg:f32,
};
/// a chain of `pts` trailing from its root like a tail: its root set on
/// `rest[0]`; every other point carries on with its own motion (its last
/// place in `prev`), damped, and is drawn toward its place in the rest
/// shape `rest` (softer toward the tip), then each link is held at its
/// length from the root out, so it swings, lags and follows through
pub fn trail(pts:[]V3,prev:[]V3,rest:[]const V3,o:Trailing,dt:f32)void{
  // how many points, and how much motion each keeps this step
  const n=pts.len;
  const keep=m.pow(f32,o.keep,dt*60);
  pts[0]=rest[0];
  prev[0]=rest[0];
  for(1..n)|i|{
    // its own motion since the last step, and how hard it is drawn home
    const v=(pts[i]-prev[i])*m.splat3(keep);
    const k=m.clamp01(o.stiff*dt*(1-0.5*m.ratio(i-1,n-1)));
    prev[i]=pts[i];
    pts[i]+=v+(rest[i]-pts[i])*m.splat3(k);
  }
  for(1..n)|i|{
    // the link from the point before, held at its length (along the rest
    // shape's if the two have met)
    const d=pts[i]-pts[i-1];
    const l=m.len(d);
    const dir=if(l>1e-6)d/m.splat3(l)else m.norm(rest[i]-rest[i-1]);
    pts[i]=pts[i-1]+dir*m.splat3(o.seg);
  }
}
/// each bone's frame inverted: from the bind pose's frames, what carries a
/// vertex built in the bind pose back into its bone
pub fn inverses(comptime n:usize,frames:[n]M4)[n]M4{
  // each frame's inverse, filled in turn
  var out:[n]M4=undefined;
  for(&out,frames)|*o,f|o.*=m.inverseRigid(f);
  return out;
}
/// the matrices a GPU skins with: each carries a vertex from the bind pose
/// (`bindInv` from `inverses`) to its bone's frame in `world`
pub fn skin(comptime n:usize,world:[n]M4,bindInv:*const[n]M4)[n]M4{
  // each bone's skinning matrix, filled in turn
  var out:[n]M4=undefined;
  for(&out,world,bindInv)|*o,w,inv|o.*=m.chain(&.{w,inv});
  return out;
}
test"a two-bone chain reaches its target, bends straight at full reach"{
  // the two links' lengths
  const a:f32=0.5;
  const b:f32=0.4;
  // the target along +Y: link a leaves at `root` off it, link b turns back
  // from link a by `bend`, and the end lands on the target
  // the triangle reaching 0.6 along +Y
  const t=twoBone(a,b,0.6);
  // the middle joint, then the end, walked along the links
  const mid=m.v3(@sin(t.root),@cos(t.root),0)*m.splat3(a);
  const end=mid+m.v3(@sin(t.root-t.bend),@cos(t.root-t.bend),0)*m.splat3(b);
  try testing.expectApproxEqAbs(@as(f32,0),end[0],1e-4);
  try testing.expectApproxEqAbs(@as(f32,0.6),end[1],1e-4);
  try testing.expectApproxEqAbs(m.pi,t.root+t.end+(m.pi-t.bend),1e-4);
  // out of reach: held just short of straight, never past it
  // asked too far: past what the links span
  const far=twoBone(a,b,2);
  try testing.expect(far.reach<a+b and far.bend<0.1);
  // asked too near: closer than the links can fold
  const near=twoBone(a,b,0);
  try testing.expect(near.reach>@abs(a-b));
}
test"the skin of the bind pose is the identity"{
  // a bind pose of two bones, one moved, one moved and turned
  const frames=[2]M4{m.translate(m.v3(1,2,3)),m.chain(&.{m.translate(m.v3(0,1,0)),m.rotX(0.7)})};
  // the bind pose skinned by its own inverses
  const s=skin(2,frames,&inverses(2,frames));
  for(s)|mat|inline for(0..4)|c|inline for(0..4)|r|{
    try testing.expectApproxEqAbs(m.identity[c][r],mat[c][r],1e-5);
  };
}
test"turns blend the short way round"{
  // two turns nearly half a turn each way, about X
  const a:Turn=.{.x=3.0};
  const b:Turn=.{.x=-3.0};
  // halfway between them, the short way round through pi
  const h=Turn.blend(a,b,0.5);
  try testing.expect(@abs(@abs(h.x)-m.pi)<0.05);
}
test"a turn read back out of its own frame is the same turn"{
  // turns of every sign, the pitch within a quarter turn
  const turns=[_]Turn{.{.x=0.3,.y=-1.2,.z=0.8},.{.x=-1.1,.y=2.5,.z=-2.9},.{.x=0.0,.y=0.0,.z=1.4},.{.x=1.4,.y=-0.2,.z=0.1}};
  for(turns)|t|{
    // the turn read back
    const r=turnOf(t.m4());
    try testing.expectApproxEqAbs(t.x,r.x,1e-4);
    try testing.expectApproxEqAbs(t.y,r.y,1e-4);
    try testing.expectApproxEqAbs(t.z,r.z,1e-4);
  }
  // a frame's +Y runs where asked, its +X square to it as near the hint as can be
  const f=frame(m.v3(0,0,2),m.v3(1,0.5,0));
  try testing.expectApproxEqAbs(@as(f32,1),f[1][2],1e-5);
  try testing.expectApproxEqAbs(@as(f32,2)/@sqrt(@as(f32,5)),f[0][0],1e-5);
  try testing.expectApproxEqAbs(@as(f32,1)/@sqrt(@as(f32,5)),f[0][1],1e-5);
}
test"the middle joint bends toward the pole and both links keep their length"{
  // links, a target and a pole out along +Z
  const a:f32=0.3;
  const b:f32=0.25;
  const target=m.v3(0.1,-0.4,0.05);
  const mid=middle(a,b,target,m.v3(0,0,1));
  try testing.expectApproxEqAbs(a,m.len(mid),1e-4);
  try testing.expectApproxEqAbs(b,m.len(target-mid),1e-4);
  try testing.expect(mid[2]>target[2]*m.len(mid)/m.len(target));
}
test"a trailing chain keeps its links and comes to rest on its rest shape"{
  // a chain of four, set off bent, its rest shape straight up
  var pts=[_]V3{m.v3(0,0,0),m.v3(0.1,0,0),m.v3(0.2,0,0),m.v3(0.3,0,0)};
  var prev=pts;
  const rest=[_]V3{m.v3(0,0,0),m.v3(0,0.1,0),m.v3(0,0.2,0),m.v3(0,0.3,0)};
  for(0..600)|_|trail(&pts,&prev,&rest,.{.stiff=8,.keep=0.9,.seg=0.1},1.0/60.0);
  for(1..4)|i|try testing.expectApproxEqAbs(@as(f32,0.1),m.len(pts[i]-pts[i-1]),1e-4);
  try testing.expect(m.len(pts[3]-rest[3])<0.01);
}
