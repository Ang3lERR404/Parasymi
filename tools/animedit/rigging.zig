//! the wolf's clickable joints, their gizmos, and what is being animated.
/// the standard library, reached through the game's hub
const std=ps.std;
/// formats text into a fixed buffer (a subject's word)
const bufPrint=std.fmt.bufPrint;
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// all the maths: vectors, matrices, turns
const m=engine.core.math;
/// keyframed clips: channels, keys and sampling
const clip=engine.anim.clip;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the move and turn handles a joint is dragged by
const gizmo=@import("../gizmo.zig");
/// the wolf's skeleton: its bones, sides and `Pose`
const skel=ps.skeleton;
/// one plant or structure standing alone, and its `Look`
const specimen=ps.specimen;
/// every f32 of the wolf's `Pose`, each a channel a clip can key
const PoseCh=clip.Channels(skel.Pose);
/// every f32 of a specimen's `Look`, each a channel a clip can key
const LookCh=clip.Channels(specimen.Look);
/// how a joint of the wolf's pose moves: its place (the hips), its turn
/// about three axes, or a hinge's about one
const Move=enum{
  /// moved to a place along three axes (the hips)
  place,
  /// turned about three axes
  turn,
  /// folded about one axis, as an elbow or knee
  hinge,
};
/// a joint of the wolf's pose: its channels (x, y, z; a hinge's alone),
/// the bone it stands at, and a hinge's axis in that bone's frame
pub const Joint=struct{
  /// the bone the joint's dot and gizmo stand at
  bone:skel.Bone,
  /// how it moves: placed, turned or hinged
  move:Move,
  /// its pose channels for x, y and z (a hinge's in the first alone)
  chans:[3]?usize,
  /// a hinge's axis in its bone's frame (x unless said)
  axis:m.V3=m.v3(1,0,0),
};
/// the joint named `name` in the pose: finds its channels by name at
/// compile time (`name.x`/`.y`/`.z`, or `name` alone for a hinge)
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
  // the bone frame's x axis, and its opposite (the elbows fold about it)
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
  // that side's bones, and its index as text for the channel names
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
/// the wolf's bones in the world, one matrix each
const Bones=[skel.count]m.M4;
/// the wolf's bones in the world this frame for `pose`, turned to face
/// `heading` (wolf space to the world)
pub fn bonesOf(pose:skel.Pose,heading:m.M4)Bones{
  // the bones in wolf space, then carried into the world
  var w=skel.fk(pose);
  for(&w)|*b|b.*=m.mul(heading,b.*);
  return w;
}
/// joint `j`'s gizmo (`heading` wolf space to the world), its axes those
/// its channels turn or move it along
pub fn gizmoOf(j:Joint,pose:*const skel.Pose,bones:*const Bones,heading:m.M4)gizmo.Gizmo{
  // the joint's bone in the world
  const w=bones[@intFromEnum(j.bone)];
  // the three axes of a bone's frame
  const xAxis=m.v3(1,0,0);
  const y=m.v3(0,1,0);
  const zAxis=m.v3(0,0,1);
  // where the gizmo stands: the bone's origin
  const at=m.origin(w);
  return switch(j.move){
    .place=>.{.at=at,.mode=.move,.axes=.{m.norm(m.mulDir(heading,xAxis)),m.norm(m.mulDir(heading,y)),m.norm(m.mulDir(heading,zAxis))}},
    .hinge=>.{.at=at,.mode=.turn,.axes=.{m.norm(m.mulDir(w,j.axis)),null,null}},
    .turn=>turn:{
      // a turn is y, then x, then z, last in its bone's frame: z about the
      // bone's own z, x before z was turned, y before both
      // the joint's turn about x and z this frame (rad)
      const x=PoseCh.get(pose,j.chans[0].?);
      const z=PoseCh.get(pose,j.chans[2].?);
      // the bone's frame with its own z turn undone
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
pub const Rig=struct{
  /// how the camera sees the world, for placing and picking handles
  view:gizmo.View,
  /// the wolf's bones in the world this frame
  bones:Bones,
  /// the wolf's facing: wolf space to the world
  heading:m.M4,
};
/// one thing a clip moves alone: a plant or a structure (never samples,
/// which no clip keys)
pub const Thing=union(enum){
  /// a plant of a species
  plant:@FieldType(specimen.Subject,"plant"),
  /// a structure of a kind
  structure:@FieldType(specimen.Subject,"structure"),
  /// it as the game's lone subject
  pub fn subject(t:Thing)specimen.Subject{
    return switch(t){
      .plant=>|sp|.{.plant=sp},
      .structure=>|k|.{.structure=k},
    };
  }
};
/// who the clip moves: the wolf, or one plant or structure alone
pub const Subject=union(enum){
  /// the vine-wolf, keyed through its joints and pose channels
  wolf,
  /// a plant or structure alone, keyed through its `Look`
  thing:Thing,
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
/// what is being dragged: nothing, the playhead, a value or a gizmo
pub const Drag=enum{
  /// nothing held
  none,
  /// the playhead, dragged along the timeline
  timeline,
  /// a channel's value, keyed as it changes
  value,
  /// the selected joint's gizmo, keying it as it turns
  gizmo,
};
