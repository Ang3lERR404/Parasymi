//! shared pieces for the wolf's body: the leaves that lie over it like fur
//! and the digits of its hands and feet (forms of planes: superellipsoids,
//! flat faces, rounded edges, with curved claws). Not a mesh itself; the
//! wolf's meshes use it.
const lib=@import("../../lib.zig");
const std=lib.std;
const Allocator=std.mem.Allocator;
const testing=std.testing;
const engine=lib.engine;
const m=engine.core.math;
const mg=lib.meshgen;
const color=engine.core.color;
const vertex=lib.vertex;
const Sculpt=engine.gfx.sculpt.Sculpt;
const V3=m.V3;
const v3=m.v3;
const M4=m.M4;
fn spow(c:f32,e:f32)f32{return m.sign(c)*m.pow(f32,@abs(c),e);}
pub const Form=struct{
  center:V3,
  radii:V3,
  /// squareness down its height (`ns`) and around it (`ew`): 1 round,
  /// toward 0 flat faces with sharper edges
  ns:f32=0.7,
  ew:f32=0.7,
  col:color.Rgba8,
  part:vertex.Part=.stem,
  t:f32=0.5,
  rings:u32=10,
  segs:u32=14,
};
fn formPoint(f:Form,th:f32,ph:f32)V3{
  const ct=spow(@cos(th),f.ns);
  return f.center+v3(f.radii[0]*ct*spow(@cos(ph),f.ew),f.radii[1]*spow(@sin(th),f.ns),f.radii[2]*ct*spow(@sin(ph),f.ew));
}
fn formNormal(f:Form,th:f32,ph:f32)V3{
  const ct=spow(@cos(th),2-f.ns);
  return m.norm(v3(ct*spow(@cos(ph),2-f.ew)/f.radii[0],spow(@sin(th),2-f.ns)/f.radii[1],ct*spow(@sin(ph),2-f.ew)/f.radii[2]));
}
/// a solid form with defined faces: a superellipsoid, closed at its poles.
pub fn form(b:*mg.Builder,f0:Form)Allocator.Error!void{
  var f=f0;
  f.rings=b.around(f0.rings,4);
  f.segs=b.around(f0.segs,6);
  for(0..f.rings)|i|for(0..f.segs)|j|{
    const th0=-m.halfPi+m.pi*m.ratio(i,f.rings);
    const th1=-m.halfPi+m.pi*m.ratio(i+1,f.rings);
    const ph0=m.tau*m.ratio(j,f.segs);
    const ph1=m.tau*m.ratio(j+1,f.segs);
    const q=[4][2]f32{.{th0,ph0},.{th0,ph1},.{th1,ph1},.{th1,ph0}};
    var p:[4]V3=undefined;
    var n:[4]V3=undefined;
    for(q,0..)|c,k|{
      p[k]=formPoint(f,c[0],c[1]);
      n[k]=formNormal(f,c[0],c[1]);
    }
    // front faces wind counter-clockwise seen from outside
    // (the quad 0,3,2,1's normal from its diagonals, robust at the poles)
    const flip=m.dot(m.cross(p[2]-p[0],p[1]-p[3]),n[0]+n[1]+n[2]+n[3])<0;
    const order=if(flip)[_]usize{0,1,2,0,2,3}else[_]usize{0,2,1,0,3,2};
    for(order)|c|try b.put(p[c],n[c],f.col,f.t,0,f.part);
  };
}
pub const Leaf=struct{
  /// where it grows from, flush with the surface
  base:V3,
  /// the way it lies along the surface (unit, tangent to it)
  along:V3,
  /// the surface's outward normal there
  out:V3,
  len:f32,
  width:f32,
  /// how far its tip has lifted off the surface (radians)
  lift:f32=0.35,
  /// how much the tip curls back over toward the surface, like an
  /// unfurled frond settling (radians at the tip)
  curl:f32=0.25,
  /// cupped across its width, edges toward the surface
  cup:f32=0.25,
  col:color.Rgba8,
  tip:color.Rgba8,
  t:f32=1,
};
/// a leaf lying over the body like fur: its base flush with the surface it
/// emerges from, lifting off it and curling back toward it at the tip. A
/// `lamina` (thin, bevelled, veined), tu.y running base to tip (the part
/// shader moves the tips, never the base).
pub fn leaf(b:*mg.Builder,l:Leaf)Allocator.Error!void{
  const ringCount=8;
  const side=m.norm(m.cross(l.out,l.along));
  var spine:[ringCount]V3=undefined;
  var face:[ringCount]V3=undefined;
  spine[0]=l.base;
  for(0..ringCount)|i|{
    const k=m.ratio(i,ringCount-1);
    const h=l.lift*m.pow(f32,k,0.7)-l.curl*k*k*k;
    const dir=l.along*m.splat3(@cos(h))+l.out*m.splat3(@sin(h));
    if(i>0)spine[i]=spine[i-1]+dir*m.splat3(l.len/(ringCount-1));
    face[i]=m.norm(m.cross(dir,side));
  }
  var sides:[ringCount]V3=undefined;
  var under:[ringCount]V3=undefined;
  var ws:[ringCount]f32=undefined;
  var dish:[ringCount]f32=undefined;
  var vein:[ringCount]f32=undefined;
  var cs:[ringCount]color.Rgba8=undefined;
  for(0..ringCount)|i|{
    const k=m.ratio(i,ringCount-1);
    // lanceolate: a narrow claw, broadest a third along, a long point
    ws[i]=l.width*@sqrt(@max(@sin(m.pi*m.pow(f32,k,0.75)),0))*(1-0.35*k);
    sides[i]=side;
    // it cups toward the body, and its vein runs in the cup
    under[i]=-face[i];
    dish[i]=l.cup*ws[i];
    vein[i]=mg.laminaThick*l.width*0.8*(1-0.7*k);
    cs[i]=color.mix(l.col,l.tip,k);
  }
  try mg.lamina(b,.{.spine=&spine,.side=&sides,.face=&under,.width=&ws,.dish=&dish,.broad=l.width,.vein=&vein,.col=&cs,.t=l.t,.part=.leaf});
}
test"a fur leaf's base stays on the surface it grows from"{
  var b:mg.Builder=.{.gpa=testing.allocator};
  defer b.deinit();
  try leaf(&b,.{.base=v3(0,1,0),.along=v3(0,0,-1),.out=v3(0,1,0),.len=0.1,.width=0.02,.col=.{.r=0,.g=0,.b=0,.a=255},.tip=.{.r=0,.g=0,.b=0,.a=255}});
  for(b.v.items)|vx|if(vx.tu[1]==0)try testing.expectApproxEqAbs(@as(f32,1),vx.pos[1],1e-5);
}
/// a lobe of resin grown over the hide (the pectorals, the rear): an
/// outline laid over the body (`s`: the part of it the lobe lies on), every
/// point of it found on the hide by casting out from one point deep inside
/// the body behind the lobe, and the lobe raised off the hide along its
/// normal there, so its base hugs the body wherever it curves.
/// `Shape` gives the outline (`outline(a)`: x, y at unit radius for angle
/// `a`), the rise off the hide (`height(k, a, x, y)`: k 0 crown .. 1 rim,
/// falling to 0 with no slope at the rim so the resin melts into the
/// hide) and `CROWN` (its crown's height). `at` places the lobe: x, y
/// across the body, +z out of it.
///
/// Every vertex is part `.resin` with tu.y its height through the lobe (0
/// on the body, 1 at its crown), weighted to the bones of the hide where
/// it lies, so it moves exactly as the hide does. One watertight sheet:
/// the raised face and a base sunk just under it, meeting at the rim.
pub fn resinLobe(b:*mg.Builder,s:*const Sculpt,at:M4,comptime Shape:type,comptime rings:usize,comptime steps:usize,col:color.Rgba8,t:f32)Allocator.Error!void{
  const ringCount=rings+1;
  const columns=steps+1; // the seam column repeats the first, at the same place
  const pointCount=ringCount*columns;
  // how far in behind the lobe the casts start, and the base's sink
  const reachDistance:f32=0.12;
  const sinkAmount:f32=0.004;
  // farther than this from where a point was expected, a cast went astray
  const jump:f32=0.012;
  // how smooth the sheet it rises off is, and from how far out (share of
  // the radius) it settles onto the hide
  const smoothing=60;
  const settle:f32=0.55;
  // and from how far out it rises along the hide's facing, not the sheet's
  const turnRate:f32=0.85;
  // the face stands this far clear of the hide (the hide's flat facets lie
  // outside its true surface in a crease and would show through), diving
  // under it to the base over this outer share of the radius
  const clear:f32=0.0015;
  const diveDepth:f32=0.08;
  const Grid=struct{hide:[pointCount]V3,up:[pointCount]V3,base:[pointCount]V3,bn:[pointCount]V3,face:[pointCount]V3,us:[pointCount]f32,skin:[pointCount]vertex.Skin,pts:[pointCount]V3,nrm:[pointCount]V3,cols:[pointCount]color.Rgba8,ts:[pointCount]f32};
  const g=try b.gpa.create(Grid);
  defer b.gpa.destroy(g);
  const hide=&g.hide;
  const up=&g.up;
  const face=&g.face;
  const us=&g.us;
  // decision: every cast starts from one point deep behind the lobe's
  // centre (always inside the body) toward its point on the lobe, so a
  // rim point never starts outside it (between the legs, under an arm)
  // and neighbouring points come out of the hide next to each other
  const deep=m.mulPoint(at,v3(0,0,-reachDistance));
  for(0..ringCount)|i|for(0..columns)|j|{
    const k=m.ratio(i,rings);
    const a=m.ratio(j,steps)*m.tau;
    const o=Shape.outline(a);
    const x=o[0]*k;
    const y=o[1]*k;
    const q=i*columns+j;
    const on=m.mulPoint(at,v3(x,y,0));
    // where the last ring's point plus this step across the lobe would be:
    // a hit much farther off came out through another part (the thigh
    // under the buttock), so the hide there is followed on instead
    const guess=if(i==0)on else hide[q-columns]+on-m.mulPoint(at,v3(o[0]*m.ratio(i-1,rings),o[1]*m.ratio(i-1,rings),0));
    const hit=try s.castOut(deep,m.norm(on-deep),3*reachDistance);
    const near=if(hit)|c|i==0 or m.len(c.p-guess)<jump else false;
    const h=if(near)hit.?else try s.project(guess);
    hide[q]=h.p;
    up[q]=h.n;
  };
  // the lobe rises off a smooth sheet stretched over the hide (its rim
  // held on it), not off every muscle and ridge under it; toward the rim
  // it settles back onto the hide itself
  const sheet=&g.pts;
  const lift=&g.nrm;
  @memcpy(sheet,hide);
  @memcpy(lift,up);
  for(0..smoothing)|_|{
    for(0..rings)|i|for(0..columns)|j|{
      const q=i*columns+j;
      if(i==0){
        var ps=v3(0,0,0);
        var ns=v3(0,0,0);
        for(0..steps)|jj|{
          ps+=sheet[columns+jj];
          ns+=lift[columns+jj];
        }
        sheet[q]=ps/m.splat3(m.f(steps));
        lift[q]=m.norm(ns);
        continue;
      }
      const jl=if(j==0)steps-1 else j-1;
      const jr=if(j==steps)1 else j+1;
      const nb=[4]usize{(i-1)*columns+j,(i+1)*columns+j,i*columns+jl,i*columns+jr};
      var ps=v3(0,0,0);
      var ns=v3(0,0,0);
      for(nb)|o|{
        ps+=sheet[o];
        ns+=lift[o];
      }
      sheet[q]=ps*m.splat3(0.25);
      lift[q]=m.norm(ns);
    };
    // never sinking into the body: it drapes over it, bridging its
    // hollows and creases but keeping its swell
    for(sheet,hide,up)|*sp,hp,n|sp.*+=n*m.splat3(@max(m.dot(hp-sp.*,n),0));
  }
  for(0..ringCount)|i|for(0..columns)|j|{
    const q=i*columns+j;
    const k=m.ratio(i,rings);
    const a=m.ratio(j,steps)*m.tau;
    const o=Shape.outline(a);
    const on=m.smooth(m.clamp01((k-settle)/(1-settle)));
    const p0=m.lerpV(sheet[q],hide[q],on);
    // it rises along the smooth sheet's facing until close to the rim,
    // where it is low: raised far along the hide's own facing over a
    // crease tighter than its height (under the buttock), it would fold
    const turn=m.smooth(m.clamp01((k-turnRate)/(1-turnRate)));
    const n0=m.norm(m.lerpV(lift[q],up[q],turn));
    const h=Shape.height(k,a,o[0]*k,o[1]*k);
    g.base[q]=p0;
    // weighted where it really lies (over a crease, the sheet bridging it)
    g.skin[q]=try s.weigh(p0);
    g.bn[q]=n0;
    const dive=m.smooth(m.clamp01((k-(1-diveDepth))/diveDepth));
    face[q]=p0+n0*m.splat3(h+m.lerp(clear,-sinkAmount,dive));
    us[q]=m.clamp01(h/Shape.crown);
  };
  // which way round the columns run so the raised face faces out
  const mid=(rings/2)*columns+1;
  const flip=m.dot(m.cross(face[mid+columns]-face[mid-columns],face[mid+1]-face[mid-1]),up[mid])<0;
  const pts=&g.pts;
  const nrm=&g.nrm;
  const cols=&g.cols;
  const ts=&g.ts;
  for(0..2)|side|{
    const back=side==1;
    for(0..ringCount)|i|for(0..columns)|jj|{
      const j=if(flip!=back)steps-jj else jj;
      const q=i*columns+j;
      const o=i*columns+jj;
      if(back){
        // just under the surface the face rises off, where the face dives
        // to meet it at the rim
        pts[o]=g.base[q]-g.bn[q]*m.splat3(sinkAmount);
        nrm[o]=-g.bn[q];
        ts[o]=0;
      }else{
        pts[o]=face[q];
        // across the grid: down the rings and round the outline (wrapping)
        const dk=face[@min(i+1,rings)*columns+j]-face[(if(i==0)0 else i-1)*columns+j];
        const da=face[i*columns+(if(j==steps)1 else j+1)]-face[i*columns+(if(j==0)steps-1 else j-1)];
        var n=m.cross(dk,da);
        if(m.len(n)<1e-10)n=up[q];
        if(m.dot(n,up[q])<0)n=-n;
        nrm[o]=m.norm(n);
        ts[o]=us[q];
      }
      cols[o]=col;
    };
    const first=b.mark();
    try mg.patch(b,ringCount,columns,pts,nrm,cols,ts,t,.resin);
    // each column moves with the hide under it, crown and base alike: the
    // patch's vertices in the order it puts them (the rows and columns
    // kept at this level of detail, two triangles a quad)
    var kr:[ringCount]usize=undefined;
    var kc:[columns]usize=undefined;
    const nr=mg.stride(ringCount,b.step(),&kr);
    const nc=mg.stride(columns,b.step(),&kc);
    const skin=try b.skinOf(first);
    var v:usize=0;
    for(0..nr-1)|ri|for(0..nc-1)|ci|{
      const quad=[4][2]usize{.{kr[ri],kc[ci]},.{kr[ri],kc[ci+1]},.{kr[ri+1],kc[ci+1]},.{kr[ri+1],kc[ci]}};
      for([_]usize{0,1,2,0,2,3})|c|{
        const i=quad[c][0];
        const jj=quad[c][1];
        const j=if(flip!=back)steps-jj else jj;
        skin[v]=g.skin[i*columns+j];
        v+=1;
      }
    };
  }
}
/// a claw: a curved, tapering hook from `base` along `dir`, bending toward
/// `down` as it goes, closed to a point.
pub fn claw(b:*mg.Builder,base:V3,dir:V3,down:V3,len:f32,r:f32,col:color.Rgba8)Allocator.Error!void{
  const steps=7;
  var path:[steps]V3=undefined;
  var ts:[steps]f32=undefined;
  var rs:[steps]f32=undefined;
  path[0]=base;
  for(0..steps)|i|{
    const k=m.ratio(i,steps-1);
    const d=m.norm(dir*m.splat3(@cos(k*1.1))+down*m.splat3(@sin(k*1.1)));
    if(i>0)path[i]=path[i-1]+d*m.splat3(len/(steps-1));
    ts[i]=0;
    rs[i]=r*(1-k)+0.0006;
  }
  try b.tubeR(&path,&ts,&rs,col,.thorn,5);
}
/// a digit: a knuckle, a finger or toe arching from `base` along `dir` and
/// down to the ground (`down`), and its claw. Segments are forms of planes.
pub const Digit=struct{
  base:V3,
  dir:V3,
  down:V3=v3(0,-1,0),
  len:f32,
  r:f32,
  col:color.Rgba8,
  claw:color.Rgba8,
};
pub fn digit(b:*mg.Builder,d:Digit)Allocator.Error!void{
  const side=m.norm(m.cross(d.down,d.dir));
  // knuckle, then two segments, each a little lower and narrower
  const segs=[_]struct{at:f32,drop:f32,w:f32,l:f32}{
    .{.at=0.0,.drop=0.0,.w=1.15,.l=0.42},
    .{.at=0.42,.drop=0.25,.w=0.95,.l=0.36},
    .{.at=0.75,.drop=0.55,.w=0.8,.l=0.3},
  };
  for(segs)|sg|{
    const c=d.base+d.dir*m.splat3(d.len*sg.at)+d.down*m.splat3(d.r*sg.drop);
    const s=b.mark();
    try form(b,.{.center=v3(0,0,0),.radii=v3(d.r*sg.w,d.r*sg.w*0.85,d.len*sg.l*0.62),.ns=0.75,.ew=0.65,.col=d.col,.rings=7,.segs=9});
    // align the segment: its length along dir, its top away from down
    const up=-m.norm(m.cross(d.dir,side));
    b.xform(s,.{
      .{side[0],side[1],side[2],0},
      .{up[0],up[1],up[2],0},
      .{d.dir[0],d.dir[1],d.dir[2],0},
      .{c[0],c[1],c[2],1},
    });
  }
  const tip=d.base+d.dir*m.splat3(d.len*0.98)+d.down*m.splat3(d.r*0.55);
  try claw(b,tip,d.dir,d.down,d.r*1.6,d.r*0.42,d.claw);
}
