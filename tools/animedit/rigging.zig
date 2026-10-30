//! the wolf's clickable joints, their gizmos, and what is being animated.
const std=ps.std;
const bufPrint=std.fmt.bufPrint;
const engine=ps.engine;
const m=engine.core.math;
const clip=engine.anim.clip;
const ps=@import("parasymi");
const gizmo=@import("../gizmo.zig");
const skel=ps.skeleton;
const specimen=ps.specimen;
const PoseCh=clip.Channels(skel.Pose);
const LookCh=clip.Channels(specimen.Look);
/// how a joint of the wolf's pose moves: its place (the hips), its turn
/// about three axes, or a hinge's about one
const Move=enum{place,turn,hinge};
/// a joint of the wolf's pose: its channels (x, y, z; a hinge's alone),
/// the bone it stands at, and a hinge's axis in that bone's frame
pub const Joint=struct{
  bone:skel.Bone,
  move:Move,
  chans:[3]?usize,
  axis:m.V3=m.v3(1,0,0),
};
fn joint(comptime name:[]const u8,bone:skel.Bone,move:Move,axis:m.V3)Joint{
  @setEvalBranchQuota(1_000_000);
  return.{.bone=bone,.move=move,.axis=axis,.chans=switch(move){
    .place,.turn=>.{PoseCh.find(name++".x").?,PoseCh.find(name++".y").?,PoseCh.find(name++".z").?},
    .hinge=>.{PoseCh.find(name).?,null,null},
  }};
}
/// every joint a gizmo turns (the fingers are keyed in the list); a
/// hinge's axis as its bone turns about it (the elbow folds about -x)
pub const joints=blk:{
  const xAxis=m.v3(1,0,0);
  const nx=m.v3(-1,0,0);
  break:blk[_]Joint{
    joint("hip",.pelvis,.place,xAxis),
    joint("pelvis",.pelvis,.turn,xAxis),
    joint("waist",.waist,.turn,xAxis),
    joint("chest",.chest,.turn,xAxis),
    joint("neck",.neck,.turn,xAxis),
    joint("head",.head,.turn,xAxis),
    joint("jaw",.jaw,.hinge,xAxis),
    joint("tail.0",.tail0,.turn,xAxis),
    joint("tail.1",.tail1,.turn,xAxis),
    joint("tail.2",.tail2,.turn,xAxis),
    joint("tail.3",.tail3,.turn,xAxis),
  }++side(0,xAxis,nx)++side(1,xAxis,nx);
};
/// a side's joints (0 left, 1 right)
fn side(comptime i:usize,xAxis:m.V3,nx:m.V3)[8]Joint{
  const sd=skel.sides[i];
  const n=std.fmt.comptimePrint("{d}",.{i});
  return.{
    joint("ears."++n,sd.ear,.turn,xAxis),
    joint("arms."++n++".root",sd.arm,.turn,xAxis),
    joint("arms."++n++".mid",sd.forearm,.hinge,nx),
    joint("arms."++n++".low",sd.hand,.turn,xAxis),
    joint("legs."++n++".root",sd.thigh,.turn,xAxis),
    joint("legs."++n++".mid",sd.shin,.hinge,xAxis),
    joint("legs."++n++".low",sd.meta,.turn,xAxis),
    joint("legs."++n++".foot",sd.foot,.hinge,xAxis),
  };
}
/// the joint channel `ch` of the pose belongs to
pub fn jointOf(ch:usize)?usize{
  for(joints,0..)|j,i|for(j.chans)|c|if(c==ch)return i;
  return null;
}
/// the wolf's bones in the world this frame, for `pose`
const Bones=[skel.count]m.M4;
pub fn bonesOf(pose:skel.Pose,heading:m.M4)Bones{
  var w=skel.fk(pose);
  for(&w)|*b|b.*=m.mul(heading,b.*);
  return w;
}
/// joint `j`'s gizmo (`heading` wolf space to the world), its axes those
/// its channels turn or move it along
pub fn gizmoOf(j:Joint,pose:*const skel.Pose,bones:*const Bones,heading:m.M4)gizmo.Gizmo{
  const w=bones[@intFromEnum(j.bone)];
  const xAxis=m.v3(1,0,0);
  const y=m.v3(0,1,0);
  const zAxis=m.v3(0,0,1);
  const at=m.origin(w);
  return switch(j.move){
    .place=>.{.at=at,.mode=.move,.axes=.{m.norm(m.mulDir(heading,xAxis)),m.norm(m.mulDir(heading,y)),m.norm(m.mulDir(heading,zAxis))}},
    .hinge=>.{.at=at,.mode=.turn,.axes=.{m.norm(m.mulDir(w,j.axis)),null,null}},
    .turn=>turn:{
      // a turn is y, then x, then z, last in its bone's frame: z about the
      // bone's own z, x before z was turned, y before both
      const x=PoseCh.get(pose,j.chans[0].?);
      const z=PoseCh.get(pose,j.chans[2].?);
      const unz=m.mul(w,m.rotZ(-z));
      break:turn.{.at=at,.mode=.turn,.axes=.{
        m.norm(m.mulDir(unz,xAxis)),
        m.norm(m.mulDir(m.mul(unz,m.rotX(-x)),y)),
        m.norm(m.mulDir(w,zAxis)),
      }};
    },
  };
}
/// what the gizmo needs of the wolf this frame
pub const Rig=struct{view:gizmo.View,bones:Bones,heading:m.M4};
pub const Subject=union(enum){
  wolf,
  thing:specimen.Subject,
  /// its word in the clip (`wolf`, `plant:<species>`, `structure:<kind>`)
  pub fn word(sj:Subject,buf:[]u8)[]const u8{
    return switch(sj){
      .wolf=>"wolf",
      .thing=>|t|switch(t){
        .plant=>|sp|bufPrint(buf,"plant:{t}",.{sp}) catch unreachable,
        .structure=>|k|bufPrint(buf,"structure:{t}",.{k}) catch unreachable,
      },
    };
  }
  /// the clip's name unless `--clip=` says
  pub fn name(sj:Subject)[]const u8{
    return switch(sj){
      .wolf=>"wolf",
      .thing=>|t|switch(t){
        .plant=>|sp|@tagName(sp),
        .structure=>|k|@tagName(k),
      },
    };
  }
};
pub const Drag=enum{none,timeline,value,gizmo};
