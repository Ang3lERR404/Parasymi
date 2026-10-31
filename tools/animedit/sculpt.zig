//! a rigged sculpt as the animation editor moves it (`--mesh=<name>`): the
//! mesh editor's `.mesh` read, its bones turned to the clip's channels
//! (the root's place, then each bone's pitch, yaw and roll), its skin
//! drawn bent by them; each twin bone turns as its bone does, mirrored.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the allocator type its channels are kept with
const Allocator=std.mem.Allocator;
/// puts one byte for another in place (a bone's spaces in its path)
const replaceScalar=std.mem.replaceScalar;
/// formats a channel's name and words
const allocPrint=std.fmt.allocPrint;
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// all the maths: vectors, matrices, angles
const m=engine.core.math;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// a point or a turn (three numbers)
const V3=m.V3;
/// makes a `V3` from its three parts
const v3=m.v3;
/// a 4×4 matrix: a bone's turn and place
const M4=m.M4;
/// the mesh editor, whose meshes and bones are read
const meshedit=@import("../meshedit.zig");
/// a mesh as the mesh editor keeps it
pub const Doc=meshedit.doc.Doc;
/// the sculpt's bones
const rig=meshedit.rig;
/// the three turns each bone's channels name, and the root's place
const turnWords=[3][]const u8{"pitch","yaw","roll"};
const placeWords=[3][]const u8{"across","up","depth"};
/// the parts of a channel's path
const axes=[3][]const u8{"x","y","z"};
/// a sculpt with its channels: their names (as the clip keys them), their
/// words (as the panel shows them) and their values now
pub const Sculpt=struct{
  /// the allocator its names and values are kept with
  gpa:Allocator,
  /// the mesh, its forms and bones
  doc:Doc,
  /// each channel's path in the clip (`place.y`, `left_arm.x`)
  names:[][]u8,
  /// each channel in words (`place up`, `left arm pitch`)
  words:[][]u8,
  /// each channel's value now (m for the place, rad for a turn)
  vals:[]f32,
  /// every channel's index, in order: all are shown
  order:[]usize,
  /// the channels of `doc` (taken over: let go with the sculpt): the root's
  /// place, then each kept bone's three turns (a bone's spaces as `_` in
  /// its path)
  pub fn init(gpa:Allocator,doc:Doc)Allocator.Error!Sculpt{
    // how many channels there are
    const n=3+3*doc.bones.items.len;
    // the lists, filled below
    const names=try gpa.alloc([]u8,n);
    errdefer gpa.free(names);
    const words=try gpa.alloc([]u8,n);
    errdefer gpa.free(words);
    var made:usize=0;
    errdefer for(0..made)|i|{
      gpa.free(names[i]);
      gpa.free(words[i]);
    };
    for(0..3)|a|{
      names[made]=try allocPrint(gpa,"place.{s}",.{axes[a]});
      errdefer gpa.free(names[made]);
      words[made]=try allocPrint(gpa,"place {s}",.{placeWords[a]});
      made+=1;
    }
    for(doc.bones.items)|b|for(0..3)|a|{
      // the bone's name, and it with its spaces as `_` for its path
      const name=b.name.slice();
      names[made]=try allocPrint(gpa,"{s}.{s}",.{name,axes[a]});
      replaceScalar(u8,names[made],' ','_');
      errdefer gpa.free(names[made]);
      words[made]=try allocPrint(gpa,"{s} {s}",.{name,turnWords[a]});
      made+=1;
    };
    const vals=try gpa.alloc(f32,n);
    errdefer gpa.free(vals);
    @memset(vals,0);
    const order=try gpa.alloc(usize,n);
    for(order,0..)|*o,i|o.*=i;
    return.{.gpa=gpa,.doc=doc,.names=names,.words=words,.vals=vals,.order=order};
  }
  /// lets the mesh, the names and the values go
  pub fn deinit(sc:*Sculpt)void{
    for(sc.names,sc.words)|nm,w|{
      sc.gpa.free(nm);
      sc.gpa.free(w);
    }
    sc.gpa.free(sc.names);
    sc.gpa.free(sc.words);
    sc.gpa.free(sc.vals);
    sc.gpa.free(sc.order);
    sc.doc.deinit(sc.gpa);
  }
  /// the bones as the values have them, the sculpt standing at `place`:
  /// each matrix in `out` (the skeleton's count of them) carries the skin
  /// from rest to now; each twin turns as its bone, mirrored
  pub fn pose(sc:*const Sculpt,place:M4,out:*[rig.maxBones]M4)rig.Skeleton{
    // the skeleton, and each of its bones' turns (degrees)
    const k=rig.skeleton(sc.doc.bones.items);
    var turns:[rig.maxBones]V3=@splat(.{0,0,0});
    for(0..sc.doc.bones.items.len)|i|{
      // this bone's turns, in degrees
      const t=v3(sc.vals[3+3*i],sc.vals[4+3*i],sc.vals[5+3*i])/m.splat3(m.rad(1));
      turns[i]=t;
      if(k.twinOf[i])|tw|turns[tw]=v3(t[0],-t[1],-t[2]);
    }
    rig.pose(&k,turns[0..k.count],v3(sc.vals[0],sc.vals[1],sc.vals[2]),place,out[0..k.count]);
    return k;
  }
};
/// the testing helpers
const testing=std.testing;
test"a sculpt's channels are its place and each bone's turns, and they bend its bones"{
  // a sculpt of a root and a twinned arm
  const gpa=testing.allocator;
  var d:Doc=.{};
  try d.bones.append(gpa,.{.name=.of("root")});
  try d.bones.append(gpa,.{.name=.of("left arm"),.parent=0,.at=.{0.2,0.5,0},.twin=true});
  var sc=try Sculpt.init(gpa,d);
  defer sc.deinit();
  try testing.expectEqual(@as(usize,9),sc.names.len);
  try testing.expectEqualStrings("left_arm.z",sc.names[8]);
  try testing.expectEqualStrings("left arm roll",sc.words[8]);
  // the arm rolled a quarter, the whole lifted: the twin rolls the other way
  sc.vals[1]=0.1;
  sc.vals[8]=m.rad(90);
  var bones:[rig.maxBones]M4=undefined;
  const k=sc.pose(m.identity,&bones);
  try testing.expectEqual(@as(usize,3),k.count);
  // a point past each arm's joint, out along its side
  const left=m.mulPoint(bones[1],v3(0.3,0.5,0));
  const right=m.mulPoint(bones[2],v3(-0.3,0.5,0));
  try testing.expectApproxEqAbs(left[1],right[1],1e-5);
  try testing.expectApproxEqAbs(@as(f32,0.7),left[1],1e-5);
  try testing.expectApproxEqAbs(-left[0],right[0],1e-5);
}
