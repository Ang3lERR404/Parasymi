//! laminae: leaves with a body, folding to a midrib.
const lib=@import("../../lib.zig");
/// the standard library, reached through the hub
const std=lib.std;
/// checks a lamina's rows fit and its ring closes
const assert=std.debug.assert;
/// the allocator type every building call may fail with
const Allocator=std.mem.Allocator;
/// the engine package
const engine=lib.engine;
/// all the maths: vectors, normals, powers
const m=engine.core.math;
/// the garden's part roles
const vertex=lib.vertex;
/// colour types and mixing, for the paler vein
const color=engine.core.color;
/// a point or direction in 3D
const V3=m.V3;
/// the mesh builder laminae are poured into
const Builder=lib.meshgen.Builder;
/// which rows or points are kept at a level of detail
const stride=lib.meshgen.stride;
/// half a leaf's or petal's thickness, as a share of its broadest half-width
pub const laminaThick:f32=0.055;
/// most rows a lamina may have
const maxLamina=12;
/// a lamina's cross-section, once round: the face (its cupped side) edge to
/// edge with the vein's crest at its middle, round the right edge, the
/// back, round the left edge
const faceU=[_]f32{-1,-0.5,-0.07,0,0.07,0.5,1};
const backU=[_]f32{1,0.5,0,-0.5,-1};
/// the edge's bevel: the angles (off the midplane) it is rounded over at
const bevel=[_]f32{0.9,-0.9};
/// how many points go round a lamina's cross-section
const laminaRing=faceU.len+backU.len+2*bevel.len;
/// how much thinner a lamina is at its edge than along its midrib
const edgeThin:f32=0.35;
/// the vein's colour: paler than the blade it runs through
const veinPale=color.rgb(0.9,0.92,0.72);
/// a leaf or petal with a body to it: its mid-surface (row i at `spine[i]`,
/// `width[i]` out each way along `side[i]`, its edges rising `dish[i]`
/// toward `face[i]`, the side it cups to; `bow` 1 folds it along the
/// midrib, 2 cups it smoothly) given a thin thickness that rounds over at
/// the edges, a small bevel catching the light. `vein` raises a midrib along
/// the face, in the fold. Rows run base to tip (tu.y); where a row closes to
/// a point the shell closes with it, so it is watertight.
pub const Lamina=struct{
  /// its mid-surface, base to tip: one point per row
  spine:[]const V3,
  /// the way each row's width lies
  side:[]const V3,
  /// the side each row cups toward
  face:[]const V3,
  /// each row's half-width
  width:[]const f32,
  /// how far each row's edges rise toward its face
  dish:[]const f32,
  /// 1 folds it to a sharp midrib (a leaf), 2 cups it smoothly (a petal)
  bow:f32=2,
  /// its broadest half-width (the thickness follows it)
  broad:f32,
  /// how far the vein rises off the face, per row
  vein:?[]const f32=null,
  /// each row's colour
  col:[]const color.Rgba8,
  /// how far along its growth it forms (tu.x)
  t:f32,
  /// the shading role it is drawn with
  part:vertex.Part,
};
/// builds a lamina: the mid-surface given its thin body, bevelled edges and
/// raised vein, its normals from the shell itself; watertight, its rows
/// thinned to the builder's level of detail
pub fn lamina(b:*Builder,l:Lamina)Allocator.Error!void{
  // how many rows the lamina has, and how many points go round each
  const rows=l.spine.len;
  const columns=laminaRing;
  // each row's points round its cross-section
  assert(rows>=2 and rows<=maxLamina);
  var pts:[maxLamina][columns]V3=undefined;
  // ...and its normal as the cross-section alone would have it
  // each point's normal as the cross-section alone would have it: it orients
  // the sheet's own, and stands in where a row closes to a point
  var tpl:[maxLamina][columns]V3=undefined;
  // each point's colour, the vein's paler
  var cs:[maxLamina][columns]color.Rgba8=undefined;
  // the vein's pale colour, as the vertex holds it
  const pale=veinPale.toRgba8(255);
  for(0..rows)|i|{
    // this row's half-width, the side it cups to and the way it lies
    const w=l.width[i];
    const fc=l.face[i];
    const sd=l.side[i];
    // thin everywhere, closing to nothing where the row narrows to a point
    // half its thickness here
    const half=@min(laminaThick*l.broad,0.4*w);
    // a point on the row's mid-surface, `u` (-1..1) across it
    const mid=struct{
      /// a point on the lamina's mid-surface at row `index`, `u` (-1..1) across it
      fn at(lm:Lamina,index:usize,u:f32)V3{
        return lm.spine[index]+lm.side[index]*m.splat3(lm.width[index]*u)+lm.face[index]*m.splat3(lm.dish[index]*m.pow(f32,@abs(u),lm.bow));
      }
    }.at;
    // which point round the section comes next
    var j:usize=0;
    for(faceU)|u|{
      // how far the vein lifts this point (only at the middle)
      const rise:f32=if(u!=0)0 else if(l.vein)|v|@min(v[i],0.3*w)else 0;
      pts[i][j]=mid(l,i,u)+fc*m.splat3(half*(1-edgeThin*u*u)+rise);
      tpl[i][j]=fc;
      cs[i][j]=if(rise>0)color.mix(l.col[i],pale,0.35)else l.col[i];
      j+=1;
    }
    // how thick the rim is, where the edges round over
    const rim=half*(1-edgeThin);
    for([_]f32{1,-1},0..)|e,ei|{
      // round the right edge face to back, then the left edge back to face
      for(0..bevel.len)|q|{
        // the angle this bevel step is turned off the midplane
        const a=if(ei==0)bevel[q]else bevel[bevel.len-1-q];
        // which way the rounded edge faces here
        const out=sd*m.splat3(e*@cos(a))+fc*m.splat3(@sin(a));
        pts[i][j]=mid(l,i,e)+out*m.splat3(rim);
        tpl[i][j]=out;
        cs[i][j]=l.col[i];
        j+=1;
      }
      if(ei==1)break;
      for(backU)|u|{
        pts[i][j]=mid(l,i,u)-fc*m.splat3(half*(1-edgeThin*u*u));
        tpl[i][j]=-fc;
        cs[i][j]=l.col[i];
        j+=1;
      }
    }
    assert(j==columns);
  }
  // normals from the shell itself, across its rows and round its section
  // each point's normal, from the shell around it
  var ns:[maxLamina][columns]V3=undefined;
  for(0..rows)|i|for(0..columns)|j|{
    // the directions across the rows and round the section
    const dk=pts[@min(i+1,rows-1)][j]-pts[if(i==0)0 else i-1][j];
    const du=pts[i][(j+1)%columns]-pts[i][(j+columns-1)%columns];
    // their cross: the shell's normal here
    var n=m.cross(du,dk);
    if(m.len(n)<1e-12)n=tpl[i][j];
    if(m.dot(n,tpl[i][j])<0)n=-n;
    ns[i][j]=m.norm(n);
  };
  // rows and points round the section kept at this level of detail (the
  // section closes on itself: its last kept point joins back to the first)
  // the rows kept, then the points round the section kept
  var kr:[maxLamina]usize=undefined;
  var kc:[columns+1]usize=undefined;
  // how many rows are kept, and how many points round the section
  const nr=stride(rows,b.step(),&kr);
  const nc=stride(columns+1,b.step(),&kc);
  for(0..nr-1)|ri|for(0..nc-1)|ci|{
    // the four corners of this quad: their rows, then their points round
    const r=[4]usize{kr[ri],kr[ri],kr[ri+1],kr[ri+1]};
    const c=[4]usize{kc[ci]%columns,kc[ci+1]%columns,kc[ci+1]%columns,kc[ci]%columns};
    for([2][3]usize{.{0,1,2},.{0,2,3}})|tri|{
      // one triangle's three points
      var p:[3]V3=undefined;
      // their summed normals, which way out it faces
      var n=m.v3(0,0,0);
      for(tri,0..)|v,q|{
        p[q]=pts[r[v]][c[v]];
        n+=ns[r[v]][c[v]];
      }
      // front faces wind counter-clockwise seen from outside
      // its winding, flipped to run counter-clockwise from outside
      const order=if(m.dot(m.cross(p[1]-p[0],p[2]-p[0]),n)<0)[3]usize{tri[0],tri[2],tri[1]}else tri;
      for(order)|v|try b.put(pts[r[v]][c[v]],ns[r[v]][c[v]],cs[r[v]][c[v]],l.t,m.ratio(r[v],rows-1),l.part);
    }
  };
}
