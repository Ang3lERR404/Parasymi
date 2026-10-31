//! a sculpt's bones: each a joint where it turns, hung off a parent, so a
//! mesh made in the editor bends as one skin (the sculpt weights every
//! vertex to the bones of the forms it lies nearest). A bone with a twin
//! has a mirrored one across the sculpt's middle (x=0), which the twins of
//! the forms on it ride. With no bones kept, one root at the origin
//! carries everything.
/// the engine package, as the game's hub hands it on
const engine=ps.engine;
/// all the maths: vectors, matrices
const m=engine.core.math;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// a point in the sculpt (m)
const V3=m.V3;
/// makes a `V3` from its three parts
const v3=m.v3;
/// a 4×4 matrix: a bone's turn and place
const M4=m.M4;
/// a bone's name, kept by value
const Name=@import("../labels.zig").Name;
/// the most bones a sculpt may have, twins counted (one bit each in the
/// sculpt's `only`, one byte each in a vertex's skin)
pub const maxBones=64;
/// one bone: its name, its parent, its joint, whether it has a twin
pub const Bone=struct{
  /// what the gardener calls it (`neck`, `left arm`)
  name:Name=.{},
  /// the bone it hangs from (an index among the kept bones), null the root
  parent:?u8=null,
  /// where it turns, in the sculpt at rest (m)
  at:V3=.{0,0,0},
  /// whether a mirrored twin of it stands across the middle
  twin:bool=false,
};
/// the bones as the sculpt takes them: the kept ones first, then each
/// twin, every one with its parent and joint
pub const Skeleton=struct{
  /// how many bones there are, twins counted
  count:usize=1,
  /// each bone's parent (null the root)
  parents:[maxBones]?u8=@splat(null),
  /// each bone's joint at rest (m)
  at:[maxBones]V3=@splat(.{0,0,0}),
  /// each kept bone's twin (null: it has none)
  twinOf:[maxBones]?u8=@splat(null),
  /// the bones a form on kept bone `b` rides: it, and its twin's mirrored
  /// form the twin bone (or the same bone, which has none)
  pub fn ride(k:*const Skeleton,b:u8,mirrored:bool)u8{
    return if(mirrored)k.twinOf[b] orelse b else b;
  }
};
/// how many bones `bones` makes, twins counted (one root when none are kept)
pub fn count(bones:[]const Bone)usize{
  if(bones.len==0)return 1;
  // the count so far
  var n=bones.len;
  for(bones)|b|n+=@intFromBool(b.twin);
  return n;
}
/// the skeleton `bones` makes: each twin hung off its parent's twin (or
/// its parent, which has none), its joint mirrored; one root at the origin
/// when none are kept. `bones` makes at most `maxBones`.
pub fn skeleton(bones:[]const Bone)Skeleton{
  // the skeleton being laid
  var k:Skeleton=.{};
  if(bones.len==0)return k;
  k.count=bones.len;
  for(bones,0..)|b,i|{
    k.parents[i]=b.parent;
    k.at[i]=b.at;
  }
  for(bones,0..)|b,i|if(b.twin){
    k.twinOf[i]=@intCast(k.count);
    k.count+=1;
  };
  for(bones,0..)|b,i|if(k.twinOf[i])|t|{
    k.parents[t]=if(b.parent)|p|k.twinOf[p] orelse p else null;
    k.at[t]=v3(-b.at[0],b.at[1],b.at[2]);
  };
  return k;
}
/// a turn (degrees: y, then x, then z, as a form's `rot` keeps them) as a matrix
pub fn turnOf(turns:V3)M4{
  return m.chain(&.{m.rotY(m.rad(turns[1])),m.rotX(m.rad(turns[0])),m.rotZ(m.rad(turns[2]))});
}
/// every bone of `k` turned by `turns` (each about its own joint, after
/// its parent's), the root also moved by `lift`, and the whole set where
/// `place` puts the sculpt: what carries each vertex from the sculpt at
/// rest to where it stands now (`out`'s first `k.count`). Parents come
/// before their children.
pub fn pose(k:*const Skeleton,turns:[]const V3,lift:V3,place:M4,out:[]M4)void{
  // each bone's frame now: where its joint has gone and how it is turned
  var frame:[maxBones]M4=undefined;
  for(0..k.count)|i|{
    // the joint, from its parent's (or the sculpt's origin), and its turn
    const from=if(k.parents[i])|p|k.at[p]else v3(0,0,0);
    const local=m.mul(m.translate(k.at[i]-from+(if(k.parents[i]==null)lift else v3(0,0,0))),turnOf(turns[i]));
    frame[i]=if(k.parents[i])|p|m.mul(frame[p],local)else m.mul(place,local);
    out[i]=m.mul(frame[i],m.translate(-k.at[i]));
  }
}
/// where every joint of `k` stands posed by `bones` (each one's `out` of
/// `pose`), for drawing them
pub fn joint(k:*const Skeleton,bones:[]const M4,i:usize)V3{return m.mulPoint(bones[i],k.at[i]);}
