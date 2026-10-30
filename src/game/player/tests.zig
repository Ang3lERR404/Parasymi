//! the wolf tested: belly lag, legs, eyes, feet, arms, gathering and the belly's stages.
const lib=@import("../../lib.zig");
const std=lib.std;
const testing=std.testing;
const engine=lib.engine;
const m=engine.core.math;
const skel=lib.skeleton;
const bellyMesh=lib.wolfBelly;
const V3=m.V3;
const v3=m.v3;
const Bone=skel.Bone;
const gatherAt=lib.player.tuning.gatherAt;
const gazeNod=lib.player.tuning.gazeNod;
const pecMax=lib.player.tuningLook.pecMax;
const Player=lib.player.player.Player;
const restHip=lib.player.tuning.restHip;
const restLift=lib.player.tuning.restLift;
const restOn=lib.player.tuning.restOn;
const rumpMax=lib.player.tuningLook.rumpMax;
const squatDrop=lib.player.tuning.squatDrop;
const trailMax=lib.player.tuning.trailMax;
const walkSpeed=lib.player.tuning.walkSpeed;
const solveArm=lib.player.ik.solveArm;
const solveLeg=lib.player.ik.solveLeg;
/// tests step at the 60 Hz tick and allow this much float slack
const testDt:f32=1.0/60.0;
const testEps:f32=1e-4;
test"belly contents lag a sprint, overshoot a stop, then settle"{
  var p:Player=.{.pos=v3(0,0,0)};
  _=p.inv.add(.grit,50);
  const dt:f32=testDt;
  for(0..120)|_|p.animate(null,dt);
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
  const w=skel.fk(.{});
  for(skel.sides,0..)|sd,s|{
    const foot=m.origin(w[@intFromEnum(sd.foot)]);
    const l=solveLeg(foot-v3(skel.sign(s)*skel.hipX,skel.hipY,0),0,0,0);
    try testing.expectApproxEqAbs(skel.restThigh,l.root.x,1e-3);
    try testing.expectApproxEqAbs(skel.restKnee,l.mid,1e-3);
    try testing.expectApproxEqAbs(skel.restHock,l.low.x,1e-3);
  }
}
test"seen from its own eyes, the head leads toward where they look and nods with them"{
  var p:Player=.{.pos=v3(0,0,0)};
  const level=p.eyes();
  // the eyes are up in the head, ahead of the chest
  try testing.expect(level[1]>p.chest()[1] and level[2]>0);
  p.aim=0.4;
  p.gaze=-0.5;
  for(0..240)|_|p.animate(null,testDt);
  try testing.expectApproxEqAbs(@as(f32,0.4),p.look.x,0.02);
  try testing.expectApproxEqAbs(0.5*gazeNod,p.nod.x,0.02);
  // looking down and to its right (+x), the eyes go with the head
  const e=p.eyes();
  try testing.expect(e[0]>level[0] and e[1]<level[1]);
}
test"a planted foot stays where it is planted while the wolf walks"{
  var p:Player=.{.pos=v3(0,0,0)};
  p.animate(null,testDt);
  p.vel=v3(0,0,walkSpeed);
  for(0..240)|_|{
    p.pos+=p.vel*m.splat3(testDt);
    const before=p.feet;
    p.animate(null,testDt);
    for(before,p.feet)|a,b|if(a.planted() and b.planted())try testing.expect(m.len(a.at-b.at)<1e-5);
  }
  // and both feet keep up with it
  for(p.feet,0..)|f,s|try testing.expect(m.len(f.at-p.rest(null,s))<trailMax+0.1);
}
test"an arm's wrist reaches what it is solved for"{
  const w0=skel.fk(.{});
  const chest=w0[@intFromEnum(Bone.chest)];
  for([_]V3{v3(0.1,-0.35,0.2),v3(0.02,-0.25,0.3),v3(0.15,-0.4,0.05)})|d|{
    var q:skel.Pose=.{};
    q.arms[1]=solveArm(d);
    const w=skel.fk(q);
    const got=m.mulPoint(m.inverseRigid(chest),m.origin(w[@intFromEnum(skel.sides[1].hand)]))-skel.shoulder;
    try testing.expect(m.len(got-d)<2e-3);
  }
}
test"gathering, the wolf squats, grips the node and each unit sends a paw to the belly"{
  var p:Player=.{.pos=v3(0,0,0)};
  p.work=v3(0,0,gatherAt);
  var t:f32=0;
  var stowed=[2]bool{false,false};
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
  var p:Player=.{.pos=v3(0,0,0)};
  const at=[_]f32{0.1,0.5,0.95};
  const want=[_]f32{0,1,2};
  var last:f32=2;
  for(at,want)|f,w|{
    p.fullness=f;
    try testing.expectApproxEqAbs(w,p.stage(),1e-3);
    const g=p.gait();
    try testing.expect(g.walk<=last and g.sprint<=last);
    try testing.expect(g.walk>=0.8 and g.sprint>=0.75);
    last=@min(g.walk,g.sprint);
  }
  // blended across a threshold, never jumping
  var prev:f32=0;
  var f:f32=0;
  while(f<=1):(f+=0.005){
    p.fullness=f;
    try testing.expect(@abs(p.stage()-prev)<0.12);
    prev=p.stage();
  }
}
test"standing still with a heavy belly, one paw rests on it and the other on the hip"{
  var p:Player=.{.pos=v3(0,0,0)};
  p.fullness=0.6;
  p.inv=.{};
  var t:f32=0;
  while(t<4):(t+=testDt){
    p.animate(null,testDt);
    p.fullness=0.6;
  }
  try testing.expect(p.restPose.x>0.95);
  const w=skel.fk(p.pose());
  const belly=m.mulPoint(w[@intFromEnum(Bone.gutTop)],restOn*v3(bellyMesh.rx,bellyMesh.upAxis,bellyMesh.rz))+v3(0,restLift,0);
  const hip=m.mulPoint(w[@intFromEnum(Bone.pelvis)],restHip*v3(-1,1,1));
  try testing.expect(m.len(m.origin(w[@intFromEnum(skel.sides[1].hand)])-belly)<0.03);
  try testing.expect(m.len(m.origin(w[@intFromEnum(skel.sides[0].hand)])-hip)<0.03);
  // a light belly never takes the pose
  var q:Player=.{.pos=v3(0,0,0)};
  t=0;
  while(t<4):(t+=testDt)q.animate(null,testDt);
  try testing.expect(q.restPose.x<0.01);
}
test"the arms ease into the gathering and belly-rest poses without swinging round"{
  // the hands travel there smoothly: never far in a frame, and the
  // shoulder never turns more than half a turn
  const Case=struct{full:f32,gather:bool};
  for([_]Case{.{.full=0.6,.gather=false},.{.full=0,.gather=true}})|c|{
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
      const q=p.pose();
      const w=skel.fk(q);
      var h:[2]V3=undefined;
      for(0..2)|s|{
        h[s]=m.origin(w[@intFromEnum(skel.sides[s].hand)]);
        try testing.expect(@abs(q.arms[s].root.x)<=m.pi+testEps);
        if(last)|l|try testing.expect(m.len(h[s]-l[s])<0.03);
      }
      last=h;
    }
  }
}
