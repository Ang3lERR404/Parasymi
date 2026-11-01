//! viewport gizmos for the tools' editors (tools/meshedit.zig,
//! tools/animedit.zig): handles drawn over the 3D view on the UI batch,
//! held at one size on screen, that move a point along an axis or across
//! the view, turn it about an axis, or size it along one. An editor says
//! where the gizmo stands and which way each handle's axis runs; a drag on
//! a handle comes back as metres or radians along that handle.
/// the standard library, reached through the game's hub
const std=ps.std;
/// the allocator type drawing may fail with
const Allocator=std.mem.Allocator;
/// the test helpers
const testing=std.testing;
/// the game, reached through its import hub
const ps=@import("parasymi");
/// the engine package
const engine=ps.engine;
/// all the maths: vectors, matrices, projections
const m=engine.core.math;
/// the UI's draw batch, which the handles are drawn into
const Draw=engine.ui.draw.Draw;
/// a UI colour: four bytes, red, green, blue and alpha
const Color=engine.ui.draw.Color;
/// the HUD's shared colours
const s=ps.style;
/// a point or direction in the world (m)
const V3=m.V3;
/// makes a `V3` from its three parts
const v3=m.v3;
/// a 4x4 matrix: a view-projection or a turn
const M4=m.M4;
/// the gizmo's reach as a share of its distance from the eye (so it keeps
/// its size on screen)
const reachDistance:f32=0.14;
/// a ring's radius, as a share of the reach
const ringRadius:f32=0.85;
/// how many straight segments a ring is drawn with
const segs=48;
/// how near (px) the mouse must come to pick a handle
const pickRadius:f32=10;
/// how near (px) the centre a turn's drag is ignored, where its angle is wild
const nearCentre:f32=4;
/// a handle seen end on (shorter than this on screen, px) cannot be dragged
const endOn:f32=6;
/// a ring whose plane the eye's ray crosses this shallowly (cosine) is
/// turned by its angle on screen instead
const edgeOn:f32=0.15;
/// a handle's stroke radius (px)
const stroke:f32=1.6;
/// the stroke radius of a handle under the mouse or held (px)
const hotStroke:f32=2.6;
/// a move arrow's tip size (px)
const tipR:f32=6;
/// a size handle's end dot radius (px)
const sizeR:f32=4.5;
/// the centre's dot radius (px)
const centreR:f32=6;
/// each axis's colour: x rose, y leaf, z sky
const axisCol=[3]Color{.{235,120,105,255},.{150,225,110,255},.{110,170,245,255}};
/// a handle under the mouse or held
const hotColor:Color=s.gold;
/// the centre's colour
const centre:Color=s.white;
/// the alpha of a ring's far half, behind the centre
const farAlpha=80;
/// what the gizmo does: moves a point, turns it, or sizes it
pub const Mode=enum{
  /// arrows along each axis, and the centre across the view
  move,
  /// a ring about each axis
  turn,
  /// a dotted handle along each axis
  size,
};
/// a handle: one of the three axes, or (moving) the centre, across the view
pub const Part=enum{
  /// the first axis's handle
  x,
  /// the second axis's handle
  y,
  /// the third axis's handle
  z,
  /// the centre, dragged across the view
  free,
};
/// how the 3D view is seen this frame
pub const View=struct{
  /// the view-projection: the world to clip space
  vp:M4,
  /// where the eye is (world)
  eye:V3,
  /// the window's size (px)
  screen:m.Vec(f32,2),
  /// `p` (world) on screen, or null behind the eye
  pub fn project(v:View,p:V3)?m.Vec(f32,2){
    // the point in clip space
    const c=m.mulV(v.vp,.{p[0],p[1],p[2],1});
    if(c[3]<=1e-4)return null;
    return.{(c[0]/c[3]*0.5+0.5)*v.screen[0],(c[1]/c[3]*0.5+0.5)*v.screen[1]};
  }
  /// where the ray through pixel `px` meets the plane through `at` across
  /// `n`, or null where it runs too nearly along the plane
  fn onPlane(v:View,px:m.Vec(f32,2),at:V3,n:V3)?V3{
    // clip space back to the world
    const inv=m.inverse(v.vp);
    // the pixel in normalized device coordinates
    const x=px[0]/v.screen[0]*2-1;
    const y=px[1]/v.screen[1]*2-1;
    // the ray's near and far ends, still homogeneous
    const a=m.mulV(inv,.{x,y,0,1});
    const b=m.mulV(inv,.{x,y,1,1});
    // the ray's start (world) and its way (unit)
    const o=v3(a[0],a[1],a[2])/m.splat3(a[3]);
    const dir=m.norm(v3(b[0],b[1],b[2])/m.splat3(b[3])-o);
    // how squarely the ray crosses the plane (cosine)
    const across=m.dot(dir,n);
    if(@abs(across)<edgeOn)return null;
    return o+dir*m.splat3(m.dot(at-o,n)/across);
  }
};
/// the gizmo: where it stands, what it does and which way its handles run
pub const Gizmo=struct{
  /// where it stands (world)
  at:V3,
  /// moves, turns or sizes
  mode:Mode,
  /// each handle's axis in the world (unit); null where there is none
  axes:[3]?V3,
  /// how long (m) a handle reaches: kept the same size on screen
  fn reach(g:Gizmo,v:View)f32{return m.len(g.at-v.eye)*reachDistance;}
  /// point `i` of `segs` round the ring of radius `r` about axis `a`
  fn ringPoint(g:Gizmo,a:V3,r:f32,i:usize)V3{
    // the point's angle round the ring (rad)
    const t=m.tau*m.f(i)/segs;
    // any direction not along the axis, to build the ring's plane from
    const ref=if(@abs(a[1])<0.9)v3(0,1,0)else v3(1,0,0);
    // two unit directions across the axis, spanning the ring's plane
    const u=m.norm(m.cross(a,ref));
    const w=m.cross(a,u);
    return g.at+(u*m.splat3(@cos(t))+w*m.splat3(@sin(t)))*m.splat3(r);
  }
  /// the handle under `mouse`, if any
  pub fn pick(g:Gizmo,v:View,mouse:m.Vec(f32,2))?Part{
    // the centre on screen, and the handles' reach
    const c=v.project(g.at) orelse return null;
    const r=g.reach(v);
    // the nearest handle so far, and how near (px)
    var best:f32=pickRadius;
    var hit:?Part=null;
    if(g.mode==.move and dist2(c,mouse)<centreR+pickRadius/2)return.free;
    for(g.axes,0..)|ax,k|if(ax)|a|{
      // how far (px) the mouse is from this handle's line or ring
      const d=switch(g.mode){
        .move,.size=>if(v.project(g.at+a*m.splat3(r)))|tip|segDist(mouse,c,tip)else continue,
        .turn=>ring:{
          // the nearest the mouse comes to the ring, and the last point drawn
          var near:f32=m.inf(f32);
          var prev=v.project(g.ringPoint(a,r*ringRadius,0));
          for(1..segs+1)|i|{
            // this point of the ring on screen
            const cur=v.project(g.ringPoint(a,r*ringRadius,i));
            if(prev!=null and cur!=null)near=@min(near,segDist(mouse,prev.?,cur.?));
            prev=cur;
          }
          break:ring near;
        },
      };
      if(d<best){
        best=d;
        hit=@enumFromInt(k);
      }
    };
    return hit;
  }
  /// how far a drag from `from` to `to` (px) carries axis `k`: metres
  /// along it (moving, sizing) or radians about it (turning)
  pub fn along(g:Gizmo,v:View,k:usize,from:m.Vec(f32,2),to:m.Vec(f32,2))f32{
    // the handle's axis, and the centre on screen
    const a=g.axes[k] orelse return 0;
    const c=v.project(g.at) orelse return 0;
    switch(g.mode){
      .move,.size=>{
        // the handle's reach, its tip on screen, and its line there (px)
        const r=g.reach(v);
        const tip=v.project(g.at+a*m.splat3(r)) orelse return 0;
        const d=tip-c;
        // the handle's length on screen (px)
        const l=@sqrt(m.sumOf(f32,2,d*d));
        if(l<endOn)return 0;
        // pixels along the handle's line, over its pixels per metre
        return m.sumOf(f32,2,(to-from)*d)/l/(l/r);
      },
      .turn=>{
        if(dist2(from,c)<nearCentre or dist2(to,c)<nearCentre)return 0;
        // where the mouse meets the ring's plane, turned about the axis
        if(v.onPlane(from,g.at,a))|p0|if(v.onPlane(to,g.at,a))|p1|{
          // the two points from the centre, in the ring's plane
          const q0=p0-g.at;
          const q1=p1-g.at;
          return m.atan2(m.dot(m.cross(q0,q1),a),m.dot(q0,q1));
        };
        // the ring seen edge on: by the angle round its centre on screen
        // the angle the mouse turned round the centre on screen (rad)
        const da=m.angleDiff(m.atan2(from[1]-c[1],from[0]-c[0]),m.atan2(to[1]-c[1],to[0]-c[0]));
        // screen y runs down: an axis toward the eye turns the other way round
        return if(m.dot(a,v.eye-g.at)>0)-da else da;
      },
    }
  }
  /// where a drag of the centre from `from` to `to` (px) carries it, across
  /// the view at its depth (world metres)
  pub fn across(g:Gizmo,v:View,from:m.Vec(f32,2),to:m.Vec(f32,2))V3{
    // the way the eye looks at the gizmo, and the view's right and up there
    const fw=m.norm(g.at-v.eye);
    const right=m.norm(m.cross(fw,v3(0,1,0)));
    const up=m.cross(right,fw);
    // the reach, the centre on screen, and the reach's right end on screen
    const r=g.reach(v);
    const c=v.project(g.at) orelse return v3(0,0,0);
    const px=v.project(g.at+right*m.splat3(r)) orelse return v3(0,0,0);
    // pixels per metre at the gizmo's depth
    const per=dist2(px,c)/r;
    if(per<m.eps)return v3(0,0,0);
    return(right*m.splat3(to[0]-from[0])-up*m.splat3(to[1]-from[1]))*m.splat3(1/per);
  }
  /// drawn over the view, `hot` (under the mouse or held) in gold
  pub fn draw(g:Gizmo,d:*Draw,v:View,hot:?Part)Allocator.Error!void{
    // the centre on screen, and the handles' reach
    const c=v.project(g.at) orelse return;
    const r=g.reach(v);
    for(g.axes,0..)|ax,k|if(ax)|a|{
      // whether this handle is hot, its colour, and its stroke
      const lit=hot!=null and @intFromEnum(hot.?)==k;
      const col=if(lit)hotColor else axisCol[k];
      const w=if(lit)hotStroke else stroke;
      switch(g.mode){
        .move,.size=>{
          // the handle's tip on screen
          const tip=v.project(g.at+a*m.splat3(r)) orelse continue;
          try d.limb(c,tip,w,w,col,0);
          if(g.mode==.move)try d.leaf(tip,m.atan2(tip[1]-c[1],tip[0]-c[0]),tipR*2,tipR*1.4,col,0,m.f(k))else try d.pod(tip[0],tip[1],sizeR,col,1,m.f(k));
        },
        .turn=>{
          // the last point of the ring
          var prev=g.ringPoint(a,r*ringRadius,0);
          for(1..segs+1)|i|{
            // the next point, and both on screen
            const cur=g.ringPoint(a,r*ringRadius,i);
            const p0=v.project(prev);
            const p1=v.project(cur);
            // the ring's half beyond the centre, seen from the eye, faint
            // whether this segment is on the eye's side of the centre
            const near=m.dot((prev+cur)*m.splat3(0.5)-g.at,v.eye-g.at)>=0;
            // its colour, faded beyond the centre
            var cc=col;
            if(!near)cc[3]=farAlpha;
            if(p0!=null and p1!=null)try d.limb(p0.?,p1.?,w,w,cc,m.f(i));
            prev=cur;
          }
        },
      }
    };
    if(g.mode==.move)try d.pod(c[0],c[1],centreR,if(hot==.free)hotColor else centre,1,0)else try d.pod(c[0],c[1],centreR*0.6,centre,1,0);
  }
};
/// the distance (px) between two points on screen
fn dist2(a:m.Vec(f32,2),b:m.Vec(f32,2))f32{
  // the run from one to the other
  const d=a-b;
  return @sqrt(m.sumOf(f32,2,d*d));
}
/// from `p` to the segment `a`..`b` (px)
fn segDist(p:m.Vec(f32,2),a:m.Vec(f32,2),b:m.Vec(f32,2))f32{
  // the segment's run, and the point from its start
  const ab=b-a;
  const ap=p-a;
  // the segment's length squared, and how far along it the nearest point is (0..1)
  const l2=m.sumOf(f32,2,ab*ab);
  const t=if(l2>m.eps)m.clamp01(m.sumOf(f32,2,ap*ab)/l2)else 0;
  // from the nearest point on the segment to `p`
  const off=ap-ab*@as(m.Vec(f32,2),@splat(t));
  return @sqrt(m.sumOf(f32,2,off*off));
}
/// a 1600x900 view from `eye` looking at the origin, for the tests
fn testView(eye:V3)View{
  // the view-projection: a 50 degree lens
  const vp=m.mul(m.perspective(m.rad(50),16.0/9.0,0.05,100),m.lookAt(eye,v3(0,0,0),v3(0,1,0)));
  return.{.vp=vp,.eye=eye,.screen=.{1600,900}};
}
test"a turn's drag reads as the turn that carries a point there"{
  for([_]V3{v3(2,1.5,3),v3(-3,2,-2)})|eye|{
    // the view from this eye
    const v=testView(eye);
    // a small turn about each axis, and those axes
    const turns=[3]M4{m.rotX(0.1),m.rotY(0.1),m.rotZ(0.1)};
    const axes=[3]V3{v3(1,0,0),v3(0,1,0),v3(0,0,1)};
    for(turns,axes,0..)|t,a,k|{
      // a turning gizmo at the origin with every ring on axis `a`
      const g:Gizmo=.{.at=v3(0,0,0),.mode=.turn,.axes=.{a,a,a}};
      // a point off the axis, turned by 0.1 about it
      const p=m.norm(m.cross(a,v3(0.3,0.5,0.7)))*m.splat3(0.5);
      // the turn the drag reads as
      const got=g.along(v,k,v.project(p).?,v.project(m.mulPoint(t,p)).?);
      try testing.expectApproxEqAbs(@as(f32,0.1),got,0.002);
    }
  }
}
test"a move's drag reads as the metres along the handle"{
  // the view, and a moving gizmo at the origin with all three arrows
  const v=testView(v3(2,1.5,3));
  const g:Gizmo=.{.at=v3(0,0,0),.mode=.move,.axes=.{v3(1,0,0),v3(0,1,0),v3(0,0,1)}};
  for(0..3)|k|{
    // a step of 5 cm along this arrow, and what the drag reads as
    const step=g.axes[k].?*m.splat3(0.05);
    const got=g.along(v,k,v.project(g.at).?,v.project(step).?);
    try testing.expectApproxEqAbs(@as(f32,0.05),got,0.01);
  }
  // across the view: back where the mouse went
  // where the mouse went, where the centre was carried, and that back on screen
  const to=v.project(v3(0.05,0.03,0)).?;
  const moved=g.across(v,v.project(g.at).?,to);
  const back=v.project(moved).?;
  try testing.expectApproxEqAbs(to[0],back[0],2);
  try testing.expectApproxEqAbs(to[1],back[1],2);
}
test"a handle is picked where it is drawn"{
  // the view, and a sizing gizmo with no y handle
  const v=testView(v3(2,1.5,3));
  const g:Gizmo=.{.at=v3(0,0,0),.mode=.size,.axes=.{v3(1,0,0),null,v3(0,0,1)}};
  // the handles' reach (m)
  const r=g.reach(v);
  try testing.expectEqual(Part.x,g.pick(v,v.project(v3(r*0.7,0,0)).?).?);
  try testing.expectEqual(Part.z,g.pick(v,v.project(v3(0,0,r*0.7)).?).?);
  // no y handle
  try testing.expect(g.pick(v,v.project(v3(0,r*0.7,0)).?)==null);
}
