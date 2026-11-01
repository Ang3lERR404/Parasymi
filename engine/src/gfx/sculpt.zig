//! sculpting one seamless surface out of many forms: each form (an
//! ellipsoid, a rounded cone, a rounded box, a tube through points) is a signed distance field,
//! the forms melt into one another by smooth union (or are carved away by
//! smooth subtraction), and the whole is meshed once at startup with
//! surface nets: one vertex per surface cell, pulled onto the surface,
//! its normal the field's gradient. Every form belongs to a bone, so each
//! vertex is also weighted to the bones of the forms it lies nearest
//! (smoothly, only along joints that are actually joined), and the mesh
//! bends as one skin (vertex.Skin; a game's shader carries each vertex with its bones).
//!
//! The field is sampled sparsely: only blocks of cells the surface can
//! pass through are evaluated, and each block only with the forms that
//! can reach it.
/// the standard library
const std=@import("std");
/// the allocator the form lists and the mesh grow with
const Allocator=std.mem.Allocator;
/// all the maths: vectors, matrices, inverses
const m=@import("../core/math.zig");
/// colour types: each form's eight-bit rgba
const color=@import("../core/color.zig");
/// the GPU layouts: mesh vertices and their skin weights
const vertex=@import("vertex.zig");
/// the thread fan-out a build's blocks are spread over
const jobs=@import("../core/jobs.zig");
/// the I/O context jobs run on
const Io=std.Io;
/// a point or direction in three dimensions
const V3=m.V3;
/// makes a `V3` from three numbers
const v3=m.v3;
/// a 4×4 matrix: where a form is placed
const M4=m.M4;
/// what a form is shaped like, in its own space
pub const Shape=union(enum){
  /// centre and radii
  ellipsoid:struct{c:V3,r:V3},
  /// a cone from `a` (radius `ra`) to `b` (radius `rb`), rounded at both ends
  cone:struct{a:V3,b:V3,ra:f32,rb:f32},
  /// centre, half extents (rounding included) and the rounding radius
  box:struct{c:V3,half:V3,round:f32},
  /// a tube through points: rounded cones from each point to the next, the
  /// radius at each its own, joined without seams (a horn, a tail)
  chain:Chain,
};
/// the most segments a chain may have
pub const chainMax=32;
/// a tube through `n`+1 points (`n` segments), each with its radius
pub const Chain=struct{
  /// the points along it, the first `n`+1 used
  pts:[chainMax+1]V3=@splat(.{0,0,0}),
  /// the radius at each point
  r:[chainMax+1]f32=@splat(0),
  /// how many segments it has (1..chainMax)
  n:u8=1,
  /// the signed distance from `p` to the tube: the nearest of its segments
  fn dist(c:*const Chain,p:V3)f32{
    // the nearest so far
    var d:f32=m.inf(f32);
    for(0..c.n)|i|d=@min(d,roundCone(p,c.pts[i],c.pts[i+1],c.r[i],c.r[i+1]));
    return d;
  }
  /// the sphere (centre, radius) it lies in
  fn bound(c:*const Chain)struct{c:V3,r:f32}{
    // the points' middle
    var mid=v3(0,0,0);
    for(0..c.n+1)|i|mid+=c.pts[i];
    mid/=m.splat3(m.f(c.n+1));
    // the farthest any point's ball reaches from it
    var far:f32=0;
    for(0..c.n+1)|i|far=@max(far,m.len(c.pts[i]-mid)+c.r[i]);
    return.{.c=mid,.r=far};
  }
};
/// one form of the sculpt: its shape, where it sits and how it is
/// stretched, which bone carries it, its colour, and how it melts in
pub const Form=struct{
  /// its shape, in its own space
  shape:Shape,
  /// where its shape space sits (in the space the surface is built in)
  at:M4=m.identity,
  /// shape space stretched by this before it is placed (a wide muzzle from
  /// a round cone); the distance is scaled back, near enough at the surface
  stretch:V3=.{1,1,1},
  /// the bone it moves with (an index into the sculpt's `parents`)
  bone:u8,
  /// its colour, blended with its neighbours' where they meet
  col:color.Rgba8,
  /// how far it melts into what is there before it (metres)
  k:f32=0.03,
  /// cut away instead of added
  carve:bool=false,
  /// only colours the surface where it lies (fading over this many metres
  /// outside it), adding nothing: a lip line, the dark round an eye
  ink:f32=0,
  /// how softly the skin passes across the joints of its bone (metres;
  /// 0 the sculpt's own): small for a finger, so it bends at its knuckles
  soft:f32=0,
  /// the role (the mesher's `Part`, by its tag) the surface is drawn with
  /// where this form lies nearest, so the game's shaders shade it so; null
  /// the role the whole mesh is given
  part:?u32=null,
};
/// a form ready to evaluate: back from the build space to its shape space,
/// and the sphere it lies in (plus its melt)
const Placed=struct{
  /// the form as it was added
  f:Form,
  /// back from the build space to its shape space
  inv:M4,
  /// the centre of the sphere it lies in, in the build space
  centre:V3,
  /// that sphere's radius, its melt and ink fade included
  reach:f32,
  /// its least stretch, to scale its distance back to metres
  shrink:f32,
};
/// smooth minimum: `a` and `b` melted together over `k` (0: plain min);
/// how forms join into one surface
fn smin(a:f32,b:f32,k:f32)f32{
  if(k<=0)return@min(a,b);
  // how much the two are within `k` of each other, 0..1
  const h=@max(k-@abs(a-b),0)/k;
  return@min(a,b)-h*h*k*0.25;
}
/// smooth maximum: what carves `b` out of `a` softly over `k`
fn smax(a:f32,b:f32,k:f32)f32{return-smin(-a,-b,k);}
/// the signed distance (near enough) from `p` to an ellipsoid of radii
/// `r` round the origin
fn ellipsoid(p:V3,r:V3)f32{
  // the point's length in the ellipsoid's unit space, and in its squared space
  const k0=m.len(p/r);
  const k1=m.len(p/(r*r));
  if(k1<1e-9)return-@reduce(.Min,r);
  return k0*(k0-1)/k1;
}
/// the exact signed distance from `p` to a cone from `a` (radius `r1`)
/// to `b` (radius `r2`), rounded at both ends
fn roundCone(p:V3,a:V3,b:V3,r1:f32,r2:f32)f32{
  // the axis, its squared length, and the radii's difference
  const ba=b-a;
  const l2=m.dot(ba,ba);
  const rr=r1-r2;
  // the slant's squared length, and the axis length's inverse squared
  const a2=l2-rr*rr;
  const il2=1/l2;
  // the point from `a`, and how far along the axis it lies (scaled)
  const pa=p-a;
  const y=m.dot(pa,ba);
  // how far past `b` it lies (scaled)
  const z=y-l2;
  // the point's offset square to the axis, scaled, and its square
  const q=pa*m.splat3(l2)-ba*m.splat3(y);
  const x2=m.dot(q,q);
  // those lengths squared, scaled by the axis length
  const y2=y*y*l2;
  const z2=z*z*l2;
  // the slant's test value: which of the three regions the point is in
  const k=m.sign(rr)*rr*rr*x2;
  if(m.sign(z)*a2*z2>k)return@sqrt(x2+z2)*il2-r2;
  if(m.sign(y)*a2*y2<k)return@sqrt(x2+y2)*il2-r1;
  return(@sqrt(x2*a2*il2)+y*rr)*il2-r1;
}
/// the signed distance from `p` to a box of half extents `half` round the
/// origin, its edges rounded by `r`
fn roundBox(p:V3,half:V3,r:f32)f32{
  // how far outside each face the point lies, rounding taken off
  const q=@abs(p)-half+m.splat3(r);
  // the parts of that which lie outside
  const out=@max(q,m.splat3(0));
  return m.len(out)+@min(@reduce(.Max,q),0)-r;
}
/// the signed distance from `p` to shape `s`, in the shape's own space
fn shapeDist(s:*const Shape,p:V3)f32{
  return switch(s.*){
    .ellipsoid=>|e|ellipsoid(p-e.c,e.r),
    .cone=>|c|roundCone(p,c.a,c.b,c.ra,c.rb),
    .box=>|x|roundBox(p-x.c,x.half,x.round),
    .chain=>|*c|c.dist(p),
  };
}
/// the sphere (centre, radius) a shape lies in, in its own space
fn shapeBound(s:Shape)struct{c:V3,r:f32}{
  return switch(s){
    .ellipsoid=>|e|.{.c=e.c,.r=@reduce(.Max,e.r)},
    .cone=>|c|.{.c=(c.a+c.b)*m.splat3(0.5),.r=m.len(c.b-c.a)*0.5+@max(c.ra,c.rb)},
    .box=>|x|.{.c=x.c,.r=m.len(x.half)},
    .chain=>|c|{
      // the chain's own sphere
      const b=c.bound();
      return.{.c=b.c,.r=b.r};
    },
  };
}
/// a colour's rgb as a vector of 0..255 values, for blending
fn colV(c:color.Rgba8)V3{return v3(m.f(c.r),m.f(c.g),m.f(c.b));}
/// a point on the surface and its outward normal there
pub const Hit=struct{
  /// the point on the surface
  p:V3,
  /// the outward normal there (unit)
  n:V3
};
/// a build hands the cores blocks of the field this many at least
const jobBlocks=4;
/// a seamless surface sculpted out of forms melted into one: its forms,
/// how bones join, and how softly weights and colours blend
pub const Sculpt=struct{
  /// the allocator its lists and meshes are made with
  gpa:Allocator,
  /// the forms, placed and ready to evaluate
  forms:std.ArrayList(Placed)=.empty,
  /// every form's index, for the few points asked about outside a build
  every:std.ArrayList(u32)=.empty,
  /// each bone's parent (weights only spread along joints)
  parents:[]const?u8,
  /// how softly a vertex's weight passes from one bone to the next across
  /// a joint (metres)
  soft:f32=0.02,
  /// how softly colours meet where forms meet (metres)
  blend:f32=0.012,
  /// the bones whose forms it keeps (a bit each); the rest are left out,
  /// for a surface cast onto only part of a body
  only:u64=~@as(u64,0),
  /// where a build's field and vertices are worked out over the cores
  /// (`jobs.each`; null: here alone, the same mesh either way)
  io:?Io=null,
  /// free its lists
  pub fn deinit(s:*Sculpt)void{
    s.forms.deinit(s.gpa);
    s.every.deinit(s.gpa);
  }
  /// place form `f` and keep it, unless its bone is left out by `only`
  pub fn add(s:*Sculpt,f:Form)Allocator.Error!void{
    if(s.only&(@as(u64,1)<<@intCast(f.bone))==0)return;
    // the sphere the shape lies in, in its own space
    const bound=shapeBound(f.shape);
    // the most the stretch widens it
    const grow=@reduce(.Max,f.stretch);
    try s.every.append(s.gpa,@intCast(s.forms.items.len));
    // the most `at` widens it: its longest axis
    var scale:f32=0;
    for(0..3)|c|scale=@max(scale,m.len(v3(f.at[c][0],f.at[c][1],f.at[c][2])));
    try s.forms.append(s.gpa,.{
      .f=f,
      .inv=m.inverseAffine(f.at),
      .centre=m.mulPoint(f.at,bound.c*f.stretch),
      .reach=bound.r*grow*scale+f.k+f.ink*4,
      .shrink=@reduce(.Min,f.stretch),
    });
  }
  /// the signed distance from `p` to one placed form, back in metres
  fn formDist(pf:*const Placed,p:V3)f32{
    // the point in the form's own, unstretched space
    const q=m.mulPoint(pf.inv,p)/pf.f.stretch;
    return shapeDist(&pf.f.shape,q)*pf.shrink;
  }
  /// the field at `p` from the forms listed (indices into `forms`)
  fn dist(s:*const Sculpt,p:V3,list:[]const u32)f32{
    // the field so far: far away until a form is met
    var d:f32=1e9;
    for(list)|i|{
      // the form being melted in or carved away
      const pf=&s.forms.items[i];
      if(pf.f.ink>0)continue;
      // its distance at `p`
      const di=formDist(pf,p);
      d=if(pf.f.carve)smax(d,-di,pf.f.k)else smin(d,di,pf.f.k);
    }
    return d;
  }
  /// the field's direction of steepest rise at `p` (unit; straight up where
  /// it is flat), by central differences `e` either side
  fn grad(s:*const Sculpt,p:V3,list:[]const u32,e:f32)V3{
    // the field's change along x, y and z
    const dx=s.dist(p+v3(e,0,0),list)-s.dist(p-v3(e,0,0),list);
    const dy=s.dist(p+v3(0,e,0),list)-s.dist(p-v3(0,e,0),list);
    const dz=s.dist(p+v3(0,0,e),list)-s.dist(p-v3(0,0,e),list);
    // the gradient, and its length
    const g=v3(dx,dy,dz);
    const l=m.len(g);
    return if(l<1e-12)v3(0,1,0)else g/m.splat3(l);
  }
  /// the surface point nearest `p` (a few steps down the field) and the
  /// outward normal there
  pub fn project(s:*const Sculpt,p0:V3)Allocator.Error!Hit{
    // every form
    const list=s.every.items;
    // the point being walked down onto the surface
    var p=p0;
    for(0..6)|_|{
      // the field there: how far it still is from the surface
      const d=s.dist(p,list);
      p-=s.grad(p,list,0.001)*m.splat3(d);
    }
    return.{.p=p,.n=s.grad(p,list,0.001)};
  }
  /// where a ray from `from` (inside the body) along `dir` comes out of it,
  /// and the outward normal there; null if it never does within `max`, or
  /// if `from` is not inside at all (it would come out where it started)
  pub fn cast(s:*const Sculpt,from:V3,dir:V3,max:f32)Allocator.Error!?Hit{
    // every form
    const list=s.every.items;
    if(s.dist(from,list)>=0)return null;
    // how far along the ray it has marched, and the last point still inside
    var t:f32=0;
    var last:f32=0;
    while(t<max){
      // the field at this step
      const d=s.dist(from+dir*m.splat3(t),list);
      if(d>=0){
        // between the last step inside and this one: halve down to it
        // the stretch the crossing lies in: last inside, first outside
        var lo=last;
        var hi=t;
        for(0..12)|_|{
          // the middle of that stretch
          const mid=(lo+hi)*0.5;
          if(s.dist(from+dir*m.splat3(mid),list)<0)lo=mid else hi=mid;
        }
        // where it crosses
        const p=from+dir*m.splat3(hi);
        return.{.p=p,.n=s.grad(p,list,0.001)};
      }
      last=t;
      t+=@max(-d,0.002);
    }
    return null;
  }
  /// where a ray from `from` (inside the body) along `dir` last comes out
  /// of it within `max` (past every part it crosses into again, as a
  /// sheet laid over the body must), and the outward normal there; null if
  /// `from` is not inside or the ray is still inside at `max`
  pub fn castOut(s:*const Sculpt,from:V3,dir:V3,max:f32)Allocator.Error!?Hit{
    // every form
    const list=s.every.items;
    if(s.dist(from,list)>=0)return null;
    // marched back in from the far end, the first point inside
    // how far along the ray it has marched back, and the last point outside
    var t=max;
    var last=max;
    if(s.dist(from+dir*m.splat3(t),list)<0)return null;
    while(t>0){
      // the field at this step
      const d=s.dist(from+dir*m.splat3(t),list);
      if(d<0){
        // the stretch the crossing lies in: first inside, last outside
        var lo=t;
        var hi=last;
        for(0..12)|_|{
          // the middle of that stretch
          const mid=(lo+hi)*0.5;
          if(s.dist(from+dir*m.splat3(mid),list)<0)lo=mid else hi=mid;
        }
        // where it crosses
        const p=from+dir*m.splat3(lo);
        return.{.p=p,.n=s.grad(p,list,0.001)};
      }
      last=t;
      t-=@max(d,0.002);
    }
    return null;
  }
  /// the skin weights at `p`: the bones of the nearest forms, softly,
  /// but only the nearest one's parent and children besides it
  pub fn weigh(s:*const Sculpt,p:V3)Allocator.Error!vertex.Skin{
    return s.weighFrom(p,s.every.items);
  }
  /// the skin weights at `p` from the forms listed: each joined bone weighed
  /// by how much farther its nearest form is than the nearest of all
  fn weighFrom(s:*const Sculpt,p:V3,list:[]const u32)vertex.Skin{
    // the most bones a sculpt may have
    const maxb=64;
    // each bone's nearest form distance at `p`
    var near:[maxb]f32=@splat(1e9);
    // each bone's softness across its joints
    var soft:[maxb]f32=@splat(s.soft);
    for(list)|i|{
      // the form weighed
      const pf=&s.forms.items[i];
      if(pf.f.carve or pf.f.ink>0)continue;
      near[pf.f.bone]=@min(near[pf.f.bone],formDist(pf,p));
      if(pf.f.soft>0)soft[pf.f.bone]=@min(soft[pf.f.bone],pf.f.soft);
    }
    // the bone of the nearest form of all
    var first:usize=0;
    for(near,0..)|d,b|if(d<near[first]){
      first=b;
    };
    // each bone's weight, before packing
    var w:[maxb]f32=@splat(0);
    for(0..s.parents.len)|b|{
      // whether bone `b` is the nearest one, its parent or its child
      const joined=b==first or s.parents[first]==@as(u8,@intCast(b)) or s.parents[b]==@as(u8,@intCast(first));
      if(!joined or near[b]>1e8)continue;
      w[b]=@exp(-(near[b]-near[first])/@min(soft[b],soft[first]));
    }
    return pack(&w);
  }
  /// a skin from weights per bone: the four heaviest, summing to one
  pub fn pack(w:[]const f32)vertex.Skin{
    // the four heaviest bones and their weights, heaviest first
    var idx:m.Vice(u8,4)=.{0,0,0,0};
    var wt:m.Vice(f32,4)=.{0,0,0,0};
    for(w,0..)|x,b|{
      if(x<=wt[3])continue;
      // where `x` goes in the sorted four
      var k:usize=3;
      while(k>0 and x>wt[k-1]):(k-=1){
        wt[k]=wt[k-1];
        idx[k]=idx[k-1];
      }
      wt[k]=x;
      idx[k]=@intCast(b);
    }
    // drop the slightest, so a bone barely there does not drag the skin
    // what the four kept weights add up to
    var sum:f32=0;
    for(&wt)|*x|{
      if(x.*<0.03*wt[0])x.*=0;
      sum+=x.*;
    }
    // the packed skin
    var out:vertex.Skin=.{};
    // what is left of 255 for the weights still to come
    var left:i32=255;
    for(0..4)|k|{
      // this weight in 255ths (the last takes all that is left)
      const q:i32=if(k==3)left else@intFromFloat(@round(wt[k]/sum*255));
      // that weight, never more than is left
      const c=m.clamp(@min(q,left),0,255);
      out.weights[k]=@intCast(c);
      left-=c;
      out.bones|=@as(u32,idx[k])<<@intCast(8*k);
    }
    return out;
  }
  /// `pack`, with how each bone's weight changes across the mesh (`slope`,
  /// per bone like `w`), so the skin's normals bend as it truly does
  pub fn packWith(w:[]const f32,slope:[]const V3)vertex.Skin{
    // the four heaviest bones, packed
    var out=pack(w);
    for(0..4)|k|{
      if(out.weights[k]==0)continue;
      // the slope of the bone in this slot
      const g=slope[(out.bones>>@intCast(8*k))&255];
      out.gx[k]=g[0];
      out.gy[k]=g[1];
      out.gz[k]=g[2];
    }
    return out;
  }
  /// the field's colour at `p` (the forms' colours meeting softly where
  /// they meet) and the role of the solid form nearest it (null: none set)
  fn colourFrom(s:*const Sculpt,p:V3,list:[]const u32)struct{c:V3,part:?u32}{
    // the nearest solid form's distance, and its role
    var best:f32=1e9;
    var part:?u32=null;
    for(list)|i|{
      // the form looked at
      const pf=&s.forms.items[i];
      if(pf.f.carve or pf.f.ink>0)continue;
      // its distance at `p`
      const d=formDist(pf,p);
      if(d<best){
        best=d;
        part=pf.f.part;
      }
    }
    // the colours summed by weight, and the weights' sum
    var c=v3(0,0,0);
    var sum:f32=0;
    for(list)|i|{
      // the form blended in
      const pf=&s.forms.items[i];
      if(pf.f.carve)continue;
      // its distance at `p`
      const d=formDist(pf,p);
      // its weight: an ink by how far inside its fade, a solid by how near it is next to the nearest
      const w=if(pf.f.ink>0)8*@exp(-@max(d,0)/pf.f.ink)else@exp(-(d-best)/s.blend);
      c+=colV(pf.f.col)*m.splat3(w);
      sum+=w;
    }
    return.{.c=c/m.splat3(@max(sum,1e-9)),.part=part};
  }
  /// mesh the surface with cells `h` across into `b`, a builder of the
  /// mesher `M` (gfx/meshgen.zig `Mesher`), every vertex the role of the
  /// form it lies nearest (`part` where that form sets none) with tu
  /// (`t`, 0), weighted to its bones.
  pub fn mesh(s:*const Sculpt,comptime M:type,b:*M.Builder,h:f32,t:f32,part:M.Part)Allocator.Error!void{
    // the sculpt's allocator, for the build's scratch
    const gpa=s.gpa;
    // the box every solid form lies in, low and high corners
    var lo=m.splat3(1e9);
    var hi=m.splat3(-1e9);
    for(s.forms.items)|pf|{
      if(pf.f.carve or pf.f.ink>0)continue;
      lo=@min(lo,pf.centre-m.splat3(pf.reach));
      hi=@max(hi,pf.centre+m.splat3(pf.reach));
    }
    lo-=m.splat3(2*h);
    hi+=m.splat3(2*h);
    // cells along each side of a block, and corners along each side
    const cells=8;
    const corners=cells+1;
    // how many blocks the box holds along x, y and z
    var nb:m.Vice(usize,3)=undefined;
    inline for(0..3)|c|nb[c]=@as(usize,@intFromFloat(@ceil((hi[c]-lo[c])/(h*cells))))+1;
    // the mark of a block or cell with nothing in it
    const noneId=m.maxInt(u32);
    // each block's index in `blocks`, or `noneId` where the surface never passes
    const map=try gpa.alloc(u32,nb[0]*nb[1]*nb[2]);
    defer gpa.free(map);
    @memset(map,noneId);
    // a block of cells the surface can pass through: its sampled field
    // and the vertex of each of its cells
    const Block=struct{
      /// which block it is, along x, y and z
      at:m.Vice(usize,3),
      /// the field at each of its corners
      vals:[corners*corners*corners]f32,
      /// each cell's vertex index, or `noneId` where the surface misses it
      vid:[cells*cells*cells]u32,
      /// the forms that can reach it, the only ones evaluated in it
      cand:[]u32,
    };
    // the blocks the surface can pass through
    var blocks:std.ArrayList(Block)=.empty;
    defer{
      for(blocks.items)|*bl|gpa.free(bl.cand);
      blocks.deinit(gpa);
    }
    // the forms that can reach the block being looked at
    var cand:std.ArrayList(u32)=.empty;
    defer cand.deinit(gpa);
    // which blocks the surface can pass through, sampled. A form is left
    // out of a block only past the widest melt of any form: a far form
    // still melts into a nearer one by the nearer one's `k`, so leaving it
    // out by its own `k` alone makes neighbouring blocks disagree (cracks)
    // half a block's diagonal: how far its centre is from its corners
    const half=h*cells*0.5*@sqrt(3.0);
    // the widest melt of any form
    var kmax:f32=0;
    for(s.forms.items)|pf|kmax=@max(kmax,pf.f.k);
    for(0..nb[2])|bz|for(0..nb[1])|by|for(0..nb[0])|bx|{
      // the block's centre
      const c=lo+v3(m.f(bx*cells)+cells*0.5,m.f(by*cells)+cells*0.5,m.f(bz*cells)+cells*0.5)*m.splat3(h);
      cand.clearRetainingCapacity();
      for(s.forms.items,0..)|pf,i|{
        if(m.len(c-pf.centre)-pf.reach<half+2*h+kmax){
          try cand.append(gpa,@intCast(i));
        }
      }
      // with nothing to add, carving and inking alone make no surface
      // whether any form there adds to the surface
      var solid=false;
      for(cand.items)|i|solid=solid or (!s.forms.items[i].f.carve and s.forms.items[i].f.ink==0);
      if(!solid)continue;
      // the field at the block's centre
      const d=s.dist(c,cand.items);
      if(@abs(d)>half*1.6+2*h)continue;
      map[(bz*nb[1]+by)*nb[0]+bx]=@intCast(blocks.items.len);
      try blocks.append(gpa,.{.at=.{bx,by,bz},.vals=undefined,.vid=@splat(noneId),.cand=try gpa.dupe(u32,cand.items)});
    };
    // a vertex as it is placed: where, which way it faces, its colour, skin and role
    const Vert=struct{p:V3,n:V3,col:color.Rgba8,skin:vertex.Skin,part:M.Part};
    // the eight corners of a cell, as steps along x, y and z
    const corner=[8]m.Vice(usize,3){.{0,0,0},.{1,0,0},.{0,1,0},.{1,1,0},.{0,0,1},.{1,0,1},.{0,1,1},.{1,1,1}};
    // the cell's twelve edges, as pairs of its corners
    const edges=[12]m.Vice(u8,2){.{0,1},.{2,3},.{4,5},.{6,7},.{0,2},.{1,3},.{4,6},.{5,7},.{0,4},.{1,5},.{2,6},.{3,7}};
    // each block's field, over the cores
    // the job that samples each block's field
    const Fill=struct{
      /// the sculpt sampled
      s:*const Sculpt,
      /// the blocks to fill
      bs:[]Block,
      /// the box's low corner
      lo:V3,
      /// how wide a cell is
      h:f32,
      /// sample the field at every corner of blocks `first..end`
      fn run(j:@This(),first:usize,end:usize)void{
        for(j.bs[first..end])|*bl|for(0..corners)|z|for(0..corners)|y|for(0..corners)|x|{
          // the corner's point in the build space
          const p=j.lo+v3(m.f(bl.at[0]*cells+x),m.f(bl.at[1]*cells+y),m.f(bl.at[2]*cells+z))*m.splat3(j.h);
          bl.vals[(z*corners+y)*corners+x]=j.s.dist(p,bl.cand);
        };
      }
    };
    jobs.each(s.io,blocks.items.len,jobBlocks,Fill,.{.s=s,.bs=blocks.items,.lo=lo,.h=h},Fill.run);
    // a vertex in every cell the surface crosses, numbered in order, then
    // placed over the cores: the mean of where it crosses the cell's
    // edges, pulled onto the surface
    // how many vertices are numbered
    var nv:u32=0;
    for(blocks.items)|*bl|for(0..cells)|z|for(0..cells)|y|for(0..cells)|x|{
      // how many of the cell's corners lie inside
      var inside:u8=0;
      for(corner)|cc|inside+=@intFromBool(bl.vals[((z+cc[2])*corners+y+cc[1])*corners+x+cc[0]]<0);
      if(inside==0 or inside==8)continue;
      bl.vid[(z*cells+y)*cells+x]=nv;
      nv+=1;
    };
    // every vertex, placed over the cores
    const verts=try gpa.alloc(Vert,nv);
    defer gpa.free(verts);
    // the job that places each numbered vertex
    const Place=struct{
      /// the sculpt sampled
      s:*const Sculpt,
      /// the blocks whose vertices it places
      bs:[]const Block,
      /// where the placed vertices go, by their numbers
      out:[]Vert,
      /// the box's low corner
      lo:V3,
      /// how wide a cell is
      h:f32,
      /// the role a vertex takes when its nearest form sets none
      part:M.Part,
      /// place, colour and weigh the vertices of blocks `first..end`
      fn run(j:@This(),first:usize,end:usize)void{
        // the sculpt and the cell width, short
        const sc=j.s;
        const hh=j.h;
        for(j.bs[first..end])|*bl|for(0..cells)|z|for(0..cells)|y|for(0..cells)|x|{
          // the cell's vertex number, if the surface crosses it
          const vi=bl.vid[(z*cells+y)*cells+x];
          if(vi==noneId)continue;
          // the field at the cell's eight corners
          var vals:[8]f32=undefined;
          for(corner,0..)|cc,k|vals[k]=bl.vals[((z+cc[2])*corners+y+cc[1])*corners+x+cc[0]];
          // where the surface crosses the edges, summed, and how many edges
          var acc=v3(0,0,0);
          var n:f32=0;
          for(edges)|e|{
            // the field at the edge's two ends
            const a=vals[e[0]];
            const c=vals[e[1]];
            if((a<0)==(c<0))continue;
            // how far along the edge it crosses
            const f=a/(a-c);
            // the edge's two ends, in cell steps
            const pa=v3(m.f(corner[e[0]][0]),m.f(corner[e[0]][1]),m.f(corner[e[0]][2]));
            const pc=v3(m.f(corner[e[1]][0]),m.f(corner[e[1]][1]),m.f(corner[e[1]][2]));
            acc+=m.lerpV(pa,pc,f);
            n+=1;
          }
          // the cell's corner, in cell steps over the whole box
          const cell=v3(m.f(bl.at[0]*cells+x),m.f(bl.at[1]*cells+y),m.f(bl.at[2]*cells+z));
          // the mean crossing, in the build space
          var p=j.lo+(cell+acc/m.splat3(n))*m.splat3(hh);
          // onto the surface, never leaving the cell's neighbourhood
          // where it was before being pulled, to fall back on
          const start=p;
          for(0..2)|_|{
            // the field there
            const d=sc.dist(p,bl.cand);
            p-=sc.grad(p,bl.cand,hh*0.25)*m.splat3(d);
          }
          if(m.len(p-start)>hh)p=start;
          // the surface's normal there
          const nrm=sc.grad(p,bl.cand,hh*0.35);
          // the colour and role there, and that colour short
          const at=sc.colourFrom(p,bl.cand);
          const cv=at.c;
          j.out[vi]=.{
            .p=p,.n=nrm,
            .col=.{.r=@intFromFloat(@min(cv[0],255)),.g=@intFromFloat(@min(cv[1],255)),.b=@intFromFloat(@min(cv[2],255)),.a=255},
            .skin=sc.weighFrom(p,bl.cand),
            .part=if(at.part)|r|@enumFromInt(r)else j.part,
          };
        };
      }
    };
    jobs.each(s.io,blocks.items.len,jobBlocks,Place,.{.s=s,.bs=blocks.items,.out=verts,.lo=lo,.h=h,.part=part},Place.run);
    // looking up a vertex by its cell over the whole box
    const Look=struct{
      /// the vertex of cell `ci` (over the whole box), or null where there is
      /// none: outside the box, in an empty block, or a cell the surface misses
      fn cellVert(bs:[]const Block,mp:[]const u32,n:m.Vice(usize,3),ci:m.Vice(isize,3))?u32{
        for(ci)|c|if(c<0)return null;
        // the cell index as unsigned, and its block along x, y and z
        const u=m.Vice(usize,3){@intCast(ci[0]),@intCast(ci[1]),@intCast(ci[2])};
        const bb=m.Vice(usize,3){u[0]/cells,u[1]/cells,u[2]/cells};
        if(bb[0]>=n[0] or bb[1]>=n[1] or bb[2]>=n[2])return null;
        // the block's index in `bs`
        const bi=mp[(bb[2]*n[1]+bb[1])*n[0]+bb[0]];
        if(bi==noneId)return null;
        // the cell's vertex number
        const v=bs[bi].vid[((u[2]%cells)*cells+u[1]%cells)*cells+u[0]%cells];
        return if(v==noneId)null else v;
      }
    };
    // a quad across every edge the surface crosses, joining the four cells
    // around it, facing the way the field rises
    // where the quads' vertices begin
    const start=b.mark();
    // each placed vertex's skin, in the order they are put
    var skins:std.ArrayList(vertex.Skin)=.empty;
    defer skins.deinit(gpa);
    // a step along x, y and z
    const steps=[3]m.Vice(usize,3){.{1,0,0},.{0,1,0},.{0,0,1}};
    // the four cells round an edge, as steps along the two axes across it
    const around=[4]m.Vice(isize,2){.{-1,-1},.{0,-1},.{0,0},.{-1,0}};
    for(blocks.items)|*bl|{
      for(0..cells)|z|for(0..cells)|y|for(0..cells)|x|{
        // the field at the cell's low corner
        const v0=bl.vals[(z*corners+y)*corners+x];
        for(steps,0..)|st,axis|{
          // the field one step along this axis
          const v1=bl.vals[((z+st[2])*corners+y+st[1])*corners+x+st[0]];
          if((v0<0)==(v1<0))continue;
          // the cell's index over the whole box
          const g=m.Vice(isize,3){@intCast(bl.at[0]*cells+x),@intCast(bl.at[1]*cells+y),@intCast(bl.at[2]*cells+z)};
          // the two axes across the edge
          // (the first and second axes across)
          const uAx=(axis+1)%3;
          const wAx=(axis+2)%3;
          // the four cells' vertices, and whether all four have one
          var q:m.Vice(u32,4)=undefined;
          var ok=true;
          for(around,0..)|o,k|{
            // this cell round the edge
            var ci=g;
            ci[uAx]+=o[0];
            ci[wAx]+=o[1];
            if(Look.cellVert(blocks.items,map,nb,ci))|vi|q[k]=vi else ok=false;
          }
          if(!ok)continue;
          // which way the field rises along the edge: toward the outside
          const sgn:f32=if(v0<0)1 else-1;
          // the edge's direction, pointing outward
          const dir=switch(axis){0=>v3(sgn,0,0),1=>v3(0,sgn,0),else=>v3(0,0,sgn)};
          // the four vertices' points
          var quad:[4]V3=undefined;
          for(&quad,q)|*pp,vi|pp.*=verts[vi].p;
          // split along the shorter diagonal
          // the two triangles the quad is split into
          const tris:[2]m.Vice(usize,3)=if(m.len(quad[0]-quad[2])<=m.len(quad[1]-quad[3])).{.{0,1,2},.{0,2,3}}else.{.{0,1,3},.{1,2,3}};
          for(tris)|tri|{
            // the triangle's face normal, as wound
            const fnrm=m.cross(quad[tri[1]]-quad[tri[0]],quad[tri[2]]-quad[tri[0]]);
            // its corners in the order that faces outward
            const order=if(m.dot(fnrm,dir)>=0)m.Vice(usize,3){tri[0],tri[1],tri[2]}else m.Vice(usize,3){tri[0],tri[2],tri[1]};
            for(order)|k|{
              // the vertex being put
              const vv=verts[q[k]];
              try b.put(vv.p,vv.n,vv.col,t,0,vv.part);
              try skins.append(gpa,vv.skin);
            }
          }
        }
      };
    }
    @memcpy(try b.skinOf(start),skins.items);
  }
};
test"a sculpt meshes the same over the cores as here alone"{
  // the test helpers, and seeing a slice as bytes
  const testing=std.testing;
  const asBytes=std.mem.sliceAsBytes;
  // the allocator the sculpts and builders use
  const gpa=testing.allocator;
  // a mesher with a single role
  const M=@import("meshgen.zig").Mesher(enum(u32){stem},.stem);
  // one mesh built here alone, one over the cores
  var built:[2]M.Builder=.{.{.gpa=gpa},.{.gpa=gpa}};
  defer for(&built)|*b|b.deinit();
  // the one colour every form takes
  const col=color.rgb(0.5,0.4,0.3).toRgba8(255);
  for(&built,[_]?Io{null,testing.io})|*b,io|{
    // two bones, the second hung off the first
    var s:Sculpt=.{.gpa=gpa,.parents=&.{null,0},.io=io};
    defer s.deinit();
    try s.add(.{.shape=.{.ellipsoid=.{.c=v3(0,0,0),.r=v3(0.2,0.15,0.1)}},.bone=0,.col=col});
    try s.add(.{.shape=.{.cone=.{.a=v3(0,0.1,0),.b=v3(0.1,0.35,0),.ra=0.08,.rb=0.03}},.bone=1,.col=col});
    try s.add(.{.shape=.{.box=.{.c=v3(0.15,0,0),.half=v3(0.06,0.06,0.2),.round=0.02}},.bone=0,.col=col,.carve=true});
    try s.mesh(M,b,0.01,0.5,.stem);
  }
  try testing.expect(built[0].v.items.len>0);
  try testing.expectEqualSlices(u8,asBytes(built[0].v.items),asBytes(built[1].v.items));
  try testing.expectEqualSlices(u8,asBytes(built[0].skin.items),asBytes(built[1].skin.items));
}
test"each vertex takes the role of the form it lies nearest"{
  // the test helpers
  const testing=std.testing;
  // the allocator the sculpt and builder use
  const gpa=testing.allocator;
  // three roles: a default, the mesh's own, and one a form sets
  const Role=enum(u32){stem,leaf,bloom};
  // a mesher over them
  const M=@import("meshgen.zig").Mesher(Role,.stem);
  // the builder the mesh goes into
  var b:M.Builder=.{.gpa=gpa};
  defer b.deinit();
  // the one colour every form takes
  const col=color.rgb(0.5,0.4,0.3).toRgba8(255);
  // a sculpt of one bone
  var s:Sculpt=.{.gpa=gpa,.parents=&.{null}};
  defer s.deinit();
  try s.add(.{.shape=.{.ellipsoid=.{.c=v3(-0.1,0,0),.r=m.splat3(0.08)}},.bone=0,.col=col});
  try s.add(.{.shape=.{.ellipsoid=.{.c=v3(0.1,0,0),.r=m.splat3(0.08)}},.bone=0,.col=col,.part=@intFromEnum(Role.bloom)});
  try s.mesh(M,&b,0.01,0.5,.leaf);
  // how many vertices took each role
  var seen:m.Vice(usize,3)=@splat(0);
  for(b.v.items)|v|{
    seen[v.part]+=1;
    try testing.expectEqual(v.part==@intFromEnum(Role.bloom),v.pos[0]>0);
  }
  try testing.expectEqual(@as(usize,0),seen[@intFromEnum(Role.stem)]);
  try testing.expect(seen[@intFromEnum(Role.leaf)]>0 and seen[@intFromEnum(Role.bloom)]>0);
}
test"a chain of one segment is its cone, and a bent chain is as near as its nearest segment"{
  // the test helpers
  const testing=std.testing;
  // a chain of one segment, and the cone it should equal
  var one:Chain=.{.n=1};
  one.pts[0]=v3(0,0,0);
  one.pts[1]=v3(0,0.3,0);
  one.r[0]=0.05;
  one.r[1]=0.02;
  const cone:Shape=.{.cone=.{.a=v3(0,0,0),.b=v3(0,0.3,0),.ra=0.05,.rb=0.02}};
  for([_]V3{v3(0.1,0.1,0),v3(0,-0.2,0.05),v3(0.02,0.4,-0.01)})|p|{
    try testing.expectApproxEqAbs(shapeDist(&cone,p),shapeDist(&.{.chain=one},p),1e-6);
  }
  // a chain bent through a corner: inside at the corner, outside past it
  var bent:Chain=.{.n=2};
  bent.pts[0]=v3(0,0,0);
  bent.pts[1]=v3(0,0.2,0);
  bent.pts[2]=v3(0.2,0.2,0);
  bent.r=@splat(0.03);
  try testing.expect(shapeDist(&.{.chain=bent},v3(0,0.2,0))<0);
  try testing.expect(shapeDist(&.{.chain=bent},v3(0.2,0,0))>0.1);
  // its sphere holds every point's ball
  const b=shapeBound(.{.chain=bent});
  for(0..3)|i|try testing.expect(m.len(bent.pts[i]-b.c)+0.03<=b.r+1e-6);
}
