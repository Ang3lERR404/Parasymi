//! the one place for numeric helpers: scalars, angles, tile/world
//! coordinates, SIMD vectors and column-major 4x4 matrices (Vulkan clip
//! space: y down, depth 0..1). World: x east, y up, z south; 1 tile = 1 unit.
//! Game code uses this instead of reaching into std.math directly.
const std=@import("std");
const math=std.math;
const testing=std.testing;
const assert=std.debug.assert;
const Allocator=std.mem.Allocator;
const runtimeSafety=std.debug.runtime_safety;
pub const V3=@Vector(3,f32);
pub const V4=@Vector(4,f32);
pub const M4=[4]V4;
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
pub const pi=math.pi;
pub const tau=math.tau;
pub const sqrt2=math.sqrt2;
/// a quarter turn (pi / 2).
pub const halfPi=pi/2.0;
pub const clamp=math.clamp;
pub const pow=math.pow;
pub const maxInt=math.maxInt;
pub const inf=math.inf;
/// int→f32. Takes anytype on purpose: callers pass i32, u8, u16, u32, usize.
/// This is the one sanctioned anytype in the file.
pub inline fn f(x:anytype)f32{return@floatFromInt(x);}
pub inline fn lerp(a:f32,b:f32,t:f32)f32{return a+(b-a)*t;}
pub inline fn clamp01(x:f32)f32{return math.clamp(x,0,1);}
pub inline fn smooth(t:f32)f32{return t*t*(3-2*t);}
/// whole units of a non-negative float (e.g. ripe seeds) as integer type T.
pub inline fn floorTo(comptime T:type,x:f32)T{return@intFromFloat(@floor(x));}
/// fraction of `a` over `b` as f32 (e.g. progress counters).
pub inline fn ratio(a:anytype,b:anytype)f32{return f(a)/f(b);}
// ---- angles ----
pub inline fn atan2(y:f32,x:f32)f32{return math.atan2(y,x);}
pub inline fn asin(x:f32)f32{return math.asin(clamp(x,-1,1));}
pub inline fn acos(x:f32)f32{return math.acos(clamp(x,-1,1));}
pub inline fn sign(x:f32)f32{return math.sign(x);}
/// |x|^p carrying x's sign (superellipse outlines).
pub fn signedPow(x:f32,p:f32)f32{
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
pub inline fn tileAt(p:V3)[2]i32{return.{tileOf(p[0]),tileOf(p[2])};}
/// world-space centre of a size x size footprint anchored at tile (x, z).
pub inline fn footprintCentre(x:i32,z:i32,size:u8,y:f32)V3{
  const half=f(size)/2;
  return.{f(x)+half,y,f(z)+half};
}
/// world-space centre of tile (x, z) at height y.
pub inline fn tileCentre(x:i32,z:i32,y:f32)V3{return footprintCentre(x,z,1,y);}
/// the tiles of a size x size footprint anchored at (x, z), row by row:
/// `var it = m.footprint(x, z, 2); while (it.next()) |t| ...` (t = .{x, z}).
pub const Footprint=struct{
  x:i32,z:i32,size:u8,k:u16=0,
  pub fn next(fp:*Footprint)?[2]i32{
    const n=@as(u16,fp.size)*fp.size;
    if(fp.k>=n)return null;
    defer fp.k+=1;
    return.{fp.x+@as(i32,fp.k%fp.size),fp.z+@as(i32,fp.k/fp.size)};
  }
};
pub inline fn footprint(x:i32,z:i32,size:u8)Footprint{return.{.x=x,.z=z,.size=size};}
/// offsets on the square ring at Chebyshev distance `r` (r = 0 is the centre
/// alone), row by row; walking r = 0, 1, 2… visits tiles nearest-first.
pub const Ring=struct{
  r:i32,dx:i32,dz:i32,
  pub fn next(it:*Ring)?[2]i32{
    while(it.dz<=it.r){
      const o:[2]i32=.{it.dx,it.dz};
      // inner rows touch the ring only at their ends
      const edge=@abs(it.dz)==it.r;
      it.dx=if(it.dx>=it.r)-it.r else if(edge)it.dx+1 else it.r;
      if(it.dx==-it.r)it.dz+=1;
      return o;
    }
    return null;
  }
};
pub inline fn ring(r:i32)Ring{return.{.r=r,.dx=-r,.dz=-r};}
/// the four facings in order, for `for (m.dirs) |d|`.
pub const dirs=[4]Dir{0,1,2,3};
/// one of four facings: +x (east), +z (south), -x (west), -z (north).
pub const Dir=u2;
pub const DirVec=struct{x:i32,z:i32};
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
pub inline fn v3(x:f32,y:f32,z:f32)V3{return.{x,y,z};}
pub inline fn splat3(s:f32)V3{return@splat(s);}
pub inline fn splat4(s:f32)V4{return@splat(s);}
pub inline fn dot(a:V3,b:V3)f32{return@reduce(.Add,a*b);}
pub inline fn len(a:V3)f32{return@sqrt(dot(a,a));}
pub inline fn norm(a:V3)V3{
  const l=len(a);
  return if(l>eps)a/splat3(l)else a;
}
pub inline fn cross(a:V3,b:V3)V3{
  return.{a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]};
}
pub inline fn lerpV(a:V3,b:V3,t:f32)V3{return a+(b-a)*splat3(t);}
/// the centre of a triangle.
pub inline fn centroid(a:V3,b:V3,c:V3)V3{return(a+b+c)*splat3(1.0/3.0);}
/// a point at fraction `k` (0..1) along a polyline, by point index (for
/// evenly resampled paths; see `Path` for arc length on uneven ones).
pub fn alongPath(path:[]const V3,k:f32)V3{
  const pos=k*f(path.len-1);
  const i:usize=@min(@as(usize,@intFromFloat(pos)),path.len-2);
  return lerpV(path[i],path[i+1],pos-f(i));
}
// ---- splines ----
/// the Catmull-Rom curve between `p1` (t=0) and `p2` (t=1); `p0` and `p3`
/// shape the tangents at either end.
pub fn catmullRom(p0:V3,p1:V3,p2:V3,p3:V3,t:f32)V3{
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
  const n=pts.len;
  var dense:[(maxSpline-1)*splineDense+1]V3=undefined;
  var at:[(maxSpline-1)*splineDense+1]f32=undefined;
  var k:usize=0;
  for(0..n-1)|seg|{
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
  const total=at[k];
  var i:usize=0;
  for(out,0..)|*o,j|{
    const want=total*ratio(j,out.len-1);
    while(i+1<k and at[i+1]<want)i+=1;
    const span=at[i+1]-at[i];
    o.*=lerpV(dense[i],dense[i+1],if(span>eps)clamp01((want-at[i])/span)else 0);
  }
}
// ---- paths (precomputed arc-length polylines) ----
/// A polyline with precomputed cumulative arc lengths for O(log n) lookup.
/// Build once when the path is set; call `.at(k)` every frame.
pub const Path=struct{
  pts:[]const V3,
  cum:[]const f32,
  total:f32,
  /// build a Path from a slice of points. Allocates `cum` via `alloc`.
  pub fn build(pts:[]const V3,alloc:Allocator)Allocator.Error!Path{
    assert(pts.len>=2);
    const cum=try alloc.alloc(f32,pts.len);
    cum[0]=0;
    for(1..pts.len)|i|cum[i]=cum[i-1]+len(pts[i]-pts[i-1]);
    return.{.pts=pts,.cum=cum,.total=cum[pts.len-1]};
  }
  pub fn deinit(self:Path,alloc:Allocator)void{alloc.free(self.cum);}
  /// point at fraction k (0..1) along the path, evenly spaced by arc length.
  pub fn at(self:Path,k:f32)V3{
    const want=clamp01(k)*self.total;
    var lo:usize=0;
    var hi:usize=self.pts.len-1;
    while(lo+1<hi){
      const mid=(lo+hi)/2;
      if(self.cum[mid]<=want)lo=mid else hi=mid;
    }
    const span=self.cum[hi]-self.cum[lo];
    const t=if(span>eps)(want-self.cum[lo])/span else 0;
    return lerpV(self.pts[lo],self.pts[hi],t);
  }
};
// ---- matrices ----
pub const identity:M4=.{
  .{1,0,0,0},.{0,1,0,0},.{0,0,1,0},.{0,0,0,1},
};
pub fn mul(a:M4,b:M4)M4{
  var r:M4=undefined;
  inline for(0..4)|c|{
    r[c]=a[0]*splat4(b[c][0])+a[1]*splat4(b[c][1]) +
      a[2]*splat4(b[c][2])+a[3]*splat4(b[c][3]);
  }
  return r;
}
pub fn mulV(m:M4,v:V4)V4{
  return m[0]*splat4(v[0])+m[1]*splat4(v[1]) +
    m[2]*splat4(v[2])+m[3]*splat4(v[3]);
}
/// a point through `m` (w = 1).
pub fn mulPoint(m:M4,p:V3)V3{
  const r=mulV(m,.{p[0],p[1],p[2],1});
  return.{r[0],r[1],r[2]};
}
/// a direction through `m` (w = 0: no translation; not renormalised).
pub fn mulDir(m:M4,d:V3)V3{
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
pub fn lookAt(eye:V3,at:V3,up:V3)M4{
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
pub fn translate(t:V3)M4{
  return.{.{1,0,0,0},.{0,1,0,0},.{0,0,1,0},.{t[0],t[1],t[2],1}};
}
pub fn scale3(s:V3)M4{
  return.{.{s[0],0,0,0},.{0,s[1],0,0},.{0,0,s[2],0},.{0,0,0,1}};
}
pub fn rotX(a:f32)M4{
  const c=@cos(a);const s=@sin(a);
  return.{.{1,0,0,0},.{0,c,s,0},.{0,-s,c,0},.{0,0,0,1}};
}
pub fn rotY(a:f32)M4{
  const c=@cos(a);const s=@sin(a);
  return.{.{c,0,-s,0},.{0,1,0,0},.{s,0,c,0},.{0,0,0,1}};
}
pub fn rotZ(a:f32)M4{
  const c=@cos(a);const s=@sin(a);
  return.{.{c,s,0,0},.{-s,c,0,0},.{0,0,1,0},.{0,0,0,1}};
}
/// chain transforms parent-first: chain(&.{a, b, c}) == a * b * c.
pub fn chain(ms:[]const M4)M4{
  var r:M4=identity;
  for(ms)|x|r=mul(r,x);
  return r;
}
pub fn origin(a:M4)V3{return.{a[3][0],a[3][1],a[3][2]};}
/// a rotation taking +Y onto `dir` (a unit vector); the roll around it is arbitrary.
pub fn alignY(dir:V3)M4{
  const ref=if(@abs(dir[2])<nearParallel)v3(0,0,1)else v3(1,0,0);
  const x=norm(cross(dir,ref));
  const z=cross(x,dir);
  return.{.{x[0],x[1],x[2],0},.{dir[0],dir[1],dir[2],0},.{z[0],z[1],z[2],0},.{0,0,0,1}};
}
// ---- springs ----
/// critically damped spring step (for procedural secondary motion).
/// Uses the exact closed-form solution, so it is stable for any `dt`.
pub fn spring(pos:*f32,vel:*f32,target:f32,freq:f32,dt:f32)void{
  const x=pos.*-target;
  const j=vel.*+freq*x;
  const e=@exp(-freq*dt);
  pos.*=target+(x+j*dt)*e;
  vel.*=(vel.*-freq*j*dt)*e;
}
/// a damped spring-mass pulling `pos` toward `rest` under an extra `force`:
/// `m a = -k (pos - rest) - c v + force`. Substepped so stiff springs stay
/// stable over long frames.
pub fn springDamper(pos:*V3,vel:*V3,rest:V3,k:f32,c:f32,mass:f32,force:V3,dt:f32)void{
  const n=@max(@as(u32,@intFromFloat(@ceil(dt*springSubstepHz))),1);
  const h=dt/f(n);
  for(0..n)|_|{
    const acc=(force-(pos.*-rest)*splat3(k)-vel.* * splat3(c))/splat3(mass);
    vel.*+=acc*splat3(h);
    pos.*+=vel.* * splat3(h);
  }
}
// ---- inverses ----
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
  const c0=column(m,0);
  const c1=column(m,1);
  const c2=column(m,2);
  const x12=cross(c1,c2);
  const det=dot(c0,x12);
  if(runtimeSafety and det==0)@panic("singular matrix in m.inverseAffine");
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
  var a:[16]f32=undefined;
  inline for(0..4)|c|inline for(0..4)|r|{a[c*4+r]=m[c][r];};
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
  const det=a[0]*inv[0]+a[1]*inv[4]+a[2]*inv[8]+a[3]*inv[12];
  if(runtimeSafety and det==0)@panic("singular matrix in m.inverse");
  const id=1/det;
  var r:M4=undefined;
  inline for(0..4)|c|inline for(0..4)|rr|{r[c][rr]=inv[c*4+rr]*id;};
  return r;
}
// ---- tests ----
/// the six planes of what a view-projection matrix sees (each xyz its
/// inward normal, w its offset), for culling what lies outside it.
pub const Frustum=struct{
  planes:[6]V4,
  /// planes from a (Vulkan, depth 0..1) view-projection matrix
  pub fn of(vp:M4)Frustum{
    var row:[4]V4=undefined;
    inline for(0..4)|i|row[i]=.{vp[0][i],vp[1][i],vp[2][i],vp[3][i]};
    var fr:Frustum=.{.planes=.{
      row[3]+row[0],row[3]-row[0],
      row[3]+row[1],row[3]-row[1],
      row[2],row[3]-row[2],
    }};
    for(&fr.planes)|*pl|{
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
      const da=pl[0]*a[0]+pl[1]*a[1]+pl[2]*a[2]+pl[3];
      const db=pl[0]*b[0]+pl[1]*b[1]+pl[2]*b[2]+pl[3];
      if(@max(da,db)<-r)return false;
    }
    return true;
  }
};
test"spring-damper settles where its force balances"{
  var p=v3(0,0,0);
  var v=v3(1,0,0);
  const k=60.0;
  const forceZ=3.0;
  for(0..120)|_|springDamper(&p,&v,v3(0,1,0),k,6,0.8,v3(0,0,forceZ),1.0/30.0);
  // equilibrium: displacement = force / k = 3/60 = 0.05
  try testing.expect(len(p-v3(0,1,forceZ/k))<1e-3);
  try testing.expect(len(v)<1e-3);
}
test"spring is stable for huge steps"{
  var p:f32=0;
  var v:f32=50;
  for(0..20)|_|spring(&p,&v,1,7,0.75);
  try testing.expectApproxEqAbs(@as(f32,1),p,1e-3);
  try testing.expect(@abs(v)<1e-2);
}
test"points move with a transform, directions only turn"{
  const t=chain(&.{translate(v3(1,2,3)),rotY(pi/2.0)});
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
  const t=chain(&.{translate(v3(1,2,3)),rotY(0.7),scale3(v3(3,0.5,1)),rotZ(0.4)});
  const along=v3(1,1,0);
  const n=v3(1,-1,0);
  const moved=mulDir(t,along);
  const turned=mulCovector(inverseAffine(t),n);
  try testing.expectApproxEqAbs(@as(f32,0),dot(moved,turned),1e-5);
  try testing.expect(len(turned)>0.1);
}
test"inverse roundtrip"{
  const p=mul(perspective(0.8,1.5,0.1,100),lookAt(v3(3,10,8),v3(0,0,0),v3(0,1,0)));
  const i=mul(inverse(p),p);
  inline for(0..4)|c|inline for(0..4)|r|{
    try testing.expectApproxEqAbs(identity[c][r],i[c][r],1e-3);
  };
}
test"affine and rigid inverses"{
  const aff=chain(&.{translate(v3(3,-2,5)),rotY(0.7),rotX(-0.4),scale3(v3(2,0.5,1.5))});
  const rig=chain(&.{translate(v3(-1,4,2)),rotY(1.9),rotZ(0.3)});
  for([_]M4{mul(inverseAffine(aff),aff),mul(aff,inverseAffine(aff)),mul(inverseRigid(rig),rig)})|i|{
    inline for(0..4)|c|inline for(0..4)|r|{
      try testing.expectApproxEqAbs(identity[c][r],i[c][r],1e-4);
    };
  }
  const ia=inverseAffine(aff);
  const ig=inverse(aff);
  inline for(0..4)|c|inline for(0..4)|r|{
    try testing.expectApproxEqAbs(ig[c][r],ia[c][r],1e-4);
  };
}
test"catmull-rom passes through its inner points"{
  const a=v3(0,0,0);
  const b=v3(1,2,0);
  const c=v3(3,2,1);
  const d=v3(4,0,1);
  try testing.expectEqual(b,catmullRom(a,b,c,d,0));
  const e=catmullRom(a,b,c,d,1);
  try testing.expect(len(e-c)<1e-5);
  const mid=catmullRom(v3(0,0,0),v3(1,0,0),v3(2,0,0),v3(3,0,0),0.5);
  try testing.expect(len(mid-v3(1.5,0,0))<1e-5);
}
test"spline resampling keeps the ends and evens the spacing"{
  const pts=[_]V3{v3(0,0,0),v3(0,1,0),v3(0.2,3,0),v3(1,3.5,0.5)};
  var out:[16]V3=undefined;
  splineResample(&pts,&out);
  try testing.expect(len(out[0]-pts[0])<1e-5);
  try testing.expect(len(out[15]-pts[3])<1e-4);
  const step=len(out[1]-out[0]);
  for(1..out.len)|i|try testing.expectApproxEqAbs(step,len(out[i]-out[i-1]),step*0.1);
}
test"alignY maps +Y onto the direction, orthonormally"{
  for([_]V3{v3(0,1,0),v3(0,0,1),norm(v3(1,-2,0.5))})|d|{
    const r=alignY(d);
    const y=mulV(r,.{0,1,0,0});
    try testing.expect(len(v3(y[0],y[1],y[2])-d)<1e-5);
    const x=v3(r[0][0],r[0][1],r[0][2]);
    const z=v3(r[2][0],r[2][1],r[2][2]);
    try testing.expectApproxEqAbs(@as(f32,1),dot(cross(x,d),z),1e-5);
  }
}
test"Path.at gives evenly spaced points"{
  const pts=[_]V3{v3(0,0,0),v3(1,0,0),v3(2,0,0),v3(3,0,0)};
  const p=try Path.build(&pts,testing.allocator);
  defer p.deinit(testing.allocator);
  try testing.expectApproxEqAbs(@as(f32,0.0),p.at(0.0)[0],1e-5);
  try testing.expectApproxEqAbs(@as(f32,1.5),p.at(0.5)[0],1e-5);
  try testing.expectApproxEqAbs(@as(f32,3.0),p.at(1.0)[0],1e-5);
}
test"a frustum keeps what is inside it and culls what is not"{
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
  const o=ortho(-2,6,-1,3,1,11);
  const lo=mulV(o,.{-2,-1,-1,1});
  const hi=mulV(o,.{6,3,-11,1});
  inline for(0..3)|i|try testing.expectApproxEqAbs(@as(f32,if(i==2)0 else-1),lo[i],1e-6);
  inline for(0..3)|i|try testing.expectApproxEqAbs(@as(f32,1),hi[i],1e-6);
}
test"degrees to radians, and a triangle's centroid"{
  try testing.expectApproxEqAbs(halfPi,rad(90),1e-6);
  const c=centroid(v3(0,0,0),v3(3,0,0),v3(0,3,6));
  try testing.expectApproxEqAbs(@as(f32,1),c[0],1e-6);
  try testing.expectApproxEqAbs(@as(f32,1),c[1],1e-6);
  try testing.expectApproxEqAbs(@as(f32,2),c[2],1e-6);
}
test"footprints and rings visit each tile once"{
  var fp=footprint(-1,4,2);
  const want=[_][2]i32{.{-1,4},.{0,4},.{-1,5},.{0,5}};
  for(want)|w|try testing.expectEqual(w,fp.next().?);
  try testing.expect(fp.next()==null);
  for(0..5)|ri|{
    const r:i32=@intCast(ri);
    var it=ring(r);
    var n:i32=0;
    while(it.next())|o|:(n+=1)try testing.expectEqual(@abs(r),@max(@abs(o[0]),@abs(o[1])));
    try testing.expectEqual(if(r==0)1 else 8*r,n);
  }
  try testing.expectEqual(@as(u8,255),unorm8(2));
  try testing.expectEqual(@as(u8,0),unorm8(-1));
}
