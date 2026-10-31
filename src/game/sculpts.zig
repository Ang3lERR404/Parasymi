//! the gardener's sculpts, read once at startup: every `.mesh` the mesh
//! editor keeps (`src/mesh/`, beside the repo; then `sculpts/` in the
//! gardener's folder, for a game shipped without the repo), each with the
//! clip of its own name the animation editor keyed for it, if there is one
//! (`src/anim/<name>.anim`, or `sculpts/<name>.anim`). The first `slots` of
//! them, in name order, are meshed into the library's sculpt slots
//! (meshes/sculpt.zig) and drawn skinned, their bones turned by their clip
//! looping. A sculpt's channels: the root's place, then each bone's pitch,
//! yaw and roll (radians).
const lib=@import("../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator type the shelf is kept with
const Allocator=std.mem.Allocator;
/// the I/O every file is read through
const Io=std.Io;
/// a directory handle
const Dir=Io.Dir;
/// formats a channel's name and words, and a file's path
const allocPrint=std.fmt.allocPrint;
/// puts one byte for another in place (a bone's spaces in its path)
const replaceScalar=std.mem.replaceScalar;
/// whether a name ends so
const endsWith=std.mem.endsWith;
/// whether two names are the same
const eql=std.mem.eql;
/// sorts the shelf by name
const sort=std.mem.sort;
/// orders two names
const lessThan=std.mem.lessThan;
/// the log, for a sculpt that will not read
const log=std.log;
/// the test helpers
const testing=std.testing;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, matrices, angles
const m=engine.core.math;
/// keyframed clips, which a sculpt's bones loop
const clip=engine.anim.clip;
/// a sculpt's forms and bones as kept
const sculptDoc=lib.sculptDoc;
/// a sculpt's bones, posed
const rig=lib.sculptRig;
/// the gardener's folder
const home=lib.home;
/// a sculpt as kept
const Doc=sculptDoc.Doc;
/// a point or a turn (three numbers)
const V3=m.V3;
/// makes a `V3` from its three parts
const v3=m.v3;
/// a 4×4 matrix: a bone's turn and place
const M4=m.M4;
/// how many sculpts the game draws: the library's sculpt slots
pub const slots=8;
/// beside the repo: where the editors keep sculpts and clips
const repoMeshes=sculptDoc.dir;
const repoClips="src/anim";
/// in the gardener's folder: sculpts and their clips together
const homeSculpts="sculpts";
/// a clip's file ending
const clipExt=".anim";
/// a kept file is at most this large
const maxFile:usize=1<<22;
/// the three turns each bone's channels name, and the root's place
const turnWords=[3][]const u8{"pitch","yaw","roll"};
const placeWords=[3][]const u8{"across","up","depth"};
/// the parts of a channel's path
const axes=[3][]const u8{"x","y","z"};
/// a sculpt with its channels: their names (as a clip keys them), their
/// words (as the animation editor shows them) and their values now
pub const Rigged=struct{
  /// the allocator its names and values are kept with
  gpa:Allocator,
  /// the mesh, its forms and bones
  doc:Doc,
  /// each channel's path in a clip (`place.y`, `left_arm.x`)
  names:[][]u8,
  /// each channel in words (`place up`, `left arm pitch`)
  words:[][]u8,
  /// each channel's value now (m for the place, rad for a turn)
  vals:[]f32,
  /// every channel's index, in order: all are shown
  order:[]usize,
  /// the channels of `doc` (taken over: let go with it): the root's place,
  /// then each kept bone's three turns (a bone's spaces as `_` in its path)
  pub fn init(gpa:Allocator,doc:Doc)Allocator.Error!Rigged{
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
      // the bone's name
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
  pub fn deinit(r:*Rigged)void{
    for(r.names,r.words)|nm,w|{
      r.gpa.free(nm);
      r.gpa.free(w);
    }
    r.gpa.free(r.names);
    r.gpa.free(r.words);
    r.gpa.free(r.vals);
    r.gpa.free(r.order);
    r.doc.deinit(r.gpa);
  }
  /// every channel set from `c` at `t` (s), the unkeyed at rest
  pub fn sample(r:*Rigged,c:*const clip.Clip,t:f32)void{
    for(r.names,r.vals)|nm,*v|v.*=c.sample(nm,t) orelse 0;
  }
  /// the bones as the values have them, the sculpt standing at `place`:
  /// each matrix in `out` (the skeleton's count of them) carries the skin
  /// from rest to now; each twin turns as its bone, mirrored
  pub fn pose(r:*const Rigged,place:M4,out:*[rig.maxBones]M4)rig.Skeleton{
    // the skeleton, and each of its bones' turns (degrees)
    const k=rig.skeleton(r.doc.bones.items);
    var turns:[rig.maxBones]V3=@splat(.{0,0,0});
    for(0..r.doc.bones.items.len)|i|{
      // this bone's turns, in degrees
      const t=v3(r.vals[3+3*i],r.vals[4+3*i],r.vals[5+3*i])/m.splat3(m.rad(1));
      turns[i]=t;
      if(k.twinOf[i])|tw|turns[tw]=v3(t[0],-t[1],-t[2]);
    }
    rig.pose(&k,turns[0..k.count],v3(r.vals[0],r.vals[1],r.vals[2]),place,out[0..k.count]);
    return k;
  }
};
/// one sculpt on the shelf: its name, its rig, and the clip it loops
pub const Kept=struct{
  /// its file name, without the ending
  name:[]u8,
  /// its forms, bones and channels
  rigged:Rigged,
  /// the clip of its own name keyed for it, if there is one
  loop:?clip.Clip,
  /// its bones at `t` (s) into its loop (at rest without one), standing at
  /// `place`: the matrices in `out`, their count returned
  pub fn bonesAt(k:*Kept,t:f32,place:M4,out:*[rig.maxBones]M4)usize{
    if(k.loop)|*c|k.rigged.sample(c,@mod(t,@max(c.length,1e-3)))else @memset(k.rigged.vals,0);
    return k.rigged.pose(place,out).count;
  }
  /// lets it all go
  fn deinit(k:*Kept,gpa:Allocator)void{
    gpa.free(k.name);
    k.rigged.deinit();
    if(k.loop)|*c|c.deinit();
  }
};
// decision: one process-wide shelf, read once at startup like `txt.s`.
/// the sculpts read, in name order
var shelf:std.ArrayList(Kept)=.empty;
/// the allocator the shelf was read with
var shelfGpa:?Allocator=null;
/// the sculpts on the shelf
pub fn all()[]Kept{return shelf.items;}
/// the sculpt kept by `name`, if there is one
pub fn find(name:[]const u8)?usize{
  for(shelf.items,0..)|k,i|if(eql(u8,k.name,name))return i;
  return null;
}
/// reads every sculpt and its clip: beside the repo first, then the
/// gardener's folder (a name already read is passed over); a file that
/// will not read is told in the log and passed over. Only the first
/// `slots` in name order are kept.
pub fn load(gpa:Allocator,io:Io)Allocator.Error!void{
  unload();
  shelfGpa=gpa;
  try readDir(gpa,io,Dir.cwd(),repoMeshes,repoClips);
  try readDir(gpa,io,home.dir(),homeSculpts,homeSculpts);
  sort(Kept,shelf.items,{},struct{
    /// whether `a` comes before `b` by name
    fn before(_:void,a:Kept,b:Kept)bool{return lessThan(u8,a.name,b.name);}
  }.before);
  while(shelf.items.len>slots){
    // the one past the slots, let go
    var gone=shelf.pop().?;
    log.warn("sculpt {s}: only {d} sculpts are drawn",.{gone.name,slots});
    gone.deinit(gpa);
  }
}
/// every sculpt in `meshes` under `root`, each with its clip from `clips`
fn readDir(gpa:Allocator,io:Io,root:Dir,meshes:[]const u8,clips:[]const u8)Allocator.Error!void{
  // the folder, open to be walked (none: nothing to read)
  var d=root.openDir(io,meshes,.{.iterate=true}) catch return;
  defer d.close(io);
  var it=d.iterate();
  while(it.next(io) catch return)|e|{
    if(e.kind!=.file or !endsWith(u8,e.name,sculptDoc.ext))continue;
    // the sculpt's name
    const name=e.name[0..e.name.len-sculptDoc.ext.len];
    if(find(name)!=null)continue;
    // its text, read and parsed
    const text=d.readFileAlloc(io,e.name,gpa,.limited(maxFile))catch|er|{
      log.warn("sculpt {s}: {t}",.{name,er});
      continue;
    };
    defer gpa.free(text);
    var doc=Doc.parse(gpa,text)catch|er|switch(er){
      error.OutOfMemory=>return error.OutOfMemory,
      error.BadMesh=>{
        log.warn("sculpt {s}: not a mesh the game can read",.{name});
        continue;
      },
    };
    errdefer doc.deinit(gpa);
    // its rig, its clip, and its name kept
    var rigged=try Rigged.init(gpa,doc);
    errdefer rigged.deinit();
    var loop=try readClip(gpa,io,root,clips,name);
    errdefer if(loop)|*c|c.deinit();
    const kept=try gpa.dupe(u8,name);
    errdefer gpa.free(kept);
    try shelf.append(gpa,.{.name=kept,.rigged=rigged,.loop=loop});
  }
}
/// the clip `<name>.anim` in `clips` under `root`, if it is there and keyed
/// for this sculpt (its subject `sculpt:<name>`)
fn readClip(gpa:Allocator,io:Io,root:Dir,clips:[]const u8,name:[]const u8)Allocator.Error!?clip.Clip{
  // the clip's path and text (none: no clip)
  const path=try allocPrint(gpa,"{s}/{s}"++clipExt,.{clips,name});
  defer gpa.free(path);
  const text=root.readFileAlloc(io,path,gpa,.limited(maxFile)) catch return null;
  defer gpa.free(text);
  var c=clip.Clip.parse(gpa,text)catch|er|switch(er){
    error.OutOfMemory=>return error.OutOfMemory,
    else=>{
      log.warn("sculpt {s}: its clip will not read",.{name});
      return null;
    },
  };
  // the subject a clip for this sculpt carries
  const want=try allocPrint(gpa,"sculpt:{s}",.{name});
  defer gpa.free(want);
  if(!eql(u8,c.subject,want)){
    c.deinit();
    return null;
  }
  return c;
}
/// lets the shelf go
pub fn unload()void{
  const gpa=shelfGpa orelse return;
  for(shelf.items)|*k|k.deinit(gpa);
  shelf.deinit(gpa);
  shelf=.empty;
  shelfGpa=null;
}
test"a sculpt's channels are its place and each bone's turns, and they bend its bones"{
  // a sculpt of a root and a twinned arm
  const gpa=testing.allocator;
  var d:Doc=.{};
  try d.bones.append(gpa,.{.name=.of("root")});
  try d.bones.append(gpa,.{.name=.of("left arm"),.parent=0,.at=.{0.2,0.5,0},.twin=true});
  var r=try Rigged.init(gpa,d);
  defer r.deinit();
  try testing.expectEqual(@as(usize,9),r.names.len);
  try testing.expectEqualStrings("left_arm.z",r.names[8]);
  try testing.expectEqualStrings("left arm roll",r.words[8]);
  // the arm rolled a quarter, the whole lifted: the twin rolls the other way
  r.vals[1]=0.1;
  r.vals[8]=m.rad(90);
  var bones:[rig.maxBones]M4=undefined;
  const k=r.pose(m.identity,&bones);
  try testing.expectEqual(@as(usize,3),k.count);
  // a point past each arm's joint, out along its side
  const left=m.mulPoint(bones[1],v3(0.3,0.5,0));
  const right=m.mulPoint(bones[2],v3(-0.3,0.5,0));
  try testing.expectApproxEqAbs(left[1],right[1],1e-5);
  try testing.expectApproxEqAbs(@as(f32,0.7),left[1],1e-5);
  try testing.expectApproxEqAbs(-left[0],right[0],1e-5);
}
test"a kept sculpt loops its clip"{
  // a sculpt of one root, and a clip lifting it over a second
  const gpa=testing.allocator;
  var d:Doc=.{};
  try d.bones.append(gpa,.{.name=.of("root")});
  var c=try clip.Clip.init(gpa,"sculpt:hop");
  c.length=1;
  try c.put("place.y",0,0);
  try c.put("place.y",0.5,0.2);
  try c.put("place.y",1,0);
  var k:Kept=.{.name=try gpa.dupe(u8,"hop"),.rigged=try Rigged.init(gpa,d),.loop=c};
  defer k.deinit(gpa);
  // half way through its loop, and again a loop later: lifted the same
  var bones:[rig.maxBones]M4=undefined;
  _=k.bonesAt(0.5,m.identity,&bones);
  try testing.expectApproxEqAbs(@as(f32,0.2),m.mulPoint(bones[0],v3(0,0,0))[1],1e-5);
  _=k.bonesAt(1.5,m.identity,&bones);
  try testing.expectApproxEqAbs(@as(f32,0.2),m.mulPoint(bones[0],v3(0,0,0))[1],1e-5);
}
