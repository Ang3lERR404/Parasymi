//! the wolf tested: belly lag, legs, eyes, feet, arms, gathering and the belly's stages.
/// the hub every game module is reached through
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the test expectations
const testing=std.testing;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, matrices, lengths
const m=engine.core.math;
/// the wolf's skeleton: bones, pose, forward kinematics
const skel=lib.skeleton;
/// the belly's mesh: its radii and top
const bellyMesh=lib.wolfBelly;
/// a point or direction in 3D
const V3=m.V3;
/// builds a 3D vector from its three parts
const v3=m.v3;
/// one bone of the wolf's skeleton
const Bone=skel.Bone;
/// how far ahead of its feet the wolf gathers from a node (m)
const gatherAt=lib.player.tuning.gatherAt;
/// the share of the eyes' look up or down the head nods
const gazeNod=lib.player.tuning.gazeNod;
/// the furthest a pectoral strays from rest (m)
const pecMax=lib.player.tuningLook.pecMax;
/// the wolf under test
const Player=lib.player.player.Player;
/// where the left paw leans on the hip
const restHip=lib.player.tuning.restHip;
/// how far the resting wrist sits off the sac (m)
const restLift=lib.player.tuning.restLift;
/// where the right paw rests on the belly
const restOn=lib.player.tuning.restOn;
/// the furthest the rear strays from rest (m)
const rumpMax=lib.player.tuningLook.rumpMax;
/// how far the hips drop in the gathering squat (m)
const squatDrop=lib.player.tuning.squatDrop;
/// a planted foot never trails the hip further than this (m)
const trailMax=lib.player.tuning.trailMax;
/// its top walking speed (m/s)
const walkSpeed=lib.player.tuning.walkSpeed;
/// an arm reaching its wrist (inverse kinematics)
const solveArm=lib.player.ik.solveArm;
/// a leg reaching its foot (inverse kinematics)
const solveLeg=lib.player.ik.solveLeg;
/// tests step at the 60 Hz tick: seconds a step
const testDt:f32=1.0/60.0;
/// the float slack the tests allow
const testEps:f32=1e-4;
test"belly contents lag a sprint, overshoot a stop, then settle"{
  // a wolf carrying fifty grit, so its belly has lumps
  var p:Player=.{.pos=v3(0,0,0)};
  _=p.inv.add(.grit,50);
  // the step
  const dt:f32=testDt;
  for(0..120)|_|p.animate(null,dt);
  // where the first lump hangs once settled
  const restAt=p.lump[0].pos;
  // a burst of speed forward (+z): the lump swings back
  p.vel=v3(0,0,4);
  p.animate(null,dt);
  for(0..3)|_|p.animate(null,dt);
  try testing.expect(p.lump[0].pos[2]<restAt[2]-0.005);
  // run steadily, then stop dead: it overshoots forward
  for(0..120)|_|p.animate(null,dt);
  p.vel=v3(0,0,0);
  for(0..4)|_|p.animate(null,dt);
  try testing.expect(p.lump[0].pos[2]>restAt[2]+0.005);
  // and it never leaves the sac
  for(p.lump)|l|try testing.expect(m.len(l.pos)<=p.bellyRoom()+testEps);
  for(p.pec)|q|try testing.expect(m.len(q.pos)<=pecMax+testEps);
  for(p.rump)|q|try testing.expect(m.len(q.pos)<=rumpMax+testEps);
}
test"the leg reaches its resting foot in its resting pose"{
  // the bones at the rest pose
  const w=skel.fk(.{});
  for(skel.sides,0..)|sd,s|{
    // this side's resting foot, and the leg solved to reach it
    const foot=m.origin(w[@intFromEnum(sd.foot)]);
    const l=solveLeg(.{.d=foot-v3(skel.sign(s)*skel.hipX,skel.hipY,0)});
    try testing.expectApproxEqAbs(skel.restThigh,l.root.x,1e-3);
    try testing.expectApproxEqAbs(skel.restKnee,l.mid,1e-3);
    try testing.expectApproxEqAbs(skel.restHock,l.low.x,1e-3);
  }
}
test"each leg bone is its own: a foot set forward and up the slope is reached, its sole laid along it"{
  // the bones at the rest pose, and a slope rising ahead and to the left
  const w=skel.fk(.{});
  const slope=m.norm(v3(0.25,1,-0.3));
  // the pose with each leg solved onto its foot, moved forward and up the slope
  var q:skel.Pose=.{};
  // where each foot is wanted
  var want:[2]V3=undefined;
  for(skel.sides,0..)|sd,s|{
    want[s]=m.origin(w[@intFromEnum(sd.foot)])+v3(0,0.04,0.1);
    q.legs[s]=solveLeg(.{.d=want[s]-v3(skel.sign(s)*skel.hipX,skel.hipY,0),.ground=slope});
  }
  // the bones so posed: each ball where it is wanted, each sole facing the slope
  const pw=skel.fk(q);
  for(skel.sides,0..)|sd,s|{
    // the foot bone's frame
    const f=pw[@intFromEnum(sd.foot)];
    try testing.expect(m.dist(m.origin(f),want[s])<1e-4);
    try testing.expect(m.dot(m.norm(v3(f[1][0],f[1][1],f[1][2])),slope)>0.99);
  }
}
test"seen from its own eyes, the head leads toward where they look and nods with them"{
  // a wolf standing at the origin
  var p:Player=.{.pos=v3(0,0,0)};
  // where its eyes are, looking level
  const level=p.eyes();
  // the eyes are up in the head, ahead of the chest
  try testing.expect(level[1]>p.chest()[1] and level[2]>0);
  p.aim=0.4;
  p.gaze=-0.5;
  for(0..240)|_|p.animate(null,testDt);
  try testing.expectApproxEqAbs(@as(f32,0.4),p.look.x,0.02);
  try testing.expectApproxEqAbs(0.5*gazeNod,p.nod.x,0.02);
  // looking down and to its right (+x), the eyes go with the head
  // where its eyes are once turned and nodded
  const e=p.eyes();
  try testing.expect(e[0]>level[0] and e[1]<level[1]);
}
test"a planted foot stays where it is planted while the wolf walks"{
  // a wolf standing at the origin
  var p:Player=.{.pos=v3(0,0,0)};
  p.animate(null,testDt);
  p.vel=v3(0,0,walkSpeed);
  for(0..240)|_|{
    p.pos+=p.vel*m.splat3(testDt);
    // the feet before this frame's step
    const before=p.feet;
    p.animate(null,testDt);
    for(before,p.feet)|a,b|if(a.planted() and b.planted())try testing.expect(m.dist(a.at,b.at)<1e-5);
  }
  // and both feet keep up with it
  for(p.feet,0..)|f,s|try testing.expect(m.dist(f.at,p.rest(null,s))<trailMax+0.1);
}
test"an arm's wrist reaches what it is solved for"{
  // the bones at the rest pose, and the chest's frame among them
  const w0=skel.fk(.{});
  const chest=w0[@intFromEnum(Bone.chest)];
  for([_]V3{v3(0.1,-0.35,0.2),v3(0.02,-0.25,0.3),v3(0.15,-0.4,0.05)})|d|{
    // a pose with just the right arm solved to reach `d`
    var q:skel.Pose=.{};
    q.arms[1]=solveArm(d,1);
    // the bones of that pose, and where the wrist got to from the shoulder
    const w=skel.fk(q);
    const got=m.mulPoint(m.inverseRigid(chest),m.origin(w[@intFromEnum(skel.sides[1].hand)]))-skel.shoulder;
    try testing.expect(m.dist(got,d)<2e-3);
  }
}
test"gathering, the wolf squats, grips the node and each unit sends a paw to the belly"{
  // a wolf told to gather from a node just ahead
  var p:Player=.{.pos=v3(0,0,0)};
  p.work=v3(0,0,gatherAt);
  // the time gone, and whether each paw has stowed a unit yet
  var t:f32=0;
  var stowed=m.Vice(bool,2){false,false};
  while(t<3):(t+=testDt){
    p.gather=@mod(t,0.45)/0.45;
    p.animate(null,testDt);
    for(p.stow,0..)|s,i|stowed[i]=stowed[i] or s>0;
  }
  try testing.expect(p.squat.x>0.95);
  try testing.expect(p.pose().hip[1]<skel.hipY-squatDrop*0.9);
  try testing.expect(stowed[0] and stowed[1]);
  // stopping, it stands back up
  p.gather=null;
  p.work=null;
  t=0;
  while(t<2):(t+=testDt)p.animate(null,testDt);
  try testing.expect(p.squat.x<0.02);
}
test"the belly's stages: light, heavy, full, each a little slower and never slow"{
  // a wolf, the fullnesses tried, and the stage each should be
  var p:Player=.{.pos=v3(0,0,0)};
  const at=[_]f32{0.1,0.5,0.95};
  const want=[_]f32{0,1,2};
  // the slowest speed share seen so far
  var last:f32=2;
  for(at,want)|f,w|{
    p.fullness=f;
    try testing.expectApproxEqAbs(w,p.stage(),1e-3);
    // the gait at this fullness
    const g=p.gait();
    try testing.expect(g.walk<=last and g.sprint<=last);
    try testing.expect(g.walk>=0.8 and g.sprint>=0.75);
    last=@min(g.walk,g.sprint);
  }
  // blended across a threshold, never jumping
  // the stage a step back, and the fullness being swept
  var prev:f32=0;
  var f:f32=0;
  while(f<=1):(f+=0.005){
    p.fullness=f;
    try testing.expect(@abs(p.stage()-prev)<0.12);
    prev=p.stage();
  }
}
test"standing still with a heavy belly, one paw rests on it and the other on the hip"{
  // a wolf with a heavy-looking belly
  var p:Player=.{.pos=v3(0,0,0)};
  p.fullness=0.6;
  p.inv=.{};
  // the time gone
  var t:f32=0;
  while(t<4):(t+=testDt){
    p.animate(null,testDt);
    p.fullness=0.6;
  }
  try testing.expect(p.restPose.x>0.95);
  // the posed bones, and where the right paw and left paw should rest
  const w=skel.fk(p.pose());
  const belly=m.mulPoint(w[@intFromEnum(Bone.gutTop)],restOn*v3(bellyMesh.rx,bellyMesh.upReach,bellyMesh.rz))+v3(0,restLift,0);
  const hip=m.mulPoint(w[@intFromEnum(Bone.pelvis)],restHip*v3(-1,1,1));
  try testing.expect(m.dist(m.origin(w[@intFromEnum(skel.sides[1].hand)]),belly)<0.03);
  try testing.expect(m.dist(m.origin(w[@intFromEnum(skel.sides[0].hand)]),hip)<0.03);
  // a light belly never takes the pose
  // a wolf with a light belly
  var q:Player=.{.pos=v3(0,0,0)};
  t=0;
  while(t<4):(t+=testDt)q.animate(null,testDt);
  try testing.expect(q.restPose.x<0.01);
}
test"the arms ease into the gathering and belly-rest poses without swinging round"{
  // the hands travel there smoothly: never far in a frame, and the
  // shoulder never turns more than half a turn
  // one way in: how full the belly is, and whether it gathers
  const Case=struct{full:f32,gather:bool};
  for([_]Case{.{.full=0.6,.gather=false},.{.full=0,.gather=true}})|c|{
    // a wolf, where its hands were last frame, and the time gone
    var p:Player=.{.pos=v3(0,0,0)};
    var last:?[2]V3=null;
    var t:f32=0;
    while(t<5):(t+=testDt){
      if(c.gather and t>0.5){
        p.work=v3(0,0,gatherAt);
        p.gather=0;
      }
      p.animate(null,testDt);
      p.fullness=c.full;
      // the pose, its bones, and where each hand is this frame
      const q=p.pose();
      const w=skel.fk(q);
      var h:[2]V3=undefined;
      for(0..2)|s|{
        h[s]=m.origin(w[@intFromEnum(skel.sides[s].hand)]);
        try testing.expect(@abs(q.arms[s].root.x)<=m.pi+testEps);
        if(last)|l|try testing.expect(m.dist(h[s],l[s])<0.03);
      }
      last=h;
    }
  }
}
test"walking, sprinting, turning back and stopping, no leg joint ever jumps and the hips never sink to a trailing foot"{
  // a wolf standing at the origin
  var p:Player=.{.pos=v3(0,0,0)};
  p.animate(null,testDt);
  // each leg's knee, hock and ball last frame (in the world), once there is one
  var last:?[2][3]V3=null;
  // the moves asked for in turn: which way (x, z) and how fast (m/s)
  const moves=[_]m.Vice(f32,3){.{0,1,1.5},.{0,-1,1.5},.{1,0,1},.{-1,1,1},.{0,1,6.5},.{0,-1,6.5},.{0,0,0},.{1,1,6.5},.{-1,-1,6.5},.{0,0,0}};
  for(moves)|mv|for(0..90)|_|{
    // the velocity wished for, eased toward, the body moved and turned to it
    const want=if(mv[2]>0)m.norm(v3(mv[0],0,mv[1]))*m.splat3(mv[2])else v3(0,0,0);
    p.vel+=(want-p.vel)*m.splat3(@min(1,testDt*lib.player.tuning.accelResponse));
    p.pos+=p.vel*m.splat3(testDt);
    if(p.groundSpeed()>0.3)p.facing+=m.angleDiff(p.facing,m.atan2(p.vel[0],p.vel[2]))*@min(1,testDt*lib.player.tuning.turnResponse);
    p.animate(null,testDt);
    // the pose, and its bones in the world
    const q=p.pose();
    var w=skel.fk(q);
    for(&w)|*b|b.*=m.mul(p.heading(),b.*);
    try testing.expect(q.hip[1]>skel.hipY*0.6);
    // each leg's joints this frame
    var now:[2][3]V3=undefined;
    for(skel.sides,&now)|sd,*n|n.*=.{m.origin(w[@intFromEnum(sd.shin)]),m.origin(w[@intFromEnum(sd.meta)]),m.origin(w[@intFromEnum(sd.foot)])};
    // none moved further in a frame than a sprinting swing carries it
    if(last)|l|for(l,now)|a,b|for(a,b)|j0,j1|try testing.expect(m.dist(j1,j0)<0.3);
    last=now;
  };
}
