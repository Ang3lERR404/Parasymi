//! the one place for numeric helpers: scalars, angles, tile/world
//! coordinates, SIMD vectors and column-major 4x4 matrices (Vulkan clip
//! space: y down, depth 0..1). World: x east, y up, z south; 1 tile = 1 unit.
//! Game code uses this instead of reaching into std.math directly.
/// the standard library
const std=@import("std");
/// the standard maths underneath, reached only from here
const math=std.math;
/// the test helpers
const testing=std.testing;
/// stops on what must never happen
const assert=std.debug.assert;
/// the allocator type a `Path` takes
const Allocator=std.mem.Allocator;
/// whether safety checks are on in this build (they guard the inverses)
const runtimeSafety=std.debug.runtime_safety;
/// a vector that does its sums all lanes at once (SIMD): `s` lanes of `t`,
/// for positions, sizes and offsets that are added and scaled together
pub fn Vec(comptime t:type,comptime s:usize)type{return @Vector(s,t);}
/// a plain row of `s` boxes of `t`: an exact layout (GPU, saves), a table
/// of numbers, or lanes picked by an index only known at runtime
pub fn Vice(comptime t:type,comptime s:usize)type{return [s]t;}
/// a matrix as `a` columns, each a `Vec` of `s` lanes of `t` (column-major,
/// as the GPU reads it)
pub fn Mat(comptime t:type,comptime s:usize,comptime a:usize)type{return [a]Vec(t,s);}
/// a point or direction in space: x east, y up, z south, in tiles
pub const V3=Vec(f32,3);
/// four lanes: a point with its w, a colour with alpha, a matrix column
pub const V4=Vec(f32,4);
/// a 4x4 matrix as four columns (column-major, as the GPU reads it)
pub const M4=Mat(f32,4,4);
// ---- constants ----
/// below this, a vector is treated as zero (for normalisation).
pub const eps:f32=1e-8;
/// substep rate for springDamper: 4 substeps per 60 Hz tick.
/// Stiffer than this and stiff springs (k=80+) overshoot on long frames.
const springSubstepHz:f32=240;
/// Catmull-Rom samples per segment for arc-length resampling.
/// 8 is the sweet spot: 4 is visibly uneven on tight curves, 16 is wasted.
const splineDense:usize=8;
/// max control points per spline path (vine, tail, etc).
pub const maxSpline:usize=64;
/// milliseconds per second (frame timings are shown and budgeted in ms).
pub const msPerS=1000;
/// nanoseconds per millisecond (GPU time stamps count in ns).
pub const nsPerMs=1_000_000;
/// seconds per minute (autosave intervals are set in minutes).
pub const sPerMin=60;
/// |cos| of the angle between unit vectors above which they count as near
/// parallel: pick a different reference axis before crossing them.
pub const nearParallel:f32=0.9;
// ---- scalars ----
/// half a turn, in radians
pub const pi=math.pi;
/// a whole turn, in radians
pub const tau=math.tau;
/// the square root of two, a square's diagonal over its side
pub const sqrt2=math.sqrt2;
/// a quarter turn (pi / 2).
pub const halfPi=pi/2.0;
/// `x` held within `lo..hi`
pub const clamp=math.clamp;
/// `x` raised to the power `p`
pub const pow=math.pow;
/// the largest value an integer type can hold
pub const maxInt=math.maxInt;
/// infinity, as a float of the given type
pub const inf=math.inf;
/// int→f32. Takes anytype on purpose: callers pass i32, u8, u16, u32, usize.
/// This is the one sanctioned anytype in the file.
pub inline fn f(x:anytype)f32{return@floatFromInt(x);}
/// the value `t` of the way from `a` to `b` (0: a, 1: b; beyond either runs on)
pub inline fn lerp(a:f32,b:f32,t:f32)f32{return a+(b-a)*t;}
/// `x` held within 0..1
pub inline fn clamp01(x:f32)f32{return math.clamp(x,0,1);}
/// cubic smoothstep of a 0..1 `t`: eases in and out, flat at both ends
pub inline fn smooth(t:f32)f32{return t*t*(3-2*t);}
/// whole units of a non-negative float (e.g. ripe seeds) as integer type T.
pub inline fn floorTo(comptime T:type,x:f32)T{return@intFromFloat(@floor(x));}
/// fraction of `a` over `b` as f32 (e.g. progress counters).
pub inline fn ratio(a:anytype,b:anytype)f32{return f(a)/f(b);}
// ---- angles ----
/// the angle (radians, -pi..pi) of the point (`x`, `y`) seen from the origin
pub inline fn atan2(y:f32,x:f32)f32{return math.atan2(y,x);}
/// the angle (radians) whose sine is `x`, `x` first held within -1..1
pub inline fn asin(x:f32)f32{return math.asin(clamp(x,-1,1));}
/// the angle (radians) whose cosine is `x`, `x` first held within -1..1
pub inline fn acos(x:f32)f32{return math.acos(clamp(x,-1,1));}
/// which way `x` points: -1, 0 or 1
pub inline fn sign(x:f32)f32{return math.sign(x);}
/// |x|^p carrying x's sign (superellipse outlines).
pub fn signedPow(x:f32,p:f32)f32{
  // the magnitude raised, before its sign is put back
  const y=pow(f32,@abs(x),p);
  return if(x<0)-y else y;
}
/// a 0..1 value quantised to a byte (clamped; truncates like the GPU's unorm).
pub inline fn unorm8(x:f32)u8{return@intFromFloat(clamp01(x)*255);}
/// degrees to radians.
pub inline fn rad(deg:f32)f32{return deg*(pi/180.0);}
/// shortest signed difference `to - from`, wrapped into -pi..pi.
pub inline fn angleDiff(from:f32,to:f32)f32{return atan2(@sin(to-from),@cos(to-from));}
// ---- tiles ----
/// the tile containing a world coordinate.
pub inline fn tileOf(x:f32)i32{return@intFromFloat(@floor(x));}
/// the tile (x, z) under a world position.
pub inline fn tileAt(p:V3)Vice(i32,2){return.{tileOf(p[0]),tileOf(p[2])};}
/// world-space centre of a size x size footprint anchored at tile (x, z).
pub inline fn footprintCentre(x:i32,z:i32,size:u8,y:f32)V3{
  // half the footprint's width, from its corner to its centre
  const half=f(size)/2;
  return.{f(x)+half,y,f(z)+half};
}
/// world-space centre of tile (x, z) at height y.
pub inline fn tileCentre(x:i32,z:i32,y:f32)V3{return footprintCentre(x,z,1,y);}
/// the tiles of a size x size footprint anchored at (x, z), row by row:
/// `var it = m.footprint(x, z, 2); while (it.next()) |t| ...` (t = .{x, z}).
pub const Footprint=struct{
  /// the anchor tile's x
  x:i32,
  /// the anchor tile's z
  z:i32,
  /// how many tiles a side the footprint spans
  size:u8,
  /// how many tiles have been handed out so far
  k:u16=0,
  /// the next tile as .{x, z}, or null once all size x size are visited
  pub fn next(fp:*Footprint)?Vice(i32,2){
    // how many tiles the whole footprint holds
    const n=@as(u16,fp.size)*fp.size;
    if(fp.k>=n)return null;
    defer fp.k+=1;
    return.{fp.x+@as(i32,fp.k%fp.size),fp.z+@as(i32,fp.k/fp.size)};
  }
};
/// a walk over the tiles of a `size` x `size` footprint anchored at (x, z)
pub inline fn footprint(x:i32,z:i32,size:u8)Footprint{return.{.x=x,.z=z,.size=size};}
/// offsets on the square ring at Chebyshev distance `r` (r = 0 is the centre
/// alone), row by row; walking r = 0, 1, 2… visits tiles nearest-first.
pub const Ring=struct{
  /// the ring's distance from the centre
  r:i32,
  /// the next offset's x, -r..r
  dx:i32,
  /// the next offset's z, -r..r
  dz:i32,
  /// the next offset on the ring as .{dx, dz}, or null once it is walked
  pub fn next(it:*Ring)?Vice(i32,2){
    while(it.dz<=it.r){
      // the offset handed out this call
      const o:Vice(i32,2)=.{it.dx,it.dz};
      // inner rows touch the ring only at their ends
      // whether this row is the ring's top or bottom, walked whole
      const edge=@abs(it.dz)==it.r;
      it.dx=if(it.dx>=it.r)-it.r else if(edge)it.dx+1 else it.r;
      if(it.dx==-it.r)it.dz+=1;
      return o;
    }
    return null;
  }
};
/// a walk round the square ring at distance `r`, from its top-left corner
pub inline fn ring(r:i32)Ring{return.{.r=r,.dx=-r,.dz=-r};}
/// the four facings in order, for `for (m.dirs) |d|`.
pub const dirs=[4]Dir{0,1,2,3};
/// one of four facings: +x (east), +z (south), -x (west), -z (north).
pub const Dir=u2;
/// a facing as a step on the tile grid: x and z each -1, 0 or 1
pub const DirVec=struct{
  /// the step east (+) or west (-)
  x:i32,
  /// the step south (+) or north (-)
  z:i32
};
/// the one-tile step a facing takes: east, south, west or north
pub fn dirVec(d:Dir)DirVec{
  return switch(d){
    0=>.{.x=1,.z=0},
    1=>.{.x=0,.z=1},
    2=>.{.x=-1,.z=0},
    3=>.{.x=0,.z=-1},
  };
}
/// yaw that turns a +x-facing model to face `d`.
pub inline fn dirYaw(d:Dir)f32{return-f(d)*pi/2.0;}
// ---- vectors ----
/// a vector from its three parts
pub inline fn v3(x:f32,y:f32,z:f32)V3{return.{x,y,z};}
/// a three-lane vector with every lane `s`
pub inline fn splat3(s:f32)V3{return@splat(s);}
/// a four-lane vector with every lane `s`
pub inline fn splat4(s:f32)V4{return@splat(s);}
/// the dot product: how far `a` and `b` lean the same way
pub inline fn dot(a:V3,b:V3)f32{return@reduce(.Add,a*b);}
/// a vector's length
pub inline fn len(a:V3)f32{return@sqrt(dot(a,a));}
/// the vector turned unit length; one too short to point anywhere is left as is
pub inline fn norm(a:V3)V3{
  // its length, divided out
  const l=len(a);
  return if(l>eps)a/splat3(l)else a;
}
/// the vector at right angles to both `a` and `b` (right-handed)
pub inline fn cross(a:V3,b:V3)V3{
  return.{a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]};
}
/// the point `t` of the way from `a` to `b`, lane by lane
pub inline fn lerpV(a:V3,b:V3,t:f32)V3{return a+(b-a)*splat3(t);}
/// the centre of a triangle.
pub inline fn centroid(a:V3,b:V3,c:V3)V3{return(a+b+c)*splat3(1.0/3.0);}
/// a point at fraction `k` (0..1) along a polyline, by point index (for
/// evenly resampled paths; see `Path` for arc length on uneven ones).
pub fn alongPath(path:[]const V3,k:f32)V3{
  // where along the points `k` falls, as a fractional index
  const pos=k*f(path.len-1);
  // the segment it falls in, the last one at most
  const i:usize=@min(@as(usize,@intFromFloat(pos)),path.len-2);
  return lerpV(path[i],path[i+1],pos-f(i));
}
// ---- splines ----
/// the Catmull-Rom curve between `p1` (t=0) and `p2` (t=1); `p0` and `p3`
/// shape the tangents at either end.
pub fn catmullRom(p0:V3,p1:V3,p2:V3,p3:V3,t:f32)V3{
  // t squared and cubed
  const t2=t*t;
  const t3=t2*t;
  return(p1*splat3(2)+(p2-p0)*splat3(t) +
    (p0*splat3(2)-p1*splat3(5)+p2*splat3(4)-p3)*splat3(t2) +
    (p1*splat3(3)-p0-p2*splat3(3)+p3)*splat3(t3))*splat3(0.5);
}
/// resample the Catmull-Rom spline through every point of `pts` into `out`,
/// evenly spaced by arc length. The end points repeat as their own outer
/// control points, so the curve starts and ends exactly on them.
pub fn splineResample(pts:[]const V3,out:[]V3)void{
  assert(pts.len>=2 and pts.len<=maxSpline and out.len>=2);
  // how many control points there are
  const n=pts.len;
  // the curve sampled densely, and the running arc length at each sample
  var dense:[(maxSpline-1)*splineDense+1]V3=undefined;
  var at:[(maxSpline-1)*splineDense+1]f32=undefined;
  // how many dense samples have been taken
  var k:usize=0;
  for(0..n-1)|seg|{
    // the outer control points, the ends standing in for themselves
    const p0=pts[if(seg==0)0 else seg-1];
    const p3=pts[@min(seg+2,n-1)];
    for(0..splineDense)|j|{
      dense[k]=catmullRom(p0,pts[seg],pts[seg+1],p3,ratio(j,splineDense));
      k+=1;
    }
  }
  dense[k]=pts[n-1];
  at[0]=0;
  for(1..k+1)|i|at[i]=at[i-1]+len(dense[i]-dense[i-1]);
  // the curve's whole length
  const total=at[k];
  // the dense segment being walked, carried from one output point to the next
  var i:usize=0;
  for(out,0..)|*o,j|{
    // the arc length this output point wants
    const want=total*ratio(j,out.len-1);
    while(i+1<k and at[i+1]<want)i+=1;
    // the length of the dense segment it falls in
    const span=at[i+1]-at[i];
    o.*=lerpV(dense[i],dense[i+1],if(span>eps)clamp01((want-at[i])/span)else 0);
  }
}
// ---- paths (precomputed arc-length polylines) ----
/// A polyline with precomputed cumulative arc lengths for O(log n) lookup.
/// Build once when the path is set; call `.at(k)` every frame.
pub const Path=struct{
  /// the points the path runs through
  pts:[]const V3,
  /// the arc length from the first point to each point
  cum:[]const f32,
  /// the whole path's length
  total:f32,
  /// build a Path from a slice of points. Allocates `cum` via `alloc`.
  pub fn build(pts:[]const V3,alloc:Allocator)Allocator.Error!Path{
    assert(pts.len>=2);
    // the running lengths, the first point at zero
    const cum=try alloc.alloc(f32,pts.len);
    cum[0]=0;
    for(1..pts.len)|i|cum[i]=cum[i-1]+len(pts[i]-pts[i-1]);
    return.{.pts=pts,.cum=cum,.total=cum[pts.len-1]};
  }
  /// frees the running lengths `build` allocated
  pub fn deinit(self:Path,alloc:Allocator)void{alloc.free(self.cum);}
  /// point at fraction k (0..1) along the path, evenly spaced by arc length.
  pub fn at(self:Path,k:f32)V3{
    // the arc length wanted
    const want=clamp01(k)*self.total;
    // the bracket the binary search narrows: a point at or before it, one after
    var lo:usize=0;
    var hi:usize=self.pts.len-1;
    while(lo+1<hi){
      // the bracket's middle
      const mid=(lo+hi)/2;
      if(self.cum[mid]<=want)lo=mid else hi=mid;
    }
    // the length of the segment found, and how far into it the length falls
    const span=self.cum[hi]-self.cum[lo];
    const t=if(span>eps)(want-self.cum[lo])/span else 0;
    return lerpV(self.pts[lo],self.pts[hi],t);
  }
};
// ---- matrices ----
/// the matrix that changes nothing
pub const identity:M4=.{
  .{1,0,0,0},.{0,1,0,0},.{0,0,1,0},.{0,0,0,1},
};
/// the product `a * b`: `b`'s transform applied first, then `a`'s
pub fn mul(a:M4,b:M4)M4{
  // the product, filled column by column
  var r:M4=undefined;
  inline for(0..4)|c|{
    r[c]=a[0]*splat4(b[c][0])+a[1]*splat4(b[c][1]) +
      a[2]*splat4(b[c][2])+a[3]*splat4(b[c][3]);
  }
  return r;
}
/// the four-lane vector `v` carried through `m`
pub fn mulV(m:M4,v:V4)V4{
  return m[0]*splat4(v[0])+m[1]*splat4(v[1]) +
    m[2]*splat4(v[2])+m[3]*splat4(v[3]);
}
/// a point through `m` (w = 1).
pub fn mulPoint(m:M4,p:V3)V3{
  // the point carried, with w = 1
  const r=mulV(m,.{p[0],p[1],p[2],1});
  return.{r[0],r[1],r[2]};
}
/// a direction through `m` (w = 0: no translation; not renormalised).
pub fn mulDir(m:M4,d:V3)V3{
  // the direction carried, with w = 0
  const r=mulV(m,.{d[0],d[1],d[2],0});
  return.{r[0],r[1],r[2]};
}
/// a covector (a normal, a gradient) through the transform whose inverse is
/// `inv`: by the inverse-transpose, so it stays perpendicular to what the
/// transform carries (not renormalised).
pub fn mulCovector(inv:M4,d:V3)V3{
  return.{
    dot(.{inv[0][0],inv[0][1],inv[0][2]},d),
    dot(.{inv[1][0],inv[1][1],inv[1][2]},d),
    dot(.{inv[2][0],inv[2][1],inv[2][2]},d),
  };
}
/// right-handed perspective for Vulkan (y flipped, depth 0..1).
pub fn perspective(fovy:f32,aspect:f32,near:f32,far:f32)M4{
  // the focal scale: one over the tangent of half the vertical view angle
  const k=1/@tan(fovy*0.5);
  return.{
    .{k/aspect,0,0,0},
    .{0,-k,0,0},
    .{0,0,far/(near-far),-1},
    .{0,0,near*far/(near-far),0},
  };
}
/// right-handed orthographic projection for Vulkan (depth 0..1, `near`
/// and `far` distances along -z), of the box (l..r, b..t) in view space;
/// y is not flipped (shadow maps sample it as drawn)
pub fn ortho(l:f32,r:f32,b:f32,t:f32,near:f32,far:f32)M4{
  return.{
    .{2/(r-l),0,0,0},
    .{0,2/(t-b),0,0},
    .{0,0,-1/(far-near),0},
    .{-(r+l)/(r-l),-(t+b)/(t-b),-near/(far-near),1},
  };
}
/// the view matrix of an eye at `eye` looking at `at`, with `up` roughly
/// overhead (right-handed: the eye looks down its -z)
pub fn lookAt(eye:V3,at:V3,up:V3)M4{
  // the eye's forward, side and true up
  const fw=norm(at-eye);
  const s=norm(cross(fw,up));
  const u=cross(s,fw);
  return.{
    .{s[0],u[0],-fw[0],0},
    .{s[1],u[1],-fw[1],0},
    .{s[2],u[2],-fw[2],0},
    .{-dot(s,eye),-dot(u,eye),dot(fw,eye),1},
  };
}
/// a move by `t`
pub fn translate(t:V3)M4{
  return.{.{1,0,0,0},.{0,1,0,0},.{0,0,1,0},.{t[0],t[1],t[2],1}};
}
/// a stretch by `s` along each axis
pub fn scale3(s:V3)M4{
  return.{.{s[0],0,0,0},.{0,s[1],0,0},.{0,0,s[2],0},.{0,0,0,1}};
}
/// a turn of `a` radians about the x axis
pub fn rotX(a:f32)M4{
  // the angle's cosine and sine
  const c=@cos(a);const s=@sin(a);
  return.{.{1,0,0,0},.{0,c,s,0},.{0,-s,c,0},.{0,0,0,1}};
}
/// a turn of `a` radians about the y axis
pub fn rotY(a:f32)M4{
  // the angle's cosine and sine
  const c=@cos(a);const s=@sin(a);
  return.{.{c,0,-s,0},.{0,1,0,0},.{s,0,c,0},.{0,0,0,1}};
}
/// a turn of `a` radians about the z axis
pub fn rotZ(a:f32)M4{
  // the angle's cosine and sine
  const c=@cos(a);const s=@sin(a);
  return.{.{c,s,0,0},.{-s,c,0,0},.{0,0,1,0},.{0,0,0,1}};
}
/// chain transforms parent-first: chain(&.{a, b, c}) == a * b * c.
pub fn chain(ms:[]const M4)M4{
  // the product so far
  var r:M4=identity;
  for(ms)|x|r=mul(r,x);
  return r;
}
/// where a transform carries the origin: its translation
pub fn origin(a:M4)V3{return.{a[3][0],a[3][1],a[3][2]};}
/// a rotation taking +Y onto `dir` (a unit vector); the roll around it is arbitrary.
pub fn alignY(dir:V3)M4{
  // an axis surely not along `dir`, to cross with it
  const ref=if(@abs(dir[2])<nearParallel)v3(0,0,1)else v3(1,0,0);
  // the two axes at right angles to `dir`, making the frame
  const x=norm(cross(dir,ref));
  const z=cross(x,dir);
  return.{.{x[0],x[1],x[2],0},.{dir[0],dir[1],dir[2],0},.{z[0],z[1],z[2],0},.{0,0,0,1}};
}
// ---- springs ----
/// critically damped spring step (for procedural secondary motion).
/// Uses the exact closed-form solution, so it is stable for any `dt`.
pub fn spring(pos:*f32,vel:*f32,target:f32,freq:f32,dt:f32)void{
  // how far from the target, and the spring's carried momentum term
  const x=pos.*-target;
  const j=vel.*+freq*x;
  // how much the motion dies away over `dt`
  const e=@exp(-freq*dt);
  pos.*=target+(x+j*dt)*e;
  vel.*=(vel.*-freq*j*dt)*e;
}
/// a damped spring-mass pulling `pos` toward `rest` under an extra `force`:
/// `m a = -k (pos - rest) - c v + force`. Substepped so stiff springs stay
/// stable over long frames.
pub fn springDamper(pos:*V3,vel:*V3,rest:V3,k:f32,c:f32,mass:f32,force:V3,dt:f32)void{
  // how many substeps, enough for 240 a second
  const n=@max(@as(u32,@intFromFloat(@ceil(dt*springSubstepHz))),1);
  // each substep's length (s)
  const h=dt/f(n);
  for(0..n)|_|{
    // the pull, the drag and the force together, over the mass
    const acc=(force-(pos.*-rest)*splat3(k)-vel.* * splat3(c))/splat3(mass);
    vel.*+=acc*splat3(h);
    pos.*+=vel.* * splat3(h);
  }
}
// ---- inverses ----
/// column `c`'s first three lanes: an axis (or, for 3, the translation)
fn column(m:M4,c:usize)V3{return.{m[c][0],m[c][1],m[c][2]};}
/// a matrix whose upper 3x3 has rows `r0..r2` and translation `-R * t`.
fn fromRows(r0:V3,r1:V3,r2:V3,t:V3)M4{
  return.{
    .{r0[0],r1[0],r2[0],0},
    .{r0[1],r1[1],r2[1],0},
    .{r0[2],r1[2],r2[2],0},
    .{-dot(r0,t),-dot(r1,t),-dot(r2,t),1},
  };
}
/// inverse of a rigid transform (rotation + translation only): transpose the 3x3.
pub fn inverseRigid(m:M4)M4{
  return fromRows(column(m,0),column(m,1),column(m,2),column(m,3));
}
/// inverse of an affine transform (rotation/scale/shear + translation;
/// bottom row 0 0 0 1). The 3x3 inverts by cofactors.
pub fn inverseAffine(m:M4)M4{
  // the three axis columns
  const c0=column(m,0);
  const c1=column(m,1);
  const c2=column(m,2);
  // the cofactor of the first column, and the determinant it gives
  const x12=cross(c1,c2);
  const det=dot(c0,x12);
  if(runtimeSafety and det==0)@panic("singular matrix in m.inverseAffine");
  // one over the determinant, in every lane
  const id=splat3(1/det);
  return fromRows(x12*id,cross(c2,c0)*id,cross(c0,c1)*id,column(m,3));
}
/// general 4x4 inverse (full cofactor expansion).
/// Only needed for view-projection (mouse picking), which is non-affine.
/// All other inverses in the game use inverseAffine or inverseRigid.
/// The [16]f32 layout is the standard formulation; it doesn't decompose
/// cleanly into 3D cross products the way the 3x3 case does.
pub fn inverse(m:M4)M4{
  // Fast path: if affine, delegate to the simpler/faster version.
  if(m[0][3]==0 and m[1][3]==0 and m[2][3]==0 and m[3][3]==1)
    return inverseAffine(m);
  // the matrix as sixteen plain numbers, column by column
  var a:[16]f32=undefined;
  inline for(0..4)|c|inline for(0..4)|r|{a[c*4+r]=m[c][r];};
  // the adjugate, cofactor by cofactor
  var inv:[16]f32=undefined;
  inv[0]=a[5]*a[10]*a[15]-a[5]*a[11]*a[14]-a[9]*a[6]*a[15]+a[9]*a[7]*a[14]+a[13]*a[6]*a[11]-a[13]*a[7]*a[10];
  inv[4]=-a[4]*a[10]*a[15]+a[4]*a[11]*a[14]+a[8]*a[6]*a[15]-a[8]*a[7]*a[14]-a[12]*a[6]*a[11]+a[12]*a[7]*a[10];
  inv[8]=a[4]*a[9]*a[15]-a[4]*a[11]*a[13]-a[8]*a[5]*a[15]+a[8]*a[7]*a[13]+a[12]*a[5]*a[11]-a[12]*a[7]*a[9];
  inv[12]=-a[4]*a[9]*a[14]+a[4]*a[10]*a[13]+a[8]*a[5]*a[14]-a[8]*a[6]*a[13]-a[12]*a[5]*a[10]+a[12]*a[6]*a[9];
  inv[1]=-a[1]*a[10]*a[15]+a[1]*a[11]*a[14]+a[9]*a[2]*a[15]-a[9]*a[3]*a[14]-a[13]*a[2]*a[11]+a[13]*a[3]*a[10];
  inv[5]=a[0]*a[10]*a[15]-a[0]*a[11]*a[14]-a[8]*a[2]*a[15]+a[8]*a[3]*a[14]+a[12]*a[2]*a[11]-a[12]*a[3]*a[10];
  inv[9]=-a[0]*a[9]*a[15]+a[0]*a[11]*a[13]+a[8]*a[1]*a[15]-a[8]*a[3]*a[13]-a[12]*a[1]*a[11]+a[12]*a[3]*a[9];
  inv[13]=a[0]*a[9]*a[14]-a[0]*a[10]*a[13]-a[8]*a[1]*a[14]+a[8]*a[2]*a[13]+a[12]*a[1]*a[10]-a[12]*a[2]*a[9];
  inv[2]=a[1]*a[6]*a[15]-a[1]*a[7]*a[14]-a[5]*a[2]*a[15]+a[5]*a[3]*a[14]+a[13]*a[2]*a[7]-a[13]*a[3]*a[6];
  inv[6]=-a[0]*a[6]*a[15]+a[0]*a[7]*a[14]+a[4]*a[2]*a[15]-a[4]*a[3]*a[14]-a[12]*a[2]*a[7]+a[12]*a[3]*a[6];
  inv[10]=a[0]*a[5]*a[15]-a[0]*a[7]*a[13]-a[4]*a[1]*a[15]+a[4]*a[3]*a[13]+a[12]*a[1]*a[7]-a[12]*a[3]*a[5];
  inv[14]=-a[0]*a[5]*a[14]+a[0]*a[6]*a[13]+a[4]*a[1]*a[14]-a[4]*a[2]*a[13]-a[12]*a[1]*a[6]+a[12]*a[2]*a[5];
  inv[3]=-a[1]*a[6]*a[11]+a[1]*a[7]*a[10]+a[5]*a[2]*a[11]-a[5]*a[3]*a[10]-a[9]*a[2]*a[7]+a[9]*a[3]*a[6];
  inv[7]=a[0]*a[6]*a[11]-a[0]*a[7]*a[10]-a[4]*a[2]*a[11]+a[4]*a[3]*a[10]+a[8]*a[2]*a[7]-a[8]*a[3]*a[6];
  inv[11]=-a[0]*a[5]*a[11]+a[0]*a[7]*a[9]+a[4]*a[1]*a[11]-a[4]*a[3]*a[9]-a[8]*a[1]*a[7]+a[8]*a[3]*a[5];
  inv[15]=a[0]*a[5]*a[10]-a[0]*a[6]*a[9]-a[4]*a[1]*a[10]+a[4]*a[2]*a[9]+a[8]*a[1]*a[6]-a[8]*a[2]*a[5];
  // the determinant, from the first row and its cofactors
  const det=a[0]*inv[0]+a[1]*inv[4]+a[2]*inv[8]+a[3]*inv[12];
  if(runtimeSafety and det==0)@panic("singular matrix in m.inverse");
  // one over the determinant
  const id=1/det;
  // the inverse, filled from the adjugate
  var r:M4=undefined;
  inline for(0..4)|c|inline for(0..4)|rr|{r[c][rr]=inv[c*4+rr]*id;};
  return r;
}
// ---- view frusta ----
/// the six planes of what a view-projection matrix sees (each xyz its
/// inward normal, w its offset), for culling what lies outside it.
pub const Frustum=struct{
  /// left, right, top, bottom, near and far, each normalised
  planes:[6]V4,
  /// planes from a (Vulkan, depth 0..1) view-projection matrix
  pub fn of(vp:M4)Frustum{
    // the matrix's rows
    var row:[4]V4=undefined;
    inline for(0..4)|i|row[i]=.{vp[0][i],vp[1][i],vp[2][i],vp[3][i]};
    // each plane from two rows, as Gribb and Hartmann give them
    var fr:Frustum=.{.planes=.{
      row[3]+row[0],row[3]-row[0],
      row[3]+row[1],row[3]-row[1],
      row[2],row[3]-row[2],
    }};
    for(&fr.planes)|*pl|{
      // the plane's normal length, divided out
      const l=len(v3(pl[0],pl[1],pl[2]));
      pl.*=pl.*/splat4(l);
    }
    return fr;
  }
  /// whether any of a sphere at `c` with radius `r` can be seen
  pub fn sphere(fr:*const Frustum,c:V3,r:f32)bool{
    for(fr.planes)|pl|{
      if(pl[0]*c[0]+pl[1]*c[1]+pl[2]*c[2]+pl[3]<-r)return false;
    }
    return true;
  }
  /// whether any of a capsule from `a` to `b` with radius `r` can be seen
  /// (conservatively: only a plane both ends lie beyond culls it)
  pub fn capsule(fr:*const Frustum,a:V3,b:V3,r:f32)bool{
    for(fr.planes)|pl|{
      // how far each end lies inside the plane (negative: outside)
      const da=pl[0]*a[0]+pl[1]*a[1]+pl[2]*a[2]+pl[3];
      const db=pl[0]*b[0]+pl[1]*b[1]+pl[2]*b[2]+pl[3];
      if(@max(da,db)<-r)return false;
    }
    return true;
  }
};
// ---- tests ----
test"spring-damper settles where its force balances"{
  // where the mass is and how fast it moves
  var p=v3(0,0,0);
  var v=v3(1,0,0);
  // the stiffness, and the sideways force that holds it off its rest
  const k=60.0;
  const forceZ=3.0;
  for(0..120)|_|springDamper(&p,&v,v3(0,1,0),k,6,0.8,v3(0,0,forceZ),1.0/30.0);
  // equilibrium: displacement = force / k = 3/60 = 0.05
  try testing.expect(len(p-v3(0,1,forceZ/k))<1e-3);
  try testing.expect(len(v)<1e-3);
}
test"spring is stable for huge steps"{
  // the spring's position and its speed, flung hard to start
  var p:f32=0;
  var v:f32=50;
  for(0..20)|_|spring(&p,&v,1,7,0.75);
  try testing.expectApproxEqAbs(@as(f32,1),p,1e-3);
  try testing.expect(@abs(v)<1e-2);
}
test"points move with a transform, directions only turn"{
  // a move then a quarter turn about y
  const t=chain(&.{translate(v3(1,2,3)),rotY(pi/2.0)});
  // a point and a direction carried through it
  const p=mulPoint(t,v3(1,0,0));
  const d=mulDir(t,v3(1,0,0));
  try testing.expectApproxEqAbs(@as(f32,1),p[0],1e-5);
  try testing.expectApproxEqAbs(@as(f32,1),@abs(p[2]-3),1e-5);
  try testing.expectApproxEqAbs(@as(f32,2),p[1],1e-5);
  try testing.expectApproxEqAbs(@as(f32,0),d[0],1e-5);
  try testing.expectApproxEqAbs(@as(f32,1),@abs(d[2]),1e-5);
  try testing.expectEqual(@as(f32,-8),signedPow(-2,3));
  try testing.expectEqual(@as(f32,4),signedPow(2,2));
}
test"covectors stay perpendicular through a sheared, unevenly scaled transform"{
  // a move, turns and an uneven stretch, all in one
  const t=chain(&.{translate(v3(1,2,3)),rotY(0.7),scale3(v3(3,0.5,1)),rotZ(0.4)});
  // a direction, and a normal at right angles to it
  const along=v3(1,1,0);
  const n=v3(1,-1,0);
  // the direction carried, and the normal carried by the inverse-transpose
  const moved=mulDir(t,along);
  const turned=mulCovector(inverseAffine(t),n);
  try testing.expectApproxEqAbs(@as(f32,0),dot(moved,turned),1e-5);
  try testing.expect(len(turned)>0.1);
}
test"inverse roundtrip"{
  // a camera's whole view-projection, which is not affine
  const p=mul(perspective(0.8,1.5,0.1,100),lookAt(v3(3,10,8),v3(0,0,0),v3(0,1,0)));
  // it times its inverse, which should be the identity
  const i=mul(inverse(p),p);
  inline for(0..4)|c|inline for(0..4)|r|{
    try testing.expectApproxEqAbs(identity[c][r],i[c][r],1e-3);
  };
}
test"affine and rigid inverses"{
  // an affine transform, stretched unevenly
  const aff=chain(&.{translate(v3(3,-2,5)),rotY(0.7),rotX(-0.4),scale3(v3(2,0.5,1.5))});
  // a rigid one, only moved and turned
  const rig=chain(&.{translate(v3(-1,4,2)),rotY(1.9),rotZ(0.3)});
  for([_]M4{mul(inverseAffine(aff),aff),mul(aff,inverseAffine(aff)),mul(inverseRigid(rig),rig)})|i|{
    inline for(0..4)|c|inline for(0..4)|r|{
      try testing.expectApproxEqAbs(identity[c][r],i[c][r],1e-4);
    };
  }
  // the affine inverse, and the general one, which must agree
  const ia=inverseAffine(aff);
  const ig=inverse(aff);
  inline for(0..4)|c|inline for(0..4)|r|{
    try testing.expectApproxEqAbs(ig[c][r],ia[c][r],1e-4);
  };
}
test"catmull-rom passes through its inner points"{
  // four control points, the curve running from b to c
  const a=v3(0,0,0);
  const b=v3(1,2,0);
  const c=v3(3,2,1);
  const d=v3(4,0,1);
  try testing.expectEqual(b,catmullRom(a,b,c,d,0));
  // the curve's far end
  const e=catmullRom(a,b,c,d,1);
  try testing.expect(len(e-c)<1e-5);
  // the middle of a straight run
  const mid=catmullRom(v3(0,0,0),v3(1,0,0),v3(2,0,0),v3(3,0,0),0.5);
  try testing.expect(len(mid-v3(1.5,0,0))<1e-5);
}
test"spline resampling keeps the ends and evens the spacing"{
  // a bent run of control points
  const pts=[_]V3{v3(0,0,0),v3(0,1,0),v3(0.2,3,0),v3(1,3.5,0.5)};
  // the run resampled to sixteen points
  var out:[16]V3=undefined;
  splineResample(&pts,&out);
  try testing.expect(len(out[0]-pts[0])<1e-5);
  try testing.expect(len(out[15]-pts[3])<1e-4);
  // the first gap, which every other must match
  const step=len(out[1]-out[0]);
  for(1..out.len)|i|try testing.expectApproxEqAbs(step,len(out[i]-out[i-1]),step*0.1);
}
test"alignY maps +Y onto the direction, orthonormally"{
  for([_]V3{v3(0,1,0),v3(0,0,1),norm(v3(1,-2,0.5))})|d|{
    // the frame for this direction
    const r=alignY(d);
    // where +Y lands
    const y=mulV(r,.{0,1,0,0});
    try testing.expect(len(v3(y[0],y[1],y[2])-d)<1e-5);
    // where +X and +Z land
    const x=v3(r[0][0],r[0][1],r[0][2]);
    const z=v3(r[2][0],r[2][1],r[2][2]);
    try testing.expectApproxEqAbs(@as(f32,1),dot(cross(x,d),z),1e-5);
  }
}
test"Path.at gives evenly spaced points"{
  // four points evenly along x
  const pts=[_]V3{v3(0,0,0),v3(1,0,0),v3(2,0,0),v3(3,0,0)};
  // the path over them
  const p=try Path.build(&pts,testing.allocator);
  defer p.deinit(testing.allocator);
  try testing.expectApproxEqAbs(@as(f32,0.0),p.at(0.0)[0],1e-5);
  try testing.expectApproxEqAbs(@as(f32,1.5),p.at(0.5)[0],1e-5);
  try testing.expectApproxEqAbs(@as(f32,3.0),p.at(1.0)[0],1e-5);
}
test"a frustum keeps what is inside it and culls what is not"{
  // the identity's view: the clip box itself
  const fr=Frustum.of(identity);
  try testing.expect(fr.sphere(v3(0,0,0.5),0.1));
  try testing.expect(!fr.sphere(v3(3,0,0.5),0.5));
  try testing.expect(fr.sphere(v3(1.3,0,0.5),0.5));
  try testing.expect(!fr.sphere(v3(0,0,-1),0.5));
  // a capsule reaching in from outside is kept, one wholly outside is not
  try testing.expect(fr.capsule(v3(3,0,0.5),v3(0,0,0.5),0.1));
  try testing.expect(!fr.capsule(v3(3,0,0.5),v3(2,0,0.5),0.5));
}
test"ortho maps its box onto clip space, near to depth 0, far to 1"{
  // a box in view space
  const o=ortho(-2,6,-1,3,1,11);
  // its near-bottom-left corner and its far-top-right one, carried to clip
  const lo=mulV(o,.{-2,-1,-1,1});
  const hi=mulV(o,.{6,3,-11,1});
  inline for(0..3)|i|try testing.expectApproxEqAbs(@as(f32,if(i==2)0 else-1),lo[i],1e-6);
  inline for(0..3)|i|try testing.expectApproxEqAbs(@as(f32,1),hi[i],1e-6);
}
test"degrees to radians, and a triangle's centroid"{
  try testing.expectApproxEqAbs(halfPi,rad(90),1e-6);
  // a triangle's centre
  const c=centroid(v3(0,0,0),v3(3,0,0),v3(0,3,6));
  try testing.expectApproxEqAbs(@as(f32,1),c[0],1e-6);
  try testing.expectApproxEqAbs(@as(f32,1),c[1],1e-6);
  try testing.expectApproxEqAbs(@as(f32,2),c[2],1e-6);
}
test"footprints and rings visit each tile once"{
  // a 2x2 footprint anchored off the origin
  var fp=footprint(-1,4,2);
  // the tiles it should visit, in order
  const want=[_]Vice(i32,2){.{-1,4},.{0,4},.{-1,5},.{0,5}};
  for(want)|w|try testing.expectEqual(w,fp.next().?);
  try testing.expect(fp.next()==null);
  for(0..5)|ri|{
    // the ring's distance
    const r:i32=@intCast(ri);
    // the walk round it
    var it=ring(r);
    // how many tiles it visited
    var n:i32=0;
    while(it.next())|o|:(n+=1)try testing.expectEqual(@abs(r),@max(@abs(o[0]),@abs(o[1])));
    try testing.expectEqual(if(r==0)1 else 8*r,n);
  }
  try testing.expectEqual(@as(u8,255),unorm8(2));
  try testing.expectEqual(@as(u8,0),unorm8(-1));
}
