//! mesh: WOLF BELLY. a sac of sap on the gut, skinned to the spine: an egg
//! rounded and full below, drawing in smoothly toward the ribs above, its
//! back sunk in the body so only the swell shows. Convex everywhere, so
//! its near side (the only side drawn) never folds away. Bare amber, the
//! wolf's own belly swelling out of the sap panel (as the gardener drew
//! it), the sash's vine crossing it with leaves along it; a belly button
//! at the front, melted into the sac.
//!
//! tu.x on every vertex is how much of the gut it is (1 low and in front,
//! 0 toward the ribs): that share of it moves with the skeleton's gut bone,
//! which swells, rounds out toward a ball, drops and pushes forward as the
//! belly fills, while its top stays with the spine. The sac carries tu.y =
//! `belly`: the shader carves it, a crease down its middle there even when
//! empty, one across it folding in as it fills (crossing at the belly
//! button, `crossing`), and the button itself, the sac's own smooth
//! surface: an innie when empty (a round hollow, a knot sunk in it),
//! rounding out as it fills into an outie, a round dome button in a soft
//! collar. `posed` finds any point of it skinned, for the paw laid on it.
//! The grid gathers its rows and columns round the button (`gathered`) so
//! all that is carved finely.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// the allocator error every building call may fail with
const Allocator=std.mem.Allocator;
/// the test helpers, for the sac's checks
const testing=std.testing;
/// the generic engine package
const engine=lib.engine;
/// all the maths: vectors, easing, angles
const m=engine.core.math;
/// the mesh builder: patches, tubes, ellipsoids
const mg=lib.meshgen;
/// the garden's shared colours (sap, the wolf's vine and leaves)
const pal=lib.palette;
/// colours, one per vertex of the sac
const color=engine.core.color;
/// the wolf's bones, and the gut's size and growth
const skel=lib.skeleton;
/// the sculpt kit, whose `packWith` turns bone weights and their slopes into a skin
const Sculpt=engine.gfx.sculpt.Sculpt;
/// a point or direction in 3D
const V3=m.V3;
/// makes a `V3` from three numbers
const v3=m.v3;
/// the gut's centre in the waist bone's frame (its radii follow: across,
/// down, up toward the ribs, and forward)
pub const centre=skel.gutAt;
/// the sac's radius across
pub const rx:f32=skel.gutR[0];
/// the sac's radius down from its centre
pub const down:f32=skel.gutR[1];
/// the sac's reach up toward the ribs (it reaches up under the pectorals,
/// so the two meet with no bare hide between them)
pub const upReach:f32=skel.gutUp;
/// the sac's radius forward
pub const rz:f32=skel.gutR[2];
/// how far the sac narrows toward its top (share of its width)
const taper:f32=0.12;
/// the tu.y that marks the sac, which the shader creases as it fills
pub const belly:f32=3;
/// how far round from the bottom the belly button sits (radians)
const navelTh:f32=m.pi*0.47;
/// how much closer the sac's grid gathers its rows and columns round the
/// belly button (0 even .. under 1: there, steps this share shorter)
const gather:f32=0.72;
/// a grid step `u` (0..1) warped to gather round `at` (0..1): a smooth map
/// rising everywhere, its ends kept when `at` is a half (and, round the
/// sac, a whole turn still a whole turn wherever `at` is)
fn gathered(u:f32,at:f32)f32{return u-gather*@sin(m.tau*(u-at))/m.tau;}
/// where the creases cross (the belly button, on the sac's surface), in
/// the bind pose (wolf space)
pub fn crossing()V3{return waistBind+surface(navelTh,m.halfPi,1);}
/// where the waist's frame sits in the bind pose (unturned there, only moved)
const waistBind=v3(0,skel.hipY+skel.waistAt[1],skel.waistAt[2]);
/// points along the sash where it crosses the belly
const sashPoints=25;
/// where on the sac the sash is at `k` (0 under the -x pectoral .. 1
/// under the +x one): its angle up the sac and round it, swagging lowest
/// over the middle of the belly
fn sashAt(k:f32)m.Vice(f32,2){return.{(0.84-0.26*@sin(m.pi*k))*m.pi,m.lerp(0.97,0.03,k)*m.pi};}
/// the wolf's kit, whose fur leaves lie along the sash
const kit=lib.wolfKit;
/// part roles, to tell the sash's leaves apart
const vertex=lib.vertex;
/// the sac's grid: rings from bottom to top
const rings=48;
/// the sac's grid: steps round it
const sides=96;
/// a point on the sac at `th` (0 bottom .. pi top) and `ph` around (0 the
/// right side, pi/2 the front), `lift` times out from its surface, in the
/// waist's frame
fn surface(th:f32,ph:f32,lift:f32)V3{
  // how far up (-1 bottom .. 1 top) and how far out (0..1) this angle is
  const y=-@cos(th);
  const r=@sin(th);
  // how far up the top half it is, and how much the sac narrows there
  const up=@max(y,0);
  const narrow=1-taper*up*up;
  return centre+v3(@cos(ph)*r*rx*narrow,y*(if(y>0)upReach else down),@sin(ph)*r*rz*narrow)*m.splat3(lift);
}
/// the sac's outward facing (unit) at `th` and `ph`, found from small steps
/// either way (held off the poles, where the steps would vanish)
fn normal(th:f32,ph:f32)V3{
  // how far each small step goes
  const e:f32=1e-3;
  // `th` held clear of the bottom pole, then of the top one
  const t0=@max(th,2*e);
  const t1=@min(t0,m.pi-2*e);
  // the steps up the sac and round it
  const dt=surface(t1+e,ph,1)-surface(t1-e,ph,1);
  const dp=surface(t1,ph+e,1)-surface(t1,ph-e,1);
  // the facing from those two, and the way out from the centre it must agree with
  const n=m.norm(m.cross(dp,dt));
  const out=surface(t1,ph,1)-centre;
  return if(m.dot(n,out)<0)-n else n;
}
/// how much of the gut a point at `th` is (`share`)
fn gut(th:f32)f32{return share(-@cos(th)*(if(@cos(th)<0)upReach else down))[0];}
/// `scale` times a smooth step of x over `from`..`from + span`, and its
/// slope in x
fn ramp(x:f32,from:f32,span:f32,scale:f32)m.Vice(f32,2){
  // how far through the step `x` is (0..1 inside it)
  const u=(x-from)/span;
  if(u<=0 or u>=1)return.{scale*m.smooth(m.clamp01(u)),0};
  return.{scale*m.smooth(u),scale*6*u*(1-u)/span};
}
/// how far up the sac (share of `upReach`) it starts being held to the body
const pin:f32=0.55;
/// how much of the gut a point `yr` above the gut's centre is, and how fast
/// that changes going up: all of it up past the middle (so the whole sac
/// swells round, up toward the ribs as well), easing to none at its top
/// where it hangs from them. Above the middle the gut is its upper bone,
/// which lifts nothing past where the waist holds it, so this easing never
/// folds the swollen sac over itself.
fn share(yr:f32)m.Vice(f32,2){
  // how far the hold toward the top has come in, and its slope
  const r=ramp(yr/upReach,pin,1-pin,1);
  return.{1-r[0],-r[1]/upReach};
}
/// the gut's two bones part across its middle, where both take a point
/// alike: below, `gut` (the sac drops and rounds out full), above,
/// `gutTop` (the sac rounds out as wide but keeps its top). This is half
/// the height (above and below the gut's centre) over which they part.
const part:f32=0.04;
/// how much of the gut a point `yr` above its centre is of the lower bone, and its slope
fn lower(yr:f32)m.Vice(f32,2){
  // how far across the parting the point is, and its slope
  const r=ramp(yr,-part,2*part,1);
  return.{1-r[0],-r[1]};
}
/// how far the full gut bones lift a point `yr` above the gut's centre
/// (negative: drop it), the lower and the upper
fn reach(yr:f32)m.Vice(f32,2){
  return.{skel.gutGrow[1]*yr+skel.gutShift[1],skel.gutGrowTop[1]*yr+skel.gutShift[1]};
}
/// lays the belly: the sac, the sash across it with its leaves, and the belly
/// button, then weights every vertex to the gut and the spine and moves it all
/// into the waist's place in the bind pose
pub fn build(b:*mg.Builder)Allocator.Error!void{
  // where the belly's vertices begin
  const start=b.mark();
  // the grid's rings and columns (the seam column repeats the first)
  const ringCount=rings+1;
  const c=sides+1;
  // the grid's points, normals, colours and heights
  const pts=try b.gpa.alloc(V3,ringCount*c);
  defer b.gpa.free(pts);
  const nrm=try b.gpa.alloc(V3,ringCount*c);
  defer b.gpa.free(nrm);
  const cols=try b.gpa.alloc(color.Rgba8,ringCount*c);
  defer b.gpa.free(cols);
  const us=try b.gpa.alloc(f32,ringCount*c);
  defer b.gpa.free(us);
  for(0..ringCount)|i|for(0..c)|j|{
    // this ring's angle up the sac, 0 bottom .. pi top, gathered round the
    // belly button's height
    const th=gathered(m.ratio(i,rings),0.5)*m.pi;
    // round the other way, so the sheet faces out, gathered round the front
    const ph=(1-gathered(m.ratio(j,sides),0.75))*m.tau;
    // this point's place in the grid
    const at=i*c+j;
    pts[at]=surface(th,ph,1);
    nrm[at]=normal(th,ph);
    cols[at]=pal.sap;
    us[at]=0;
  };
  try mg.patch(b,ringCount,c,pts,nrm,cols,us,0,.bloom);
  // tu.x: how much of the gut each vertex is
  for(b.v.items[start..])|*vx|{
    vx.tu[0]=share(vx.pos[1]-centre[1])[0];
  }
  // decision: no net of vines over it: the belly is the wolf's own amber
  // belly as the gardener drew it, bare sap swelling out of the panel;
  // only the sash crosses it: from under the -x pectoral it swags down
  // over the belly and back up under the +x one (where the body's sash
  // runs on, under the pectorals), leaves along it
  var path:[sashPoints]V3=undefined;
  var vts:[sashPoints]f32=undefined;
  var rs:[sashPoints]f32=undefined;
  for(&path,&vts,&rs,0..)|*p,*t,*r,j|{
    // how far along the sash this point is, 0..1, and where on the sac
    const k=m.ratio(j,sashPoints-1);
    const sp=sashAt(k);
    p.*=surface(sp[0],sp[1],1.035);
    t.*=gut(sp[0]);
    // full thickness across the sac, tapering only where it tucks in at its ends
    r.*=@max(0.0105*@sqrt(@sin(m.pi*m.lerp(0.06,0.94,k))),0.0005);
  }
  try b.tubeR(&path,&vts,&rs,pal.wolfVine,.stem,5);
  for([_]usize{4,8,12,16,20})|j|{
    // which side of the sash this leaf leans, and how far up the sac it grows
    const lean:f32=if(j%8==0)1 else-1;
    const sp=sashAt(m.ratio(j,sashPoints-1));
    const out=normal(sp[0],sp[1]);
    const along=m.norm(path[j+1]-path[j-1]);
    try kit.leaf(b,.{
      .base=path[j],.along=m.norm(along+m.cross(out,along)*m.splat3(0.6*lean)),.out=out,
      .len=0.05,.width=0.02,.lift=0.5,.curl=0.4,.cup=0.3,
      .col=pal.wolfLeafDark,.tip=pal.wolfLeafLite,.t=vts[j],
    });
  }
  // (the leaves keep theirs: it is how far along them, for their stir)
  for(b.v.items[start..])|*vx|if(vx.part!=@intFromEnum(vertex.Part.leaf)){
    vx.tu[1]=belly;
  };
  // decision: the belly button is no knot of its own but the sac's surface
  // carved by the shader (a rounded button in a soft ring), so it melts into it
  // into the waist's place in the bind pose: the gut with the gut bones,
  // the rest with the spine, the hips below it and the ribs above. The
  // weights change with height alone, and the gut swells the sac to three
  // times its size, so its normals turn by how fast the weights change up
  // it too (each weight's slope, carried in the skin), not by the blended
  // bones alone
  for(b.v.items[start..],try b.skinOf(start))|vx,*k|{
    // each bone's weight for this vertex, and how fast it changes going up
    const sw=weights(vx.pos[1]);
    // each weight's slope as a direction: straight up, by how fast it changes
    var grad:[skel.count]V3=undefined;
    for(&grad,sw.dw)|*q,d|q.*=v3(0,d,0);
    k.*=Sculpt.packWith(&sw.w,&grad);
  }
  b.xform(start,skel.bind()[@intFromEnum(skel.Bone.waist)]);
}
/// each bone's weight for a point of the sac and how fast it changes going up
const Weights=struct{
  /// the weights, one per bone (summing to 1)
  w:[skel.count]f32=@splat(0),
  /// each weight's slope up the sac
  dw:[skel.count]f32=@splat(0),
};
/// the skin of a point of the sac `y` up the waist's frame: the gut (its
/// lower and upper bones) by its share, the rest the spine's, the hips
/// below and the ribs above
fn weights(y:f32)Weights{
  // how much of the gut it is, and how fast that changes going up
  const yc=y-centre[1];
  const sh=share(yc);
  const g=sh[0];
  const dg=sh[1];
  // how much of the gut is its lower bone, and its slope
  const lo=lower(yc);
  // how much of the rest the hips and the ribs take, low and high, and their slopes
  const low=ramp(-y,0,0.09,0.5);
  const high=ramp(y,0.06,0.1,0.6);
  // those slopes turned to run up the sac
  const dlow=-low[1];
  const dhigh=high[1];
  // how much of the rest is the spine's own
  const spine=1-low[0]-high[0];
  // the weights, filled in below
  var out=Weights{};
  out.w[@intFromEnum(skel.Bone.gut)]=g*lo[0];
  out.dw[@intFromEnum(skel.Bone.gut)]=dg*lo[0]+g*lo[1];
  out.w[@intFromEnum(skel.Bone.gutTop)]=g*(1-lo[0]);
  out.dw[@intFromEnum(skel.Bone.gutTop)]=dg*(1-lo[0])-g*lo[1];
  out.w[@intFromEnum(skel.Bone.pelvis)]=(1-g)*low[0];
  out.dw[@intFromEnum(skel.Bone.pelvis)]=-dg*low[0]+(1-g)*dlow;
  out.w[@intFromEnum(skel.Bone.chest)]=(1-g)*high[0];
  out.dw[@intFromEnum(skel.Bone.chest)]=-dg*high[0]+(1-g)*dhigh;
  out.w[@intFromEnum(skel.Bone.waist)]=(1-g)*spine;
  out.dw[@intFromEnum(skel.Bone.waist)]=-dg*spine-(1-g)*(dlow+dhigh);
  return out;
}
/// where the sac's surface is at `th` (0 bottom .. pi top) and `ph` around
/// (0 the right side, pi/2 the front), `lift` times out from it, in the
/// wolf's space for the bones `skin` (`skel.skin`'s matrices): skinned just
/// as the GPU skins it, so a paw laid there lies on it at every fill
pub fn posed(skin:*const[skel.count]m.M4,th:f32,ph:f32,lift:f32)V3{
  // the point in the waist's frame, and in the bind pose (the waist there
  // unturned, only moved, as `crossing` has it)
  const local=surface(th,ph,lift);
  const bound=local+waistBind;
  // the bones' weights there, and the point carried by them
  const sw=weights(local[1]);
  var out=v3(0,0,0);
  for(sw.w,skin)|wt,mat|if(wt>0){
    out+=m.mulPoint(mat,bound)*m.splat3(wt);
  };
  return out;
}
/// the sac's outward facing (unit) at `th` and `ph` for the bones `skin`,
/// from small steps either way across its posed surface
pub fn posedNormal(skin:*const[skel.count]m.M4,th:f32,ph:f32)V3{
  // how far each small step goes
  const e:f32=0.01;
  // the steps up the sac and round it, and the way out they must agree with
  const dt=posed(skin,th+e,ph,1)-posed(skin,th-e,ph,1);
  const dp=posed(skin,th,ph+e,1)-posed(skin,th,ph-e,1);
  const n=m.norm(m.cross(dp,dt));
  const out=posed(skin,th,ph,1)-posed(skin,th,ph,0.5);
  return if(m.dot(n,out)<0)-n else n;
}
test"the belly is full below and narrows toward the ribs"{
  // how wide the sac is at its middle, and high up toward the ribs
  const mid=surface(m.halfPi,0,1)[0]-centre[0];
  const high=surface(m.pi*0.85,0,1)[0]-centre[0];
  try testing.expect(mid>0.1);
  try testing.expect(high<mid*0.6);
  try testing.expect(gut(m.pi*0.25)>0.95 and gut(m.pi*0.95)<0.05);
}
test"the gathered grid rises everywhere and keeps its ends"{
  try testing.expectApproxEqAbs(0,gathered(0,0.5),1e-6);
  try testing.expectApproxEqAbs(1,gathered(1,0.5),1e-6);
  try testing.expectApproxEqAbs(1,gathered(1,0.75)-gathered(0,0.75),1e-6);
  // the last step's place, to see each one rises past it
  var last:f32=-1;
  for(0..101)|k|{
    // this step's place, gathered round the front
    const g=gathered(m.ratio(k,100),0.75);
    try testing.expect(g>last);
    last=g;
  }
}
test"the gut's shares change up the sac as their slopes say"{
  // the small step each slope is checked over
  const e:f32=1e-4;
  // which of the 200 heights up the sac is checked
  var k:usize=1;
  while(k<200):(k+=1){
    // that height above the gut's centre
    const yr=m.lerp(-down,upReach,m.ratio(k,200));
    // the gut share's slope, measured
    const fd=(share(yr+e)[0]-share(yr-e)[0])/(2*e);
    try testing.expectApproxEqAbs(fd,share(yr)[1],0.05+0.02*@abs(fd));
    // the lower bone's share's slope, measured
    const fl=(lower(yr+e)[0]-lower(yr-e)[0])/(2*e);
    try testing.expectApproxEqAbs(fl,lower(yr)[1],0.05+0.02*@abs(fl));
  }
}
test"the swelling sac never folds over itself, however full"{
  for([_]f32{0.25,0.5,1})|fill|{
    // how high the last point checked was lifted to
    var last:f32=-1e9;
    // which of the 400 heights up the sac is checked
    var k:usize=0;
    while(k<=400):(k+=1){
      // that height above the gut's centre
      const yr=m.lerp(-down,upReach,m.ratio(k,400));
      // how much of it is the gut, how much of that the lower bone, and how far each bone lifts it
      const g=share(yr)[0];
      const lo=lower(yr)[0];
      const r=reach(yr);
      // where it ends up at this fill
      const h=yr+fill*g*(lo*r[0]+(1-lo)*r[1]);
      try testing.expect(h>last);
      last=h;
    }
    // and its top stays where it hangs from the ribs
    try testing.expectApproxEqAbs(upReach,last,1e-4);
  }
}
