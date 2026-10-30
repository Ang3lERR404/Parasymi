//! growth splines: the hidden skeleton a grown thing is built on and
//! grows along. Never drawn: a structure mesh lays out its splines first
//! (a trunk, then branches off it, offshoots off those), builds its pieces
//! along them with the usual primitives, and tags them (`along`, `on`).
//! Every tagged vertex then carries where it grows out of and when
//! (`vertex.Grow`), and the GPU grows it there (growth.glsl `growOut`) as
//! the thing's growth passes: shrunk into its spline
//! until the spline's growth front reaches it, tapering to a point at the
//! front, thickening as its spline finishes. A spline grows only once the
//! one it branches off is done (unless told otherwise, `After`), so the
//! growing is laid out by the skeleton alone, never by hand.
//!
//!   var k = growth.Skeleton.begin(b);
//!   const stem = k.trunk(&.{...}, .{});
//!   try k.tube(b, stem, .{...});            // grows along the stem
//!   const twig = k.branch(stem, 0.7, &.{...}, .{});
//!   try k.leaves(b, twig, .{...});          // unfold as the twig passes
//!   k.finish(b);                            // times to shares of growth
//!
//! A game makes it for its builder (`Grower(M, leaf)`, M its
//! `meshgen.Mesher`), handing it how it builds one leaf.
/// the standard library
const std=@import("std");
/// checks that hold in debug builds: no adding to a sealed skeleton
const assert=std.debug.assert;
/// the allocator a builder's growth records may fail with
const Allocator=std.mem.Allocator;
/// the test helpers
const testing=std.testing;
/// all the maths: vectors, splines, easing
const m=@import("../core/math.zig");
/// the mesh builder and its primitives (`Mesher`, vines, braids)
const mg=@import("meshgen.zig");
/// the GPU layouts, for the growth record each vertex carries
const vertex=@import("vertex.zig");
/// colour types: the eight-bit rgba pieces are tinted with
const color=@import("../core/color.zig");
/// the seeded random stream a run of leaves is varied by
const Rng=@import("../core/rng.zig").Rng;
/// a point or direction in three dimensions
const V3=m.V3;
/// splines a skeleton may hold
pub const max=64;
/// points each spline is resampled into, evenly by arc length
pub const res=33;
/// how long a spline's growth front is (it tapers to a point over it), as
/// a share of the time the spline takes to grow
pub const front:f32=0.35;
/// shortest time a spline takes, so a stub never pops in at once
const minTime:f32=0.05;
/// which spline of a skeleton: its index, in the order they were added
pub const Id=enum(u8){
  // (no named values: any index below `max`)
  _,
  /// the index it stands for, for reaching into the skeleton's list
  fn idx(id:Id)usize{return@intFromEnum(id);}
};
/// when a branch starts growing
pub const After=enum{
  /// once the spline it grows off is done (the default)
  done,
  /// as that spline's front passes the point it grows from
  passing,
  /// with that spline, from its first moment
  with,
};
/// how a branch grows: how fast, when it begins after its parent, and how
/// long its tapering front is
pub const Branch=struct{
  /// how long it takes per unit of its length (2: twice as slow)
  pace:f32=1,
  /// when it begins: once its parent is done, as its front passes, or with it
  after:After=.done,
  /// extra wait before it starts, in the skeleton's time units (per unit length)
  delay:f32=0,
  /// share of its own time its front is long (defaults to the file's `front`)
  front:f32=front,
};
/// one growth spline: its resampled points, its length, where it hangs off
/// its parent and when it grows
pub const Spline=struct{
  /// the `res` points it is resampled into, evenly by arc length
  pts:[res]V3,
  /// its length
  len:f32,
  /// the spline it grows off (null: the trunk)
  parent:?Id,
  /// how far along its parent it grows from (0..1)
  at:f32,
  /// when it starts and how long its front takes to reach its end (the
  /// skeleton's own time, made shares of the whole growth by `finish`)
  start:f32,
  /// how long its front takes to run from its root to its tip
  time:f32,
  /// how long its front is, a share of `time` (from `Branch.front`)
  front:f32,
};
/// the window (when it begins, how long it takes, shares of the whole
/// growth) of the last `tail` of a structure's growth
pub fn tailWindow(tail:f32)[2]f32{return.{1-tail,tail};}
/// how far a piece forming over the last `tail` of its structure's growth
/// has come when that growth is `g`: the same curve part.vert grows a
/// tagged piece by, for one the structure places itself
pub fn formed(tail:f32,g:f32)f32{return m.smooth(m.clamp01((g-(1-tail))/tail));}
/// one leaf of `Skeleton.leaves` at `u` along `path`, the `i`th of them
/// (`len` long, `width` wide, tu.x from `t0` to `t1`, coloured `col` to `tip`)
pub fn LeafFn(comptime B:type)type{
  return fn(b:*B,path:[]const V3,u:f32,i:usize,len:f32,width:f32,t0:f32,t1:f32,col:color.Rgba8,tip:color.Rgba8,seed:u64,rng:*Rng)Allocator.Error!void;
}
/// growth splines for the builder of mesher `M` (gfx/meshgen.zig
/// `Mesher`), its leaves built by `leaf`
pub fn Grower(comptime M:type,comptime leaf:LeafFn(M.Builder))type{
  return struct{
  /// the hidden skeleton a grown thing is laid out on: up to `max` splines,
  /// timed off each other, and the vertices built along them
  pub const Skeleton=struct{
    /// the splines, the first `n` in use
    s:[max]Spline=undefined,
    /// how many splines it holds
    n:usize=0,
    /// the first vertex built on it (`finish` times what follows)
    first:usize,
    /// set by `finish`: no more may be added
    sealed:bool=false,
    /// the share of the whole growth kept after everything on it is grown,
    /// for pieces emitted on their own that form last (a germinator's cups
    /// and core): they `tag` themselves with `tailWindow`
    tail:f32=0,
    /// a skeleton for what `b` builds from here on
    pub fn begin(b:*const M.Builder)Skeleton{return.{.first=b.mark()};}
    /// the first spline, through the control points `ctrl` (a Catmull-Rom
    /// curve through them, so it never runs straight or kinks).
    pub fn trunk(k:*Skeleton,ctrl:[]const V3,o:Branch)Id{
      return k.add(null,0,ctrl,o);
    }
    /// a spline off `parent` at `u` along it, through `ctrl` (its first point
    /// is moved onto the parent there, so it always grows out of it).
    pub fn branch(k:*Skeleton,parent:Id,u:f32,ctrl:[]const V3,o:Branch)Id{
      // the control points, the first moved onto the parent at `u`
      var c:[m.maxSpline]V3=undefined;
      @memcpy(c[0..ctrl.len],ctrl);
      c[0]=k.point(parent,u);
      return k.add(parent,u,c[0..ctrl.len],o);
    }
    /// a branch grown the way a vine grows (`mg.Growth`, its `start`
    /// replaced by the point on `parent`), through `ctrlN` control points.
    pub fn vine(k:*Skeleton,parent:?Id,u:f32,g:mg.Growth,ctrlN:usize,o:Branch)Id{
      // the growth, its start moved onto the parent when there is one
      var gg=g;
      if(parent)|p|gg.start=k.point(p,u);
      // the vine's control points, laid out by `growthPath`
      var c:[m.maxSpline]V3=undefined;
      mg.growthPath(gg,c[0..ctrlN]);
      return k.add(parent,u,c[0..ctrlN],o);
    }
    /// add a spline through `ctrl` off `parent` at `u`: resample it, measure it
    /// and time it after its parent as `o` asks; returns its id
    fn add(k:*Skeleton,parent:?Id,u:f32,ctrl:[]const V3,o:Branch)Id{
      assert(!k.sealed and k.n<max);
      // the new spline, timed below
      var sp:Spline=.{.pts=undefined,.len=0,.parent=parent,.at=m.clamp01(u),.start=0,.time=0,.front=o.front};
      m.splineResample(ctrl,&sp.pts);
      for(1..res)|i|sp.len+=m.len(sp.pts[i]-sp.pts[i-1]);
      sp.time=@max(minTime,sp.len*o.pace);
      if(parent)|p|{
        // the parent it waits on
        const ps=k.s[p.idx()];
        sp.start=ps.start+o.delay*sp.len+switch(o.after){
          .done=>ps.time,
          .passing=>ps.time*sp.at,
          .with=>0,
        };
      }else sp.start=o.delay*sp.len;
      k.s[k.n]=sp;
      k.n+=1;
      return@enumFromInt(k.n-1);
    }
    /// done building: every time on it, and in what was built on it, made
    /// a share of the whole growth, the last piece closing at 1 (less its
    /// `tail`).
    pub fn finish(k:*Skeleton,b:*M.Builder)void{
      assert(!k.sealed);
      k.sealed=true;
      // the latest moment anything on it is still growing, in its own time
      var end:f32=minTime;
      for(k.s[0..k.n])|sp|end=@max(end,sp.start+sp.time*(1+sp.front));
      // the growth records of everything built on it
      const gs:[]vertex.Grow=if(k.first<b.grow.items.len)b.grow.items[k.first..]else&.{};
      for(gs)|g|end=@max(end,g.at[0]+g.at[1]);
      end/=1-k.tail;
      for(k.s[0..k.n])|*sp|{
        sp.start/=end;
        sp.time/=end;
      }
      for(gs)|*g|for(&g.at)|*a|{
        a.*/=end;
      };
    }
    /// the spline `id` itself
    pub fn get(k:*const Skeleton,id:Id)*const Spline{return&k.s[id.idx()];}
    /// the point `u` (0..1, by arc length) along a spline
    pub fn point(k:*const Skeleton,id:Id,u:f32)V3{return m.alongPath(&k.s[id.idx()].pts,m.clamp01(u));}
    /// the way a spline runs at `u` along it (unit)
    pub fn tangent(k:*const Skeleton,id:Id,u:f32)V3{
      // one resampled step, as a share of the spline (to look either side)
      const d=1.0/@as(f32,res-1);
      return m.norm(k.point(id,u+d)-k.point(id,u-d));
    }
    /// the stretch `from..to` of a spline, evenly resampled into `out` (a tube,
    /// braid or leaf built along it)
    pub fn path(k:*const Skeleton,id:Id,from:f32,to:f32,out:[]V3)void{
      for(out,0..)|*p,i|p.*=k.point(id,m.lerp(from,to,m.ratio(i,out.len-1)));
    }
    /// when a spline's front reaches `u` along it (after `finish`, a share
    /// of the whole growth, 0..1)
    pub fn when(k:*const Skeleton,id:Id,u:f32)f32{
      // the spline whose front is asked after
      const sp=k.s[id.idx()];
      return sp.start+sp.time*m.clamp01(u);
    }
    /// when a spline has finished growing, its front closed at its tip
    pub fn done(k:*const Skeleton,id:Id)f32{
      // the spline whose finish is asked after
      const sp=k.s[id.idx()];
      return sp.start+sp.time*(1+sp.front);
    }
    /// how far along a spline (0..1) lies the point nearest `p`
    pub fn nearest(k:*const Skeleton,id:Id,p:V3)f32{
      // the spline's points
      const pts=&k.s[id.idx()].pts;
      // the nearest squared distance found yet, and where along it lies
      var best:f32=m.inf(f32);
      var at:f32=0;
      for(0..res-1)|i|{
        // one segment: its start, its run and its run's squared length
        const a=pts[i];
        const d=pts[i+1]-a;
        const dd=m.dot(d,d);
        // how far along the segment the nearest point lies (0..1), and that point
        const t=if(dd>m.eps)m.clamp01(m.dot(p-a,d)/dd)else 0;
        const q=a+d*m.splat3(t);
        // the squared distance from `p` to it
        const e=m.dot(p-q,p-q);
        if(e<best){
          best=e;
          at=(m.f(i)+t)/@as(f32,res-1);
        }
      }
      return at;
    }
    /// everything built since `start` grows along spline `id`: each vertex
    /// out of its nearest point on it as the front passes there (a tube,
    /// braid or loft built along it grows from its root to its tip, its tip
    /// tapering), thickening until the spline is done.
    pub fn along(k:*const Skeleton,b:*M.Builder,start:usize,id:Id)Allocator.Error!void{
      assert(!k.sealed);
      // the spline, how long its front is in time, and when it is done
      const sp=k.s[id.idx()];
      const span=sp.time*sp.front;
      const end=k.done(id);
      // a growth record for each vertex built since `start`
      const gs=try b.growOf(start);
      for(b.v.items[start..],gs)|v,*g|{
        // how far along the spline the vertex lies
        const u=k.nearest(id,v.pos);
        g.*=.{.from=k.point(id,u),.at=.{k.when(id,u),span,sp.start,end}};
      }
    }
    /// how a piece hung on a spline grows: how long, after what wait, and from where
    pub const On=struct{
      /// how long it takes to grow once begun, in the skeleton's time (null:
      /// as long as its spline's front)
      span:?f32=null,
      /// how long after the front reaches it it begins, in the skeleton's time
      delay:f32=0,
      /// where it grows out of, if not the point on the spline
      from:?V3=null,
    };
    /// everything built since `start` is one piece on spline `id` at `u` (a
    /// leaf, a cup, a pod): it grows out of that point (or `o.from`) once the
    /// front reaches it. Leaves unfold from their base, tips last (the game's shader).
    pub fn on(k:*const Skeleton,b:*M.Builder,start:usize,id:Id,u:f32,o:On)Allocator.Error!void{
      assert(!k.sealed);
      // when it begins, how long it takes, and where it grows out of
      const t0=k.when(id,u)+o.delay;
      const span=o.span orelse k.s[id.idx()].time*k.s[id.idx()].front;
      const from=o.from orelse k.point(id,u);
      for(try b.growOf(start))|*g|g.*=.{.from=from,.at=.{t0,span,0,0}};
    }
    // ---- building along it: the usual primitives, grown on the spline ----
    /// a tapering tube built the length of a spline
    pub const Tube=struct{
      /// its radius at the root
      r0:f32,
      /// its radius at the tip, a share of `r0`
      tip:f32=0.3,
      /// its colour
      col:color.Rgba8,
      /// the part role it is drawn with
      part:M.Part=M.defaultPart,
      /// how many sides round it has
      sides:u32=6,
      /// its tu.x from root to tip
      t0:f32=0,
      /// (its tu.x at the tip)
      t1:f32=1,
    };
    /// a tube the length of spline `id`, tapering, grown along it.
    pub fn tube(k:*const Skeleton,b:*M.Builder,id:Id,o:Tube)Allocator.Error!void{
      // the radius and tu.x at each of the spline's points
      var rs:[res]f32=undefined;
      var ts:[res]f32=undefined;
      mg.taperRadii(o.r0,o.tip,&rs);
      for(&ts,0..)|*t,i|t.*=m.lerp(o.t0,o.t1,m.ratio(i,res-1));
      // where the tube's vertices begin
      const s=b.mark();
      try b.tubeR(&k.s[id.idx()].pts,&ts,&rs,o.col,o.part,o.sides);
      try k.along(b,s,id);
    }
    /// a braid of twisting strands round a core, built the length of a spline
    pub const Braid=struct{
      /// how thick it is at the root
      girth:f32,
      /// its girth at the tip, a share of the root's
      tip:f32=0.35,
      /// how many strands twist round the core
      strands:u32=3,
      /// how many turns the strands make from root to tip
      twist:f32=2.2,
      /// how far each strand wanders from its even twist
      wobble:f32,
      /// the seed the wobble is drawn from
      seed:u64,
      /// the core's colour
      core:color.Rgba8,
      /// the strands' colour
      strand:color.Rgba8,
      /// its tu.x at the root
      t0:f32=0,
      /// its tu.x at the tip
      t1:f32=0,
      /// the role of the core showing between its strands
      corePart:M.Part=M.defaultPart,
    };
    /// a braid (`mg.braid`) the length of spline `id`, grown along it.
    pub fn braid(k:*const Skeleton,b:*M.Builder,id:Id,o:Braid)Allocator.Error!void{
      // the radius, tu.x and turn at each of the spline's points
      var rs:[res]f32=undefined;
      var ts:[res]f32=undefined;
      var turn:[res]f32=undefined;
      for(&rs,&ts,&turn,0..)|*r,*t,*a,i|{
        // how far along the spline this point is (0..1)
        const u=m.ratio(i,res-1);
        r.*=o.girth*m.lerp(1,o.tip,u);
        t.*=m.lerp(o.t0,o.t1,u);
        a.*=u*o.twist;
      }
      // where the braid's vertices begin
      const s=b.mark();
      try M.braidAround(b,&k.s[id.idx()].pts,&ts,&rs,&turn,o.strands,o.wobble,o.seed,o.core,o.strand,o.corePart);
      try k.along(b,s,id);
    }
    /// a run of leaves along a spline, each built the game's way
    pub const Leaves=struct{
      /// how many leaves
      n:u32,
      /// how long each leaf is
      len:f32,
      /// how wide each leaf is
      width:f32,
      /// the stretch of the spline they sit along
      from:f32=0.15,
      /// (where that stretch ends)
      to:f32=0.85,
      /// tu.x at each leaf's base
      t0:f32=0,
      /// tu.x at each leaf's tip
      t1:f32=1,
      /// the leaf's colour at its base
      col:color.Rgba8,
      /// the leaf's colour at its tip
      tip:color.Rgba8,
      /// the seed each leaf is varied by
      seed:u64,
    };
    /// `n` leaves along spline `id` (each as the game builds a leaf), each unfolding
    /// from its base once the front has passed it.
    pub fn leaves(k:*const Skeleton,b:*M.Builder,id:Id,o:Leaves)Allocator.Error!void{
      // the random stream the leaves are varied by
      var rng=Rng.init(o.seed);
      for(0..o.n)|i|{
        // how far along the spline this leaf sits, spaced evenly in the stretch
        const u=m.lerp(o.from,o.to,(m.f(i)+0.5)/m.f(o.n));
        // where the leaf's vertices begin
        const s=b.mark();
        try leaf(b,&k.s[id.idx()].pts,u,i,o.len,o.width,o.t0,o.t1,o.col,o.tip,o.seed,&rng);
        try k.on(b,s,id,u,.{});
      }
    }
  };
  /// everything built since `start` grows out of `from` over `window` of its
  /// structure's growth: a piece built as a mesh of its own (emitted by the
  /// structure) kept in step with the skeleton it stands on.
  pub fn tag(b:*M.Builder,start:usize,from:V3,window:[2]f32)Allocator.Error!void{
    for(try b.growOf(start))|*g|g.*=.{.from=from,.at=.{window[0],window[1],0,0}};
  }
  };
}
test"branches wait for their spline, the whole closing at one"{
  // the builder the test's pieces go into
  var b:T.Builder=.{.gpa=testing.allocator};
  defer b.deinit();
  // the skeleton laid out on it
  var k=G.Skeleton.begin(&b);
  // the trunk, straight up one unit
  const t=k.trunk(&.{m.v3(0,0,0),m.v3(0,0.5,0),m.v3(0,1,0)},.{});
  // a branch off the trunk's middle that waits for it to finish
  const a=k.branch(t,0.5,&.{m.v3(0,0,0),m.v3(0.3,0.7,0),m.v3(0.6,0.8,0)},.{});
  // a branch off the same point that starts as the front passes
  const p=k.branch(t,0.5,&.{m.v3(0,0,0),m.v3(-0.3,0.7,0)},.{.after=.passing});
  // a branch off the tip of `a`
  const c=k.branch(a,1,&.{m.v3(0,0,0),m.v3(0.6,1.1,0)},.{});
  k.finish(&b);
  // a branch starts on its parent, and grows once it is done
  try testing.expect(m.len(k.point(a,0)-k.point(t,0.5))<1e-4);
  try testing.expectApproxEqAbs(k.when(t,1),k.when(a,0),1e-5);
  try testing.expectApproxEqAbs(k.when(a,1),k.when(c,0),1e-5);
  // a passing one as the front goes by
  try testing.expectApproxEqAbs(k.when(t,0.5),k.when(p,0),1e-5);
  try testing.expect(k.when(t,0)==0);
  // the latest finish of any spline, which `finish` closes at one
  var last:f32=0;
  for([_]Id{t,a,p,c})|id|last=@max(last,k.done(id));
  try testing.expectApproxEqAbs(@as(f32,1),last,1e-5);
  try testing.expect(k.nearest(t,m.v3(0.1,0.25,0))>0.2 and k.nearest(t,m.v3(0.1,0.25,0))<0.3);
}
test"pieces built along a spline grow from its root to its tip"{
  // the builder the test's pieces go into
  var b:T.Builder=.{.gpa=testing.allocator};
  defer b.deinit();
  try b.put(m.v3(9,9,9),m.v3(0,1,0),white,0,0,.stem); // before: untouched
  // the skeleton laid out on it
  var k=G.Skeleton.begin(&b);
  // the trunk, straight up one unit
  const t=k.trunk(&.{m.v3(0,0,0),m.v3(0,1,0)},.{});
  // eight points along the trunk, for a tube
  var p:[8]V3=undefined;
  k.path(t,0,1,&p);
  // where the tube's vertices begin
  const s=b.mark();
  try b.tube(&p,&(.{0}**8),0.1,0.05,white,.stem,6);
  try k.along(&b,s,t);
  // a leaf on it, built later, still closes by the end
  // where the leaf's vertices begin
  const l=b.mark();
  try b.cone(m.v3(0,1,0),m.v3(1,0,0),0.3,0.05,white,0,.leaf);
  try k.on(&b,l,t,1,.{});
  k.tail=0.2;
  k.finish(&b);
  try testing.expectApproxEqAbs(@as(f32,0.8),b.grow.items[b.grow.items.len-1].at[0]+b.grow.items[b.grow.items.len-1].at[1],1e-5);
  try testing.expect(b.grow.items[0].at[1]==0);
  for(b.v.items[s..l],b.grow.items[s..l])|v,g|{
    try testing.expect(m.len(@as(V3,g.from)-m.v3(0,v.pos[1],0))<0.02);
    try testing.expectApproxEqAbs(v.pos[1]*k.get(t).time,g.at[0],0.02);
  }
}
/// plain white, for the tests' pieces
const white=color.Rgba8{.r=255,.g=255,.b=255,.a=255};
/// the tests' builder: two roles, leaves as cones
const T=mg.Mesher(enum(u32){stem,leaf},.stem);
/// the tests' leaf: a cone at `u` along the path
fn testLeaf(b:*T.Builder,path:[]const V3,u:f32,_:usize,len:f32,width:f32,t0:f32,_:f32,col:color.Rgba8,_:color.Rgba8,_:u64,_:*Rng)Allocator.Error!void{
  try b.cone(m.alongPath(path,u),m.v3(1,0,0),len,width,col,t0,.leaf);
}
/// the tests' growth splines, over their builder
const G=Grower(T,testLeaf);
