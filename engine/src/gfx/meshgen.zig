//! procedural mesh construction, the generic half: a `Builder` holding a
//! mesh's vertices (with skin weights and growth records beside them, and
//! the level of detail it is built at) and the primitives every mesh is
//! composed of: watertight tubes along a spline (parallel-transported
//! frames, shared rings, capped ends), lofts of any cross-section, cones,
//! ellipsoids, grid patches, grown vines (Catmull-Rom, tapering) and woven
//! braids. A vertex's role is the game's own enum (`Mesher(Part, stem)`):
//! its shaders key motion and shading off it.
/// the standard library
const std=@import("std");
/// checks that hold in debug builds: spines and loops within their limits
const assert=std.debug.assert;
/// the allocator a builder's lists grow with
const Allocator=std.mem.Allocator;
/// the I/O whose pool a build's heavy pieces (sculpts) are spread over
const Io=std.Io;
/// the test helpers
const testing=std.testing;
/// all the maths: vectors, matrices, splines, easing
const m=@import("../core/math.zig");
/// the seeded random stream a vine's wobble is drawn from
const Rng=@import("../core/rng.zig").Rng;
/// colour types: the eight-bit rgba every vertex carries
const color=@import("../core/color.zig");
/// smooth noise, for a braid strand's wander
const noise=@import("../core/noise.zig");
/// the GPU layouts: mesh vertices, skin weights, growth records
const vertex=@import("vertex.zig");
/// a point or direction in three dimensions
const V3=m.V3;
/// most points a tube's spine may have (the maths' spline limit)
const maxSpine=m.maxSpline;
/// most sides round a tube's ring
const maxSides=16;
/// most points round a loft's cross-section, or along it
const maxLoft=24;
/// most rows or columns a patch may have
const maxPatch=128;
/// how many rings a rounded end closes over at full detail (each level of
/// detail halves them, never under two)
const domeRings=4;
/// an end this thin (a share of its tube's thickest ring) is a point: it is
/// rounded off over its last segment instead of capped beyond it
const pointShare:f32=0.2;
/// tu.z on a tube's sides: this, plus how far round its ring a point lies
/// (0..1), so a shader can run fibres along it (sheets use 1..3, see vertex.Mesh)
pub const tubeRound:f32=4;
/// how a tube or loft closes at its ends
pub const Tips=enum{
  /// rounded: a blunt end domes out like a fingertip, a point closes in a
  /// rounded bullet over its last segment
  round,
  /// as built: a blunt end capped flat, a point left sharp (thorns, claws)
  sharp,
};
/// levels of detail every mesh is built at: 0 full, then each level keeps
/// every other ring/row along a surface and half its sides around (see
/// `Builder.lod`), so far things draw with a fraction of the vertices.
pub const lods=3;
/// eye distance at which each level after the first takes over
pub const lodDistances=[lods-1]f32{36,70};
/// braids: the core's and each strand's share of the radius, how far out
/// the strands run (share of the radius), and the seed step between strands
/// (the core's share of the radius)
pub const braidCore:f32=0.72;
/// (each strand's share of the radius)
pub const braidStrand:f32=0.26;
/// (how far out the strands run, a share of the radius)
pub const braidOff:f32=0.8;
/// (the seed step from one strand to the next)
pub const strandSalt=7919;
/// a strand's wander: noise frequency along it, and how far its turn and
/// its distance out stray (per unit of wobble)
/// (how often the noise turns along the strand)
const strandFreq:f32=3;
/// (how far its turn round the core strays)
const strandTurnRate:f32=4;
/// (how far its distance out strays)
const strandSwellRate:f32=3;
/// how far a braid strand (seeded `sd`) strays round the core at `u` along it.
pub fn strandTurn(sd:u64,u:f32,wobble:f32)f32{return wobble*strandTurnRate*noise.grad(sd,u*strandFreq,0.5);}
/// how far out a braid strand runs at `u` along it, as a factor of its rest.
pub fn strandSwell(sd:u64,u:f32,wobble:f32)f32{return 1+wobble*strandSwellRate*noise.grad(sd,u*strandFreq,7.5);}
/// the level of detail for something `dist` from the eye.
pub fn lodAt(dist:f32)u32{
  // the level reached so far: one more for each distance passed
  var l:u32=0;
  for(lodDistances)|d|{
    if(dist>d)l+=1;
  }
  return l;
}
/// indices 0, s, 2s, .. and always the last, for keeping every s-th of `n`
/// points along a surface (s = 1 keeps them all). Returns how many.
pub fn stride(n:usize,s:usize,out:[]usize)usize{
  // how many indices are written, and the next point index
  var k:usize=0;
  var i:usize=0;
  while(i<n-1):(i+=s){
    out[k]=i;
    k+=1;
  }
  out[k]=n-1;
  return k+1;
}
/// a frame carried smoothly along a curve (parallel transport): for each
/// point a normal and binormal perpendicular to the local tangent, twisting
/// as little as possible, so rings built from it never shear or flip.
pub fn transport(spine:[]const V3,nrms:[]V3,bis:[]V3)void{
  // how many points the curve has
  const n=spine.len;
  // the first segment's direction, which the first normal is crossed off
  const t0=m.norm(spine[1]-spine[0]);
  // the normal being carried along, starting square to that direction
  var nrm=m.norm(m.cross(t0,if(@abs(t0[1])>0.9)m.v3(1,0,0)else m.v3(0,1,0)));
  for(0..n)|i|{
    // tangent: average of the neighbouring segments, so joints bisect the bend
    const tan=m.norm(spine[@min(i+1,n-1)]-spine[if(i==0)0 else i-1]);
    // carry the normal along: remove its component along the new tangent
    nrm=m.norm(nrm-tan*m.splat3(m.dot(nrm,tan)));
    nrms[i]=nrm;
    bis[i]=m.cross(tan,nrm);
  }
}
/// how a vine grows: mostly along one direction, never quite straight.
pub const Growth=struct{
  /// where the vine's root sits; it never moves
  start:V3,
  /// dominant growth direction (unit)
  direction:V3,
  /// how long the vine runs from root to tip
  length:f32,
  /// how much noise perturbs the path, relative to the control-point spacing
  wobble:f32=0.15,
  /// spiral around the growth axis: 0 none, 0.5 a tight tendril (two turns)
  curl:f32=0,
  /// tip radius relative to the base
  taper:f32=0.3,
  /// the seed its wobble is drawn from
  seed:u64=0,
};
/// perturb a control polyline the way a vine grows: wobble perpendicular to
/// `g.direction` and a curl around it, both easing off toward the tip. The
/// first point is the root and never moves. Deterministic in `g.seed`.
pub fn grow(pts:[]V3,g:Growth)void{
  // how many points there are
  const n=pts.len;
  // the direction it grows along
  const axis=g.direction;
  // two directions square to it and to each other, the wobble's plane
  const up=m.norm(m.cross(axis,if(@abs(axis[1])<m.nearParallel)m.v3(0,1,0)else m.v3(1,0,0)));
  const side=m.norm(m.cross(axis,up));
  // the random stream the wobble is drawn from
  var rng=Rng.init(g.seed);
  // how far apart the points sit along the axis
  const step=g.length/m.f(n-1);
  for(pts[1..],1..)|*p,i|{
    // how far toward the tip this point is (0..1)
    const t=m.ratio(i,n-1);
    // how far it may wobble, easing off toward the tip
    const w=g.wobble*step*(1-0.5*t);
    p.*+=side*m.splat3((rng.float()-0.5)*w)+up*m.splat3((rng.float()-0.5)*w);
    if(g.curl>0){
      // how far round the spiral this point has turned
      const a=t*g.curl*4*m.tau;
      // the spiral widens out of the root and closes toward the tip
      const r=g.curl*0.25*g.length*m.smooth(@min(1,t*4))*(1-t);
      p.*+=side*m.splat3(@cos(a)*r)+up*m.splat3(@sin(a)*r);
    }
  }
}
/// control points for a grown vine, one per element of `out`.
pub fn growthPath(g:Growth,out:[]V3)void{
  for(out,0..)|*p,i|p.*=g.start+g.direction*m.splat3(g.length*m.ratio(i,out.len-1));
  grow(out,g);
}
/// radii tapering smoothly from `r0` at the base to `r0 * tip` at the end.
/// how much thicker a branch swells where it leaves its parent stem, at its root
const collarSwell:f32=0.7;
/// how far along a branch (a share of its length) its collar eases away
const collarSpan:f32=0.14;
/// how thick a branch is `u` along it (0 root .. 1 tip) for its collar: it
/// flares into the stem it leaves like a real branch's collar, so it grows
/// out of it instead of being stuck into it (a factor on its radius)
pub fn collar(u:f32)f32{
  // how far into the collar's easing this is, 0 at the root
  const k=m.clamp01(u/collarSpan);
  return 1+collarSwell*(1-k)*(1-k);
}
pub fn taperRadii(r0:f32,tip:f32,out:[]f32)void{
  for(out,0..)|*r,i|r.*=r0*(1-m.ratio(i,out.len-1)*(1-tip));
}
/// the builder and the primitives that write a role: `Part` is the game's
/// enum(u32) of vertex roles, `stem` the role a plain woody surface takes
/// (braids, bands, an ellipsoid left unset); returns the mesher type
pub fn Mesher(comptime Role:type,comptime stem:Role)type{
  return struct{
    /// the game's enum of vertex roles
    pub const Part=Role;
    /// the role a plain woody surface takes when none is given
    pub const defaultPart=stem;
    /// (the same enum, short)
    const P=Role;
  /// a mesh being built: its vertices, the skin weights and growth records
  /// beside them, and the level of detail it is built at
  pub const Builder=struct{
    /// the allocator its lists grow with
    gpa:Allocator,
    /// the vertices built so far, three to a triangle
    v:std.ArrayList(vertex.Mesh)=.empty,
    /// skin weights beside `v`, as far as the last skinned vertex (see `skinOf`)
    skin:std.ArrayList(vertex.Skin)=.empty,
    /// growth records beside `v`, as far as the last vertex grown along a
    /// growth spline (see `growOf`, gfx/growth.zig)
    grow:std.ArrayList(vertex.Grow)=.empty,
    /// the level of detail being built (0 full): primitives keep every
    /// `step()`-th ring along their length and `around()` of their sides, the
    /// same way every time, so growth keys built at one level still match
    lod:u32=0,
    /// how tubes and lofts close at their ends (claws and thorns set `.sharp`
    /// round their own building, and set it back)
    tips:Tips=.round,
    /// where a sculpt meshed into it works out its field and vertices over
    /// the cores (null: here alone, the same mesh either way)
    io:?Io=null,
    /// how many points along a surface to step over at this level
    pub fn step(b:*const Builder)usize{return@as(usize,1)<<@intCast(b.lod);}
    /// how many sides a ring keeps at this level (never fewer than `min`)
    pub fn around(b:*const Builder,sides:u32,min:u32)u32{return@max(@min(sides,min),sides>>@intCast(b.lod));}
    /// free its lists
    pub fn deinit(b:*Builder)void{
      b.v.deinit(b.gpa);
      b.skin.deinit(b.gpa);
      b.grow.deinit(b.gpa);
    }
    /// the skin weights of every vertex since `start`, to be filled in
    /// (vertices before it without any are left unskinned)
    pub fn skinOf(b:*Builder,start:usize)Allocator.Error![]vertex.Skin{
      try b.skin.appendNTimes(b.gpa,.{},b.v.items.len-|b.skin.items.len);
      return b.skin.items[start..b.v.items.len];
    }
    /// the growth records of every vertex since `start`, to be filled in
    /// (vertices before it without any grow as their structure does)
    pub fn growOf(b:*Builder,start:usize)Allocator.Error![]vertex.Grow{
      try b.grow.appendNTimes(b.gpa,.{},b.v.items.len-|b.grow.items.len);
      return b.grow.items[start..b.v.items.len];
    }
    /// add one vertex: at `p` facing `n` (normalised here), coloured `col`,
    /// tu `t` up the thing and `u` across, with role `part`
    pub fn put(b:*Builder,p:V3,n:V3,col:color.Rgba8,t:f32,u:f32,part:Part)Allocator.Error!void{
      try b.v.append(b.gpa,.{.pos=p,.nrm=m.norm(n),.col=col,.tu=.{t,u,0},.part=@intFromEnum(part)});
    }
    /// apply a transform to every vertex added since `start` (build in a unit
    /// space, then place/scale into the final part space).
    pub fn xform(b:*Builder,start:usize,mat:m.M4)void{
      // (the inverse here, read as its transpose by `mulCovector`)
      const nm=m.inverse(mat); // normals use the inverse-transpose
      for(b.v.items[start..])|*v|{
        v.pos=m.mulPoint(mat,v.pos);
        v.nrm=m.norm(m.mulCovector(nm,v.nrm));
      }
      // where a vertex grows out of moves with it
      if(start<b.grow.items.len)for(b.grow.items[start..])|*g|{
        g.from=m.mulPoint(mat,g.from);
      };
      // a weight's gradient is a covector too: it goes as the normals do
      if(start>=b.skin.items.len)return;
      for(b.skin.items[start..])|*k|for(0..4)|i|{
        // the gradient, turned with the normals
        const g=m.mulCovector(nm,.{k.gx[i],k.gy[i],k.gz[i]});
        k.gx[i]=g[0];
        k.gy[i]=g[1];
        k.gz[i]=g[2];
      };
    }
    /// how many vertices it holds now: where the next piece begins, for
    /// `xform`, `skinOf`, `growOf` and the growth tags
    pub fn mark(b:*const Builder)usize{return b.v.items.len;}
    /// tube along a spine, `sides` facets, radius tapering from r0 to r1.
    pub fn tube(b:*Builder,spine:[]const V3,ts:[]const f32,r0:f32,r1:f32,col:color.Rgba8,part:Part,sides:u32)Allocator.Error!void{
      // a radius per spine point, lerped from `r0` to `r1`
      var radii:[maxSpine]f32=undefined;
      // the last point's index, as a float
      const last=m.f(spine.len-1);
      for(0..spine.len)|i|radii[i]=m.lerp(r0,r1,m.f(i)/last);
      try b.tubeR(spine,ts,radii[0..spine.len],col,part,sides);
    }
    /// watertight tube: one ring per spine point, oriented by a frame carried
    /// smoothly along the curve (parallel transport) so consecutive segments
    /// share their rings exactly, with both ends capped.
    pub fn tubeR(b:*Builder,spine:[]const V3,ts:[]const f32,radii:[]const f32,col:color.Rgba8,part:Part,sides:u32)Allocator.Error!void{
      // the one colour, once per ring
      var cols:[maxSpine]color.Rgba8=undefined;
      @memset(cols[0..spine.len],col);
      try b.tubeC(spine,ts,radii,cols[0..spine.len],null,part,sides);
    }
    /// `tubeR` with a colour per ring (a gradient along the tube, shared rings
    /// so it never steps), and optionally `us[i]` written to tu.y.
    pub fn tubeC(b:*Builder,spine:[]const V3,ts:[]const f32,radii:[]const f32,cols:[]const color.Rgba8,us:?[]const f32,part:Part,fullSides:u32)Allocator.Error!void{
      // (the most sides at full detail, before `around` thins them)
      assert(spine.len>=2 and spine.len<=maxSpine and fullSides<=maxSides and cols.len==spine.len);
      // the sides it keeps at this level, never under three
      const sides=b.around(fullSides,3);
      // each ring's points and outward directions
      var rings:[maxSpine][maxSides]V3=undefined;
      var norms:[maxSpine][maxSides]V3=undefined;
      // how many spine points
      const n=spine.len;
      // the carried frame's normal and binormal at each point
      var frameNormal:[maxSpine]V3=undefined;
      var fb:[maxSpine]V3=undefined;
      transport(spine,frameNormal[0..n],fb[0..n]);
      for(0..n)|i|{
        for(0..sides)|k|{
          // how far round the ring this side is (radians)
          const a=m.ratio(k,sides)*m.tau;
          // which way out from the spine that is
          const dir=frameNormal[i]*m.splat3(@cos(a))+fb[i]*m.splat3(@sin(a));
          norms[i][k]=dir;
          rings[i][k]=spine[i]+dir*m.splat3(radii[i]);
        }
      }
      // rings kept at this level of detail (the frames came from all of them)
      var keep:[maxSpine]usize=undefined;
      // how many rings are kept
      const kn=stride(n,b.step(),&keep);
      // whether each end is rounded off as a point over its last kept
      // segment (it needs a segment of its own to round)
      const round=b.tips==.round;
      const pointFirst=round and kn>=3 and pointed(radii,0);
      const pointLast=round and kn>=3 and pointed(radii,n-1);
      for(0..kn-1)|j|{
        if((j==0 and pointFirst)or(j==kn-2 and pointLast))continue;
        for(0..sides)|k|{
          // the next side round, wrapping
          const k1=(k+1)%sides;
          // the quad's side indices and ring indices, corner by corner
          const q=m.Vice(usize,4){k,k1,k1,k};
          const r=m.Vice(usize,4){keep[j],keep[j],keep[j+1],keep[j+1]};
          // how far round each corner lies (the closing side runs on to a
          // whole turn, so nothing reads back across the seam)
          const roundAt=m.Vice(f32,4){m.ratio(k,sides),m.ratio(k+1,sides),m.ratio(k+1,sides),m.ratio(k,sides)};
          for([_]usize{0,1,2,0,2,3})|c|{
            try b.put(rings[r[c]][q[c]],norms[r[c]][q[c]],cols[r[c]],ts[r[c]],uOf(us,r[c]),part);
            b.v.items[b.v.items.len-1].tu[2]=tubeRound+roundAt[c];
          }
        }
      }
      if(round){
        for([_]bool{true,false})|first|{
          // the end ring and the ring the end closes from: a point rounds
          // off from the kept ring before it, a blunt end domes beyond itself
          const e=if(first)0 else n-1;
          const isPoint=if(first)pointFirst else pointLast;
          const from=if(!isPoint)e else if(first)keep[1]else keep[kn-2];
          // the way out of the tube there
          const out=if(isPoint)m.norm(spine[e]-spine[from])else if(first)m.norm(spine[0]-spine[1])else m.norm(spine[n-1]-spine[n-2]);
          // how far the end reaches: to the point, or a blunt end's own radius
          const reach=if(isPoint)m.dist(spine[e],spine[from])else radii[e];
          if(radii[from]<1e-4 or reach<1e-5)continue;
          try b.dome(.{
            .centre=spine[from],.out=out,.ring=rings[from][0..sides],.norms=norms[from][0..sides],
            .across=radii[from],.reach=reach,.col=cols[from],.t0=ts[from],.t1=ts[e],.u=uOf(us,e),
            .part=part,.start=first,
          });
        }
        return;
      }
      // caps (skipped where the tube tapers to a point anyway)
      for([_]usize{0,n-1})|i|{
        if(radii[i]<1e-4)continue;
        // which way the cap faces: out of the tube's end
        const out=if(i==0)m.norm(spine[0]-spine[1])else m.norm(spine[n-1]-spine[n-2]);
        for(0..sides)|k|{
          // the next side round, wrapping
          const k1=(k+1)%sides;
          try b.put(spine[i],out,cols[i],ts[i],uOf(us,i),part);
          try b.put(rings[i][k],out,cols[i],ts[i],uOf(us,i),part);
          try b.put(rings[i][k1],out,cols[i],ts[i],uOf(us,i),part);
        }
      }
    }
    /// one rounded end to close: a quarter ellipsoid from a ring out to a point
    const Dome=struct{
      /// the ring's centre on the spine
      centre:V3,
      /// which way the end runs, out of the tube
      out:V3,
      /// the ring's points
      ring:[]const V3,
      /// their outward normals
      norms:[]const V3,
      /// how wide the ring is (its radius, or a loft's smaller half width)
      across:f32,
      /// how far out beyond the ring the end reaches
      reach:f32,
      /// its colour
      col:color.Rgba8,
      /// tu.x at the ring and at the point
      t0:f32,
      /// (tu.x at the point)
      t1:f32,
      /// tu.y throughout
      u:f32,
      /// its role
      part:Part,
      /// whether it closes the tube's start (wound the other way round)
      start:bool,
    };
    /// closes a ring into a rounded end: rings shrinking along a quarter
    /// ellipse (`across` wide, `reach` out), their normals turning smoothly
    /// from the tube's to straight out, to a point on the spine
    fn dome(b:*Builder,d:Dome)Allocator.Error!void{
      // how many rings it closes over at this level
      const rings=@max(2,@as(usize,domeRings)>>@intCast(b.lod));
      // the sides round each ring
      const sides=d.ring.len;
      for(0..rings)|j|{
        // the angle up the ellipse at this band's inner and outer rings
        const a0=m.ratio(j,rings)*m.tau/4;
        const a1=m.ratio(j+1,rings)*m.tau/4;
        // how far along the end each ring is (tu.x)
        const t0=m.lerp(d.t0,d.t1,@sin(a0));
        const t1=m.lerp(d.t0,d.t1,@sin(a1));
        // the last band closes to the point: one triangle a side
        const last=j+1==rings;
        for(0..sides)|k|{
          // the next side round, wrapping
          const k1=(k+1)%sides;
          // the band's quad: its inner pair, then its outer pair
          const q=[4]V3{domePoint(d,k,a0),domePoint(d,k1,a0),domePoint(d,k1,a1),domePoint(d,k,a1)};
          const n=[4]V3{domeNormal(d,k,a0),domeNormal(d,k1,a0),domeNormal(d,k1,a1),domeNormal(d,k,a1)};
          const ts=m.Vice(f32,4){t0,t0,t1,t1};
          // (the start's end faces the other way: wound the other way round)
          const order:[6]usize=if(d.start).{0,2,1,0,3,2}else.{0,1,2,0,2,3};
          for(order,0..)|c,o|{
            if(last and o>=3)break;
            try b.put(q[c],n[c],d.col,ts[c],d.u,d.part);
          }
        }
      }
    }
    /// where side `k` of a dome's ring lies at angle `a` up its ellipse
    fn domePoint(d:Dome,k:usize,a:f32)V3{
      return d.centre+(d.ring[k]-d.centre)*m.splat3(@cos(a))+d.out*m.splat3(d.reach*@sin(a));
    }
    /// which way side `k` of a dome faces at angle `a` up its ellipse
    fn domeNormal(d:Dome,k:usize,a:f32)V3{
      return m.norm(d.norms[k]*m.splat3(@cos(a)/d.across)+d.out*m.splat3(@sin(a)/d.reach));
    }
    /// whether end ring `i` of `radii` is a point (rounded over its last segment)
    fn pointed(radii:[]const f32,i:usize)bool{
      // the thickest ring
      var top:f32=0;
      for(radii)|r|top=@max(top,r);
      return radii[i]<=pointShare*top;
    }
    /// the tu.y of ring `i`: from `us` if given, else zero
    fn uOf(us:?[]const f32,i:usize)f32{return if(us)|s|s[i]else 0;}
    /// a closed cone from `base` along `dir`, `len` long and `r` wide at its
    /// base, its point at the tip
    pub fn cone(b:*Builder,base:V3,dir:V3,len:f32,r:f32,col:color.Rgba8,t:f32,part:Part)Allocator.Error!void{
      // two directions square to `dir`, the base ring's plane
      const side=m.norm(m.cross(dir,if(@abs(dir[1])>0.9)m.v3(1,0,0)else m.v3(0,1,0)));
      // the third direction of the base ring's plane
      const up=m.cross(side,dir);
      // the cone's point
      const tip=base+dir*m.splat3(len);
      // how many sides round it has (always four: a cone is small)
      const sides=4;
      for(0..sides)|i|{
        // where this side begins and ends round the base (radians)
        const a0=m.f(i)/sides*m.tau;
        const a1=m.f(i+1)/sides*m.tau;
        // which way out the side's two base corners face
        const n0=side*m.splat3(@cos(a0))+up*m.splat3(@sin(a0));
        const n1=side*m.splat3(@cos(a1))+up*m.splat3(@sin(a1));
        try b.put(base+n0*m.splat3(r),n0,col,t,0,part);
        try b.put(base+n1*m.splat3(r),n1,col,t,0,part);
        try b.put(tip,dir,col,t,1,part);
        // base cap so a cone never shows a hole when seen from below
        try b.put(base,-dir,col,t,0,part);
        try b.put(base+n1*m.splat3(r),-dir,col,t,0,part);
        try b.put(base+n0*m.splat3(r),-dir,col,t,0,part);
      }
    }
  };
  /// a grown vine: `ctrlN` control points from `g`, smoothed by Catmull-Rom
  /// into `res` evenly spaced rings, tapering by `g.taper`, `t` from t0 to t1.
  pub fn vine(b:*Builder,g:Growth,ctrlN:usize,res:usize,r0:f32,col:color.Rgba8,part:Part,sides:u32,t0:f32,t1:f32)Allocator.Error!void{
    // the control points, laid out by `growthPath`
    var ctrl:[maxSpine]V3=undefined;
    growthPath(g,ctrl[0..ctrlN]);
    // the spline through them, resampled evenly into `res` points
    var path:[maxSpine]V3=undefined;
    m.splineResample(ctrl[0..ctrlN],path[0..res]);
    // the radius at each point, tapering by `g.taper`
    var radii:[maxSpine]f32=undefined;
    taperRadii(r0,g.taper,radii[0..res]);
    // the tu.x at each point, from `t0` to `t1`
    var ts:[maxSpine]f32=undefined;
    for(ts[0..res],0..)|*t,i|t.*=m.lerp(t0,t1,m.ratio(i,res-1));
    try b.tubeR(path[0..res],ts[0..res],radii[0..res],col,part,sides);
  }
  /// a woven vine: a darker core along `spine` wrapped by `strands` helical
  /// vines, `radii[i]` the bundle's radius at each point. `wobble` roughs the
  /// strands' winding with smooth noise (0 = a perfect lathe-like helix).
  pub fn braid(b:*Builder,spine:[]const V3,ts:[]const f32,radii:[]const f32,strands:u32,twist:f32,wobble:f32,seed:u64,core:color.Rgba8,strand:color.Rgba8)Allocator.Error!void{
    // how far round the core the strands have wound at each point
    var turn:[maxSpine]f32=undefined;
    for(turn[0..spine.len],0..)|*a,i|a.*=m.ratio(i,spine.len-1)*twist;
    try braidTurned(b,spine,ts,radii,turn[0..spine.len],strands,wobble,seed,core,strand);
  }
  /// a braid whose strands have wound `turn[i]` radians around the core by
  /// point i: winding fast spreads them into a loose diagonal weave, winding
  /// slowly gathers them tight and nearly vertical.
  pub fn braidTurned(b:*Builder,spine:[]const V3,ts:[]const f32,radii:[]const f32,turn:[]const f32,strands:u32,wobble:f32,seed:u64,core:color.Rgba8,strand:color.Rgba8)Allocator.Error!void{
    try braidAround(b,spine,ts,radii,turn,strands,wobble,seed,core,strand,stem);
  }
  /// `braidTurned` round a core of role `corePart` (an arsthraxia's nerve
  /// showing between its strands)
  pub fn braidAround(b:*Builder,spine:[]const V3,ts:[]const f32,radii:[]const f32,turn:[]const f32,strands:u32,wobble:f32,seed:u64,core:color.Rgba8,strand:color.Rgba8,corePart:Part)Allocator.Error!void{
    // how many spine points
    const n=spine.len;
    // the carried frame's normal and binormal at each point
    var frameNormal:[maxSpine]V3=undefined;
    var fb:[maxSpine]V3=undefined;
    transport(spine,frameNormal[0..n],fb[0..n]);
    // the radius at each point: the core's first, then each strand's
    var r:[maxSpine]f32=undefined;
    for(0..n)|i|r[i]=radii[i]*braidCore;
    try b.tubeR(spine,ts,r[0..n],core,corePart,8);
    for(0..n)|i|r[i]=radii[i]*braidStrand;
    for(0..strands)|si|{
      // where this strand starts round the core (radians)
      const a0=m.ratio(si,strands)*m.tau;
      // this strand's own seed for its wander
      const sd=seed+%si*strandSalt;
      // the strand's path, wound round the spine
      var path:[maxSpine]V3=undefined;
      for(0..n)|i|{
        // how far along the spine this point is (0..1)
        const u=m.ratio(i,n-1);
        // strands stay embedded in the core: the offset never leaves 0.8 +- 10%
        const a=a0+turn[i]+strandTurn(sd,u,wobble);
        // how far out from the spine the strand runs here
        const off=radii[i]*braidOff*strandSwell(sd,u,wobble);
        path[i]=spine[i]+(frameNormal[i]*m.splat3(@cos(a))+fb[i]*m.splat3(@sin(a)))*m.splat3(off);
      }
      try b.tubeR(path[0..n],ts,r[0..n],strand,stem,5);
    }
  }
  /// a tube along `spine` whose cross-section is `shape` (a closed curve over
  /// 0..tau, roughly unit size, counter-clockwise when seen from the spine's
  /// start) scaled by `widths`/`heights`, upright toward `up`. Rings are
  /// shared and both ends capped, so it is watertight like `tubeR`.
  pub fn loft(b:*Builder,spine:[]const V3,ts:[]const f32,widths:[]const f32,heights:[]const f32,up:V3,comptime shape:fn(f32)m.Vice(f32,2),col:color.Rgba8,part:Part,fullSides:u32)Allocator.Error!void{
    assert(spine.len>=2 and spine.len<=maxSpine and fullSides<=maxLoft);
    // the sides it keeps at this level, never under six
    const sides=b.around(fullSides,6);
    // how many spine points
    const n=spine.len;
    // each ring's points and outward normals
    var rings:[maxSpine][maxLoft]V3=undefined;
    var norms:[maxSpine][maxLoft]V3=undefined;
    for(0..n)|i|{
      // the spine's direction here, the average of its neighbours
      const tan=m.norm(spine[@min(i+1,n-1)]-spine[if(i==0)0 else i-1]);
      // the section's sideways and upright directions
      const side=m.norm(m.cross(up,tan));
      // (the section's upright, square to the spine and the side)
      const u=m.cross(tan,side);
      for(0..sides)|k|{
        // how far round the section this side is (radians)
        const a=m.ratio(k,sides)*m.tau;
        // the section curve's point there, at unit size
        const p=shape(a);
        // outward normal of the (scaled) section curve
        // the small step either side the curve's slope is measured over
        const e:f32=0.01;
        // the curve's points either side, and the scaled slope between them
        const p0=shape(a-e);
        const p1=shape(a+e);
        const dx=(p1[0]-p0[0])*widths[i];
        const dy=(p1[1]-p0[1])*heights[i];
        norms[i][k]=m.norm(side*m.splat3(dy)-u*m.splat3(dx));
        rings[i][k]=spine[i]+side*m.splat3(p[0]*widths[i])+u*m.splat3(p[1]*heights[i]);
      }
    }
    // the rings kept at this level of detail
    var keep:[maxSpine]usize=undefined;
    // how many rings are kept
    const kn=stride(n,b.step(),&keep);
    for(0..kn-1)|j|for(0..sides)|k|{
      // the next side round, wrapping
      const k1=(k+1)%sides;
      // the quad's side indices and ring indices, corner by corner
      const q=m.Vice(usize,4){k,k1,k1,k};
      const r=m.Vice(usize,4){keep[j],keep[j],keep[j+1],keep[j+1]};
      for([_]usize{0,1,2,0,2,3})|c|try b.put(rings[r[c]][q[c]],norms[r[c]][q[c]],col,ts[r[c]],0,part);
    };
    if(b.tips==.round){
      // each end domes out beyond itself, as far as its section is thin
      for([_]bool{true,false})|first|{
        // the end ring
        const e=if(first)0 else n-1;
        // the way out of the loft there
        const out=if(first)m.norm(spine[0]-spine[1])else m.norm(spine[n-1]-spine[n-2]);
        // the section's smaller half size: how far the end reaches
        const across=@min(widths[e],heights[e]);
        if(across<1e-5)continue;
        try b.dome(.{
          .centre=spine[e],.out=out,.ring=rings[e][0..sides],.norms=norms[e][0..sides],
          .across=across,.reach=across,.col=col,.t0=ts[e],.t1=ts[e],.u=0,.part=part,.start=first,
        });
      }
      return;
    }
    for([_]usize{0,n-1})|i|{
      // which way the cap faces: out of the loft's end
      const out=if(i==0)m.norm(spine[0]-spine[1])else m.norm(spine[n-1]-spine[n-2]);
      for(0..sides)|k|{
        // the next side round, wrapping
        const k1=(k+1)%sides;
        try b.put(spine[i],out,col,ts[i],0,part);
        try b.put(rings[i][k],out,col,ts[i],0,part);
        try b.put(rings[i][k1],out,col,ts[i],0,part);
      }
    }
  }
  /// a surface from a grid of `rows` x `cols` points (row-major), quads shared
  /// between neighbours. Normals, colours and `us` (written to tu.y) are per point.
  pub fn patch(b:*Builder,rows:usize,cols:usize,pts:[]const V3,nrms:[]const V3,colsRgba:[]const color.Rgba8,us:[]const f32,t:f32,part:Part)Allocator.Error!void{
    assert(pts.len==rows*cols and nrms.len==pts.len and colsRgba.len==pts.len and us.len==pts.len);
    // rows and columns kept at this level of detail
    var kr:[maxPatch]usize=undefined;
    var kc:[maxPatch]usize=undefined;
    // how many rows and columns are kept
    const nr=stride(rows,b.step(),&kr);
    const nc=stride(cols,b.step(),&kc);
    for(0..nr-1)|ri|for(0..nc-1)|ci|{
      // the quad's two kept rows and two kept columns
      const r0=kr[ri];
      const r1=kr[ri+1];
      const c0=kc[ci];
      const c1=kc[ci+1];
      // the quad's four point indices, round its corners
      const q=m.Vice(usize,4){r0*cols+c0,r0*cols+c1,r1*cols+c1,r1*cols+c0};
      for([_]usize{0,1,2,0,2,3})|v|try b.put(pts[q[v]],nrms[q[v]],colsRgba[q[v]],t,us[q[v]],part);
    };
  }
  /// grown vine bands wrapping over an ellipsoid (centre `at`, `radii`) along
  /// its curvature: each band runs from (polar th0, azimuth ph0) to (th1, ph1).
  /// `side` mirrors it in x, so left and right forms are built, not mirrored.
  pub fn bands(b:*Builder,at:V3,radii:V3,arcs:[]const m.Vice(f32,4),side:f32,r:f32,wobble:f32,seed:u64,col:color.Rgba8)Allocator.Error!void{
    for(arcs,0..)|arc,i|{
      // the band's six control points, laid over the surface
      var ctrl:[6]V3=undefined;
      for(&ctrl,0..)|*c,j|{
        // how far along the band this point is (0..1)
        const k=m.ratio(j,ctrl.len-1);
        // its polar and azimuth angles, lerped across the band
        const th=m.lerp(arc[0],arc[2],k);
        const ph=m.lerp(arc[1],arc[3],k);
        c.*=at+m.v3(@sin(th)*@cos(ph)*side,@cos(th),@sin(th)*@sin(ph))*radii*m.splat3(1.03);
      }
      grow(&ctrl,.{
        .start=ctrl[0],.direction=m.norm(ctrl[ctrl.len-1]-ctrl[0]),.length=m.dist(ctrl[ctrl.len-1],ctrl[0]),
        .wobble=wobble,.curl=0,.seed=seed+%i*17,
      });
      // the band's path, smoothed and resampled
      var path:[16]V3=undefined;
      m.splineResample(&ctrl,&path);
      // the tu.x and radius at each point of it
      var ts:[16]f32=undefined;
      var rs:[16]f32=undefined;
      for(&ts,&rs,0..)|*t,*rr,j|{
        t.*=m.ratio(j,15);
        // a grown vine: it tapers to a point at both ends, never cut off
        rr.*=@max(r*@sqrt(@sin(m.pi*t.*)),r*0.05);
      }
      try b.tubeR(&path,&ts,&rs,col,stem,5);
    }
  }
  /// a closed ellipsoid of quads, `rings` from pole to pole and `segs` round
  pub const Ellipsoid=struct{
    /// its centre
    center:V3,
    /// its half-widths along x, y and z
    radii:V3,
    /// its colour
    col:color.Rgba8,
    /// the part role it is drawn with
    part:Part=stem,
    /// how many rings of quads from pole to pole (thinned at coarser detail)
    rings:u32=8,
    /// how many quads round each ring (thinned at coarser detail)
    segs:u32=10,
    /// value written to tu.x (e.g. height along a body part)
    t:f32=0,
  };
  /// an ellipsoid as `e` describes, its normals true to its stretched surface
  pub fn ellipsoid(b:*Builder,e:Ellipsoid)Allocator.Error!void{
    // how many rings and segments are kept at this level
    const ringCount=b.around(e.rings,3);
    const segCount=b.around(e.segs,4);
    for(0..ringCount)|ri|for(0..segCount)|si|{
      // the quad's four corners and their normals
      var q:[4]V3=undefined;
      var n:[4]V3=undefined;
      // which ring and segment step each corner takes
      const corners=[4]m.Vice(u32,2){.{0,0},.{1,0},.{1,1},.{0,1}};
      for(corners,0..)|cn,k|{
        // the corner's polar and azimuth angles
        const th=m.ratio(ri+cn[0],ringCount)*m.pi;
        const ph=m.ratio(si+cn[1],segCount)*m.tau;
        // the corner's point on the unit sphere
        const u=m.v3(@sin(th)*@cos(ph),@cos(th),@sin(th)*@sin(ph));
        q[k]=e.center+u*e.radii;
        n[k]=u/e.radii;
      }
      for([_]usize{0,1,2,0,2,3})|k|try b.put(q[k],n[k],e.col,e.t,0,e.part);
    };
  }
  /// a woven bundle of vines along +Y from 0 to 1 (see `braid`).
  /// `profile(k)` gives the bundle radius at height k.
  pub fn bundle(b:*Builder,comptime profile:fn(f32)f32,strands:u32,twist:f32,wobble:f32,seed:u64,core:color.Rgba8,strand:color.Rgba8)Allocator.Error!void{
    // how many points along the bundle's spine, less one
    const strandSides=18;
    // the spine straight up, tu.x and the radius at each point
    var spine:[strandSides+1]V3=undefined;
    var ts:[strandSides+1]f32=undefined;
    var radii:[strandSides+1]f32=undefined;
    for(0..strandSides+1)|i|{
      // how far up the bundle this point is (0..1)
      const k=m.f(i)/strandSides;
      spine[i]=m.v3(0,k,0);
      ts[i]=k;
      radii[i]=profile(k);
    }
    try braid(b,&spine,&ts,&radii,strands,twist,wobble,seed,core,strand);
  }
  };
}
test"grown vines keep their root and regrow identically"{
  // a curling, wobbling vine one unit long
  const g:Growth=.{.start=m.v3(1,0,2),.direction=m.v3(0,1,0),.length=1,.wobble=0.2,.curl=0.4,.seed=9};
  // its control points, grown twice from the same growth
  var a:[8]V3=undefined;
  var b:[8]V3=undefined;
  growthPath(g,&a);
  growthPath(g,&b);
  try testing.expectEqual(g.start,a[0]);
  for(a,b)|x,y|try testing.expectEqual(x,y);
  // it still grows along its direction, roughly its length
  try testing.expect(@abs(a[7][1]-1)<0.1);
}
test"a tube keeps fewer rings and sides at a coarser level of detail, its caps closed"{
  // the test's two roles
  const Role=enum(u32){stem,leaf};
  // a mesher over them
  const M=Mesher(Role,.stem);
  // a gently bending five-point spine
  const spine=[_]V3{m.v3(0,0,0),m.v3(0,0.3,0),m.v3(0.1,0.6,0),m.v3(0.1,0.9,0.1),m.v3(0,1.2,0.1)};
  // tu.x along it
  const ts=[_]f32{0,0.25,0.5,0.75,1};
  // the vertex count at full detail and at the next level
  var counts:m.Vice(usize,2)=undefined;
  for(&counts,0..)|*c,l|{
    // a builder at this level of detail
    var b:M.Builder=.{.gpa=testing.allocator,.lod=@intCast(l)};
    defer b.deinit();
    try b.tube(&spine,&ts,0.1,0.05,color.rgb(0.4,0.3,0.2).toRgba8(255),.stem,8);
    // two triangles a side between kept rings; each blunt end a rounded
    // dome: two a side for each band but the last, one a side there
    // the sides kept at this level
    const sides:usize=b.around(8,3);
    // the rings kept at this level, and how many there are
    var keep:[8]usize=undefined;
    const rings=stride(spine.len,b.step(),&keep);
    // the bands each dome closes over at this level
    const bands=@max(2,@as(usize,domeRings)>>@intCast(b.lod));
    try testing.expectEqual((rings-1)*sides*6+2*((bands-1)*sides*6+sides*3),b.v.items.len);
    c.*=b.v.items.len;
  }
  try testing.expect(counts[1]<counts[0]);
}
